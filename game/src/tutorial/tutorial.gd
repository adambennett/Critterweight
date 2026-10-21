class_name Tutorial
## Entry points and text helpers for Granny Haymaker's tutorial (UI-12, docs/design/
## ANNOUNCER_AND_TUTORIAL.md §2). Exercises are data (content/core/tutorial/exercises.json); the
## logic lives in TutorialMode and the on-screen coach in TutorialOverlay.
##
##   Tutorial.start()            first exercise with the default fighter (Stoke)
##   Tutorial.start(4, "f_dozer") a single exercise with a chosen fighter
##   Tutorial.exercises(course)  ordered exercise dictionaries (title, goal, ...) of a course
##
## Two courses (v0.9.18, docs/design/MOVESET_COMBAT.md §9): "moves" teaches the fighter's equipped
## moves (Movesets, the default), "classic" is the v0.9.17 course, unchanged (the Classic rule, and
## Varga, whose Cage Rules lessons are written for his own layout). An exercise names its course
## with "style" ("moves" | "classic"; none = both) and its place with "order" ("moves_order" in the
## Movesets course when it differs). Movesets lines use tokens for the equipped moves: {basic},
## {basic_name}, {string_names}, {finisher_name}, {dash_name}, {charge}, {charge_name},
## {charge_full}, {sustain}, {sustain_name}, {sustain_max}, {special}, {special_name},
## {special_cat}, {ultimate}, {ultimate_name}, {moves}: the input ones resolve to the live binding
## of the slot the move is equipped in ("[X]"), so a custom loadout reads right too.

const DEFAULT_FIGHTER := "f_stoke"
const PARTNER := "npc_kid_lamprey"
const OVERLAY := "res://src/tutorial/tutorial_overlay.gd"
const COURSES := ["moves", "classic"]


## The course a fighter takes: Movesets for every fighter in Movesets except martial fighters (Varga
## keeps his Cage Rules lessons); Classic for the Classic rule.
static func course_for(c: CreatureDef, combat := "moves") -> String:
	if combat == "classic" or c == null or c.tags.has("martial"):
		return "classic"
	return "moves"


static func exercises(course := "moves") -> Array:
	var out := []
	for id in Content.ids("tutorial"):
		var e := Content.get_entry("tutorial", id)
		if e.has("order") and in_course(e, course):
			out.append(e)
	var key := "moves_order" if course == "moves" else "order"
	out.sort_custom(func(a, b): return int(a.get(key, a["order"])) < int(b.get(key, b["order"])))
	return out


## Whether an exercise belongs to a course ("style" absent = both courses).
static func in_course(e: Dictionary, course: String) -> bool:
	var style := str(e.get("style", ""))
	return style == "" or style == course


static func completed_ids() -> Array:
	var t: Dictionary = Profiles.current.get("tutorial", {})
	return t.get("exercises", [])


## Starts the tutorial at exercise `index` (0-based, in the fighter's course). `exit_to` =
## {screen: App screen name, params} is where the player goes when they leave (the Cannery:
## {"screen": "hub", "params": {spot}}); default: back to the tutorial menu or the main menu. A
## plain route, never a Callable: a static holding a lambda crashes the engine at exit if the game
## is closed during the lesson. `combat`: "moves" (the player's saved loadout for the fighter is the
## one taught) or "classic".
static func start(index := 0, creature_id := "", exit_to: Dictionary = {}, combat := "moves") -> MatchScene:
	var cid := creature_id if creature_id != "" and Content.creature(creature_id) != null else DEFAULT_FIGHTER
	if Content.creature(cid) == null:
		cid = str(Content.playable_creatures()[0])
	var partner_id := partner_for(cid)
	_exit_route = exit_to.duplicate(true)
	var t: Dictionary = Profiles.current.get("tutorial", {})
	t["times_offered"] = int(t.get("times_offered", 0)) + 1
	Profiles.current["tutorial"] = t
	var style := "classic" if combat == "classic" else "moves"
	# plain data only (no mode object): MatchFlow keeps it for the pause menu's Restart
	return MatchFlow.launch({"arena": "practice_cage", "seed": 1234, "overlay_script": OVERLAY,
		"audio_context": "tutorial", "music": "fight_night_poster", "no_record": true,
		"rules": {"id": "tutorial", "name": "Tutorial", "mode": "tutorial", "combat": style, "round_time": 0.0, "rounds": 1, "intro_time": 0.0,
			"tutorial_start": index},
		"fighters": [
			{"creature": cid, "team": 0, "kind": "player", "name": Profiles.player_name(), "loadout": MovesUi.saved_loadout(cid)},
			{"creature": partner_id, "team": 1, "kind": "scripted", "name": "Kid Lamprey"}]})


