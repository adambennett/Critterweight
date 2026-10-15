class_name PromptGlyph
extends Control
## One input glyph drawn procedurally (crisp at any scale, no per-platform art): keyboard key caps,
## mouse buttons, Xbox/PlayStation face buttons, shoulders, triggers, sticks (with direction) and the
## D-pad (active arm highlighted). Shapes differ per button so glyphs never rely on colour alone.
## The textual binding comes from Controls.event_label()/prompt_for() and is used as the tooltip.
##
## Event selection mirrors Controls.prompt_for(): the first binding of the device class the prompt
## style asks for (auto = last device used), else the first binding of any class.

const XBOX_FACE := {JOY_BUTTON_A: ["A", Color("#5dbb46")], JOY_BUTTON_B: ["B", Color("#e0453a")],
	JOY_BUTTON_X: ["X", Color("#3b8edb")], JOY_BUTTON_Y: ["Y", Color("#f2c230")]}
const PS_FACE := {JOY_BUTTON_A: ["cross", Color("#7aa7e8")], JOY_BUTTON_B: ["circle", Color("#e86a6a")],
	JOY_BUTTON_X: ["square", Color("#e69ad3")], JOY_BUTTON_Y: ["triangle", Color("#4ec9a0")]}
const PAD_LIGHT := Color("#d9dbe0")
const PAD_DARK := Color("#22262e")
const KEY_FACE := Color("#e9e2cf")
const KEY_LIP := Color("#a9a291")
const INK := Color("#1a1d24")
const KEY_SHORT := {"Escape": "Esc", "Backslash": "\\", "Page Up": "PgUp", "Page Down": "PgDn",
	"Backspace": "Bksp", "Delete": "Del", "Kp Enter": "Enter", "Control": "Ctrl", "Ctrl": "Ctrl",
	"Insert": "Ins", "Capslock": "Caps", "Quoteleft": "`", "Bracketleft": "[", "Bracketright": "]",
	"Semicolon": ";", "Apostrophe": "'", "Comma": ",", "Period": ".", "Slash": "/", "Minus": "-", "Equal": "="}

var event: InputEvent
var style := "xbox"                ## xbox | playstation | keyboard
var glyph_size := 40.0             ## height in du
var _caption := ""


static func wants_pad() -> bool:
	if Controls.prompt_style == "auto":
		return Controls.last_device == "gamepad"
	return Controls.prompt_style != "keyboard"


## Glyph family for the current prompt setting / last device.
static func style_now() -> String:
	if not wants_pad():
		return "keyboard"
	return "playstation" if Controls.prompt_style == "playstation" else "xbox"


static func is_pad_event(ev: InputEvent) -> bool:
	return ev is InputEventJoypadButton or ev is InputEventJoypadMotion


static func events_for(action: String, pad: bool) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if not InputMap.has_action(action):
		return out
	for ev in InputMap.action_get_events(action):
		if is_pad_event(ev) == pad:
			out.append(ev)
	return out


static func event_for(action: String) -> InputEvent:
	var evs := events_for(action, wants_pad())
	if not evs.is_empty():
		return evs[0]
	if not InputMap.has_action(action):
		return null
	var all := InputMap.action_get_events(action)
	return all[0] if not all.is_empty() else null


func _init(ev: InputEvent = null, style_ := "", size_du := 40.0) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	setup(ev, style_, size_du)


func setup(ev: InputEvent, style_ := "", size_du := -1.0) -> void:
	event = ev
	if style_ != "":
		style = style_
	elif ev != null:
		style = ("playstation" if Controls.prompt_style == "playstation" else "xbox") if is_pad_event(ev) else "keyboard"
	if size_du > 0.0:
		glyph_size = size_du
	_caption = Controls.event_label(ev) if ev != null else "?"
	tooltip_text = _caption
	custom_minimum_size = Vector2(_width(), glyph_size)
	update_minimum_size()
	queue_redraw()


func caption() -> String:
	return _caption


func _font() -> Font:
	return UiTheme.font("label")


