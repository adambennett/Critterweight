extends CampaignTestCase
## v0.9.18 moves in runs (docs/CAMPAIGN_SYSTEMS.md "Moves in runs", MOVESET_COMBAT.md §5/§8): the
## run state's learned / equipped / drilled moves, the learn / equip / drill decisions (logged,
## verified, replayed), move tutors, scrolls, rest training and drills, the event op learn_move,
## fights that bring the equipped moves as drilled, the v1 -> v2 migration, Fight Camp's Sparring
## Partner and Film Study, and the autopilot's choices. Synthetic fight results (no physics) except
## where a fight is built. Co-op member intents: test_campaign_coop.gd; the upgrade translation and
## its lint: test_upgrade_translation.gd.

const FURNACE := ["ember_jab", "flamethrower", "steam_vent", "stoke_the_fire"]
const BRAWLER := ["ember_jab", "furnace_haymaker", "flare_rush", "cinder_shot"]


func _moves(ctrl: RunController, pid := "p0") -> Dictionary:
	return RunMoves.moves_of(ctrl.player(pid))


## The log entries of one kind.
func _logged(ctrl: RunController, kind: String) -> Array:
	var out := []
	for e in ctrl.state["log"]:
		if str(e.get("k", "")) == kind:
			out.append(e)
	return out


func _verifies(ctrl: RunController, what: String) -> void:
	var wire = JSON.parse_string(JSON.stringify(RunStore.json_stable(ctrl.state), "", false, true))
	var v := RunController.verify(cat(), wire)
	check(bool(v["ok"]), "%s: the run follows from its decision log (%s)" % [what, v["error"]])
	var rp := RunController.replay(cat(), ctrl.state["start_cfg"], (ctrl.state["log"] as Array).slice(1))
	check_eq(RunController.digest(rp.state), RunController.digest(ctrl.state), "%s: a replay rebuilds it" % what)


## The shortest route from the start of an act to its first `t` stop that passes no elite or boss
## on the way (an elite's tutor would teach the one move Stoke has left to learn). [] = none.
func _path_to_type(m: Dictionary, t: String) -> Array:
	var best := []
	for p in ActMap.all_paths(m):
		var pa: Array = p
		for i in pa.size():
			var ty := str(ActMap.node(m, str(pa[i])).get("type", ""))
			if ty == t:
				if best.is_empty() or i + 1 < best.size():
					best = pa.slice(0, i + 1)
				break
			if ty in ["elite", "boss"]:
				break
	return best


## A Stoke run seed (or a party's, via `extra`) whose act 1 map has such a route to a `t` stop.
func _seed_with(t: String, extra := {}) -> int:
	for s in range(1, 600):
		var cfg := run_cfg("f_stoke", {"seed": s})
		for k in extra:
			cfg[k] = extra[k]
		var st := RunState.create(cat(), cfg)
		if not _path_to_type(RunState.act_map(st, 1), t).is_empty():
			return s
	return 0


## Walks the act 1 map to the first `t` stop (synthetic fights, first options) and enters it.
func _walk_to(ctrl: RunController, t: String) -> bool:
	var target := _path_to_type(RunState.current_map(ctrl.state), t)
	if target.is_empty():
		return false
	for j in target.size():
		if not ctrl.choose_node(str(target[j]), "p0"):
			fail("could not enter %s: %s" % [target[j], ctrl.last_error])
			return false
		if j < target.size() - 1:
			settle_node(ctrl)
	return true


# =============================================================================================
# Run state
# =============================================================================================

