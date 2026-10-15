class_name TeamChip
extends Control
## Team badge: a coloured shield with the team LETTER (A/B/C/D...) — teams are identified by letter
## and shape as well as colour (ART_DIRECTION §10). Team -1 draws a neutral "solo" dash.

var team := 0
var chip_size := 40.0


func _init(team_ := 0, size_du := 40.0) -> void:
	team = team_
	chip_size = size_du
	custom_minimum_size = Vector2(size_du, size_du)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func set_team(t: int) -> void:
	team = t
	queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := Vector2(size.x * 0.5, size.y * 0.5)
	var col := UiTheme.DIM if team < 0 else UiTheme.team_color(team)
	var hw := s * 0.46
	var pts := PackedVector2Array([c + Vector2(-hw, -s * 0.46), c + Vector2(hw, -s * 0.46), c + Vector2(hw, s * 0.1),
		c + Vector2(0, s * 0.5), c + Vector2(-hw, s * 0.1)])
	draw_colored_polygon(pts, col)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, UiTheme.BG, 2.0, true)
	var f := UiTheme.font("head")
	var fs := int(s * 0.62)
	var t := "–" if team < 0 else UiTheme.team_letter(team)
	var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var asc := f.get_ascent(fs)
	var ink := UiTheme.BG if col.get_luminance() > 0.45 else Color.WHITE
	draw_string(f, Vector2(c.x - tw * 0.5, c.y - (asc + f.get_descent(fs)) * 0.5 + asc - s * 0.04), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