## The creature Kid Lamprey spars in: his own kit (`npc_kid_lamprey`) when it exists, else a
## roster stand-in, else the player's own fighter. The stand-in is the first of STAND_INS that
## isn't the player's fighter and stands at most MAX_HEIGHT_RATIO times the player's height:
## Gusto's wing and kick strikes are authored at a 1.84 m bird's neck height, and size matching
## can't bring them down onto a body under ~1.15 m (Jitters, or Dredge behind his raised claws),
## so short fighters spar with Stoke, whose straight punches reach them. If no stand-in fits, the
## closest in height. The tests use this too, so they always run the pairing the game launches.
const STAND_INS := ["f_gusto", "f_stoke"]
const MAX_HEIGHT_RATIO := 1.6


static func partner_for(player_id: String) -> String:
	if Content.creature(PARTNER) != null:
		return PARTNER
	var me := Content.creature(player_id)
	var best := ""
	var best_ratio := INF
	for stand_in in STAND_INS:
		var c := Content.creature(stand_in)
		if stand_in == player_id or c == null:
			continue
		var ratio := c.body.height / maxf(0.3, me.body.height) if me else 1.0
		if ratio <= MAX_HEIGHT_RATIO:
			return stand_in
		if ratio < best_ratio:
			best_ratio = ratio
			best = stand_in
	return best if best != "" else player_id


## TutorialHook launcher (the tutorial menu): lesson 1 runs the whole course in order, any other
## lesson is a single replay.
static func start_lesson(lesson_id: String, creature_id := "", combat := "moves") -> void:
	var cid := creature_id if creature_id != "" and Content.creature(creature_id) != null else DEFAULT_FIGHTER
	var list := exercises(course_for(Content.creature(cid), combat))
	var idx := 0
	for i in list.size():
		if str(list[i].get("id", "")) == lesson_id:
			idx = i
	start(idx, creature_id, {}, combat)


## Where the running lesson leaves to ({screen, params}; {} = the default exit). Plain data only:
## a static holding a lambda crashes Godot 4.5.1 at exit (AGENTS.md).
static var _exit_route: Dictionary = {}


static func forget_exit() -> void:
	clear_exit_route()


static func exit_tutorial() -> void:
	var route := _exit_route
	_exit_route = {}
	var screen := str(route.get("screen", ""))
	if screen != "" and App.has_screen(screen):
		App.goto(screen, route.get("params", {}))
	else:
		_default_exit()


## Forgets where the current lesson would return to (leaving to the main menu, quitting the game).
static func clear_exit_route() -> void:
	_exit_route = {}


static func _default_exit() -> void:
	if App.has_screen("tutorial_menu"):
		App.goto("tutorial_menu")
	elif App.has_screen("main_menu"):
		App.goto("main_menu")
	else:
		App.quit()


## The practice cage (content/core/arenas/practice_cage.json): a small Gullet ("mini-Gullet").
static func practice_cage() -> ArenaDef:
	var a := Content.arena("practice_cage")
	return a if a else Content.arena("the_gullet")


