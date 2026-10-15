class_name RunState
extends RefCounted
## The run model shared by Off the Street, Fight Camp, co-op parties and The Bookie's Table.
## A run is ONE JSON-safe Dictionary (saved as-is by RunStore, sent as the co-op party ticket):
##   version, run_id, seed, seed_text, variant, mode (campaign|bookie), difficulty, dose,
##   coop_format (simultaneous|tag), custom, custom_reasons, seeded, created_at, elapsed,
##   content_hash, acts: [3 act maps], act (1..3), position (node id or ""), path: [node ids],
##   phase: map|fight|event|shop|rest|reward|victory|defeat, node: {active node session},
##   players: [player], claims: {node_key: {player_id: [claim ids]}}, log: [decisions],
##   flags: {run-wide: boss_mods, film_study, act_intro...}, stats, result.
## Player: id, name, profile_id, fighter, hp, scrip, hype_carry, supplements [{id, stacks}],
##   techniques, side_effects, consumables {id: n}, run_effects [{source, apply}],
##   next_fights [{source, remaining, apply, rules, arena}], triggers [...], meta {upgrade: level},
##   coupon, rerolls_free, cosmetics, stats, clout, connected, bot, out.
## Invariants (check()): position is a node of the current act reachable from the path; phase and
## node session agree; every referenced content id exists; hp within (0, max]; no negative Scrip.

const VERSION := 1
const PHASES := ["map", "fight", "event", "shop", "rest", "reward", "victory", "defeat"]


static func party_mode(state: Dictionary) -> String:
	if (state.get("players", []) as Array).size() <= 1:
		return "solo"
	return "tag" if str(state.get("coop_format", "simultaneous")) == "tag" else "coop"


static func new_player(catalog: CampaignCatalog, cfg: Dictionary, p: Dictionary, index: int) -> Dictionary:
	var pid := str(p.get("id", "p%d" % index))
	return {
		"id": pid, "name": str(p.get("name", "Player %d" % (index + 1))), "profile_id": str(p.get("profile_id", "")),
		"fighter": str(p.get("fighter", "")), "hp": 0.0, "scrip": int(catalog.rules.get("start_scrip", 60)),
		"hype_carry": 0.0, "supplements": [], "techniques": [], "side_effects": [], "consumables": {},
		"run_effects": [], "next_fights": [], "triggers": [],
		"meta": (p.get("meta", {}) as Dictionary).duplicate() if str(cfg.get("variant", "")) == "fight_camp" else {},
		"coupon": 0.0, "rerolls_free": 0, "cosmetics": [],
		"stats": {"fights": 0, "wins": 0, "kos": 0, "minion_kos": 0, "knockdowns_taken": 0, "damage_dealt": 0.0,
			"damage_taken": 0.0, "biggest_hit": 0.0, "taunts": 0, "downs": 0, "boss_no_hit": [], "scrip_earned": 0},
		"clout": 0, "connected": true, "bot": bool(p.get("bot", false)), "out": false,
	}


