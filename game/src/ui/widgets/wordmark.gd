class_name Wordmark
extends Control
## The CRITTERWEIGHT wordmark (ART_DIRECTION §9), drawn live so it is crisp at any resolution:
## Bungee letters on a slight arch, the "W" drawn as two upturned claws, #F2F2EC fill over a dark
## outline with a #C9A227 offset shadow (6 du at the 132 du title size).
## Title-card animation (play_intro): the wordmark stamps in with a 2-frame overshoot, the sequins on
## the first "I" glint, and a JUICE can falls past and clips the first "T", which wobbles back.
## Reduced motion: no stamp, no can; the glint is a static sparkle.

const WORD := "CRITTERWEIGHT"
const W_INDEX := 7
const I_INDEX := 2
const T_INDEX := 3

var font_size := 132.0
var arch := 0.2                      ## arch height as a fraction of the font size
var with_shadow := true
var _t := -1.0                       ## intro clock (s); < 0 = static
var _stamp := 1.0
var _alpha := 1.0
var _t_tilt := 0.0                   ## degrees, the clipped T
var _t_tilt_v := 0.0
var _can_p := -1.0                   ## can fall progress 0..1 (< 0 hidden)
var _can_hit := false
var _glint := 0.0
var _glint_clock := 0.0
var _layout: Array = []              ## [{ch, adv, x, y, rot}]
var _width := 0.0


func _init(size_du := 132.0) -> void:
	font_size = size_du
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_relayout()


func _font() -> Font:
	return UiTheme.font("display")


func cap_height() -> float:
	return font_size * 0.74


func _relayout() -> void:
	var f := _font()
	var fs := int(font_size)
	_layout.clear()
	var tracking := font_size * 0.02
	var advs: Array[float] = []
	var total := 0.0
	for i in WORD.length():
		var ch := WORD[i]
		var adv := f.get_char_size(ch.unicode_at(0), fs).x
		advs.append(adv)
		total += adv + (tracking if i < WORD.length() - 1 else 0.0)
	_width = total
	var x := -total * 0.5
	var half := total * 0.5
	var k := arch * font_size / (half * half)
	for i in WORD.length():
		var cx := x + advs[i] * 0.5
		_layout.append({"ch": WORD[i], "adv": advs[i], "x": cx, "y": k * cx * cx, "rot": atan(2.0 * k * cx)})
		x += advs[i] + tracking
	custom_minimum_size = Vector2(total + font_size * 0.5, font_size * (1.25 + arch))
	update_minimum_size()


func set_font_size(s: float) -> void:
	font_size = s
	_relayout()
	queue_redraw()


func play_intro() -> void:
	if UiTheme.reduce_motion():
		_t = -1.0
		_stamp = 1.0
		_alpha = 1.0
		_glint = 0.7
		queue_redraw()
		return
	_t = 0.0
	_stamp = 1.5
	_alpha = 0.0
	_can_p = -1.0
	_can_hit = false
	set_process(true)


func _ready() -> void:
	set_process(true)


func _process(dt: float) -> void:
	if UiTheme.reduce_motion():
		return
	_glint_clock += dt
	var g := fmod(_glint_clock, 4.2)
	_glint = clampf(1.0 - absf(g - 0.35) / 0.35, 0.0, 1.0) if g < 0.7 else 0.0
	if _t >= 0.0:
		_t += dt
		# stamp: 1.5 -> 0.94 (0.18 s) -> 1.0 (0.3 s)
		if _t < 0.18:
			_stamp = lerpf(1.5, 0.94, ease(_t / 0.18, 0.4))
		elif _t < 0.3:
			_stamp = lerpf(0.94, 1.0, (_t - 0.18) / 0.12)
		else:
			_stamp = 1.0
		_alpha = clampf(_t / 0.12, 0.0, 1.0)
		# the can falls from 0.75 s to 1.75 s
		if _t >= 0.75 and _t < 1.75:
			_can_p = (_t - 0.75) / 1.0
			if not _can_hit and _can_p > 0.38:
				_can_hit = true
				_t_tilt_v = -260.0
		elif _t >= 1.75:
			_can_p = -1.0
		if _t > 4.0:
			_t = -1.0
	# spring the clipped T back upright
	var acc := -_t_tilt * 140.0 - _t_tilt_v * 9.0
	_t_tilt_v += acc * dt
	_t_tilt += _t_tilt_v * dt
	queue_redraw()


func _letter_xform(i: int, center: Vector2) -> Transform2D:
	var e: Dictionary = _layout[i]
	var rot: float = e["rot"]
	if i == T_INDEX:
		rot += deg_to_rad(_t_tilt)
	var base := center + Vector2(float(e["x"]), float(e["y"]))
	return Transform2D(rot, base)


