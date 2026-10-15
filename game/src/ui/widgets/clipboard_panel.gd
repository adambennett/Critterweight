class_name ClipboardPanel
extends PanelContainer
## "Settings are a clipboard" (ART_DIRECTION §8): a dark sheet on a rust-brown board edge with a
## steel clip drawn across the top. Purely decorative framing; content goes inside as usual.


func _init() -> void:
	var sb := UiTheme.box(Color(UiTheme.BG, 0.94), 10, 18.0, 30.0)
	sb.content_margin_top = 44.0
	sb.border_color = Color("#6b4a2e")
	sb.set_border_width_all(10)
	sb.border_width_top = 14
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 26
	add_theme_stylebox_override("panel", sb)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS


func _draw() -> void:
	var w := minf(260.0, size.x * 0.3)
	var cx := size.x * 0.5
	var top := -2.0
	# clip base plate
	var plate := Rect2(cx - w * 0.5, top, w, 40.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#9fa6ad")
	sb.border_color = Color("#3a404c")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	sb.anti_aliasing = true
	draw_style_box(sb, plate)
	# lever ring (kept within ~12 du above the board so it never touches the tab bar)
	var ring := Rect2(cx - w * 0.22, top - 12.0, w * 0.44, 28.0)
	var sb2 := StyleBoxFlat.new()
	sb2.draw_center = false
	sb2.border_color = Color("#c7ccd2")
	sb2.set_border_width_all(7)
	sb2.set_corner_radius_all(16)
	sb2.anti_aliasing = true
	draw_style_box(sb2, ring)
	# rivets
	draw_circle(Vector2(cx - w * 0.38, top + 20.0), 6.0, Color("#3a404c"))
	draw_circle(Vector2(cx + w * 0.38, top + 20.0), 6.0, Color("#3a404c"))
