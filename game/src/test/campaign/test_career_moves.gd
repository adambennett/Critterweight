extends CareerTestCase
## v0.9.18 Career moves (CMP-08 + docs/design/MOVESET_COMBAT.md §5, §8): a new career starts with
## its fighter's recommended loadouts learned and the default one equipped; "Learn a move" and
## "Drill a move" are training weeks recorded in the career state; the loadout is validated and
## saved with the career; the bout builds the career fighter with the equipped loadout and the
## drilled styles composed into its creature (the same BuildApplier path as the career stats); the
## explicit v1 -> v2 save migration and the load-time repair of stale moves.
## Stoke is the fighter with an authored move pool here (eight moves, loadouts Furnace and Brawler,
## two styles per move); expectations are computed from the installed kit wherever they can be.

const STOKE := "f_stoke"


func after_each() -> void:
	store = null
	super.after_each()


func _kit(id := STOKE) -> CreatureDef:
	var c := CareerMoves.creature(cat(), id)
	check(c != null, "%s resolves" % id)
	return c


## The area effect of a pool move's inline MoveDef ({} when none).
func _area(c: CreatureDef, move_id: String) -> Dictionary:
	var pm: PoolMove = c.pool.get(move_id)
	if pm == null or pm.move == null:
		return {}
	for e in pm.move.effects:
		if typeof(e) == TYPE_DICTIONARY and str((e as Dictionary).get("type", "")) == "area":
			return e
	return {}


func test_new_careers_start_with_the_recommended_moves() -> void:
	var kit := _kit()
	if kit == null:
		return
	var ctrl := new_career()
	var mv: Dictionary = ctrl.state["moves"]
	var union := {}
	for lk in kit.loadouts:
		for id in (kit.loadouts[lk] as Dictionary)["moves"]:
			union[str(id)] = true
	check_eq((mv["learned"] as Array).size(), union.size(), "every move of both recommended loadouts is learned")
	for id2 in union:
		check((mv["learned"] as Array).has(id2), "%s learned" % id2)
	check_eq(mv["equipped"], kit.resolve_loadout([]), "the default loadout is equipped")
	check((mv["drilled"] as Dictionary).is_empty(), "nothing drilled yet")
	check_eq(int(ctrl.state["version"]), CareerState.VERSION, "a current-format career")
	check_eq(CareerState.VERSION, 2, "career saves are version 2 since v0.9.18")
	check(CareerState.check(cat(), ctrl.state).is_empty(), "valid: %s" % [CareerState.check(cat(), ctrl.state)])
	# Stoke's two loadouts share the basic string: seven of eight moves known, Fire Spin to learn
	check_eq(mv["equipped"], ["ember_jab", "flamethrower", "steam_vent", "stoke_the_fire"], "Stoke starts in Furnace")
	check_eq((mv["learned"] as Array).size(), 7, "Furnace + Brawler = seven moves")
	check(not (mv["learned"] as Array).has("fire_spin"), "Fire Spin is left to learn")
	# every playable fighter gets a valid start, authored pool or not
	for f in cat().available_fighters():
		var c := CareerMoves.creature(cat(), str(f))
		var st := CareerMoves.starting(c)
		check(not (st["equipped"] as Array).is_empty(), "%s starts with a loadout" % f)
		check_eq(st["equipped"], CareerMoves.default_loadout(c), "%s starts with its default loadout" % f)
		check(CareerMoves.same(CareerMoves.normalize(c, st), st), "%s: the starting moves are already normal" % f)


