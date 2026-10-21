extends MoveFxKit
## Varga's Movesets effects (v0.9.18, docs/kits/f_varga.md): a fighting-type aura in gold and white
## that grows out of his v0.9.17 look (crisp gold speed lines, tight shock rings, four-point glints)
## instead of an elemental glow. Every piece is drawn where the simulation fires it, in its true
## footprint:
##   * plain strikes (Movesets): a small aura flare on a clean hit; the teep's pressure cone;
##   * hooks: the Comet Hook's trailing crescent of shockwave, the Spiral Hook's vortex;
##   * straights: the Pressure Palm's gathering aura while it charges, the aura blast it throws and
##     its pop; the Force Palm's point-blank shock disc (and the crack of a guard it caught);
##   * overhands: the Meteor Hammer's falling streak and cracked-floor ring (and its crater);
##     the Thunder Chop's stun spark;
##   * kicks: the Shockwave Roundhouse's wave arc, the flying Crescent Moon wave, the Sweep Quake;
##     the Iron Shins' steel sheen, clang, Axe Kick drop and Leg Breaker crack;
##   * combinations: the Thousand-Fist Flurry's afterimage fists and finale ring, the Iron Counter's
##     iron shell and answer burst, the Afterimage Rush's gold ghosts, the Shockwave Uppercut's ring.
## Budget: particles go through AbilityVfx (Effects quality, crowd thinning); ribbons, ghosts and
## meshes are few and short-lived, and the decorative ones are skipped at Low; lights share the
## AbilityVfx cap; Reduce flashing dims flashes and slows the crackle. View-only: it reads events,
## entities and the views, never the simulation.

const GOLD := Color(1.0, 0.78, 0.32)
const HOT := Color(1.0, 0.95, 0.78)
const WHITE := Color(1.0, 1.0, 0.94)
const DEEP := Color(0.95, 0.55, 0.18)
const STEEL := Color(0.8, 0.86, 0.95)
const STEEL_HOT := Color(1.0, 0.98, 0.92)
const DUST := Color(0.8, 0.72, 0.6, 0.45)
## Varga's strike points: the one nearest an on-hit effect is the limb that just landed
const STRIKE_POINTS := ["lFist", "rFist", "lFoot", "rFoot", "lKnee", "rKnee", "lShin", "rShin"]
const GHOSTS := [2, 4, 6]               ## afterimages per rush, per Effects quality

var _palms := {}        ## fighter -> {fist, def, t, node, mat, level, done}: a Pressure Palm gathering aura
var _fists := {}        ## fighter -> afterimage fists drawn in the running Thousand-Fist Flurry
var _crescent: ArrayMesh = null
var _ghost_mesh: SphereMesh = null


func vfx_names() -> Array:
	return ["varga_aura_flare", "varga_pressure_teep", "varga_comet_arc", "varga_spiral_vortex", "varga_pressure_blast",
		"varga_force_palm_burst", "varga_force_palm_crack", "varga_meteor_crack", "varga_meteor_crater", "varga_thunder_spark",
		"varga_shockwave_arc", "varga_crescent_wave", "varga_sweep_quake", "varga_iron_clang", "varga_axe_drop",
		"varga_leg_breaker", "varga_flurry_start", "varga_flurry_fist", "varga_flurry_finale", "varga_iron_counter",
		"varga_iron_counter_burst", "varga_afterimage_rush", "varga_shockwave_ring"]


func on_effect(fi: int, ev: Dictionary) -> bool:
	var pos: Vector3 = ev.get("pos", fx._ground(fi))
	var r := float(ev.get("radius", 1.0))
	match str(ev.get("vfx", "")):
		"varga_aura_flare":
			_aura_flare(_contact(fi, pos), 1.0)
		"varga_pressure_teep":
			_pressure_teep(fi, _contact(fi, pos))
		"varga_comet_arc":
			_wave_arc(fi, ev, 1.2, GOLD, WHITE, 0.24, true)
		"varga_spiral_vortex":
			_spiral(fi, pos, r)
		"varga_pressure_blast":
			_palm_release(fi, ev)
		"varga_force_palm_burst":
			_force_burst(fi, _contact(fi, pos))
		"varga_force_palm_crack":
			_guard_crack(fi, _contact(fi, pos))
		"varga_meteor_crack":
			_meteor(fi, pos, r)
		"varga_meteor_crater":
			pass        # the crack drew the moment; the broken floor itself is the zone's entity
		"varga_thunder_spark":
			_thunder(_contact(fi, pos))
		"varga_shockwave_arc":
			_wave_arc(fi, ev, 1.0, GOLD, HOT, 0.3, false)
		"varga_crescent_wave":
			_crescent_launch(fi, ev)
		"varga_sweep_quake":
			_quake(fi, pos, r)
		"varga_iron_clang":
			_clang(_contact(fi, pos))
		"varga_axe_drop":
			_axe_drop(fi, _contact(fi, pos))
		"varga_leg_breaker":
			_leg_breaker(_contact(fi, pos))
		"varga_flurry_start":
			_flurry_start(fi)
		"varga_flurry_fist":
			_flurry_fist(fi)
		"varga_flurry_finale":
			_flurry_finale(fi, _contact(fi, pos))
		"varga_iron_counter":
			_iron_shell(fi)
		"varga_iron_counter_burst":
			_iron_answer(fi, pos)
		"varga_afterimage_rush":
			_rush(fi, ev)
		"varga_shockwave_ring":
			_shockwave_ring(fi, pos, r)
		_:
			return false
	return true


