class_name AbilityVfx
extends Node3D
## v0.9.17 ability VFX (docs/art/VFX.md): every fighter's abilities, JUICE, charged attacks,
## projectiles, ground effects, elemental hits and reactions, shared by local matches
## (MatchScene) and online clients (NetMatchScene). Driven only by simulation events, the
## replicated entity list and per-fighter view state: never by authority, never back into it.
##
## Each effect has a purposeful preparation (from the move's start to its first effect time, read
## from the move definition), motion, contact (exactly when the simulation fires the effect, in
## exactly its footprint: cone angle, line length/width, ring radii) and dissipation. Shapes
## follow the element language (docs/design/ART_DIRECTION.md §6, FxKit) and each fighter's own
## identity: Stoke's furnace pressure and ignition, Dredge's tidal force, Gusto's vortices,
## Dozer's crushing debris, Slurry's viscous sludge, Jitters' electrical discharge, Knell's
## spectral motion and Varga's precise martial impact.
##
## Budget (ART_DIRECTION §10): floor footprints are cheap decals; particles scale with the Effects
## quality (Low/Medium/High) and thin out in crowded fights; one trail per fighter; light flashes
## are capped; "Reduce flashing" dims flashes and stops lightning flicker.

const Q_RATIO := [0.35, 0.65, 1.0]          ## particle amount per Effects quality
const MAX_LIGHTS := [0, 3, 6]
const POOL_CAP := 10                        ## pooled one-shot emitters per preset
const CORE_SEG := {"f_stoke": "chest", "f_dredge": "shell", "f_gusto": "torso", "f_dozer": "chest",
	"f_slurry": "body1", "f_jitters": "body", "f_varga": "chest", "f_knell": "chest"}
## centre of the core segment's body relative to its joint pivot (rest space, metres)
const CORE_OFF := {"f_stoke": Vector3(0, 0.26, 0.04), "f_dredge": Vector3(0, 0.03, 0), "f_gusto": Vector3(0, 0.06, 0),
	"f_dozer": Vector3(0, 0.04, -0.03), "f_slurry": Vector3(0, 0.175, -0.025), "f_jitters": Vector3.ZERO,
	"f_varga": Vector3(0, 0.233, 0), "f_knell": Vector3(0, 0.22, 0)}
## Stoke's two back stacks (tops), relative to the core centre
const STOKE_STACKS := [Vector3(0.12, 0.26, -0.195), Vector3(-0.12, 0.26, -0.195)]

## Particle presets. "debris" = solid pieces (fx_debris.gdshader), "puff" = soft volumes (fx_puff).
const PRESETS := {
	"chunks": {"kind": "debris", "mesh": "hex", "mat": "rock", "amount": 16, "life": 1.5, "speed": [2.5, 6.0], "spread": 0.7,
		"gravity": 13.0, "bounce": 0.3, "scale": [0.07, 0.17], "spin": 10.0},
	"pebbles": {"kind": "debris", "mesh": "hex", "mat": "rock", "amount": 24, "life": 1.1, "speed": [1.5, 4.5], "spread": 0.9,
		"gravity": 12.0, "bounce": 0.35, "scale": [0.025, 0.06], "spin": 14.0},
	"drops": {"kind": "debris", "mesh": "drop", "mat": "drop", "amount": 26, "life": 0.9, "speed": [2.0, 5.5], "spread": 0.8,
		"gravity": 11.0, "bounce": 0.05, "scale": [0.03, 0.075], "stretch": 0.9},
	"gobs": {"kind": "debris", "mesh": "goo", "mat": "goo", "amount": 16, "life": 1.3, "speed": [1.5, 4.0], "spread": 0.8,
		"gravity": 9.0, "bounce": 0.0, "scale": [0.05, 0.13], "stretch": 0.6},
	"shards": {"kind": "debris", "mesh": "shard", "mat": "shard", "amount": 12, "life": 0.8, "speed": [3.0, 7.0], "spread": 0.9,
		"gravity": 12.0, "bounce": 0.4, "scale": [0.04, 0.08], "spin": 18.0},
	"cinders": {"kind": "debris", "mesh": "streak", "mat": "glow", "amount": 24, "life": 1.0, "speed": [1.0, 3.5], "spread": 0.9,
		"gravity": 0.6, "buoyancy": 2.5, "drag": 1.5, "scale": [0.012, 0.03], "stretch": 1.5},
	"sparks": {"kind": "debris", "mesh": "streak", "mat": "glow", "amount": 22, "life": 0.45, "speed": [4.0, 9.0], "spread": 1.0,
		"gravity": 9.0, "bounce": 0.3, "scale": [0.01, 0.02], "stretch": 2.5},
	"feathers": {"kind": "debris", "mesh": "feather", "mat": "feather", "amount": 8, "life": 1.8, "speed": [1.0, 3.0], "spread": 1.2,
		"gravity": 1.2, "drag": 2.5, "scale": [0.07, 0.11], "spin": 6.0},
	"steam": {"kind": "puff", "look": 0, "add": false, "amount": 26, "life": 1.4, "speed": [1.0, 4.0], "spread": 0.5,
		"drag": 2.6, "buoyancy": 1.2, "size": [0.22, 0.45], "grow": 3.0},
	"smoke": {"kind": "puff", "look": 0, "add": false, "amount": 14, "life": 1.6, "speed": [0.3, 1.2], "spread": 0.8,
		"drag": 1.5, "buoyancy": 0.9, "size": [0.25, 0.5], "grow": 2.4},
	"dust": {"kind": "puff", "look": 0, "add": false, "amount": 18, "life": 1.1, "speed": [0.8, 3.0], "spread": 1.2,
		"drag": 3.0, "buoyancy": 0.15, "size": [0.2, 0.42], "grow": 2.2},
	"flames": {"kind": "puff", "look": 1, "add": true, "hot": 0.8, "amount": 22, "life": 0.55, "speed": [0.4, 1.4], "spread": 0.5,
		"drag": 1.0, "buoyancy": 3.0, "size": [0.14, 0.3], "grow": 0.55, "spin": 0.0},
	"fireball": {"kind": "puff", "look": 0, "add": true, "amount": 14, "life": 0.45, "speed": [0.5, 2.5], "spread": 1.5,
		"drag": 3.0, "buoyancy": 1.5, "size": [0.25, 0.5], "grow": 1.8},
	"mist": {"kind": "puff", "look": 0, "add": false, "amount": 16, "life": 1.0, "speed": [0.5, 2.0], "spread": 1.2,
		"drag": 2.0, "buoyancy": 0.3, "size": [0.2, 0.4], "grow": 2.2},
	"wisps": {"kind": "puff", "look": 3, "add": true, "amount": 14, "life": 1.2, "speed": [0.3, 1.2], "spread": 1.4,
		"drag": 1.2, "buoyancy": 0.7, "swirl": 2.0, "size": [0.18, 0.36], "grow": 1.7},
	"wind": {"kind": "puff", "look": 3, "add": false, "amount": 16, "life": 0.8, "speed": [2.0, 5.0], "spread": 0.6,
		"drag": 2.0, "buoyancy": 0.0, "swirl": 3.0, "size": [0.25, 0.5], "grow": 1.6},
	"motes": {"kind": "puff", "look": 2, "add": true, "amount": 18, "life": 0.5, "speed": [0.5, 1.5], "spread": 3.1,
		"drag": 0.0, "buoyancy": 0.0, "size": [0.04, 0.08], "grow": 0.6},
	"bubbles": {"kind": "puff", "look": 2, "add": false, "amount": 12, "life": 0.9, "speed": [0.2, 0.8], "spread": 0.6,
		"drag": 1.0, "buoyancy": 0.6, "size": [0.05, 0.12], "grow": 1.4},
	"glints": {"kind": "puff", "look": 5, "add": true, "amount": 10, "life": 0.35, "speed": [1.5, 4.0], "spread": 3.1,
		"drag": 4.0, "buoyancy": 0.0, "size": [0.08, 0.16], "grow": 0.4},
	"spray": {"kind": "puff", "look": 4, "add": false, "amount": 20, "life": 0.7, "speed": [2.0, 5.0], "spread": 0.7,
		"drag": 1.0, "buoyancy": -8.0, "size": [0.04, 0.08], "grow": 1.0},
}

var quality := 2
var reduce_flashes := false
var view_of: Callable            ## (fighter index) -> CreatureView or null
var info_of: Callable            ## (fighter index) -> {ground, yaw, state, juiced, hidden, charge (-1 none, -2 unknown), out}
var fighter_count: Callable      ## () -> int

var _pool := {}                  ## preset -> Array[GPUParticles3D]
var _anims: Array = []           ## [{node, t, dur, fn: Callable(k, t), free}]
var _follows: Array = []         ## [{node, fi, anchor, off, until, end: Callable}]
var _ents := {}                  ## entity id -> {node, kind, pos, end: Callable, ...}
var _moves := {}                 ## fighter -> {def: MoveDef, slot, t0, id}
var _auras := {}                 ## fighter -> {node, end: Callable}
var _charges := {}               ## fighter -> {node, mat, glow}
var _trails := {}                ## fighter -> {rib, pts: [[pos, t]], weapon, until, color}
var _lights := 0
var _clock := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	# build every effect material once during the intro, out of sight, so the first ability of the
	# match never waits on a shader
	for preset in PRESETS:
		burst(preset, Vector3(0, -30, 0), Vector3.UP, Color(1, 1, 1, 0.01), null, {"amount": 0.02, "warm": true})
	var warm := footprint("scorch", "circle", Vector3(0, -30, 0), 0.0, 0.5, {}, 0.2)
	warm.visible = true
	ring_wall(Vector3(0, -30, 0), 0.1, 0.2, 0.1, Color(1, 1, 1, 0.01), Color(1, 1, 1, 0.01), 0.2)


func configure(effects_quality: int, reduce: bool) -> void:
	quality = clampi(effects_quality, 0, 2)
	reduce_flashes = reduce


# =====================================================================================
# Fighter access (view side only)
# =====================================================================================

func _view(fi: int) -> CreatureView:
	if not view_of.is_valid():
		return null
	var v = view_of.call(fi)
	return v as CreatureView if v is CreatureView and is_instance_valid(v) else null


func _cid(fi: int) -> String:
	var v := _view(fi)
	return v.creature.id if v != null and v.creature != null else ""


func _info(fi: int) -> Dictionary:
	if not info_of.is_valid():
		return {}
	var d = info_of.call(fi)
	return d if d is Dictionary else {}


func _ground(fi: int) -> Vector3:
	var inf := _info(fi)
	if inf.has("ground"):
		return inf["ground"]
	var v := _view(fi)
	if v != null:
		var p := v.segment_world(0).origin
		return Vector3(p.x, 0.0, p.z)
	return Vector3.ZERO


func _yaw(fi: int) -> float:
	var inf := _info(fi)
	if inf.has("yaw"):
		return float(inf["yaw"])
	var v := _view(fi)
	if v != null:
		var z := v.segment_world(_core_index(fi)).basis.z
		return atan2(z.x, z.z)
	return 0.0


func _fwd(fi: int) -> Vector3:
	return MathX.forward_of_yaw(_yaw(fi))


func _core_index(fi: int) -> int:
	var v := _view(fi)
	if v == null or v.body == null:
		return 0
	return int(v.body.seg_index.get(str(CORE_SEG.get(_cid(fi), "")), 0))


## World position of a named weapon point or segment of a fighter (plus a local offset).
func anchor(fi: int, name_: String, off := Vector3.ZERO) -> Vector3:
	var v := _view(fi)
	if name_ == "__ground":
		return _ground(fi) + off
	if v == null or v.body == null:
		return _ground(fi) + Vector3.UP * 0.8
	if name_ == "core":
		return v.segment_world(_core_index(fi)) * (CORE_OFF.get(_cid(fi), Vector3.ZERO) + off)
	if v.body.weapons.has(name_):
		var w: BodyDef.Weapon = v.body.weapons[name_]
		return v.segment_world(w.seg) * (w.local + off)
	if v.body.seg_index.has(name_):
		return v.segment_world(int(v.body.seg_index[name_])) * off
	return v.segment_world(_core_index(fi)) * off


## A point in the fighter's own space (+Z forward, floor at y = 0), like kit offsets.
func fpoint(fi: int, local: Vector3) -> Vector3:
	return _ground(fi) + MathX.yaw_basis(_yaw(fi)) * local


func _move_def(fi: int, id: String) -> MoveDef:
	var v := _view(fi)
	if v == null or v.creature == null:
		return null
	var slot := id.substr(id.find(".") + 1) if id.contains(".") else id
	if v.creature.abilities.has(slot):
		return v.creature.abilities[slot]
	if v.creature.moves.has(slot):
		return v.creature.moves[slot]
	return null


static func first_effect_t(m: MoveDef) -> float:
	var t := INF
	for e in m.effects:
		t = minf(t, float((e as Dictionary).get("t", 0.0)))
	if t == INF:
		t = m.first_active() if not m.windows.is_empty() else 0.3
	return t


static func effect_of(m: MoveDef, type: String) -> Dictionary:
	if m == null:
		return {}
	for e in m.effects:
		if str((e as Dictionary).get("type", "")) == type:
			return e
	return {}


func _ratio() -> float:
	var r: float = Q_RATIO[quality]
	var n := int(fighter_count.call()) if fighter_count.is_valid() else 2
	if n > 4:
		r *= 0.7         # crowded fights: thinner volumes keep everyone readable
	return r


# =====================================================================================
# Primitives
# =====================================================================================

func _new_emitter(preset: String) -> GPUParticles3D:
	var p: Dictionary = PRESETS[preset]
	var gp := GPUParticles3D.new()
	gp.one_shot = true
	gp.explosiveness = 0.92
	gp.local_coords = false
	gp.amount = int(p["amount"])
	gp.lifetime = float(p["life"])
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gp.visibility_aabb = AABB(Vector3(-7, -3, -7), Vector3(14, 10, 14))
	var m := ShaderMaterial.new()
	if str(p["kind"]) == "debris":
		m.shader = FxKit.shader("fx_debris")
		var mesh := FxKit.piece_mesh(str(p["mesh"]))
		gp.draw_pass_1 = mesh
		gp.material_override = FxKit.piece_material(str(p["mat"]))
	else:
		m.shader = FxKit.shader("fx_puff")
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		gp.draw_pass_1 = q
		gp.material_override = FxKit.puff_material(int(p["look"]), bool(p["add"]), float(p.get("hot", 0.0)))
	gp.process_material = m
	add_child(gp)
	return gp


func _pooled(preset: String) -> GPUParticles3D:
	var list: Array = _pool.get(preset, [])
	for gp: GPUParticles3D in list:
		if not gp.emitting:
			return gp
	if list.size() >= POOL_CAP:
		var oldest: GPUParticles3D = list.pop_front()
		list.append(oldest)
		return oldest
	var n := _new_emitter(preset)
	list.append(n)
	_pool[preset] = list
	return n


func _configure(gp: GPUParticles3D, preset: String, dir: Vector3, ca: Color, cb: Color, o: Dictionary) -> void:
	var p: Dictionary = PRESETS[preset]
	var m := gp.process_material as ShaderMaterial
	var d := dir.normalized() if dir.length_squared() > 1e-6 else Vector3.UP
	var spd: Array = o.get("speed_range", p["speed"])
	var sm := float(o.get("speed", 1.0))
	m.set_shader_parameter("direction", d)
	m.set_shader_parameter("spread", float(o.get("spread", p.get("spread", 0.8))))
	m.set_shader_parameter("speed_min", float(spd[0]) * sm)
	m.set_shader_parameter("speed_max", float(spd[1]) * sm)
	m.set_shader_parameter("color_a", ca)
	m.set_shader_parameter("color_b", cb)
	m.set_shader_parameter("emit_seed", _rng.randf() * 100.0)
	m.set_shader_parameter("emit_radius", float(o.get("radius", 0.0)))
	m.set_shader_parameter("emit_box", o.get("box", Vector3.ZERO))
	m.set_shader_parameter("drag", float(o.get("drag", p.get("drag", 0.0))))
	m.set_shader_parameter("buoyancy", float(o.get("buoyancy", p.get("buoyancy", 0.0))))
	var sc := float(o.get("scale", 1.0))
	if str(p["kind"]) == "debris":
		var s: Array = p["scale"]
		m.set_shader_parameter("gravity", float(o.get("gravity", p.get("gravity", 9.8))))
		m.set_shader_parameter("bounce", float(p.get("bounce", 0.3)))
		m.set_shader_parameter("floor_y", float(o.get("floor", 0.0)))
		m.set_shader_parameter("spin", float(p.get("spin", 0.0)))
		m.set_shader_parameter("scale_min", float(s[0]) * sc)
		m.set_shader_parameter("scale_max", float(s[1]) * sc)
		m.set_shader_parameter("stretch", float(p.get("stretch", 0.0)))
		m.set_shader_parameter("shrink_from", float(o.get("shrink_from", 0.7)))
	else:
		var z: Array = p["size"]
		m.set_shader_parameter("swirl", float(o.get("swirl", p.get("swirl", 0.0))))
		m.set_shader_parameter("size_min", float(z[0]) * sc)
		m.set_shader_parameter("size_max", float(z[1]) * sc)
		m.set_shader_parameter("grow", float(o.get("grow", p.get("grow", 1.5))))
		m.set_shader_parameter("spin", float(p.get("spin", 1.0)))
		m.set_shader_parameter("ring", 1.0 if bool(o.get("ring", false)) else 0.0)
		m.set_shader_parameter("emit_height", float(o.get("height", 0.0)))
		m.set_shader_parameter("fade_in", float(o.get("fade_in", 0.08)))


## One-shot particle burst. o: speed, spread, radius, box, scale, amount, life, floor, ring,
## height, swirl, grow, gravity, drag, buoyancy.
func burst(preset: String, pos: Vector3, dir: Vector3, ca: Color, cb = null, o := {}) -> void:
	if not PRESETS.has(preset):
		return
	var gp := _pooled(preset)
	if str(PRESETS[preset].get("mat", "")) == "glow":
		ca = _hdr(ca)
		cb = _hdr(cb if cb is Color else ca)
	_configure(gp, preset, dir, ca, cb if cb is Color else ca, o)
	gp.lifetime = float(PRESETS[preset]["life"]) * float(o.get("life", 1.0))
	var amt := float(o.get("amount", 1.0))
	if not bool(o.get("warm", false)):
		amt *= _ratio()
		if reduce_flashes and bool(PRESETS[preset].get("add", false)) and preset in ["fireball", "glints", "motes"]:
			amt *= 0.6
	gp.amount_ratio = clampf(amt, 0.02, 1.0)
	gp.global_position = pos
	gp.restart()
	gp.emitting = true


