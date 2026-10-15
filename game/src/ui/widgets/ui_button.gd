class_name UiButton
extends Button
## The menu button every screen uses. Focus is unmistakable without colour: gold ring + 4% scale +
## a chevron at the left edge. Mouse hover moves keyboard/controller focus to the button (so the
## pointer and the pad never disagree). Plays Audio.sfx ui_move / ui_accept / ui_error.
## `help_title`/`help_text` feed HelpPanel; `route` is free metadata for screens and tests.

var help_title := ""
var help_text := ""
var route := ""                    ## e.g. a screen name this button opens
var sfx_accept := "ui_accept"
var show_chevron := true
var focus_scale := UiTheme.FOCUS_SCALE
var _tween: Tween


func _init(text_ := "", variation := "", icon_name := "") -> void:
	text = text_
	if variation != "":
		theme_type_variation = variation
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	if icon_name != "":
		icon = UiIcons.tex(icon_name)
		expand_icon = false
	# note: no text_overrun_behavior by default — trimming makes a Button's minimum size ignore its text


func _ready() -> void:
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	mouse_entered.connect(_on_mouse_entered)
	pressed.connect(_on_pressed)
	resized.connect(_update_pivot)
	_update_pivot()


func set_help(title: String, body: String) -> UiButton:
	help_title = title
	help_text = body
	return self


func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _on_mouse_entered() -> void:
	if not disabled and focus_mode != Control.FOCUS_NONE and not has_focus() and is_visible_in_tree():
		grab_focus()


func _on_focus_entered() -> void:
	if UiNav.user_initiated():
		Audio.sfx("ui_move")
	_animate_scale(focus_scale)
	queue_redraw()


func _on_focus_exited() -> void:
	_animate_scale(1.0)
	queue_redraw()


func _on_pressed() -> void:
	Audio.sfx(sfx_accept)


func _animate_scale(target: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	if UiTheme.reduce_motion() or not is_inside_tree():
		scale = Vector2.ONE * target
		return
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE * target, UiTheme.ANIM_FAST).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	if not show_chevron or not has_focus():
		return
	# chevron: a shape cue that does not depend on the gold colour
	var h := size.y
	var s := clampf(h * 0.16, 7.0, 13.0)
	var cx := 16.0 + s * 0.4
	var cy := h * 0.5
	var pts := PackedVector2Array([Vector2(cx - s * 0.55, cy - s), Vector2(cx + s * 0.75, cy), Vector2(cx - s * 0.55, cy + s)])
	draw_colored_polygon(pts, UiTheme.GOLD_HI)
