class_name ToggleSwitch
extends Control
## The pill switch drawn inside ToggleRow: knob left + "OFF" in steel, knob right + "ON" on gold.

var on := false
var _knob_t := 0.0                  ## 0 = off position, 1 = on position (animated)
var _tween: Tween


func _init() -> void:
	custom_minimum_size = Vector2(124, 44)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _ready() -> void:
	_knob_t = 1.0 if on else 0.0


func animate() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	var target := 1.0 if on else 0.0
	if UiTheme.reduce_motion():
		_knob_t = target
		queue_redraw()
		return
	_tween = create_tween()
	_tween.tween_method(func(v: float) -> void:
		_knob_t = v
		queue_redraw(), _knob_t, target, UiTheme.ANIM_FAST)


func _draw() -> void:
	if _tween == null or not _tween.is_valid():
		_knob_t = 1.0 if on else 0.0
	var r := Rect2(Vector2.ZERO, size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.GOLD.lerp(UiTheme.SHADOW, 1.0 - _knob_t)
	sb.border_color = UiTheme.GOLD_HI if on else UiTheme.DIM
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(size.y * 0.5))
	sb.anti_aliasing = true
	draw_style_box(sb, r)
	var kr := size.y * 0.5 - 5.0
	var kx := lerpf(size.y * 0.5, size.x - size.y * 0.5, _knob_t)
	draw_circle(Vector2(kx, size.y * 0.5), kr, UiTheme.TEXT)
	var f := UiTheme.font("label")
	var fs := int(size.y * 0.5)
	var txt := "ON" if on else "OFF"
	var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	# text sits on the side opposite the knob
	var tx := 14.0 if on else size.x - tw - 14.0
	var asc := f.get_ascent(fs)
	draw_string(f, Vector2(tx, (size.y - (asc + f.get_descent(fs))) * 0.5 + asc), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		UiTheme.BG if on else UiTheme.MUTED)
