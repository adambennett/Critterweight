class_name CreatureCard
extends PanelContainer
## Selectable fighter card for character select: element icon, NAME, epithet, element name.
## Focus = gold border + 5% scale + chevron; hover focuses; A/click emits `chosen`.
## `creature_id` "random" shows the dice card.

signal chosen(id: String)

var creature_id := ""
var help_title := ""
var help_text := ""
var selected := false
var _tween: Tween


func _init(id := "") -> void:
	creature_id = id
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(300, 196)
	add_theme_stylebox_override("panel", UiTheme.style("card"))
	var v := UiTheme.vbox(4)
	add_child(v)
	var top := UiTheme.hbox(UiTheme.GAP_S)
	var d := Content.get_entry("creatures", id)
	var el := str(d.get("element", ""))
	var icon_name := "random" if id == "random" else ("el_" + el if el != "" else "fight")
	top.add_child(UiIcons.rect(icon_name, 60))
	top.add_child(UiTheme.spacer())
	if id != "random":
		var tags: Array = d.get("tags", [])
		if tags.has("dev"):
			var chip := UiTheme.panel("PanelChip")
			chip.add_child(UiTheme.label("TEST", "Caption"))
			top.add_child(chip)
	v.add_child(top)
	var nm := UiTheme.label("RANDOM" if id == "random" else str(d.get("name", id)).to_upper(), "H3")
	nm.add_theme_font_override("font", UiTheme.font("head"))
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(nm)
	var sub := UiTheme.label("Let fate pick" if id == "random" else str(d.get("title", "")), "Caption")
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(sub)
	if el != "":
		var eln := UiTheme.label(Elements.display_name(el).to_upper(), "Eyebrow")
		eln.add_theme_color_override("font_color", UiTheme.element_color(el).lerp(UiTheme.TEXT, 0.3))
		v.add_child(eln)
	help_title = nm.text
	help_text = sub.text


func _ready() -> void:
	mouse_entered.connect(func() -> void:
		if not has_focus() and is_visible_in_tree():
			grab_focus())
	resized.connect(func() -> void: pivot_offset = size * 0.5)


func set_selected(on: bool) -> void:
	selected = on
	if not has_focus():
		add_theme_stylebox_override("panel", UiTheme.style("card_selected" if on else "card"))


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_FOCUS_ENTER:
			add_theme_stylebox_override("panel", UiTheme.style("card_focus"))
			if UiNav.user_initiated():
				Audio.sfx("ui_move")
			_animate(1.05)
			queue_redraw()
		NOTIFICATION_FOCUS_EXIT:
			add_theme_stylebox_override("panel", UiTheme.style("card_selected" if selected else "card"))
			_animate(1.0)
			queue_redraw()


func _animate(target: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	if UiTheme.reduce_motion() or not is_inside_tree():
		scale = Vector2.ONE * target
		return
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE * target, UiTheme.ANIM_FAST).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	if not has_focus():
		return
	var s := 12.0
	var x := size.x - 26.0
	var y := size.y - 24.0
	draw_colored_polygon(PackedVector2Array([Vector2(x - s * 0.55, y - s), Vector2(x + s * 0.75, y), Vector2(x - s * 0.55, y + s)]), UiTheme.GOLD_HI)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			grab_focus()
			Audio.sfx("ui_accept")
			chosen.emit(creature_id)
		return
	if event.is_action_pressed("ui_accept", false, true):
		accept_event()
		Audio.sfx("ui_accept")
		chosen.emit(creature_id)
