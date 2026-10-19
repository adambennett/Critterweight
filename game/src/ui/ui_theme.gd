class_name UiTheme
extends RefCounted
## CRITTERWEIGHT design system (docs/design/ART_DIRECTION.md §8, docs/UI.md): palette, typography,
## spacing and the code-built Theme every Screen uses.
##
## Units: all sizes are design units (du) on the 1920x1080 base canvas. The engine's canvas_items
## stretch maps du to pixels (1280x800 -> 0.667 px/du, 4K -> 2 px/du) and Settings multiplies that by
## `display.ui_scale` (and part of `access.text_scale`) through content_scale_factor. Text sizes are
## additionally multiplied by font_scale() so the text-size option scales text more than layout.
## Minimum text is 28 du (= 18.7 px at 1280x800, the Deck legibility floor).
##
## Every text style is a theme *type variation* (Label "H1", Button "MenuItem", ...) instead of a
## per-node override, so refresh() can rescale all text live when the text-size option changes.

# --- palette (ART_DIRECTION §3.1 / §8) ---------------------------------------------------------
const BG := Color("#1a1d24")
const BG_PANEL := Color(0.102, 0.114, 0.141, 0.85)
const BG_DEEP := Color("#111318")
const SURFACE := Color("#232731")
const SURFACE_HI := Color("#2e3442")
const LINE := Color("#3a404c")
const TEXT := Color("#f2f2ec")
const MUTED := Color("#9aa0ab")
const DIM := Color("#5b6168")          ## cage steel
const GOLD := Color("#c9a227")         ## circuit gold: focus, highlights
const GOLD_HI := Color("#e6c04a")
const RUST := Color("#8c3b2b")
const NEON := Color("#8bd426")         ## Glandco green
const RIM := Color("#35c1c9")          ## night rim
const DANGER := Color("#ff5a5a")
const SUCCESS := Color("#8bd426")
const WARNING := Color("#ffc43d")
const SHADOW := Color("#2b2f3a")
const CANVAS := Color("#e9e2cf")
const WARM := Color("#ffd9a0")
const TEAM := [Color("#ff5a5a"), Color("#4da3ff"), Color("#ffc43d"), Color("#b06bff")]
const TEAM_LETTERS := ["A", "B", "C", "D", "E", "F", "G", "H"]
const ELEMENT_COLORS := {"scorch": Color("#ff6b2b"), "brine": Color("#2e9be0"), "static": Color("#f7e04a"),
	"sludge": Color("#8bd426"), "grit": Color("#b8905e"), "gale": Color("#cff4f2"), "scrap": Color("#e79664"), "spectral": Color("#ac8dff")}

# --- spacing (du) ------------------------------------------------------------------------------
const GAP_XS := 6
const GAP_S := 12
const GAP_M := 20
const GAP_L := 32
const GAP_XL := 56
const SCREEN_MARGIN := 72
const FOCUS_BORDER := 4
const RADIUS := 6
const ROW_HEIGHT := 76
const FOCUS_SCALE := 1.04
const ANIM_FAST := 0.12
const ANIM := 0.16
const ANIM_SLOW := 0.24

# --- typography: base sizes in du at text scale 1.0 --------------------------------------------
const SIZES := {
	"caption": 28, "body": 30, "body_lg": 34, "label": 30, "value": 34, "button": 34, "button_sm": 30,
	"menu": 54, "tab": 32, "h3": 38, "h2": 54, "h1": 80, "display": 132, "glyph": 40,
}

const FONT_FILES := {
	"display": "res://assets/fonts/Bungee-Regular.ttf",
	"head": "res://assets/fonts/BarlowCondensed-900.woff2",
	"label": "res://assets/fonts/BarlowCondensed-700.woff2",
	"label_med": "res://assets/fonts/BarlowCondensed-500.woff2",
	"body": "res://assets/fonts/Barlow-400.woff2",
	"body_bold": "res://assets/fonts/Barlow-600.woff2",
}
## Letter tracking (+2% for condensed headers per ART_DIRECTION) as extra du between glyphs.
const TRACKING := {"display": 2, "head": 1, "label": 1}

static var _theme: Theme
static var _fonts := {}
static var _styles := {}