func on_move_start(fi: int, ev: Dictionary) -> bool:
	var m := fx._move_def(fi, str(ev.get("id", "")))
	var weapon := _weapon(m)
	var lead := m.first_active() if m != null else 0.15
	match str(ev.get("pool", "")):
		"pressure_palm":
			_palm_begin(fi, m, weapon)
		"comet_hook":
			_limb_trail(fi, weapon, lead + 0.22, GOLD, WHITE, 0.07)
		"spiral_hook":
			_limb_trail(fi, weapon, lead + 0.2, DEEP, HOT, 0.06)
		"force_palm":
			fx._glow_at(fi, weapon, Vector3.ZERO, lead, lead + 0.05, HOT, 0.24, true)
		"meteor_hammer":
			fx._glow_at(fi, weapon, Vector3.ZERO, lead, lead + 0.05, DEEP, 0.3, true)
			_limb_trail(fi, weapon, lead + 0.18, DEEP, HOT, 0.08)
		"thunder_chop":
			_crackle(fi, weapon, lead)
			_limb_trail(fi, weapon, lead + 0.15, HOT, WHITE, 0.05)
		"shockwave_kicks":
			_limb_trail(fi, weapon, lead + 0.25, GOLD, WHITE, 0.08)
		"iron_shins":
			_limb_trail(fi, weapon, lead + 0.25, STEEL, STEEL_HOT, 0.09)
			fx.burst("glints", fx.anchor(fi, weapon), Vector3.UP, STEEL_HOT, STEEL, {"amount": 0.35, "speed": 0.4})
	return false        # the v0.9.17 move-start handling (it has nothing for limb strikes) still runs


func on_hit(fi: int, ev: Dictionary) -> void:
	if bool(ev.get("blocked", false)) or bool(ev.get("parried", false)):
		return
	var p: Vector3 = ev.get("point", fx._ground(fi) + Vector3.UP)
	var s := clampf(float(ev.get("damage", 0.0)) / 12.0, 0.25, 1.0)
	if str(ev.get("pool", "")) == "pressure_palm" and str(ev.get("slot", "")) == "effect":
		# the blast landing: the aura breaks over him in a white-gold ring
		fx.ring_wall(p, 0.1, 0.5 + 0.5 * s, 0.25, GOLD, WHITE, 0.22, {"bands": 0.0, "core": 0.5})
		fx.burst("glints", p, Vector3.UP, HOT, WHITE, {"amount": 0.5 + 0.5 * s, "speed": 1.0 + s, "scale": 1.0 + s})
		fx.flash_light(p, GOLD, 2.0 + 2.0 * s, 3.0, 0.22)
	else:
		# a technique strike landing: a few gold motes burst out of the impact
		fx.burst("motes", p, Vector3.UP, GOLD, WHITE, {"amount": 0.25 + 0.3 * s, "speed": 1.2, "spread": 1.2})


func make_entity(e: Dictionary) -> Dictionary:
	match str(e.get("vfx", "")):
		"varga_pressure_blast":
			return _blast(e)
		"varga_crescent_wave":
			return _crescent_wave(e)
		"varga_meteor_crater":
			return _crater(e)
	return {}


func process(delta: float) -> void:
	for fi in _palms.keys():
		_palm_tick(int(fi), delta)


# =====================================================================================================
# Shared pieces
# =====================================================================================================

## The weapon a move strikes with (its first hit window's first weapon), or "core".
func _weapon(m: MoveDef) -> String:
	if m != null and not m.windows.is_empty():
		var ws := PackedStringArray((m.windows[0] as Dictionary).get("weapons", PackedStringArray()))
		if ws.size() > 0:
			return ws[0]
	return "core"


## Where an on-hit effect really happened: the event carries the floor under the contact, so the
## strike point (fist, foot, knee or shin) of Varga's nearest the event is the limb that landed.
func _contact(fi: int, pos: Vector3) -> Vector3:
	var best := pos + Vector3.UP * 1.0
	var best_d := INF
	for w in STRIKE_POINTS:
		var p := fx.anchor(fi, str(w))
		var d := Vector2(p.x - pos.x, p.z - pos.z).length()
		if d < best_d:
			best_d = d
			best = p
	return best


## A ring wall standing upright and facing `dir` (a shock disc in front of a palm or a fist).
func _disc(p: Vector3, dir: Vector3, r0: float, r1: float, depth: float, ca: Color, cb: Color, dur: float) -> void:
	var mi := fx.ring_wall(p, r0, r1, depth, ca, cb, dur, {"bands": 0.0, "core": 0.5, "expand": 0.4})
	var d := dir.normalized() if dir.length_squared() > 1e-6 else Vector3.FORWARD
	var x := d.cross(Vector3.UP).normalized() if absf(d.y) < 0.95 else Vector3.RIGHT
	var z := x.cross(d).normalized()
	var turn := Basis(x, d, z)
	# ring_wall scales its mesh every frame (radius, depth); keep that scale and turn the ring so its
	# axis (the mesh's Y) points along the strike, centred on the point
	var holder := Node3D.new()
	fx.add_child(holder)
	holder.global_position = p - d * depth * 0.5
	holder.global_basis = turn
	mi.reparent(holder, false)
	mi.position = Vector3.ZERO
	fx.animate(holder, dur + 0.05, func(_k: float, _t: float) -> void:
		pass)


## A gold aura flare where a strike lands (plain strikes in Movesets, technique extras).
func _aura_flare(p: Vector3, s: float) -> void:
	fx.burst("glints", p, Vector3.UP, HOT, WHITE, {"amount": 0.5 * s, "speed": 0.8, "scale": 1.1 * s})
	fx.burst("motes", p, Vector3.UP, GOLD, HOT, {"amount": 0.3 * s, "speed": 1.4, "spread": 1.4})
	if fx.quality >= 1:
		fx.ring_wall(p - Vector3.UP * 0.08, 0.05, 0.38 * s, 0.16, GOLD, WHITE, 0.16, {"bands": 0.0, "core": 0.5, "expand": 0.5})


## A ribbon that follows one of Varga's strike points for `dur` seconds: the limb's aura trail.
func _limb_trail(fi: int, weapon: String, dur: float, ca: Color, cb: Color, width: float) -> void:
	if fx.quality <= 0:
		return
	var rib := fx.ribbon(ca, cb, true)
	var hist: Array = []
	fx.animate(rib, dur + 0.15, func(k: float, t: float) -> void:
		if t <= dur:
			hist.append(fx.anchor(fi, weapon))
		if hist.size() > 9:
			hist.pop_front()
		var w: Array = []
		var al: Array = []
		var n := hist.size()
		for i in n:
			var u := float(i) / maxf(1.0, float(n - 1))
			w.append(width * (0.25 + 0.75 * u))
			al.append(0.85 * u * (1.0 - smoothstep(0.55, 1.0, k)))
		fx.draw_ribbon(rib, hist, w, al))


