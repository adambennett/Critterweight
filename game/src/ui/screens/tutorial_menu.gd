extends Screen
## Tutorial lesson list ("tutorial_menu") — Granny Haymaker's corner. Lessons come from Content kind
## "tutorial" when a package provides them, else TutorialHook.DEFAULT_LESSONS (ANNOUNCER_AND_TUTORIAL
## §2.1). Starting a lesson calls TutorialHook.launch(lesson_id, fighter_id): the tutorial owner wires
## TutorialHook.launcher. Until then the menu explains that lessons are not playable in this build and
## offers Practice instead. Entry point: App.goto/push("tutorial_menu").

var _scroll: FocusScroll
var _help: HelpPanel


func on_enter(_p: Dictionary) -> void:
	MenuBackdrop.ensure()
	add_backdrop_gradient(0.97, 0.7)
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
	var done := bool((Profiles.current.get("tutorial", {}) as Dictionary).get("completed", false))
	var c := _scroll.content
	var start := UiButton.new("Start from lesson 1", "PrimaryButton", "tutorial")
	start.route = "start"
	start.set_help("Start the tutorial", "Runs every lesson in order. Lessons 8–10 are the next layer and can be skipped.")
	var lessons := TutorialHook.lessons()
	start.pressed.connect(_launch.bind(str((lessons[0] as Dictionary)["id"]) if not lessons.is_empty() else ""))
	c.add_child(start)
	c.add_child(UiTheme.label("LESSONS" + ("  ·  COMPLETED" if done else ""), "Eyebrow"))
	for i in lessons.size():
		var d: Dictionary = lessons[i]
		var b := UiButton.new("%d.  %s" % [i + 1, str(d.get("name", d.get("id", "")))], "SubItem")
		b.route = str(d["id"])
		var extra := "  (next layer — skippable)" if bool(d.get("skippable", false)) else ""
		b.set_help("%d. %s" % [i + 1, str(d.get("name", ""))], str(d.get("goal", "")) + extra)
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
	play_intro()


func default_focus() -> Control:
	var fs := _scroll.focusables()
	return fs[0] if not fs.is_empty() else null


func _launch(lesson_id: String) -> void:
	if TutorialHook.launch(lesson_id, ""):
		return
	App.dialog("Lessons aren't ready yet", "Granny's lessons are not playable in this build yet. Practice mode is available from Fight › Practice.",
		[{"label": "OK", "id": "ok"}], Callable())
