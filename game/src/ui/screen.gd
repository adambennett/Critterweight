class_name Screen
extends Control
## Base class for every menu screen/overlay managed by App. Screens are built in code, must be
## fully operable with a controller (focus chain + ui_accept/ui_cancel) and mouse/keyboard, and
## must restore sensible focus whenever they become the top screen again (UI-02).

var params := {}
var screen_name := ""
var _last_focus: Control = null


## Called after the screen is added; build UI here.
func on_enter(_params: Dictionary) -> void:
	pass


## Called before the screen is removed.
func on_exit() -> void:
	pass


## Called when this screen becomes the top screen again (after an overlay closes).
func on_resume() -> void:
	restore_focus()


## Return true if the screen handled "back" itself (e.g. closing a sub-panel).
func on_back() -> bool:
	return false


## Control that should receive focus when nothing else is focused.
func default_focus() -> Control:
	return null


func remember_focus() -> void:
	var f := get_viewport().gui_get_focus_owner()
	if f and is_ancestor_of(f):
		_last_focus = f


func restore_focus() -> void:
	var target: Control = _last_focus if is_instance_valid(_last_focus) and _last_focus.is_visible_in_tree() else default_focus()
	if target and target.is_visible_in_tree() and target.focus_mode != Control.FOCUS_NONE:
		target.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or App.top_screen() != self:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		App.back()
