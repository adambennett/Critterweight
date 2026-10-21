extends Screen
## Tutorial lesson list ("tutorial_menu") — Granny Haymaker's corner. Lessons come from Content kind
## "tutorial" when a package provides them, else TutorialHook.DEFAULT_LESSONS (ANNOUNCER_AND_TUTORIAL
## §2.1). Starting a lesson calls TutorialHook.launch(lesson_id, fighter_id, combat): the tutorial
## owner wires TutorialHook.launcher. Until then the menu explains that lessons are not playable in
## this build and offers Practice instead. Entry point: App.goto/push("tutorial_menu").
## v0.9.18: the fighter and the combat style pick the course. Movesets (the default) teaches the
## fighter's equipped moves (the player's saved loadout, else the recommended one); Classic keeps
## the v0.9.17 lessons; Varga's lessons teach his Cage Rules layout in either style.

var _scroll: FocusScroll
var _help: HelpPanel
var _fighter := ""
var _combat := "moves"


func on_enter(_p: Dictionary) -> void:
	MenuBackdrop.ensure()
	add_backdrop_gradient(0.97, 0.7)
	var ids := Content.playable_creatures()
	_fighter = Tutorial.DEFAULT_FIGHTER if ids.has(Tutorial.DEFAULT_FIGHTER) or ids.is_empty() else str(ids[0])
	var f := build_frame("Granny's corner", "Tutorial")
	(f["prompts"] as PromptBar).set_prompts(std_prompts())
	var body: VBoxContainer = f["body"]
	var cols := UiTheme.hbox(UiTheme.GAP_L)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	var lp := UiTheme.panel("PanelSolid", 18.0)
	lp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lp.size_flags_stretch_ratio = 1.4
	cols.add_child(lp)
	_scroll = FocusScroll.new(6)
	lp.add_child(_scroll)
	var right := UiTheme.vbox(UiTheme.GAP_M)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var quote := UiTheme.panel("PanelPoster")
	var qv := UiTheme.vbox(UiTheme.GAP_S)
	qv.add_child(UiTheme.label("GRANNY HAYMAKER, HEAD COACH", "Eyebrow"))
	qv.add_child(UiTheme.label("\"Stick moves you. Camera does the thinking. Everything after that is timing.\"", "H3", true))
	quote.add_child(qv)
	right.add_child(quote)
	if not TutorialHook.is_wired():
		var banner := UiTheme.panel("PanelBanner")
		var br := UiTheme.hbox(UiTheme.GAP_S)
		br.add_child(UiIcons.rect("warning", 34, UiTheme.WARNING))
		var bl := UiTheme.label("Lessons are not playable in this build yet. Practice mode is.", "BodyStrong", true)
		bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		br.add_child(bl)
		banner.add_child(br)
		right.add_child(banner)
	_help = HelpPanel.new(_scroll, "Lesson")
	right.add_child(_help)
	_build()
	play_intro()


## The course the chosen fighter and style take ("moves" | "classic").
func course() -> String:
	return Tutorial.course_for(Content.creature(_fighter), _combat)


func _build(focus_key := "") -> void:
	_scroll.clear()
	var c := _scroll.content
	var done := bool((Profiles.current.get("tutorial", {}) as Dictionary).get("completed", false))
	var ids := Content.playable_creatures()
	if not ids.is_empty():
		var names: Array[String] = []
		for id in ids:
			names.append(str(Content.get_entry("creatures", str(id)).get("name", id)))
		var fr := OptionRow.new("Fighter")
		fr.setup(ids, names, _fighter)
		fr.set_meta("focus_key", "fighter")
		fr.set_help("Fighter", "Who takes the lessons. In Movesets Granny teaches this fighter's own moves: the four you equipped for them (Moves in fight setup), else their recommended loadout.")
		fr.value_changed.connect(func(v) -> void:
			_fighter = str(v)
			_build("fighter"))
		c.add_child(fr)
	var sr := OptionRow.new("Combat style")
	sr.setup(["moves", "classic"], ["Movesets", "Classic"], _combat)
	sr.set_meta("focus_key", "combat")
	sr.set_help("Combat style", "Movesets (the default everywhere): the lessons teach your four equipped moves, their holds and your Ultimate. Classic: the original Light, Heavy, Grab and two-ability lessons, for the Classic match rule.")
	sr.value_changed.connect(func(v) -> void:
		_combat = str(v)
		_build("combat"))
	c.add_child(sr)
	var cr := Content.creature(_fighter)
	var note := ""
	if cr and cr.tags.has("martial"):
		note = "%s's lessons teach his Cage Rules layout." % cr.display_name
	elif course() == "moves" and cr:
		note = "Teaching %s's moves: %s." % [cr.display_name, ", ".join(MovesUi.loadout_names(cr, MovesUi.player_loadout(cr)))]
	if note != "":
		c.add_child(UiTheme.label(note, "Caption", true))
	var lessons := TutorialHook.lessons(course())
	var start := UiButton.new("Start from lesson 1", "PrimaryButton", "tutorial")
	start.route = "start"
	var first_skip := -1
	for i in lessons.size():
		if first_skip < 0 and bool((lessons[i] as Dictionary).get("skippable", false)):
			first_skip = i
	start.set_help("Start the tutorial", "Runs every lesson in order." + (" Lessons %d–%d are the next layer and can be skipped." % [first_skip + 1, lessons.size()] if first_skip >= 0 else ""))
	start.pressed.connect(_launch.bind(str((lessons[0] as Dictionary)["id"]) if not lessons.is_empty() else ""))
	c.add_child(start)
	c.add_child(UiTheme.label("LESSONS" + ("  ·  COMPLETED" if done else ""), "Eyebrow"))
	for i in lessons.size():
		var d: Dictionary = lessons[i]
		var b := UiButton.new("%d.  %s" % [i + 1, str(d.get("name", d.get("id", "")))], "SubItem")
		b.route = str(d["id"])
		var extra := "  (next layer — skippable)" if bool(d.get("skippable", false)) else ""
		b.set_help("%d. %s" % [i + 1, str(d.get("name", ""))], Tutorial.fill(str(d.get("goal", "")), cr, MovesUi.player_loadout(cr) if cr and course() == "moves" else []) + extra)
		b.pressed.connect(_launch.bind(str(d["id"])))
		c.add_child(b)
	c.add_child(UiTheme.spacer(false, 6))
	if App.has_screen("versus_setup"):
		var pr := UiButton.new("Practice instead", "", "practice")
		pr.route = "practice"
		pr.set_help("Practice", "No clock, endless respawns, a dummy or a bot of your choice.")
		pr.pressed.connect(func() -> void: App.push("versus_setup", {"mode": "practice"}))
		c.add_child(pr)
	_scroll.wrap_focus.call_deferred()
	if focus_key != "":
		_focus_key.call_deferred(focus_key)


func _focus_key(key: String) -> void:
	for fc in _scroll.focusables():
		if fc.has_meta("focus_key") and str(fc.get_meta("focus_key")) == key:
			fc.grab_focus()
			return
	ensure_focus()


func default_focus() -> Control:
	var fs := _scroll.focusables()
	for fc in fs:
		if fc is UiButton and (fc as UiButton).route == "start":
			return fc
	return fs[0] if not fs.is_empty() else null


func _launch(lesson_id: String) -> void:
	if TutorialHook.launch(lesson_id, _fighter, _combat):
		return
	App.dialog("Lessons aren't ready yet", "Granny's lessons are not playable in this build yet. Practice mode is available from Fight › Practice.",
		[{"label": "OK", "id": "ok"}], Callable())
