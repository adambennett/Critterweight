class_name RunController
extends RefCounted
## The run state machine shared by Off the Street, Fight Camp, co-op parties and The Bookie's
## Table. Every transition validates the current phase/node/player, mutates `state`, appends a
## decision to state.log, records claims, emits `changed` and calls `autosave` — so a run can be
## suspended at any node boundary, resumed after a crash, replayed from its seed + log, and
## shipped to co-op members as a party ticket.
##
## Phases: map -> (fight | event | shop | rest | reward) -> map ... boss -> next act ... ->
##         victory | defeat.
## Duplicate protection: every grant is keyed by (node id, player id, claim id) in state.claims;
## a second claim (double click, resent network message, replay after crash) is rejected.
## Fights that were in progress when the app quit are re-run from their start (their plan is
## stored in the node session; nothing from an unfinished fight is ever applied).

signal changed(reason: String)

var catalog: CampaignCatalog
var state: Dictionary = {}
var last_error := ""
var autosave: Callable = Callable()   ## called with (state) after every committed transition
var replaying := false
var last_texts: Array = []            ## result lines of the latest event choice (UI only, not saved)


static func start_run(cat: CampaignCatalog, cfg: Dictionary) -> RunController:
	var c := RunController.new()
	c.catalog = cat
	c.state = RunState.create(cat, cfg)
	c.state["start_cfg"] = _cfg_snapshot(cfg, int(c.state["seed"]))
	c._log("start", "", {})
	c._commit("start")
	return c


static func from_state(cat: CampaignCatalog, st: Dictionary) -> RunController:
	var c := RunController.new()
	c.catalog = cat
	c.state = st
	return c


static func _cfg_snapshot(cfg: Dictionary, seed_value: int) -> Dictionary:
	var c := {}
	for k in ["variant", "difficulty", "dose", "mode", "coop_format", "custom", "custom_reasons", "seeded", "created_at", "run_id", "content_hash"]:
		if cfg.has(k):
			c[k] = cfg[k]
	c["seed"] = seed_value
	var ps := []
	for p in cfg.get("players", []):
		ps.append((p as Dictionary).duplicate(true))
	c["players"] = ps
	return c


## Rebuilds a run from its starting config and decision log (determinism check, party tickets).
static func replay(cat: CampaignCatalog, start_cfg: Dictionary, log_entries: Array) -> RunController:
	var c := RunController.new()
	c.catalog = cat
	c.replaying = true
	c.state = RunState.create(cat, start_cfg)
	c.state["start_cfg"] = start_cfg.duplicate(true)
	c._log("start", "", {})
	for e in log_entries:
		var k := str(e.get("k", ""))
		var pid := str(e.get("p", ""))
		var d: Dictionary = e.get("d", {})
		match k:
			"choose":
				c.choose_node(str(d.get("node", "")), pid)
			"fight":
				c.complete_fight({"campaign": d.get("result", {})})
			"claim":
				c.claim(pid, str(d.get("rid", "")), str(d.get("choice", "")))
			"reroll":
				c.reroll(pid, str(d.get("rid", "")))
			"event":
				c.choose_event(pid, str(d.get("choice", "")))
			"buy":
				c.shop_buy(pid, str(d.get("slot", "")))
			"service":
				c.shop_service(pid, str(d.get("arg", "")))
			"sell":
				c.shop_sell(pid, str(d.get("item", "")))
			"leave":
				c.shop_leave(pid)
			"rest":
				c.rest_choose(pid, str(d.get("option", "")))
			"consume":
				c.use_consumable(pid, str(d.get("item", "")))
			"abandon":
				c.abandon()
	c.replaying = false
	return c


# =============================================================================================
# Queries
# =============================================================================================

func phase() -> String:
	return str(state.get("phase", "map"))


func is_over() -> bool:
	return phase() in ["victory", "defeat"]


func players() -> Array:
	return state.get("players", [])


func player(pid: String) -> Dictionary:
	return RunState.player(state, pid)


func max_hp(p: Dictionary) -> float:
	return BuildApplier.max_hp(catalog, state, p)


func rules_for(pid: String) -> Dictionary:
	return RunRules.compute(catalog, state, player(pid))


func session() -> Dictionary:
	return state.get("node", {})


## Captain (CAMPAIGN.md §11): host in Act 1, then rotates each act; in 4-player parties the
## lowest-HP player at the act boundary captains (stored when the act starts).
func captain() -> String:
	var ids := RunState.player_ids(state)
	if ids.is_empty():
		return ""
	var fixed := str(state.get("flags", {}).get("captain", ""))
	if fixed != "" and ids.has(fixed):
		return fixed
	var act := int(state.get("act", 1))
	return str(ids[(act - 1) % ids.size()])


func available_nodes() -> Array:
	return RunState.available_nodes(state)


## Node type as shown on the map (mystery/treasure stay "?" until entered; far rows unknown).
func visible_type(node_id: String) -> String:
	var n := RunState.node(state, node_id)
	if n.is_empty():
		return "unknown"
	var t := str(n.get("type", ""))
	if t == "boss":
		return t
	var revealed: Dictionary = state.get("flags", {}).get("revealed", {})
	if revealed.has(node_id):
		return str(revealed[node_id])
	if int(n.get("act", 1)) != int(state.get("act", 1)):
		return "unknown"
	var cur_row := 0
	var pos := str(state.get("position", ""))
	if pos != "":
		cur_row = int(RunState.node(state, pos).get("row", 0))
	if int(n.get("row", 0)) > cur_row + RunState.reveal_rows(catalog, state):
		return "unknown"
	return t


