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
	var partner_id := PARTNER if Content.creature(PARTNER) != null else ("f_gusto" if cid != "f_gusto" else "f_stoke")
	if Content.creature(partner_id) == null:
		partner_id = cid
	var mode := TutorialMode.new()
	mode.start_index = index
	mode.on_exit = on_exit if on_exit.is_valid() else Callable(Tutorial, "_default_exit")
	var t: Dictionary = Profiles.current.get("tutorial", {})
	t["times_offered"] = int(t.get("times_offered", 0)) + 1
	Profiles.current["tutorial"] = t
	return App.start_match({"arena": practice_cage(), "seed": 1234, "mode": mode, "overlay_script": OVERLAY,
		"audio_context": "tutorial", "music": "fight_night_poster",
		"rules": {"id": "tutorial", "name": "Tutorial", "mode": "tutorial", "round_time": 0.0, "rounds": 1, "intro_time": 0.0},
		"fighters": [
			{"creature": cid, "team": 0, "kind": "player", "name": "You"},
			{"creature": partner_id, "team": 1, "kind": "scripted", "name": "Kid Lamprey"}]})


static func _default_exit() -> void:
	if App.has_screen("tutorial_menu"):
		App.goto("tutorial_menu")
	elif App.has_screen("main_menu"):
		App.goto("main_menu")
	else:
		App.quit()


## The practice cage: the Gullet at 6 m across (ARENAS: "mini-Gullet").
static func practice_cage() -> ArenaDef:
	var d: Dictionary = Content.get_entry("arenas", "the_gullet").duplicate(true)
	d["id"] = "practice_cage"
	d["name"] = "Granny's Practice Cage"
	d["radius"] = 3.6
	d["spawns"] = [[0, -1.6, 0], [0, 1.6, 180]]
	d["props"] = []
	d["hazards"] = []
	return ArenaDef.from_dict(d, "core")


## Replaces {tokens} with live binding prompts and the fighter's own move names.
static func fill(text: String, c: CreatureDef) -> String:
	var out := text
	for a in ["light", "heavy", "guard", "dodge", "grab", "ability1", "ability2", "juice", "taunt", "pause", "target"]:
		out = out.replace("{%s}" % a, "[%s]" % Controls.prompt_for(a))
	var mv := "Left stick" if Controls.last_device == "gamepad" else "%s %s %s %s" % [Controls.prompt_for("move_up"), Controls.prompt_for("move_left"), Controls.prompt_for("move_down"), Controls.prompt_for("move_right")]
	out = out.replace("{move}", mv)
	if c:
		var names := []
		for slot in c.light_string.slice(0, 3):
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
