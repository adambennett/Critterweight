class_name FocusScroll
extends ScrollContainer
## Vertical scroll list that keeps the focused child visible (follow_focus) with a little breathing
## room, and pads its content so focused items can scale up without being clipped.
## Add rows to `content` (a VBoxContainer). `wrap_focus()` links last<->first for controller loops.

var content: VBoxContainer
var _pad: MarginContainer


func _init(gap := 10) -> void:
	follow_focus = true
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	_pad = MarginContainer.new()
	_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pad.mouse_filter = Control.MOUSE_FILTER_PASS
	_pad.add_theme_constant_override("margin_left", 22)
	_pad.add_theme_constant_override("margin_right", 26)
	_pad.add_theme_constant_override("margin_top", 10)
	_pad.add_theme_constant_override("margin_bottom", 14)
	add_child(_pad)
	content = UiTheme.vbox(gap)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	_pad.add_child(content)


func clear() -> void:
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()


## Focusable descendants in tree order (rows, slots, buttons).
func focusables() -> Array[Control]:
	var out: Array[Control] = []
	_collect(content, out)
	return out


func _collect(n: Node, out: Array[Control]) -> void:
	for c in n.get_children():
		if c is Control:
			var cc := c as Control
			if not cc.visible:
				continue
			if cc.focus_mode == Control.FOCUS_ALL:
				out.append(cc)
			_collect(cc, out)


## Makes up on the first item go to the last and down on the last go to the first.
func wrap_focus() -> void:
	var f := focusables()
	if f.size() < 2:
		return
	var first := f[0]
	var last := f[f.size() - 1]
	first.focus_neighbor_top = first.get_path_to(last)
	last.focus_neighbor_bottom = last.get_path_to(first)


func scroll_to_top() -> void:
	scroll_vertical = 0