## Encounter/event name of a node if the party knows it (entered, or Film study for elites/boss).
func node_label(node_id: String) -> String:
	var n := RunState.node(state, node_id)
	var t := visible_type(node_id)
	var film: Dictionary = state.get("flags", {}).get("film_study", {})
	var known := (state.get("path", []) as Array).has(node_id) or (t in ["elite", "boss"] and bool(film.get(str(n.get("act", 0)), false)))
	if not known:
		return ""
	var enc := str(n.get("encounter", ""))
	if enc != "":
		return str(catalog.encounters.get(enc, {}).get("name", enc))
	var ev := str(n.get("event", ""))
	if ev != "":
		return str(catalog.events.get(ev, {}).get("title", ev))
	return ""


# =============================================================================================
# Map
# =============================================================================================

func choose_node(node_id: String, by := "") -> bool:
	if phase() != "map":
		return _fail("cannot choose a route during '%s'" % phase())
	if not available_nodes().has(node_id):
		return _fail("node %s is not reachable from here" % node_id)
	var n := RunState.node(state, node_id)
	state["position"] = node_id
	(state["path"] as Array).append(node_id)
	state["stats"]["nodes"] = int(state["stats"].get("nodes", 0)) + 1
	_log("choose", by, {"node": node_id})
	var t := str(n.get("type", "fight"))
	var enc := str(n.get("encounter", ""))
	var evt := str(n.get("event", ""))
	if t == "mystery":
		var h: Dictionary = n.get("hidden", {})
		t = str(h.get("type", "event"))
		enc = str(h.get("encounter", ""))
		evt = str(h.get("event", ""))
		state["flags"]["revealed"][node_id] = t
	var sess := {"id": node_id, "type": t, "pending": {}, "ready": {}, "fights": 0}
	for pid in RunState.player_ids(state):
		sess["pending"][pid] = []
	state["node"] = sess
	match t:
		"fight", "elite", "boss":
			var tier := "normal" if t == "fight" else t
			sess["fight"] = {"encounter": enc, "tier": tier, "mini": false, "spar": false,
				"plan": EncounterBuilder.plan(catalog, state, enc, {"node_id": node_id, "kind": tier})}
			state["phase"] = "fight"
		"event":
			sess["event"] = EventRunner.begin(self, node_id, evt)
			state["phase"] = "event"
		"shop":
			var shops := {}
			for pid2 in RunState.player_ids(state):
				shops[pid2] = CampaignShop.stock(self, pid2)
				player(pid2)["coupon"] = 0.0
			sess["shop"] = shops
			state["phase"] = "shop"
		"rest":
			var rests := {}
			for pid3 in RunState.player_ids(state):
				rests[pid3] = {"done": false, "choice": ""}
			sess["rest"] = rests
			state["phase"] = "rest"
		"treasure":
			var tr: Dictionary = catalog.rules.get("rewards", {}).get("treasure", {})
			for pid4 in RunState.player_ids(state):
				add_pending(pid4, "supplement", {"n": int(tr.get("options", 3)), "source": "treasure",
					"min_rarity": str(tr.get("min_rarity", "black_market")), "scrip_alt": int(tr.get("scrip_alternative", 150))})
			state["phase"] = "reward"
		_:
			state["phase"] = "reward"
	_commit("enter")
	_try_complete_node()
	return true


# =============================================================================================
# Fights
# =============================================================================================

func current_plan() -> Dictionary:
	return session().get("fight", {}).get("plan", {})


## MatchSim/App config for the pending fight (EncounterBuilder.build_match).
func match_config(opts := {}) -> Dictionary:
	if phase() != "fight":
		return {"config": {}, "errors": PackedStringArray(["no fight pending"]), "warnings": [], "roles": []}
	var f: Dictionary = session().get("fight", {})
	var o := opts.duplicate()
	if bool(f.get("spar", false)):
		o["spar_player"] = str(f.get("by", ""))
	return EncounterBuilder.build_match(catalog, state, f.get("plan", {}), o)