## The shared Theme (built once). Screens assign it to themselves; Controls inherit it.
static func get_theme() -> Theme:
	if _theme == null:
		_theme = Theme.new()
		_build(_theme)
	return _theme


## Re-applies text sizes after `access.text_scale` changed; every themed control updates live.
static func refresh() -> void:
	if _theme != null:
		_apply_sizes(_theme)


## Extra text multiplier on top of content_scale_factor: Settings applies lerp(1, text_scale, 0.6)
## to the whole canvas, so text gets the remainder to reach exactly ui_scale * text_scale.
static func font_scale() -> float:
	var ts := 1.0
	if Engine.get_main_loop() != null and (Engine.get_main_loop() as SceneTree).root.has_node("Settings"):
		ts = float(Settings.get_value("access.text_scale"))
	return ts / lerpf(1.0, ts, 0.6)


static func size(kind: String) -> int:
	return roundi(float(SIZES.get(kind, 30)) * font_scale())


static func font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var path: String = FONT_FILES.get(kind, FONT_FILES["body"])
	var base: Font = load(path)
	var f: Font = base
	if TRACKING.has(kind):
		var fv := FontVariation.new()
		fv.base_font = base
		fv.spacing_glyph = int(TRACKING[kind])
		f = fv
	_fonts[kind] = f
	return f


static func reduce_motion() -> bool:
	if Engine.get_main_loop() == null or not (Engine.get_main_loop() as SceneTree).root.has_node("Settings"):
		return false
	return bool(Settings.get_value("access.reduce_motion"))


static func team_color(team: int) -> Color:
	return TEAM[posmod(team, TEAM.size())] if team < TEAM.size() else TeamColors.color(team)


static func team_letter(team: int) -> String:
	return TEAM_LETTERS[posmod(team, TEAM_LETTERS.size())]


static func element_color(id: String) -> Color:
	if ELEMENT_COLORS.has(id):
		return ELEMENT_COLORS[id]
	return Elements.color(id) if id != "" else MUTED


# --- style boxes -------------------------------------------------------------------------------

