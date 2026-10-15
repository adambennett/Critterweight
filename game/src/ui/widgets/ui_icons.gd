class_name UiIcons
extends RefCounted
## SVG icon access. Icons live in res://assets/ui/icons/<name>.svg and are imported as DPITexture
## (crisp at every UI scale). UI glyphs are flat #f2f2ec shapes tinted with `modulate`; element
## icons (`el_<element>`) carry their colour, a light outline and a dark halo, and are always shown
## next to the element name (colour is never the only cue).

const DIR := "res://assets/ui/icons/"

static var _cache := {}
static var _missing := {}


static func tex(name_: String) -> Texture2D:
	if _cache.has(name_):
		return _cache[name_]
	var path := DIR + name_ + ".svg"
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	elif not _missing.has(name_):
		_missing[name_] = true
		Log.w("ui", "missing icon %s" % path)
	_cache[name_] = t
	return t


static func element_tex(element_id: String) -> Texture2D:
	return tex("el_" + element_id) if element_id != "" else null


## A TextureRect showing an icon at `size_du` (square), tinted by `color`.
static func rect(name_: String, size_du := 40.0, color := Color.WHITE) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex(name_)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size_du, size_du)
	r.modulate = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


## Element icon + element name (and optionally the status it inflicts), e.g. "[flame] SCORCH · Sizzle".
static func element_badge(element_id: String, size_du := 40.0, with_status := false) -> HBoxContainer:
	var b := UiTheme.hbox(UiTheme.GAP_S)
	if element_id == "":
		b.add_child(UiTheme.label("No element", "BodyMuted"))
		return b
	var r := TextureRect.new()
	r.texture = element_tex(element_id)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size_du, size_du)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(r)
	var name_l := UiTheme.label(Elements.display_name(element_id).to_upper(), "Value")
	name_l.add_theme_color_override("font_color", UiTheme.element_color(element_id).lerp(UiTheme.TEXT, 0.35))
	b.add_child(name_l)
	if with_status:
		var st := status_name(element_id)
		if st != "":
			b.add_child(UiTheme.label("inflicts %s" % st, "Caption"))
	return b


static func status_name(element_id: String) -> String:
	var table: Dictionary = Content.tables.get("_elements", {})
	for e in table.get("elements", []):
		if typeof(e) == TYPE_DICTIONARY and str(e.get("id", "")) == element_id:
			return str(e.get("status_name", ""))
	return ""
