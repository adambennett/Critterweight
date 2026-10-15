class_name MapGenerator
extends RefCounted
## Seeded fight-card generation (CAMPAIGN.md §2): three acts of 6 rows + boss, 3–4 lanes per row,
## branching/merging non-crossing edges, node types by row rules and weights, per-act guarantees,
## pacing per route (2–3 fights in rows 2–5 => 12–15 fights per run incl. bosses; never more than
## 3 fights in a row), then content assignment (encounters, events, mystery results, the hidden
## Treasure of acts 2–3). Same seed + same config + same content => identical card.
##
## Generation is attempt-based: each attempt draws a layout and types from its own sub-stream,
## repairs violations deterministically, and is accepted only when ActMap.problems() is empty.
## After MAX_ATTEMPTS a hand-built safe layout is used (always valid), so generation cannot fail
## or loop forever. cfg: {seed, fighters: [ids], elements: [ids], classes: [ids], variant, dose,
## party_size, stand_ins_ok}

const MAX_ATTEMPTS := 48
const MAX_REPAIRS := 60


static func generate(catalog: CampaignCatalog, cfg: Dictionary) -> Array:
	var acts := []
	var used_events := {}
	var used_encounters := {}
	for a in [1, 2, 3]:
		var m := generate_act(catalog, cfg, a, used_events, used_encounters)
		acts.append(m)
	return acts


static func generate_act(catalog: CampaignCatalog, cfg: Dictionary, act: int, used_events: Dictionary, used_encounters: Dictionary) -> Dictionary:
	var seed_value := int(cfg.get("seed", 1))
	for attempt in MAX_ATTEMPTS:
		var m := _layout(catalog, seed_value, act, attempt)
		var trng := RunRng.stream(seed_value, "a%d/types/%d" % [act, attempt])
		_assign_types(catalog, m, trng)
		if not _repair(catalog, m, trng):
			continue
		_assign_content(catalog, cfg, m, act, used_events, used_encounters)
		if ActMap.problems(m, catalog.rules).is_empty():
			m["attempt"] = attempt
			return m
	var safe := _safe_layout(catalog, act)
	_assign_content(catalog, cfg, safe, act, used_events, used_encounters)
	safe["attempt"] = -1
	return safe


# ---------------------------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------------------------

static func _node_id(act: int, row: int, lane: int) -> String:
	return "a%dr%dl%d" % [act, row, lane]


static func _new_node(act: int, row: int, lane: int, lanes: int) -> Dictionary:
	return {"id": _node_id(act, row, lane), "act": act, "row": row, "lane": lane,
		"x": 0.5 if lanes <= 1 else float(lane) / float(lanes - 1), "type": "", "edges": [],
		"encounter": "", "event": "", "hidden": {}, "treasure": false}


static func _layout(catalog: CampaignCatalog, seed_value: int, act: int, attempt: int) -> Dictionary:
	var mr: Dictionary = catalog.rules.get("map", {})
	var nrows := int(mr.get("rows", 6))
	var rng := RunRng.stream(seed_value, "a%d/layout/%d" % [act, attempt])
	var m := {"act": act, "rows": [], "nodes": {}, "boss": ""}
	for r in range(1, nrows + 1):
		var lanes := rng.range_i(int(mr.get("lanes_min", 3)), int(mr.get("lanes_max", 4)))
		var ids := []
		for l in lanes:
			var n := _new_node(act, r, l, lanes)
			m["nodes"][n["id"]] = n
			ids.append(n["id"])
		m["rows"].append(ids)
	var boss := _new_node(act, nrows + 1, 0, 1)
	boss["id"] = "a%dboss" % act
	boss["type"] = "boss"
	m["nodes"][boss["id"]] = boss
	m["rows"].append([boss["id"]])
	m["boss"] = boss["id"]
	for r in range(1, nrows):
		_connect(m, m["rows"][r - 1], m["rows"][r], rng)
	for id in m["rows"][nrows - 1]:
		m["nodes"][id]["edges"] = [boss["id"]]
	return m


