class_name Screen
extends Control
## Base class for every menu screen/overlay managed by App. Screens are built in code, must be
## fully operable with a controller (focus chain + ui_accept/ui_cancel) and mouse/keyboard, and
## must restore sensible focus whenever they become the top screen again (UI-02).
##
## Contract (see docs/UI.md):
##  - on_enter(params) builds the UI; default_focus() names the first control to focus.
##  - is_overlay = true: the screen below stays visible (dimmed); false: the screen below is hidden.
##    Either way, screens below the top one get focus and mouse disabled (focus_behavior_recursive /
##    mouse_behavior_recursive), so navigation can never escape into a covered screen.
##  - ui_cancel calls App.back(); on_back() may intercept (close a sub-panel, cancel a dialog).
##  - remember_focus()/restore_focus() keep the focused control across overlays; UiNav's focus
##    guardian calls ensure_focus() if focus is ever lost.
##  - The shared UiTheme is applied automatically; intro transitions respect "Reduce motion".

var params := {}
var screen_name := ""
var is_overlay := false
var dim_alpha := 0.62                ## overlay dimmer strength
var _last_focus: Control = null
var _dimmer: ColorRect
var _covered := false


func _enter_tree() -> void:
	theme = UiTheme.get_theme()
	UiNav.ensure()
	if not App.screen_changed.is_connected(_on_stack_changed):
		App.screen_changed.connect(_on_stack_changed)


## Called after the screen is added; build UI here.
func on_enter(_params: Dictionary) -> void:
	pass


## Called before the screen is removed.
func on_exit() -> void:
	pass


## Called when this screen becomes the top screen again (after an overlay closes).
func on_resume() -> void:
	_set_covered(false)
	restore_focus()


## Return true if the screen handled "back" itself (e.g. closing a sub-panel).
func on_back() -> bool:
	return false


## Control that should receive focus when nothing else is focused.
func default_focus() -> Control:
	return null


func is_top() -> bool:
	return App.top_screen() == self


func remember_focus() -> void:
	var f := get_viewport().gui_get_focus_owner()
	if f and is_ancestor_of(f):
		_last_focus = f


func restore_focus() -> void:
	_restore_deferred.call_deferred()


func _restore_deferred() -> void:
	# deferred: by now another overlay may have been pushed on top; only the top screen takes focus
	if not is_inside_tree() or is_queued_for_deletion() or App.top_screen() != self:
		return
	var target := _focus_target()
	if target:
		target.grab_focus()


## Immediate variant used by UiNav's focus guardian.
func ensure_focus() -> void:
	var target := _focus_target()
	if target and target.is_inside_tree():
		target.grab_focus()


func _focus_target() -> Control:
	if _usable(_last_focus):
		return _last_focus
	var d := default_focus()
	if _usable(d):
		return d
	return first_focusable(self)


func _usable(c: Control) -> bool:
	return c != null and is_instance_valid(c) and c.is_inside_tree() and c.is_visible_in_tree() \
		and c.focus_mode != Control.FOCUS_NONE and not c.is_queued_for_deletion() \
		and not (c is BaseButton and (c as BaseButton).disabled)


## First visible, focusable descendant in tree order (null if none).
static func first_focusable(n: Node) -> Control:
	for c in n.get_children():
		if c is Control:
			var cc := c as Control
			if not cc.visible:
				continue
			if cc.focus_mode == Control.FOCUS_ALL and not (cc is BaseButton and (cc as BaseButton).disabled):
				return cc
			var deeper := first_focusable(cc)
			if deeper:
				return deeper
	return null


## Full-screen dark backdrop for overlays (call first in on_enter so it sits behind the content).
func add_dimmer(alpha := -1.0) -> ColorRect:
	_dimmer = ColorRect.new()
	_dimmer.color = Color(UiTheme.BG_DEEP, dim_alpha if alpha < 0.0 else alpha)
	_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dimmer)
	return _dimmer


## Left-to-right darkening over the 3D backdrop for full screens (content on the left stays readable).
func add_backdrop_gradient(left_alpha := 0.94, right_alpha := 0.35) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(UiTheme.BG_DEEP, left_alpha))
	g.set_color(1, Color(UiTheme.BG_DEEP, right_alpha))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	gt.fill_from = Vector2(0.0, 0.0)
	gt.fill_to = Vector2(1.0, 0.0)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(tr)
	return tr


## Standard screen frame: margins + column with header / body / footer. Returns {root, header, body, footer, prompts}.
func build_frame(eyebrow: String, title: String, prompts: Array = []) -> Dictionary:
	var m := UiTheme.margin(UiTheme.SCREEN_MARGIN, 56, 40)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(m)
	var col := UiTheme.vbox(UiTheme.GAP_M)
	m.add_child(col)
	var header := UiTheme.vbox(2)
	if eyebrow != "":
		header.add_child(UiTheme.label(eyebrow.to_upper(), "Eyebrow"))
	if title != "":
		header.add_child(UiTheme.label(title.to_upper(), "H1"))
	col.add_child(header)
	var body_box := UiTheme.vbox(UiTheme.GAP_M)
	body_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body_box)
	var footer := UiTheme.hbox(UiTheme.GAP_L)
	col.add_child(footer)
	var bar := PromptBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(bar)
	if not prompts.is_empty():
		bar.set_prompts(prompts)
	return {"root": m, "column": col, "header": header, "body": body_box, "footer": footer, "prompts": bar}


## Standard footer prompts: Select + Back (clickable), plus extras.
func std_prompts(extra: Array = [], back_text := "Back") -> Array:
	var out := [{"actions": ["ui_accept"], "text": "Select"}]
	out.append_array(extra)
	out.append({"actions": ["ui_cancel"], "text": back_text, "call": App.back})
	return out


## Intro transition: fade + short slide (overlays: fade + slight scale). Skipped with reduce motion.
func play_intro(from_right := true) -> void:
	if UiTheme.reduce_motion():
		return
	modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, UiTheme.ANIM).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if not is_overlay:
		var dx := 36.0 if from_right else -36.0
		position.x = dx
		tw.tween_property(self, "position:x", 0.0, UiTheme.ANIM_SLOW).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## "Stamp": a card slams in with a 2-frame overshoot (results, title cards). Skipped with reduce motion.
static func stamp(c: Control, delay := 0.0) -> void:
	if UiTheme.reduce_motion():
		return
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2.ONE * 1.35
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(c, "modulate:a", 1.0, 0.06)
	tw.parallel().tween_property(c, "scale", Vector2.ONE * 0.95, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(c, "scale", Vector2.ONE, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_stack_changed(_name: String) -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	var idx := App.stack.find(self)
	if idx < 0:
		return
	if idx == App.stack.size() - 1:
		_set_covered(false)
		return
	# hidden when ANY full (non-overlay) screen sits above this one; overlays alone keep it visible
	var hide := false
	for j in range(idx + 1, App.stack.size()):
		var s: Screen = App.stack[j]
		if is_instance_valid(s) and not s.is_overlay:
			hide = true
			break
	_set_covered(true, hide)


func _set_covered(covered: bool, hide := false) -> void:
	_covered = covered
	focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED if covered else Control.FOCUS_BEHAVIOR_INHERITED
	mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED if covered else Control.MOUSE_BEHAVIOR_INHERITED
	visible = not (covered and hide)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or App.top_screen() != self:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Audio.sfx("ui_back")
		App.back()