## Short white-gold bolts crackling around a fist through a wind-up (fewer, slower when flashes are reduced).
func _crackle(fi: int, weapon: String, lead: float) -> void:
	if fx.quality <= 0:
		return
	var n := clampi(int(lead / (0.12 if fx.reduce_flashes else 0.06)), 1, 5)
	for k in n:
		fx._later(lead * float(k) / float(n), func() -> void:
			var c := fx.anchor(fi, weapon)
			var d := Vector3(fx._rng.randf_range(-1, 1), fx._rng.randf_range(-0.6, 1), fx._rng.randf_range(-1, 1)).normalized()
			fx.bolt(c, c + d * 0.22, HOT, 0.07, 0.03, 0.05))


# =====================================================================================================
# Plain strikes and hooks
# =====================================================================================================

func _pressure_teep(fi: int, p: Vector3) -> void:
	# the push kick's pressure wave rolls on through him in a short cone
	var fwd := aim_dir(fi)
	fx.jet(p - fwd * 0.15, fwd, 1.3, 0.5, Color(GOLD, 0.8), WHITE, 0.3, {"cover": 0.45, "glow_k": 1.0, "flat": 0.7})
	fx.burst("glints", p, fwd, HOT, WHITE, {"amount": 0.4, "speed": 1.5, "spread": 0.5})
	fx.burst("dust", Vector3(p.x, fx._ground(fi).y, p.z), fwd + Vector3.UP * 0.2, DUST, null, {"amount": 0.3, "speed": 0.8})


## A crescent of shockwave sweeping across a cone area at `height` (Comet Hook, Shockwave Roundhouse):
## it starts at the striking limb's side and sweeps across in the direction of the swing while it
## grows to the area's radius; a second, fainter crescent trails it. The floor shows the true cone.
func _wave_arc(fi: int, ev: Dictionary, height: float, ca: Color, cb: Color, dur: float, comet: bool) -> void:
	var origin: Vector3 = ev.get("origin", ev.get("pos", fx._ground(fi)))
	var yaw := float(ev.get("yaw", fx._yaw(fi)))
	var r := float(ev.get("radius", 2.3))
	var cone := float(ev.get("cone_deg", 110.0))
	var m := fx._move_def(fi, str(ev.get("move", "")))
	var w := _weapon(m)
	var from_left := w.begins_with("l")     # a left limb swings from his left (+X) across to his right
	fx.footprint("scrap", "cone", origin, yaw, r, {"cone_deg": cone, "fill": 0.4, "front": 1.0,
		"color": DEEP, "color2": HOT}, 0.5, dur * 0.6)
	var half := deg_to_rad(cone) * 0.5
	var layers := 2 if fx.quality >= 1 else 1
	for layer in layers:
		var rib := fx.ribbon(ca, cb, true)
		var lag := 0.05 * float(layer)
		var h := height - 0.22 * float(layer)
		fx.animate(rib, dur + 0.12 + lag, func(k: float, t: float) -> void:
			var g := clampf((t - lag) / dur, 0.0, 1.0)
			g = 1.0 - (1.0 - g) * (1.0 - g)
			var rad := lerpf(0.5, r, g)
			var head := lerpf(-1.0, 1.0, g)
			var pts: Array = []
			var wid: Array = []
			var al: Array = []
			for i in 13:
				var u := float(i) / 12.0
				var s := lerpf(-1.0, head, u)
				var a := half * (-s if from_left else s)
				pts.append(origin + Vector3(sin(yaw + a), 0.0, cos(yaw + a)) * rad + Vector3.UP * h)
				var taper := sin(u * PI * 0.5 + 0.0001)
				wid.append((0.16 if comet else 0.22) * taper * (1.0 - 0.4 * float(layer)))
				al.append(taper * (1.0 - smoothstep(0.6, 1.0, k)) * (0.9 - 0.35 * float(layer)))
			fx.draw_ribbon(rib, pts, wid, al))
	var tip_a := half * (-1.0 if from_left else 1.0)
	var tip := origin + Vector3(sin(yaw + tip_a), 0.0, cos(yaw + tip_a)) * r + Vector3.UP * height
	fx.burst("glints", tip, Vector3.UP, HOT, WHITE, {"amount": 0.4, "speed": 0.8})
	if not comet:
		fx.burst("dust", origin + MathX.forward_of_yaw(yaw) * r * 0.6, Vector3.UP, DUST, null, {"amount": 0.4, "speed": 0.9, "radius": r * 0.4})


func _spiral(fi: int, pos: Vector3, r: float) -> void:
	# a spinning gold vortex at the fist that draws everything near it inward
	var p := Vector3(pos.x, fx._ground(fi).y, pos.z)
	fx.vortex(p + Vector3.UP * 0.5, minf(r, 1.2) * 0.75, 1.2, Color(DEEP, 0.85), HOT, 0.4, {"add": true, "spin": 14.0, "turns": 2.2, "r0": 0.15})
	fx._converge_point(p + Vector3.UP * 1.1, 0.3, GOLD, WHITE, 0.6, "motes")
	fx.footprint("scrap", "circle", p, 0.0, r, {"fill": 0.3, "front": 1.0, "color": DEEP, "color2": HOT}, 0.45, 0.2)


# =====================================================================================================
# Pressure Palm (the gathering aura, the blast, its pop) and Force Palm
# =====================================================================================================

func _palm_begin(fi: int, m: MoveDef, fist: String) -> void:
	_palm_end(fi, false)
	if m == null or m.charge_time <= 0.0:
		return
	_palms[fi] = {"fist": fist, "def": m, "t": 0.0, "node": null, "mat": null, "level": 0.0, "pulse": 0.0}