func test_new_runs_learn_both_loadouts_and_equip_the_default() -> void:
	var ctrl := new_run({"seed": 31})
	check_eq(int(ctrl.state["version"]), 2, "run format v2")
	check_eq(str(ctrl.state["combat"]), "moves", "new runs fight Movesets")
	var m := _moves(ctrl)
	var both := FURNACE.duplicate()
	for id in BRAWLER:
		if not both.has(id):
			both.append(id)
	check_eq(m["learned"], both, "Stoke starts with Furnace and Brawler learned")
	check_eq(m["equipped"], FURNACE, "and Furnace (his default loadout) equipped")
	check((m["drilled"] as Dictionary).is_empty(), "nothing drilled")
	var dozer := new_run({"seed": 31}, "f_dozer")
	var dm := _moves(dozer)
	check_eq(dm["equipped"], (RunMoves.info(cat(), "f_dozer")["loadouts"]["classic"] as Dictionary)["moves"], "a fighter without a pool fights its Classic kit as moves")
	check_eq(dm["learned"], dm["equipped"], "(which is all it can learn)")
	check(RunState.check(cat(), ctrl.state).is_empty(), "a new run passes its own check")
	var classic := new_run({"seed": 31, "combat": "classic"})
	check_eq(str(classic.state["combat"]), "classic", "a run can be started Classic")
	check_eq(str(classic.state["start_cfg"].get("combat", "")), "classic", "and replays as Classic")
	check(not classic.equip_moves("p0", BRAWLER), "a Classic run does not equip moves")
	check(classic.last_error.contains("Classic"), "and says why (%s)" % classic.last_error)


func test_scripts_with_moves_screens_compile() -> void:
	for path in ["res://src/campaign/ui/reward_screen.gd", "res://src/campaign/ui/shop_screen.gd", "res://src/campaign/ui/rest_screen.gd",
			"res://src/campaign/ui/run_map_screen.gd", "res://src/campaign/ui/campaign_ui.gd", "res://src/campaign/ui/coop_flow.gd",
			"res://src/hub/view/hub_upgrade_props.gd", "res://src/hub/ui/hub_board_station.gd"]:
		var s = load(path)
		check(s != null and (s as GDScript).can_instantiate(), "%s compiles" % path)


# =============================================================================================
# Decisions: learn / equip / drill
# =============================================================================================

func test_equip_is_a_logged_decision_with_loadout_rules() -> void:
	var ctrl := new_run({"seed": 41})
	check(ctrl.equip_moves("p0", BRAWLER), "equip Brawler: %s" % ctrl.last_error)
	check_eq(_moves(ctrl)["equipped"], BRAWLER, "equipped")
	var eq := _logged(ctrl, "equip")
	check_eq(eq.size(), 1, "logged once")
	if not eq.is_empty():
		check_eq(eq[0]["d"]["loadout"], BRAWLER, "with the loadout")
		check_eq(str(eq[0]["p"]), "p0", "and the player")
	check(ctrl.equip_moves("p0", BRAWLER), "equipping the same loadout again is fine")
	check_eq(_logged(ctrl, "equip").size(), 1, "and logs nothing")
	check(not ctrl.equip_moves("p0", ["ember_jab", "fire_spin"]), "an unlearned move cannot be equipped")
	check(ctrl.last_error.contains("not learned"), "(%s)" % ctrl.last_error)
	check(not ctrl.equip_moves("p0", ["flamethrower", "steam_vent"]), "a loadout needs a basic strike")
	check(not ctrl.equip_moves("p0", ["ember_jab", "flamethrower", "steam_vent", "stoke_the_fire", "flare_rush"]), "at most four moves")
	check(not ctrl.equip_moves("p0", ["ember_jab", "ember_jab"]), "no move twice")
	check(ctrl.equip_moves("p0", ["ember_jab", "flamethrower", "furnace_haymaker", "flare_rush"]), "any four learned moves with a basic")
	_verifies(ctrl, "equip")


