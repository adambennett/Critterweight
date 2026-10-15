class_name ArrowButton
extends Control
## Small clickable triangle (◀ / ▶) used inside rows for mouse users. Not a focus stop: controller
## and keyboard users change values with left/right on the row itself.

signal pressed

var direction := 1                 ## -1 left, +1 right
var arrow_size := 34.0
var _hover := false


func _init(dir := 1, size_du := 34.0) -> void:
	direction = dir
	arrow_size = size_du
	custom_minimum_size = Vector2(size_du, size_du)
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _ready() -> void:
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		pressed.emit()


func _draw() -> void:
	var c := size * 0.5
	var s := minf(size.x, size.y) * 0.32
	var d := float(direction)
	if _hover:
		draw_circle(c, minf(size.x, size.y) * 0.5, Color(UiTheme.GOLD, 0.25))
	var pts := PackedVector2Array([c + Vector2(d * s, 0), c + Vector2(-d * s * 0.7, -s), c + Vector2(-d * s * 0.7, s)])
	draw_colored_polygon(pts, UiTheme.GOLD_HI if _hover else UiTheme.TEXT)