func _palm_tick(fi: int, delta: float) -> void:
	var p: Dictionary = _palms[fi]
	var m: MoveDef = p["def"]
	p["t"] = float(p["t"]) + delta
	var t := float(p["t"])
	var inf := fx._info(fi)
	var level := float(inf.get("charge", -2.0))
	var st := int(inf.get("state", Fighter.State.ATTACK))
	var start := m.charge_start()
	var lv := float(p["level"])
	if level >= 0.0:
		lv = level                                    # local: the real charge
	elif level == -2.0:
		lv = clampf((t - start) / maxf(m.charge_time, 0.05), 0.0, 1.0)   # online, while held: by time
	var let_go := level == -1.0 and t > start + 0.05
	var alive := not inf.is_empty() and not bool(inf.get("out", false)) and fx._view(fi) != null
	if not alive or st != Fighter.State.ATTACK or let_go or t > start + m.charge_time + 0.4:
		_palm_end(fi, lv > 0.08)
		return
	p["level"] = lv
	if lv <= 0.02:
		return
	if p["node"] == null:
		var mi := MeshInstance3D.new()
		mi.mesh = fx._sphere(0.5, 14)
		var mat := FxKit.flow_material(GOLD, WHITE, {"additive": 1.0, "fresnel": 1.3, "scroll": Vector2(0.6, -1.4),
			"noise_scale": Vector2(5.0, 3.0), "edge_v": 0.0, "core": 0.5, "core_width": 0.6, "alpha": 0.0})
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fx.add_child(mi)
		p["node"] = mi
		p["mat"] = mat
	var node = p["node"]
	if is_instance_valid(node):
		var ball := node as MeshInstance3D
		var wob := 1.0 + 0.06 * sin(t * 23.0)
		ball.global_position = fx.anchor(fi, str(p["fist"]))
		ball.scale = Vector3.ONE * (0.16 + 0.3 * lv) * wob
		(p["mat"] as ShaderMaterial).set_shader_parameter("alpha", (0.55 + 0.45 * lv) * (0.8 if fx.reduce_flashes else 1.0))
	# aura gathers into the palm, faster the fuller it gets; a faint aura ring breathes at his feet
	p["pulse"] = float(p["pulse"]) - delta
	if float(p["pulse"]) <= 0.0:
		p["pulse"] = lerpf(0.2, 0.1, lv)
		fx._converge(fi, str(p["fist"]), Vector3.ZERO, 0.22, GOLD, WHITE, 0.15 + 0.25 * lv)
		if fx.quality >= 1 and lv > 0.3:
			fx.ring_wall(fx._ground(fi) + Vector3.UP * 0.03, 0.75, 0.45, 0.3 * lv, Color(GOLD, 0.7), HOT, 0.25, {"bands": 6.0})


func _palm_end(fi: int, flash: bool) -> void:
	if not _palms.has(fi):
		return
	var p: Dictionary = _palms[fi]
	_palms.erase(fi)
	var node = p.get("node")
	if node != null and is_instance_valid(node):
		(node as Node).queue_free()
	if flash:
		var c := fx.anchor(fi, str(p["fist"]))
		fx.burst("glints", c, aim_dir(fi), HOT, WHITE, {"amount": 0.6, "speed": 1.2})


## The blast leaves the palm: a shock disc at the palm, a flash, the aura trail is the entity.
func _palm_release(fi: int, ev: Dictionary) -> void:
	var m := fx._move_def(fi, str(ev.get("move", "")))
	var fist := _weapon(m)
	_palm_end(fi, false)
	var c := fx.anchor(fi, fist)
	var lv := clampf((float(ev.get("radius", 0.24)) / 0.24 - 1.0), 0.0, 1.0)   # the charge shows in its size
	_disc(c, aim_dir(fi), 0.08, 0.35 + 0.35 * lv, 0.2, GOLD, WHITE, 0.2)
	fx.burst("glints", c, aim_dir(fi), HOT, WHITE, {"amount": 0.5 + 0.4 * lv, "speed": 1.5, "spread": 0.6})
	fx.flash_light(c, GOLD, 2.0 + 2.0 * lv, 3.0, 0.2)


func _blast(e: Dictionary) -> Dictionary:
	var r := maxf(float(e.get("radius", 0.24)), 0.1)
	var root := Node3D.new()
	fx.add_child(root)
	root.global_position = e["pos"]
	var core := MeshInstance3D.new()
	core.mesh = fx._sphere(r * 0.6, 12)
	core.material_override = FxKit.flow_material(HOT, WHITE, {"additive": 1.0, "fresnel": 0.6, "scroll": Vector2(1.0, -2.0),
		"noise_scale": Vector2(4.0, 3.0), "edge_v": 0.0, "core": 0.5, "core_width": 0.7, "alpha": 1.0})
	root.add_child(core)
	var shell := MeshInstance3D.new()
	shell.mesh = fx._sphere(r * 1.05, 14)
	shell.material_override = FxKit.flow_material(GOLD, HOT, {"additive": 1.0, "fresnel": 1.8, "scroll": Vector2(0.0, -3.0),
		"noise_scale": Vector2(6.0, 3.0), "edge_v": 0.0, "core": 0.5, "core_width": 0.5, "alpha": 0.85})
	root.add_child(shell)
	# two thin bands spin around the ball: the palm's pressure still turning in it
	var bands: Array = []
	if fx.quality >= 1:
		for k in 2:
			var band := MeshInstance3D.new()
			band.mesh = FxKit.wall_mesh(32, 1.0)
			band.material_override = FxKit.flow_material(GOLD, WHITE, {"additive": 1.0, "scroll": Vector2(2.5, 0.0), "noise_scale": Vector2(8.0, 1.0),
				"edge_v": 0.5, "core": 0.5, "core_width": 0.3, "bands": 3.0, "alpha": 0.8})
			band.scale = Vector3(r * 1.35, r * 0.18, r * 1.35)
			band.rotation = Vector3(PI * 0.5 * float(k) + 0.4, 0.0, 0.3)
			root.add_child(band)
			bands.append(band)
	for n in root.get_children():
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var trail := fx._attached_stream(root, "motes", GOLD, WHITE, {"speed": 0.2, "amount": 0.7, "radius": r * 0.5})
	var glints := fx._attached_stream(root, "glints", HOT, null, {"speed": 0.3, "amount": 0.35})
	var light: OmniLight3D = null
	if fx.quality >= 1:
		light = OmniLight3D.new()
		light.light_color = GOLD
		light.light_energy = 1.4 * (0.6 if fx.reduce_flashes else 1.0)
		light.omni_range = 1.5 + r * 3.0
		light.shadow_enabled = false
		root.add_child(light)
	var state := {"t": 0.0, "pos": e["pos"]}
	return {"node": root, "kind": "projectile", "pos": e["pos"], "dir": Vector3.FORWARD,
		"tick": func(e2: Dictionary) -> void:
			state["t"] = float(state["t"]) + 1.0 / 60.0
			state["pos"] = e2["pos"]
			var tt := float(state["t"])
			if is_instance_valid(shell):
				shell.scale = Vector3.ONE * (1.0 + 0.08 * sin(tt * 31.0))
			for i in bands.size():
				var b: MeshInstance3D = bands[i]
				if is_instance_valid(b):
					b.rotation.y = tt * (9.0 if i == 0 else -7.0),
		"end": func() -> void:
			var at: Vector3 = state["pos"]
			for s in [trail, glints]:
				if s != null and is_instance_valid(s):
					var gpos: Vector3 = (s as GPUParticles3D).global_position
					(s as GPUParticles3D).reparent(fx)
					(s as GPUParticles3D).global_position = gpos
					fx.end_stream(s)
			# it pops where it ends (on a fighter, the fence, the floor, or out of range)
			fx.ring_wall(at, 0.1, r * 2.2, r * 1.2, GOLD, WHITE, 0.2, {"bands": 0.0, "core": 0.5})
			fx.burst("glints", at, Vector3.UP, HOT, WHITE, {"amount": 0.4, "speed": 0.9})
			if is_instance_valid(root):
				root.queue_free()}


