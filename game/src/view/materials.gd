class_name Materials
## Shared stylized material factory (see docs/ART_DIRECTION.md). Keeps every surface in one
## cohesive "chunky toy under arena lights" look: toon-ramped PBR, soft rim, optional outline.

static var _cache := {}
static var _creature_shader: Shader
static var _outline_shader: Shader


## Stylized PBR surface. rough/metal follow PBR; rim adds the readable silhouette edge.
static func toon(color: Color, rough := 0.7, metal := 0.0, rim := 0.35, emissive := Color.BLACK) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f|%s" % [color.to_html(), rough, metal, rim, emissive.to_html()]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	if rim > 0.0:
		m.rim_enabled = true
		m.rim = rim
		m.rim_tint = 0.4
	if emissive != Color.BLACK:
		m.emission_enabled = true
		m.emission = emissive
		m.emission_energy_multiplier = 2.0
	_cache[key] = m
	return m


static func unshaded(color: Color, transparent := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	if transparent or color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## Creature skin: toon PBR with vertex colors, rim light, hit flash, juiced glow and up to 8
## localized bruise points (cosmetic injury feedback). Parameters set per CreatureView.
static func creature_material() -> ShaderMaterial:
	if _creature_shader == null:
		_creature_shader = load("res://src/view/shaders/creature.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _creature_shader
	return m


static func outline_material(width := 0.012, color := Color(0.05, 0.03, 0.07)) -> ShaderMaterial:
	if _outline_shader == null:
		_outline_shader = load("res://src/view/shaders/outline.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _outline_shader
	m.set_shader_parameter("width", width)
	m.set_shader_parameter("color", color)
	return m