func test_rest_learn_and_drill_are_logged_decisions() -> void:
	var seed_value := _seed_with("rest")
	check(seed_value > 0, "precondition: a card with a rest stop")
	var ctrl := new_run({"seed": seed_value})
	check(_walk_to(ctrl, "rest"), "walked to the rest stop")
	check_eq(ctrl.phase(), "rest", "resting")
	var ids := []
	for o in ctrl.rest_options("p0"):
		ids.append(str(o["id"]))
	check(ids.slice(0, 4) == ["patch_up", "train", "rub_down", "film_study"], "the classic four come first (%s)" % str(ids))
	check(ids.has("learn") and ids.has("drill"), "Movesets runs add Learn a move and Drill a move")
	check(ctrl.rest_choose("p0", "learn"), "learn: %s" % ctrl.last_error)
	var pend := ctrl.pending_for("p0")
	check(pend.size() == 1 and str(pend[0]["kind"]) == "move", "a move pick waits")
	if pend.is_empty():
		return
	var e: Dictionary = pend[0]
	var opts: Array = e["options"]
	check(not opts.is_empty() and RunMoves.learnable(cat(), ctrl.player("p0")).has(str(opts[0])), "it offers moves Stoke does not know (%s)" % str(opts))
	check(not ctrl.learn_move("p0", "ember_jab", "pick:" + str(e["rid"])), "a known move is refused")
	check(not ctrl.learn_move("p0", str(opts[0]), "pick:nope"), "an unknown pick is refused")
	check(ctrl.learn_move("p0", str(opts[0]), "pick:" + str(e["rid"])), "learn %s: %s" % [opts[0], ctrl.last_error])
	check((_moves(ctrl)["learned"] as Array).has(str(opts[0])), "learned")
	check_eq(_moves(ctrl)["equipped"], FURNACE, "learning does not change the loadout")
	check(not ctrl.learn_move("p0", str(opts[0]), "pick:" + str(e["rid"])), "the same pick twice is refused")
	var lg := _logged(ctrl, "learn")
	check(lg.size() == 1 and str(lg[0]["d"]["move"]) == str(opts[0]) and str(lg[0]["d"]["source"]) == "pick:" + str(e["rid"]),
		"logged as learn {move, source} (%s)" % str(lg))
	check_eq(ctrl.phase(), "map", "the rest stop completes with the pick")
	_verifies(ctrl, "learn at a rest")
	check(not ctrl.rest_options("p0").is_empty(), "options still list")
	# the same card, drilling at that rest instead
	var d := new_run({"seed": seed_value})
	check(_walk_to(d, "rest"), "walked to the rest stop again")
	check(d.rest_choose("p0", "drill"), "drill: %s" % d.last_error)
	var dp := d.pending_for("p0")
	check(dp.size() == 1 and str(dp[0]["kind"]) == "drill", "a drill pick waits")
	if dp.is_empty():
		return
	var opt := str(dp[0]["options"][0])
	var md := RunMoves.split_drill(opt)
	check(FURNACE.has(str(md[0])), "equipped moves are offered first (%s)" % opt)
	check(not d.drill_move("p0", str(md[0]), "no_such_style", "pick:" + str(dp[0]["rid"])), "an unknown style is refused")
	check(not d.drill_move("p0", "fire_spin", "inferno_ring", "pick:" + str(dp[0]["rid"])), "an unlearned move cannot be drilled")
	check(d.drill_move("p0", str(md[0]), str(md[1]), "pick:" + str(dp[0]["rid"])), "drill %s: %s" % [opt, d.last_error])
	check_eq(str((_moves(d)["drilled"] as Dictionary).get(str(md[0]), "")), str(md[1]), "drilled for the run")
	var dl := _logged(d, "drill")
	check(dl.size() == 1 and str(dl[0]["d"]["style"]) == str(md[1]) and str(dl[0]["d"]["move"]) == str(md[0]), "logged as drill {move, style, source}")
	check_eq(d.phase(), "map", "the rest stop completes with the drill")
	_verifies(d, "drill at a rest")