static func box(bg: Color, radius := RADIUS, margin_h := 24.0, margin_v := 12.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin_h
	s.content_margin_right = margin_h
	s.content_margin_top = margin_v
	s.content_margin_bottom = margin_v
	s.anti_aliasing = true
	return s


static func focus_ring(radius := RADIUS + 2, expand := 3.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = GOLD
	s.set_border_width_all(FOCUS_BORDER)
	s.set_corner_radius_all(radius)
	s.set_expand_margin_all(expand)
	s.anti_aliasing = true
	return s


static func empty(margin_h := 0.0, margin_v := 0.0) -> StyleBoxEmpty:
	var s := StyleBoxEmpty.new()
	s.content_margin_left = margin_h
	s.content_margin_right = margin_h
	s.content_margin_top = margin_v
	s.content_margin_bottom = margin_v
	return s


## Named shared style boxes used by widgets that swap styles on focus (rows, cards, slots).
static func style(name_: String) -> StyleBox:
	if _styles.has(name_):
		return _styles[name_]
	var s: StyleBox
	match name_:
		"row":
			var r := box(Color(SURFACE, 0.78), RADIUS, 0.0, 8.0)
			r.content_margin_left = 44.0
			r.content_margin_right = 20.0
			s = r
		"row_focus":
			var rf := box(Color(SURFACE_HI, 0.97), RADIUS + 2, 0.0, 8.0)
			rf.content_margin_left = 44.0
			rf.content_margin_right = 20.0
			rf.border_color = GOLD
			rf.set_border_width_all(FOCUS_BORDER)
			rf.set_expand_margin_all(2.0)
			s = rf
		"row_capture":
			var rc := box(Color(RUST, 0.85), RADIUS + 2, 0.0, 8.0)
			rc.content_margin_left = 44.0
			rc.content_margin_right = 20.0
			rc.border_color = GOLD_HI
			rc.set_border_width_all(FOCUS_BORDER)
			rc.set_expand_margin_all(2.0)
			s = rc
		"card":
			var c := box(Color(SURFACE, 0.92), 8, 20.0, 16.0)
			c.border_color = LINE
			c.set_border_width_all(2)
			s = c
		"card_focus":
			var cf := box(Color(SURFACE_HI, 0.98), 10, 20.0, 16.0)
			cf.border_color = GOLD
			cf.set_border_width_all(FOCUS_BORDER)
			cf.set_expand_margin_all(2.0)
			s = cf
		"card_selected":
			var cs := box(Color(GOLD, 0.22), 8, 20.0, 16.0)
			cs.border_color = GOLD
			cs.set_border_width_all(2)
			s = cs
		"slot":
			var sl := box(BG_DEEP, RADIUS, 14.0, 6.0)
			sl.border_color = LINE
			sl.set_border_width_all(2)
			s = sl
		"slot_focus":
			var sf := box(SURFACE_HI, RADIUS + 2, 14.0, 6.0)
			sf.border_color = GOLD
			sf.set_border_width_all(FOCUS_BORDER)
			sf.set_expand_margin_all(2.0)
			s = sf
		"slot_capture":
			var sc := box(Color(RUST, 0.9), RADIUS + 2, 14.0, 6.0)
			sc.border_color = GOLD_HI
			sc.set_border_width_all(FOCUS_BORDER)
			sc.set_expand_margin_all(2.0)
			s = sc
		"chip":
			s = box(SHADOW, 16, 14.0, 2.0)
		"scroll_text":
			var st := box(Color(BG_DEEP, 0.55), RADIUS, 32.0, 24.0)
			s = st
		"scroll_text_focus":
			var stf := box(Color(BG_DEEP, 0.7), RADIUS + 2, 32.0, 24.0)
			stf.border_color = GOLD
			stf.set_border_width_all(FOCUS_BORDER)
			s = stf
		_:
			s = box(BG_PANEL)
	_styles[name_] = s
	return s


# --- theme construction ------------------------------------------------------------------------

static func _build(t: Theme) -> void:
	t.default_font = font("body")
	t.default_font_size = size("body")
	_build_labels(t)
	_build_buttons(t)
	_build_panels(t)
	_build_inputs(t)
	_apply_sizes(t)


static func _label_variation(t: Theme, name_: String, font_kind: String, color: Color, outline := 0) -> void:
	t.set_type_variation(name_, "Label")
	t.set_font(&"font", name_, font(font_kind))
	t.set_color(&"font_color", name_, color)
	if outline > 0:
		t.set_constant(&"outline_size", name_, outline)
		t.set_color(&"font_outline_color", name_, BG_DEEP)


static func _build_labels(t: Theme) -> void:
	t.set_color(&"font_color", &"Label", TEXT)
	t.set_font(&"font", &"Label", font("body"))
	t.set_constant(&"line_spacing", &"Label", 2)
	_label_variation(t, "Display", "display", TEXT, 10)
	_label_variation(t, "H1", "head", TEXT, 8)
	_label_variation(t, "H2", "head", TEXT, 6)
	_label_variation(t, "H3", "label", TEXT)
	_label_variation(t, "Eyebrow", "label", GOLD)
	_label_variation(t, "Body", "body", TEXT)
	_label_variation(t, "BodyStrong", "body_bold", TEXT)
	_label_variation(t, "BodyMuted", "body", MUTED)
	_label_variation(t, "Caption", "body", MUTED)
	_label_variation(t, "CaptionStrong", "body_bold", TEXT)
	_label_variation(t, "Value", "label", TEXT)
	_label_variation(t, "ValueGold", "label", GOLD)
	_label_variation(t, "Danger", "body_bold", DANGER)
	_label_variation(t, "Success", "body_bold", SUCCESS)
	_label_variation(t, "Warning", "body_bold", WARNING)
	_label_variation(t, "Stat", "head", TEXT)
	_label_variation(t, "Glyph", "label", BG)
	# rich text (credits, notices, help)
	t.set_font(&"normal_font", &"RichTextLabel", font("body"))
	t.set_font(&"bold_font", &"RichTextLabel", font("body_bold"))
	t.set_font(&"italics_font", &"RichTextLabel", font("body"))
	t.set_font(&"mono_font", &"RichTextLabel", font("label_med"))
	t.set_color(&"default_color", &"RichTextLabel", TEXT)
	t.set_stylebox(&"normal", &"RichTextLabel", empty())
	t.set_stylebox(&"focus", &"RichTextLabel", empty())
	t.set_stylebox(&"panel", &"TooltipPanel", box(BG, 6, 18.0, 10.0))
	t.set_font(&"font", &"TooltipLabel", font("body"))
	t.set_color(&"font_color", &"TooltipLabel", TEXT)


static func _button_styles(t: Theme, type: String, normal: StyleBox, hover: StyleBox, pressed: StyleBox,
		disabled: StyleBox, focus: StyleBox) -> void:
	t.set_stylebox(&"normal", type, normal)
	t.set_stylebox(&"hover", type, hover)
	t.set_stylebox(&"pressed", type, pressed)
	t.set_stylebox(&"hover_pressed", type, pressed)
	t.set_stylebox(&"disabled", type, disabled)
	t.set_stylebox(&"focus", type, focus)


static func _button_colors(t: Theme, type: String, normal: Color, focus: Color, pressed: Color, disabled: Color) -> void:
	t.set_color(&"font_color", type, normal)
	t.set_color(&"font_hover_color", type, focus)
	t.set_color(&"font_focus_color", type, focus)
	t.set_color(&"font_pressed_color", type, pressed)
	t.set_color(&"font_hover_pressed_color", type, pressed)
	t.set_color(&"font_disabled_color", type, disabled)
	t.set_color(&"icon_normal_color", type, normal)
	t.set_color(&"icon_hover_color", type, focus)
	t.set_color(&"icon_focus_color", type, focus)
	t.set_color(&"icon_pressed_color", type, pressed)
	t.set_color(&"icon_hover_pressed_color", type, pressed)
	t.set_color(&"icon_disabled_color", type, disabled)


static func _build_buttons(t: Theme) -> void:
	# Default button: dark slab with a darker lip; focus = gold ring (+ chevron and 4% scale in UiButton).
	var normal := box(Color(SURFACE, 0.95), RADIUS, 24.0, 12.0)
	normal.content_margin_left = 40.0
	normal.border_color = Color("#14161b")
	normal.border_width_bottom = 3
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = SURFACE_HI
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = GOLD
	pressed.border_color = Color("#8a6d12")
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color("#1c1f26", 0.8)
	disabled.border_width_bottom = 0
	_button_styles(t, "Button", normal, hover, pressed, disabled, focus_ring())
	_button_colors(t, "Button", TEXT, Color.WHITE, BG, DIM)
	t.set_font(&"font", &"Button", font("body_bold"))
	t.set_constant(&"h_separation", &"Button", 14)
	t.set_constant(&"icon_max_width", &"Button", 44)
	t.set_constant(&"outline_size", &"Button", 0)

	# Main menu item: poster typography, no slab until focused.
	t.set_type_variation(&"MenuItem", &"Button")
	var mi_normal := empty(28.0, 4.0)
	mi_normal.content_margin_left = 52.0
	var mi_hover := box(Color(SURFACE, 0.55), RADIUS, 28.0, 4.0)
	mi_hover.content_margin_left = 52.0
	var mi_pressed := box(Color(GOLD, 0.9), RADIUS, 28.0, 4.0)
	mi_pressed.content_margin_left = 52.0
	var mi_focus := focus_ring(RADIUS + 2, 2.0)
	mi_focus.draw_center = true
	mi_focus.bg_color = Color(GOLD, 0.16)
	_button_styles(t, "MenuItem", mi_normal, mi_hover, mi_pressed, mi_normal, mi_focus)
	_button_colors(t, "MenuItem", TEXT, Color.WHITE, BG, DIM)
	t.set_font(&"font", &"MenuItem", font("head"))
	t.set_constant(&"h_separation", &"MenuItem", 20)
	t.set_constant(&"icon_max_width", &"MenuItem", 52)

	# Sub-menu item (second column): condensed bold.
	t.set_type_variation(&"SubItem", &"Button")
	var si_normal := box(Color(SURFACE, 0.82), RADIUS, 24.0, 10.0)
	si_normal.content_margin_left = 48.0
	var si_hover := si_normal.duplicate() as StyleBoxFlat
	si_hover.bg_color = SURFACE_HI
	var si_pressed := si_normal.duplicate() as StyleBoxFlat
	si_pressed.bg_color = GOLD
	_button_styles(t, "SubItem", si_normal, si_hover, si_pressed, si_normal, focus_ring())
	_button_colors(t, "SubItem", TEXT, Color.WHITE, BG, DIM)
	t.set_font(&"font", &"SubItem", font("label"))
	t.set_constant(&"h_separation", &"SubItem", 16)
	t.set_constant(&"icon_max_width", &"SubItem", 40)

	# Danger (destructive confirmations): rust slab, still gold focus ring.
	t.set_type_variation(&"DangerButton", &"Button")
	var dn := normal.duplicate() as StyleBoxFlat
	dn.bg_color = Color(RUST, 0.95)
	var dh := dn.duplicate() as StyleBoxFlat
	dh.bg_color = Color("#a8483a")
	var dp := dn.duplicate() as StyleBoxFlat
	dp.bg_color = DANGER
	_button_styles(t, "DangerButton", dn, dh, dp, disabled, focus_ring())
	_button_colors(t, "DangerButton", TEXT, Color.WHITE, BG, DIM)

	# Primary call to action (Start fight, Confirm): gold slab.
	t.set_type_variation(&"PrimaryButton", &"Button")
	var pn := normal.duplicate() as StyleBoxFlat
	pn.bg_color = Color("#3b3218")
	pn.border_color = Color("#7a6216")      # dull brass: must never look like the gold focus ring
	pn.set_border_width_all(2)
	var ph := pn.duplicate() as StyleBoxFlat
	ph.bg_color = Color("#54461c")
	var pp := pn.duplicate() as StyleBoxFlat
	pp.bg_color = GOLD
	_button_styles(t, "PrimaryButton", pn, ph, pp, disabled, focus_ring())
	_button_colors(t, "PrimaryButton", GOLD_HI, Color.WHITE, BG, DIM)
	t.set_font(&"font", &"PrimaryButton", font("label"))

	# Tabs: text tabs with a gold underline on the active one (TabStrip swaps variations).
	t.set_type_variation(&"TabButton", &"Button")
	var tn := empty(22.0, 8.0)
	var th := box(Color(SURFACE, 0.6), RADIUS, 22.0, 8.0)
	_button_styles(t, "TabButton", tn, th, th, tn, empty(22.0, 8.0))
	_button_colors(t, "TabButton", MUTED, TEXT, TEXT, DIM)
	t.set_font(&"font", &"TabButton", font("label"))
	t.set_type_variation(&"TabButtonActive", &"Button")
	var ta := box(Color(GOLD, 0.18), RADIUS, 22.0, 8.0)
	ta.border_color = GOLD
	ta.border_width_bottom = 5
	_button_styles(t, "TabButtonActive", ta, ta, ta, ta, empty(22.0, 8.0))
	_button_colors(t, "TabButtonActive", TEXT, Color.WHITE, Color.WHITE, DIM)
	t.set_font(&"font", &"TabButtonActive", font("label"))

	# Small flat button (arrows, prompt chips, icon buttons): no slab.
	t.set_type_variation(&"FlatButton", &"Button")
	var fl := empty(6.0, 2.0)
	_button_styles(t, "FlatButton", fl, box(Color(SURFACE_HI, 0.6), 4, 6.0, 2.0), box(Color(GOLD, 0.5), 4, 6.0, 2.0), fl, empty(6.0, 2.0))
	_button_colors(t, "FlatButton", TEXT, Color.WHITE, Color.WHITE, DIM)


static func _panel_variation(t: Theme, name_: String, s: StyleBox) -> void:
	t.set_type_variation(name_, "PanelContainer")
	t.set_stylebox(&"panel", name_, s)


static func _build_panels(t: Theme) -> void:
	t.set_stylebox(&"panel", &"PanelContainer", box(BG_PANEL, 10, 32.0, 28.0))
	t.set_stylebox(&"panel", &"Panel", box(BG_PANEL, 10))
	_panel_variation(t, "PanelSolid", box(BG, 10, 32.0, 28.0))
	var help := box(Color(SURFACE, 0.9), RADIUS, 32.0, 28.0)
	help.border_color = GOLD
	help.border_width_left = 6
	_panel_variation(t, "PanelHelp", help)
	var poster := box(Color(BG, 0.92), 4, 40.0, 36.0)
	poster.border_color = GOLD
	poster.border_width_top = 8
	poster.shadow_color = Color(0, 0, 0, 0.35)
	poster.shadow_size = 24
	_panel_variation(t, "PanelPoster", poster)
	var dialog := box(Color(BG, 0.98), 12, 48.0, 40.0)
	dialog.border_color = LINE
	dialog.set_border_width_all(2)
	dialog.border_width_top = 8
	dialog.shadow_color = Color(0, 0, 0, 0.5)
	dialog.shadow_size = 40
	_panel_variation(t, "PanelDialog", dialog)
	var dialog_danger := dialog.duplicate() as StyleBoxFlat
	dialog_danger.border_color = DANGER
	_panel_variation(t, "PanelDialogDanger", dialog_danger)
	_panel_variation(t, "PanelRow", style("row"))
	_panel_variation(t, "PanelCard", style("card"))
	_panel_variation(t, "PanelChip", style("chip"))
	var toast := box(Color(BG, 0.96), RADIUS, 24.0, 14.0)
	toast.border_width_left = 8
	toast.border_color = RIM
	toast.shadow_color = Color(0, 0, 0, 0.4)
	toast.shadow_size = 16
	_panel_variation(t, "PanelToast", toast)
	_panel_variation(t, "PanelClear", empty())
	var banner := box(Color(RUST, 0.92), RADIUS, 28.0, 14.0)
	banner.border_color = WARNING
	banner.border_width_left = 8
	_panel_variation(t, "PanelBanner", banner)


static func _build_inputs(t: Theme) -> void:
	var le := box(BG_DEEP, RADIUS, 18.0, 10.0)
	le.border_color = LINE
	le.set_border_width_all(2)
	var le_focus := le.duplicate() as StyleBoxFlat
	le_focus.border_color = GOLD
	le_focus.set_border_width_all(FOCUS_BORDER)
	t.set_stylebox(&"normal", &"LineEdit", le)
	t.set_stylebox(&"focus", &"LineEdit", le_focus)
	t.set_stylebox(&"read_only", &"LineEdit", le)
	t.set_font(&"font", &"LineEdit", font("body_bold"))
	t.set_color(&"font_color", &"LineEdit", TEXT)
	t.set_color(&"font_placeholder_color", &"LineEdit", DIM)
	t.set_color(&"caret_color", &"LineEdit", GOLD_HI)
	t.set_color(&"selection_color", &"LineEdit", Color(GOLD, 0.35))
	t.set_constant(&"caret_width", &"LineEdit", 3)
	# slider: track + gold fill; grabber is a crisp SVG disc
	var track := box(BG_DEEP, 5, 0.0, 6.0)
	track.border_color = LINE
	track.set_border_width_all(2)
	var fill := box(GOLD, 5, 0.0, 6.0)
	var fill_hi := box(GOLD_HI, 5, 0.0, 6.0)
	t.set_stylebox(&"slider", &"HSlider", track)
	t.set_stylebox(&"grabber_area", &"HSlider", fill)
	t.set_stylebox(&"grabber_area_highlight", &"HSlider", fill_hi)
	var grab := _svg_tex("<svg xmlns='http://www.w3.org/2000/svg' width='30' height='30'><circle cx='15' cy='15' r='12' fill='#f2f2ec' stroke='#1a1d24' stroke-width='3'/></svg>")
	t.set_icon(&"grabber", &"HSlider", grab)
	t.set_icon(&"grabber_highlight", &"HSlider", grab)
	t.set_icon(&"grabber_disabled", &"HSlider", grab)
	t.set_constant(&"center_grabber", &"HSlider", 1)
	# scroll bars
	var sb := box(Color(BG_DEEP, 0.6), 5, 4.0, 4.0)
	var grabber := box(DIM, 5)
	var grabber_hi := box(MUTED, 5)
	var grabber_pr := box(GOLD, 5)
	for sbt in [&"VScrollBar", &"HScrollBar"]:
		t.set_stylebox(&"scroll", sbt, sb)
		t.set_stylebox(&"scroll_focus", sbt, sb)
		t.set_stylebox(&"grabber", sbt, grabber)
		t.set_stylebox(&"grabber_highlight", sbt, grabber_hi)
		t.set_stylebox(&"grabber_pressed", sbt, grabber_pr)
	t.set_stylebox(&"panel", &"ScrollContainer", empty())
	t.set_stylebox(&"focus", &"ScrollContainer", empty())
	# progress bars (countdowns, meters)
	t.set_stylebox(&"background", &"ProgressBar", box(BG_DEEP, 5, 0.0, 0.0))
	t.set_stylebox(&"fill", &"ProgressBar", box(GOLD, 5, 0.0, 0.0))
	t.set_font(&"font", &"ProgressBar", font("label"))
	t.set_color(&"font_color", &"ProgressBar", TEXT)


static func _svg_tex(svg: String) -> Texture2D:
	return DPITexture.create_from_string(svg)


static func _apply_sizes(t: Theme) -> void:
	t.default_font_size = size("body")
	var label_sizes := {"Display": "display", "H1": "h1", "H2": "h2", "H3": "h3", "Eyebrow": "caption",
		"Body": "body", "BodyStrong": "body", "BodyMuted": "body", "Caption": "caption", "CaptionStrong": "caption",
		"Value": "value", "ValueGold": "value", "Danger": "body", "Success": "body", "Warning": "body", "Stat": "h2",
		"Glyph": "caption"}
	t.set_font_size(&"font_size", &"Label", size("body"))
	for v in label_sizes:
		t.set_font_size(&"font_size", v, size(str(label_sizes[v])))
	var button_sizes := {"Button": "button", "MenuItem": "menu", "SubItem": "h3", "DangerButton": "button",
		"PrimaryButton": "h3", "TabButton": "tab", "TabButtonActive": "tab", "FlatButton": "button_sm"}
	for b in button_sizes:
		t.set_font_size(&"font_size", b, size(str(button_sizes[b])))
	t.set_font_size(&"font_size", &"LineEdit", size("body_lg"))
	t.set_font_size(&"font_size", &"TooltipLabel", size("caption"))
	t.set_font_size(&"font_size", &"ProgressBar", size("caption"))
	for rt in [&"normal_font_size", &"bold_font_size", &"italics_font_size", &"mono_font_size"]:
		t.set_font_size(rt, &"RichTextLabel", size("body"))


# --- small factories used everywhere -----------------------------------------------------------

static func label(text: String, variation := "Body", autowrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if autowrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func vbox(sep := GAP_S) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func hbox(sep := GAP_S) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func spacer(expand := true, min_size := 0.0) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(min_size, min_size)
	return c


static func panel(variation := "", margin_override := -1.0) -> PanelContainer:
	var p := PanelContainer.new()
	if variation != "":
		p.theme_type_variation = variation
	if margin_override >= 0.0:
		# read from OUR theme: the node is not in the tree yet, so p.get_theme_stylebox() would
		# resolve Godot's default (translucent) panel instead
		var type := variation if variation != "" else "PanelContainer"
		var sb := get_theme().get_stylebox(&"panel", type).duplicate() as StyleBox
		sb.content_margin_left = margin_override
		sb.content_margin_right = margin_override
		sb.content_margin_top = margin_override
		sb.content_margin_bottom = margin_override
		p.add_theme_stylebox_override("panel", sb)
	return p


static func margin(all := SCREEN_MARGIN, top := -1, bottom := -1) -> MarginContainer:
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", all)
	m.add_theme_constant_override("margin_right", all)
	m.add_theme_constant_override("margin_top", all if top < 0 else top)
	m.add_theme_constant_override("margin_bottom", all if bottom < 0 else bottom)
	return m


## Human formatting for durations (stats screens).
static func duration_text(seconds: float) -> String:
	var s := int(seconds)
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	return "%dm %02ds" % [s / 60, s % 60]