## Applies a finished fight. `result` = MatchSim result (needs result["campaign"]).
func complete_fight(result: Dictionary) -> bool:
	if phase() != "fight":
		return _fail("no fight in progress")
	var sess := session()
	var f: Dictionary = sess.get("fight", {})
	var fkey := "_fight%d" % int(sess.get("fights", 0))
	if _claimed(str(sess["id"]), "_run", fkey):
		return _fail("fight result already applied")
	_record_claim(str(sess["id"]), "_run", fkey)
	sess["fights"] = int(sess.get("fights", 0)) + 1
	var camp: Dictionary = result.get("campaign", {})
	_log("fight", "", {"result": _compact_result(camp)})
	var won := bool(camp.get("won", false))
	var spar := bool(f.get("spar", false))
	var tier := str(f.get("tier", "normal"))
	var pres: Dictionary = camp.get("players", {})
	state["stats"]["fights"] = int(state["stats"].get("fights", 0)) + 1
	if won:
		state["stats"]["fights_won"] = int(state["stats"].get("fights_won", 0)) + 1
	var plan_arena := str(f.get("plan", {}).get("arena_key", ""))
	var reward_mults := {}
	for p0 in players():
		reward_mults[str(p0["id"])] = float(BuildApplier.next_rules(p0, plan_arena).get("reward_mult", 1.0))
	for p in players():
		var pid := str(p["id"])
		var r: Dictionary = pres.get(pid, {})
		var st: Dictionary = p["stats"]
		st["fights"] = int(st.get("fights", 0)) + 1
		if r.is_empty():
			continue
		st["kos"] = int(st.get("kos", 0)) + int(r.get("kos", 0))
		st["minion_kos"] = int(st.get("minion_kos", 0)) + int(r.get("minion_kos", 0))
		st["knockdowns_taken"] = int(st.get("knockdowns_taken", 0)) + int(r.get("knockdowns", 0))
		st["damage_dealt"] = float(st.get("damage_dealt", 0.0)) + float(r.get("damage_dealt", 0.0))
		st["damage_taken"] = float(st.get("damage_taken", 0.0)) + float(r.get("damage_taken", 0.0))
		st["biggest_hit"] = maxf(float(st.get("biggest_hit", 0.0)), float(r.get("biggest_hit", 0.0)))
		st["taunts"] = int(st.get("taunts", 0)) + int(r.get("taunts", 0))
		st["downs"] = int(st.get("downs", 0)) + int(r.get("downs", 0))
		state["stats"]["kos"] = int(state["stats"].get("kos", 0)) + int(r.get("kos", 0))
		state["stats"]["biggest_hit"] = maxf(float(state["stats"].get("biggest_hit", 0.0)), float(r.get("biggest_hit", 0.0)))
		state["stats"]["taunts"] = int(state["stats"].get("taunts", 0)) + int(r.get("taunts", 0))
		state["stats"]["knockdowns_taken"] = int(state["stats"].get("knockdowns_taken", 0)) + int(r.get("knockdowns", 0))
		if spar:
			continue
		# HP carries; Out players return at 50% after a won fight
		var mh := max_hp(p)
		if won:
			if bool(r.get("out", false)) or float(r.get("hp", 0.0)) <= 0.0:
				p["hp"] = maxf(1.0, mh * float(catalog.rules.get("coop", {}).get("out_return_frac", 0.5)))
			else:
				p["hp"] = clampf(float(r.get("hp", mh)), 1.0, mh)
		else:
			p["hp"] = maxf(0.0, float(r.get("hp", 0.0)))
		var hc: Dictionary = catalog.rules.get("hype_carry", {})
		p["hype_carry"] = minf(float(hc.get("cap", 50.0)), float(r.get("hype", 0.0)) * float(hc.get("fraction", 0.5)))
		if tier == "boss" and won and not bool(r.get("hit_by_boss", true)):
			(st["boss_no_hit"] as Array).append(str(f.get("encounter", "")))
		# next-fight effects are consumed by this fight (arena-bound ones only in that arena)
		var keep := []
		for nf in p.get("next_fights", []):
			if not BuildApplier.next_fight_applies(nf, plan_arena):
				keep.append(nf)
				continue
			nf["remaining"] = int(nf.get("remaining", 1)) - 1
			if int(nf["remaining"]) > 0:
				keep.append(nf)
		p["next_fights"] = keep
		# bets / triggers on this fight
		var trig_keep := []
		for tg in p.get("triggers", []):
			var cond: Dictionary = tg.get("if", {})
			var ok := true
			if cond.has("won") and bool(cond["won"]) != won:
				ok = false
			if cond.has("max_knockdowns") and int(r.get("knockdowns", 0)) > int(cond["max_knockdowns"]):
				ok = false
			if cond.has("min_knockdowns") and int(r.get("knockdowns", 0)) < int(cond["min_knockdowns"]):
				ok = false
			for eff in (tg.get("win", []) if ok else tg.get("lose", [])):
				EventRunner.apply_effect(self, pid, eff, {"source": str(tg.get("source", "bet")), "key": "bet"})
		p["triggers"] = trig_keep
		# Blood Money
		var rr := rules_for(pid)
		var bm := int(rr.get("blood_money_ko", 0.0)) * (int(r.get("kos", 0)) - int(r.get("minion_kos", 0)))
		bm += int(rr.get("blood_money_knockdown", 0.0)) * int(r.get("knockdowns", 0))
		if bm != 0:
			p["scrip"] = maxi(0, int(p["scrip"]) + bm)
	state["elapsed"] = float(state.get("elapsed", 0.0)) + float(camp.get("time", 0.0))
	if spar:
		var effs: Array = f.get("on_win", []) if won else f.get("on_loss", [])
		var by := str(f.get("by", ""))
		for eff2 in effs:
			EventRunner.apply_effect(self, by, eff2, {"source": "spar", "key": "spar"})
		state["phase"] = "reward"
		_commit("fight")
		_try_complete_node()
		return true
	if not won:
		_end_run(false)
		return true
	# post-fight sustain
	for p2 in players():
		var rr2 := rules_for(str(p2["id"]))
		var heal := float(rr2.get("post_fight_heal", 0.0))
		if heal > 0.0:
			p2["hp"] = minf(max_hp(p2), float(p2["hp"]) + max_hp(p2) * heal)
	if bool(f.get("mini", false)):
		var by2 := str(f.get("by", ""))
		var targets: Array = RunState.player_ids(state) if bool(session().get("event", {}).get("group", false)) else [by2]
		for t in targets:
			for eff3 in f.get("on_win", []):
				EventRunner.apply_effect(self, str(t), eff3, {"source": "event_fight", "key": "event_fight"})
	else:
		_grant_fight_rewards(tier, reward_mults)
	state["phase"] = "reward"
	_commit("fight")
	_try_complete_node()
	return true