## Non-crossing edges: node i of row A covers a contiguous interval [lo_i, hi_i] of row B
## (1–3 nodes), intervals are ordered, consecutive intervals touch (merge) or are adjacent, and
## together cover all of B.
static func _connect(m: Dictionary, a_ids: Array, b_ids: Array, rng: RunRng) -> void:
	var n := a_ids.size()
	var mb := b_ids.size()
	var lo := 0
	for i in n:
		var remaining := n - 1 - i
		var cands := []
		var weights := []
		for h in range(lo, mini(lo + 2, mb - 1) + 1):
			if remaining == 0:
				if h == mb - 1:
					cands.append(h)
					weights.append(1.0)
				continue
			# some next start (h or h+1) must still let the remaining nodes reach the end
			var ok := false
			for nxt in [h, h + 1]:
				if nxt <= mb - 1 and mb <= nxt + 3 * remaining:
					ok = true
			if ok:
				cands.append(h)
				weights.append([1.0, 0.7, 0.3][h - lo])
		if cands.is_empty():
			cands = [mini(lo + 2, mb - 1)]
			weights = [1.0]
		var hi := int(cands[maxi(0, rng.weighted_index(weights))])
		var edges := []
		for j in range(lo, hi + 1):
			edges.append(b_ids[j])
		m["nodes"][a_ids[i]]["edges"] = edges
		if remaining > 0:
			var opts := []
			for nxt2 in [hi + 1, hi]:
				if nxt2 <= mb - 1 and mb <= nxt2 + 3 * remaining:
					opts.append(nxt2)
			if opts.is_empty():
				lo = mini(hi + 1, mb - 1)
			elif opts.size() == 1:
				lo = int(opts[0])
			else:
				lo = int(opts[0]) if rng.chance(0.7) else int(opts[1])


static func _safe_layout(catalog: CampaignCatalog, act: int) -> Dictionary:
	## 3 straight lanes with fixed, valid types — the generator's last resort.
	var mr: Dictionary = catalog.rules.get("map", {})
	var nrows := int(mr.get("rows", 6))
	var pattern := [
		["fight", "fight", "fight"],
		["event", "fight", "shop"],
		["fight", "event", "fight"],
		["elite", "rest", "event"],
		["event", "fight", "fight"],
		["rest", "shop", "rest"],
	]
	var m := {"act": act, "rows": [], "nodes": {}, "boss": ""}
	for r in range(1, nrows + 1):
		var ids := []
		for l in 3:
			var n := _new_node(act, r, l, 3)
			n["type"] = pattern[mini(r - 1, pattern.size() - 1)][l]
			m["nodes"][n["id"]] = n
			ids.append(n["id"])
		m["rows"].append(ids)
	var boss := _new_node(act, nrows + 1, 0, 1)
	boss["id"] = "a%dboss" % act
	boss["type"] = "boss"
	m["nodes"][boss["id"]] = boss
	m["rows"].append([boss["id"]])
	m["boss"] = boss["id"]
	for r in range(1, nrows):
		for l in 3:
			m["nodes"][m["rows"][r - 1][l]]["edges"] = [m["rows"][r][l]]
	for id in m["rows"][nrows - 1]:
		m["nodes"][id]["edges"] = [boss["id"]]
	if CampaignCatalog.has_num(mr.get("treasure_acts", [2, 3]), act):
		var mid: String = m["rows"][1][0]
		m["nodes"][mid]["type"] = "mystery"
		m["nodes"][mid]["treasure"] = true
	return m


# ---------------------------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------------------------

static func _assign_types(catalog: CampaignCatalog, m: Dictionary, rng: RunRng) -> void:
	var mr: Dictionary = catalog.rules.get("map", {})
	var nrows := ActMap.row_count(m) - 1
	var w: Dictionary = mr.get("row_weights", {})
	var elite_rows: Array = mr.get("elite_rows", [3, 4, 5])
	var types := ["fight", "event", "mystery", "shop", "rest", "elite"]
	for r in range(1, nrows + 1):
		var ids: Array = m["rows"][r - 1]
		for i in ids.size():
			var n: Dictionary = m["nodes"][ids[i]]
			if r == 1:
				n["type"] = "fight"
			elif r == nrows:
				n["type"] = "rest" if rng.chance(0.5) else "shop"
			else:
				var ws := []
				for t in types:
					var wt := float(w.get(t, 0.0))
					if t == "elite" and not CampaignCatalog.has_num(elite_rows, r):
						wt = 0.0
					ws.append(wt)
				n["type"] = types[maxi(0, rng.weighted_index(ws))]
		if r == nrows and ids.size() >= 2:
			var has_rest := false
			var has_shop := false
			for id in ids:
				has_rest = has_rest or m["nodes"][id]["type"] == "rest"
				has_shop = has_shop or m["nodes"][id]["type"] == "shop"
			if not has_rest:
				m["nodes"][ids[rng.range_i(0, ids.size() - 1)]]["type"] = "rest"
			if not has_shop:
				for id2 in rng.shuffled(ids):
					if m["nodes"][id2]["type"] == "rest" and _count_in(m, ids, "rest") > 1:
						m["nodes"][id2]["type"] = "shop"
						break


