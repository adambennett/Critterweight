class_name CampaignAutoPilot
extends RefCounted
## Between-fight decisions without a human: The Bookie's Table unattended mode ("Teddy picks"),
## co-op members who disconnected or went idle, and tests. Documented heuristic
## (docs/CAMPAIGN_SYSTEMS.md#autopilot):
##   Route   - value each visible node type by the player's state (HP fraction, Scrip, owned
##             build) and pick the next node with the best discounted route value to the boss
##             (unknown/hidden nodes count as average). Low HP steers to Rest/Shop and away from
##             Elites; healthy runs take Elites and Treasure; ties go to the lowest lane.
##   Rewards - supplements score rarity + synergy with owned tags (+ build tags of owned
##             techniques) - glass/side-effect risk when HP is low; techniques prefer completing
##             a build direction; skip only if every option scores negative; Treasure takes the
##             Scrip alternative when the best supplement is weak.
##   Events  - expected value of each available choice's weighted outcomes (HP weighted more
##             when low, Scrip, picks, side effects, fights only when healthy). Availability is
##             EventRunner's (group costs must fit every member); nothing available = PASS.
##   Shop    - buy the best affordable item above a value threshold keeping a 30 Scrip reserve
##             (a move scroll scores like a move pick); Rub-down with 2+ side effects; then leave.
##   Rest    - Patch up below 60% HP, Rub-down with 2+ side effects, else Train if a technique
##             is left, else Drill a move, else Learn a move, else Patch up below 90%, else Film
##             study.
##   Moves   - (Movesets runs) a move scores 1 + 0.3 per owned technique and 0.15 per supplement
##             stack that improves it (RunMoves.improves) + 0.5 when drilled; picks learn the best
##             new move (+0.2 for a category not learned yet), drills go to an equipped move
##             (first style); after every pick the loadout keeps its basic strike and equips the
##             three best other learned moves, the current ones winning ties, so a run keeps its
##             recommended loadout until its build favours other moves.
## All choices are deterministic for a given run state (no randomness of their own).

const RARITY_VALUE := {"otc": 1.0, "prescription": 1.6, "black_market": 2.3, "banned": 2.6}
const TYPE_VALUE := {"fight": 1.0, "elite": 1.6, "event": 0.9, "mystery": 0.95, "shop": 0.5, "rest": 0.4,
	"treasure": 1.6, "boss": 0.0, "unknown": 0.85}


static func hp_frac(ctrl: RunController, pid: String) -> float:
	var p := ctrl.player(pid)
	return clampf(float(p.get("hp", 0.0)) / maxf(1.0, ctrl.max_hp(p)), 0.0, 1.0)


static func node_value(ctrl: RunController, pid: String, t: String) -> float:
	var hp := hp_frac(ctrl, pid)
	var scrip := float(ctrl.player(pid).get("scrip", 0))
	var v := float(TYPE_VALUE.get(t, 0.8))
	match t:
		"fight":
			v -= maxf(0.0, 0.45 - hp) * 2.0
		"elite":
			v = 1.8 if hp > 0.7 else (0.5 if hp > 0.5 else -1.2)
		"shop":
			v += minf(1.4, scrip / 140.0)
		"rest":
			v += (1.0 - hp) * 2.2
		"event", "mystery":
			v -= maxf(0.0, 0.3 - hp)
	return v


static func choose_route(ctrl: RunController, pid: String) -> String:
	var opts := ctrl.available_nodes()
	if opts.is_empty():
		return ""
	var m := RunState.current_map(ctrl.state)
	var memo := {}
	var best := ""
	var best_v := -INF
	for id in opts:
		var v := _route_value(ctrl, pid, m, str(id), memo)
		if v > best_v + 1e-6:
			best_v = v
			best = str(id)
	return best


static func _route_value(ctrl: RunController, pid: String, m: Dictionary, id: String, memo: Dictionary) -> float:
	if memo.has(id):
		return float(memo[id])
	var n := ActMap.node(m, id)
	var own := node_value(ctrl, pid, ctrl.visible_type(id))
	var best_next := 0.0
	var first := true
	for e in n.get("edges", []):
		var nv := _route_value(ctrl, pid, m, str(e), memo)
		if first or nv > best_next:
			best_next = nv
			first = false
	var v := own + 0.85 * best_next
	memo[id] = v
	return v


