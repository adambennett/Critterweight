class_name ScrollText
extends PanelContainer
## A focusable block of long text (credits, licence notices) that scrolls with up/down (D-pad,
## stick, arrows; held = repeats), the right stick, PgUp/PgDn when not used for tabs, and the mouse
## wheel. Being a real focus stop means controller focus is never "lost" on text-only screens.

var rich: RichTextLabel
var scroll: ScrollContainer
var line_step := 90.0
var help_title := ""
var help_text := ""


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel", UiTheme.style("scroll_text"))
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(scroll)
	rich = RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.fit_content = true
	rich.scroll_active = false
	rich.selection_enabled = false
	rich.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rich.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(rich)


func set_plain(text: String) -> void:
	rich.bbcode_enabled = false
	rich.text = text
	scroll.scroll_vertical = 0


func set_bbcode(text: String) -> void:
	rich.bbcode_enabled = true
	rich.text = text
	scroll.scroll_vertical = 0


func _notification(what: int) -> void:
	if what == NOTIFICATION_FOCUS_ENTER:
		add_theme_stylebox_override("panel", UiTheme.style("scroll_text_focus"))
	elif what == NOTIFICATION_FOCUS_EXIT:
		add_theme_stylebox_override("panel", UiTheme.style("scroll_text"))


func scroll_by(amount: float) -> void:
	scroll.scroll_vertical = int(clampf(scroll.scroll_vertical + amount, 0.0, maxf(0.0, rich.size.y - scroll.size.y)))


func at_end() -> bool:
	return scroll.scroll_vertical >= int(rich.size.y - scroll.size.y) - 2


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_down", true, true):
		scroll_by(line_step)
		accept_event()
	elif event.is_action_pressed("ui_up", true, true):
		scroll_by(-line_step)
		accept_event()
	elif event is InputEventKey and (event as InputEventKey).pressed:
		var k := (event as InputEventKey).keycode
		if k == KEY_HOME:
			scroll.scroll_vertical = 0
			accept_event()
		elif k == KEY_END:
			scroll.scroll_vertical = int(rich.size.y)
			accept_event()