static func _count_in(m: Dictionary, ids: Array, t: String) -> int:
	var n := 0
	for id in ids:
		if m["nodes"][id]["type"] == t:
			n += 1
	return n


static func _mid_rows(m: Dictionary) -> Array:
	var out := []
	var nrows := ActMap.row_count(m) - 1
	for r in range(2, nrows):
		for id in m["rows"][r - 1]:
			out.append(id)
	return out


## Deterministic repair of type rules. Returns false if it could not converge.
static func _repair(catalog: CampaignCatalog, m: Dictionary, rng: RunRng) -> bool:
	var mr: Dictionary = catalog.rules.get("map", {})
	var act := int(m["act"])
	var elite_rows: Array = mr.get("elite_rows", [3, 4, 5])
	var max_streak := int(mr.get("max_consecutive_fights", 3))
	for it in MAX_REPAIRS:
		var nodes: Dictionary = m["nodes"]
		var mids := _mid_rows(m)
		# elite caps and adjacency
		var elites := []
		for id in mids:
			if nodes[id]["type"] == "elite":
				elites.append(id)
		if elites.size() > int(mr.get("max_elites", 2)):
			nodes[elites[rng.range_i(0, elites.size() - 1)]]["type"] = "fight"
			continue
		var adj := ""
		for id in elites:
			for e in nodes[id]["edges"]:
				if nodes[e]["type"] == "elite":
					adj = e
		if adj != "":
			nodes[adj]["type"] = "fight"
			continue
		if elites.is_empty():
			var cands := []
			for id in mids:
				if nodes[id]["type"] == "fight" and CampaignCatalog.has_num(elite_rows, int(nodes[id]["row"])) and not _touches_type(m, id, "elite"):
					cands.append(id)
			if cands.is_empty():
				for id in mids:
					if CampaignCatalog.has_num(elite_rows, int(nodes[id]["row"])) and not _touches_type(m, id, "elite"):
						cands.append(id)
			if cands.is_empty():
				return false
			nodes[cands[rng.range_i(0, cands.size() - 1)]]["type"] = "elite"
			continue
		# mystery caps (acts with a hidden treasure need at least one mystery)
		var myst := []
		for id in mids:
			if nodes[id]["type"] == "mystery":
				myst.append(id)
		if myst.size() > int(mr.get("max_mystery", 2)):
			nodes[myst[rng.range_i(0, myst.size() - 1)]]["type"] = "event"
			continue
		if myst.is_empty() and CampaignCatalog.has_num(mr.get("treasure_acts", [2, 3]), act):
			var c2 := []
			for id in mids:
				if nodes[id]["type"] in ["event", "shop", "rest"]:
					c2.append(id)
			if c2.is_empty():
				c2 = mids.duplicate()
			nodes[c2[rng.range_i(0, c2.size() - 1)]]["type"] = "mystery"
			continue
		if ActMap.count_type(m, "event") < 1:
			var c3 := []
			for id in mids:
				if nodes[id]["type"] in ["shop", "rest", "mystery"]:
					c3.append(id)
			if c3.is_empty():
				for id in mids:
					if nodes[id]["type"] == "fight":
						c3.append(id)
			if c3.is_empty():
				return false
			nodes[c3[rng.range_i(0, c3.size() - 1)]]["type"] = "event"
			continue
		# pacing per route
		var fixed := false
		for p in ActMap.all_paths(m):
			var k := ActMap.path_fights(m, p)
			var on_path := []
			for id in p:
				var r := int(nodes[id]["row"])
				if r >= 2 and r <= 5:
					on_path.append(id)
			if k < 2:
				var c4 := []
				for id in on_path:
					if not nodes[id]["type"] in ActMap.FIGHTLIKE:
						c4.append(id)
				var pick: String = c4[rng.range_i(0, c4.size() - 1)]
				nodes[pick]["type"] = "fight"
				fixed = true
				break
			if k > 3:
				var c5 := []
				for id in on_path:
					if nodes[id]["type"] == "fight":
						c5.append(id)
				if c5.is_empty():
					for id in on_path:
						if nodes[id]["type"] == "elite":
							c5.append(id)
				var pick2: String = c5[rng.range_i(0, c5.size() - 1)]
				nodes[pick2]["type"] = ["event", "rest", "shop"][rng.range_i(0, 2)]
				fixed = true
				break
			var st := ActMap.longest_fight_streak(m, p)
			if int(st[0]) > max_streak:
				# break the streak at its middle (never row 1)
				var end_i := int(st[1])
				var start_i := end_i - int(st[0]) + 1
				var mid := clampi(int((start_i + end_i + 1) / 2.0), 1, p.size() - 1)
				if int(nodes[p[mid]]["row"]) < 2:
					mid += 1
				nodes[p[mid]]["type"] = "event"
				fixed = true
				break
		if fixed:
			continue
		return true
	return false