func _compact_result(camp: Dictionary) -> Dictionary:
	var out := {"won": bool(camp.get("won", false)), "time": snappedf(float(camp.get("time", 0.0)), 0.01), "players": {}}
	for pid in camp.get("players", {}):
		var r: Dictionary = camp["players"][pid]
		var c := {}
		for k in ["hp", "hype", "out", "knockdowns", "kos", "minion_kos", "damage_dealt", "damage_taken", "biggest_hit", "taunts", "downs", "hit_by_boss"]:
			if r.has(k):
				c[k] = r[k]
		out["players"][pid] = c
	if camp.has("boss"):
		out["boss"] = camp["boss"]
	return out


func _grant_fight_rewards(tier: String, reward_mults: Dictionary = {}) -> void:
	var rw: Dictionary = catalog.rules.get("rewards", {}).get("fight" if tier == "normal" else tier, {})
	var node_row := int(RunState.node(state, str(state["position"])).get("row", 0))
	for p in players():
		var pid := str(p["id"])
		var rr := rules_for(pid)
		var scrip := int(round(RewardRoller.scrip_roll(state, "node/%s/%s/scrip" % [state["position"], pid], rw.get("scrip", [40, 70]))
			* float(rr.get("scrip_mult", 1.0)) * float(reward_mults.get(pid, 1.0))))
		p["scrip"] = int(p["scrip"]) + scrip
		p["stats"]["scrip_earned"] = int(p["stats"].get("scrip_earned", 0)) + scrip
		p["clout"] = int(p.get("clout", 0)) + int(rw.get("clout", 0))
		var n := int(rw.get("options", 3))
		if tier == "elite":
			n += int(rr.get("elite_extra_options", 0.0))
		add_pending(pid, "supplement", {"n": n, "source": tier if tier != "normal" else "fight", "min_rarity": str(rw.get("min_rarity", "")),
			"banned_chance": float(rw.get("banned_chance", 0.0))})
		var techs := int(rw.get("techniques", 0))
		if techs == 0 and tier == "normal" and node_row == 1 and float(rr.get("technique_pick_row1", 0.0)) > 0.0:
			techs = 2
		if techs > 0:
			add_pending(pid, "technique", {"n": techs, "source": tier})


## Starts a fight from an event outcome (mini-encounter or spar) inside the current node.
func begin_event_fight(pid: String, encounter: String, spar: bool, on_win: Array, on_loss: Array) -> void:
	var sess := session()
	sess["fight"] = {"encounter": encounter, "tier": "event", "mini": true, "spar": spar, "by": pid,
		"on_win": on_win, "on_loss": on_loss,
		"plan": EncounterBuilder.plan(catalog, state, encounter, {"node_id": "%s_evt" % sess["id"], "kind": "event", "mini": true, "spar": spar, "player": pid})}
	state["phase"] = "fight"


# =============================================================================================
# Rewards
# =============================================================================================

func pending_for(pid: String) -> Array:
	return session().get("pending", {}).get(pid, [])


func has_pending() -> bool:
	for pid in session().get("pending", {}):
		if not (session()["pending"][pid] as Array).is_empty():
			return true
	return false


## Adds a pick for a player. kind: supplement | technique. opts: {n, source, min_rarity,
## banned_chance, scrip_alt}
func add_pending(pid: String, kind: String, opts: Dictionary) -> void:
	var sess := session()
	if not sess.has("pending"):
		sess["pending"] = {}
	if not sess["pending"].has(pid):
		sess["pending"][pid] = []
	var counter := int(sess.get("reward_counter", 0))
	sess["reward_counter"] = counter + 1
	var rid := "%s%d" % [kind.substr(0, 3), counter]
	var key := "node/%s/%s/%s" % [sess.get("id", ""), pid, rid]
	var entry := {"rid": rid, "kind": kind, "source": str(opts.get("source", "fight")), "rerolls": 0, "key": key,
		"opts": opts.duplicate(), "scrip_alt": int(opts.get("scrip_alt", 0))}
	entry["options"] = _roll_options(pid, entry, key)
	if (entry["options"] as Array).is_empty() and int(entry["scrip_alt"]) <= 0:
		# nothing left to offer (e.g. all techniques learned): pay out instead of a dead pick
		var p := player(pid)
		p["scrip"] = int(p["scrip"]) + 50
		return
	var rr := rules_for(pid)
	if kind == "supplement" and float(rr.get("supplement_side_effects", 0.0)) > 0.0:
		entry["side_effect"] = RewardRoller.side_effect_roll(catalog, state, player(pid), key + "/dose7")
		entry["side_effect_visible"] = float(rr.get("side_effect_preview", 0.0)) > 0.0
	(sess["pending"][pid] as Array).append(entry)