static func owned_tags(ctrl: RunController, pid: String) -> Dictionary:
	var counts := RewardRoller.tag_counts(ctrl.catalog, ctrl.player(pid))
	for tid in ctrl.player(pid).get("techniques", []):
		var b := str(ctrl.catalog.techniques.get(str(tid), {}).get("build", ""))
		for t in ctrl.catalog.builds.get(b, {}).get("tags", []):
			counts[t] = int(counts.get(t, 0)) + 1
	return counts


static func supplement_score(ctrl: RunController, pid: String, id: String) -> float:
	var d: Dictionary = ctrl.catalog.supplements.get(id, {})
	if d.is_empty():
		return -9.0
	var hp := hp_frac(ctrl, pid)
	var tags: Array = d.get("tags", [])
	var counts := owned_tags(ctrl, pid)
	var s := float(RARITY_VALUE.get(str(d.get("rarity", "otc")), 1.0))
	for t in tags:
		s += minf(1.0, 0.35 * float(counts.get(t, 0)))
	if tags.has("glass") and hp < 0.5:
		s -= 1.2
	if str(d.get("rarity", "")) == "banned" and hp < 0.45:
		s -= 1.5
	if str(d.get("side_effect", "")) != "":
		s -= 0.25
	if bool(d.get("consumable", false)):
		s = 1.4 if not (ctrl.player(pid).get("side_effects", []) as Array).is_empty() else 0.1
	if tags.has("coop") and (ctrl.players().size() <= 1):
		s -= 0.6
	return s


static func technique_score(ctrl: RunController, pid: String, tid: String) -> float:
	var t: Dictionary = ctrl.catalog.techniques.get(tid, {})
	var s := 1.0
	var b := str(t.get("build", ""))
	for owned in ctrl.player(pid).get("techniques", []):
		if str(ctrl.catalog.techniques.get(str(owned), {}).get("build", "")) == b:
			s += 1.5
	var counts := owned_tags(ctrl, pid)
	for tag in t.get("tags", []):
		s += 0.25 * float(counts.get(tag, 0))
	return s


## Choice for a pending reward entry: an option id, "scrip" or "skip".
static func choose_reward(ctrl: RunController, pid: String, entry: Dictionary) -> String:
	var opts: Array = entry.get("options", [])
	match str(entry.get("kind", "")):
		"move":
			return _best_new_move(ctrl, pid, opts)
		"drill":
			return _best_drill(ctrl, pid, opts)
	var best := "skip"
	var best_s := 0.0
	for o in opts:
		var s := technique_score(ctrl, pid, str(o)) if str(entry.get("kind", "")) == "technique" else supplement_score(ctrl, pid, str(o))
		if s > best_s:
			best_s = s
			best = str(o)
	if int(entry.get("scrip_alt", 0)) > 0 and best_s < 1.5:
		return "scrip"
	return best


# ---------------------------------------------------------------------------------------------
# Moves (Movesets runs)
# ---------------------------------------------------------------------------------------------

## How much the player's build wants a pool move (see the header).
static func move_score(ctrl: RunController, pid: String, id: String) -> float:
	var p := ctrl.player(pid)
	if RunMoves.move_info(ctrl.catalog, str(p.get("fighter", "")), id).is_empty():
		return -9.0
	var s := 1.0
	for tid in p.get("techniques", []):
		if (RunMoves.analysis(ctrl.catalog, ctrl.state, p, str(tid))["moves"] as Dictionary).has(id):
			s += 0.3
	for sp in p.get("supplements", []):
		if (RunMoves.analysis(ctrl.catalog, ctrl.state, p, str(sp.get("id", "")))["moves"] as Dictionary).has(id):
			s += 0.15 * int(sp.get("stacks", 1))
	if (RunMoves.moves_of(p)["drilled"] as Dictionary).has(id):
		s += 0.5
	return s


static func _best_new_move(ctrl: RunController, pid: String, opts: Array) -> String:
	var p := ctrl.player(pid)
	var fighter := str(p.get("fighter", ""))
	var cats := {}
	for lid in RunMoves.moves_of(p)["learned"]:
		cats[str(RunMoves.move_info(ctrl.catalog, fighter, str(lid)).get("category", ""))] = true
	var best := "skip"
	var best_s := -INF
	for o in opts:
		var s := move_score(ctrl, pid, str(o))
		if not cats.has(str(RunMoves.move_info(ctrl.catalog, fighter, str(o)).get("category", ""))):
			s += 0.2
		if s > best_s + 1e-6:
			best_s = s
			best = str(o)
	return best