func test_learning_a_move_is_a_training_week() -> void:
	new_store()
	var ctrl := new_career({}, true)
	ctrl.state["injury"] = {"head": 30.0, "body": 0.0, "legs": 0.0}
	var rows := ctrl.train_rows()
	check_eq(str(rows[6]["id"]), "rest", "Rest keeps its place in the train grid")
	check_eq(str(rows[7]["id"]), "learn", "then Learn a move")
	check_eq(str(rows[8]["id"]), "drill", "then Drill a move")
	check(bool(rows[7]["available"]) and int(rows[7]["options"]) == 1, "one move to learn this week")
	var opts := ctrl.learn_options()
	check_eq(opts.size(), 1, "the only unlearned move is offered")
	check_eq(str(opts[0]["id"]), "fire_spin", "Fire Spin")
	check(str(opts[0]["name"]) == "Fire Spin" and str(opts[0]["desc"]).length() > 20, "with its name and description")
	var week := int(ctrl.state["week"])
	var pop := float(ctrl.state["pop"])
	var stats := sig(ctrl.state["stats"])
	var offers := sig(ctrl.state["offers"])
	check(not bool(ctrl.learn_move("flamethrower")["ok"]), "an already learned move is refused")
	check(not bool(ctrl.learn_move("nope")["ok"]), "an unknown move is refused")
	check_eq(int(ctrl.state["week"]), week, "refusals cost nothing")
	var r := ctrl.learn_move("fire_spin")
	check(bool(r["ok"]), "learned: %s" % r.get("error", ""))
	check_eq(str(r["focus"]), "learn", "the train report says what the week was for")
	check_eq(str(r["name"]), "Fire Spin", "and names the move")
	check((ctrl.state["moves"]["learned"] as Array).has("fire_spin"), "recorded in the career state")
	check_eq(int(ctrl.state["week"]), week + 1, "it takes the week")
	check_near(float(ctrl.state["pop"]), pop - 0.6, 0.0001, "an unbooked week costs popularity like any other")
	check(sig(ctrl.state["offers"]) != offers, "and brings new offers")
	check_eq(sig(ctrl.state["stats"]), stats, "no stat gains")
	check_near(float(ctrl.state["injury"]["head"]), 20.0, 0.0001, "injuries heal as in a training week")
	check_eq(str(ctrl.state["last_train"]["focus"]), "learn", "last_train records it")
	check(str(ctrl.news()[0]["text"]).contains("Fire Spin"), "news line")
	check(ctrl.learn_options().is_empty(), "nothing left to learn")
	check(not bool(ctrl.train_rows()[7]["available"]), "the Learn card says so")
	check(not bool(ctrl.learn_move("fire_spin")["ok"]), "learning it twice is refused")
	var back := store.load_slot("tester", 1, cat())
	check((back["state"]["moves"]["learned"] as Array).has("fire_spin"), "autosaved")
	# booked: a camp week like any other, written into the camp plan
	var b := new_career({"seed": 77})
	var o: Dictionary = b.state["offers"][0]
	check(b.accept(str(o["id"])), "booked")
	var left := int(b.booked()["weeks_left"])
	check(bool(b.learn_move("fire_spin")["ok"]), "learned in camp")
	check_eq(int(b.booked()["weeks_left"]), left - 1, "the camp counts down")
	check_eq(b.booked()["plan"], ["learn:fire_spin"], "the plan records the week")
	check_eq(b.fight_card()["plan"], ["Learned Fire Spin"], "and the fight card names it")
	b.state["booked"]["weeks_left"] = 0
	check(not bool(b.learn_move("fire_spin")["ok"]) and str(b.last_error).contains("fight week"), "no training on fight week")
	check(b.train_rows().is_empty(), "the grid (and its move cards) hide on fight week")


func test_learn_choices_are_a_few_and_stable_for_the_week() -> void:
	var kit := _kit()
	if kit == null:
		return
	var none := {"learned": ["ember_jab"], "equipped": ["ember_jab"], "drilled": {}}
	var a := CareerMoves.learn_options(kit, none, 4242, 3, 3)
	check_eq(a.size(), 3, "at most learn_choices moves are offered")
	check_eq(a, CareerMoves.learn_options(kit, none, 4242, 3, 3), "the same week offers the same moves")
	var all_pool := CareerMoves.learn_options(kit, none, 4242, 3, 0)
	check_eq(all_pool.size(), kit.pool.size() - 1, "no limit: every unlearned move")
	var differs := false
	for w in range(4, 30):
		if CareerMoves.learn_options(kit, none, 4242, w, 3) != a:
			differs = true
	check(differs, "other weeks offer other moves")
	for id in a:
		check(kit.pool.has(id) and str(id) != "ember_jab", "only unlearned pool moves (%s)" % id)
	check_eq(int(CareerDefaults.rules()["moves"]["learn_choices"]), 3, "three choices a week by default")