func _roll_options(pid: String, entry: Dictionary, key: String) -> Array:
	var p := player(pid)
	var opts: Dictionary = entry.get("opts", {})
	if str(entry["kind"]) == "technique":
		return RewardRoller.technique_offer(catalog, state, p, key, int(opts.get("n", 2)))
	return RewardRoller.supplement_offer(catalog, state, p, key, {"source": str(opts.get("source", "fight")), "n": int(opts.get("n", 3)),
		"min_rarity": str(opts.get("min_rarity", "")), "banned_chance": float(opts.get("banned_chance", 0.0)), "act": int(state.get("act", 1))})


func _find_pending(pid: String, rid: String) -> Dictionary:
	for e in pending_for(pid):
		if str(e.get("rid", "")) == rid:
			return e
	return {}


func reroll_cost(pid: String, rid: String) -> int:
	var e := _find_pending(pid, rid)
	if e.is_empty():
		return -1
	if int(player(pid).get("rerolls_free", 0)) > 0:
		return 0
	return int(catalog.rules.get("reroll", {}).get("cost", 30))


func reroll(pid: String, rid: String) -> bool:
	var e := _find_pending(pid, rid)
	if e.is_empty():
		return _fail("no such pending reward")
	var limit := int(catalog.rules.get("reroll", {}).get("max_per_node", 2))
	if int(e.get("rerolls", 0)) >= limit:
		return _fail("reroll limit reached for this reward")
	var p := player(pid)
	var cost := reroll_cost(pid, rid)
	if cost > 0 and int(p["scrip"]) < cost:
		return _fail("not enough Scrip to reroll")
	if cost == 0:
		p["rerolls_free"] = int(p["rerolls_free"]) - 1
	else:
		p["scrip"] = int(p["scrip"]) - cost
	e["rerolls"] = int(e["rerolls"]) + 1
	e["options"] = _roll_options(pid, e, "%s/reroll%d" % [e["key"], e["rerolls"]])
	_log("reroll", pid, {"rid": rid})
	_commit("reroll")
	return true


## Claims a pending reward: choice = an option id, "skip", or "scrip" (treasure alternative).
func claim(pid: String, rid: String, choice: String) -> bool:
	var sess := session()
	var node_id := str(sess.get("id", ""))
	if node_id == "":
		return _fail("no node in progress")
	if _claimed(node_id, pid, rid):
		return _fail("reward %s already claimed" % rid)
	var e := _find_pending(pid, rid)
	if e.is_empty():
		return _fail("no such pending reward")
	var p := player(pid)
	if choice == "skip":
		pass
	elif choice == "scrip":
		if int(e.get("scrip_alt", 0)) <= 0:
			return _fail("this reward has no Scrip alternative")
		p["scrip"] = int(p["scrip"]) + int(e["scrip_alt"])
	elif not (e.get("options", []) as Array).has(choice):
		return _fail("'%s' is not one of the offered options" % choice)
	elif str(e["kind"]) == "technique":
		_grant_technique(pid, choice)
	else:
		grant_supplement(pid, choice, "%s:%s" % [node_id, rid])
		if str(e.get("side_effect", "")) != "" and not (p["side_effects"] as Array).has(e["side_effect"]):
			(p["side_effects"] as Array).append(str(e["side_effect"]))
			p["hp"] = clampf(float(p["hp"]), 1.0, max_hp(p))
	_record_claim(node_id, pid, rid)
	(sess["pending"][pid] as Array).erase(e)
	_log("claim", pid, {"rid": rid, "choice": choice})
	_commit("claim")
	_try_complete_node()
	return true


## Adds a supplement (or applies a consumable). Returns a result line.
func grant_supplement(pid: String, id: String, _source: String) -> String:
	var p := player(pid)
	var d: Dictionary = catalog.supplements.get(id, {})
	if d.is_empty():
		return ""
	var before := max_hp(p)
	if bool(d.get("consumable", false)):
		for eff in d.get("on_pick", []):
			EventRunner.apply_effect(self, pid, eff, {"source": id, "key": id})
		return "Used %s" % d.get("name", id)
	if not RewardRoller.can_take(catalog, p, id):
		p["scrip"] = int(p["scrip"]) + CampaignShop.sell_value(self, id)
		return "Already maxed: sold %s" % d.get("name", id)
	var found := false
	for s in p["supplements"]:
		if str(s["id"]) == id:
			s["stacks"] = int(s["stacks"]) + 1
			found = true
	if not found:
		(p["supplements"] as Array).append({"id": id, "stacks": 1})
	var after := max_hp(p)
	if after > before:
		p["hp"] = float(p["hp"]) + (after - before)
	p["hp"] = clampf(float(p["hp"]), 1.0, after)
	return "Got %s" % d.get("name", id)


func remove_supplement(pid: String, id: String) -> void:
	var p := player(pid)
	for s in (p["supplements"] as Array).duplicate():
		if str(s["id"]) == id:
			s["stacks"] = int(s["stacks"]) - 1
			if int(s["stacks"]) <= 0:
				(p["supplements"] as Array).erase(s)
			break
	p["hp"] = clampf(float(p["hp"]), 1.0, max_hp(p))