## Replaces {tokens} with live binding prompts and the fighter's own move names. `loadout`: the
## equipped Movesets moves the Movesets tokens name (empty: the fighter's default loadout).
static func fill(text: String, c: CreatureDef, loadout: Array = []) -> String:
	var out := _fill_classic(text, c)
	if c != null and out.contains("{"):
		out = _fill_moves(out, c, loadout)
	return out


## Words for a Movesets token whose move the loadout lacks (that lesson is skipped and says so).
const MOVE_TOKEN_FALLBACK := {"{basic}": "your basic strike's button", "{basic_name}": "your basic strike",
	"{string_names}": "the string", "{finisher_name}": "the finisher", "{dash_name}": "the dash strike",
	"{charge}": "its button", "{charge_name}": "a hold-to-charge move", "{charge_full}": "the full charge",
	"{sustain}": "its button", "{sustain_name}": "a hold-to-sustain move", "{sustain_max}": "a couple of",
	"{special}": "its button", "{special_name}": "a special move", "{special_cat}": "special",
	"{ultimate_name}": "your Ultimate", "{moves}": "your four moves"}


## The equipped moves the Movesets lessons teach, from loadout `lo`: "basic" (the basic strike),
## "charge" (the first hold-to-charge move), "sustain" (the first hold-to-sustain move) and
## "special" (the special to land: an offensive special-role move the other lessons don't teach
## first, else any offensive one, else a counter / support / utility move, which is used rather
## than landed) -> {id, slot ("m1".."m4"), action (its Controls action), button (FighterInput),
## pm}. A lesson whose move is missing is skipped with its adapted line.
static func moves_kit(c: CreatureDef, lo: Array) -> Dictionary:
	var entries: Array = []
	for i in mini(lo.size(), Fighter.MOVE_SLOTS.size()):
		var pm: PoolMove = c.pool.get(str(lo[i])) if c else null
		if pm != null:
			entries.append({"id": pm.id, "slot": Fighter.MOVE_SLOTS[i], "action": MovesUi.slot_action(i), "button": Fighter.MOVE_BUTTONS[i], "pm": pm})
	var kit := {}
	for e in entries:
		var pm: PoolMove = e["pm"]
		if pm.role == "basic" and not kit.has("basic"):
			kit["basic"] = e
		elif pm.hold == "charge" and pm.move != null and pm.move.charge_time > 0.0 and not kit.has("charge"):
			kit["charge"] = e
		elif pm.hold == "sustain" and not kit.has("sustain"):
			kit["sustain"] = e
	var taught: Array = []
	for k in ["charge", "sustain"]:
		if kit.has(k):
			taught.append(str((kit[k] as Dictionary)["id"]))
	var best := -1
	for e in entries:
		var pm: PoolMove = e["pm"]
		if pm.role == "basic":
			continue
		var score := 0
		if pm.category in MovesUi.OFFENSIVE and pm.role != "support":
			score += 4
		if not taught.has(pm.id):
			score += 2
		if pm.role == "special":
			score += 1
		if score > best:
			best = score
			kit["special"] = e
	return kit


