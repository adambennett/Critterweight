class_name ProfileFrame
extends RefCounted
## The profile frame (a Cannery cosmetic: Sign Fixer, Soaked, Headliner badges) drawn around the
## player's name card wherever it shows — the fight HUD, the results table and the profile screen.
## Purely cosmetic; only the active profile's own card is framed (FighterCosmetics.frame).
##   ProfileFrame.wrap(content, style)  -> the content inside a framed plate with the frame's tag
##   (returns `content` itself when no frame is equipped)

const NODE_NAME := "ProfileFrame"


static func style(profile: Dictionary = {}) -> Dictionary:
	return FighterCosmetics.frame(profile if not profile.is_empty() else Profiles.current)


static func stylebox(st: Dictionary) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var bg := Color.from_string(str(st.get("bg", "#14111C")), Color(0.08, 0.07, 0.11))
	bg.a = 0.88
	sb.bg_color = bg
	sb.border_color = Color.from_string(str(st.get("border", "#E8B923")), Color(0.9, 0.72, 0.15))
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(10)
	var glow := Color.from_string(str(st.get("glow", "#FFFFFF")), Color.WHITE)
	glow.a = 0.55
	sb.shadow_color = glow
	sb.shadow_size = 7
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


## `content` (not yet in the tree) inside a framed plate; `tag_size` = the tag's font size (theme
## units; >= 27 keeps it at >= 18 px on a 1280x800 screen).
static func wrap(content: Control, st: Dictionary, tag_size := 27) -> Control:
	if st.is_empty():
		return content
	var pc := PanelContainer.new()
	pc.name = NODE_NAME
	pc.set_meta("frame_id", str(st.get("id", "")))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_theme_stylebox_override("panel", stylebox(st))
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 0)
	pc.add_child(v)
	v.add_child(content)
	var tag := str(st.get("tag", ""))
	if tag != "":
		var l := Label.new()
		l.name = "FrameTag"
		l.text = tag
		l.add_theme_font_override("font", load("res://assets/fonts/BarlowCondensed-700.woff2"))
		l.add_theme_font_size_override("font_size", tag_size)
		l.add_theme_color_override("font_color", Color.from_string(str(st.get("glow", "#FFFFFF")), Color.WHITE))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l)
	return pc