func _force_burst(fi: int, p: Vector3) -> void:
	# point blank: the palm's pressure goes off in a white shock disc and blows straight through him
	var fwd := aim_dir(fi)
	_disc(p, fwd, 0.08, 0.85, 0.3, WHITE, HOT, 0.2)
	fx.jet(p - fwd * 0.1, fwd, 1.5, 0.55, Color(GOLD, 0.85), WHITE, 0.28, {"cover": 0.5, "glow_k": 1.2, "flat": 1.0})
	fx.burst("sparks", p, fwd, HOT, WHITE, {"amount": 0.7, "speed": 1.4, "spread": 0.5})
	fx.burst("glints", p, fwd, WHITE, HOT, {"amount": 0.6, "speed": 1.2, "scale": 1.4})
	fx.flash_light(p, HOT, 3.5, 3.5, 0.2)


func _guard_crack(fi: int, p: Vector3) -> void:
	# the palm caught a guard: it cracks like a plate (shards and a broken ring)
	fx.burst("shards", p, aim_dir(fi) + Vector3.UP * 0.3, Color(1.0, 0.85, 0.55), null, {"amount": 0.6, "speed": 0.9, "floor": fx._ground(fi).y})
	_disc(p, aim_dir(fi), 0.1, 0.55, 0.12, DEEP, HOT, 0.16)
	fx.burst("sparks", p, Vector3.UP, HOT, null, {"amount": 0.4})


# =====================================================================================================
# Overhands
# =====================================================================================================

func _meteor(fi: int, pos: Vector3, r: float) -> void:
	var g := Vector3(pos.x, fx._ground(fi).y, pos.z)
	# the fist comes down as a falling star, and the floor cracks in its ring
	if fx.quality >= 1:
		var rib := fx.ribbon(DEEP, WHITE, true)
		var top := g + Vector3.UP * 2.3 - aim_dir(fi) * 0.4
		fx.animate(rib, 0.22, func(k: float, _t: float) -> void:
			var head := clampf(k / 0.45, 0.0, 1.0)
			var a := top.lerp(g + Vector3.UP * 0.2, maxf(0.0, head - 0.35))
			var b := top.lerp(g + Vector3.UP * 0.2, head)
			fx.draw_ribbon(rib, [a, a.lerp(b, 0.5), b], [0.02, 0.12, 0.2], [0.0, 0.8 * (1.0 - k), 1.0 - k]))
	fx.footprint("scrap", "circle", g, 0.0, r, {"fill": 0.6, "front": 1.0, "color": DEEP, "color2": HOT}, 0.9, 0.08)
	fx.ring_wall(g + Vector3.UP * 0.03, 0.2, r, 0.4, GOLD, HOT, 0.3, {"bands": 0.0, "core": 0.6, "expand": 0.35})
	fx.burst("chunks", g + Vector3.UP * 0.05, Vector3.UP, Color(0.55, 0.47, 0.38), Color(0.78, 0.66, 0.5), {"amount": 0.45, "speed": 0.9, "floor": g.y})
	fx.burst("dust", g, Vector3.UP, DUST, null, {"ring": true, "radius": r * 0.7, "amount": 0.7, "speed": 0.8})
	fx.burst("glints", g + Vector3.UP * 0.3, Vector3.UP, HOT, WHITE, {"amount": 0.6, "speed": 1.0, "scale": 1.3})
	fx.flash_light(g + Vector3.UP * 0.4, GOLD, 3.0, 4.0, 0.25)


func _crater(e: Dictionary) -> Dictionary:
	# Crater style: broken floor that keeps glowing faintly for as long as it slows
	var r := float(e.get("radius", 1.4))
	var p: Vector3 = e["pos"]
	var root := Node3D.new()
	fx.add_child(root)
	root.global_position = Vector3(p.x, 0.0, p.z)
	var floor_mi := fx.footprint("scrap", "circle", root.global_position, 0.0, r, {"fill": 0.5, "strength": 0.75, "color": DEEP, "color2": HOT}, INF)
	var motes := fx._attached_stream(root, "motes", GOLD, null, {"ring": true, "radius": r * 0.7, "speed": 0.2, "amount": 0.25})
	return {"node": root, "kind": "zone", "pos": p,
		"end": func() -> void:
			if motes != null and is_instance_valid(motes):
				fx.end_stream(motes)
			if is_instance_valid(floor_mi):
				var fmat := floor_mi.material_override as ShaderMaterial
				fx.animate(floor_mi, 0.3, func(k: float, _t: float) -> void:
					fmat.set_shader_parameter("fade", 0.75 * (1.0 - k)))
			if is_instance_valid(root):
				root.queue_free()}


