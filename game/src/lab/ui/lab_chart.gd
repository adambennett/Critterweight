class_name LabChart
extends Control
## Minimal learning-curve chart drawn with Control._draw (no plugins). Each series is a list of
## [x, y] points; series can draw a line, dots, or both. Every series has a text legend entry and
## dots are drawn as distinct shapes so curves are distinguishable without colour.

var series: Array = []          ## [{name, points: [[x, y]...], color, dots: bool, line: bool, shape: "circle"|"square"|"diamond"}]
var x_label := ""
var y_label := ""
var empty_text := "No data yet"
var font: Font
var font_size := 28


func _ready() -> void:
	custom_minimum_size = Vector2(520, 320)
	font = UiTheme.font("body")
	font_size = UiTheme.size("caption") + 4
	resized.connect(queue_redraw)


func set_series(s: Array) -> void:
	series = s
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.06, 0.05, 0.08, 0.92))
	draw_rect(r, Color(0.35, 0.32, 0.4), false, 1.0)
	var pad_l := 100.0
	var pad_r := 20.0
	var pad_t := 52.0
	var pad_b := 52.0
	var plot := Rect2(pad_l, pad_t, maxf(10.0, size.x - pad_l - pad_r), maxf(10.0, size.y - pad_t - pad_b))
	var xmin := INF
	var xmax := -INF
	var ymin := INF
	var ymax := -INF
	for s: Dictionary in series:
		for p in s.get("points", []):
			var x := float(p[0])
			var y := float(p[1])
			if not is_finite(x) or not is_finite(y):
				continue
			xmin = minf(xmin, x)
			xmax = maxf(xmax, x)
			ymin = minf(ymin, y)
			ymax = maxf(ymax, y)
	if xmin == INF:
		draw_string(font, Vector2(20, size.y * 0.5), empty_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.8, 0.78, 0.85))
		return
	if xmax - xmin < 1e-6:
		xmax = xmin + 1.0
	if ymax - ymin < 1e-6:
		ymax += 0.5
		ymin -= 0.5
	var ypad := (ymax - ymin) * 0.06
	ymin -= ypad
	ymax += ypad
	# grid + axis labels
	var grid_col := Color(1, 1, 1, 0.08)
	for k in 5:
		var gy := plot.position.y + plot.size.y * float(k) / 4.0
		draw_line(Vector2(plot.position.x, gy), Vector2(plot.end.x, gy), grid_col, 1.0)
		var val := ymax - (ymax - ymin) * float(k) / 4.0
		draw_string(font, Vector2(6, gy + 10), _fmt(val), HORIZONTAL_ALIGNMENT_LEFT, pad_l - 8, font_size - 4, Color(0.75, 0.73, 0.8))
	var int_x := xmax - xmin >= 4.0   # generations / epochs: whole-number ticks
	for k in 5:
		var gx := plot.position.x + plot.size.x * float(k) / 4.0
		draw_line(Vector2(gx, plot.position.y), Vector2(gx, plot.end.y), grid_col, 1.0)
		var xv := xmin + (xmax - xmin) * float(k) / 4.0
		var xt := ("%d" % roundi(xv)) if int_x else _fmt(xv)
		var x0 := clampf(gx - 45.0, 0.0, size.x - 92.0)
		draw_string(font, Vector2(x0, plot.end.y + 34), xt, HORIZONTAL_ALIGNMENT_CENTER, 90, font_size - 4, Color(0.75, 0.73, 0.8))
	draw_rect(plot, Color(0.5, 0.48, 0.55), false, 1.0)
	# series
	var lx := pad_l
	for s: Dictionary in series:
		var col: Color = s.get("color", Color.WHITE)
		var pts: Array = s.get("points", [])
		var prev := Vector2.INF
		for p in pts:
			var x := float(p[0])
			var y := float(p[1])
			if not is_finite(x) or not is_finite(y):
				continue
			var q := Vector2(plot.position.x + (x - xmin) / (xmax - xmin) * plot.size.x, plot.end.y - (y - ymin) / (ymax - ymin) * plot.size.y)
			if bool(s.get("line", true)) and prev != Vector2.INF:
				draw_line(prev, q, col, 2.0, true)
			if bool(s.get("dots", false)):
				_mark(q, str(s.get("shape", "circle")), col)
			prev = q
		# legend
		var label := str(s.get("name", ""))
		_mark(Vector2(lx + 6, 22), str(s.get("shape", "circle")), col)
		draw_line(Vector2(lx - 4, 22), Vector2(lx + 16, 22), col, 2.0)
		draw_string(font, Vector2(lx + 24, 32), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 2, Color(0.9, 0.88, 0.94))
		lx += 40.0 + font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 2).x
	# axis names sit inside the plot corners (y: top left, x: bottom right), dimmed
	var dim := Color(0.7, 0.68, 0.75, 0.85)
	if y_label != "":
		draw_string(font, plot.position + Vector2(8, font_size - 2), y_label, HORIZONTAL_ALIGNMENT_LEFT, plot.size.x - 16.0, font_size - 6, dim)
	if x_label != "":
		var w := font.get_string_size(x_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 6).x
		draw_string(font, Vector2(plot.end.x - w - 8.0, plot.end.y - 8.0), x_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 6, dim)


func _mark(q: Vector2, shape: String, col: Color) -> void:
	match shape:
		"square":
			draw_rect(Rect2(q - Vector2(4, 4), Vector2(8, 8)), col)
		"diamond":
			draw_colored_polygon(PackedVector2Array([q + Vector2(0, -5), q + Vector2(5, 0), q + Vector2(0, 5), q + Vector2(-5, 0)]), col)
		_:
			draw_circle(q, 4.0, col)


static func _fmt(v: float) -> String:
	if absf(v) >= 1000.0:
		return "%.0f" % v
	if absf(v) >= 10.0:
		return "%.1f" % v
	return "%.2f" % v