## Creates a brand-new run (map generated for all three acts).
## cfg: {seed, variant, difficulty, dose, mode, coop_format, custom, custom_reasons, seeded,
##       players: [{id, name, profile_id, fighter, meta, bot}], run_id, created_at}
static func create(catalog: CampaignCatalog, cfg: Dictionary) -> Dictionary:
	var seed_value := int(cfg.get("seed", 0))
	if seed_value == 0:
		seed_value = RunRng.fresh_seed()
	var players := []
	var plist: Array = cfg.get("players", [])
	for i in plist.size():
		players.append(new_player(catalog, cfg, plist[i], i))
	var fighters := []
	var elements := []
	var classes := []
	for p in players:
		fighters.append(p["fighter"])
		elements.append(catalog.fighter_element(str(p["fighter"])))
		classes.append(catalog.weight_class(str(p["fighter"])))
	var gen_cfg := {"seed": seed_value, "fighters": fighters, "elements": elements, "classes": classes,
		"variant": str(cfg.get("variant", "off_the_street")), "dose": int(cfg.get("dose", 0)),
		"difficulty": str(cfg.get("difficulty", "amateur")), "party_size": players.size()}
	var state := {
		"version": VERSION,
		"run_id": str(cfg.get("run_id", "run_%s_%d" % [RunRng.seed_to_text(seed_value).replace("-", ""), int(cfg.get("created_at", 0))])),
		"seed": seed_value, "seed_text": RunRng.seed_to_text(seed_value),
		"variant": str(cfg.get("variant", "off_the_street")), "mode": str(cfg.get("mode", "campaign")),
		"difficulty": str(cfg.get("difficulty", "amateur")), "dose": clampi(int(cfg.get("dose", 0)), 0, 10),
		"coop_format": str(cfg.get("coop_format", "simultaneous")),
		"custom": bool(cfg.get("custom", false)), "custom_reasons": (cfg.get("custom_reasons", []) as Array).duplicate(),
		"seeded": bool(cfg.get("seeded", false)), "created_at": int(cfg.get("created_at", 0)), "elapsed": 0.0,
		"content_hash": str(cfg.get("content_hash", "")),
		"acts": MapGenerator.generate(catalog, gen_cfg),
		"act": 1, "position": "", "path": [], "phase": "map", "node": {},
		"players": players, "claims": {}, "log": [], "flags": {"boss_mods": {}, "film_study": {}, "revealed": {}},
		"stats": {"fights": 0, "fights_won": 0, "nodes": 0, "kos": 0, "knockdowns_taken": 0, "biggest_hit": 0.0, "taunts": 0},
		"result": {},
		"gen_cfg": gen_cfg,
	}
	# starting resources from run modifiers (Fight Camp upgrades)
	for p in state["players"]:
		var rr := RunRules.compute(catalog, state, p)
		p["scrip"] = int(p["scrip"]) + int(rr.get("start_scrip_add", 0.0))
		p["rerolls_free"] = int(rr.get("free_rerolls", 0.0))
		var anti := int(rr.get("start_antidotes", 0.0))
		if anti > 0:
			p["consumables"]["sup_antidote_lozenge"] = anti
		p["hp"] = BuildApplier.max_hp(catalog, state, p)
	return state


static func player(state: Dictionary, pid: String) -> Dictionary:
	for p in state.get("players", []):
		if str(p.get("id", "")) == pid:
			return p
	return {}


static func player_ids(state: Dictionary) -> Array:
	var out := []
	for p in state.get("players", []):
		out.append(str(p["id"]))
	return out


static func act_map(state: Dictionary, act: int) -> Dictionary:
	var acts: Array = state.get("acts", [])
	if act < 1 or act > acts.size():
		return {}
	return acts[act - 1]


static func current_map(state: Dictionary) -> Dictionary:
	return act_map(state, int(state.get("act", 1)))


static func node(state: Dictionary, id: String) -> Dictionary:
	for m in state.get("acts", []):
		var n: Dictionary = m.get("nodes", {}).get(id, {})
		if not n.is_empty():
			return n
	return {}


## Nodes the party may enter next (row 1 at the start of an act, else the current node's edges).
static func available_nodes(state: Dictionary) -> Array:
	if str(state.get("phase", "")) != "map":
		return []
	var m := current_map(state)
	var pos := str(state.get("position", ""))
	if pos == "":
		return ActMap.row_ids(m, 1).duplicate()
	return ActMap.node(m, pos).get("edges", []).duplicate()


## How many rows ahead node types are visible (Scouting Report adds one; boss always shown).
static func reveal_rows(catalog: CampaignCatalog, state: Dictionary) -> int:
	var base := int(catalog.rules.get("map", {}).get("reveal_rows", 3))
	var best := 0
	for p in state.get("players", []):
		best = maxi(best, int(RunRules.compute(catalog, state, p).get("reveal_rows_add", 0.0)))
	return base + best


## Every content id referenced by the run (for resume validation / missing-mod detection).
static func referenced_content(state: Dictionary) -> Dictionary:
	var refs := {"supplements": {}, "techniques": {}, "events": {}, "encounters": {}, "meta_upgrades": {}, "creatures": {}}
	for m in state.get("acts", []):
		for id in m.get("nodes", {}):
			var n: Dictionary = m["nodes"][id]
			if str(n.get("encounter", "")) != "":
				refs["encounters"][str(n["encounter"])] = true
			if str(n.get("event", "")) != "":
				refs["events"][str(n["event"])] = true
			var h: Dictionary = n.get("hidden", {})
			if str(h.get("encounter", "")) != "":
				refs["encounters"][str(h["encounter"])] = true
			if str(h.get("event", "")) != "":
				refs["events"][str(h["event"])] = true
	for p in state.get("players", []):
		refs["creatures"][str(p.get("fighter", ""))] = true
		for s in p.get("supplements", []):
			refs["supplements"][str(s.get("id", ""))] = true
		for se in p.get("side_effects", []):
			refs["supplements"][str(se)] = true
		for c in p.get("consumables", {}):
			refs["supplements"][str(c)] = true
		for t in p.get("techniques", []):
			refs["techniques"][str(t)] = true
		for mid in p.get("meta", {}):
			refs["meta_upgrades"][str(mid)] = true
	var out := {}
	for k in refs:
		var ks: Array = refs[k].keys()
		ks.sort()
		out[k] = ks
	return out


