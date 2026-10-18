class_name ArenaCatalog
## Arena parts catalog (data-driven, docs/ARENAS_AND_EDITOR.md "Prop catalog"):
##   * placeable props and mode markers  <- content `props/*.json` entries (schema prop.schema.json)
##   * arena bases                       <- arena entries that carry a `base_def` block
##                                          (content `arenas/arena_<base>.json`)
## Sources are the Content registry (core + enabled mods, already merged in load order). When
## Content reloads (mods toggled) the catalog notices the new tables and re-normalizes lazily.
## Every entry is normalized here once so the builder, hazards runtime, view, validator and
## editor all read the same defaults.
##
## Invariants: ids are unique (Content enforces it); marker types start with "marker_"; a prop
## with class "marker" never gets a physics body; costs are integers >= 0.

const CLASSES := ["obstacle", "wall", "hazard", "pickup", "marker", "floor"]
const TABS := ["obstacles", "walls", "hazards", "pickups", "markers"]
const TAB_LABELS := {"obstacles": "Obstacles", "walls": "Walls", "hazards": "Hazards", "pickups": "Pickups", "markers": "Markers"}
const CORE_PROPS := "res://content/core/props"
const CORE_ARENAS := "res://content/core/arenas"
const EDITOR_TEMPLATES := "res://assets/data/editor_arena_templates.json"

static var _props := {}            ## id -> normalized prop entry
static var _order: Array = []      ## prop ids in catalog (file) order
static var _bases := {}            ## base id -> normalized base_def
static var _editor_templates := {} ## creation templates, deliberately absent from playable Content
static var _base_arena := {}       ## base id -> arena id that defines it
static var _src_props = null       ## identity of the Content table we normalized last
static var _src_arenas = null
static var _loaded := false
static var errors: PackedStringArray = PackedStringArray()


# =====================================================================================
# Loading
# =====================================================================================

static func _content() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("Content")
	return null


## Re-reads the catalog when Content's tables changed (cheap identity check).
static func ensure() -> void:
	var c := _content()
	var tp = null
	var ta = null
	if c != null:
		var tables: Dictionary = c.get("tables")
		tp = tables.get("props", null)
		ta = tables.get("arenas", null)
	if _loaded and is_same(tp, _src_props) and is_same(ta, _src_arenas):
		return
	_load(tp, ta)
	_loaded = true


static func reload() -> void:
	_loaded = false
	ensure()


static func _load(tp, ta) -> void:
	_props.clear()
	_order.clear()
	_bases.clear()
	_base_arena.clear()
	_editor_templates.clear()
	errors.clear()
	var prop_entries: Array = []
	var arena_entries: Array = []
	# Content tables keep insertion (= load) order: core files sorted by name, items in file order.
	if tp != null and typeof(tp) == TYPE_DICTIONARY and not (tp as Dictionary).is_empty():
		for k in (tp as Dictionary).keys():
			prop_entries.append(tp[k])
	else:
		prop_entries = _read_dir_items(CORE_PROPS)
	if ta != null and typeof(ta) == TYPE_DICTIONARY and not (ta as Dictionary).is_empty():
		for k in (ta as Dictionary).keys():
			arena_entries.append(ta[k])
	else:
		arena_entries = _read_dir_items(CORE_ARENAS)
	for e in prop_entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var errs := Schema.validate_named(e, "prop", "props#%s" % str(e.get("id", "?")))
		if not errs.is_empty():
			errors.append_array(errs)
			continue
		var n := normalize_prop(e)
		_props[n["id"]] = n
		_order.append(n["id"])
	for a in arena_entries:
		if typeof(a) != TYPE_DICTIONARY or typeof(a.get("base_def", null)) != TYPE_DICTIONARY:
			continue
		var bd := normalize_base(a["base_def"], str(a.get("base", "")))
		_bases[bd["id"]] = bd
		_base_arena[bd["id"]] = str(a.get("id", ""))
	# These bases must resolve at runtime for saved layouts, but their blank creation
	# templates must never become match/campaign/compendium arena entries.
	var templates = JSON.parse_string(FileAccess.get_file_as_string(EDITOR_TEMPLATES))
	if templates is Dictionary:
		for entry in templates.get("items", []):
			var errs := Schema.validate_named(entry, "arena", EDITOR_TEMPLATES)
			if not errs.is_empty():
				errors.append_array(errs)
				continue
			var bd := normalize_base(entry["base_def"], str(entry["base"]))
			_bases[bd["id"]] = bd
			_base_arena.erase(bd["id"])
			_editor_templates[bd["id"]] = entry
	_src_props = tp
	_src_arenas = ta