## A continuous emitter (auras, trails, zones). Stop it with end_stream().
## Sparks and cinders are HDR so they bloom (alpha untouched).
static func _hdr(c: Color, k := 1.8) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)


func stream(preset: String, ca: Color, cb = null, o := {}) -> GPUParticles3D:
	if str(PRESETS[preset].get("mat", "")) == "glow":
		ca = _hdr(ca)
		cb = _hdr(cb if cb is Color else ca)
	var gp := _new_emitter(preset)
	gp.one_shot = false
	gp.explosiveness = 0.0
	gp.lifetime = float(PRESETS[preset]["life"]) * float(o.get("life", 1.0))
	_configure(gp, preset, o.get("dir", Vector3.UP), ca, cb if cb is Color else ca, o)
	gp.amount_ratio = clampf(float(o.get("amount", 1.0)) * _ratio(), 0.02, 1.0)
	gp.emitting = true
	return gp


func end_stream(gp: GPUParticles3D) -> void:
	if gp == null or not is_instance_valid(gp):
		return
	gp.emitting = false
	# by id: the emitter may be gone (scene change) before the timer fires
	var gid := gp.get_instance_id()
	get_tree().create_timer(gp.lifetime + 0.1, false).timeout.connect(func():
		var o := instance_from_id(gid)
		if o != null:
			(o as Node).queue_free())


## Runs fn(k 0..1, t seconds) every frame for `dur` seconds, then frees the node (unless keep).
func animate(node: Node, dur: float, fn: Callable, keep := false) -> void:
	_anims.append({"node": node, "t": 0.0, "dur": maxf(dur, 0.001), "fn": fn, "free": not keep})
	fn.call(0.0, 0.0)


## The true footprint of an area (or a zone) drawn on the floor in its element's pattern.
## o: cone_deg, length, width, inner, color, color2, style, additive, fill, front, strength.
func footprint(el: String, shape: String, origin: Vector3, yaw: float, radius: float, o := {}, life := 0.7, sweep := 0.12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = FxKit.floor_quad()
	var reach := maxf(radius, float(o.get("length", 0.0)))
	var size := 2.0 * reach + 0.8
	var mat := FxKit.area_material(el, shape, radius, o)
	mat.set_shader_parameter("size_m", size)
	if reduce_flashes:
		mat.set_shader_parameter("front", float(o.get("front", 0.8)) * 0.5)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-size * 0.5, -0.3, -size * 0.5), Vector3(size, 0.6, size))
	add_child(mi)
	mi.global_position = origin + Vector3.UP * (0.025 + _rng.randf() * 0.01)
	mi.rotation.y = yaw
	var strength := float(o.get("strength", 1.0)) * (0.75 if reduce_flashes else 1.0)
	var fade_from := float(o.get("fade_from", 0.55))
	if life < INF:
		animate(mi, life, func(k: float, t: float) -> void:
			var pr := clampf(t / maxf(sweep, 0.001), 0.0, 1.0)
			pr = 1.0 - (1.0 - pr) * (1.0 - pr)
			mat.set_shader_parameter("progress", pr * 1.02)
			mat.set_shader_parameter("fade", (1.0 - smoothstep(fade_from, 1.0, k)) * strength))
	else:
		mat.set_shader_parameter("progress", 1.02)
		mat.set_shader_parameter("fade", strength)
	return mi