func test_drill_picks_and_claim_routing() -> void:
	# a drill pick opened at a node session (as Train / Drill at a rest do), claimed through claim()
	var ctrl := new_run({"seed": 43})
	ctrl.state["phase"] = "reward"
	ctrl.state["node"] = {"id": "d1", "type": "rest", "pending": {"p0": []}, "fights": 0}
	ctrl.add_pending("p0", "drill", {"n": 2, "source": "rest"})
	var e: Dictionary = ctrl.pending_for("p0")[0]
	var opts: Array = e["options"]
	check_eq(opts.size(), 4, "two moves with both their styles")
	for o in opts:
		check(FURNACE.has(str(RunMoves.split_drill(str(o))[0])), "an equipped move: %s" % o)
	check(ctrl.claim("p0", str(e["rid"]), str(opts[1])), "claim() takes a drill option: %s" % ctrl.last_error)
	check_eq(_logged(ctrl, "drill").size(), 1, "and logs it as the drill decision")
	check_eq(_logged(ctrl, "claim").size(), 0, "not as a plain claim")
	var md := RunMoves.split_drill(str(opts[1]))
	check_eq(str(_moves(ctrl)["drilled"][str(md[0])]), str(md[1]), "drilled")
	ctrl.state["phase"] = "reward"
	ctrl.state["node"] = {"id": "d2", "type": "rest", "pending": {"p0": []}, "fights": 0}
	ctrl.add_pending("p0", "drill", {"n": 4, "source": "rest"})
	var e2: Dictionary = ctrl.pending_for("p0")[0]
	for o2 in e2["options"]:
		check(str(RunMoves.split_drill(str(o2))[0]) != str(md[0]), "a drilled move is not offered again")
	check(ctrl.claim("p0", str(e2["rid"]), "skip"), "a pick can be skipped")


# =============================================================================================
# Sources: tutors, scrolls, events
# =============================================================================================

func test_elite_and_boss_wins_bring_a_move_tutor() -> void:
	var seed_value := _seed_with("elite")
	check(seed_value > 0, "precondition: a card with an elite")
	var ctrl := new_run({"seed": seed_value})
	check(_walk_to(ctrl, "elite"), "walked to the elite")
	check_eq(ctrl.phase(), "fight", "elite fight pending")
	ctrl.complete_fight(fake_result(ctrl))
	var kinds := {}
	var tutor := {}
	for e in ctrl.pending_for("p0"):
		kinds[str(e["kind"])] = true
		if str(e["kind"]) == "move":
			tutor = e
	check(kinds.has("supplement") and kinds.has("technique"), "the usual supplement and technique picks")
	check(not tutor.is_empty(), "and a move tutor")
	if tutor.is_empty():
		return
	check_eq(str(tutor["source"]), "elite", "from the elite")
	check_eq(str(tutor["rid"]).substr(0, 3), "mov", "after the other picks (their ids are unchanged)")
	for o in tutor["options"]:
		check(RunMoves.learnable(cat(), ctrl.player("p0")).has(str(o)), "offers an unlearned move: %s" % o)
	check(ctrl.claim("p0", str(tutor["rid"]), str(tutor["options"][0])), "claim the tutor: %s" % ctrl.last_error)
	check((_moves(ctrl)["learned"] as Array).has(str(tutor["options"][0])), "learned from the tutor")
	settle_node(ctrl)
	_verifies(ctrl, "elite tutor")
	# a normal fight has no tutor
	var normal := new_run({"seed": seed_value})
	normal.choose_node(str(normal.available_nodes()[0]), "p0")
	normal.complete_fight(fake_result(normal))
	for e2 in normal.pending_for("p0"):
		check(str(e2["kind"]) != "move", "no tutor after a normal fight")