static func _read_dir_items(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	var files := d.get_files()
	files.sort()
	for f in files:
		if not f.ends_with(".json"):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		if parsed.has("items") and typeof(parsed["items"]) == TYPE_ARRAY:
			out.append_array(parsed["items"])
		else:
			out.append(parsed)
	return out


# =====================================================================================
# Normalization
# =====================================================================================

static func normalize_prop(e: Dictionary) -> Dictionary:
	var n: Dictionary = e.duplicate(true)
	var id := str(n.get("id", ""))
	var cls := str(n.get("class", "obstacle"))
	n["id"] = id
	n["name"] = str(n.get("name", id))
	n["class"] = cls
	n["cost"] = int(n.get("cost", 0))
	n["palette"] = bool(n.get("palette", true))
	var default_tab := "obstacles"
	match cls:
		"wall": default_tab = "walls"
		"hazard": default_tab = "hazards"
		"pickup": default_tab = "pickups"
		"marker": default_tab = "markers"
	n["tab"] = str(n.get("tab", default_tab))
	n["description"] = str(n.get("description", ""))
	n["element"] = str(n.get("element", ""))
	n["icon"] = str(n.get("icon", n["element"]))
	var fp: Dictionary = n.get("footprint", {})
	var fshape := str(fp.get("shape", "circle" if cls == "marker" else "box"))
	var fsize: Array = fp.get("size", [1.0, 1.0])
	n["footprint"] = {"shape": fshape, "size": Vector2(float(fsize[0]), float(fsize[1] if fsize.size() > 1 else fsize[0]))}
	n["height"] = float(n.get("height", 1.0))
	n["body"] = str(n.get("body", "none" if cls in ["marker", "pickup"] else "static"))
	n["solid"] = bool(n.get("solid", cls in ["obstacle", "wall"]))
	n["hazard"] = bool(n.get("hazard", cls == "hazard"))
	n["hp"] = float(n.get("hp", 0.0))
	n["splat"] = bool(n.get("splat", n["body"] == "static" and n["solid"]))
	n["rotation_step"] = float(n.get("rotation_step", 15.0))
	n["max_per_layout"] = int(n.get("max_per_layout", 0))
	n["behaviour"] = str(n.get("behaviour", "static"))
	n["params"] = n.get("params", {})
	n["timed"] = n.get("timed", {})
	n["on_destroy"] = n.get("on_destroy", {})
	n["touch"] = n.get("touch", {})
	n["push"] = n.get("push", {})
	n["bounce"] = n.get("bounce", {})
	n["pickup"] = n.get("pickup", {})
	n["visual"] = str(n.get("visual", id))
	n["is_marker"] = cls == "marker"
	# the layout hazard cap (ARENAS.md §3) counts timed hazards and destructible elemental ones
	var timed_def: Dictionary = n["timed"]
	n["limited_hazard"] = bool(n.get("limited_hazard", bool(n["hazard"]) and (not timed_def.is_empty() or (float(n["hp"]) > 0.0 and str(n["element"]) != ""))))
	if cls == "marker":
		var m: Dictionary = n.get("marker", {})
		n["marker"] = {"name": str(m.get("name", id.trim_prefix("marker_"))), "max": int(m.get("max", 8)),
			"teams": bool(m.get("teams", false)), "team_max": int(m.get("team_max", 4)), "min": int(m.get("min", 0)),
			"size": MathX.vec3(m.get("size", [0.6, 0.0, 0.6]))}
		n["body"] = "none"
		n["solid"] = false
		n["hazard"] = false
	return n


## Normalizes a base definition (geometry, hazards, quirks, variants). `fallback_id` is the
## arena entry's "base" value (base defs may omit their own id).
static func normalize_base(b: Dictionary, fallback_id := "") -> Dictionary:
	var n: Dictionary = b.duplicate(true)
	var id := str(n.get("id", fallback_id))
	n["id"] = id
	n["name"] = str(n.get("name", id.capitalize()))
	n["shape"] = str(n.get("shape", "octagon"))
	n["style"] = str(n.get("style", id))
	var sz: Array = n.get("size", [12.0, 12.0])
	n["size"] = Vector2(float(sz[0]), float(sz[1] if sz.size() > 1 else sz[0]))
	var smin: Array = n.get("size_min", sz)
	var smax: Array = n.get("size_max", sz)
	n["size_min"] = Vector2(float(smin[0]), float(smin[1] if smin.size() > 1 else smin[0]))
	n["size_max"] = Vector2(float(smax[0]), float(smax[1] if smax.size() > 1 else smax[0]))
	n["size_step"] = float(n.get("size_step", 0.5))
	n["uniform"] = bool(n.get("uniform", n["shape"] in ["octagon", "circle"]))
	var nt: Array = n.get("notch", [0.0, 0.0])
	n["notch"] = Vector2(float(nt[0]), float(nt[1] if nt.size() > 1 else nt[0]))
	n["wall_height"] = float(n.get("wall_height", 2.4))
	n["open_edges"] = bool(n.get("open_edges", float(n["wall_height"]) <= 0.01))
	n["allow_pits"] = bool(n.get("allow_pits", n["open_edges"]))
	n["quirks"] = n.get("quirks", {})
	n["hazards"] = n.get("hazards", [])
	n["areas"] = n.get("areas", [])
	n["builtins"] = n.get("builtins", [])
	n["variants"] = n.get("variants", {"default": {"label": "Default"}})
	n["default_variant"] = str(n.get("default_variant", (n["variants"] as Dictionary).keys()[0] if not (n["variants"] as Dictionary).is_empty() else "default"))
	n["palette"] = n.get("palette", {})
	n["ringout"] = n.get("ringout", {})
	n["description"] = str(n.get("description", ""))
	return n


# =====================================================================================
# Queries
# =====================================================================================

static func prop(id: String) -> Dictionary:
	ensure()
	return _props.get(id, {})


static func has_prop(id: String) -> bool:
	ensure()
	return _props.has(id)


static func prop_ids() -> Array:
	ensure()
	return _order.duplicate()


## Palette entries (normalized dicts) for an editor tab ("" = all), in catalog order.
static func palette(tab := "") -> Array:
	ensure()
	var out := []
	for id in _order:
		var p: Dictionary = _props[id]
		if not bool(p["palette"]):
			continue
		if tab != "" and str(p["tab"]) != tab:
			continue
		out.append(p)
	return out


static func base(id: String) -> Dictionary:
	ensure()
	return _bases.get(id, {})


static func base_ids() -> Array:
	ensure()
	var out: Array = _bases.keys()
	out.sort()
	# core bases first in their canonical order
	var canonical := ["gullet", "drydock", "crusher", "rooftop"]
	var ordered := []
	for c in canonical:
		if out.has(c):
			ordered.append(c)
	for o in out:
		if not ordered.has(o):
			ordered.append(o)
	return ordered


static func editor_template(base_id: String) -> Dictionary:
	ensure()
	return (_editor_templates.get(base_id, {}) as Dictionary).duplicate(true)


static func base_arena_id(base_id: String) -> String:
	ensure()
	return str(_base_arena.get(base_id, ""))


static func is_marker(type_id: String) -> bool:
	return type_id.begins_with("marker_")


## "marker_spawn" -> "spawn"
static func marker_name(type_id: String) -> String:
	var p := prop(type_id)
	if not p.is_empty() and p.has("marker"):
		return str(p["marker"]["name"])
	return type_id.trim_prefix("marker_")


## "spawn" -> "marker_spawn" (the catalog type that edits this marker list)
static func marker_type(name_: String) -> String:
	ensure()
	for id in _order:
		var p: Dictionary = _props[id]
		if bool(p["is_marker"]) and str(p["marker"]["name"]) == name_:
			return id
	return "marker_" + name_


# =====================================================================================
# Footprints (XZ). A placed item is {type, pos: Vector3, yaw (rad), scale, pos2?, params}.
# Local -> world uses Godot's Basis(UP, yaw): local +X -> (cos y, -sin y), local +Z -> (sin y, cos y).
# =====================================================================================

static func footprint_size(item: Dictionary, def: Dictionary) -> Vector2:
	var fp: Dictionary = def.get("footprint", {})
	var s: Vector2 = fp.get("size", Vector2(0.6, 0.6))
	var params: Dictionary = item.get("params", {})
	if params.has("length"):
		s.x = float(params["length"])
	return s * float(item.get("scale", 1.0))


static func footprint_shape(def: Dictionary) -> String:
	return str(def.get("footprint", {}).get("shape", "box"))


static func to_local(item: Dictionary, p: Vector2) -> Vector2:
	var c: Vector3 = item["pos"]
	var y := float(item.get("yaw", 0.0))
	var d := Vector2(p.x - c.x, p.y - c.z)
	return Vector2(d.x * cos(y) - d.y * sin(y), d.x * sin(y) + d.y * cos(y))


static func to_world(item: Dictionary, l: Vector2) -> Vector2:
	var c: Vector3 = item["pos"]
	var y := float(item.get("yaw", 0.0))
	return Vector2(c.x + l.x * cos(y) + l.y * sin(y), c.z - l.x * sin(y) + l.y * cos(y))


## Signed distance from p (XZ) to the item's footprint (negative inside).
static func footprint_distance(item: Dictionary, def: Dictionary, p: Vector2) -> float:
	var shape := footprint_shape(def)
	var s := footprint_size(item, def)
	var c: Vector3 = item["pos"]
	match shape:
		"circle", "pair":
			var dd := p.distance_to(Vector2(c.x, c.z)) - s.x * 0.5
			if shape == "pair" and item.has("pos2"):
				var c2: Vector3 = item["pos2"]
				dd = minf(dd, p.distance_to(Vector2(c2.x, c2.z)) - s.x * 0.5)
			return dd
		"none":
			return p.distance_to(Vector2(c.x, c.z))
	var l := to_local(item, p)
	var qx := absf(l.x) - s.x * 0.5
	var qz := absf(l.y) - s.y * 0.5
	if qx <= 0.0 and qz <= 0.0:
		return maxf(qx, qz)
	return Vector2(maxf(qx, 0.0), maxf(qz, 0.0)).length()


## Outline sample points (box corners, 12 points per circle) for bounds checks and drawing.
static func footprint_outline(item: Dictionary, def: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	var shape := footprint_shape(def)
	var s := footprint_size(item, def)
	var c: Vector3 = item["pos"]
	if shape in ["circle", "pair", "none"]:
		var centers: Array = [Vector2(c.x, c.z)]
		if shape == "pair" and item.has("pos2"):
			var c2: Vector3 = item["pos2"]
			centers.append(Vector2(c2.x, c2.z))
		for cc: Vector2 in centers:
			for i in 12:
				var a := TAU * i / 12.0
				out.append(cc + Vector2(cos(a), sin(a)) * s.x * 0.5)
		return out
	for l in [Vector2(-s.x, -s.y), Vector2(s.x, -s.y), Vector2(s.x, s.y), Vector2(-s.x, s.y)]:
		out.append(to_world(item, l * 0.5))
	return out


static func footprint_aabb(item: Dictionary, def: Dictionary) -> Rect2:
	var pts := footprint_outline(item, def)
	var r := Rect2(pts[0], Vector2.ZERO)
	for v in pts:
		r = r.expand(v)
	return r


static func footprint_area(item: Dictionary, def: Dictionary) -> float:
	var s := footprint_size(item, def)
	match footprint_shape(def):
		"circle":
			return PI * s.x * s.x * 0.25
		"pair":
			return PI * s.x * s.x * 0.5
		"none":
			return 0.0
	return s.x * s.y