## Validates a loaded state against the catalog. Returns human-readable problems (empty = OK).
## Missing content is reported per id so the player can re-enable the mod that provided it.
static func check(catalog: CampaignCatalog, state: Dictionary) -> Array:
	var out := []
	if int(state.get("version", 0)) != VERSION:
		out.append("unsupported run format version %s" % state.get("version", "?"))
		return out
	for k in ["seed", "acts", "act", "phase", "players", "claims", "path", "position"]:
		if not state.has(k):
			out.append("run save is missing '%s'" % k)
	if not out.is_empty():
		return out
	if not PHASES.has(str(state["phase"])):
		out.append("unknown run phase '%s'" % state["phase"])
	if (state["acts"] as Array).size() != 3:
		out.append("run must have 3 acts")
		return out
	var act := int(state["act"])
	if act < 1 or act > 3:
		out.append("act %d out of range" % act)
		return out
	var players: Array = state["players"]
	if players.is_empty() or players.size() > 4:
		out.append("run must have 1-4 players")
	var refs := referenced_content(state)
	for sid in refs["supplements"]:
		if catalog.item(str(sid)).is_empty():
			out.append("missing supplement '%s'" % sid)
	for tid in refs["techniques"]:
		if not catalog.techniques.has(str(tid)):
			out.append("missing technique '%s'" % tid)
	for eid in refs["events"]:
		if not catalog.events.has(str(eid)):
			out.append("missing event '%s'" % eid)
	for enc in refs["encounters"]:
		if not catalog.encounters.has(str(enc)):
			out.append("missing encounter '%s'" % enc)
	for mid in refs["meta_upgrades"]:
		if not catalog.meta.has(str(mid)):
			out.append("missing Fight Camp upgrade '%s'" % mid)
	for fid in refs["creatures"]:
		if not catalog.resolver.resolvable(str(fid)):
			out.append("missing fighter '%s'" % fid)
	for m in state["acts"]:
		var mp := ActMap.problems(m, catalog.rules)
		if not mp.is_empty():
			out.append("act %s map is invalid: %s" % [m.get("act", "?"), mp[0]])
	var pos := str(state["position"])
	var cm := current_map(state)
	if pos != "" and ActMap.node(cm, pos).is_empty():
		out.append("position '%s' is not on the act %d map" % [pos, act])
	var path: Array = state["path"]
	for i in range(1, path.size()):
		var prev := node(state, str(path[i - 1]))
		var cur := node(state, str(path[i]))
		if cur.is_empty() or prev.is_empty():
			out.append("path references unknown nodes")
			break
		if int(cur.get("act", 0)) == int(prev.get("act", 0)) and not (prev.get("edges", []) as Array).has(path[i]):
			out.append("path step %s -> %s is not a map edge" % [path[i - 1], path[i]])
			break
	if pos != "" and (path.is_empty() or str(path[path.size() - 1]) != pos):
		out.append("position does not match the end of the path")
	var phase := str(state["phase"])
	var sess: Dictionary = state.get("node", {})
	if phase in ["fight", "event", "shop", "rest", "reward"] and (sess.is_empty() or str(sess.get("id", "")) != pos):
		out.append("phase '%s' without a matching node session" % phase)
	if phase == "map" and not sess.is_empty():
		out.append("map phase with a stale node session")
	for p in players:
		if float(p.get("hp", 0.0)) <= 0.0 and phase != "defeat" and not bool(p.get("out", false)):
			out.append("player %s has no HP outside a defeat" % p.get("id", "?"))
		if int(p.get("scrip", 0)) < 0:
			out.append("player %s has negative Scrip" % p.get("id", "?"))
	return out