func test_the_shop_sells_a_move_scroll() -> void:
	var seed_value := _seed_with("shop")
	check(seed_value > 0, "precondition: a card with a shop")
	cat().rules["start_scrip"] = 500         # (this test's catalog: the replay starts the same way)
	var ctrl := new_run({"seed": seed_value})
	check(_walk_to(ctrl, "shop"), "walked to the shop")
	var scrip0 := int(ctrl.player("p0")["scrip"])
	var v := ctrl.shop_view("p0")
	var scroll := {}
	for it in v["items"]:
		if str(it["kind"]) == "move":
			scroll = it
	check(not scroll.is_empty(), "the stall stocks a move scroll")
	if scroll.is_empty():
		return
	check(RunMoves.learnable(cat(), ctrl.player("p0")).has(str(scroll["id"])), "for a move Stoke does not know")
	check(int(scroll["price"]) > 0 and int(scroll["price"]) <= int(round(80.0 * 1.3)), "at the scroll price (%d)" % int(scroll["price"]))
	check(not ctrl.learn_move("p0", str(scroll["id"]), "shop:s0"), "a supplement slot is no scroll")
	check(ctrl.shop_buy("p0", str(scroll["slot"])), "buy the scroll: %s" % ctrl.last_error)
	check_eq(int(ctrl.player("p0")["scrip"]), scrip0 - int(scroll["price"]), "paid")
	check((_moves(ctrl)["learned"] as Array).has(str(scroll["id"])), "learned")
	var lg := _logged(ctrl, "learn")
	check(lg.size() == 1 and str(lg[0]["d"]["source"]) == "shop:" + str(scroll["slot"]), "logged as learn from the shop")
	check(not ctrl.shop_buy("p0", str(scroll["slot"])), "a scroll sells once")
	ctrl.shop_leave("p0")
	settle_node(ctrl)
	_verifies(ctrl, "move scroll")


func test_the_rest_stop_event_teaches_a_move() -> void:
	var c := cat()
	var ev: Dictionary = c.events.get("evt_rest_stop", {})
	var choice := {}
	for ch in ev.get("choices", []):
		if str(ch["id"]) == "shadowbox":
			choice = ch
	check(not choice.is_empty(), "Highway Rest Stop has a Shadowbox choice")
	var ctrl := new_run({"seed": 47})
	ctrl.state["phase"] = "event"
	ctrl.state["position"] = "ev"
	ctrl.state["node"] = {"id": "ev", "type": "event", "pending": {"p0": []}, "fights": 0, "event": EventRunner.begin(ctrl, "ev", "evt_rest_stop")}
	check(ctrl.choose_event("p0", "shadowbox"), "shadowbox: %s" % ctrl.last_error)
	var pend := ctrl.pending_for("p0")
	check(pend.size() == 1 and str(pend[0]["kind"]) == "move" and str(pend[0]["source"]) == "event", "a move pick from the event")
	var classic := new_run({"seed": 47, "combat": "classic"})
	classic.state["phase"] = "event"
	classic.state["position"] = "ev"
	classic.state["node"] = {"id": "ev", "type": "event", "pending": {"p0": []}, "fights": 0, "event": EventRunner.begin(classic, "ev", "evt_rest_stop")}
	var s0 := int(classic.player("p0")["scrip"])
	check(classic.choose_event("p0", "shadowbox"), "Classic run: shadowbox")
	check_eq(int(classic.player("p0")["scrip"]), s0 + 25, "a Classic run gets 25 Scrip instead")
	check(classic.pending_for("p0").is_empty(), "and no move pick")
	# {move: id}: a fighter-specific event can teach one move outright
	var c2 := cat()
	c2.events["evt_test_teacher"] = {"id": "evt_test_teacher", "type": "event", "title": "Old Stoker", "text": "Watch the hips.",
		"choices": [{"id": "watch", "label": "Watch", "outcomes": [{"effects": [{"op": "learn_move", "move": "fire_spin"}]}]}]}
	var t := new_run({"seed": 48})
	t.state["phase"] = "event"
	t.state["position"] = "ev"
	t.state["node"] = {"id": "ev", "type": "event", "pending": {"p0": []}, "fights": 0, "event": EventRunner.begin(t, "ev", "evt_test_teacher")}
	check(t.choose_event("p0", "watch"), "watch: %s" % t.last_error)
	check((_moves(t)["learned"] as Array).has("fire_spin"), "Fire Spin learned from the event")
	check(t.pending_for("p0").is_empty(), "without a pick")
	check(t.last_texts.has("Learned Fire Spin"), "and the result says so (%s)" % str(t.last_texts))


# =============================================================================================
# Fights
# =============================================================================================

