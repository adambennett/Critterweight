extends Screen
## Per-context playlists; changes save immediately and refresh the currently playing context.
var list: FocusScroll
var tabs: TabStrip
var context := "menu"


func on_enter(_p: Dictionary) -> void:
	add_dimmer(0.97)
	var frame := build_frame("Soundtrack", "Jukebox")
	var body: VBoxContainer = frame["body"]
	tabs = TabStrip.new()
	tabs.setup(Jukebox.LABELS, Jukebox.CONTEXTS)
	tabs.tab_changed.connect(func(i: int): context = Jukebox.CONTEXTS[i]; _build())
	body.add_child(tabs)
	list = FocusScroll.new(10)
	body.add_child(list)
	(frame["prompts"] as PromptBar).set_prompts([
		{"actions": ["ui_accept"], "text": "Toggle track / preview"},
		{"actions": ["ui_tab_prev", "ui_tab_next"], "text": "Context"},
		{"actions": ["ui_cancel"], "text": "Back", "call": App.back}])
	_build()


func _build() -> void:
	list.clear()
	var cfg := Jukebox.config(context)
	var mode := OptionRow.new("Playback")
	mode.setup(Jukebox.MODES, Jukebox.MODE_LABELS, cfg["mode"])
	mode.value_changed.connect(func(value):
		cfg["mode"] = str(value)
		Jukebox.save(context, cfg))
	list.content.add_child(mode)
	list.content.add_child(UiTheme.label("Choose tracks below. Selection order is playback order. Repeat plays the first selected track; an empty custom playlist is silent.", "BodyMuted", true))
	for id in Jukebox.tracks():
		var entry: Dictionary = Audio.bank["music"][id]
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		var toggle := CheckButton.new()
		toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var order: int = (cfg["tracks"] as Array).find(id)
		toggle.text = ("%d. " % (order + 1) if order >= 0 else "") + str(entry.get("title", id))
		toggle.button_pressed = order >= 0
		toggle.set_meta("track", id)
		toggle.toggled.connect(func(on: bool):
			var selected: Array = cfg["tracks"]
			if on and not selected.has(id):
				selected.append(id)
			elif not on:
				selected.erase(id)
			Jukebox.save(context, cfg)
			for control in list.content.find_children("*", "CheckButton", true, false):
				var track := str(control.get_meta("track", ""))
				var index := selected.find(track)
				control.text = ("%d. " % (index + 1) if index >= 0 else "") + str(Audio.bank["music"][track].get("title", track)))
		row.add_child(toggle)
		var preview := UiButton.new("Preview")
		preview.name = "JukeboxPreview_" + id
		preview.custom_minimum_size = Vector2(150, 50)
		preview.show_chevron = false
		preview.set_help("Preview " + str(entry.get("title", id)), "Stops the previous music preview before playing this track.")
		preview.pressed.connect(func() -> void: Audio.preview_music(id))
		row.add_child(preview)
		list.content.add_child(row)
	list.wrap_focus()
	mode.grab_focus.call_deferred()


func default_focus() -> Control:
	return list.focusables()[0] if list and not list.focusables().is_empty() else null


func _unhandled_input(event: InputEvent) -> void:
	if is_top() and (event.is_action_pressed("ui_tab_prev") or event.is_action_pressed("ui_tab_next")):
		get_viewport().set_input_as_handled()
		tabs.step(-1 if event.is_action_pressed("ui_tab_prev") else 1)
		return
	super(event)
