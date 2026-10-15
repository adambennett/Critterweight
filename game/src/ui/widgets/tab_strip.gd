class_name TabStrip
extends HBoxContainer
## Tab bar: [LB]  Display  Graphics  Audio ...  [RB]. LB/RB (Q/E, PgUp/PgDn) switch tabs via the
## ui_tab_prev/ui_tab_next actions handled by the owning screen calling `step()`; tabs are also
## clickable. Tabs are not focus stops, so focus stays in the content and never gets "stuck" in the
## bar; the active tab is marked by a gold underline AND a filled background (not colour alone).

signal tab_changed(index: int)

var current := 0
var tab_ids: Array[String] = []
var _buttons: Array[Button] = []
var _prev: ButtonPrompt
var _next: ButtonPrompt
var _tabs_box: HBoxContainer


func _init() -> void:
	add_theme_constant_override("separation", 14)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prev = ButtonPrompt.new(["ui_tab_prev"], "", 38.0)
	_prev.pressed.connect(func() -> void: step(-1))
	add_child(_prev)
	_tabs_box = UiTheme.hbox(4)
	add_child(_tabs_box)
	_next = ButtonPrompt.new(["ui_tab_next"], "", 38.0)
	_next.pressed.connect(func() -> void: step(1))
	add_child(_next)


## titles: display names; ids: stable ids (e.g. settings categories).
func setup(titles: Array, ids: Array, start := 0) -> void:
	for b in _buttons:
		b.queue_free()
	_buttons.clear()
	tab_ids.clear()
	for i in titles.size():
		var b := Button.new()
		b.text = str(titles[i]).to_upper()
		b.focus_mode = Control.FOCUS_NONE
		b.theme_type_variation = "TabButton"
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var idx := i
		b.pressed.connect(func() -> void: select(idx))
		_tabs_box.add_child(b)
		_buttons.append(b)
		tab_ids.append(str(ids[i]) if i < ids.size() else str(i))
	current = clampi(start, 0, maxi(0, titles.size() - 1))
	_restyle()


func step(dir: int) -> void:
	if _buttons.is_empty():
		return
	select(posmod(current + dir, _buttons.size()))


func select(i: int, emit := true) -> void:
	if i == current or i < 0 or i >= _buttons.size():
		return
	current = i
	Audio.sfx("ui_move")
	_restyle()
	if emit:
		tab_changed.emit(i)


func current_id() -> String:
	return tab_ids[current] if current < tab_ids.size() else ""


func index_of(id: String) -> int:
	return tab_ids.find(id)


func _restyle() -> void:
	for i in _buttons.size():
		_buttons[i].theme_type_variation = "TabButtonActive" if i == current else "TabButton"