func test_fights_bring_the_equipped_moves_as_drilled() -> void:
	var ctrl := new_run({"seed": 53})
	var lo := ["ember_jab", "flamethrower", "flare_rush", "cinder_shot"]
	check(ctrl.equip_moves("p0", lo), "equip: %s" % ctrl.last_error)
	RunMoves.block(ctrl.player("p0"))["drilled"] = {"flamethrower": "wide_nozzle", "cinder_shot": "scatter_coals"}
	ctrl.state["phase"] = "fight"
	ctrl.state["position"] = "t"
	ctrl.state["node"] = {"id": "t", "type": "fight", "pending": {"p0": []}, "fights": 0,
		"fight": {"encounter": "enc_a1_open_tryout", "tier": "normal", "plan": EncounterBuilder.plan(cat(), ctrl.state, "enc_a1_open_tryout", {"node_id": "t"})}}
	var built := ctrl.match_config({"player_kinds": {"p0": "bot"}})
	check((built["errors"] as PackedStringArray).is_empty(), "the fight builds: %s" % str(built["errors"]))
	var fighters: Array = built["config"].get("fighters", [])
	if fighters.is_empty():
		return
	check_eq(fighters[0].get("loadout", []), lo, "the player's fighter brings the equipped moves")
	check_eq(str(built["config"]["rules"]["combat"]), "moves", "in a Movesets fight")
	var c: CreatureDef = fighters[0]["creature"]
	var flame: MoveDef = (c.pool["flamethrower"] as PoolMove).move
	var area := {}
	for e in flame.effects:
		if str(e.get("type", "")) == "area":
			area = e
	check_near(float(area.get("cone_deg", 0.0)), 60.0, 0.001, "Flamethrower is drilled: Wide Nozzle's 60 degree fan")
	check_near(float(area.get("radius", 0.0)), 2.4, 0.001, "2.4 m long")
	var coal: MoveDef = (c.pool["cinder_shot"] as PoolMove).move
	var proj := {}
	for e2 in coal.effects:
		if str(e2.get("type", "")) == "projectile":
			proj = e2
	check_eq(int(proj.get("count", 1)), 3, "Cinder Shot is drilled: Scatter Coals throws three")
	var sv := fresh_world()
	var sim := MatchSim.new()
	sim.running = false
	sv.add_child(sim)
	sim.setup(built["config"])
	var f: Fighter = sim.fighters[0]
	check_eq(f.combat_style, "moves", "the fighter fights Movesets")
	check_eq(f.loadout, lo, "with the run's loadout on its four move inputs")
	sim.queue_free()


# =============================================================================================
# Migration (v1 -> v2) and older logs
# =============================================================================================

## A v1 save image of a run played under v1 rules: every decision of the run is a legacy one, then
## the v2 fields are removed exactly as a v0.9.17 build would never have written them.
func _v1_image(ctrl: RunController) -> Dictionary:
	var old: Dictionary = RunStore.json_stable(ctrl.state)
	old.erase("combat")
	old.erase("legacy_log")
	(old["start_cfg"] as Dictionary).erase("legacy_log")
	for p in old["players"]:
		(p as Dictionary).erase("moves")
	old["version"] = 1
	return old