static func _best_drill(ctrl: RunController, pid: String, opts: Array) -> String:
	var equipped: Array = RunMoves.fight_loadout(ctrl.catalog, ctrl.player(pid))
	var best := "skip"
	var best_s := -INF
	for o in opts:
		var mv := str(RunMoves.split_drill(str(o))[0])
		var s := move_score(ctrl, pid, mv) + (1.0 if equipped.has(mv) else 0.0)
		if s > best_s + 1e-6:
			best_s = s
			best = str(o)
	return best


## The loadout the autopilot fights with: the current basic strike and the three best other
## learned moves (current ones win ties, then pool order). Martial fighters keep theirs.
static func best_loadout(ctrl: RunController, pid: String) -> Array:
	var p := ctrl.player(pid)
	var cat := ctrl.catalog
	var inf := RunMoves.info(cat, str(p.get("fighter", "")))
	var cur := RunMoves.fight_loadout(cat, p)
	if bool(inf.get("martial", false)) or not RunMoves.is_movesets(ctrl.state):
		return cur
	var moves: Dictionary = inf.get("moves", {})
	var basic := ""
	for id in cur:
		if str(moves.get(str(id), {}).get("role", "")) == "basic":
			basic = str(id)
			break
	var learned: Array = RunMoves.moves_of(p)["learned"]
	var ranked := []
	for id2 in inf.get("order", []):
		if not learned.has(str(id2)):
			continue
		if basic == "" and str(moves.get(str(id2), {}).get("role", "")) == "basic":
			basic = str(id2)
		if str(id2) == basic or str(moves.get(str(id2), {}).get("role", "")) == "basic":
			continue
		ranked.append([move_score(ctrl, pid, str(id2)) + (0.3 if cur.has(str(id2)) else 0.0), ranked.size(), str(id2)])
	if basic == "":
		return cur
	ranked.sort_custom(func(a, b): return float(a[0]) > float(b[0]) + 1e-6 or (absf(float(a[0]) - float(b[0])) <= 1e-6 and int(a[1]) < int(b[1])))
	var lo := [basic]
	for r in ranked:
		if lo.size() >= 4:
			break
		lo.append(str(r[2]))
	if RunMoves.loadout_problem(cat, p, lo) != "":
		return cur
	# the same moves in another order is no change: keep the player's slots
	var same := lo.size() == cur.size()
	for id3 in lo:
		same = same and cur.has(id3)
	return cur if same else lo


## Equips best_loadout() when it differs from the current one. True if anything changed.
static func auto_equip(ctrl: RunController, pid: String) -> bool:
	if not RunMoves.is_movesets(ctrl.state) or ctrl.is_over():
		return false
	var lo := best_loadout(ctrl, pid)
	if lo == RunMoves.fight_loadout(ctrl.catalog, ctrl.player(pid)):
		return false
	return ctrl.equip_moves(pid, lo)


static func effect_value(ctrl: RunController, pid: String, eff: Dictionary) -> float:
	var hp := hp_frac(ctrl, pid)
	var hp_w := 0.06 if hp < 0.5 else 0.025
	match str(eff.get("op", "")):
		"hp":
			return float(eff.get("amount", 0.0)) * hp_w
		"hp_pct":
			return float(eff.get("amount", 0.0)) * 100.0 * hp_w
		"max_hp":
			return float(eff.get("amount", 0.0)) * 0.04
		"scrip":
			return float(eff.get("amount", 0.0)) * 0.012
		"hype_carry":
			return float(eff.get("amount", 0.0)) * 0.006
		"grant_supplement":
			return 0.9
		"side_effect":
			return -0.5 * float(eff.get("count", 1))
		"remove_supplement":
			return -0.9
		"remove_side_effects":
			return 0.4 * float((ctrl.player(pid).get("side_effects", []) as Array).size())
		"technique_pick":
			return 1.1
		"learn_move":
			# a new move beats a stretch, but a hurt fighter takes the heal (nap: 0.9 below half HP)
			return 0.8 if RunMoves.is_movesets(ctrl.state) and not RunMoves.learnable(ctrl.catalog, ctrl.player(pid)).is_empty() else 0.3
		"reward_pick":
			return 1.3
		"run_mods", "run_patches", "run_hooks":
			return 0.35
		"next_fight", "boss_mod", "coupon", "consumable", "cosmetic", "quip":
			return 0.25
		"bet":
			return 0.2 if hp > 0.6 else -0.1
		"fight":
			var w := 0.0
			for sub in eff.get("on_win", []):
				w += effect_value(ctrl, pid, sub)
			return (w * 0.7 - 0.4) if hp > 0.6 else -1.5
	return 0.0


