class_name OptionPips
extends Control
## Row of small markers under an option value: the current one is a filled gold bar, the rest are
## dots — position is readable by shape, not only colour.

var count := 0
var current := 0


func _init() -> void:
	custom_minimum_size = Vector2(0, 10)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if count <= 1:
		return
	var gap := 14.0
	var total := gap * (count - 1)
	var x0 := size.x * 0.5 - total * 0.5
	var y := size.y * 0.5
	for i in count:
		var x := x0 + gap * i
		if i == current:
			draw_rect(Rect2(x - 6.0, y - 3.0, 12.0, 6.0), UiTheme.GOLD_HI)
		else:
			draw_circle(Vector2(x, y), 2.6, UiTheme.DIM)