func test_v1_runs_migrate_and_keep_their_log() -> void:
	var seed_value := _seed_with("elite")
	var ctrl := new_run({"seed": seed_value, "legacy_log": 100000})     # every decision under v1 rules
	check(_walk_to(ctrl, "elite"), "a v1-era run through an elite")
	ctrl.complete_fight(fake_result(ctrl))
	for e in ctrl.pending_for("p0"):
		check(str(e["kind"]) != "move", "v1 rules: no tutor")
	settle_node(ctrl)
	var old := _v1_image(ctrl)
	var store := RunStore.new(temp_dir("moves_migrate_%d" % Time.get_ticks_usec()))
	check_eq(Saves.write_json(store.slot_path("tester", "off_the_street"), RunStore.KIND, 1, old), OK, "a v1 save on disk")
	var r := store.load_slot("tester", "off_the_street", cat())
	check(bool(r["ok"]), "the v1 run loads: %s" % r["error"])
	check(bool(r["migrated"]), "flagged as migrated")
	if not bool(r["ok"]):
		return
	var st: Dictionary = r["state"]
	check_eq(int(st["version"]), 2, "now v2")
	check_eq(str(st["combat"]), "moves", "fighting Movesets")
	var n := (old["log"] as Array).size()
	check_eq(int(st["legacy_log"]), n, "its %d logged decisions are marked as made under v1 rules" % n)
	check_eq(int(st["start_cfg"]["legacy_log"]), n, "(also in its start config, so replays know)")
	var start := RunMoves.start_moves(cat(), "f_stoke")
	check_eq(st["players"][0]["moves"], start, "the player gets the moves a new run starts with")
	var kept: Dictionary = st.duplicate(true)
	kept.erase("combat")
	kept.erase("legacy_log")
	(kept["start_cfg"] as Dictionary).erase("legacy_log")
	for p in kept["players"]:
		(p as Dictionary).erase("moves")
	kept["version"] = 1
	check_eq(sig(kept), sig(old), "every other field is kept as it was")
	var v := RunController.verify(cat(), st)
	check(bool(v["ok"]), "the migrated run verifies: %s" % v["error"])
	# it plays on with today's rules: the next elite brings a tutor
	var resumed := RunController.from_state(cat(), st)
	check(not resumed.new_rules(), "nothing new has been decided yet")
	var guard := 0
	var saw_tutor := false
	while not resumed.is_over() and guard < 30:
		guard += 1
		var av := resumed.available_nodes()
		if av.is_empty():
			break
		var pick := str(av[0])
		for id in av:
			if resumed.visible_type(str(id)) == "elite":
				pick = str(id)
		resumed.choose_node(pick, "p0")
		if resumed.phase() == "fight" and str(resumed.session().get("type", "")) in ["elite", "boss"]:
			resumed.complete_fight(fake_result(resumed))
			for e2 in resumed.pending_for("p0"):
				saw_tutor = saw_tutor or str(e2["kind"]) == "move"
		settle_node(resumed)
		if saw_tutor:
			break
	check(saw_tutor, "after the migration an elite or boss offers a move tutor")
	_verifies(resumed, "migrated run played on")


func test_v0_saves_migrate_through_v1() -> void:
	var data := {"version": 0, "players": [{"id": "p0", "fighter": "f_stoke"}], "log": []}
	var m = RunStore.migrate(data.duplicate(true), 0, cat())
	check(m != null, "v0 migrates")
	if m == null:
		return
	check_eq(int(m["version"]), 2, "straight to v2")
	check(m.has("claims") and m.has("flags"), "the v0 -> v1 step still runs")
	check_eq(m["players"][0]["moves"], RunMoves.start_moves(cat(), "f_stoke"), "and the v1 -> v2 step")
	check(not m.has("legacy_log"), "an empty log needs no legacy marker")
	check(RunStore.migrate({"version": 3}, 3, cat()) == null, "a newer format is never migrated down")


# =============================================================================================
# Fight Camp: Sparring Partner, Film Study
# =============================================================================================

