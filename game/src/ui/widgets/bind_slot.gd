class_name BindSlot
extends PanelContainer
## One binding cell of a KeybindRow (keyboard & mouse OR controller). Shows the action's current
## inputs of that class as glyphs ("Unbound" + warning icon when empty). A/Enter/click starts a
## capture (UiNav swallows all input until a matching key/button arrives, Esc cancels, 5 s timeout);
## X/Delete restores the action's defaults.

signal capture_requested(slot: BindSlot)
signal reset_requested(slot: BindSlot)

var action := ""
var pad := false
var help_title := ""
var help_text := ""
var help_extra := ""
var capturing := false
var _box: HBoxContainer
var _tween: Tween


func _init(action_ := "", pad_ := false) -> void:
	action = action_
	pad = pad_
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(320, 60)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_theme_stylebox_override("panel", UiTheme.style("slot"))
	_box = UiTheme.hbox(8)
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_box)
	var what := "controller" if pad else "keyboard & mouse"
	help_title = BindingsFlow.label_of(action_)
	help_text = "%s binding. Select it, then press the new %s within %d seconds (Esc cancels). The new input becomes the primary one; if another action used it, that action loses it and is marked Unbound." % [
		what.capitalize(), "button, trigger or stick direction" if pad else "key or mouse button", int(BindingsFlow.CAPTURE_SECONDS)]
	help_extra = "X / Delete: restore this action's default bindings."
	if BindingsFlow.help_of(action_) != "":
		help_extra = BindingsFlow.help_of(action_) + "\n" + help_extra


func _ready() -> void:
	mouse_entered.connect(func() -> void:
		if not has_focus() and is_visible_in_tree():
			grab_focus())
	resized.connect(func() -> void: pivot_offset = size * 0.5)
	refresh()


func refresh() -> void:
	for c in _box.get_children():
		c.queue_free()
	if capturing:
		var lbl := UiTheme.label(_capture_text(), "BodyStrong")
		_box.add_child(lbl)
		return
	var evs := BindingsFlow.events_of(action, pad)
	if evs.is_empty():
		_box.add_child(UiIcons.rect("warning", 30, UiTheme.DANGER))
		_box.add_child(UiTheme.label("Unbound", "Danger"))
		return
	var st := ("playstation" if Controls.prompt_style == "playstation" else "xbox") if pad else "keyboard"
	for i in mini(evs.size(), 3):
		_box.add_child(PromptGlyph.new(evs[i], st, 40.0))


func bound_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for ev in BindingsFlow.events_of(action, pad):
		parts.append(Controls.event_label(ev))
	return ", ".join(parts) if not parts.is_empty() else "Unbound"


func _capture_text() -> String:
	var left := ceili(UiNav.capture_seconds_left())
	return ("Press a button…  %d" if pad else "Press a key…  %d") % left


func set_capturing(on: bool) -> void:
	capturing = on
	add_theme_stylebox_override("panel", UiTheme.style("slot_capture" if on else ("slot_focus" if has_focus() else "slot")))
	refresh()
	set_process(on)


func _process(_dt: float) -> void:
	if capturing and _box.get_child_count() > 0:
		var l := _box.get_child(0) as Label
		if l:
			l.text = _capture_text()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_FOCUS_ENTER:
			if not capturing:
				add_theme_stylebox_override("panel", UiTheme.style("slot_focus"))
			if UiNav.user_initiated():
				Audio.sfx("ui_move")
			_animate(1.04)
			queue_redraw()
		NOTIFICATION_FOCUS_EXIT:
			if not capturing:
				add_theme_stylebox_override("panel", UiTheme.style("slot"))
			_animate(1.0)
			queue_redraw()


func _animate(target: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	if UiTheme.reduce_motion() or not is_inside_tree():
		scale = Vector2.ONE * target
		return
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE * target, UiTheme.ANIM_FAST)


func _draw() -> void:
	if has_focus():
		var s := 9.0
		var cy := size.y * 0.5
		draw_colored_polygon(PackedVector2Array([Vector2(6, cy - s), Vector2(6 + s * 1.2, cy), Vector2(6, cy + s)]), UiTheme.GOLD_HI)


func _gui_input(event: InputEvent) -> void:
	if capturing:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			grab_focus()
			accept_event()
			capture_requested.emit(self)
		return
	if event.is_action_pressed("ui_accept", false, true):
		accept_event()
		Audio.sfx("ui_accept")
		capture_requested.emit(self)
	elif event.is_action_pressed("ui_extra", false, true):
		accept_event()
		reset_requested.emit(self)