static func _touches_type(m: Dictionary, id: String, t: String) -> bool:
	var nodes: Dictionary = m["nodes"]
	for e in nodes[id]["edges"]:
		if nodes[e]["type"] == t:
			return true
	for other in nodes:
		if nodes[other]["edges"].has(id) and nodes[other]["type"] == t:
			return true
	return false


# ---------------------------------------------------------------------------------------------
# Content
# ---------------------------------------------------------------------------------------------

## Event eligibility for a party at generation time (act, fighter/element/weight-class filters).
static func event_eligible(catalog: CampaignCatalog, cfg: Dictionary, act: int, eid: String) -> bool:
	if not catalog.event_valid(eid):
		return false
	var e: Dictionary = catalog.events[eid]
	var req: Dictionary = e.get("requires", {})
	if req.has("act") and not CampaignCatalog.has_num(req["act"], act):
		return false
	if req.has("fighters"):
		var any := false
		for f in cfg.get("fighters", []):
			if (req["fighters"] as Array).has(f):
				any = true
		if not any:
			return false
	if req.has("party_element"):
		var any2 := false
		for el in cfg.get("elements", []):
			if str(el) == str(req["party_element"]):
				any2 = true
		if not any2:
			return false
	if req.has("weight_class"):
		var any3 := false
		for c in cfg.get("classes", []):
			if (req["weight_class"] as Array).has(c):
				any3 = true
		if not any3:
			return false
	if req.has("variant") and str(req["variant"]) != str(cfg.get("variant", "")):
		return false
	if req.has("coop") and bool(req["coop"]) != (int(cfg.get("party_size", 1)) > 1):
		return false
	# events whose only choices are fights need playable encounters
	for c2 in e.get("choices", []):
		for o in c2.get("outcomes", []):
			for eff in o.get("effects", []):
				if str(eff.get("op", "")) == "fight" and not encounter_playable(catalog, str(eff.get("encounter", ""))):
					return false
	return true


## True when every creature an encounter needs can be resolved (real content or stand-ins).
static func encounter_playable(catalog: CampaignCatalog, enc_id: String) -> bool:
	if not catalog.encounter_valid(enc_id):
		return false
	for en in catalog.encounters[enc_id].get("enemies", []):
		if en.has("minion") and not catalog.resolver.resolvable(str(en["minion"])):
			return false
		if en.has("boss_fight"):
			var bf: Dictionary = catalog.boss_fights.get(str(en["boss_fight"]), {})
			if bf.is_empty() or not catalog.resolver.resolvable(str(bf.get("creature", ""))):
				return false
		if en.has("fighter"):
			var f := str(en["fighter"])
			if f in ["random", "mirror"]:
				var pool: Array = en.get("pool", catalog.roster())
				var any := false
				for pf in pool:
					if catalog.resolver.resolvable(str(pf)):
						any = true
				if not any and f == "random":
					return false
			elif not catalog.resolver.resolvable(f):
				return false
	return true