func test_fight_camp_sparring_partner_and_film_study() -> void:
	var c := cat()
	var sp: Dictionary = c.meta.get("meta_sparring_partner", {})
	var fs: Dictionary = c.meta.get("meta_film_study", {})
	check(bool(sp.get("meta_bonus", false)) and not (sp.get("costs", []) as Array).is_empty(), "Sparring Partner is a Cannery upgrade with a price")
	check(bool(fs.get("meta_bonus", false)) and not (fs.get("costs", []) as Array).is_empty(), "Film Study is a Cannery upgrade with a price")
	var prof := Profiles.default_profile("t", "T")
	CampaignProgression.ensure_fields(prof)
	prof["camp"]["clout"] = 1000
	check(bool(FightCamp.buy_upgrade(c, prof, "meta_sparring_partner")["ok"]), "Sparring Partner can be bought")
	var locked := FightCamp.buy_upgrade(c, prof, "meta_film_study")
	check(not bool(locked["ok"]) and str(locked["error"]).contains("locked"), "Film Study waits for Act 1 to be beaten")
	prof["camp"]["flags"]["beat_act1"] = true
	check(bool(FightCamp.buy_upgrade(c, prof, "meta_film_study")["ok"]), "and then sells")
	var meta := FightCamp.meta_levels(prof)
	var cfg := run_cfg("f_stoke", {"seed": 61, "variant": "fight_camp"})
	cfg["players"][0]["meta"] = meta
	var fc := RunController.start_run(c, cfg)
	var plain := new_run({"seed": 61, "variant": "fight_camp"})
	var m := _moves(fc)
	check_eq((m["learned"] as Array).size(), (_moves(plain)["learned"] as Array).size() + 1, "Sparring Partner: one more move learned")
	check_eq((m["drilled"] as Dictionary).size(), 1, "Film Study: one move drilled")
	for id in m["drilled"]:
		check(FURNACE.has(str(id)), "an equipped move (%s)" % id)
		check(((RunMoves.move_info(c, "f_stoke", str(id))["styles"]) as Dictionary).has(str(m["drilled"][id])), "with one of its styles")
	var again := RunController.start_run(c, cfg.duplicate(true))
	check_eq(sig(_moves(again)), sig(m), "the same card starts the same way (seeded)")
	var cfg_ots := run_cfg("f_stoke", {"seed": 61})
	cfg_ots["players"][0]["meta"] = meta
	var ots := RunController.start_run(c, cfg_ots)
	check_eq(_moves(ots), _moves(new_run({"seed": 61})), "Off the Street never carries Cannery upgrades")
	_verifies(fc, "Fight Camp start")


# =============================================================================================
# Autopilot
# =============================================================================================

func test_autopilot_learns_drills_and_equips_sensibly() -> void:
	var ctrl := new_run({"seed": 67})
	ctrl.state["phase"] = "reward"
	ctrl.state["node"] = {"id": "ap", "type": "rest", "pending": {"p0": []}, "fights": 0}
	ctrl.add_pending("p0", "move", {"n": 3, "source": "rest"})
	check(CampaignAutoPilot.settle(ctrl, ["p0"]), "the autopilot settles a move pick")
	check(ctrl.pending_for("p0").is_empty(), "it learned instead of skipping")
	check_eq((_moves(ctrl)["learned"] as Array).size(), 8, "Stoke now knows his whole pool")
	check_eq(_moves(ctrl)["equipped"], FURNACE, "with no build reason, it keeps the recommended loadout")
	ctrl.state["phase"] = "reward"
	ctrl.state["node"] = {"id": "ap2", "type": "rest", "pending": {"p0": []}, "fights": 0}
	ctrl.add_pending("p0", "drill", {"n": 2, "source": "rest"})
	CampaignAutoPilot.settle(ctrl, ["p0"])
	var drilled: Dictionary = _moves(ctrl)["drilled"]
	check_eq(drilled.size(), 1, "it drilled a move")
	for id in drilled:
		check(FURNACE.has(str(id)), "an equipped one (%s)" % id)
	# a build that favours the haymaker moves it into the loadout
	var p := ctrl.player("p0")
	p["techniques"] = ["tech_stoke_overcooked"]
	p["supplements"] = [{"id": "sup_tusk_dust", "stacks": 2}, {"id": "sup_double_wraps", "stacks": 1}]
	var best := CampaignAutoPilot.best_loadout(ctrl, "p0")
	check(best.has("furnace_haymaker") and best.has("ember_jab"), "a heavy build brings Furnace Haymaker (%s)" % str(best))
	check(CampaignAutoPilot.auto_equip(ctrl, "p0"), "and equips it")
	check(not CampaignAutoPilot.auto_equip(ctrl, "p0"), "then stays put")
	check_eq(_logged(ctrl, "equip").size(), 1, "one equip decision")