func _grant_technique(pid: String, tid: String) -> void:
	var p := player(pid)
	if (p["techniques"] as Array).has(tid):
		return
	var before := max_hp(p)
	(p["techniques"] as Array).append(tid)
	var after := max_hp(p)
	if after > before:
		p["hp"] = float(p["hp"]) + (after - before)
	p["hp"] = clampf(float(p["hp"]), 1.0, after)


# =============================================================================================
# Events
# =============================================================================================

func event_view(pid: String) -> Dictionary:
	if not session().has("event"):
		return {}
	return EventRunner.view(self, session()["event"], pid)


func choose_event(pid: String, choice_id: String) -> bool:
	if phase() != "event":
		return _fail("no event in progress")
	var node_id := str(session().get("id", ""))
	if _claimed(node_id, "_run", "event"):
		return _fail("this event was already decided")
	var r := EventRunner.choose(self, pid, choice_id)
	if not bool(r.get("ok", false)):
		return _fail(str(r.get("error", "event choice failed")))
	last_texts = (r.get("texts", []) as Array).duplicate()
	_record_claim(node_id, "_run", "event")
	_log("event", pid, {"choice": choice_id})
	if phase() == "event":
		state["phase"] = "reward"
	_commit("event")
	_try_complete_node()
	return true


# =============================================================================================
# Shop
# =============================================================================================

func shop_view(pid: String) -> Dictionary:
	var s: Dictionary = session().get("shop", {}).get(pid, {})
	if s.is_empty():
		return {}
	var v := s.duplicate(true)
	v["scrip"] = int(player(pid).get("scrip", 0))
	v["sellable"] = []
	for sp in player(pid).get("supplements", []):
		v["sellable"].append({"id": sp["id"], "value": CampaignShop.sell_value(self, str(sp["id"]))})
	return v


func shop_buy(pid: String, slot: String) -> bool:
	if phase() != "shop":
		return _fail("no shop open")
	var s: Dictionary = session().get("shop", {}).get(pid, {})
	if s.is_empty() or bool(s.get("done", false)):
		return _fail("shop closed for this player")
	var node_id := str(session()["id"])
	if _claimed(node_id, pid, "buy:%s:%d" % [slot, int(s.get("rerolls", 0))]):
		return _fail("already bought")
	var item := {}
	for it in s["items"]:
		if str(it["slot"]) == slot:
			item = it
	if item.is_empty() or bool(item.get("sold", false)):
		return _fail("nothing to buy in slot %s" % slot)
	var p := player(pid)
	if int(p["scrip"]) < int(item["price"]):
		return _fail("not enough Scrip")
	if str(item["kind"]) == "supplement" and not RewardRoller.can_take(catalog, p, str(item["id"])):
		return _fail("you cannot carry another %s" % catalog.item_name(str(item["id"])))
	p["scrip"] = int(p["scrip"]) - int(item["price"])
	item["sold"] = true
	if str(item["kind"]) == "technique":
		_grant_technique(pid, str(item["id"]))
	else:
		grant_supplement(pid, str(item["id"]), "shop")
		var rr := rules_for(pid)
		if float(rr.get("supplement_side_effects", 0.0)) > 0.0:
			var se := RewardRoller.side_effect_roll(catalog, state, p, "node/%s/%s/shop/%s/dose7" % [node_id, pid, slot])
			if se != "" and not (p["side_effects"] as Array).has(se):
				(p["side_effects"] as Array).append(se)
	_record_claim(node_id, pid, "buy:%s:%d" % [slot, int(s.get("rerolls", 0))])
	_log("buy", pid, {"slot": slot})
	_commit("buy")
	return true


## Uses the shop's service: rub_down | antidote | reroll (arg unused) — sell uses shop_sell.
func shop_service(pid: String, _arg := "") -> bool:
	if phase() != "shop":
		return _fail("no shop open")
	var s: Dictionary = session().get("shop", {}).get(pid, {})
	if s.is_empty() or bool(s.get("done", false)):
		return _fail("shop closed for this player")
	var p := player(pid)
	var svc := str(s.get("service", ""))
	var price := int(s.get("service_price", 0))
	var node_id := str(session()["id"])
	match svc:
		"rub_down":
			if _claimed(node_id, pid, "svc:rub_down"):
				return _fail("already used")
			if int(p["scrip"]) < price:
				return _fail("not enough Scrip")
			p["scrip"] = int(p["scrip"]) - price
			p["side_effects"] = []
			p["hp"] = clampf(float(p["hp"]), 1.0, max_hp(p))
			_record_claim(node_id, pid, "svc:rub_down")
		"antidote":
			var n := int(s.get("antidotes_bought", 0))
			if int(p["scrip"]) < price:
				return _fail("not enough Scrip")
			p["scrip"] = int(p["scrip"]) - price
			p["consumables"]["sup_antidote_lozenge"] = int(p["consumables"].get("sup_antidote_lozenge", 0)) + 1
			s["antidotes_bought"] = n + 1
		"reroll":
			if bool(s.get("reroll_used", false)):
				return _fail("this shop's stock was already rerolled")
			if int(p["scrip"]) < price:
				return _fail("not enough Scrip")
			p["scrip"] = int(p["scrip"]) - price
			var fresh := CampaignShop.stock(self, pid, 1)
			fresh["reroll_used"] = true
			fresh["service"] = svc
			fresh["service_price"] = price
			session()["shop"][pid] = fresh
		_:
			return _fail("this shop does not offer that service")
	_log("service", pid, {"arg": svc})
	_commit("service")
	return true