func test_drilling_a_move_is_a_permanent_training_week() -> void:
	new_store()
	var ctrl := new_career({}, true)
	var kit := ctrl.creature()
	var opts := ctrl.drill_options()
	var learned: Array = ctrl.state["moves"]["learned"]
	var pairs := 0
	for id in learned:
		pairs += (kit.pool[id] as PoolMove).styles.size()
	check_eq(opts.size(), pairs, "every style of every learned move can be drilled")
	var first: Dictionary = opts[0]
	check(str(first["style_name"]) != "" and str(first["desc"]) != "", "with the style's name and description")
	check(not bool(ctrl.drill_move("fire_spin", "inferno_ring")["ok"]), "an unlearned move cannot be drilled")
	check(not bool(ctrl.drill_move("flamethrower", "nope")["ok"]), "an unknown style is refused")
	var week := int(ctrl.state["week"])
	var r := ctrl.drill_move("flamethrower", "wide_nozzle")
	check(bool(r["ok"]), "drilled: %s" % r.get("error", ""))
	check_eq(str(r["style_name"]), "Wide Nozzle", "the report names the style")
	check_eq(ctrl.state["moves"]["drilled"], {"flamethrower": "wide_nozzle"}, "recorded in the career state")
	check_eq(int(ctrl.state["week"]), week + 1, "it takes the week")
	check_eq(str(ctrl.state["last_train"]["focus"]), "drill", "last_train records it")
	check(str(ctrl.news()[0]["text"]).contains("Wide Nozzle"), "news line")
	var again := ctrl.drill_move("flamethrower", "pressure_jet")
	check(not bool(again["ok"]) and str(again["error"]).contains("for good"), "a drill is permanent")
	check_eq(ctrl.state["moves"]["drilled"], {"flamethrower": "wide_nozzle"}, "unchanged")
	for o in ctrl.drill_options():
		check(str(o["move"]) != "flamethrower", "a drilled move is no longer offered")
	check_eq(ctrl.drill_options().size(), pairs - 2, "its two styles are gone from the choices")
	check(ctrl.loadout_rows()[1]["style_name"] == "Wide Nozzle", "the equipped list shows the drilled style")
	check_eq(store.load_slot("tester", 1, cat())["state"]["moves"]["drilled"], {"flamethrower": "wide_nozzle"}, "autosaved")


func test_loadout_changes_are_validated_and_saved() -> void:
	new_store()
	var ctrl := new_career({}, true)
	var brawler := ["ember_jab", "furnace_haymaker", "flare_rush", "cinder_shot"]
	check(ctrl.set_loadout(brawler), "a recommended loadout of learned moves: %s" % ctrl.last_error)
	check_eq(ctrl.state["moves"]["equipped"], brawler, "equipped")
	check_eq(ctrl.loadout_name(), "Brawler", "named after the recommended loadout")
	check_eq(store.load_slot("tester", 1, cat())["state"]["moves"]["equipped"], brawler, "saved with the career")
	var custom := ["ember_jab", "flamethrower", "cinder_shot"]
	check(ctrl.set_loadout(custom), "any learned moves with a basic strike: %s" % ctrl.last_error)
	check_eq(ctrl.loadout_name(), "Custom", "a custom loadout")
	var week := int(ctrl.state["week"])
	check_eq(int(ctrl.state["week"]), week, "equipping is free")
	check(not ctrl.set_loadout(["ember_jab", "fire_spin"]), "an unlearned move is refused")
	check(ctrl.last_error.contains("not learned"), "with the reason: %s" % ctrl.last_error)
	check(not ctrl.set_loadout(["flamethrower", "cinder_shot"]), "a loadout without a basic strike is refused")
	check(not ctrl.set_loadout(["ember_jab", "ember_jab"]), "a move twice is refused")
	check(not ctrl.set_loadout(["ember_jab", "flamethrower", "cinder_shot", "steam_vent", "flare_rush"]), "five moves are refused")
	check(not ctrl.set_loadout([]), "an empty loadout is refused")
	check_eq(ctrl.state["moves"]["equipped"], custom, "refusals change nothing")
	# a launched bout that was never settled is fought again with the moves it started with (D4)
	book(ctrl)
	check(ctrl.begin_fight(), "launched")
	check(not ctrl.set_loadout(brawler), "the loadout is locked until the bout is settled")
	check(ctrl.loadout_locked() != "", "and says why")
	check_eq(ctrl.state["moves"]["equipped"], custom, "unchanged")