static func _fill_moves(text: String, c: CreatureDef, loadout: Array) -> String:
	var lo: Array = loadout if not loadout.is_empty() else c.resolve_loadout([])
	var kit := moves_kit(c, lo)
	var out := text
	if kit.has("basic"):
		var b: Dictionary = kit["basic"]
		var bp: PoolMove = b["pm"]
		var steps := MovesUi.string_names(bp, c)
		out = out.replace("{basic}", MovesUi.input_text(str(b["action"])))
		out = out.replace("{basic_name}", bp.display_name)
		out = out.replace("{string_names}", " – ".join(steps))
		out = out.replace("{finisher_name}", steps[steps.size() - 1] if steps.size() > 1 else bp.display_name)
		if bp.dash != "" and c.moves.has(bp.dash):
			out = out.replace("{dash_name}", (c.moves[bp.dash] as MoveDef).display_name)
	if kit.has("charge"):
		var ch: Dictionary = kit["charge"]
		var cp: PoolMove = ch["pm"]
		out = out.replace("{charge}", MovesUi.input_text(str(ch["action"])))
		out = out.replace("{charge_name}", cp.display_name)
		var full := MovesUi.charged_name(cp)
		out = out.replace("{charge_full}", full if full != "" else "a full charge")
	if kit.has("sustain"):
		var su: Dictionary = kit["sustain"]
		var sp: PoolMove = su["pm"]
		out = out.replace("{sustain}", MovesUi.input_text(str(su["action"])))
		out = out.replace("{sustain_name}", sp.display_name)
		out = out.replace("{sustain_max}", MovesUi.num(sp.max_hold))
	if kit.has("special"):
		var spc: Dictionary = kit["special"]
		var xp: PoolMove = spc["pm"]
		out = out.replace("{special}", MovesUi.input_text(str(spc["action"])))
		out = out.replace("{special_name}", xp.display_name)
		out = out.replace("{special_cat}", MovesUi.category_name(xp.category).to_lower())
	out = out.replace("{ultimate}", MovesUi.input_text(MartialControls.action("juice", c)))
	if c.abilities.has("juice"):
		out = out.replace("{ultimate_name}", (c.abilities["juice"] as MoveDef).display_name)
	if out.contains("{moves}"):
		var parts := PackedStringArray()
		for i in mini(lo.size(), 4):
			var pm: PoolMove = c.pool.get(str(lo[i]))
			if pm:
				parts.append("%s %s" % [MovesUi.input_text(MovesUi.slot_action(i)), pm.display_name])
		out = out.replace("{moves}", ", ".join(parts))
	for k in MOVE_TOKEN_FALLBACK:
		out = out.replace(str(k), str(MOVE_TOKEN_FALLBACK[k]))
	return out


static func _fill_classic(text: String, c: CreatureDef) -> String:
	var out := text
	for a in ["light", "heavy", "guard", "dodge", "grab", "ability1", "ability2", "juice", "taunt", "pause", "target"]:
		var action: String = a
		if c and c.tags.has("martial"):
			action = {"light": "mma_lh", "heavy": "mma_rl"}.get(a, "mma_" + a if MartialControls.MAP.has("mma_" + a) else a)
		out = out.replace("{%s}" % a, "[%s]" % Controls.prompt_for(action))
	for action in MartialControls.MAP:
		out = out.replace("{%s}" % action, "[%s]" % Controls.prompt_for(action))
	var mv := "Left stick" if Controls.last_device == "gamepad" else "%s %s %s %s" % [Controls.prompt_for("move_up"), Controls.prompt_for("move_left"), Controls.prompt_for("move_down"), Controls.prompt_for("move_right")]
	out = out.replace("{move}", mv)
	if c:
		var names := []
		for slot in TutorialMode.string_slots(c):     # the string the Hands drill checks
			if c.moves.has(slot):
				names.append((c.moves[slot] as MoveDef).display_name)
		out = out.replace("{l_names}", " – ".join(names) if not names.is_empty() else "jab, cross, hook")
		out = out.replace("{heavy_name}", (c.moves["heavy"] as MoveDef).display_name if c.moves.has("heavy") else "Heavy")
		var charged: MoveDef = c.moves.get("heavy_charged", c.moves.get("heavy"))
		out = out.replace("{charged_name}", charged.display_name if charged else "the charged one")
		out = out.replace("{ability1_name}", (c.abilities["ability1"] as MoveDef).display_name if c.abilities.has("ability1") else "your first trick")
		out = out.replace("{juice_name}", (c.abilities["juice"] as MoveDef).display_name if c.abilities.has("juice") else "the JUICE")
	return out


static func jab_for(creature_id: String) -> String:
	var j: Dictionary = Content.get_entry("tutorial", "tutorial_jabs").get("jabs", {})
	return str(j.get(creature_id, ""))
