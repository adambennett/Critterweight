class_name ToastLayer
extends CanvasLayer
## Non-blocking notifications stacked at the top-right above every screen (layer 30). Each toast
## has an icon whose SHAPE encodes its kind (info circle, check, warning triangle, error X) plus a
## coloured edge; it never takes focus and ignores the mouse. Reduced motion: no slide.

const KINDS := {"info": ["info", UiTheme.RIM], "success": ["check", UiTheme.SUCCESS],
	"warning": ["warning", UiTheme.WARNING], "error": ["error", UiTheme.DANGER]}
const MAX_VISIBLE := 4

var _root: Control
var _stack: VBoxContainer
var history: Array[Dictionary] = []          ## [{text, kind, msec}] (tests, diagnostics)


func _init() -> void:
	layer = 30
	name = "Toasts"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.get_theme()
	add_child(_root)
	_stack = UiTheme.vbox(UiTheme.GAP_S)
	_stack.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_stack.anchor_left = 1.0
	_stack.anchor_right = 1.0
	_stack.offset_left = -760
	_stack.offset_right = -UiTheme.SCREEN_MARGIN * 0.6
	_stack.offset_top = UiTheme.SCREEN_MARGIN * 0.6
	_stack.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_stack.alignment = BoxContainer.ALIGNMENT_BEGIN
	_root.add_child(_stack)


func show_toast(text: String, kind := "info", seconds := 3.5) -> void:
	history.append({"text": text, "kind": kind, "msec": Time.get_ticks_msec()})
	if history.size() > 50:
		history.pop_front()
	Log.i("toast", "[%s] %s" % [kind, text])
	var spec: Array = KINDS.get(kind, KINDS["info"])
	var p := PanelContainer.new()
	p.theme_type_variation = "PanelToast"
	var sb := p.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	sb.border_color = spec[1]
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := UiTheme.hbox(UiTheme.GAP_M)
	row.add_child(UiIcons.rect(str(spec[0]), 36, spec[1]))
	var l := UiTheme.label(text, "BodyStrong", true)
	l.custom_minimum_size = Vector2(520, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	p.add_child(row)
	_stack.add_child(p)
	while _stack.get_child_count() > MAX_VISIBLE:
		var old := _stack.get_child(0)
		_stack.remove_child(old)
		old.queue_free()
	if not UiTheme.reduce_motion():
		p.modulate.a = 0.0
		var tw := p.create_tween()
		tw.tween_property(p, "modulate:a", 1.0, UiTheme.ANIM)
	var t := get_tree().create_timer(seconds, true, false, true)
	t.timeout.connect(func() -> void:
		if not is_instance_valid(p):
			return
		if UiTheme.reduce_motion():
			p.queue_free()
			return
		var tw2 := p.create_tween()
		tw2.tween_property(p, "modulate:a", 0.0, UiTheme.ANIM_SLOW)
		tw2.tween_callback(p.queue_free))


func visible_texts() -> Array[String]:
	var out: Array[String] = []
	for c in _stack.get_children():
		var lbls := c.find_children("*", "Label", true, false)
		for l in lbls:
			out.append((l as Label).text)
	return out