## Deliverable 4: the bout is built with the equipped loadout on the career fighter's entry and the
## drilled styles composed into its creature (BuildApplier, before the stats); the rules keep the
## career preset's combat style (Movesets); the opponent and the plain content are untouched.
func test_the_bout_uses_the_career_loadout_and_drilled_styles() -> void:
	var ctrl := new_career({"seed": 2023})
	var base := _kit()
	if base == null:
		return
	check(bool(ctrl.drill_move("flamethrower", "wide_nozzle")["ok"]), "drill Flamethrower")
	check(bool(ctrl.drill_move("furnace_haymaker", "pressure_valve")["ok"]), "drill Furnace Haymaker")
	check(bool(ctrl.drill_move("ember_jab", "bellows")["ok"]), "drill Ember Jab")
	var lo := ["ember_jab", "furnace_haymaker", "flamethrower", "cinder_shot"]
	check(ctrl.set_loadout(lo), "equip: %s" % ctrl.last_error)
	book(ctrl, {})
	var built := ctrl.fight_config({"player_kind": "bot"})
	check((built["errors"] as PackedStringArray).is_empty(), "builds: %s" % [built["errors"]])
	if not (built["errors"] as PackedStringArray).is_empty():
		return
	var cfg: Dictionary = built["config"]
	check_eq(str(cfg["rules"]["combat"]), "moves", "the bout keeps the career preset's combat style: Movesets")
	var me: Dictionary = cfg["fighters"][0]
	check_eq(me["loadout"], lo, "the fighter entry carries the equipped loadout")
	check(not me.has("styles"), "styles are composed into the creature, never sent as an entry key")
	var c: CreatureDef = me["creature"]
	check(c.is_valid(), "the composed creature is valid: %s" % [c.errors])
	check_eq(c.resolve_loadout(lo), lo, "the loadout is valid for the composed creature")
	# Wide Nozzle: a 60 degree, 2.4 m fan (the authored jet is 40 degrees, 3.2 m)
	var area := _area(c, "flamethrower")
	var base_area := _area(base, "flamethrower")
	check_near(float(base_area.get("cone_deg", 0.0)), 40.0, 0.001, "precondition: the stock flame")
	check_near(float(area.get("cone_deg", 0.0)), 60.0, 0.001, "Wide Nozzle widens the cone")
	check_near(float(area.get("radius", 0.0)), 2.4, 0.001, "and shortens it")
	# Pressure Valve: the heavy charges in half the time
	check_near(c.moves["heavy"].charge_time, base.moves["heavy"].charge_time * 0.5, 0.0001, "Pressure Valve halves the charge time")
	# Bellows: faster punches (time_scale 0.9) that cost more stamina (x1.25), then the stats on top
	check_near(c.moves["l1"].duration, base.moves["l1"].duration * 0.9, 0.0001, "Bellows speeds up the jab")
	check_near(c.moves["l1"].stamina, base.moves["l1"].stamina * 1.25, 0.0001, "and makes it cost more")
	var sources: Array = []
	var comp := CareerBuild.compose(cat(), ctrl.rules, STOKE, ctrl.state["stats"], {}, "x", CareerMoves.drill_effects(base, ctrl.state["moves"]["drilled"]))
	sources = comp["sources"]
	check_eq(sources, ["drill:ember_jab:bellows", "drill:furnace_haymaker:pressure_valve", "drill:flamethrower:wide_nozzle", "career"],
		"the drills come first (pool order), then the career stats block")
	check((comp["warnings"] as Array).is_empty(), "every style patch matched: %s" % [comp["warnings"]])
	# a sim built from the config equips exactly that loadout on the career fighter
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	sim.setup(cfg)
	check_eq(sim.combat_style(), "moves", "the sim plays Movesets")
	check_eq(sim.fighters[0].loadout, lo, "the career fighter fights with its loadout")
	check_eq(sim.fighters[1].loadout, (cfg["fighters"][1]["creature"] as CreatureDef).resolve_loadout([]), "the opponent with its default one")
	# nothing leaks: the stock creature and an opponent of the same kind are untouched
	check_near(float(_area(Content.creature(STOKE), "flamethrower").get("cone_deg", 0.0)), 40.0, 0.001, "Content's Stoke keeps the stock flame")
	var them := CareerBuild.compose(cat(), ctrl.rules, STOKE, ctrl.state["stats"], {}, "career_opponent")
	check_near(float(_area(them["creature"], "flamethrower").get("cone_deg", 0.0)), 40.0, 0.001, "an opponent Stoke has no drills")
	# the drilled styles also hold with stats far from 0.5 (the style is applied before the stats)
	var maxed := {}
	for k in CareerDefaults.STATS:
		maxed[k] = 0.99
	var strong := CareerBuild.compose(cat(), ctrl.rules, STOKE, maxed, {}, "x", CareerMoves.drill_effects(base, {"flamethrower": "pressure_jet"}))
	check_near(float(_area(strong["creature"], "flamethrower").get("cone_deg", 0.0)), 22.0, 0.001, "Pressure Jet narrows the cone")