## An expanding ring wall (shockwave, tidal crest, toll) from r0 to r1 metres.
## o: add (bool), lean (top radius factor), scroll, bands, h_end, noise, edge_v, core.
func ring_wall(pos: Vector3, r0: float, r1: float, height: float, ca: Color, cb: Color, dur: float, o := {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = FxKit.wall_mesh(48, float(o.get("lean", 1.0)))
	var mat := FxKit.flow_material(ca, cb, {"additive": 1.0 if bool(o.get("add", true)) else 0.0,
		"scroll": o.get("scroll", Vector2(0.35, -1.2)), "noise_scale": o.get("noise", Vector2(12.0, 2.0)),
		"edge_v": float(o.get("edge_v", 0.35)), "core": float(o.get("core", 0.2)), "core_width": float(o.get("core_width", 0.25)),
		"bands": float(o.get("bands", 0.0)), "alpha": 1.0})
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	var h_end := float(o.get("h_end", 0.35))
	var expand := float(o.get("expand", 0.6))       # fraction of the life spent expanding
	animate(mi, dur, func(k: float, _t: float) -> void:
		var e := clampf(k / expand, 0.0, 1.0)
		e = 1.0 - pow(1.0 - e, 3.0)
		var r := lerpf(r0, r1, e)
		mi.scale = Vector3(maxf(r, 0.01), height * lerpf(1.0, h_end, k), maxf(r, 0.01))
		mat.set_shader_parameter("dissolve", smoothstep(0.5, 1.0, k))
		mat.set_shader_parameter("alpha", (1.0 - smoothstep(0.75, 1.0, k)) * (0.8 if reduce_flashes else 1.0)))
	return mi


## A rotating spiral funnel (vortex, tornado, rising water column).
func vortex(pos: Vector3, radius: float, height: float, ca: Color, cb: Color, dur: float, o := {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = FxKit.spiral_mesh(float(o.get("turns", 2.5)), float(o.get("r0", 0.3)), 1.0, float(o.get("width", 0.22)))
	var mat := FxKit.flow_material(ca, cb, {"additive": 1.0 if bool(o.get("add", false)) else 0.0, "scroll": Vector2(-1.6, 0.0),
		"noise_scale": Vector2(8.0, 1.5), "edge_v": 0.45, "core": 0.5, "core_width": 0.3, "bands": 3.0, "alpha": 1.0})
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	var spin := float(o.get("spin", 7.0))
	var grow := float(o.get("grow", 0.25))
	animate(mi, dur, func(k: float, t: float) -> void:
		var g := clampf(k / grow, 0.0, 1.0)
		mi.scale = Vector3(radius * (0.4 + 0.6 * g), height * g, radius * (0.4 + 0.6 * g))
		mi.rotation.y = -t * spin
		mat.set_shader_parameter("dissolve", smoothstep(0.6, 1.0, k))
		mat.set_shader_parameter("alpha", 1.0 - smoothstep(0.8, 1.0, k)))
	return mi


## A pressure jet: an open cone from `apex` along `dir`, `length` long and `radius` wide at its end,
## surging out and breaking up (Stoke's steam, sprays, blasts).
func jet(apex: Vector3, dir: Vector3, length: float, radius: float, ca: Color, cb: Color, dur: float, o := {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = FxKit.wall_mesh(32, 0.06)           # y = 0: wide end, y = 1: the narrow apex
	var mat := FxKit.flow_material(ca, cb, {"cover": float(o.get("cover", 0.7)), "glow_k": float(o.get("glow_k", 0.5)), "scroll": Vector2(0.3, 2.4),
		"noise_scale": Vector2(6.0, 2.5), "edge_v": 0.2, "core": 0.75, "core_width": 0.35, "alpha": 1.0})
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var d := dir.normalized()
	var x := d.cross(Vector3.UP).normalized() if absf(d.y) < 0.95 else Vector3.RIGHT
	var y := -d
	var z := x.cross(y).normalized()
	animate(mi, dur, func(k: float, _t: float) -> void:
		var reach := clampf(k / 0.35, 0.0, 1.0)
		reach = 1.0 - (1.0 - reach) * (1.0 - reach)
		var l := maxf(length * reach, 0.05)
		mi.global_transform = Transform3D(Basis(x * radius * reach, y * l, z * radius * reach * float(o.get("flat", 1.0))), apex + d * l)
		mat.set_shader_parameter("dissolve", smoothstep(0.35, 1.0, k))
		mat.set_shader_parameter("alpha", 1.0 - smoothstep(0.8, 1.0, k)))
	return mi


## A ground crest (rolling wave, sludge surge) travelling from origin along yaw for `length` m.
func crest(origin: Vector3, yaw: float, length: float, width: float, height: float, ca: Color, cb: Color, travel: float, dur: float, o := {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = FxKit.crest_mesh()
	var mat := FxKit.flow_material(ca, cb, {"additive": 1.0 if bool(o.get("add", false)) else 0.0, "scroll": o.get("scroll", Vector2(-0.8, -0.6)),
		"noise_scale": Vector2(3.0, 4.0), "edge_v": 0.15, "edge_u": 0.2, "core": 0.75, "core_width": 0.2, "alpha": 1.0})
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var fwd := MathX.forward_of_yaw(yaw)
	var depth := float(o.get("depth", 0.5))          # the crest's own thickness along its travel
	mi.rotation.y = yaw
	animate(mi, dur, func(k: float, t: float) -> void:
		var a := clampf(t / maxf(travel, 0.001), 0.0, 1.0)
		var along := lerpf(depth * 0.5, length - depth * 0.5, 1.0 - (1.0 - a) * (1.0 - a))
		mi.global_position = origin + fwd * along
		var h := height * (sin(clampf(a * 1.2, 0.0, 1.0) * PI * 0.5)) * (1.0 - smoothstep(0.6, 1.0, k))
		mi.scale = Vector3(width, maxf(h, 0.01), depth)
		mat.set_shader_parameter("dissolve", smoothstep(0.55, 1.0, k)))
	return mi


## A camera-facing ribbon through world points (ImmediateMesh), redrawn by the caller.
func ribbon(ca: Color, cb: Color, add := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	mi.material_override = FxKit.flow_material(ca, cb, {"additive": 1.0 if add else 0.0, "scroll": Vector2(-2.0, 0.0),
		"noise_scale": Vector2(3.0, 1.0), "edge_v": 0.5, "core": 0.5, "core_width": 0.32, "alpha": 1.0})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	add_child(mi)
	mi.global_transform = Transform3D.IDENTITY
	return mi


func draw_ribbon(mi: MeshInstance3D, pts: Array, widths: Array, alphas: Array) -> void:
	var im := mi.mesh as ImmediateMesh
	im.clear_surfaces()
	var n := pts.size()
	if n < 2:
		return
	var cam := get_viewport().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam else Vector3(0, 10, 10)
	# keep a generous box: ribbons move every frame
	mi.custom_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 40, 80))
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n:
		var p: Vector3 = pts[i]
		var tng: Vector3 = (pts[mini(i + 1, n - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)
		var side := tng.cross(eye - p)
		side = side.normalized() * float(widths[i]) * 0.5 if side.length_squared() > 1e-8 else Vector3.RIGHT * float(widths[i]) * 0.5
		var c := Color(1, 1, 1, clampf(float(alphas[i]), 0.0, 1.0))
		var u := float(i) / float(n - 1)
		im.surface_set_color(c)
		im.surface_set_uv(Vector2(u, 0.0))
		im.surface_add_vertex(p - side)
		im.surface_set_color(c)
		im.surface_set_uv(Vector2(u, 1.0))
		im.surface_add_vertex(p + side)
	im.surface_end()


## A jagged lightning bolt between two points (re-forks while it lives; steady under Reduce flashing).
func bolt(a: Vector3, b: Vector3, ca: Color, dur := 0.2, width := 0.06, jag := 0.22) -> void:
	var mi := ribbon(ca, Color(1.0, 1.0, 0.8), true)
	(mi.material_override as ShaderMaterial).set_shader_parameter("cover", 0.85)
	(mi.material_override as ShaderMaterial).set_shader_parameter("glow_k", 1.4)
	width *= 1.5
	var segs := clampi(int(a.distance_to(b) / 0.16), 4, 22)
	var regen := 0.16 if reduce_flashes else 0.045
	var state := {"next": 0.0, "pts": []}
	animate(mi, dur, func(k: float, t: float) -> void:
		if t >= float(state["next"]) or (state["pts"] as Array).is_empty():
			state["next"] = t + regen
			var pts := []
			var dirv := b - a
			var perp1 := dirv.cross(Vector3.UP).normalized() if absf(dirv.normalized().y) < 0.95 else Vector3.RIGHT
			var perp2 := dirv.cross(perp1).normalized()
			for i in segs + 1:
				var u := float(i) / segs
				var off := Vector3.ZERO
				if i > 0 and i < segs:
					off = (perp1 * _rng.randf_range(-1, 1) + perp2 * _rng.randf_range(-1, 1)) * jag * sin(u * PI)
				pts.append(a.lerp(b, u) + off)
			state["pts"] = pts
		var p: Array = state["pts"]
		var w := []
		var al := []
		for i in p.size():
			w.append(width * (1.0 - k * 0.5))
			al.append((1.0 - k) * (0.7 if reduce_flashes else 1.0))
		draw_ribbon(mi, p, w, al))


## A short light flash (capped per Effects quality; dimmed under Reduce flashing).
func flash_light(pos: Vector3, color: Color, energy: float, rng: float, dur: float) -> void:
	if _lights >= int(MAX_LIGHTS[quality]):
		return
	var l := OmniLight3D.new()
	l.light_color = color
	l.omni_range = rng
	l.shadow_enabled = false
	var e0 := energy * (0.35 if reduce_flashes else 1.0)
	l.light_energy = e0
	add_child(l)
	l.global_position = pos
	_lights += 1
	animate(l, dur, func(k: float, _t: float) -> void:
		l.light_energy = e0 * (1.0 - k) * (1.0 - k)
		if k >= 1.0:
			_lights = maxi(0, _lights - 1))


## Keeps `node` on a fighter's anchor for `dur` seconds; `end` runs when it lets go.
func follow(node: Node3D, fi: int, anchor_name: String, off: Vector3, dur: float, end: Callable = Callable()) -> void:
	_follows.append({"node": node, "fi": fi, "anchor": anchor_name, "off": off, "until": _clock + dur, "end": end})
	node.global_position = anchor(fi, anchor_name, off)


## Ends every follow of a fighter whose anchor matches (or all of them).
func release(fi: int, tag := "") -> void:
	for f in _follows:
		if int(f["fi"]) == fi and (tag == "" or str(f.get("tag", "")) == tag):
			f["until"] = _clock


func _stream_at(fi: int, anchor_name: String, off: Vector3, dur: float, preset: String, ca: Color, cb = null, o := {}, tag := "") -> GPUParticles3D:
	if quality <= 0 and not bool(o.get("essential", false)):
		return null
	var gp := stream(preset, ca, cb, o)
	var gid := gp.get_instance_id()
	follow(gp, fi, anchor_name, off, dur, func(): end_stream(instance_from_id(gid) as GPUParticles3D))
	if tag != "":
		_follows[-1]["tag"] = tag
	return gp


# =====================================================================================
# Frame update
# =====================================================================================

func _process(delta: float) -> void:
	_clock += delta
	# animations (fn may free things; iterate a copy)
	var keep: Array = []
	for a in _anims:
		if not is_instance_valid(a["node"]):
			continue
		var node: Node = a["node"]
		a["t"] = float(a["t"]) + delta
		var k := clampf(float(a["t"]) / float(a["dur"]), 0.0, 1.0)
		(a["fn"] as Callable).call(k, float(a["t"]))
		if k >= 1.0:
			if bool(a["free"]):
				node.queue_free()
		else:
			keep.append(a)
	_anims = keep
	# followers
	var fk: Array = []
	for f in _follows:
		if not is_instance_valid(f["node"]):
			continue
		var n: Node3D = f["node"]
		var fi := int(f["fi"])
		if _clock >= float(f["until"]) or _view(fi) == null:
			var end: Callable = f["end"]
			if end.is_valid():
				end.call()
			continue
		n.global_position = anchor(fi, str(f["anchor"]), f["off"])
		fk.append(f)
	_follows = fk
	_update_fighters()
	_update_trails()


func _update_fighters() -> void:
	var n := int(fighter_count.call()) if fighter_count.is_valid() else 0
	for fi in n:
		var inf := _info(fi)
		var alive := not inf.is_empty() and not bool(inf.get("out", false)) and not bool(inf.get("hidden", false)) and _view(fi) != null
		# JUICE aura
		var juiced := alive and bool(inf.get("juiced", false))
		if juiced and not _auras.has(fi):
			_auras[fi] = _juice_aura(fi)
		elif not juiced and _auras.has(fi):
			var au: Dictionary = _auras[fi]
			_auras.erase(fi)
			(au["end"] as Callable).call()
		# heavy charge glow
		_update_charge(fi, inf, alive)


# =====================================================================================
# Events
# =====================================================================================

func on_event(ev: Dictionary) -> void:
	var fi := int(ev.get("fighter", -1))
	match str(ev.get("type", "")):
		"move_start":
			_on_move_start(fi, ev)
		"effect":
			_on_effect(fi, ev)
		"hit":
			_on_hit(ev)
		"reaction":
			_on_reaction(ev)
		"zone_reaction":
			_on_zone_reaction(ev)
		"juice":
			_on_juice(fi)
		"submerge":
			_on_submerge(fi, ev)
		"hover":
			_on_hover(fi)
		"land":
			release(fi, "hover")
			if _cid(fi) == "f_gusto":
				burst("wind", _ground(fi) + Vector3.UP * 0.1, Vector3.UP, Color(0.85, 0.97, 0.96, 0.4), null, {"ring": true, "radius": 0.4, "spread": 0.3, "speed": 0.6, "amount": 0.5})
		"counter":
			_on_counter(fi, ev)
		"wall_bonk", "splat":
			_on_crash(fi, ev)
		"carry":
			var vi := int(ev.get("victim", -1))
			if vi >= 0 and _cid(fi) == "f_dozer":
				var vp := anchor(vi, "core")
				burst("chunks", vp, Vector3.UP, Color(0.5, 0.41, 0.31), Color(0.7, 0.6, 0.46), {"amount": 0.5, "speed": 0.8, "floor": _ground(fi).y})
				burst("dust", vp, Vector3.UP, Color(0.72, 0.6, 0.45, 0.55), null, {"amount": 0.6})
		"arc":
			var el := str(ev.get("element", "static"))
			bolt(ev["from"] + Vector3.UP * 0.7, ev["to"] + Vector3.UP * 0.7, FxKit.el_color(el), 0.22, 0.07)
			burst("sparks", ev["to"] + Vector3.UP * 0.7, Vector3.UP, FxKit.el_hot(el), FxKit.el_color(el), {"amount": 0.5})
		"spring":
			_on_spring(ev)
		"projectile_destroyed":
			var pd: Vector3 = ev["pos"]
			burst("steam", pd, Vector3.UP, Color(0.92, 0.92, 0.95, 0.5), null, {"amount": 0.4, "speed": 0.5})
			burst("sparks", pd, Vector3.UP, Color(1.0, 0.8, 0.5), null, {"amount": 0.4})
		"reflect":
			var rp: Vector3 = ev.get("pos", _ground(fi) + Vector3.UP)
			burst("glints", rp, Vector3.UP, Color(0.85, 0.95, 1.0), null, {"amount": 0.8})
			ring_wall(rp, 0.1, 0.8, 0.25, Color(0.7, 0.9, 1.0), Color(1, 1, 1), 0.25, {"bands": 6.0})
		"status":
			if not bool(ev.get("reacted", false)):
				_on_status(fi, str(ev.get("element", "")))
		"dodge":
			if _cid(fi) == "f_varga":
				_varga_afterimage(fi, _ground(fi), 0.25)


func _on_move_start(fi: int, ev: Dictionary) -> void:
	var id := str(ev.get("id", ""))
	var m := _move_def(fi, id)
	if m == null:
		return
	var slot := str(ev.get("slot", "")).split("@")[0]
	_moves[fi] = {"def": m, "slot": slot, "t0": _clock, "id": id}
	_end_charge(fi, slot == "heavy_charged")
	var cid := _cid(fi)
	if slot in ["ability1", "ability2", "juice"]:
		_prep(fi, cid, slot, m)
	if slot in ["heavy_charged", "finisher"] or (slot == "heavy" and cid == "f_varga"):
		_start_trail(fi, m)
	elif slot == "heavy" and m.charge_time > 0.0:
		_charges[fi] = {"t0": _clock, "def": m, "node": null}


# =====================================================================================
# Preparation (move start .. first effect)
# =====================================================================================

func _prep(fi: int, cid: String, slot: String, m: MoveDef) -> void:
	var lead := first_effect_t(m)
	var el := m.element if m.element != "" else (str(effect_of(m, "area").get("element", "")) if not effect_of(m, "area").is_empty() else "")
	match cid + ":" + slot:
		"f_stoke:ability1":
			# pressure builds: the boiler glows, vents hiss, hot motes rush into the firebox
			_converge(fi, "belly", Vector3.ZERO, lead, Color(1.0, 0.55, 0.15), Color(1.0, 0.9, 0.5), 0.55)
			_stacks_puff(fi, "steam", lead, 0.7)
			_glow_at(fi, "belly", Vector3(0, 0, -0.02), lead + 0.05, Color(1.0, 0.5, 0.1), 0.35)
		"f_stoke:ability2":
			_converge(fi, "belly", Vector3.ZERO, lead, Color(1.0, 0.45, 0.1), Color(1.0, 0.85, 0.4), 0.7)
			_stacks_puff(fi, "smoke", lead, 0.5)
		"f_stoke:juice":
			# overheating: white-hot core, heat shimmer, the footprint of the blast spreading under him
			_glow_at(fi, "core", Vector3(0, 0.0, 0.1), lead + 0.1, Color(1.0, 0.6, 0.2), 0.75, true)
			_converge(fi, "core", Vector3.ZERO, lead, Color(1.0, 0.6, 0.15), Color(1.0, 1.0, 0.8), 1.0)
			_stacks_puff(fi, "flames", lead, 0.8)
			var r := float(effect_of(m, "area").get("radius", 3.0))
			footprint("scorch", "circle", _ground(fi), 0.0, r, {"fill": 0.12, "front": 0.4, "strength": 0.45}, lead + 0.05, lead)
		"f_dredge:ability1":
			_converge(fi, "head", Vector3(0, 0.0, 0.18), lead, Color(0.5, 0.8, 1.0), Color(0.9, 0.98, 1.0), 0.5)
			burst("drops", anchor(fi, "head", Vector3(0, 0, 0.15)), Vector3.DOWN, Color(0.55, 0.8, 1.0, 0.8), null, {"amount": 0.25, "speed": 0.3, "floor": _ground(fi).y})
		"f_dredge:ability2":
			_converge(fi, "core", Vector3(0, -0.1, 0), lead, Color(0.4, 0.75, 1.0), Color(0.9, 0.98, 1.0), 0.5)
		"f_dredge:juice":
			# the tide rises around him before it breaks outward
			var g := _ground(fi)
			vortex(g, 1.1, 1.6, Color(0.25, 0.6, 0.95, 0.9), Color(0.85, 0.97, 1.0), lead + 0.12, {"turns": 2.0, "r0": 0.85, "spin": 5.0, "grow": 0.9})
			burst("spray", g + Vector3.UP * 0.2, Vector3.UP, Color(0.35, 0.65, 0.95, 0.8), null, {"ring": true, "radius": 1.0, "spread": 0.4, "speed": 0.6, "life": 0.9})
			footprint("brine", "circle", g, 0.0, 1.3, {"fill": 0.4, "strength": 0.8}, lead + 0.1, lead)
		"f_gusto:ability1":
			_converge(fi, "beak", Vector3(0, 0, 0.05), lead, Color(0.4, 0.78, 0.8), Color(1, 1, 1), 0.45, "wisps")
		"f_gusto:ability2":
			burst("feathers", anchor(fi, "core"), Vector3.UP, Color(0.95, 0.93, 0.85), Color(0.75, 0.9, 0.9), {"amount": 0.5, "floor": _ground(fi).y})
		"f_gusto:juice":
			var gg := _ground(fi)
			vortex(gg, 1.0, 1.5, Color(0.3, 0.72, 0.76, 0.85), Color(1, 1, 1), lead + 0.15, {"turns": 3.0, "r0": 0.4, "spin": 9.0, "grow": 0.8})
			burst("wind", gg + Vector3.UP * 0.4, Vector3.UP, Color(0.42, 0.78, 0.8, 0.55), null, {"ring": true, "radius": 1.2, "swirl": 6.0, "speed": 0.4})
			burst("feathers", anchor(fi, "core"), Vector3.UP, Color(0.95, 0.93, 0.85), Color(0.75, 0.9, 0.9), {"amount": 0.6, "floor": gg.y})
		"f_dozer:ability1":
			# hoof scrape: dust and grit kicked out behind, the floor cracking under the front hooves
			var back := -_fwd(fi)
			burst("dust", anchor(fi, "hoof_bl"), back + Vector3.UP * 0.4, Color(0.72, 0.6, 0.45, 0.6), null, {"amount": 0.5, "speed": 0.8})
			burst("pebbles", anchor(fi, "hoof_br"), back + Vector3.UP * 0.8, Color(0.6, 0.48, 0.34), Color(0.78, 0.66, 0.5), {"amount": 0.5, "floor": _ground(fi).y})
			footprint("grit", "circle", fpoint(fi, Vector3(0, 0, 0.5)), 0.0, 0.7, {"fill": 0.6, "strength": 0.8}, 0.9, 0.2)
		"f_dozer:ability2":
			burst("dust", _ground(fi), Vector3.UP, Color(0.75, 0.62, 0.45, 0.55), null, {"ring": true, "radius": 0.6, "speed": 0.6})
		"f_dozer:juice":
			var lg := _ground(fi)
			for k in 3:
				_later(lead * (0.15 + 0.3 * k), func():
					burst("pebbles", lg + Vector3.UP * 0.05, Vector3.UP, Color(0.6, 0.48, 0.34), Color(0.82, 0.7, 0.52), {"radius": 1.2, "amount": 0.4, "speed": 0.5, "floor": lg.y}))
			var la := effect_of(m, "area")
			footprint("grit", "line", lg, _yaw(fi), 0.0, {"length": float(la.get("length", 6.0)), "width": float(la.get("width", 2.0)), "fill": 0.15, "front": 0.3, "strength": 0.5}, lead + 0.05, lead)
		"f_slurry:ability1":
			_drip(fi, "fang", lead + 0.1, 0.5)
		"f_slurry:ability2":
			burst("bubbles", _ground(fi) + Vector3.UP * 0.1, Vector3.UP, Color(0.55, 0.85, 0.2, 0.8), null, {"radius": 0.5, "amount": 0.6})
		"f_slurry:juice":
			_drip(fi, "head", lead + 0.2, 1.0)
			_drip(fi, "body1", lead + 0.2, 0.8)
			burst("bubbles", _ground(fi) + Vector3.UP * 0.1, Vector3.UP, Color(0.55, 0.85, 0.2, 0.8), null, {"radius": 0.9, "amount": 1.0})
		"f_jitters:ability1":
			_antenna_sparks(fi, lead + 0.05, 0.6)
		"f_jitters:ability2":
			_antenna_sparks(fi, lead, 0.4)
		"f_jitters:juice":
			_antenna_sparks(fi, lead + 0.05, 1.0)
			for k in 4:
				_later(lead * 0.2 * k, func(): _body_arcs(fi, 2, 0.16))
			footprint("static", "circle", _ground(fi), 0.0, float(effect_of(m, "area").get("radius", 3.0)), {"fill": 0.1, "front": 0.3, "strength": 0.4}, lead + 0.05, lead)
		"f_varga:ability2":
			burst("mist", anchor(fi, "head", Vector3(0, -0.02, 0.12)), _fwd(fi) + Vector3.UP * 0.2, Color(0.95, 0.96, 1.0, 0.35), null, {"amount": 0.5, "speed": 0.4})
		"f_varga:juice":
			_glow_at(fi, "chest", Vector3(0, 0.05, 0.1), lead + 0.05, Color(1.0, 0.75, 0.4), 0.4)
			burst("glints", anchor(fi, "chest"), Vector3.UP, Color(1.0, 0.85, 0.5), null, {"amount": 0.6, "speed": 0.5})
		"f_knell:ability1":
			# a lantern flame kindles where the Ghost Light will leave his hand
			var pe := effect_of(m, "projectile")
			var off: Array = pe.get("offset", [0, 1.2, 0.5])
			var lp := fpoint(fi, Vector3(float(off[0]), float(off[1]), float(off[2])))
			burst("flames", lp, Vector3.UP, Color(0.7, 0.5, 1.0, 0.9), Color(0.95, 0.9, 1.0), {"amount": 0.5, "scale": 0.8})
			_converge_point(lp, lead, Color(0.7, 0.55, 1.0), Color(0.95, 0.9, 1.0), 0.4, "wisps")
		"f_knell:ability2":
			burst("wisps", anchor(fi, "core"), Vector3.UP, Color(0.65, 0.5, 1.0, 0.7), null, {"amount": 0.5, "radius": 0.3})
		"f_knell:juice":
			_knell_bell(fi, m)
		_:
			if el != "":
				_converge(fi, "core", Vector3.ZERO, lead, FxKit.el_color(el), FxKit.el_hot(el), 0.4)


## Glowing motes rushing into a fighter's anchor over `dur` seconds (pressure, gathering power).
func _converge(fi: int, anchor_name: String, off: Vector3, dur: float, ca: Color, cb: Color, amount: float, preset := "motes") -> void:
	_converge_point(anchor(fi, anchor_name, off), dur, ca, cb, amount, preset)


func _converge_point(p: Vector3, dur: float, ca: Color, cb: Color, amount: float, preset := "motes") -> void:
	var life := clampf(dur, 0.12, 0.6)
	# spawned on a ring around the point and pulled straight in: speed = radius / life
	var r := 0.55
	burst(preset, p + Vector3.DOWN * 0.25, Vector3.UP, ca, cb, {"ring": true, "radius": r, "height": 0.5, "speed_range": [-r / life * 0.85, -r / life],
		"spread": 0.05, "life": life / float(PRESETS[preset]["life"]), "amount": amount, "drag": 0.0, "buoyancy": 0.0, "fade_in": 0.3})


func _glow_at(fi: int, anchor_name: String, off: Vector3, dur: float, c: Color, size: float, white_hot := false) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	var mat := FxKit.flow_material(c, Color(1.0, 0.97, 0.85) if white_hot else c.lightened(0.4),
		{"additive": 1.0, "fresnel": 1.5, "scroll": Vector2(0.3, -0.8), "noise_scale": Vector2(4.0, 3.0), "edge_v": 0.0, "core": 0.5, "core_width": 0.5, "alpha": 0.0})
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	follow(mi, fi, anchor_name, off, dur + 0.15)
	animate(mi, dur + 0.15, func(k: float, _t: float) -> void:
		var g := smoothstep(0.0, 0.85, k)
		mi.scale = Vector3.ONE * size * (0.4 + 0.6 * g)
		mat.set_shader_parameter("alpha", g * (1.0 - smoothstep(0.88, 1.0, k)) * (0.7 if reduce_flashes else 1.0)))
	if quality >= 1:
		var l := OmniLight3D.new()
		l.light_color = c
		l.omni_range = 2.2
		l.shadow_enabled = false
		add_child(l)
		follow(l, fi, anchor_name, off, dur + 0.15)
		var e0 := 1.6 * (0.4 if reduce_flashes else 1.0)
		animate(l, dur + 0.15, func(k: float, _t: float) -> void:
			l.light_energy = e0 * smoothstep(0.0, 0.85, k) * (1.0 - smoothstep(0.9, 1.0, k)))


## Stoke's back stacks (two vents behind the shoulders).
func _stacks_puff(fi: int, preset: String, dur: float, amount: float) -> void:
	for off in STOKE_STACKS:
		var c := Color(0.92, 0.92, 0.95, 0.5) if preset == "steam" else (Color(0.35, 0.33, 0.33, 0.5) if preset == "smoke" else Color(1.0, 0.55, 0.15, 0.9))
		_stream_at(fi, "core", off, dur, preset, c, Color(1.0, 0.9, 0.5, 0.9) if preset == "flames" else null,
			{"amount": amount * 0.45, "speed": 0.6, "spread": 0.2, "life": 0.55, "scale": 0.55, "grow": 1.8})


func _drip(fi: int, anchor_name: String, dur: float, amount: float) -> void:
	_stream_at(fi, anchor_name, Vector3.ZERO, dur, "gobs", Color(0.45, 0.72, 0.12), Color(0.62, 0.86, 0.2),
		{"dir": Vector3.DOWN, "speed": 0.15, "spread": 0.6, "amount": amount * 0.6, "scale": 0.6, "floor": _ground(fi).y})


func _antenna_sparks(fi: int, dur: float, amount: float) -> void:
	for a in ["antenna_l", "antenna_r"]:
		_stream_at(fi, a, Vector3.ZERO, dur, "sparks", Color(1.0, 0.95, 0.55), Color(1.0, 1.0, 0.9), {"amount": amount * 0.5, "speed": 0.4, "floor": _ground(fi).y})
	if quality >= 1:
		var steps := clampi(int(dur / 0.09), 1, 8)
		for k in steps:
			_later(0.09 * k, func(): bolt(anchor(fi, "antenna_l"), anchor(fi, "antenna_r"), Color(1.0, 0.92, 0.35), 0.08, 0.04, 0.08))


## Short arcs crawling over Jitters' body (static).
func _body_arcs(fi: int, n: int, dur: float) -> void:
	var v := _view(fi)
	if v == null:
		return
	var c := anchor(fi, "core")
	for k in n:
		var a := c + Vector3(_rng.randf_range(-0.35, 0.35), _rng.randf_range(-0.1, 0.45), _rng.randf_range(-0.35, 0.35))
		var b := c + Vector3(_rng.randf_range(-0.35, 0.35), _rng.randf_range(-0.1, 0.45), _rng.randf_range(-0.35, 0.35))
		bolt(a, b, Color(1.0, 0.9, 0.3), dur, 0.035, 0.1)


func _later(delay: float, fn: Callable) -> void:
	if delay <= 0.0:
		fn.call()
		return
	var holder := Node.new()
	add_child(holder)
	animate(holder, delay, func(k: float, _t: float) -> void:
		if k >= 1.0:
			fn.call())


# =====================================================================================
# Contact (effect events)
# =====================================================================================

func _on_effect(fi: int, ev: Dictionary) -> void:
	var t := str(ev.get("effect", ""))
	var vfx := str(ev.get("vfx", t))
	var el := str(ev.get("element", ""))
	var pos: Vector3 = ev.get("pos", _ground(fi))
	var yaw := float(ev.get("yaw", _yaw(fi)))
	var r := float(ev.get("radius", 0.0))
	var shape := str(ev.get("shape", "circle"))
	var origin: Vector3 = ev.get("origin", pos)
	var cid := _cid(fi) if fi >= 0 else ""
	match vfx:
		"steam_vent":
			_steam_vent(fi, origin, yaw, r, float(ev.get("cone_deg", 60.0)))
			return
		"stoke_the_fire":
			_stoke_the_fire(fi)
			return
		"meltdown":
			_meltdown(fi, pos, r)
			return
		"tide_ring":
			_high_tide(fi, pos, r, float(ev.get("inner", 0.0)))
			return
		"brine_wave":
			_brine_wave(fi, origin, yaw, float(ev.get("length", 3.5)), float(ev.get("width", 1.0)))
			return
		"hurricane":
			_hurricane(fi, origin, yaw, r, float(ev.get("cone_deg", 90.0)))
			return
		"gust_burst":
			_gust_burst(pos, r)
			return
		"crosswind":
			_crosswind(fi, pos, r)
			return
		"downdraft", "tailspin":
			_wind_ring(fi, pos, r, vfx == "tailspin")
			return
		"landslide":
			_landslide(fi, origin, yaw, float(ev.get("length", 6.0)), float(ev.get("width", 2.0)))
			return
		"gravel_spray":
			_gravel_spray(fi, origin, yaw, r, float(ev.get("cone_deg", 60.0)))
			return
		"wave":
			_sludge_wave(fi, origin, yaw, float(ev.get("length", 4.0)), float(ev.get("width", 1.6)))
			return
		"drain":
			_drain_emerge(pos, r)
			return
		"overcharge", "pulse", "squash", "discharge":
			_static_burst(fi, pos, r, vfx)
			return
		"ring":
			if cid == "f_knell":
				_knell_toll(fi, pos, r)
				return
		"bolt":
			_sky_bolt(pos, r, el)
			return
	match t:
		"area":
			_generic_area(fi, cid, el, shape, pos, origin, yaw, r, ev)
		"zone":
			_zone_spawn_splash(el, pos, r, vfx)
		"buff":
			_buff(fi, cid, ev)
		"dash":
			if cid == "f_varga":
				_varga_dash(fi, ev)
			else:
				burst("dust", _ground(fi), -_fwd(fi) + Vector3.UP * 0.3, Color(0.8, 0.75, 0.65, 0.4), null, {"amount": 0.4})
		"counter_stance":
			_anchor_drop(fi, float(ev.get("duration", 2.5)))
		"charge":
			_bulldoze(fi, float(ev.get("distance", 6.0)) / maxf(0.5, float(ev.get("speed", 7.0))))
		"juice_state":
			pass        # the aura follows the fighter's JUICE state (see _update_fighters)
		"projectile":
			_muzzle(fi, cid, el, vfx)
		"prop":
			pass        # the prop itself appears through sync_entities
		"leap":
			burst("dust", _ground(fi), Vector3.UP, Color(0.8, 0.75, 0.65, 0.45), null, {"ring": true, "radius": 0.3, "amount": 0.5, "speed": 0.7})
		"heal":
			burst("motes", anchor(fi, "core"), Vector3.UP, Color(0.5, 1.0, 0.6), Color(0.9, 1.0, 0.8), {"amount": 0.5, "speed": 0.6, "radius": 0.3})
		"shield":
			ring_wall(_ground(fi), 0.6, 0.75, 1.6, Color(0.6, 0.85, 1.0), Color(1, 1, 1), 0.5, {"bands": 8.0})
		"pull", "push":
			_push_wave(fi, pos, maxf(r, 1.0), el, t == "pull")


## ---- Stoke: furnace pressure and ignition ----

func _steam_vent(fi: int, origin: Vector3, yaw: float, r: float, cone: float) -> void:
	var fwd := MathX.forward_of_yaw(yaw)
	var nozzle := anchor(fi, "belly", Vector3(0, 0, 0.05))
	footprint("scorch", "cone", origin, yaw, r, {"cone_deg": cone, "color": Color(1.0, 0.6, 0.3), "color2": Color(1.0, 0.95, 0.8), "fill": 0.45}, 0.75, 0.1)
	# the jet: scalding steam rushing through the cone, an ignition flash at the vent, cinders
	var half := deg_to_rad(cone) * 0.5
	jet(nozzle, fwd, r, tan(half) * r, Color(0.93, 0.92, 0.9, 0.95), Color(1.0, 0.82, 0.55), 0.45, {"cover": 0.8, "glow_k": 0.5, "flat": 0.28})
	burst("steam", nozzle, fwd + Vector3.UP * 0.05, Color(0.95, 0.94, 0.92, 0.7), Color(1.0, 0.86, 0.72, 0.55),
		{"spread": half * 0.8, "speed": r / 1.2, "drag": 1.6, "life": 1.0, "amount": 1.0})
	burst("steam", origin + fwd * r * 0.55 + Vector3.UP * 0.35, fwd, Color(0.95, 0.95, 0.97, 0.45), null,
		{"spread": half, "speed": 0.5, "amount": 0.5, "radius": r * 0.25})
	burst("fireball", nozzle, fwd, Color(1.0, 0.55, 0.15, 0.9), Color(1.0, 0.85, 0.45, 0.9), {"spread": half * 0.6, "speed": 1.2, "amount": 0.6, "scale": 0.7})
	burst("cinders", nozzle, fwd, Color(1.0, 0.7, 0.25), Color(1.0, 0.45, 0.1), {"spread": half, "speed": 1.6, "amount": 0.6})
	flash_light(nozzle + fwd * 0.4, Color(1.0, 0.6, 0.25), 3.0, 3.5, 0.3)
	_stacks_puff(fi, "steam", 0.45, 0.6)


func _stoke_the_fire(fi: int) -> void:
	# ignition: flames roar out of both stacks, an ember ring kicks off his feet, then the stoked
	# fire keeps burning at the stacks for as long as the buff lasts
	var m := _move_def(fi, "ability2")
	var st: Dictionary = effect_of(m, "buff").get("status", {})
	var dur := float(st.get("duration", 5.0))
	for off in STOKE_STACKS:
		var p := anchor(fi, "core", off)
		burst("flames", p, Vector3.UP, Color(1.0, 0.5, 0.12, 0.95), Color(1.0, 0.9, 0.45, 0.95), {"amount": 0.9, "speed": 1.8, "spread": 0.3, "scale": 1.3})
		burst("cinders", p, Vector3.UP, Color(1.0, 0.75, 0.3), null, {"amount": 0.5, "speed": 1.4, "spread": 0.4})
	var g := _ground(fi)
	ring_wall(g, 0.3, 1.1, 0.35, Color(1.0, 0.45, 0.1), Color(1.0, 0.9, 0.5), 0.45, {"bands": 10.0})
	footprint("scorch", "circle", g, 0.0, 1.1, {"fill": 0.5}, 0.8, 0.15)
	flash_light(anchor(fi, "core"), Color(1.0, 0.55, 0.2), 2.5, 3.0, 0.35)
	_stacks_puff(fi, "flames", dur, 0.45)
	_stream_at(fi, "fist_l", Vector3.ZERO, dur, "cinders", Color(1.0, 0.7, 0.25), null, {"amount": 0.25, "speed": 0.4})
	_stream_at(fi, "fist_r", Vector3.ZERO, dur, "cinders", Color(1.0, 0.7, 0.25), null, {"amount": 0.25, "speed": 0.4})


func _meltdown(fi: int, pos: Vector3, r: float) -> void:
	# the furnace bursts: a fire wall rolls out to the blast radius, flame tongues ring the edge,
	# the floor is licked by fire and cinders rain down
	footprint("scorch", "circle", pos, 0.0, r, {"fill": 0.6, "front": 1.0, "stain_a": 0.5}, 1.6, 0.18)
	ring_wall(pos, 0.4, r, 1.4, Color(1.0, 0.4, 0.06), Color(1.0, 0.85, 0.45), 0.6, {"bands": 0.0, "scroll": Vector2(0.25, -2.2), "noise": Vector2(16.0, 2.5), "edge_v": 0.35, "core": 0.12, "expand": 0.45})
	burst("flames", pos + Vector3.UP * 0.1, Vector3.UP, Color(1.0, 0.45, 0.1, 0.95), Color(1.0, 0.8, 0.35, 0.95),
		{"ring": true, "radius": r * 0.92, "speed": 0.3, "spread": 0.2, "scale": 2.2, "amount": 1.0})
	burst("fireball", anchor(fi, "core"), Vector3.UP, Color(1.0, 0.5, 0.12, 0.7), Color(1.0, 0.85, 0.5, 0.6), {"speed": 2.2, "scale": 0.9, "amount": 0.6})
	burst("cinders", pos + Vector3.UP * 0.5, Vector3.UP, Color(1.0, 0.7, 0.25), Color(1.0, 0.4, 0.1), {"speed": 2.2, "spread": 1.2, "amount": 1.0})
	burst("smoke", pos + Vector3.UP * 0.3, Vector3.UP, Color(0.28, 0.25, 0.25, 0.45), null, {"ring": true, "radius": r * 0.6, "speed": 0.4, "amount": 0.7})
	flash_light(pos + Vector3.UP * 1.0, Color(1.0, 0.55, 0.2), 5.0, r * 2.2, 0.5)


## ---- Dredge: tidal force ----

func _high_tide(fi: int, pos: Vector3, r: float, inner: float) -> void:
	footprint("brine", "ring" if inner > 0.0 else "circle", pos, 0.0, r, {"inner": inner, "fill": 0.55, "front": 1.0}, 1.2, 0.3)
	# a breaking wave crest rolls out to the ring's edge, throwing spray
	ring_wall(pos, 0.6, r, 0.9, Color(0.22, 0.55, 0.9, 0.85), Color(0.92, 0.98, 1.0), 0.75,
		{"add": false, "lean": 0.82, "scroll": Vector2(0.15, -0.9), "noise": Vector2(16.0, 2.0), "core": 0.85, "core_width": 0.18, "edge_v": 0.2, "expand": 0.5, "h_end": 0.2})
	burst("spray", pos + Vector3.UP * 0.3, Vector3.UP, Color(0.35, 0.65, 0.95, 0.85), null, {"ring": true, "radius": r * 0.55, "speed": 1.4, "spread": 0.35, "amount": 1.0})
	burst("drops", pos + Vector3.UP * 0.3, Vector3.UP, Color(0.4, 0.7, 1.0, 0.85), Color(0.8, 0.95, 1.0, 0.85), {"radius": r * 0.6, "speed": 1.1, "spread": 0.6, "floor": pos.y})
	burst("mist", pos + Vector3.UP * 0.2, Vector3.UP, Color(0.55, 0.75, 0.95, 0.4), null, {"ring": true, "radius": r * 0.8, "speed": 0.5})
	_later(0.0, func(): burst("drops", anchor(fi, "core"), Vector3.UP, Color(0.4, 0.7, 1.0, 0.85), null, {"speed": 1.2, "spread": 0.9, "amount": 0.5, "floor": pos.y}))


func _brine_wave(fi: int, origin: Vector3, yaw: float, length: float, width: float) -> void:
	footprint("brine", "line", origin, yaw, 0.0, {"length": length, "width": width, "fill": 0.5}, 0.9, 0.22)
	crest(origin, yaw, length, width, 0.55, Color(0.25, 0.58, 0.92, 0.9), Color(0.92, 0.98, 1.0), 0.24, 0.6)
	var fwd := MathX.forward_of_yaw(yaw)
	burst("spray", origin + fwd * length * 0.5 + Vector3.UP * 0.2, fwd + Vector3.UP, Color(0.35, 0.65, 0.95, 0.8), null,
		{"box": Vector3(width * 0.5, 0.1, length * 0.45), "speed": 0.7, "amount": 0.8})
	burst("drops", origin + fwd * length * 0.8 + Vector3.UP * 0.2, fwd + Vector3.UP, Color(0.4, 0.7, 1.0, 0.85), null, {"amount": 0.5, "speed": 0.8, "floor": origin.y})


func _anchor_drop(fi: int, dur: float) -> void:
	# a whirlpool turns around him on the floor while he holds his ground
	var g := _ground(fi)
	var wp := footprint("brine", "ring", g, 0.0, 1.25, {"inner": 0.55, "fill": 0.6, "strength": 0.9, "speed": 2.5}, INF)
	var ms := wp.material_override as ShaderMaterial
	var wid := wp.get_instance_id()
	follow(wp, fi, "__ground", Vector3.UP * 0.03, dur, func():
		var o := instance_from_id(wid)
		if o != null:
			animate(o, 0.3, func(k: float, _t: float) -> void:
				ms.set_shader_parameter("fade", 0.9 * (1.0 - k))))
	_follows[-1]["tag"] = "stance"
	var vx := vortex(g, 1.15, 0.45, Color(0.25, 0.6, 0.95, 0.85), Color(0.9, 0.97, 1.0), dur + 0.2, {"turns": 1.5, "r0": 1.0, "spin": 6.0, "grow": 0.1})
	var vid := vx.get_instance_id()
	follow(vx, fi, "__ground", Vector3.ZERO, dur, func():
		var o := instance_from_id(vid)
		if o != null:
			(o as Node).queue_free())
	_follows[-1]["tag"] = "stance"
	_stream_at(fi, "core", Vector3(0, -0.2, 0), dur, "spray", Color(0.35, 0.65, 0.95, 0.7), null, {"amount": 0.35, "radius": 0.9, "ring": true, "speed": 0.3, "swirl": 4.0}, "stance")


func _on_counter(fi: int, ev: Dictionary) -> void:
	release(fi, "stance")
	var cid := _cid(fi)
	var p := anchor(fi, "core")
	if cid == "f_dredge":
		# the anchor drops: the held water crashes down onto the attacker
		var vi := int(ev.get("victim", -1))
		var tp := anchor(vi, "core") if vi >= 0 else p + _fwd(fi)
		ring_wall(_ground(fi), 0.4, 1.8, 0.8, Color(0.22, 0.55, 0.9, 0.85), Color(0.92, 0.98, 1.0), 0.5, {"add": false, "lean": 0.8, "core": 0.85})
		burst("spray", tp, Vector3.UP, Color(0.4, 0.68, 0.95, 0.85), null, {"speed": 1.3, "amount": 1.0})
		burst("drops", tp, Vector3.UP, Color(0.4, 0.7, 1.0, 0.85), null, {"speed": 1.2, "floor": _ground(fi).y})
	else:
		burst("glints", p, Vector3.UP, Color(1.0, 0.9, 0.6), null, {"amount": 0.8})


## ---- Gusto: vortices ----

func _hurricane(fi: int, origin: Vector3, yaw: float, r: float, cone: float) -> void:
	footprint("gale", "cone", origin, yaw, r, {"cone_deg": cone, "fill": 0.5}, 0.9, 0.14)
	var fwd := MathX.forward_of_yaw(yaw)
	var half := deg_to_rad(cone) * 0.5
	# curling streaks sweep through the whole cone, gusts carry feathers and dust out to its edge
	for k in 7:
		var a := lerpf(-half * 0.92, half * 0.92, float(k) / 6.0)
		_wind_streak(origin + Vector3.UP * (0.35 + 0.25 * (k % 3)), yaw + a, r, 0.32 + 0.04 * k, signf(a + 0.001) * 0.5)
	burst("wind", origin + Vector3.UP * 0.5 + fwd * 0.3, fwd, Color(0.42, 0.78, 0.8, 0.55), null, {"spread": half, "speed": r / 2.0, "amount": 1.0})
	burst("dust", origin + fwd * r * 0.5, fwd, Color(0.8, 0.78, 0.7, 0.35), null, {"spread": half, "speed": 0.8, "radius": r * 0.3, "amount": 0.5})
	burst("feathers", anchor(fi, "core"), fwd + Vector3.UP * 0.5, Color(0.95, 0.93, 0.85), Color(0.75, 0.9, 0.9), {"spread": half, "speed": 1.4, "floor": origin.y})


## One curved wind streak travelling `length` m along yaw (a ribbon whose head runs ahead).
func _wind_streak(start: Vector3, yaw: float, length: float, dur: float, curl := 0.4) -> void:
	if quality <= 0:
		return
	var mi := ribbon(Color(0.3, 0.72, 0.76, 0.9), Color(1, 1, 1), true)
	var fwd := MathX.forward_of_yaw(yaw)
	var side := fwd.cross(Vector3.UP)
	animate(mi, dur, func(k: float, _t: float) -> void:
		var head := clampf(k * 1.35, 0.0, 1.0)
		var tail := clampf(k * 1.35 - 0.45, 0.0, 1.0)
		var pts := []
		var w := []
		var al := []
		for i in 10:
			var u := lerpf(tail, head, float(i) / 9.0)
			pts.append(start + fwd * length * u + side * curl * sin(u * PI) * 0.6 + Vector3.UP * 0.15 * sin(u * PI * 2.0))
			w.append(0.15 * (float(i) / 9.0))
			al.append((float(i) / 9.0) * (1.0 - smoothstep(0.7, 1.0, k)))
		draw_ribbon(mi, pts, w, al))


func _gust_burst(pos: Vector3, r: float) -> void:
	footprint("gale", "circle", pos, 0.0, r, {"fill": 0.5}, 0.7, 0.12)
	ring_wall(pos, 0.2, r, 0.7, Color(0.3, 0.72, 0.76), Color(1, 1, 1), 0.4, {"bands": 9.0, "scroll": Vector2(1.5, -0.5)})
	burst("wind", pos + Vector3.UP * 0.4, Vector3.UP, Color(0.42, 0.78, 0.8, 0.55), null, {"ring": true, "radius": 0.2, "speed": r / 1.2, "spread": 0.2, "swirl": 3.0})
	for k in 4:
		_wind_streak(pos + Vector3.UP * 0.3, TAU * k / 4.0 + 0.3, r, 0.3, 0.6)


func _crosswind(fi: int, pos: Vector3, r: float) -> void:
	var yaw := _yaw(fi)
	footprint("gale", "circle", pos, 0.0, r, {"fill": 0.35, "strength": 0.8}, 0.5, 0.1)
	# a crescent slash of wind across the front
	var mi := ribbon(Color(0.3, 0.72, 0.76), Color(1, 1, 1), true)
	var c := pos + Vector3.UP * 0.7
	animate(mi, 0.3, func(k: float, _t: float) -> void:
		var pts := []
		var w := []
		var al := []
		var sweep := lerpf(-1.3, 1.3, clampf(k * 1.6, 0.0, 1.0))
		for i in 12:
			var a := yaw + lerpf(sweep - 1.1, sweep, float(i) / 11.0)
			pts.append(c + Vector3(sin(a), 0, cos(a)) * r * 0.75)
			w.append(0.16 * float(i) / 11.0)
			al.append(float(i) / 11.0 * (1.0 - k))
		draw_ribbon(mi, pts, w, al))
	burst("wind", c, MathX.forward_of_yaw(yaw), Color(0.42, 0.78, 0.8, 0.5), null, {"spread": 0.9, "amount": 0.6})


func _wind_ring(fi: int, pos: Vector3, r: float, spin: bool) -> void:
	footprint("gale", "circle", pos, 0.0, r, {"fill": 0.45}, 0.7, 0.1)
	if spin:
		vortex(pos, r, 0.9, Color(0.3, 0.72, 0.76, 0.9), Color(1, 1, 1), 0.45, {"turns": 1.2, "r0": 0.7, "spin": 14.0, "grow": 0.2, "add": true})
	else:
		ring_wall(pos, r, r * 0.3, 0.9, Color(0.3, 0.72, 0.76), Color(1, 1, 1), 0.35, {"bands": 8.0, "scroll": Vector2(0.0, 2.0)})
	burst("dust", pos, Vector3.UP, Color(0.8, 0.77, 0.7, 0.4), null, {"ring": true, "radius": r * 0.7, "speed": 0.8, "amount": 0.6})
	burst("feathers", anchor(fi, "core"), Vector3.UP, Color(0.95, 0.93, 0.85), Color(0.75, 0.9, 0.9), {"amount": 0.4, "floor": pos.y})


func _on_hover(fi: int) -> void:
	if _cid(fi) != "f_gusto":
		return
	var m := _move_def(fi, "ability2")
	var dur := float(effect_of(m, "hover").get("duration", 1.2))
	# downdraft: pulsing wind rings pressed onto the floor under him, dust spreading out
	var g0 := _ground(fi)
	var pulses := int(dur / 0.22)
	for k in pulses:
		_later(0.22 * k, func():
			var gp := _ground(fi)
			ring_wall(gp + Vector3.UP * 0.05, 0.2, 1.1, 0.15, Color(0.35, 0.75, 0.78, 0.85), Color(1, 1, 1), 0.35, {"bands": 6.0}))
	_stream_at(fi, "core", Vector3(0, -0.25, 0), dur, "wind", Color(0.42, 0.78, 0.8, 0.45), null, {"dir": Vector3.DOWN, "speed": 0.5, "amount": 0.5, "spread": 0.5}, "hover")
	burst("dust", g0, Vector3.UP, Color(0.8, 0.77, 0.7, 0.4), null, {"ring": true, "radius": 0.5, "speed": 0.9})


## ---- Dozer: crushing debris ----

func _bulldoze(fi: int, dur: float) -> void:
	# kick-off: grit sprays back off the hooves; then a heavy plume of dust and gravel follows the
	# charge and the floor is torn up along its path
	var g0 := _ground(fi)
	var back := -_fwd(fi)
	burst("chunks", g0 + Vector3.UP * 0.15, back + Vector3.UP * 0.6, Color(0.5, 0.41, 0.31), Color(0.68, 0.58, 0.45), {"amount": 0.5, "speed": 0.8, "floor": g0.y})
	burst("dust", g0, back + Vector3.UP * 0.3, Color(0.7, 0.58, 0.43, 0.6), null, {"amount": 0.8, "speed": 0.9, "scale": 1.3})
	for hoof in ["hoof_bl", "hoof_br"]:
		_stream_at(fi, hoof, Vector3.ZERO, dur, "dust", Color(0.7, 0.58, 0.43, 0.62), Color(0.8, 0.7, 0.55, 0.5), {"speed": 0.35, "amount": 1.0, "spread": 1.1, "scale": 1.4, "grow": 2.6}, "charge")
	_stream_at(fi, "hoof_fl", Vector3.ZERO, dur, "pebbles", Color(0.5, 0.41, 0.31), Color(0.7, 0.6, 0.46), {"speed": 0.6, "amount": 0.8, "floor": g0.y}, "charge")
	_stream_at(fi, "horn", Vector3.ZERO, dur, "sparks", Color(1.0, 0.8, 0.45), null, {"speed": 0.3, "amount": 0.25, "floor": g0.y}, "charge")
	var holder := Node.new()
	add_child(holder)
	var st := {"next": 0.0}
	animate(holder, dur, func(_k: float, t: float) -> void:
		if t >= float(st["next"]) and _view(fi) != null:
			st["next"] = t + 0.09
			footprint("grit", "circle", _ground(fi) + _fwd(fi) * 0.3, _yaw(fi), 0.5, {"fill": 0.75, "stain_a": 0.45, "front": 0.0}, 1.5, 0.05))


func _on_crash(fi: int, ev: Dictionary) -> void:
	var p: Vector3 = ev.get("pos", anchor(fi, "core"))
	release(fi, "charge")
	burst("chunks", p + Vector3.UP * 0.3, Vector3.UP, Color(0.5, 0.41, 0.31), Color(0.7, 0.6, 0.46), {"amount": 0.8, "floor": _ground(fi).y})
	burst("dust", p, Vector3.UP, Color(0.72, 0.6, 0.45, 0.6), null, {"amount": 1.0, "scale": 1.3})
	ring_wall(Vector3(p.x, _ground(fi).y, p.z), 0.2, 1.3, 0.35, Color(0.6, 0.48, 0.34, 0.8), Color(0.85, 0.75, 0.55), 0.35, {"add": false, "core": 0.3})


func _landslide(fi: int, origin: Vector3, yaw: float, length: float, width: float) -> void:
	footprint("grit", "line", origin, yaw, 0.0, {"length": length, "width": width, "fill": 0.7, "front": 0.8}, 1.6, 0.3)
	var fwd := MathX.forward_of_yaw(yaw)
	var side := fwd.cross(Vector3.UP).normalized()
	# rock spires burst out of the floor one after another along the whole line, then crumble
	var n := 6 if quality >= 1 else 4
	for k in n:
		var u := (float(k) + 0.5) / n
		var delay := u * 0.28
		var p := origin + fwd * length * u + side * _rng.randf_range(-width * 0.3, width * 0.3)
		_later(delay, func(): _rock_spire(p, 0.35 + 0.25 * _rng.randf(), yaw))
	burst("dust", origin + fwd * length * 0.5, Vector3.UP, Color(0.74, 0.62, 0.46, 0.5), null, {"box": Vector3(width * 0.5, 0.1, length * 0.5), "speed": 0.7, "amount": 1.0})
	burst("chunks", origin + fwd * length * 0.5 + Vector3.UP * 0.2, Vector3.UP, Color(0.58, 0.47, 0.34), Color(0.8, 0.7, 0.55), {"box": Vector3(width * 0.4, 0.1, length * 0.45), "speed": 0.9, "floor": origin.y})


func _rock_spire(p: Vector3, size: float, yaw: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = FxKit.piece_mesh("hex")
	mi.material_override = Materials.toon(Color(0.4, 0.34, 0.28), 0.95, 0.0, 0.2)
	add_child(mi)
	mi.global_position = p
	mi.rotation = Vector3(_rng.randf_range(-0.25, 0.25), yaw + _rng.randf() * TAU, _rng.randf_range(-0.25, 0.25))
	burst("pebbles", p + Vector3.UP * 0.1, Vector3.UP, Color(0.5, 0.41, 0.31), Color(0.7, 0.6, 0.46), {"amount": 0.35, "floor": p.y})
	burst("dust", p, Vector3.UP, Color(0.7, 0.58, 0.43, 0.55), null, {"amount": 0.35, "speed": 0.6})
	animate(mi, 1.2, func(k: float, _t: float) -> void:
		var up := clampf(k / 0.12, 0.0, 1.0)
		var s := size * (1.0 + 0.25 * sin(up * PI)) * up
		var sink := smoothstep(0.65, 1.0, k)
		mi.scale = Vector3(s, s * 2.2, s) * (1.0 - sink * 0.6)
		mi.global_position = p + Vector3.UP * (s * 0.6 - sink * s * 1.4))


func _gravel_spray(fi: int, origin: Vector3, yaw: float, r: float, cone: float) -> void:
	footprint("grit", "cone", origin, yaw, r, {"cone_deg": cone, "fill": 0.6}, 0.8, 0.12)
	var fwd := MathX.forward_of_yaw(yaw)
	var half := deg_to_rad(cone) * 0.5
	var mouth := anchor(fi, "snout")
	burst("pebbles", mouth, fwd + Vector3.UP * 0.25, Color(0.6, 0.48, 0.34), Color(0.8, 0.68, 0.5), {"spread": half, "speed": 1.2, "floor": origin.y, "amount": 1.0})
	burst("dust", mouth, fwd, Color(0.75, 0.64, 0.5, 0.45), null, {"spread": half, "speed": 0.9, "amount": 0.6})


## ---- Slurry: viscous sludge ----

func _sludge_wave(fi: int, origin: Vector3, yaw: float, length: float, width: float) -> void:
	footprint("sludge", "line", origin, yaw, 0.0, {"length": length, "width": width, "fill": 0.7}, 1.1, 0.25)
	crest(origin, yaw, length, width, 0.65, Color(0.3, 0.5, 0.06, 0.95), Color(0.65, 0.9, 0.2), 0.3, 0.75, {"depth": 0.7})
	var fwd := MathX.forward_of_yaw(yaw)
	burst("gobs", origin + fwd * length * 0.6 + Vector3.UP * 0.3, fwd + Vector3.UP * 1.2, Color(0.42, 0.68, 0.1), Color(0.62, 0.86, 0.2),
		{"box": Vector3(width * 0.4, 0.1, length * 0.35), "speed": 0.8, "floor": origin.y})
	burst("bubbles", origin + fwd * length * 0.5, Vector3.UP, Color(0.55, 0.85, 0.2, 0.8), null, {"box": Vector3(width * 0.5, 0.05, length * 0.5), "amount": 0.8})


func _on_submerge(fi: int, ev: Dictionary) -> void:
	var a: Vector3 = ev.get("pos", _ground(fi))
	var b: Vector3 = ev.get("dest", a)
	var cid := _cid(fi)
	var m := _move_def(fi, "ability2")
	var delay := float(effect_of(m, "blink").get("delay", 0.4))
	if cid == "f_knell":
		# he comes apart into grave-mist, a wisp streaks across, and he gathers again
		burst("wisps", a + Vector3.UP * 0.9, Vector3.UP, Color(0.65, 0.5, 1.0, 0.75), Color(0.9, 0.85, 1.0, 0.6), {"radius": 0.35, "height": 1.2, "speed": 0.6})
		burst("mist", a + Vector3.UP * 0.4, Vector3.UP, Color(0.55, 0.45, 0.75, 0.35), null, {"radius": 0.4, "amount": 0.6})
		footprint("spectral", "circle", a, 0.0, 0.8, {"fill": 0.5}, 0.9, 0.1)
		_traveller(a + Vector3.UP * 0.9, b + Vector3.UP * 0.9, delay, "wisps", Color(0.7, 0.55, 1.0, 0.85), Color(0.95, 0.9, 1.0, 0.8))
		_later(delay * 0.6, func(): _converge_point(b + Vector3.UP * 0.9, delay * 0.4, Color(0.7, 0.55, 1.0), Color(0.95, 0.9, 1.0), 0.6, "wisps"))
		return
	# Slurry (and any diver): the floor opens into a sludge pool, bubbles trace the path under the
	# floor, and a second pool swells where he will come up
	footprint("sludge", "circle", a, 0.0, 0.85, {"fill": 0.8, "stain_a": 0.6}, delay + 0.6, 0.1)
	burst("gobs", a + Vector3.UP * 0.2, Vector3.UP, Color(0.42, 0.68, 0.1), Color(0.62, 0.86, 0.2), {"amount": 0.6, "speed": 0.8, "floor": a.y})
	burst("bubbles", a + Vector3.UP * 0.05, Vector3.UP, Color(0.55, 0.85, 0.2, 0.8), null, {"radius": 0.6})
	_traveller(a + Vector3.UP * 0.05, b + Vector3.UP * 0.05, delay, "bubbles", Color(0.55, 0.85, 0.2, 0.85), null)
	footprint("sludge", "circle", b, 0.0, 0.9, {"fill": 0.8, "front": 0.2, "stain_a": 0.6}, delay + 0.5, delay)


## A moving emitter from a to b over `dur` (underground bubbles, a travelling wisp).
func _traveller(a: Vector3, b: Vector3, dur: float, preset: String, ca: Color, cb) -> void:
	if quality <= 0:
		return
	var gp := stream(preset, ca, cb, {"amount": 1.0, "speed": 0.4, "life": 0.7})
	gp.global_position = a
	animate(gp, dur, func(k: float, _t: float) -> void:
		gp.global_position = a.lerp(b, k * k * (3.0 - 2.0 * k))
		if k >= 1.0:
			end_stream(gp), true)


func _drain_emerge(pos: Vector3, r: float) -> void:
	footprint("sludge", "circle", pos, 0.0, r, {"fill": 0.75, "front": 0.8}, 1.0, 0.1)
	ring_wall(pos, 0.3, r, 0.7, Color(0.32, 0.52, 0.07, 0.95), Color(0.65, 0.9, 0.22), 0.45, {"add": false, "lean": 0.7, "core": 0.8})
	burst("gobs", pos + Vector3.UP * 0.2, Vector3.UP, Color(0.42, 0.68, 0.1), Color(0.62, 0.86, 0.2), {"speed": 1.3, "spread": 0.5, "floor": pos.y})
	burst("bubbles", pos + Vector3.UP * 0.1, Vector3.UP, Color(0.55, 0.85, 0.2, 0.8), null, {"radius": r * 0.6})


## ---- Jitters: electrical discharge ----

func _static_burst(fi: int, pos: Vector3, r: float, vfx: String) -> void:
	var big := vfx == "overcharge"
	var rr := maxf(r, 0.4)
	footprint("static", "circle", pos, 0.0, rr, {"fill": 0.55 if big else 0.4, "front": 1.0}, 0.8 if big else 0.55, 0.08)
	var c := Color(1.0, 0.9, 0.3)
	var forks := 9 if big else (5 if rr >= 1.0 else 3)
	var h := 0.35 if vfx != "discharge" else 0.0
	var src := pos + Vector3.UP * (0.6 if vfx != "discharge" else 0.0)
	for k in forks:
		var a := TAU * (float(k) + _rng.randf() * 0.6) / forks
		var tip := pos + Vector3(sin(a), 0, cos(a)) * rr + Vector3.UP * (0.05 + h * _rng.randf())
		bolt(src, tip, c, 0.24 if big else 0.16, 0.07 if big else 0.05, 0.25)
	if big:
		ring_wall(pos, 0.3, rr, 0.5, Color(1.0, 0.92, 0.4), Color(1, 1, 0.9), 0.3, {"bands": 14.0, "scroll": Vector2(3.0, 0.0)})
		_body_arcs(fi, 4, 0.25)
	burst("sparks", src, Vector3.UP, Color(1.0, 0.95, 0.6), Color(1.0, 1.0, 0.95), {"amount": 1.0 if big else 0.5, "speed": 1.2 if big else 0.8, "floor": pos.y})
	flash_light(src, Color(1.0, 0.95, 0.6), 4.0 if big else 2.0, rr * 2.0 + 1.0, 0.18)


## ---- Knell: spectral motion ----

func _knell_bell(fi: int, m: MoveDef) -> void:
	# a ghostly bell hangs over him for the whole JUICE move and swings with each toll
	var dur := m.duration + 0.2
	var pivot := Node3D.new()           # the bell's crown: it swings about this point
	add_child(pivot)
	var mi := MeshInstance3D.new()
	mi.mesh = FxKit.wall_mesh(32, 0.45)  # wide mouth at the bottom, narrow crown on top
	var mat := FxKit.flow_material(Color(0.45, 0.25, 0.9), Color(0.85, 0.75, 1.0), {"cover": 0.85, "glow_k": 0.9, "scroll": Vector2(0.2, -0.4),
		"noise_scale": Vector2(6.0, 2.0), "edge_v": 0.15, "core": 0.1, "core_width": 0.25, "alpha": 0.0})
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(0.32, 0.4, 0.32)
	mi.position = Vector3(0, -0.4, 0)
	pivot.add_child(mi)
	follow(pivot, fi, "head", Vector3(0, 0.78, 0), dur)
	var tolls: Array = []
	for e in m.effects:
		if str((e as Dictionary).get("type", "")) == "area":
			tolls.append(float(e.get("t", 0.0)))
	animate(pivot, dur, func(k: float, t: float) -> void:
		var swing := 0.0
		for tt in tolls:
			var u := clampf((t - float(tt) + 0.15) / 0.55, 0.0, 1.0)
			if u > 0.0 and u < 1.0:
				swing += sin(u * TAU) * 0.35 * (1.0 - u)
		pivot.rotation = Vector3(swing, 0, 0)
		mat.set_shader_parameter("alpha", smoothstep(0.0, 0.15, k) * (1.0 - smoothstep(0.85, 1.0, k)) * 0.9))


func _knell_toll(fi: int, pos: Vector3, r: float) -> void:
	footprint("spectral", "circle", pos, 0.0, r, {"fill": 0.4, "front": 1.0}, 0.9, 0.14)
	# the toll: a ring of sound rolls out to exactly the toll's reach
	ring_wall(pos + Vector3.UP * 0.05, 0.3, r, 0.75, Color(0.62, 0.45, 1.0), Color(0.95, 0.92, 1.0), 0.5, {"bands": 3.0, "scroll": Vector2(0.0, -1.5), "core": 0.5, "core_width": 0.3, "expand": 0.45})
	burst("wisps", pos + Vector3.UP * 0.4, Vector3.UP, Color(0.68, 0.52, 1.0, 0.7), Color(0.9, 0.85, 1.0, 0.6), {"ring": true, "radius": r * 0.85, "speed": 0.3, "amount": 0.7})
	flash_light(anchor(fi, "head", Vector3(0, 0.45, 0)), Color(0.7, 0.55, 1.0), 2.0, r + 2.0, 0.3)


## ---- Varga: precise martial impact ----

func _varga_dash(fi: int, _ev: Dictionary) -> void:
	var dur := 0.22
	_varga_afterimage(fi, _ground(fi), dur)
	var g := _ground(fi)
	burst("dust", g, -_fwd(fi) + Vector3.UP * 0.2, Color(0.85, 0.8, 0.72, 0.35), null, {"amount": 0.4, "speed": 0.6})


## Crisp speed lines streaming off his body along the move (a cut, not a smear).
func _varga_afterimage(fi: int, _from: Vector3, dur: float) -> void:
	if quality <= 0:
		return
	for part in ["chest", "lFist", "rFist"]:
		var rib := ribbon(Color(1.0, 0.82, 0.55), Color(1, 1, 1), true)
		var hist := []
		animate(rib, dur + 0.2, func(k: float, t: float) -> void:
			if t <= dur:
				hist.append(anchor(fi, part))
			if hist.size() > 10:
				hist.pop_front()
			var w := []
			var al := []
			for i in hist.size():
				w.append(0.05 if part != "chest" else 0.12)
				al.append(0.8 * float(i) / maxf(1.0, hist.size() - 1) * (1.0 - smoothstep(0.6, 1.0, k)))
			draw_ribbon(rib, hist, w, al))


# ---- generic contact for other areas / fighters --------------------------------------------

func _generic_area(fi: int, cid: String, el: String, shape: String, pos: Vector3, origin: Vector3, yaw: float, r: float, ev: Dictionary) -> void:
	if r <= 0.0 and shape != "line":
		return
	var o := {"cone_deg": float(ev.get("cone_deg", 60.0)), "length": float(ev.get("length", 3.0)), "width": float(ev.get("width", 1.0)),
		"inner": float(ev.get("inner", 0.0)), "fill": 0.45}
	var at := origin if shape in ["cone", "cone_back", "line"] else pos
	footprint(el, shape, at, yaw, r, o, 0.75, 0.12)
	if shape == "circle" or shape == "ring":
		var c := FxKit.el_color(el)
		var covers := FxKit.AREA_COVERS.has(el)
		ring_wall(pos, 0.2, r, 0.5, c, FxKit.el_hot(el), 0.4, {"add": not covers, "bands": 0.0 if covers else 6.0})
	_element_burst(el, pos + Vector3.UP * 0.4, 1.0, pos.y)
	if cid == "f_varga":
		_varga_ring(pos, r)
	elif cid == "f_knell":
		burst("wisps", pos + Vector3.UP * 0.5, Vector3.UP, Color(0.68, 0.52, 1.0, 0.7), null, {"ring": true, "radius": r * 0.8, "speed": 0.4})


func _varga_ring(pos: Vector3, r: float) -> void:
	# a clean, tight shock ring and a gold star-burst: the hit lands exactly where he means it to
	ring_wall(pos + Vector3.UP * 0.05, 0.15, r, 0.35, Color(0.95, 0.62, 0.22), Color(1.0, 0.9, 0.6), 0.22, {"add": false, "bands": 0.0, "expand": 0.35, "core": 0.5})
	footprint("scrap", "circle", pos, 0.0, r, {"fill": 0.55, "front": 1.0}, 0.5, 0.06)
	burst("glints", pos + Vector3.UP * 0.9, Vector3.UP, Color(1.0, 0.75, 0.35), Color(1.0, 0.95, 0.75), {"amount": 1.0, "speed": 1.2, "scale": 1.4})


func _buff(fi: int, cid: String, ev: Dictionary) -> void:
	var p := anchor(fi, "core")
	match cid:
		"f_varga":
			# Second Wind / Cut the Angle / Championship Rounds: a breath ring and rising focus motes
			var g := _ground(fi)
			ring_wall(g + Vector3.UP * 0.05, 0.3, 1.2, 0.3, Color(0.95, 0.68, 0.32), Color(1.0, 0.92, 0.7), 0.35, {"add": false, "bands": 0.0, "core": 0.5})
			burst("motes", p, Vector3.UP, Color(1.0, 0.85, 0.55), Color(1, 1, 0.9), {"radius": 0.35, "height": 0.3, "speed": 0.8, "spread": 0.3, "amount": 0.7})
			burst("glints", anchor(fi, "lFist"), Vector3.UP, Color(1.0, 0.86, 0.55), null, {"amount": 0.3, "speed": 0.4})
			burst("glints", anchor(fi, "rFist"), Vector3.UP, Color(1.0, 0.86, 0.55), null, {"amount": 0.3, "speed": 0.4})
		"f_knell":
			burst("wisps", p, Vector3.UP, Color(0.68, 0.52, 1.0, 0.7), null, {"radius": 0.4, "amount": 0.6})
		"f_dozer":
			burst("dust", _ground(fi), Vector3.UP, Color(0.75, 0.62, 0.45, 0.5), null, {"ring": true, "radius": 0.8, "amount": 0.6})
		"f_stoke":
			pass        # Stoke the Fire is drawn by its own vfx id
		_:
			var el := str(ev.get("element", ""))
			burst("motes", p, Vector3.UP, FxKit.el_color(el) if el != "" else Color(1.0, 0.9, 0.6), null, {"radius": 0.4, "amount": 0.5})


func _muzzle(fi: int, cid: String, el: String, _vfx: String) -> void:
	match cid:
		"f_dredge":
			burst("spray", anchor(fi, "head", Vector3(0, 0, 0.2)), _fwd(fi) + Vector3.UP * 0.4, Color(0.35, 0.65, 0.95, 0.8), null, {"amount": 0.5, "speed": 0.6, "spread": 0.4})
		"f_gusto":
			burst("wind", anchor(fi, "beak"), _fwd(fi), Color(0.42, 0.78, 0.8, 0.5), null, {"amount": 0.4, "spread": 0.4})
		"f_slurry":
			burst("gobs", anchor(fi, "fang"), _fwd(fi) + Vector3.UP * 0.3, Color(0.42, 0.68, 0.1), Color(0.62, 0.86, 0.2), {"amount": 0.3, "speed": 0.5, "floor": _ground(fi).y})
		"f_jitters":
			burst("sparks", anchor(fi, "antenna_l"), Vector3.UP, Color(1.0, 0.95, 0.6), null, {"amount": 0.5, "floor": _ground(fi).y})
			bolt(anchor(fi, "antenna_l"), anchor(fi, "antenna_r"), Color(1.0, 0.92, 0.35), 0.1, 0.05, 0.08)
		"f_knell":
			burst("wisps", fpoint(fi, Vector3(0, 1.2, 0.5)), _fwd(fi), Color(0.7, 0.55, 1.0, 0.7), null, {"amount": 0.4, "speed": 0.5})
		_:
			if el != "":
				_element_burst(el, anchor(fi, "core", Vector3(0, 0, 0.3)), 0.4, _ground(fi).y)


func _push_wave(_fi: int, pos: Vector3, r: float, el: String, pull: bool) -> void:
	var c := FxKit.el_color(el) if el != "" else Color(0.85, 0.9, 1.0)
	ring_wall(pos + Vector3.UP * 0.05, r if pull else 0.2, 0.2 if pull else r, 0.4, c, Color(1, 1, 1), 0.3, {"bands": 8.0})


func _sky_bolt(pos: Vector3, r: float, el: String) -> void:
	# Stormfront's delayed strike: a bolt from above into the marked circle
	var c := FxKit.el_color(el if el != "" else "static")
	bolt(pos + Vector3(0.3, 6.0, -0.2), pos + Vector3.UP * 0.05, c, 0.3, 0.12, 0.6)
	footprint("static", "circle", pos, 0.0, maxf(r, 0.6), {"fill": 0.6, "front": 1.0}, 0.6, 0.06)
	burst("sparks", pos + Vector3.UP * 0.1, Vector3.UP, Color(1.0, 0.95, 0.6), null, {"speed": 1.2, "floor": pos.y})
	flash_light(pos + Vector3.UP * 1.0, Color(1.0, 0.95, 0.7), 5.0, 5.0, 0.2)


func _zone_spawn_splash(el: String, pos: Vector3, r: float, _vfx: String) -> void:
	# a projectile turning into a puddle (Tide Spit, Sludge Lob) splashes where it lands
	var rr := maxf(r, 0.8)
	match el:
		"brine":
			burst("spray", pos + Vector3.UP * 0.15, Vector3.UP, Color(0.35, 0.65, 0.95, 0.85), null, {"ring": true, "radius": 0.2, "speed": 1.0, "spread": 0.35})
			burst("drops", pos + Vector3.UP * 0.15, Vector3.UP, Color(0.4, 0.7, 1.0, 0.85), null, {"speed": 0.9, "spread": 0.6, "amount": 0.7, "floor": pos.y})
			ring_wall(pos, 0.1, rr, 0.25, Color(0.3, 0.62, 0.95, 0.8), Color(0.9, 0.97, 1.0), 0.4, {"add": false, "core": 0.8})
		"sludge":
			burst("gobs", pos + Vector3.UP * 0.15, Vector3.UP, Color(0.42, 0.68, 0.1), Color(0.62, 0.86, 0.2), {"speed": 0.9, "spread": 0.7, "amount": 0.8, "floor": pos.y})
			burst("bubbles", pos + Vector3.UP * 0.05, Vector3.UP, Color(0.55, 0.85, 0.2, 0.8), null, {"radius": rr * 0.5})
		"":
			pass
		_:
			_element_burst(el, pos + Vector3.UP * 0.2, 0.6, pos.y)


# =====================================================================================
# Hits, statuses, reactions
# =====================================================================================

func _on_hit(ev: Dictionary) -> void:
	if bool(ev.get("blocked", false)):
		return
	var dmg := float(ev.get("damage", 0.0))
	if dmg < 1.5:
		return
	var p: Vector3 = ev.get("point", Vector3.ZERO)
	var el := str(ev.get("element", ""))
	var ai := int(ev.get("fighter", -1))
	var cid := _cid(ai) if ai >= 0 else ""
	var s := clampf(dmg / 12.0, 0.25, 1.0)
	var ti := int(ev.get("target", -1))
	var fy := _ground(ti).y if ti >= 0 else 0.0
	if cid == "f_varga":
		_varga_impact(p, ev.get("normal", Vector3.UP), s, bool(ev.get("counter", false)))
	if el != "":
		_element_burst(el, p, s * 0.8, fy)


## Varga: a crisp four-point burst and short impact lines along the strike, struck-metal sparks on
## the big ones.
func _varga_impact(p: Vector3, normal: Vector3, s: float, counter: bool) -> void:
	burst("glints", p, Vector3.UP, Color(1.0, 0.92, 0.75), Color(1, 1, 1), {"amount": 0.4 + 0.6 * s, "speed": 0.6 + s, "scale": 0.8 + s})
	if quality >= 1:
		var n := normal.normalized() if normal.length_squared() > 1e-6 else Vector3.UP
		for k in 4:
			var d := (-n + Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.4, 0.6), _rng.randf_range(-0.6, 0.6))).normalized()
			var rib := ribbon(Color(1.0, 0.88, 0.62), Color(1, 1, 1), true)
			var len := 0.25 + 0.35 * s
			animate(rib, 0.16, func(k2: float, _t: float) -> void:
				var a := p + d * (0.08 + len * k2)
				var b := p + d * (0.08 + len * minf(1.0, k2 + 0.45))
				draw_ribbon(rib, [a, b], [0.035, 0.0], [1.0 - k2, 1.0 - k2]))
	if s >= 0.6 or counter:
		burst("sparks", p, Vector3.UP, Color(1.0, 0.75, 0.4), Color(1.0, 0.95, 0.8), {"amount": 0.5 + 0.5 * s})
		ring_wall(p, 0.05, 0.45 + 0.3 * s, 0.12, Color(1.0, 0.85, 0.6), Color(1, 1, 1), 0.18, {"bands": 0.0})


## The element's small/medium burst (ART_DIRECTION §6) at a point.
func _element_burst(el: String, p: Vector3, s: float, floor_y: float) -> void:
	var c := FxKit.el_color(el)
	var h := FxKit.el_hot(el)
	match el:
		"scorch":
			burst("flames", p, Vector3.UP, Color(1.0, 0.5, 0.12, 0.95), Color(1.0, 0.85, 0.4, 0.95), {"amount": 0.5 * s + 0.2, "scale": 0.6 + 0.6 * s})
			burst("cinders", p, Vector3.UP, Color(1.0, 0.7, 0.25), null, {"amount": 0.4 * s + 0.1, "speed": 0.8})
		"brine":
			burst("drops", p, Vector3.UP, Color(0.4, 0.7, 1.0, 0.85), Color(0.8, 0.95, 1.0, 0.85), {"amount": 0.5 * s + 0.15, "floor": floor_y})
			burst("spray", p, Vector3.UP, Color(0.4, 0.68, 0.95, 0.8), null, {"amount": 0.4 * s + 0.1, "speed": 0.7})
		"gale":
			burst("wind", p, Vector3.UP, Color(0.42, 0.78, 0.8, 0.55), null, {"amount": 0.5 * s + 0.15, "speed": 0.6, "swirl": 5.0})
		"grit":
			burst("pebbles", p, Vector3.UP, Color(0.6, 0.48, 0.34), Color(0.82, 0.7, 0.52), {"amount": 0.5 * s + 0.15, "floor": floor_y})
			burst("dust", p, Vector3.UP, Color(0.78, 0.66, 0.5, 0.45), null, {"amount": 0.3 * s + 0.1, "speed": 0.6})
		"sludge":
			burst("gobs", p, Vector3.UP, Color(0.42, 0.68, 0.1), Color(0.62, 0.86, 0.2), {"amount": 0.45 * s + 0.15, "floor": floor_y})
		"static":
			burst("sparks", p, Vector3.UP, Color(1.0, 0.95, 0.6), Color(1, 1, 0.9), {"amount": 0.5 * s + 0.2, "floor": floor_y})
			if quality >= 1:
				for k in 2:
					var d := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 1), _rng.randf_range(-1, 1)).normalized()
					bolt(p, p + d * (0.25 + 0.3 * s), c, 0.1, 0.03, 0.06)
		"scrap":
			burst("sparks", p, Vector3.UP, Color(1.0, 0.72, 0.4), Color(1.0, 0.92, 0.75), {"amount": 0.45 * s + 0.15, "floor": floor_y})
			burst("shards", p, Vector3.UP, Color(0.75, 0.55, 0.42), Color(0.9, 0.8, 0.7), {"amount": 0.3 * s, "floor": floor_y})
		"spectral":
			burst("wisps", p, Vector3.UP, Color(0.68, 0.52, 1.0, 0.75), Color(0.92, 0.88, 1.0, 0.6), {"amount": 0.5 * s + 0.15, "speed": 0.8})
		_:
			burst("motes", p, Vector3.UP, c, h, {"amount": 0.4 * s + 0.1})


func _on_status(fi: int, el: String) -> void:
	# the element's medium burst wraps the body (status trigger)
	if fi < 0 or el == "":
		return
	var p := anchor(fi, "core")
	_element_burst(el, p, 0.9, _ground(fi).y)
	ring_wall(_ground(fi) + Vector3.UP * 0.05, 0.3, 0.8, 1.2, FxKit.el_color(el), FxKit.el_hot(el), 0.4,
		{"add": not FxKit.AREA_COVERS.has(el), "bands": 5.0, "h_end": 0.6})


func _on_reaction(ev: Dictionary) -> void:
	var p: Vector3 = ev.get("pos", Vector3.ZERO)
	var a := str(ev.get("a", ""))
	var b := str(ev.get("b", ""))
	var fi := int(ev.get("fighter", -1))
	var g := _ground(fi) if fi >= 0 else Vector3(p.x, 0.0, p.z)
	var c := p + Vector3.UP * 0.8
	# both parents' shapes collide at the point for a moment (ART_DIRECTION §7), then the
	# reaction's own large effect
	_element_burst(a, c, 1.0, g.y)
	_element_burst(b, c, 1.0, g.y)
	match str(ev.get("reaction", "")):
		"steam_burst":
			burst("steam", c, Vector3.UP, Color(0.97, 0.97, 0.98, 0.6), Color(0.9, 0.9, 0.95, 0.5), {"spread": 1.4, "speed": 1.0, "amount": 1.0, "scale": 1.4})
			ring_wall(g, 0.3, 2.0, 0.8, Color(0.95, 0.95, 0.97, 0.7), Color(1, 1, 1), 0.5, {"add": false, "core": 0.6})
		"flare_up":
			burst("fireball", c, Vector3.UP, Color(1.0, 0.5, 0.12, 0.95), Color(1.0, 0.95, 0.6, 0.95), {"scale": 2.0, "speed": 1.6})
			burst("gobs", c, Vector3.UP, Color(1.0, 0.55, 0.15), Color(0.6, 0.85, 0.2), {"speed": 1.4, "floor": g.y})
			burst("smoke", c, Vector3.UP, Color(0.25, 0.22, 0.2, 0.5), null, {"amount": 0.8, "speed": 0.6})
			flash_light(c, Color(1.0, 0.6, 0.2), 5.0, 5.0, 0.4)
		"backdraft":
			vortex(g, 2.5, 1.6, Color(1.0, 0.45, 0.1, 0.9), Color(1.0, 0.9, 0.5), 0.7, {"add": true, "turns": 2.0, "r0": 0.3, "spin": 10.0})
			burst("flames", g + Vector3.UP * 0.1, Vector3.UP, Color(1.0, 0.5, 0.12, 0.95), null, {"ring": true, "radius": 2.0, "swirl": 4.0, "amount": 0.8})
		"short_out":
			for k in 6:
				var a2 := TAU * k / 6.0
				bolt(c, g + Vector3(sin(a2), 0.05, cos(a2)) * 1.2, Color(1.0, 0.92, 0.35), 0.35, 0.06, 0.3)
			burst("drops", c, Vector3.UP, Color(0.45, 0.72, 1.0, 0.85), null, {"speed": 1.0, "floor": g.y})
			flash_light(c, Color(1.0, 0.95, 0.6), 4.0, 4.0, 0.3)
		"mudbound":
			burst("gobs", c, Vector3.UP, Color(0.45, 0.33, 0.2), Color(0.6, 0.46, 0.3), {"speed": 1.2, "floor": g.y})
			footprint("grit", "circle", g, 0.0, 2.5, {"color": Color(0.45, 0.33, 0.2), "fill": 0.6, "additive": 0.0}, 0.8, 0.15)
		"dilute":
			burst("spray", c, Vector3.UP, Color(0.4, 0.68, 0.95, 0.8), null, {"speed": 1.2, "amount": 1.0})
			burst("gobs", c, Vector3.UP, Color(0.45, 0.72, 0.15), null, {"speed": 0.9, "amount": 0.5, "floor": g.y})
		"catalyze":
			burst("bubbles", c, Vector3.UP, Color(0.6, 0.95, 0.25, 0.9), null, {"radius": 0.5, "amount": 1.0, "speed": 1.5})
			burst("sparks", c, Vector3.UP, Color(1.0, 0.95, 0.5), null, {"amount": 0.6, "floor": g.y})
		"stormfront":
			vortex(g, 1.5, 1.2, Color(0.4, 0.75, 0.8, 0.6), Color(1.0, 0.95, 0.6), 0.6, {"add": true, "turns": 2.0, "spin": 12.0})
		"crust":
			burst("chunks", c, Vector3.UP, Color(0.45, 0.5, 0.25), Color(0.6, 0.5, 0.35), {"speed": 0.7, "spread": 1.2, "floor": g.y})
			ring_wall(g, 0.5, 0.6, 1.4, Color(0.5, 0.45, 0.3, 0.9), Color(0.7, 0.65, 0.45), 0.8, {"add": false, "h_end": 1.0, "expand": 0.2})
		"spray":
			burst("gobs", c, Vector3.UP, Color(0.42, 0.68, 0.1), Color(0.62, 0.86, 0.2), {"spread": 1.3, "speed": 1.6, "floor": g.y})
			burst("wind", c, Vector3.UP, Color(0.42, 0.78, 0.8, 0.5), null, {"amount": 0.6, "swirl": 5.0})
		"sandblast":
			burst("dust", c, -Vector3.UP, Color(0.85, 0.72, 0.5, 0.55), null, {"spread": 1.2, "speed": 1.4, "amount": 1.0})
			burst("pebbles", c, Vector3.UP, Color(0.75, 0.62, 0.45), null, {"speed": 1.4, "floor": g.y})
		"bell_ringer":
			ring_wall(c, 0.1, 1.6, 0.25, Color(1.0, 0.8, 0.5), Color(1, 1, 1), 0.35, {"bands": 0.0})
			ring_wall(c, 0.1, 2.2, 0.25, Color(0.65, 0.5, 1.0), Color(0.95, 0.9, 1.0), 0.5, {"bands": 0.0})
			burst("glints", c, Vector3.UP, Color(1.0, 0.9, 0.7), null, {"speed": 1.5})
		"grave_chill":
			burst("mist", c, Vector3.UP, Color(0.75, 0.8, 1.0, 0.45), null, {"amount": 1.0, "speed": 0.8})
			burst("shards", c, Vector3.UP, Color(0.75, 0.85, 1.0), Color(0.85, 0.75, 1.0), {"amount": 0.7, "floor": g.y})
		"crack_guard":
			burst("shards", c, Vector3.UP, Color(0.85, 0.6, 0.4), Color(0.7, 0.55, 0.4), {"speed": 1.3, "floor": g.y})
			burst("pebbles", c, Vector3.UP, Color(0.7, 0.58, 0.42), null, {"amount": 0.6, "floor": g.y})
		_:
			burst("motes", c, Vector3.UP, FxKit.el_color(a), FxKit.el_color(b), {"speed": 1.5})


func _on_zone_reaction(ev: Dictionary) -> void:
	var p: Vector3 = ev.get("pos", Vector3.ZERO)
	_element_burst(str(ev.get("a", "")), p + Vector3.UP * 0.3, 0.8, p.y)
	_element_burst(str(ev.get("b", "")), p + Vector3.UP * 0.3, 0.8, p.y)


func _on_spring(ev: Dictionary) -> void:
	var p: Vector3 = ev.get("pos", Vector3.ZERO)
	for id in _ents:
		var en: Dictionary = _ents[id]
		if str(en.get("kind", "")) == "prop" and (en["pos"] as Vector3).distance_to(p) < 0.3:
			en["bounce"] = _clock
	burst("sparks", p + Vector3.UP * 0.2, Vector3.UP, Color(1.0, 0.95, 0.6), null, {"amount": 0.6, "floor": p.y})
	ring_wall(p + Vector3.UP * 0.05, 0.3, 1.1, 0.2, Color(1.0, 0.92, 0.4), Color(1, 1, 0.9), 0.3, {"bands": 10.0})


func _on_juice(fi: int) -> void:
	# JUICE activation (ART_DIRECTION §7): a 3 m ring in the fighter's JUICE colour; the move's own
	# preparation (above) carries the fighter-specific part
	var v := _view(fi)
	var jc := v.juice_color if v != null else Color(1.0, 0.6, 0.1)
	ring_wall(_ground(fi) + Vector3.UP * 0.05, 0.4, 3.0, 0.45, jc, Color(1, 1, 0.9), 0.5, {"bands": 0.0, "core": 0.3})


# =====================================================================================
# Continuous: JUICE auras and heavy charge
# =====================================================================================

func _juice_aura(fi: int) -> Dictionary:
	var cid := _cid(fi)
	var streams: Array = []
	var forever := 1e9
	var add := func(gp: GPUParticles3D) -> void:
		if gp != null:
			streams.append(gp)
	match cid:
		"f_stoke":
			for off in STOKE_STACKS:
				add.call(_stream_at(fi, "core", off, forever, "flames", Color(1.0, 0.5, 0.12, 0.9), Color(1.0, 0.85, 0.4, 0.9), {"amount": 0.35, "speed": 0.7, "spread": 0.3}))
			add.call(_stream_at(fi, "core", Vector3.ZERO, forever, "cinders", Color(1.0, 0.7, 0.25), null, {"amount": 0.3, "speed": 0.4, "radius": 0.3}))
		"f_dredge":
			add.call(_stream_at(fi, "core", Vector3(0, 0.1, 0), forever, "drops", Color(0.45, 0.72, 1.0, 0.85), null, {"dir": Vector3.DOWN, "speed": 0.1, "amount": 0.35, "radius": 0.4, "floor": _ground(fi).y}))
			add.call(_stream_at(fi, "core", Vector3(0, -0.2, 0), forever, "mist", Color(0.5, 0.7, 0.95, 0.3), null, {"amount": 0.3, "speed": 0.2, "radius": 0.5}))
		"f_gusto":
			add.call(_stream_at(fi, "core", Vector3.ZERO, forever, "wind", Color(0.42, 0.78, 0.8, 0.45), null, {"amount": 0.35, "speed": 0.3, "swirl": 8.0, "radius": 0.4}))
		"f_dozer":
			add.call(_stream_at(fi, "core", Vector3(0, 0.2, 0), forever, "pebbles", Color(0.6, 0.48, 0.34), Color(0.82, 0.7, 0.52), {"dir": Vector3.DOWN, "speed": 0.1, "amount": 0.25, "radius": 0.4, "floor": _ground(fi).y}))
			add.call(_stream_at(fi, "core", Vector3(0, -0.3, 0), forever, "dust", Color(0.75, 0.64, 0.48, 0.35), null, {"amount": 0.3, "speed": 0.2, "radius": 0.5}))
		"f_slurry":
			add.call(_stream_at(fi, "head", Vector3.ZERO, forever, "gobs", Color(0.42, 0.68, 0.1), Color(0.62, 0.86, 0.2), {"dir": Vector3.DOWN, "speed": 0.1, "amount": 0.25, "scale": 0.6, "floor": _ground(fi).y}))
			add.call(_stream_at(fi, "body3", Vector3.ZERO, forever, "bubbles", Color(0.55, 0.85, 0.2, 0.8), null, {"amount": 0.35, "radius": 0.3}))
		"f_jitters":
			add.call(_stream_at(fi, "core", Vector3(0, 0.15, 0), forever, "sparks", Color(1.0, 0.95, 0.6), null, {"amount": 0.2, "speed": 0.4, "radius": 0.25, "floor": _ground(fi).y}))
		"f_varga":
			add.call(_stream_at(fi, "lFist", Vector3.ZERO, forever, "glints", Color(1.0, 0.86, 0.55), null, {"amount": 0.25, "speed": 0.2}))
			add.call(_stream_at(fi, "rFist", Vector3.ZERO, forever, "glints", Color(1.0, 0.86, 0.55), null, {"amount": 0.25, "speed": 0.2}))
		"f_knell":
			add.call(_stream_at(fi, "core", Vector3(0, 0.1, 0), forever, "wisps", Color(0.66, 0.5, 1.0, 0.6), Color(0.9, 0.85, 1.0, 0.5), {"amount": 0.35, "speed": 0.2, "radius": 0.3}))
		_:
			var v := _view(fi)
			var jc := v.juice_color if v != null else Color(1.0, 0.6, 0.1)
			add.call(_stream_at(fi, "core", Vector3.ZERO, forever, "motes", jc, null, {"amount": 0.3, "speed": 0.4, "radius": 0.3}))
	# the Jitters crackle: arcs crawling over the body now and then
	var crackle := cid == "f_jitters"
	var holder := Node3D.new()
	add_child(holder)
	var st := {"next": 0.0}
	animate(holder, 1e9, func(_k: float, t: float) -> void:
		if crackle and t >= float(st["next"]) and quality >= 1:
			st["next"] = t + (0.5 if reduce_flashes else 0.22)
			_body_arcs(fi, 1, 0.12), true)
	var end := func() -> void:
		# letting go of the followers ends their streams (see _stream_at)
		for f in _follows:
			if streams.has(f["node"]):
				f["until"] = _clock
		if is_instance_valid(holder):
			holder.queue_free()
	return {"node": holder, "end": end}


func _update_charge(fi: int, inf: Dictionary, alive: bool) -> void:
	if not _charges.has(fi):
		return
	var ch: Dictionary = _charges[fi]
	var m: MoveDef = ch["def"]
	var t := _clock - float(ch["t0"])
	var level := float(inf.get("charge", -2.0))
	var state := int(inf.get("state", Fighter.State.ATTACK))
	var start := m.first_active() * 0.7
	var lv := 0.0
	if level >= 0.0:
		lv = level                                   # local: the real charge
	elif level == -2.0:
		lv = clampf((t - start) / maxf(m.charge_time, 0.05), 0.0, 1.0)   # online: by time
	var done := not alive or state != Fighter.State.ATTACK or t > start + m.charge_time + 0.35 or (level == -1.0 and t > start + 0.05)
	if done:
		_end_charge(fi, false)
		return
	if lv <= 0.02:
		return
	if ch["node"] == null:
		ch["node"] = _charge_glow(fi, m)
	var g: Dictionary = ch["node"]
	(g["set"] as Callable).call(lv)


func _charge_glow(fi: int, m: MoveDef) -> Dictionary:
	var el := m.element if m.element != "" else (_view(fi).creature.element if _view(fi) != null else "")
	var weapon := ""
	if not m.windows.is_empty():
		var ws = (m.windows[0] as Dictionary).get("weapons", [])
		if ws.size() > 0:
			weapon = str(ws[0])
	if weapon == "":
		weapon = "core"
	var c := FxKit.el_color(el)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	var mat := FxKit.flow_material(FxKit.el_paint(el), FxKit.el_glow(el), {"additive": 0.45, "fresnel": 1.2, "scroll": Vector2(0.4, -1.2), "noise_scale": Vector2(5.0, 3.0), "edge_v": 0.0, "core": 0.5, "core_width": 0.5, "alpha": 0.0})
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	follow(mi, fi, weapon, Vector3.ZERO, 1e9)
	_follows[-1]["tag"] = "charge"
	var preset := str({"scorch": "cinders", "brine": "spray", "gale": "wind", "grit": "pebbles", "sludge": "bubbles", "static": "sparks", "spectral": "wisps", "scrap": "glints"}.get(el, "motes"))
	var gp := _stream_at(fi, weapon, Vector3.ZERO, 1e9, str(preset), c, FxKit.el_hot(el), {"amount": 0.4, "speed": 0.3, "radius": 0.15, "floor": _ground(fi).y}, "charge")
	var set := func(lv: float) -> void:
		if is_instance_valid(mi):
			mi.scale = Vector3.ONE * (0.12 + 0.28 * lv)
			mat.set_shader_parameter("alpha", (0.35 + 0.65 * lv) * (0.7 if reduce_flashes else 1.0))
		if gp != null and is_instance_valid(gp):
			gp.amount_ratio = clampf((0.2 + 0.8 * lv) * _ratio(), 0.02, 1.0)
	return {"set": set, "mi": mi, "weapon": weapon, "color": c}


func _end_charge(fi: int, released: bool) -> void:
	if not _charges.has(fi):
		return
	var ch: Dictionary = _charges[fi]
	_charges.erase(fi)
	release(fi, "charge")
	var g = ch["node"]
	if g is Dictionary:
		var mi: MeshInstance3D = g["mi"]
		if released and is_instance_valid(mi):
			var c: Color = g["color"]
			burst("glints", mi.global_position, Vector3.UP, c.lightened(0.4), null, {"amount": 0.8, "speed": 1.0})
			flash_light(mi.global_position, c, 2.5, 2.5, 0.2)
		if is_instance_valid(mi):
			mi.queue_free()


# ---- weapon trails (charged heavies, finishers, Varga's strikes): one per fighter -------------

func _start_trail(fi: int, m: MoveDef) -> void:
	if quality <= 0 or m.windows.is_empty():
		return
	var w0 := m.windows[0] as Dictionary
	var ws = w0.get("weapons", [])
	if ws.size() == 0:
		return
	var old: Dictionary = _trails.get(fi, {})
	if not old.is_empty() and is_instance_valid(old["rib"]):
		(old["rib"] as Node).queue_free()
	var el := m.element if m.element != "" else (_view(fi).creature.element if _view(fi) != null else "")
	var c := Color(1.0, 0.88, 0.6) if _cid(fi) == "f_varga" else FxKit.el_color(el)
	var rib := ribbon(c, Color(1, 1, 1) if _cid(fi) == "f_varga" else FxKit.el_hot(el), true)
	_trails[fi] = {"rib": rib, "pts": [], "weapon": str(ws[0]), "t0": _clock + float(w0.get("t0", 0.0)) - 0.04,
		"t1": _clock + m.last_active() + 0.05, "w": 0.14 if _cid(fi) != "f_varga" else 0.09}


func _update_trails() -> void:
	for fi in _trails.keys():
		var tr: Dictionary = _trails[fi]
		var rib: MeshInstance3D = tr["rib"]
		if not is_instance_valid(rib):
			_trails.erase(fi)
			continue
		var pts: Array = tr["pts"]
		if _clock >= float(tr["t0"]) and _clock <= float(tr["t1"]) and _view(fi) != null:
			pts.append([anchor(fi, str(tr["weapon"])), _clock])
		while not pts.is_empty() and _clock - float(pts[0][1]) > 0.13:
			pts.pop_front()
		if pts.is_empty() and _clock > float(tr["t1"]):
			rib.queue_free()
			_trails.erase(fi)
			continue
		var p := []
		var w := []
		var al := []
		for i in pts.size():
			var age := _clock - float(pts[i][1])
			p.append(pts[i][0])
			w.append(float(tr["w"]) * (1.0 - age / 0.13))
			al.append(clampf(1.0 - age / 0.13, 0.0, 1.0) * 0.9)
		draw_ribbon(rib, p, w, al)


# =====================================================================================
# Entities: projectiles, zones, props, delayed strikes
# =====================================================================================

func sync_entities(entities: Array) -> void:
	var seen := {}
	for e in entities:
		var spec = e.get("e", {})
		if typeof(spec) == TYPE_DICTIONARY and (spec as Dictionary).has("hazard"):
			continue      # hazard zones and arena pads are drawn by the arena
		var id := int(e["id"])
		seen[id] = true
		var en: Dictionary = _ents.get(id, {})
		if en.is_empty():
			en = _make_entity(e)
			_ents[id] = en
		_update_entity(en, e)
	for id in _ents.keys():
		if not seen.has(id):
			var en2: Dictionary = _ents[id]
			_ents.erase(id)
			(en2["end"] as Callable).call()


func _make_entity(e: Dictionary) -> Dictionary:
	var kind := str(e.get("kind", "zone"))
	match kind:
		"projectile":
			return _make_projectile(e)
		"prop":
			return _make_prop(e)
		"delayed":
			return _make_marker(e)
	return _make_zone(e)


func _update_entity(en: Dictionary, e: Dictionary) -> void:
	var node: Node3D = en["node"]
	if not is_instance_valid(node):
		return
	var p: Vector3 = e["pos"]
	if str(en["kind"]) == "projectile":
		var last: Vector3 = en["pos"]
		var vel := p - last
		node.global_position = p
		if vel.length_squared() > 1e-6:
			en["dir"] = vel.normalized()
			var up := Vector3.UP if absf(vel.normalized().y) < 0.95 else Vector3.RIGHT
			node.global_basis = Basis.looking_at(vel.normalized(), up)
	else:
		node.global_position = Vector3(p.x, p.y if str(en["kind"]) == "prop" else p.y, p.z)
		if en.has("ground"):
			(en["ground"] as Node3D).global_position = Vector3(p.x, 0.02, p.z)
	en["pos"] = p
	if en.has("tick"):
		(en["tick"] as Callable).call(e)


func _sphere(radius: float, segs := 16) -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = segs
	sm.rings = maxi(6, segs / 2)
	return sm


func _make_projectile(e: Dictionary) -> Dictionary:
	var el := str(e.get("element", ""))
	var vfx := str(e.get("vfx", "orb"))
	var r := maxf(float(e.get("radius", 0.25)), 0.08)
	var root := Node3D.new()
	add_child(root)
	root.global_position = e["pos"]
	var c := FxKit.el_color(el)
	var hot := FxKit.el_hot(el)
	var streams: Array = []
	var animated: Array = []          # [node, fn(t)]
	var look := vfx
	if vfx == "orb":
		look = {"static": "static_orb", "spectral": "ghost_light"}.get(el, "orb")
	match look:
		"brine_glob":
			# a wobbling ball of seawater, shedding droplets and spray
			var mi := MeshInstance3D.new()
			mi.mesh = _sphere(r * 1.15)
			var mat := FxKit.flow_material(Color(0.1, 0.45, 0.9, 1.0), Color(0.75, 0.93, 1.0), {"cover": 1.0, "glow_k": 0.55, "fresnel": 0.6, "scroll": Vector2(0.6, -1.0), "noise_scale": Vector2(4.0, 3.0), "edge_v": 0.0, "core": 0.5, "core_width": 0.6, "alpha": 1.0})
			mi.material_override = mat
			root.add_child(mi)
			animated.append([mi, func(t: float) -> void: mi.scale = Vector3(1.0 + 0.12 * sin(t * 17.0), 1.0 - 0.1 * sin(t * 17.0), 1.0 + 0.08 * cos(t * 13.0))])
			streams.append(_attached_stream(root, "drops", Color(0.4, 0.7, 1.0, 0.85), Color(0.8, 0.95, 1.0, 0.85), {"dir": Vector3.DOWN, "speed": 0.2, "amount": 0.5, "radius": r * 0.6}))
			streams.append(_attached_stream(root, "spray", Color(0.4, 0.68, 0.95, 0.7), null, {"speed": 0.2, "amount": 0.4}))
		"gust_bomb":
			# a knot of air: two crossed spinning swirls around a pale core, wind streaming off it
			var core := MeshInstance3D.new()
			core.mesh = _sphere(r * 0.75)
			core.material_override = FxKit.flow_material(Color(0.3, 0.72, 0.76, 0.85), Color(1, 1, 1), {"additive": 1.0, "fresnel": 2.0, "edge_v": 0.0, "core": 0.5, "core_width": 0.6, "alpha": 0.8})
			root.add_child(core)
			for k in 2:
				var sw := MeshInstance3D.new()
				sw.mesh = FxKit.spiral_mesh(1.6, 0.6, 1.0, 0.3)
				sw.material_override = FxKit.flow_material(Color(0.35, 0.76, 0.8, 0.9), Color(1, 1, 1), {"additive": 1.0, "scroll": Vector2(-2.5, 0.0), "noise_scale": Vector2(6.0, 1.0), "edge_v": 0.5, "core": 0.5, "core_width": 0.35, "bands": 2.0, "alpha": 0.9})
				sw.scale = Vector3(r * 1.5, r * 2.4, r * 1.5)
				sw.position = Vector3(0, -r * 1.2, 0)
				var holder := Node3D.new()
				holder.add_child(sw)
				holder.rotation = Vector3(PI * 0.5 * k, 0, 0)
				root.add_child(holder)
				var kk := k
				animated.append([holder, func(t: float) -> void: holder.rotation = Vector3(PI * 0.5 * kk, t * (14.0 if kk == 0 else -11.0), 0)])
			streams.append(_attached_stream(root, "wind", Color(0.42, 0.78, 0.8, 0.5), null, {"speed": 0.2, "amount": 0.6}))
		"glob", "spit":
			# a lumpy, glossy gob of sludge trailing drips
			var g := MeshInstance3D.new()
			g.mesh = _sphere(r * 1.1, 12)
			var gm := StandardMaterial3D.new()
			gm.albedo_color = Color(0.4, 0.66, 0.1)
			gm.roughness = 0.2
			gm.metallic_specular = 0.8
			gm.rim_enabled = true
			gm.rim = 0.5
			gm.emission_enabled = true
			gm.emission = Color(0.12, 0.25, 0.02)
			g.material_override = gm
			root.add_child(g)
			if look == "glob":
				for k in 2:
					var lump := MeshInstance3D.new()
					lump.mesh = _sphere(r * 0.55, 10)
					lump.material_override = gm
					lump.position = Vector3(0.6 - 1.2 * k, 0.35, -0.3) * r
					root.add_child(lump)
				animated.append([g, func(t: float) -> void: g.scale = Vector3(1.0 + 0.15 * sin(t * 11.0), 1.0 - 0.12 * sin(t * 11.0), 1.0 + 0.2 * absf(sin(t * 6.0)))])
				streams.append(_attached_stream(root, "gobs", Color(0.42, 0.68, 0.1), Color(0.62, 0.86, 0.2), {"dir": Vector3.DOWN, "speed": 0.1, "amount": 0.4, "scale": 0.5}))
			else:
				g.scale = Vector3(0.7, 0.7, 1.8)
				streams.append(_attached_stream(root, "gobs", Color(0.42, 0.68, 0.1), null, {"dir": Vector3.DOWN, "speed": 0.1, "amount": 0.25, "scale": 0.3}))
		"static_orb":
			# a crackling ball: hot core, arcs snapping off it, a spark wake
			var so := MeshInstance3D.new()
			so.mesh = _sphere(r * 0.9)
			so.material_override = FxKit.flow_material(Color(1.0, 0.88, 0.25), Color(1.0, 1.0, 0.9), {"additive": 1.0, "fresnel": 1.0, "scroll": Vector2(2.0, -2.0), "noise_scale": Vector2(6.0, 4.0), "edge_v": 0.0, "core": 0.5, "core_width": 0.6, "alpha": 1.0})
			root.add_child(so)
			var st := {"next": 0.0}
			animated.append([so, func(t: float) -> void:
				so.scale = Vector3.ONE * (0.9 + 0.2 * sin(t * 40.0) if not reduce_flashes else 1.0)
				if t >= float(st["next"]) and quality >= 1:
					st["next"] = t + (0.25 if reduce_flashes else 0.08)
					var d := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
					bolt(root.global_position, root.global_position + d * (r * 2.5 + 0.15), Color(1.0, 0.92, 0.35), 0.07, 0.035, 0.07)])
			streams.append(_attached_stream(root, "sparks", Color(1.0, 0.95, 0.6), null, {"speed": 0.3, "amount": 0.45}))
		"ghost_light":
			# a lantern flame drifting toward its mark, grave-light wisps peeling off behind
			var gl := MeshInstance3D.new()
			gl.mesh = _sphere(r * 0.8)
			gl.material_override = FxKit.flow_material(Color(0.62, 0.45, 1.0), Color(0.97, 0.94, 1.0), {"additive": 1.0, "fresnel": 1.4, "scroll": Vector2(0.4, -1.6), "noise_scale": Vector2(4.0, 3.0), "edge_v": 0.0, "core": 0.5, "core_width": 0.7, "alpha": 1.0})
			root.add_child(gl)
			streams.append(_attached_stream(root, "flames", Color(0.6, 0.45, 1.0, 0.9), Color(0.92, 0.88, 1.0, 0.9), {"speed": 0.2, "amount": 0.6, "scale": 0.9, "buoyancy": 1.5}))
			streams.append(_attached_stream(root, "wisps", Color(0.66, 0.5, 1.0, 0.7), Color(0.9, 0.85, 1.0, 0.5), {"speed": 0.15, "amount": 0.6}))
		_:
			var mi2 := MeshInstance3D.new()
			mi2.mesh = _sphere(r)
			mi2.material_override = FxKit.flow_material(c, hot, {"additive": 1.0, "fresnel": 1.2, "edge_v": 0.0, "core": 0.5, "core_width": 0.6, "alpha": 1.0})
			root.add_child(mi2)
			var trail := str({"scorch": "cinders", "brine": "drops", "gale": "wind", "grit": "pebbles", "sludge": "gobs", "static": "sparks", "spectral": "wisps", "scrap": "glints"}.get(el, "motes"))
			streams.append(_attached_stream(root, str(trail), c, hot, {"speed": 0.2, "amount": 0.4, "scale": 0.6}))
	for n in root.get_children():
		if n is GeometryInstance3D:
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light: OmniLight3D = null
	if quality >= 1 and look != "brine_glob" and look != "glob" and look != "spit":
		light = OmniLight3D.new()
		light.light_color = c
		light.light_energy = 1.2 * (0.6 if reduce_flashes else 1.0)
		light.omni_range = 2.0
		light.shadow_enabled = false
		root.add_child(light)
	var t0 := _clock
	var en := {"node": root, "kind": "projectile", "pos": e["pos"], "dir": Vector3.FORWARD}
	en["tick"] = func(_e: Dictionary) -> void:
		var t := _clock - t0
		for a in animated:
			if is_instance_valid(a[0]):
				(a[1] as Callable).call(t)
	en["end"] = func() -> void:
		for gp in streams:
			if gp != null and is_instance_valid(gp):
				# keep the wake where it is while it fades
				var gpos: Vector3 = gp.global_position
				gp.reparent(self)
				gp.global_position = gpos
				end_stream(gp)
		if is_instance_valid(root):
			root.queue_free()
	return en


func _attached_stream(parent: Node3D, preset: String, ca: Color, cb, o := {}) -> GPUParticles3D:
	if quality <= 0 and not bool(o.get("essential", false)):
		return null
	var gp := stream(preset, ca, cb, o)
	gp.reparent(parent)
	gp.position = Vector3.ZERO
	return gp


## Zone visuals: the footprint in the element's floor pattern plus sparse particles of its kind.
const ZONE_LOOK := {
	"scorch_patch": ["scorch", "flames"], "burning_puddle": ["scorch", "flames"], "brine_puddle": ["brine", "spray"],
	"brine_flood": ["brine", ""], "sludge_puddle": ["sludge", "bubbles"], "fizzing_puddle": ["sludge", "sparks"],
	"static_field": ["static", "sparks"], "live_puddle": ["brine", "sparks"], "storm": ["static", "sparks"],
	"grit_rubble": ["grit", "dust"], "gale_vortex": ["gale", "wind"], "dust_bowl": ["grit", "dust"],
	"mud": ["grit", "bubbles"], "steam": ["", "steam"],
}


func _make_zone(e: Dictionary) -> Dictionary:
	var vfx := str(e.get("vfx", "zone"))
	var kind := str(e.get("zone_kind", ""))
	var el := str(e.get("element", ""))
	var look: Array = ZONE_LOOK.get(vfx, ZONE_LOOK.get(kind, [el, ""]))
	var r := maxf(float(e.get("radius", 1.5)), 0.2)
	var p: Vector3 = e["pos"]
	var root := Node3D.new()
	add_child(root)
	root.global_position = Vector3(p.x, p.y, p.z)
	var fel := str(look[0])
	var o := {"fill": 0.6, "front": 0.0, "speed": 1.0}
	match vfx:
		"brine_flood":
			o = {"fill": 0.42, "front": 0.0, "speed": 0.6, "color": Color(0.2, 0.5, 0.85, 0.55), "color2": Color(0.85, 0.95, 1.0),
				"stain": Color(0.1, 0.35, 0.7), "stain_a": 0.38}
		"mud":
			o = {"fill": 0.75, "color": Color(0.38, 0.27, 0.16, 0.85), "color2": Color(0.55, 0.42, 0.28), "style": 5, "additive": 0.0}
		"dust_bowl":
			o = {"fill": 0.4, "color": Color(0.72, 0.6, 0.44, 0.6), "color2": Color(0.85, 0.75, 0.6), "style": 3, "additive": 0.0, "speed": 2.0}
		"steam":
			o = {"fill": 0.3, "color": Color(0.92, 0.92, 0.95, 0.4), "color2": Color(1, 1, 1), "style": 2, "additive": 0.0}
		"live_puddle":
			o = {"fill": 0.6, "color": Color(0.3, 0.6, 0.95, 0.75), "color2": Color(1.0, 0.95, 0.5)}
		"fizzing_puddle":
			o = {"fill": 0.65, "color": Color(0.5, 0.75, 0.15, 0.85), "color2": Color(1.0, 0.95, 0.5)}
	o["pulse"] = 1.0
	if fel in ["brine", "sludge"] and not o.has("stain_a"):
		o["stain_a"] = 0.5          # puddles read as wet / gooey floor, not just a ring
	var fp := footprint(fel if fel != "" else "brine", "circle", Vector3.ZERO, 0.0, r, o, INF)
	fp.reparent(root)
	fp.position = Vector3.UP * (0.02 + _rng.randf() * 0.01)
	var mat := fp.material_override as ShaderMaterial
	mat.set_shader_parameter("pulse", 1.0)
	# grow in from the centre
	var grow := {"t": 0.0}
	var pt := str(look[1])
	var gp: GPUParticles3D = null
	if pt != "" and quality >= 1:
		var pc := FxKit.el_color(fel) if fel != "" else Color(0.95, 0.95, 0.97, 0.5)
		var amt := clampf(r / 2.0, 0.3, 1.0) * 0.45
		var po := {"radius": r * 0.85, "speed": 0.25, "amount": amt, "floor": p.y}
		match pt:
			"flames":
				pc = Color(1.0, 0.5, 0.12, 0.9)
				po["scale"] = 0.8
			"spray":
				pc = Color(0.35, 0.65, 0.95, 0.6)
				po["amount"] = amt * 0.4
			"bubbles":
				pc = Color(0.55, 0.85, 0.2, 0.8) if fel == "sludge" else Color(0.5, 0.38, 0.25, 0.9)
			"dust":
				pc = Color(0.74, 0.62, 0.46, 0.4)
				po["swirl"] = 3.0 if vfx == "dust_bowl" else 0.0
				po["ring"] = vfx == "dust_bowl"
			"wind":
				pc = Color(0.42, 0.78, 0.8, 0.5)
				po["swirl"] = 9.0
			"steam":
				pc = Color(0.95, 0.95, 0.97, 0.4)
				po["amount"] = 0.8
		gp = stream(pt, pc, FxKit.el_hot(fel) if fel != "" else null, po)
		gp.reparent(root)
		gp.position = Vector3.ZERO
	# a small tornado for gale vortices (Gusto's JUICE dodges), a slow turning dust wall for Dust Bowl
	var extra: MeshInstance3D = null
	if vfx == "gale_vortex":
		extra = MeshInstance3D.new()
		extra.mesh = FxKit.spiral_mesh(2.5, 0.25, 1.0, 0.25)
		extra.material_override = FxKit.flow_material(Color(0.32, 0.74, 0.78, 0.9), Color(1, 1, 1), {"additive": 1.0, "scroll": Vector2(-2.0, 0.0), "noise_scale": Vector2(8.0, 1.0), "edge_v": 0.45, "core": 0.5, "core_width": 0.3, "bands": 3.0, "alpha": 0.9})
		extra.scale = Vector3(r, 1.4, r)
	elif vfx == "dust_bowl":
		extra = MeshInstance3D.new()
		extra.mesh = FxKit.wall_mesh(40, 1.15)
		extra.material_override = FxKit.flow_material(Color(0.72, 0.6, 0.44, 0.75), Color(0.88, 0.8, 0.65), {"additive": 0.0, "scroll": Vector2(-0.35, 0.2), "noise_scale": Vector2(10.0, 2.0), "edge_v": 0.45, "core": 0.3, "core_width": 0.3, "alpha": 0.55})
		extra.scale = Vector3(r, 0.9, r)
	if extra != null:
		extra.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(extra)
	var t0 := _clock
	var en := {"node": root, "kind": "zone", "pos": p}
	en["tick"] = func(_e: Dictionary) -> void:
		var t := _clock - t0
		grow["t"] = t
		mat.set_shader_parameter("progress", clampf(t / 0.25, 0.0, 1.0) * 1.02)
		if extra != null and is_instance_valid(extra):
			extra.rotation.y = -t * (6.0 if vfx == "gale_vortex" else 1.2)
	en["end"] = func() -> void:
		if gp != null and is_instance_valid(gp):
			gp.emitting = false
		animate(root, 0.45, func(k: float, _t: float) -> void:
			mat.set_shader_parameter("fade", 1.0 - k)
			if extra != null and is_instance_valid(extra):
				(extra.material_override as ShaderMaterial).set_shader_parameter("dissolve", k))
	return en


func _make_prop(e: Dictionary) -> Dictionary:
	var kind := str(e.get("prop", e.get("vfx", "")))
	var p: Vector3 = e["pos"]
	var root := Node3D.new()
	add_child(root)
	root.global_position = p
	var r := maxf(float(e.get("radius", 1.0)), 0.3)
	var t0 := _clock
	var en := {"node": root, "kind": "prop", "pos": p, "bounce": -9.0}
	if kind == "spring_pad":
		# Jitters' pad: a riveted base, a coil spring, a charged plate that crackles now and then
		var base := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r * 0.62
		cm.bottom_radius = r * 0.7
		cm.height = 0.05
		cm.radial_segments = 24
		base.mesh = cm
		base.material_override = Materials.toon(Color(0.28, 0.3, 0.34), 0.5, 0.6, 0.3)
		base.position = Vector3.UP * 0.025
		root.add_child(base)
		var coil := MeshInstance3D.new()
		coil.mesh = FxKit.spiral_mesh(4.0, 1.0, 1.0, 0.05)
		coil.material_override = Materials.toon(Color(0.75, 0.75, 0.8), 0.3, 0.9, 0.3)
		coil.scale = Vector3(r * 0.4, 0.1, r * 0.4)
		coil.position = Vector3.UP * 0.05
		root.add_child(coil)
		var plate := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = r * 0.55
		pm.bottom_radius = r * 0.55
		pm.height = 0.035
		pm.radial_segments = 24
		plate.mesh = pm
		var plate_mat := Materials.toon(Color(0.95, 0.82, 0.25), 0.4, 0.2, 0.4, Color(0.6, 0.45, 0.05))
		plate.material_override = plate_mat
		plate.position = Vector3.UP * 0.17
		root.add_child(plate)
		var ring := footprint("static", "ring", Vector3.ZERO, 0.0, r, {"inner": r * 0.75, "fill": 0.3, "strength": 0.6}, INF)
		ring.reparent(root)
		ring.position = Vector3.UP * 0.02
		var st := {"next": 0.6}
		# spawn: springs up out of the floor
		root.scale = Vector3(1, 0.01, 1)
		burst("sparks", p + Vector3.UP * 0.2, Vector3.UP, Color(1.0, 0.95, 0.6), null, {"amount": 0.5, "floor": p.y})
		en["tick"] = func(_e: Dictionary) -> void:
			var t := _clock - t0
			var up := clampf(t / 0.18, 0.0, 1.0)
			var b := clampf((_clock - float(en["bounce"])) / 0.35, 0.0, 1.0)
			var squash := 1.0 - 0.55 * sin(b * PI) * (1.0 - b) if b < 1.0 else 1.0
			root.scale = Vector3(1.0, maxf(0.01, (up + 0.25 * sin(up * PI)) * squash), 1.0)
			if t >= float(st["next"]) and quality >= 1:
				st["next"] = t + _rng.randf_range(0.8, 1.6)
				var a := _rng.randf() * TAU
				bolt(root.global_position + Vector3(sin(a) * r * 0.5, 0.2, cos(a) * r * 0.5), root.global_position + Vector3(sin(a + 1.2) * r * 0.45, 0.2, cos(a + 1.2) * r * 0.45), Color(1.0, 0.82, 0.15), 0.1, 0.03, 0.06)
	elif kind in ["boulder", "rubble"]:
		var rock := MeshInstance3D.new()
		rock.mesh = FxKit.piece_mesh("hex")
		rock.material_override = Materials.toon(Color(0.52, 0.42, 0.32), 0.95, 0.0, 0.25)
		var s := r * (2.0 if kind == "boulder" else 1.4)
		rock.scale = Vector3(s, s * (0.9 if kind == "boulder" else 0.45), s)
		rock.position = Vector3.UP * s * 0.35
		root.add_child(rock)
		burst("dust", p, Vector3.UP, Color(0.74, 0.62, 0.46, 0.5), null, {"ring": true, "radius": r, "amount": 0.6})
	else:
		var disc := footprint("", "circle", Vector3.ZERO, 0.0, r, {"fill": 0.3, "color": Color(1.0, 0.85, 0.5)}, INF)
		disc.reparent(root)
		disc.position = Vector3.UP * 0.03
	en["end"] = func() -> void:
		if not is_instance_valid(root):
			return
		burst("dust", root.global_position, Vector3.UP, Color(0.75, 0.7, 0.62, 0.45), null, {"amount": 0.4})
		animate(root, 0.25, func(k: float, _t: float) -> void:
			root.scale = Vector3(1.0 - k * 0.5, maxf(0.01, 1.0 - k), 1.0 - k * 0.5))
	return en


func _make_marker(e: Dictionary) -> Dictionary:
	# a delayed strike's warning: its true circle, crackling and tightening until the strike lands
	var el := str(e.get("element", "static"))
	var r := maxf(float(e.get("radius", 1.5)), 0.3)
	var p: Vector3 = e["pos"]
	var root := Node3D.new()
	add_child(root)
	root.global_position = p
	var fp := footprint(el if el != "" else "static", "ring", Vector3.ZERO, 0.0, r, {"inner": r * 0.82, "fill": 0.5, "front": 0.0}, INF)
	fp.reparent(root)
	fp.position = Vector3.UP * 0.03
	var mat := fp.material_override as ShaderMaterial
	var t0 := _clock
	var en := {"node": root, "kind": "delayed", "pos": p}
	en["tick"] = func(_e: Dictionary) -> void:
		var t := _clock - t0
		mat.set_shader_parameter("fade", 0.6 + 0.4 * sin(t * (10.0 if not reduce_flashes else 4.0)))
	en["end"] = func() -> void:
		if is_instance_valid(root):
			root.queue_free()
	return en