func _key_text() -> String:
	var k := event as InputEventKey
	var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	var s := OS.get_keycode_string(code)
	if KEY_SHORT.has(s):
		return KEY_SHORT[s]
	return s


func _is_arrow_key() -> bool:
	if not event is InputEventKey:
		return false
	var k := event as InputEventKey
	var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	return code in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]


func _width() -> float:
	var h := glyph_size
	if event == null:
		return h
	if event is InputEventKey:
		if _is_arrow_key():
			return h
		var fs := int(h * 0.56)
		var tw := _font().get_string_size(_key_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		return maxf(h, tw + h * 0.6)
	if event is InputEventMouseButton:
		return h * 0.78
	if event is InputEventJoypadButton:
		var b := (event as InputEventJoypadButton).button_index
		if b in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
			return h * 1.55
		if b in [JOY_BUTTON_BACK, JOY_BUTTON_START, JOY_BUTTON_GUIDE]:
			return h * 1.35
		return h
	if event is InputEventJoypadMotion:
		var a := (event as InputEventJoypadMotion).axis
		if a in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
			return h * 1.3
		return h
	return h


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if event == null:
		_draw_pill(r, "?", PAD_LIGHT, INK)
	elif event is InputEventKey:
		_draw_key(r)
	elif event is InputEventMouseButton:
		_draw_mouse(r, (event as InputEventMouseButton).button_index)
	elif event is InputEventJoypadButton:
		_draw_pad_button(r, (event as InputEventJoypadButton).button_index)
	elif event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		_draw_axis(r, jm.axis, signf(jm.axis_value))
	else:
		_draw_pill(r, "?", PAD_LIGHT, INK)


func _text_centered(text: String, rect: Rect2, color: Color, fs: int) -> void:
	var f := _font()
	var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var asc := f.get_ascent(fs)
	var desc := f.get_descent(fs)
	var pos := Vector2(rect.position.x + (rect.size.x - ts.x) * 0.5, rect.position.y + (rect.size.y - (asc + desc)) * 0.5 + asc)
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _rounded(rect: Rect2, radius: float, color: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	draw_style_box(sb, rect)


func _draw_pill(r: Rect2, text: String, fill: Color, ink: Color) -> void:
	_rounded(r, r.size.y * 0.5, fill)
	_text_centered(text, r, ink, int(r.size.y * 0.5))


func _draw_key(r: Rect2) -> void:
	var h := r.size.y
	_rounded(r, h * 0.16, KEY_LIP)
	var face := Rect2(r.position, Vector2(r.size.x, r.size.y - h * 0.1))
	_rounded(face, h * 0.16, KEY_FACE)
	if _is_arrow_key():
		var k := event as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		var dir := {KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT, KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN}[code] as Vector2
		_triangle(face.get_center(), dir, h * 0.22, INK)
	else:
		_text_centered(_key_text(), face, INK, int(h * 0.56))


func _triangle(c: Vector2, dir: Vector2, s: float, color: Color) -> void:
	var perp := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([c + dir * s, c - dir * s * 0.7 + perp * s, c - dir * s * 0.7 - perp * s])
	draw_colored_polygon(pts, color)


func _draw_mouse(r: Rect2, button: int) -> void:
	var body := r.grow(-r.size.y * 0.03)
	_rounded(body, body.size.x * 0.45, PAD_LIGHT)
	var inner := body.grow(-body.size.y * 0.07)
	var half := inner.size.y * 0.42
	var left := Rect2(inner.position, Vector2(inner.size.x * 0.5 - 1.5, half))
	var right := Rect2(inner.position + Vector2(inner.size.x * 0.5 + 1.5, 0), Vector2(inner.size.x * 0.5 - 1.5, half))
	var hl := UiTheme.GOLD
	var dim := Color("#b8bcc6")
	draw_rect(left, hl if button == MOUSE_BUTTON_LEFT else dim)
	draw_rect(right, hl if button == MOUSE_BUTTON_RIGHT else dim)
	var wheel := Rect2(inner.position + Vector2(inner.size.x * 0.5 - inner.size.x * 0.09, half * 0.18), Vector2(inner.size.x * 0.18, half * 0.64))
	_rounded(wheel, wheel.size.x * 0.5, hl if button == MOUSE_BUTTON_MIDDLE else INK)
	if button > MOUSE_BUTTON_MIDDLE:
		_text_centered("M%d" % button, Rect2(inner.position + Vector2(0, half), Vector2(inner.size.x, inner.size.y - half)), INK, int(r.size.y * 0.32))


func _draw_pad_button(r: Rect2, b: int) -> void:
	var h := r.size.y
	if XBOX_FACE.has(b):
		var c := r.get_center()
		var rad := h * 0.5
		if style == "playstation":
			var ps: Array = PS_FACE[b]
			draw_circle(c, rad, PAD_DARK)
			draw_arc(c, rad - 1.0, 0.0, TAU, 40, Color("#5b6168"), 2.0, true)
			_ps_symbol(c, rad * 0.5, str(ps[0]), ps[1])
		else:
			var xb: Array = XBOX_FACE[b]
			var col: Color = xb[1]
			draw_circle(c, rad, col)
			draw_arc(c, rad - 1.0, 0.0, TAU, 40, INK, 2.0, true)
			_text_centered(str(xb[0]), r, INK if col.get_luminance() > 0.45 else Color.WHITE, int(h * 0.62))
		return
	match b:
		JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER:
			var left := b == JOY_BUTTON_LEFT_SHOULDER
			var sb := StyleBoxFlat.new()
			sb.bg_color = PAD_LIGHT
			sb.anti_aliasing = true
			sb.corner_radius_top_left = int(h * (0.5 if left else 0.18))
			sb.corner_radius_top_right = int(h * (0.18 if left else 0.5))
			sb.corner_radius_bottom_left = int(h * 0.14)
			sb.corner_radius_bottom_right = int(h * 0.14)
			draw_style_box(sb, r.grow_individual(0, -h * 0.08, 0, -h * 0.08))
			var t := ("L1" if left else "R1") if style == "playstation" else ("LB" if left else "RB")
			_text_centered(t, r, INK, int(h * 0.52))
		JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK:
			var c2 := r.get_center()
			draw_circle(c2, h * 0.5, PAD_LIGHT)
			draw_arc(c2, h * 0.34, 0.0, TAU, 32, INK, 2.0, true)
			var t2 := ("L3" if b == JOY_BUTTON_LEFT_STICK else "R3") if style == "playstation" else ("LS" if b == JOY_BUTTON_LEFT_STICK else "RS")
			_text_centered(t2, r, INK, int(h * 0.4))
		JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
			_draw_dpad(r, b)
		JOY_BUTTON_START, JOY_BUTTON_BACK, JOY_BUTTON_GUIDE:
			_rounded(r.grow_individual(0, -h * 0.12, 0, -h * 0.12), h * 0.38, PAD_LIGHT)
			var c3 := r.get_center()
			if b == JOY_BUTTON_START:
				for i in 3:
					var y := c3.y + (i - 1) * h * 0.14
					draw_line(Vector2(c3.x - h * 0.2, y), Vector2(c3.x + h * 0.2, y), INK, maxf(2.0, h * 0.06))
			elif b == JOY_BUTTON_BACK:
				var s := h * 0.2
				draw_rect(Rect2(c3 + Vector2(-s * 1.1, -s * 0.9), Vector2(s * 1.3, s * 1.3)), INK, false, maxf(2.0, h * 0.05))
				draw_rect(Rect2(c3 + Vector2(-s * 0.2, -s * 0.4), Vector2(s * 1.3, s * 1.3)), INK, true)
			else:
				draw_circle(c3, h * 0.18, INK)
		_:
			_draw_pill(r, _caption, PAD_LIGHT, INK)


func _ps_symbol(c: Vector2, s: float, kind: String, col: Color) -> void:
	var w := maxf(2.5, glyph_size * 0.075)
	match kind:
		"cross":
			draw_line(c + Vector2(-s, -s), c + Vector2(s, s), col, w, true)
			draw_line(c + Vector2(s, -s), c + Vector2(-s, s), col, w, true)
		"circle":
			draw_arc(c, s, 0.0, TAU, 32, col, w, true)
		"square":
			draw_rect(Rect2(c - Vector2(s, s) * 0.9, Vector2(s, s) * 1.8), col, false, w)
		"triangle":
			var pts := PackedVector2Array([c + Vector2(0, -s * 1.05), c + Vector2(s * 1.0, s * 0.75), c + Vector2(-s * 1.0, s * 0.75), c + Vector2(0, -s * 1.05)])
			draw_polyline(pts, col, w, true)


func _draw_dpad(r: Rect2, b: int) -> void:
	var c := r.get_center()
	var h := r.size.y
	var arm := h * 0.32
	var half := h * 0.5
	var vert := Rect2(c.x - arm * 0.5, c.y - half, arm, h)
	var horz := Rect2(c.x - half, c.y - arm * 0.5, h, arm)
	_rounded(vert, arm * 0.25, PAD_LIGHT)
	_rounded(horz, arm * 0.25, PAD_LIGHT)
	var dirs := {JOY_BUTTON_DPAD_UP: Vector2.UP, JOY_BUTTON_DPAD_DOWN: Vector2.DOWN, JOY_BUTTON_DPAD_LEFT: Vector2.LEFT, JOY_BUTTON_DPAD_RIGHT: Vector2.RIGHT}
	var d: Vector2 = dirs.get(b, Vector2.UP)
	var arm_rect := Rect2(c + d * (half - arm * 0.5) - Vector2(arm, arm) * 0.5, Vector2(arm, arm))
	if d.x != 0.0:
		arm_rect = Rect2(c.x + (half * 0.5 if d.x > 0 else -half), c.y - arm * 0.5, half * 0.5, arm)
	else:
		arm_rect = Rect2(c.x - arm * 0.5, c.y + (half * 0.5 if d.y > 0 else -half), arm, half * 0.5)
	_rounded(arm_rect, arm * 0.25, UiTheme.GOLD)
	_triangle(arm_rect.get_center(), d, arm * 0.22, INK)


func _draw_axis(r: Rect2, axis: int, dir: float) -> void:
	var h := r.size.y
	if axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		var left := axis == JOY_AXIS_TRIGGER_LEFT
		var w := r.size.x
		var top := h * 0.06
		var pts := PackedVector2Array()
		# trigger silhouette: rounded top on the outer side, straight inner edge
		var x0 := r.position.x
		var y0 := r.position.y
		if left:
			pts = PackedVector2Array([Vector2(x0 + w * 0.22, y0 + top), Vector2(x0 + w, y0 + top), Vector2(x0 + w, y0 + h), Vector2(x0, y0 + h), Vector2(x0, y0 + h * 0.42)])
		else:
			pts = PackedVector2Array([Vector2(x0, y0 + top), Vector2(x0 + w * 0.78, y0 + top), Vector2(x0 + w, y0 + h * 0.42), Vector2(x0 + w, y0 + h), Vector2(x0, y0 + h)])
		draw_colored_polygon(pts, PAD_LIGHT)
		var t := ("L2" if left else "R2") if style == "playstation" else ("LT" if left else "RT")
		_text_centered(t, Rect2(r.position + Vector2(0, h * 0.08), r.size), INK, int(h * 0.5))
		return
	var c := r.get_center()
	draw_circle(c, h * 0.5, PAD_DARK)
	draw_arc(c, h * 0.5 - 1.5, 0.0, TAU, 36, PAD_LIGHT, maxf(2.0, h * 0.07), true)
	var left_stick := axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]
	_text_centered("L" if left_stick else "R", r, PAD_LIGHT, int(h * 0.46))
	var d := Vector2.ZERO
	if axis in [JOY_AXIS_LEFT_X, JOY_AXIS_RIGHT_X]:
		d = Vector2(dir, 0.0)
	else:
		d = Vector2(0.0, dir)
	if d != Vector2.ZERO:
		_triangle(c + d * h * 0.36, d, h * 0.13, UiTheme.GOLD)