func test_v1_saves_migrate_explicitly() -> void:
	var ctrl := new_career({"seed": 31})
	var v1: Dictionary = ctrl.state.duplicate(true)
	v1.erase("moves")
	v1["version"] = 1
	var m = CareerState.migrate(v1, 1, cat())
	if not check(typeof(m) == TYPE_DICTIONARY, "a v1 career migrates"):
		return
	var d: Dictionary = m
	check_eq(int(d["version"]), 2, "to version 2")
	check_eq(int(d["migrated_from"]), 1, "recording where it came from")
	check_eq(d["moves"], CareerMoves.starting(ctrl.creature()), "with the starting moves of a new career")
	for k in v1:
		if str(k) != "version":
			check_eq(sig(d[k]), sig(v1[k]), "%s kept" % k)
	check(not v1.has("moves") and int(v1["version"]) == 1, "the input is not modified")
	check(CareerState.check(cat(), d).is_empty(), "the migrated career is valid: %s" % [CareerState.check(cat(), d)])
	# no catalog (or the fighter not installed): empty moves, filled in on load by repair()
	var bare = CareerState.migrate(v1, 1)
	check_eq((bare as Dictionary)["moves"], CareerMoves.empty(), "without a catalog the moves start empty")
	var c2 := CareerController.from_state(cat(), (bare as Dictionary).duplicate(true))
	check(c2.repairs.has("moves updated"), "repaired on load")
	check_eq(c2.state["moves"], CareerMoves.starting(ctrl.creature()), "to the starting moves")
	# through the store: a v1 file on disk
	new_store()
	var path := store.slot_path("tester", 2)
	check_eq(Saves.write_json(path, CareerStore.KIND, 1, v1), OK, "a v1 career on disk")
	var r := CareerController.load_career(cat(), store, "tester", 2)
	check(bool(r["ok"]) and bool(r["load"]["migrated"]), "loads, migrated: %s" % r["error"])
	if bool(r["ok"]):
		var lc: CareerController = r["ctrl"]
		check_eq(lc.state["moves"], CareerMoves.starting(ctrl.creature()), "with its starting moves")
		check_eq(Saves.read_json(path, CareerStore.KIND, 1)["version"], 1, "the file stays v1 until the next save")
		check(bool(lc.train("power")["ok"]), "and plays on")
		var after := Saves.read_json(path, CareerStore.KIND, CareerState.VERSION)
		check(bool(after["ok"]) and int(after["version"]) == 2 and not bool(after["migrated"]), "saved as version 2")
	# a future format is never migrated down
	check(CareerState.migrate(v1, 3, cat()) == null, "unknown versions are refused (the file is kept)")