static func _assign_content(catalog: CampaignCatalog, cfg: Dictionary, m: Dictionary, act: int, used_events: Dictionary, used_encounters: Dictionary) -> void:
	var seed_value := int(cfg.get("seed", 1))
	var rng := RunRng.stream(seed_value, "a%d/content" % act)
	var nodes: Dictionary = m["nodes"]
	var normals := []
	for id in catalog.encounters_for(act, "normal"):
		if encounter_playable(catalog, id):
			normals.append(id)
	var elites := []
	var forced_elite := ""
	if act == 3:
		var rr := RunRules.compute(catalog, {"difficulty": cfg.get("difficulty", "amateur"), "dose": cfg.get("dose", 0)})
		forced_elite = str(rr.get("act3_elite", ""))
	for id in catalog.encounters_for(act, "elite"):
		if encounter_playable(catalog, id) and (forced_elite == "" or id == forced_elite):
			elites.append(id)
	if elites.is_empty():
		for id in catalog.encounters_for(act, "elite"):
			if encounter_playable(catalog, id):
				elites.append(id)
	var events := []
	for id in CampaignCatalog._sorted_keys(catalog.events):
		if not used_events.has(id) and event_eligible(catalog, cfg, act, id):
			events.append(id)
	events = rng.shuffled(events)
	var normal_bag := rng.shuffled(normals)
	var elite_bag := rng.shuffled(elites)
	var ordered := []
	for row in m["rows"]:
		for id in row:
			ordered.append(id)
	for id in ordered:
		var n: Dictionary = nodes[id]
		match str(n["type"]):
			"fight":
				n["encounter"] = _draw(normal_bag, normals, rng, _neighbour_encounters(m, id))
			"elite":
				n["encounter"] = _draw(elite_bag, elites, rng, _neighbour_encounters(m, id))
			"event":
				n["event"] = _draw_event(events, used_events, catalog, cfg, act, rng)
			"boss":
				n["encounter"] = str(catalog.acts.get(act, {}).get("boss", ""))
	# mystery results and the hidden treasure (acts 2-3)
	var mysteries := []
	for id in ordered:
		if nodes[id]["type"] == "mystery":
			mysteries.append(id)
	var treasure_id := ""
	if CampaignCatalog.has_num(catalog.rules.get("map", {}).get("treasure_acts", [2, 3]), act) and not mysteries.is_empty():
		treasure_id = mysteries[rng.range_i(0, mysteries.size() - 1)]
	var odds: Dictionary = catalog.rules.get("map", {}).get("mystery_odds", {})
	for id in mysteries:
		var n2: Dictionary = nodes[id]
		var mrng := RunRng.stream(seed_value, "a%d/mystery/%s" % [act, id])
		var h := {}
		if id == treasure_id:
			h["type"] = "treasure"
			n2["treasure"] = true
		else:
			n2["treasure"] = false
			var kinds := ["fight", "event", "shop", "treasure"]
			var ws := []
			for k in kinds:
				ws.append(float(odds.get(k, 0.0)))
			h["type"] = kinds[maxi(0, mrng.weighted_index(ws))]
		match str(h["type"]):
			"fight":
				h["encounter"] = _draw(normal_bag, normals, mrng, [])
			"event":
				h["event"] = _draw_event(events, used_events, catalog, cfg, act, mrng)
				if str(h["event"]) == "":
					h = {"type": "shop"}
		n2["hidden"] = h


static func _neighbour_encounters(m: Dictionary, id: String) -> Array:
	var out := []
	var nodes: Dictionary = m["nodes"]
	for e in nodes[id]["edges"]:
		if str(nodes[e].get("encounter", "")) != "":
			out.append(nodes[e]["encounter"])
	for other in nodes:
		if nodes[other]["edges"].has(id) and str(nodes[other].get("encounter", "")) != "":
			out.append(nodes[other]["encounter"])
	return out


## Takes the next encounter from a shuffled bag (refilled when empty), avoiding repeats on
## directly connected nodes when possible.
static func _draw(bag: Array, pool: Array, rng: RunRng, avoid: Array) -> String:
	if pool.is_empty():
		return ""
	if bag.is_empty():
		bag.append_array(rng.shuffled(pool))
	for i in bag.size():
		if not avoid.has(bag[i]):
			var v: String = bag[i]
			bag.remove_at(i)
			return v
	var v2: String = bag.pop_front()
	return v2


static func _draw_event(events: Array, used: Dictionary, catalog: CampaignCatalog, cfg: Dictionary, act: int, rng: RunRng) -> String:
	if events.is_empty():
		# all eligible events used this run: allow repeats rather than an empty node
		var again := []
		for id in CampaignCatalog._sorted_keys(catalog.events):
			if event_eligible(catalog, cfg, act, id):
				again.append(id)
		if again.is_empty():
			return ""
		events.append_array(rng.shuffled(again))
	var e: String = events.pop_front()
	used[e] = true
	return e
