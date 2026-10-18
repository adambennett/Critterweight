class_name CombatPrompt
extends ButtonPrompt
## Live input glyph with a descending cooldown veil and numeric seconds. Rebinding/device
## changes rebuild the glyph and its overlay together, so the timer never floats elsewhere.
var remaining := 0.0
var duration := 1.0
var available := true

func _init(a: Array = [], title := "", glyph_du := 40.0) -> void:
	super(a, title, glyph_du)
	clickable = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func refresh() -> void:
	super.refresh()
	for glyph in _glyph_box.get_children():
		if glyph.is_queued_for_deletion():
			continue
		var veil := ColorRect.new()
		veil.name = "CooldownVeil"
		veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		veil.color = Color(0.02, 0.02, 0.03, 0.78)
		glyph.add_child(veil)
		veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var timer := UiTheme.label("", "CaptionStrong")
		timer.name = "CooldownSeconds"
		timer.add_theme_color_override("font_color", Color.WHITE)
		timer.add_theme_color_override("font_outline_color", Color.BLACK)
		timer.add_theme_constant_override("outline_size", 6)
		timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		timer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.add_child(timer)
		timer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_cooldown(remaining, duration, available)

func set_cooldown(seconds: float, total: float, ready: bool) -> void:
	remaining = maxf(0.0, seconds)
	duration = maxf(0.01, total)
	available = ready
	for glyph in _glyph_box.get_children():
		if glyph.is_queued_for_deletion():
			continue
		var veil := glyph.get_node_or_null("CooldownVeil") as ColorRect
		var timer := glyph.get_node_or_null("CooldownSeconds") as Label
		if veil:
			veil.visible = not ready
			veil.anchor_top = 1.0 - clampf(remaining / duration, 0.0, 1.0) if remaining > 0.0 else 0.0
		if timer:
			timer.text = str(ceili(remaining)) if remaining > 0.0 else ""
	_label.modulate = UiTheme.GOLD_HI if ready else UiTheme.MUTED