func _thunder(p: Vector3) -> void:
	# the stun spark: a crown of short white-gold forks snapping off the impact
	var n := 2 if fx.reduce_flashes else 4
	for k in n:
		var a := TAU * float(k) / float(n) + fx._rng.randf_range(-0.4, 0.4)
		var d := Vector3(cos(a), fx._rng.randf_range(-0.3, 0.8), sin(a)).normalized()
		fx.bolt(p, p + d * fx._rng.randf_range(0.3, 0.5), HOT, 0.14, 0.04, 0.12)
	fx.burst("sparks", p, Vector3.UP, HOT, WHITE, {"amount": 0.6, "speed": 1.2})
	fx.flash_light(p, WHITE, 2.0, 2.5, 0.12)


# =====================================================================================================
# Kicks
# =====================================================================================================

## The kick's own flash as the crescent leaves the foot (the wave itself is the entity).
func _crescent_launch(fi: int, ev: Dictionary) -> void:
	var m := fx._move_def(fi, str(ev.get("move", "")))
	var foot := fx.anchor(fi, _foot(m))
	fx.burst("glints", foot, aim_dir(fi), HOT, WHITE, {"amount": 0.5, "speed": 1.4, "spread": 0.7})
	fx.flash_light(foot, GOLD, 1.8, 2.5, 0.16)


func _foot(m: MoveDef) -> String:
	if m != null and not m.windows.is_empty():
		for w in (m.windows[0] as Dictionary).get("weapons", PackedStringArray()):
			if str(w).ends_with("Foot"):
				return str(w)
	return _weapon(m)


## A flat crescent band (convex edge toward local -Z, the way the wave flies), width 1 at its
## middle tapering to points, spanning 1 unit either side.
func _crescent_mesh() -> ArrayMesh:
	if _crescent != null:
		return _crescent
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 20
	var prev_o := Vector3.ZERO
	var prev_i := Vector3.ZERO
	for i in steps + 1:
		var u := float(i) / float(steps)
		var th := lerpf(-1.25, 1.25, u)
		var outer := Vector3(sin(th), 0.0, -cos(th) + 1.0)
		var thick := 0.42 * sin(u * PI)
		var inner := Vector3(sin(th) * (1.0 - thick), 0.0, (-cos(th) + 1.0) * (1.0 - thick) + thick)
		if i > 0:
			var u0 := float(i - 1) / float(steps)
			for v in [[prev_o, Vector2(u0, 0)], [inner, Vector2(u, 1)], [prev_i, Vector2(u0, 1)], [prev_o, Vector2(u0, 0)], [outer, Vector2(u, 0)], [inner, Vector2(u, 1)]]:
				st.set_uv(v[1])
				st.add_vertex(v[0])
		prev_o = outer
		prev_i = inner
	st.generate_normals()
	_crescent = st.commit()
	return _crescent


func _crescent_wave(e: Dictionary) -> Dictionary:
	var r := maxf(float(e.get("radius", 0.42)), 0.15)
	var root := Node3D.new()
	fx.add_child(root)
	root.global_position = e["pos"]
	var tilt := Node3D.new()            # the kick's slant: the crescent flies tilted along its arc
	tilt.rotation = Vector3(0.0, 0.0, 0.45)
	root.add_child(tilt)
	var body := MeshInstance3D.new()
	body.mesh = _crescent_mesh()
	body.material_override = FxKit.flow_material(GOLD, WHITE, {"additive": 1.0, "scroll": Vector2(-3.0, 0.0), "noise_scale": Vector2(6.0, 1.5),
		"edge_v": 0.3, "edge_u": 0.15, "core": 0.25, "core_width": 0.3, "alpha": 0.95})
	body.scale = Vector3(r * 1.3, 1.0, r * 1.0)
	tilt.add_child(body)
	var edge := MeshInstance3D.new()
	edge.mesh = _crescent_mesh()
	edge.material_override = FxKit.flow_material(HOT, WHITE, {"additive": 1.0, "scroll": Vector2(-4.0, 0.0), "noise_scale": Vector2(4.0, 1.0),
		"edge_v": 0.4, "edge_u": 0.2, "core": 0.2, "core_width": 0.25, "alpha": 0.9})
	edge.scale = Vector3(r * 1.1, 1.0, r * 0.6)
	edge.position = Vector3(0, 0, -r * 0.1)
	tilt.add_child(edge)
	for n in [body, edge]:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var wake := fx._attached_stream(root, "glints", HOT, null, {"speed": 0.2, "amount": 0.4, "radius": r})
	var state := {"t": 0.0}
	return {"node": root, "kind": "projectile", "pos": e["pos"], "dir": Vector3.FORWARD,
		"tick": func(_e2: Dictionary) -> void:
			state["t"] = float(state["t"]) + 1.0 / 60.0
			if is_instance_valid(body):
				body.scale = Vector3(r * 1.3 * (1.0 + 0.05 * sin(float(state["t"]) * 27.0)), 1.0, r * 1.0),
		"end": func() -> void:
			if wake != null and is_instance_valid(wake):
				var gpos := wake.global_position
				wake.reparent(fx)
				wake.global_position = gpos
				fx.end_stream(wake)
			if is_instance_valid(root):
				var pos: Vector3 = root.global_position
				fx.burst("glints", pos, Vector3.UP, HOT, WHITE, {"amount": 0.35, "speed": 0.8})
				root.queue_free()}


func _quake(fi: int, pos: Vector3, r: float) -> void:
	var g := Vector3(pos.x, fx._ground(fi).y, pos.z)
	# the floor bucks where the low kick lands: a low quake ring, grit thrown up, a crack under it
	fx.footprint("scrap", "circle", g, 0.0, r, {"fill": 0.55, "front": 1.0, "color": DEEP, "color2": HOT}, 0.7, 0.1)
	fx.ring_wall(g + Vector3.UP * 0.02, 0.15, r, 0.28, DEEP, HOT, 0.26, {"bands": 0.0, "core": 0.7, "expand": 0.3, "lean": 0.85})
	fx.burst("pebbles", g + Vector3.UP * 0.05, Vector3.UP, Color(0.55, 0.47, 0.38), Color(0.78, 0.66, 0.5), {"ring": true, "radius": r * 0.6, "amount": 0.6, "speed": 0.9, "floor": g.y})
	fx.burst("dust", g, Vector3.UP, DUST, null, {"ring": true, "radius": r * 0.8, "amount": 0.6, "speed": 0.6})
	fx.flash_light(g + Vector3.UP * 0.3, DEEP, 2.0, 3.0, 0.2)