func _draw() -> void:
	if _layout.is_empty():
		return
	var f := _font()
	var fs := int(font_size)
	var center := Vector2(size.x * 0.5, size.y * 0.5 + cap_height() * 0.5 - font_size * arch * 0.5)
	var g := Transform2D(0.0, Vector2.ONE * _stamp, 0.0, Vector2.ZERO)
	var pivot := Transform2D(0.0, size * 0.5)
	var root := pivot * g * pivot.affine_inverse()
	var shadow := Vector2(1, 1) * (font_size / 132.0) * 6.0
	var outline := int(maxf(4.0, font_size * 0.07))
	var fill := Color(UiTheme.TEXT, _alpha)
	var gold := Color(UiTheme.GOLD, _alpha)
	var ink := Color(UiTheme.BG_DEEP, _alpha)
	# pass 0: shadows, pass 1: outlines, pass 2: fills (so no letter's shadow covers a neighbour)
	for pass_i in 3:
		for i in _layout.size():
			var e: Dictionary = _layout[i]
			var xf := root * _letter_xform(i, center)
			if pass_i == 0:
				if not with_shadow:
					continue
				xf = Transform2D(0.0, shadow * _stamp) * xf
			draw_set_transform_matrix(xf)
			var adv: float = e["adv"]
			var origin := Vector2(-adv * 0.5, 0.0)
			var ch: String = e["ch"]
			if i == W_INDEX:
				_draw_claw_tips(adv, [gold, ink, fill][pass_i], pass_i == 1, outline)
			match pass_i:
				0:
					draw_char(f, origin, ch, fs, gold)
				1:
					draw_char_outline(f, origin, ch, fs, outline, ink)
				2:
					draw_char(f, origin, ch, fs, fill)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	_draw_glint(root, center)
	if _can_p >= 0.0:
		_draw_can(root, center)


## The "W" is Bungee's own W (legibility first) with its two outer strokes growing into upturned,
## outward-hooked claw tips — the two claws of ART_DIRECTION §9.
func _draw_claw_tips(adv: float, color: Color, as_outline: bool, outline: int) -> void:
	for pts in claw_polygons(adv):
		if as_outline:
			var loop := pts.duplicate()
			loop.append(pts[0])
			draw_polyline(loop, color, float(outline) * 2.0, true)
		else:
			draw_colored_polygon(pts, color)


func claw_polygons(adv: float) -> Array[PackedVector2Array]:
	var cap := cap_height()
	var out: Array[PackedVector2Array] = []
	for side in [-1.0, 1.0]:
		var s: float = side
		var base_out := Vector2(s * adv * 0.47, -cap + cap * 0.16)
		var base_in := Vector2(s * adv * 0.17, -cap + cap * 0.16)
		var tip := Vector2(s * adv * 0.6, -cap - cap * 0.4)
		var c_out := Vector2(s * adv * 0.56, -cap - cap * 0.06)
		var c_in := Vector2(s * adv * 0.24, -cap - cap * 0.3)
		var pts := PackedVector2Array()
		var n := 10
		for i in n + 1:
			var t := float(i) / n
			pts.append(base_out.lerp(c_out, t).lerp(c_out.lerp(tip, t), t))
		for i in range(n - 1, -1, -1):
			var t := float(i) / n
			pts.append(base_in.lerp(c_in, t).lerp(c_in.lerp(tip, t), t))
		out.append(pts)
	return out


func _draw_glint(root: Transform2D, center: Vector2) -> void:
	if _glint <= 0.01:
		return
	var xf := root * _letter_xform(I_INDEX, center)
	draw_set_transform_matrix(xf)
	var cap := cap_height()
	# three sequins on the stem brighten, then a 4-point sparkle at the top
	for s in 3:
		var p := Vector2(0.0, -cap * (0.25 + 0.25 * s))
		var a := clampf(_glint * 1.6 - s * 0.25, 0.0, 1.0)
		var d := font_size * 0.035
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)]), Color(UiTheme.GOLD_HI, a))
	var c := Vector2(font_size * 0.06, -cap - font_size * 0.05)
	var r := font_size * 0.16 * _glint
	var w := r * 0.22
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(w, -w), c + Vector2(r, 0), c + Vector2(w, w),
		c + Vector2(0, r), c + Vector2(-w, w), c + Vector2(-r, 0), c + Vector2(-w, -w)]), Color(1, 1, 1, _glint))
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_can(root: Transform2D, center: Vector2) -> void:
	var e: Dictionary = _layout[T_INDEX]
	var cap := cap_height()
	var start_y := -size.y * 0.5 - font_size
	var end_y := size.y * 0.5 + font_size * 1.5
	var y := lerpf(start_y, end_y, _can_p * _can_p)
	var x := float(e["x"]) + font_size * 0.32 + (_can_p - 0.38) * font_size * 0.6 * (1.0 if _can_hit else 0.0)
	var rot := _can_p * 5.0
	var xf := root * Transform2D(rot, center + Vector2(x, y - cap * 0.5))
	draw_set_transform_matrix(xf)
	var w := font_size * 0.3
	var h := font_size * 0.52
	var body := Rect2(-w * 0.5, -h * 0.5, w, h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.NEON
	sb.set_corner_radius_all(int(w * 0.22))
	sb.border_color = UiTheme.BG_DEEP
	sb.set_border_width_all(int(maxf(2.0, font_size * 0.025)))
	sb.anti_aliasing = true
	draw_style_box(sb, body)
	draw_rect(Rect2(-w * 0.5 + 2, -h * 0.12, w - 4, h * 0.26), Color("#5c8f17"))
	draw_rect(Rect2(-w * 0.32, -h * 0.42, w * 0.64, h * 0.05), UiTheme.BG_DEEP)
	draw_set_transform_matrix(Transform2D.IDENTITY)