static func choose_event(ctrl: RunController, pid: String) -> String:
	var view := ctrl.event_view(pid)
	var ev: Dictionary = ctrl.catalog.events.get(str(view.get("id", "")), {})
	var best := ""
	var best_v := -INF
	for c in view.get("choices", []):
		if not bool(c.get("available", false)):
			continue
		var choice := {}
		for c2 in ev.get("choices", []):
			if str(c2.get("id", "")) == str(c["id"]):
				choice = c2
		var total_w := 0.0
		var v := 0.0
		for o in choice.get("outcomes", []):
			var w := float(o.get("weight", 1.0))
			total_w += w
			var ov := 0.0
			for eff in o.get("effects", []):
				ov += effect_value(ctrl, pid, eff)
			v += w * ov
		v = v / maxf(total_w, 0.001) - float(choice.get("cost", {}).get("scrip", 0)) * 0.012
		if v > best_v + 1e-6:
			best_v = v
			best = str(c["id"])
	# nothing anyone can take (e.g. a group cost nobody can split): move on instead of stalling
	return best if best != "" else EventRunner.PASS


static func rest_choice(ctrl: RunController, pid: String) -> String:
	var hp := hp_frac(ctrl, pid)
	var opts := {}
	for o in ctrl.rest_options(pid):
		opts[str(o["id"])] = bool(o["available"])
	if hp < 0.6:
		return "patch_up"
	if (ctrl.player(pid).get("side_effects", []) as Array).size() >= 2:
		return "rub_down"
	if bool(opts.get("train", false)):
		return "train"
	if bool(opts.get("drill", false)):
		return "drill"
	if bool(opts.get("learn", false)):
		return "learn"
	if hp < 0.9:
		return "patch_up"
	return "film_study"


## Performs every shop action for a player and leaves.
static func do_shop(ctrl: RunController, pid: String) -> void:
	var guard := 0
	while guard < 8:
		guard += 1
		var v := ctrl.shop_view(pid)
		if v.is_empty() or bool(v.get("done", false)):
			return
		var scrip := int(v.get("scrip", 0))
		if str(v.get("service", "")) == "rub_down" and (ctrl.player(pid).get("side_effects", []) as Array).size() >= 2 and scrip >= int(v.get("service_price", 99)) + 10:
			if ctrl.shop_service(pid):
				continue
		var best := ""
		var best_s := 1.2
		for it in v.get("items", []):
			if bool(it.get("sold", false)) or int(it["price"]) > scrip - 30:
				continue
			var s := 0.0
			match str(it["kind"]):
				"technique":
					s = technique_score(ctrl, pid, str(it["id"])) + 0.6
				"move":
					s = move_score(ctrl, pid, str(it["id"])) + 0.7     # a new move for good: worth a scroll's price
				_:
					s = supplement_score(ctrl, pid, str(it["id"]))
			s -= float(it["price"]) / 200.0
			if s > best_s:
				best_s = s
				best = str(it["slot"])
		if best == "" or not ctrl.shop_buy(pid, best):
			break
	ctrl.shop_leave(pid)


## Makes every pending non-fight decision for the given players at the current node.
## Returns true if anything was decided. Fights are never auto-resolved here.
static func settle(ctrl: RunController, pids: Array) -> bool:
	var did := false
	for pid in pids:
		var spid := str(pid)
		match ctrl.phase():
			"event":
				var view := ctrl.event_view(spid)
				if bool(view.get("can_decide", true)) and str(view.get("chosen", "")) == "":
					var c := choose_event(ctrl, spid)
					if c != "" and ctrl.choose_event(spid, c):
						did = true
			"shop":
				if not bool(ctrl.shop_view(spid).get("done", true)):
					do_shop(ctrl, spid)
					auto_equip(ctrl, spid)        # a move scroll may have been bought
					did = true
			"rest":
				var r: Dictionary = ctrl.session().get("rest", {}).get(spid, {})
				if not r.is_empty() and not bool(r.get("done", false)):
					if ctrl.rest_choose(spid, rest_choice(ctrl, spid)):
						did = true
		var picked := false
		for e in ctrl.pending_for(spid).duplicate():
			if ctrl.claim(spid, str(e["rid"]), choose_reward(ctrl, spid, e)):
				did = true
				picked = true
		# a new move or drill may change what the fighter should bring
		if picked and auto_equip(ctrl, spid):
			did = true
	return did