func shop_sell(pid: String, item_id: String) -> bool:
	if phase() != "shop":
		return _fail("no shop open")
	var s: Dictionary = session().get("shop", {}).get(pid, {})
	if s.is_empty() or str(s.get("service", "")) != "sell" or bool(s.get("done", false)):
		return _fail("this shop is not buying")
	var p := player(pid)
	if RewardRoller.stacks_of(p, item_id) <= 0:
		return _fail("you do not own %s" % item_id)
	remove_supplement(pid, item_id)
	p["scrip"] = int(p["scrip"]) + CampaignShop.sell_value(self, item_id)
	_log("sell", pid, {"item": item_id})
	_commit("sell")
	return true


func shop_leave(pid: String) -> bool:
	if phase() != "shop":
		return _fail("no shop open")
	var s: Dictionary = session().get("shop", {}).get(pid, {})
	if s.is_empty():
		return _fail("unknown player")
	if bool(s.get("done", false)):
		return true
	s["done"] = true
	_log("leave", pid, {})
	_commit("leave")
	_try_complete_node()
	return true


# =============================================================================================
# Rest
# =============================================================================================

func rest_heal_fraction(pid: String) -> float:
	var rr := rules_for(pid)
	var rest: Dictionary = catalog.rules.get("rest", {})
	var base := float(rest.get("patch_up", 0.3))
	if float(rr.get("rest_heal_override", 0.0)) > 0.0:
		base = maxf(base, float(rr["rest_heal_override"]))
	return (base + float(rr.get("rest_heal_add", 0.0))) * float(rr.get("rest_heal_mult", 1.0))


func rest_options(pid: String) -> Array:
	var p := player(pid)
	var rest: Dictionary = catalog.rules.get("rest", {})
	var techs_left := RewardRoller.technique_offer(catalog, state, p, "probe", 1).size() > 0
	return [
		{"id": "patch_up", "label": "Patch up", "desc": "Heal %d%% of max HP" % int(round(rest_heal_fraction(pid) * 100.0)), "available": true},
		{"id": "train", "label": "Train", "desc": "Learn 1 technique (1 of %d)" % int(rest.get("train_options", 2)), "available": techs_left},
		{"id": "rub_down", "label": "Rub-down", "desc": "Remove all side effects and heal %d%%" % int(float(rest.get("rub_down_heal", 0.1)) * 100.0), "available": true},
		{"id": "film_study", "label": "Film study", "desc": "Reveal the next act's elite and boss; +%d Hype carry" % int(rest.get("film_study_hype", 15)), "available": true},
	]


func rest_choose(pid: String, option: String) -> bool:
	if phase() != "rest":
		return _fail("no rest in progress")
	var r: Dictionary = session().get("rest", {}).get(pid, {})
	if r.is_empty():
		return _fail("unknown player")
	var node_id := str(session()["id"])
	if bool(r.get("done", false)) or _claimed(node_id, pid, "rest"):
		return _fail("you already rested here")
	var ok := false
	for o in rest_options(pid):
		if str(o["id"]) == option and bool(o["available"]):
			ok = true
	if not ok:
		return _fail("rest option '%s' not available" % option)
	var p := player(pid)
	var rest: Dictionary = catalog.rules.get("rest", {})
	match option:
		"patch_up":
			p["hp"] = minf(max_hp(p), float(p["hp"]) + max_hp(p) * rest_heal_fraction(pid))
		"train":
			add_pending(pid, "technique", {"n": int(rest.get("train_options", 2)), "source": "rest"})
		"rub_down":
			p["side_effects"] = []
			p["hp"] = minf(max_hp(p), float(p["hp"]) + max_hp(p) * float(rest.get("rub_down_heal", 0.1)))
		"film_study":
			var act := int(state.get("act", 1))
			state["flags"]["film_study"][str(mini(3, act + 1))] = true
			state["flags"]["film_study"][str(act)] = true
			p["hype_carry"] = minf(100.0, float(p.get("hype_carry", 0.0)) + float(rest.get("film_study_hype", 15)))
	r["done"] = true
	r["choice"] = option
	_record_claim(node_id, pid, "rest")
	_log("rest", pid, {"option": option})
	_commit("rest")
	_try_complete_node()
	return true


# =============================================================================================
# Consumables, abandon, time
# =============================================================================================

func use_consumable(pid: String, item_id: String) -> bool:
	if is_over():
		return _fail("the run is over")
	var p := player(pid)
	var cs: Dictionary = p.get("consumables", {})
	if int(cs.get(item_id, 0)) <= 0:
		return _fail("you have no %s" % item_id)
	cs[item_id] = int(cs[item_id]) - 1
	if int(cs[item_id]) <= 0:
		cs.erase(item_id)
	var d: Dictionary = catalog.supplements.get(item_id, {})
	for eff in d.get("on_pick", []):
		EventRunner.apply_effect(self, pid, eff, {"source": item_id, "key": "use/%s/%d" % [item_id, (state["log"] as Array).size()]})
	_log("consume", pid, {"item": item_id})
	_commit("consume")
	return true