func _clang(p: Vector3) -> void:
	# iron on bone: steel sparks and a hard white ring
	fx.burst("sparks", p, Vector3.UP, STEEL_HOT, Color(1.0, 0.75, 0.4), {"amount": 0.8, "speed": 1.3})
	fx.burst("glints", p, Vector3.UP, STEEL_HOT, STEEL, {"amount": 0.5, "speed": 0.8, "scale": 1.2})
	if fx.quality >= 1:
		fx.ring_wall(p - Vector3.UP * 0.1, 0.05, 0.5, 0.2, STEEL, STEEL_HOT, 0.16, {"bands": 0.0, "core": 0.5})


func _axe_drop(fi: int, p: Vector3) -> void:
	# the heel comes down like an axe: a falling steel crescent, then the floor takes it
	var g := Vector3(p.x, fx._ground(fi).y, p.z)
	if fx.quality >= 1:
		var rib := fx.ribbon(STEEL, STEEL_HOT, true)
		var side := aim_dir(fi).cross(Vector3.UP).normalized()
		fx.animate(rib, 0.2, func(k: float, _t: float) -> void:
			var pts: Array = []
			var w: Array = []
			var al: Array = []
			for i in 9:
				var u := float(i) / 8.0
				var a := lerpf(-0.9, 0.9, u)
				pts.append(p + Vector3.UP * (0.35 * cos(a) - 0.6 * k) + side * 0.35 * sin(a))
				w.append(0.1 * sin(u * PI))
				al.append((1.0 - k) * sin(u * PI))
			fx.draw_ribbon(rib, pts, w, al))
	_clang(p)
	fx.footprint("scrap", "circle", g, 0.0, 0.7, {"fill": 0.5, "front": 1.0, "color": STEEL, "color2": STEEL_HOT}, 0.55, 0.06)
	fx.burst("dust", g, Vector3.UP, DUST, null, {"ring": true, "radius": 0.4, "amount": 0.5, "speed": 0.7})


func _leg_breaker(p: Vector3) -> void:
	# a cracked shin: shards and a deep gold crack ring at knee height
	fx.burst("shards", p, Vector3.UP, Color(1.0, 0.8, 0.5), null, {"amount": 0.5, "speed": 0.8})
	fx.burst("sparks", p, Vector3.UP, DEEP, HOT, {"amount": 0.5})
	fx.ring_wall(p - Vector3.UP * 0.05, 0.05, 0.45, 0.12, DEEP, HOT, 0.2, {"bands": 5.0, "core": 0.5})


# =====================================================================================================
# Combinations
# =====================================================================================================

func _flurry_start(fi: int) -> void:
	_fists[fi] = 0
	var g := fx._ground(fi)
	# his aura flares up all at once: a ring at his feet and gold rising off him for the barrage
	fx.ring_wall(g + Vector3.UP * 0.03, 0.3, 1.0, 0.5, GOLD, HOT, 0.35, {"bands": 8.0, "scroll": Vector2(0.8, -2.0)})
	fx._stream_at(fi, "core", Vector3.ZERO, 0.55, "motes", GOLD, HOT, {"dir": Vector3.UP, "speed": 0.9, "amount": 0.7, "radius": 0.35})
	fx.flash_light(fx.anchor(fi, "core"), GOLD, 2.0, 3.0, 0.4)


func _flurry_fist(fi: int) -> void:
	var n := int(_fists.get(fi, 0))
	_fists[fi] = n + 1
	# afterimage fists: each beat throws one or more gold fists from alternating shoulders
	var count := 1 + mini(fx.quality, 2)
	for k in count:
		var side := 1.0 if (n + k) % 2 == 0 else -1.0
		var from := fx.fpoint(fi, Vector3(0.22 * side, 1.38 + fx._rng.randf_range(-0.05, 0.05), 0.15))
		var to := fx.fpoint(fi, Vector3(fx._rng.randf_range(-0.22, 0.22), fx._rng.randf_range(1.15, 1.55), 0.9))
		if fx.quality >= 1:
			var rib := fx.ribbon(GOLD, WHITE, true)
			fx.animate(rib, 0.12, func(kk: float, _t: float) -> void:
				var head := clampf(kk / 0.5, 0.0, 1.0)
				var a := from.lerp(to, maxf(0.0, head - 0.55))
				var b := from.lerp(to, head)
				fx.draw_ribbon(rib, [a, a.lerp(b, 0.6), b], [0.03, 0.09, 0.14], [0.0, 0.85 * (1.0 - kk), 1.0 - kk]))
		fx.burst("glints", to, Vector3.UP, HOT, WHITE, {"amount": 0.25, "speed": 0.6, "scale": 0.9})


func _flurry_finale(fi: int, p: Vector3) -> void:
	_fists.erase(fi)
	# the last straight: a big shock disc through him, a star of glints, the floor rings
	_disc(p, aim_dir(fi), 0.1, 1.1, 0.35, GOLD, WHITE, 0.26)
	fx.burst("glints", p, aim_dir(fi), WHITE, HOT, {"amount": 1.0, "speed": 1.6, "scale": 1.6})
	fx.burst("sparks", p, aim_dir(fi), HOT, GOLD, {"amount": 0.8, "speed": 1.5})
	var g := Vector3(p.x, fx._ground(fi).y, p.z)
	fx.ring_wall(g + Vector3.UP * 0.03, 0.2, 1.3, 0.3, GOLD, HOT, 0.3, {"bands": 0.0, "core": 0.5})
	fx.flash_light(p, GOLD, 4.0, 4.5, 0.3)


