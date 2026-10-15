class_name StatSegments
extends Control
## Ten skewed segments; filled ones are solid, the partial one is half-filled, empty ones outlined.

var fraction := 0.5
var color := UiTheme.GOLD
var segments := 10


func _init() -> void:
	custom_minimum_size = Vector2(240, 26)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _draw() -> void:
	var gap := 5.0
	var w := (size.x - gap * (segments - 1)) / segments
	var h := size.y
	var skew := h * 0.3
	var filled := fraction * segments
	for i in segments:
		var x := i * (w + gap)
		var pts := PackedVector2Array([Vector2(x + skew, 0), Vector2(x + w, 0), Vector2(x + w - skew, h), Vector2(x, h)])
		if float(i) + 1.0 <= filled + 0.001:
			draw_colored_polygon(pts, color)
		elif float(i) < filled:
			draw_colored_polygon(pts, Color(color, 0.45))
			var outline := pts.duplicate()
			outline.append(pts[0])
			draw_polyline(outline, color, 2.0, true)
		else:
			var outline2 := pts.duplicate()
			outline2.append(pts[0])
			draw_polyline(outline2, UiTheme.DIM, 2.0, true)