## Load-time repair: moves renamed or removed by a content update are dropped, a pool that replaced a
## derived one starts over, an invalid loadout falls back to the default (whose moves are learned).
func test_stale_moves_are_repaired_on_load() -> void:
	var ctrl := new_career({"seed": 41})
	var kit := ctrl.creature()
	var start := CareerMoves.starting(kit)
	check(CareerMoves.same(CareerMoves.normalize(kit, start), start), "valid moves are left alone")
	var stale := {"learned": ["ember_jab", "flamethrower", "gone_move", "cinder_shot"], "equipped": ["ember_jab", "gone_move"],
		"drilled": {"flamethrower": "wide_nozzle", "gone_move": "x", "cinder_shot": "no_such_style"}}
	var n := CareerMoves.normalize(kit, stale)
	check(not (n["learned"] as Array).has("gone_move"), "unknown moves are dropped")
	check_eq(n["equipped"], CareerMoves.default_loadout(kit), "an invalid loadout falls back to the default one")
	for id in n["equipped"]:
		check((n["learned"] as Array).has(id), "%s (default loadout) is learned" % id)
	check_eq(n["drilled"], {"flamethrower": "wide_nozzle"}, "only drills of known moves and styles survive")
	# a derived Classic pool replaced by an authored one: none of the old ids exist any more
	var derived := {"learned": ["basic", "heavy", "ability1", "ability2"], "equipped": ["basic", "heavy", "ability1", "ability2"], "drilled": {}}
	check_eq(CareerMoves.normalize(kit, derived), start, "starts over with the starting moves")
	# malformed blocks
	check_eq(CareerMoves.normalize(kit, "junk"), start, "a non-object becomes the starting moves")
	check_eq(CareerMoves.normalize(kit, {"learned": "x", "equipped": 3, "drilled": []}), start, "so does a malformed one")
	check(CareerState.blocking(CareerState.check(cat(), _with_moves(ctrl.state, "junk"))).is_empty(), "malformed moves never block loading")
	check(not CareerState.check(cat(), _with_moves(ctrl.state, "junk")).is_empty(), "but are reported")
	# on load
	new_store()
	var st: Dictionary = ctrl.state.duplicate(true)
	st["moves"] = stale
	check_eq(store.save(st, "tester", 1), OK, "a career with stale moves on disk")
	var r := CareerController.load_career(cat(), store, "tester", 1)
	check(bool(r["ok"]), "it loads: %s" % r["error"])
	if bool(r["ok"]):
		var c: CareerController = r["ctrl"]
		check(c.repairs.has("moves updated"), "the moves were repaired")
		check_eq(c.state["moves"], n, "as normalize() says")
		check_eq(store.load_slot("tester", 1, cat())["state"]["moves"], n, "and the repair was saved")
	# a fresh load of a valid career repairs nothing
	var fresh := new_career({"seed": 42, "slot": 2}, true)
	var r2 := CareerController.load_career(cat(), store, "tester", 2)
	check(bool(r2["ok"]) and (r2["ctrl"] as CareerController).repairs.is_empty(), "nothing to repair on a valid career")
	check_eq((r2["ctrl"] as CareerController).state["moves"], fresh.state["moves"], "same moves")


func _with_moves(st: Dictionary, mv) -> Dictionary:
	var d: Dictionary = st.duplicate(true)
	d["moves"] = mv
	return d