func _iron_shell(fi: int) -> void:
	# the iron catch: a steel-gold shell closes around him for the counter window
	var g := fx._ground(fi)
	var shell := fx.ring_wall(g, 0.75, 0.55, 1.8, Color(STEEL, 0.75), STEEL_HOT, 0.34, {"add": true, "bands": 10.0, "scroll": Vector2(0.0, 2.0),
		"lean": 0.7, "expand": 0.25, "h_end": 0.9})
	fx.follow(shell, fi, "__ground", Vector3.ZERO, 0.34)
	for w in ["lFist", "rFist"]:
		fx.burst("glints", fx.anchor(fi, str(w)), Vector3.UP, STEEL_HOT, STEEL, {"amount": 0.3, "speed": 0.3})


func _iron_answer(fi: int, pos: Vector3) -> void:
	# caught: the strike rings off him and the answer bursts back out at the striker
	var c := fx.anchor(fi, "core")
	var to := Vector3(pos.x, c.y, pos.z) - c
	var p := c + (to.normalized() * 0.3 if to.length_squared() > 1e-4 else aim_dir(fi) * 0.3)
	_disc(p, to if to.length_squared() > 1e-4 else aim_dir(fi), 0.1, 1.0, 0.3, STEEL_HOT, WHITE, 0.24)
	fx.burst("sparks", p, Vector3.UP, STEEL_HOT, HOT, {"amount": 1.0, "speed": 1.5})
	fx.burst("glints", p, Vector3.UP, WHITE, HOT, {"amount": 0.8, "speed": 1.2, "scale": 1.5})
	fx.flash_light(p, WHITE, 4.0, 4.0, 0.25)


func _rush(fi: int, ev: Dictionary) -> void:
	var dur := float(ev.get("time", 0.26))
	var g := fx._ground(fi)
	var d: Vector3 = ev.get("dir", aim_dir(fi))
	d.y = 0.0
	var fwd := d.normalized() if d.length_squared() > 1e-4 else aim_dir(fi)
	var yaw := atan2(fwd.x, fwd.z)
	var dist := float(ev.get("speed", 6.0)) * dur + 1.0
	# a clean cut across the floor (his v0.9.17 dash line, longer) and gold ghosts left behind
	fx.footprint("scrap", "line", g - fwd * 0.2, yaw, 0.0, {"length": dist, "width": 0.5, "fill": 0.55, "front": 1.0,
		"color": DEEP, "color2": HOT}, 0.7, dur)
	fx.burst("dust", g, -fwd + Vector3.UP * 0.2, DUST, null, {"amount": 0.6, "speed": 0.9})
	var n: int = GHOSTS[clampi(fx.quality, 0, 2)]
	for k in n:
		var at := dur * float(k) / float(n)
		var fade := 0.35 + 0.15 * float(k) / float(n)
		fx._later(at, func() -> void:
			_ghost(fi, 0.75 - 0.35 * float(k) / float(n), fade))
	_limb_trail(fi, "lFist", dur + 0.1, GOLD, WHITE, 0.06)
	_limb_trail(fi, "rFist", dur + 0.1, GOLD, WHITE, 0.06)


## One afterimage: Varga's body as it is right now, in gold light, left behind to fade.
func _ghost(fi: int, alpha: float, life: float) -> void:
	var v := fx._view(fi)
	if v == null or v.body == null:
		return
	if _ghost_mesh == null:
		_ghost_mesh = SphereMesh.new()
		_ghost_mesh.radius = 0.5
		_ghost_mesh.height = 1.0
		_ghost_mesh.radial_segments = 10
		_ghost_mesh.rings = 6
	var root := Node3D.new()
	fx.add_child(root)
	var mat := FxKit.flow_material(GOLD, WHITE, {"additive": 1.0, "fresnel": 1.6, "scroll": Vector2(0.0, -1.5), "noise_scale": Vector2(3.0, 3.0),
		"edge_v": 0.0, "core": 0.5, "core_width": 0.6, "alpha": alpha})
	for s: BodyDef.Seg in v.body.segments:
		var xf := v.segment_world(s.index)
		for sh: BodyDef.Shape in s.shapes:
			var a: Vector3 = xf * sh.hit_a
			var b: Vector3 = xf * sh.hit_b
			var axis := b - a
			var length := axis.length()
			var y := axis / length if length > 1e-4 else Vector3.UP
			var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
			var z := x.cross(y).normalized()
			var mi := MeshInstance3D.new()
			mi.mesh = _ghost_mesh
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
			mi.global_transform = Transform3D(Basis(x * sh.hit_r * 2.0, y * (length + sh.hit_r * 2.0), z * sh.hit_r * 2.0), (a + b) * 0.5)
	fx.animate(root, life, func(k: float, _t: float) -> void:
		mat.set_shader_parameter("alpha", alpha * (1.0 - k) * (0.8 if fx.reduce_flashes else 1.0))
		mat.set_shader_parameter("dissolve", smoothstep(0.3, 1.0, k)))


func _shockwave_ring(fi: int, pos: Vector3, r: float) -> void:
	var g := Vector3(pos.x, fx._ground(fi).y, pos.z)
	# the launcher: a ring rolls out from his feet and a column of gold climbs with the target
	fx.ring_wall(g + Vector3.UP * 0.03, 0.2, r, 0.45, GOLD, WHITE, 0.32, {"bands": 0.0, "core": 0.55, "expand": 0.4})
	fx.footprint("scrap", "circle", g, 0.0, r, {"fill": 0.45, "front": 1.0, "color": DEEP, "color2": HOT}, 0.6, 0.1)
	var top := fx.anchor(fi, "core") + aim_dir(fi) * 0.6
	fx.ring_wall(Vector3(top.x, g.y + 0.6, top.z), 0.1, 0.55, 1.4, Color(GOLD, 0.8), WHITE, 0.3, {"bands": 6.0, "scroll": Vector2(0.0, -3.0), "lean": 0.6})
	fx.burst("glints", Vector3(top.x, g.y + 1.2, top.z), Vector3.UP, HOT, WHITE, {"amount": 0.7, "speed": 2.0, "spread": 0.4})
	fx.burst("dust", g, Vector3.UP, DUST, null, {"ring": true, "radius": r * 0.7, "amount": 0.5, "speed": 0.7})
	fx.flash_light(top, GOLD, 3.0, 4.0, 0.25)
