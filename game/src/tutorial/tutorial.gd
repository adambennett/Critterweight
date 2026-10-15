class_name Tutorial
## Entry points and text helpers for Granny Haymaker's tutorial (UI-12, docs/design/
## ANNOUNCER_AND_TUTORIAL.md §2). Exercises are data (content/core/tutorial/exercises.json); the
## logic lives in TutorialMode and the on-screen coach in TutorialOverlay.
##
##   Tutorial.start()            first exercise with the default fighter (Stoke)
##   Tutorial.start(4, "f_dozer") a single exercise with a chosen fighter
##   Tutorial.exercises()        ordered exercise dictionaries (title, goal, ...)

const DEFAULT_FIGHTER := "f_stoke"
const PARTNER := "npc_kid_lamprey"
const OVERLAY := "res://src/tutorial/tutorial_overlay.gd"


static func exercises() -> Array:
	var out := []
	for id in Content.ids("tutorial"):
		var e := Content.get_entry("tutorial", id)
		if e.has("order"):
			out.append(e)
	out.sort_custom(func(a, b): return int(a["order"]) < int(b["order"]))
	return out


static func completed_ids() -> Array:
	var t: Dictionary = Profiles.current.get("tutorial", {})
	return t.get("exercises", [])


## Starts the tutorial at exercise `index` (0-based). `on_exit` is called when the player
## leaves (default: back to the tutorial menu or the main menu).
static func start(index := 0, creature_id := "", on_exit: Callable = Callable()) -> MatchScene:
	var cid := creature_id if creature_id != "" and Content.creature(creature_id) != null else DEFAULT_FIGHTER
	if Content.creature(cid) == null:
		cid = str(Content.playable_creatures()[0])
	var partner_id := partner_for(cid)
	_exit_override = on_exit
	var t: Dictionary = Profiles.current.get("tutorial", {})
	t["times_offered"] = int(t.get("times_offered", 0)) + 1
	Profiles.current["tutorial"] = t
	# plain data only (no mode object): MatchFlow keeps it for the pause menu's Restart
	return MatchFlow.launch({"arena": "practice_cage", "seed": 1234, "overlay_script": OVERLAY,
		"audio_context": "tutorial", "music": "fight_night_poster", "no_record": true,
		"rules": {"id": "tutorial", "name": "Tutorial", "mode": "tutorial", "round_time": 0.0, "rounds": 1, "intro_time": 0.0,
			"tutorial_start": index},
		"fighters": [
			{"creature": cid, "team": 0, "kind": "player", "name": Profiles.player_name()},
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
static func start_lesson(lesson_id: String, creature_id := "") -> void:
	var list := exercises()
	var idx := 0
	for i in list.size():
		if str(list[i].get("id", "")) == lesson_id:
			idx = i
	start(idx, creature_id)


static var _exit_override: Callable = Callable()


static func exit_tutorial() -> void:
	var cb := _exit_override
	_exit_override = Callable()
	if cb.is_valid():
		cb.call()
	else:
		_default_exit()


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


## Replaces {tokens} with live binding prompts and the fighter's own move names.
static func fill(text: String, c: CreatureDef) -> String:
	var out := text
	for a in ["light", "heavy", "guard", "dodge", "grab", "ability1", "ability2", "juice", "taunt", "pause", "target"]:
		out = out.replace("{%s}" % a, "[%s]" % Controls.prompt_for(a))
	var mv := "Left stick" if Controls.last_device == "gamepad" else "%s %s %s %s" % [Controls.prompt_for("move_up"), Controls.prompt_for("move_left"), Controls.prompt_for("move_down"), Controls.prompt_for("move_right")]
	out = out.replace("{move}", mv)
	if c:
		var names := []
		for slot in TutorialMode.string_slots(c):     # the string the Hands drill checks
			if c.moves.has(slot):
				names.append((c.moves[slot] as MoveDef).display_name)
		out = out.replace("{l_names}", " – ".join(names) if not names.is_empty() else "jab, cross, hook")
		out = out.replace("{heavy_name}", (c.moves["heavy"] as MoveDef).display_name if c.moves.has("heavy") else "Heavy")
		out = out.replace("{ability1_name}", (c.abilities["ability1"] as MoveDef).display_name if c.abilities.has("ability1") else "your first trick")
		out = out.replace("{juice_name}", (c.abilities["juice"] as MoveDef).display_name if c.abilities.has("juice") else "the JUICE")
	return out


static func jab_for(creature_id: String) -> String:
	var j: Dictionary = Content.get_entry("tutorial", "tutorial_jabs").get("jabs", {})
	return str(j.get(creature_id, ""))