func abandon() -> void:
	if is_over():
		return
	_log("abandon", "", {})
	_end_run(false, true)


func add_time(seconds: float) -> void:
	state["elapsed"] = float(state.get("elapsed", 0.0)) + maxf(0.0, seconds)


# =============================================================================================
# Node completion, acts, end of run
# =============================================================================================

func _node_activity_done() -> bool:
	var sess := session()
	match str(state.get("phase", "")):
		"fight":
			return false
		"event":
			return str(sess.get("event", {}).get("chosen", "")) != ""
		"shop":
			for pid in sess.get("shop", {}):
				if not bool(sess["shop"][pid].get("done", false)):
					return false
			return true
		"rest":
			for pid2 in sess.get("rest", {}):
				if not bool(sess["rest"][pid2].get("done", false)):
					return false
			return true
	return true


func _try_complete_node() -> void:
	if is_over() or phase() == "map":
		return
	if not _node_activity_done() or has_pending():
		return
	_complete_node()


func _complete_node() -> void:
	var sess := session()
	var t := str(sess.get("type", ""))
	state["node"] = {}
	if t == "boss":
		var act := int(state.get("act", 1))
		if act >= 3:
			_end_run(true)
			return
		var heals: Array = catalog.rules.get("boss_heal", [0.5, 0.35, 0.0])
		for p in players():
			var frac := float(heals[act - 1]) if act - 1 < heals.size() else 0.0
			frac += float(rules_for(str(p["id"])).get("boss_heal_add", 0.0))
			p["hp"] = minf(max_hp(p), float(p["hp"]) + max_hp(p) * frac)
		state["act"] = act + 1
		state["position"] = ""
		state["flags"]["act_intro"] = act + 1
		if players().size() >= 4:
			var low := ""
			var low_frac := INF
			for p2 in players():
				var fr := float(p2["hp"]) / maxf(1.0, max_hp(p2))
				if fr < low_frac:
					low_frac = fr
					low = str(p2["id"])
			state["flags"]["captain"] = low
		else:
			state["flags"]["captain"] = ""
	state["phase"] = "map"
	_commit("node_done")


func _end_run(victory: bool, abandoned := false) -> void:
	state["phase"] = "victory" if victory else "defeat"
	state["node"] = {} if victory else state.get("node", {})
	if victory:
		for p0 in players():
			p0["clout"] = int(p0.get("clout", 0)) + int(catalog.rules.get("rewards", {}).get("run_clear_clout", 150))
	var per := {}
	for p in players():
		per[str(p["id"])] = {"fighter": p["fighter"], "name": p["name"], "supplements": (p["supplements"] as Array).duplicate(true),
			"techniques": (p["techniques"] as Array).duplicate(), "side_effects": (p["side_effects"] as Array).duplicate(),
			"scrip": int(p["scrip"]), "stats": (p["stats"] as Dictionary).duplicate(true), "clout_raw": int(p.get("clout", 0)),
			"cosmetics": (p.get("cosmetics", []) as Array).duplicate()}
	state["result"] = {"victory": victory, "abandoned": abandoned, "act": int(state.get("act", 1)), "node": str(state.get("position", "")),
		"elapsed": float(state.get("elapsed", 0.0)), "dose": int(state.get("dose", 0)), "difficulty": str(state.get("difficulty", "")),
		"variant": str(state.get("variant", "")), "mode": str(state.get("mode", "")), "custom": bool(state.get("custom", false)),
		"seed_text": str(state.get("seed_text", "")), "players": per, "stats": (state.get("stats", {}) as Dictionary).duplicate(true)}
	_commit("victory" if victory else "defeat")


## The latest fight's compact result from the decision log ({} if none yet): result banners.
func last_fight() -> Dictionary:
	var lg: Array = state.get("log", [])
	for i in range(lg.size() - 1, -1, -1):
		var e: Dictionary = lg[i]
		if str(e.get("k", "")) == "fight":
			return e.get("d", {}).get("result", {})
	return {}


## Summary for the results card (victory/defeat screen, history).
func summary() -> Dictionary:
	var r: Dictionary = state.get("result", {})
	return r.duplicate(true)


# =============================================================================================
# Internals
# =============================================================================================

func _fail(msg: String) -> bool:
	last_error = msg
	return false


func _claimed(node_key: String, pid: String, cid: String) -> bool:
	return (state["claims"].get(node_key, {}).get(pid, []) as Array).has(cid)


func _record_claim(node_key: String, pid: String, cid: String) -> void:
	var c: Dictionary = state["claims"]
	if not c.has(node_key):
		c[node_key] = {}
	if not c[node_key].has(pid):
		c[node_key][pid] = []
	(c[node_key][pid] as Array).append(cid)


func _log(kind: String, pid: String, data: Dictionary) -> void:
	(state["log"] as Array).append({"k": kind, "p": pid, "d": data})


func _commit(reason: String) -> void:
	last_error = ""
	changed.emit(reason)
	if autosave.is_valid() and not replaying:
		autosave.call(state)
