extends MoveFxKit
## Dredge's Movesets effects (v0.9.18): the Bubble Stream's froth and its drifting soap-film
## bubbles, the Hydro Cannon's charge, beam and recoil skid, the Whirlpool's stir, opening and
## spinning pool, and the Shell Brace's hardened shell; plus the looks of the drilled styles that
## add effects (bubble mines, the riptide beam, the geyser, barnacle shards, the cavitation snap, the
## brine bomb). Tidal identity: seawater under pressure that falls, rolls and foams (bubbles, spray,
## wet floor) and a barnacled crab's weight; it never glows like fire.

const WATER := Color(0.22, 0.55, 0.9, 0.88)
const DEEP := Color(0.1, 0.42, 0.86, 1.0)
const SPRAY := Color(0.35, 0.65, 0.95, 0.8)
const DROP := Color(0.4, 0.7, 1.0, 0.85)
const DROP_LIGHT := Color(0.8, 0.95, 1.0, 0.85)
const FOAM := Color(0.92, 0.98, 1.0)
const MIST := Color(0.55, 0.75, 0.95, 0.4)
const FILM := Color(0.6, 0.86, 1.0, 0.55)        ## a bubble's skin ...
const SHEEN := Color(0.96, 0.9, 1.0)             ## ... and the oily sheen round its rim
const BARNACLE := Color(0.73, 0.7, 0.65)
const SHELL := Color(0.55, 0.23, 0.17)
const COLD := Color(0.55, 0.82, 1.0)             ## light flashes (dimmed by fx under Reduce flashing)
## The mouthparts under the eyestalks, from the shell's centre (where the bubbles leave)
const MOUTH := Vector3(0, 0.08, 0.6)
## The hardened skin over the braced shell (an ellipsoid a little larger than the shell, metres)
const SHELL_SIZE := Vector3(1.6, 0.8, 1.3)

var _froth := {}         ## fighter -> true while a Bubble Stream pours (its mouth streams follow tagged "dredge_froth")
var _cannons := {}       ## fighter -> the Hydro Cannon charging: {orb, mat, scope, t, level, base, k, cone, at, ct, next}
var _whirls := {}        ## fighter -> the Whirlpool's telegraph until it opens: {fp, ahead, t}
var _braces := {}        ## fighter -> the Shell Brace's hardened skin: {node, mat, t, dur}
var _bubble_mesh: SphereMesh = null      ## one mesh and one material shared by every bubble
var _bubble_mat: ShaderMaterial = null


func vfx_names() -> Array:
	return ["dredge_bubble", "dredge_bubble_pop", "dredge_hydro_beam", "dredge_riptide_beam", "dredge_hydro_kick", "dredge_whirl_open",
		"dredge_whirlpool", "dredge_geyser", "dredge_shell_brace", "dredge_barnacle_burst", "dredge_cavitation", "dredge_spit_splash"]


## The mouthparts in the world.
func mouth(fi: int) -> Vector3:
	return fx.anchor(fi, "core", MOUTH)


## One of this fighter's pool moves as its content defines it (null if it has none).
func _pool_move(fi: int, pool_id: String) -> PoolMove:
	var v := fx._view(fi)
	if v == null or v.creature == null:
		return null
	var pm: PoolMove = v.creature.pool.get(pool_id)
	return pm if pm != null and pm.move != null else null


## The first effect of a type in one of this fighter's pool moves ({} when there is none): the
## previews read the true reach of what is about to fire (drilled styles change it).
func _pool_effect(fi: int, pool_id: String, type: String) -> Dictionary:
	var pm := _pool_move(fi, pool_id)
	if pm == null:
		return {}
	for e in pm.move.effects:
		if typeof(e) == TYPE_DICTIONARY and str((e as Dictionary).get("type", "")) == type:
			var d: Dictionary = e
			return d
	return {}


func on_sustain(fi: int, ev: Dictionary) -> bool:
	if str(ev.get("pool", "")) != "bubble_stream":
		return false
	if str(ev.get("phase", "")) == "start":
		_start_froth(fi)
	else:
		_end_froth(fi)
	return true


func on_effect(fi: int, ev: Dictionary) -> bool:
	match str(ev.get("vfx", "")):
		"dredge_bubble":
			_puff(fi)
		"dredge_bubble_pop":
			_mine_pop(Vector3(ev.get("pos", Vector3.ZERO)), float(ev.get("radius", 0.9)))
		"dredge_hydro_beam":
			_beam(fi, ev, false)
		"dredge_riptide_beam":
			_beam(fi, ev, true)
		"dredge_hydro_kick":
			_kick(fi, ev)
		"dredge_whirl_open":
			_whirl_open(fi, ev)
		"dredge_whirlpool":
			_whirl_well(ev)          # the pool itself is drawn as a zone
		"dredge_geyser":
			_geyser(ev)
		"dredge_shell_brace":
			_brace(fi, ev)
		"dredge_barnacle_burst":
			_barnacles(fi, ev)
		"dredge_cavitation":
			_cavitation(fi, ev)
		"dredge_spit_splash":
			_spit_splash(ev)
		_:
			return false
	return true


func on_move_start(fi: int, ev: Dictionary) -> bool:
	match str(ev.get("pool", "")):
		"bubble_stream":
			# he gulps seawater: bubbles rush into the mouthparts, brine dribbles off his chin
			fx._converge(fi, "core", MOUTH, 0.28, SPRAY, FOAM, 0.45, "bubbles")
			fx.burst("drops", mouth(fi), Vector3.DOWN, DROP, DROP_LIGHT, {"amount": 0.25, "speed": 0.3, "floor": fx._ground(fi).y})
		"hydro_cannon":
			_start_cannon(fi)
		"whirlpool":
			_start_whirl(fi)
		"shell_brace":
			# the barnacles clatter shut: water and grit shaken off the shell as he clamps down
			fx.burst("drops", fx.anchor(fi, "core", Vector3(0, 0.3, 0)), Vector3.UP, DROP, DROP_LIGHT,
				{"amount": 0.4, "speed": 0.6, "spread": 1.2, "radius": 0.45, "floor": fx._ground(fi).y})
	return false        # the generic move-start clean-up still runs


func on_hit(fi: int, ev: Dictionary) -> void:
	if bool(ev.get("blocked", false)):
		return
	var p: Vector3 = ev.get("point", Vector3.ZERO)
	match str(ev.get("pool", "")):
		"hydro_cannon":
			# the beam breaks over its target: a sheet of spray off the impact
			var s := clampf(float(ev.get("damage", 6.0)) / 18.0, 0.3, 1.0)
			fx.burst("spray", p, aim_dir(fi, 0.4), SPRAY, null, {"amount": 0.4 + 0.5 * s, "speed": 1.4 + s, "spread": 0.7})
			fx.burst("mist", p, Vector3.UP, MIST, null, {"amount": 0.3 + 0.4 * s, "speed": 0.6})
		"whirlpool":
			# caught by the pull: spray whirls round the body
			fx.burst("spray", p, Vector3.UP, SPRAY, null, {"amount": 0.35, "speed": 0.5, "swirl": 6.0, "radius": 0.35})


func make_entity(e: Dictionary) -> Dictionary:
	match str(e.get("vfx", "")):
		"dredge_bubble":
			return _bubble(e)
		"dredge_whirlpool":
			return _whirlpool(e)
	return {}


func process(delta: float) -> void:
	for fi in _froth.keys():
		if not is_acting(fi):
			_end_froth(fi)            # cut off (hit, knocked down): the froth stops with the move
	_tick_cannons(delta)
	_tick_whirls(delta)
	_tick_braces(delta)


## ---- Bubble Stream -------------------------------------------------------------------------

func _start_froth(fi: int) -> void:
	_end_froth(fi, true)
	_froth[fi] = true
	# foam keeps welling out of the mouthparts while he blows, brine dribbling off his chin
	fx._stream_at(fi, "core", MOUTH, 1e9, "bubbles", FOAM, FILM, {"speed": 0.5, "spread": 0.7, "amount": 0.55, "scale": 0.8}, "dredge_froth")
	fx._stream_at(fi, "core", MOUTH + Vector3(0, -0.06, 0.02), 1e9, "drops", DROP, DROP_LIGHT,
		{"dir": Vector3.DOWN, "speed": 0.15, "spread": 0.5, "amount": 0.3, "scale": 0.7, "floor": fx._ground(fi).y}, "dredge_froth")


func _end_froth(fi: int, now := false) -> void:
	if not _froth.erase(fi):
		return
	fx.release(fi, "dredge_froth")
	if not now:
		# the last breath: a sputter of spray from the mouth
		fx.burst("spray", mouth(fi), aim_dir(fi, 0.1), SPRAY, null, {"amount": 0.35, "speed": 0.6, "spread": 0.5})


## One puff of the stream (its projectile event): froth gouts from the mouth along the stream.
func _puff(fi: int) -> void:
	fx.burst("bubbles", mouth(fi), aim_dir(fi, 0.1), FOAM, FILM, {"amount": 0.28, "speed": 1.6, "spread": 0.3, "scale": 0.8})


func _bubble_sphere() -> SphereMesh:
	if _bubble_mesh == null:
		_bubble_mesh = fx._sphere(1.0, 12)
	return _bubble_mesh


func _bubble_material() -> ShaderMaterial:
	if _bubble_mat == null:
		# a soap film: nearly clear face-on, a bright oily rim (fresnel), colour swirling slowly over it
		_bubble_mat = FxKit.flow_material(FILM, SHEEN, {"cover": 0.5, "glow_k": 0.75, "fresnel": 2.4, "scroll": Vector2(0.18, -0.3),
			"noise_scale": Vector2(3.0, 2.0), "edge_v": 0.0, "core": 0.5, "core_width": 0.7, "alpha": 0.9})
	return _bubble_mat


## A bubble of the stream: blown out small, it swells to size and shivers as it drifts; wherever it
## ends (on a fighter, on a shot it stopped, at the end of its drift) the film bursts into a fine
## spray (a pop on a fighter also gets the element's hit burst, so this stays small).
func _bubble(e: Dictionary) -> Dictionary:
	var r := maxf(float(e.get("radius", 0.22)), 0.06)
	var root := Node3D.new()
	fx.add_child(root)
	root.global_position = e["pos"]
	var skin := MeshInstance3D.new()
	skin.mesh = _bubble_sphere()
	skin.material_override = _bubble_material()
	skin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	skin.scale = Vector3.ONE * r * 0.4
	root.add_child(skin)
	var t0 := fx._clock
	var ph := fx._rng.randf() * TAU
	var en := {"node": root, "kind": "projectile", "pos": e["pos"], "dir": Vector3.FORWARD}
	en["tick"] = func(_e2: Dictionary) -> void:
		if not is_instance_valid(skin):
			return
		var t := fx._clock - t0
		var w := t * 8.0 + ph
		var size := r * minf(1.0, 0.4 + t * 4.0)
		skin.scale = Vector3(1.0 + 0.09 * sin(w), 1.0 - 0.08 * sin(w), 1.0 + 0.06 * cos(w * 1.3)) * size
	en["end"] = func() -> void:
		if not is_instance_valid(root):
			return
		fx.burst("spray", root.global_position, Vector3.UP, SPRAY, null, {"amount": 0.1 + r * 0.4, "speed": 0.6, "spread": 1.5, "scale": 0.7})
		fx.animate(root, 0.08, func(k: float, _t: float) -> void:
			if is_instance_valid(skin):
				skin.scale = Vector3.ONE * r * (1.0 + 0.5 * k))
	return en


## Bubble Mines: a mine bursting at the end of its drift, a soaking splash over its true circle.
func _mine_pop(pos: Vector3, r: float) -> void:
	var g := Vector3(pos.x, 0.0, pos.z)
	fx.burst("spray", pos, Vector3.UP, SPRAY, null, {"amount": 0.45, "speed": 1.0, "spread": 1.2})
	fx.burst("drops", pos, Vector3.UP, DROP, DROP_LIGHT, {"amount": 0.4, "speed": 0.9, "spread": 1.3, "floor": 0.0})
	fx.footprint("brine", "circle", g, 0.0, r, {"fill": 0.5, "front": 0.8, "strength": 0.7}, 0.6, 0.1)
	fx.ring_wall(g, 0.1, r, 0.2, WATER, FOAM, 0.3, {"add": false, "core": 0.8})


## ---- Hydro Cannon --------------------------------------------------------------------------

func _start_cannon(fi: int) -> void:
	_end_cannon(fi, false, true)
	var pm := _pool_move(fi, "hydro_cannon")
	var be := _pool_effect(fi, "hydro_cannon", "area")
	var cs: Dictionary = be.get("charge_scale", {}) if typeof(be.get("charge_scale", {})) == TYPE_DICTIONARY else {}
	var cone := str(be.get("shape", "line")) == "cone"
	var base := float(be.get("radius", 2.6)) if cone else float(be.get("length", 3.6))
	# the barrel: seawater swirling into a ball at the crusher claw, swelling with the charge
	var orb := MeshInstance3D.new()
	orb.mesh = fx._sphere(1.0, 14)
	var mat := FxKit.flow_material(DEEP, FOAM, {"cover": 0.85, "glow_k": 0.6, "fresnel": 0.8, "scroll": Vector2(1.6, -2.6),
		"noise_scale": Vector2(5.0, 3.0), "edge_v": 0.0, "core": 0.5, "core_width": 0.6, "alpha": 0.0})
	orb.material_override = mat
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(orb)
	orb.global_position = fx.anchor(fi, "claw_crusher")
	orb.scale = Vector3.ONE * 0.05
	# the shot's true footprint, stretching out along the floor as the charge builds
	var o := {"length": base, "width": float(be.get("width", 0.9)), "cone_deg": float(be.get("cone_deg", 40.0)),
		"fill": 0.12, "front": 0.35, "strength": 0.45}
	var scope := fx.footprint("brine", "cone" if cone else "line", fx._ground(fi), fx._yaw(fi), base if cone else 0.0, o, INF)
	(scope.material_override as ShaderMaterial).set_shader_parameter("progress", 0.0)
	_cannons[fi] = {"orb": orb, "mat": mat, "scope": scope, "t": 0.0, "level": 0.0, "base": base, "cone": cone,
		"k": float(cs.get("radius" if cone else "length", 1.0)), "at": pm.move.charge_start() if pm else 0.3,
		"ct": maxf(pm.move.charge_time, 0.1) if pm else 1.2, "next": 0.0}


func _end_cannon(fi: int, fired: bool, now := false) -> void:
	var c: Dictionary = _cannons.get(fi, {})
	if c.is_empty():
		return
	_cannons.erase(fi)
	var orb: MeshInstance3D = c["orb"]
	if is_instance_valid(orb):
		if not fired and not now:
			# cut off before it fired: the gathered water slops out of the claw
			fx.burst("drops", orb.global_position, Vector3.UP, DROP, DROP_LIGHT, {"amount": 0.5, "speed": 0.7, "spread": 1.1, "floor": fx._ground(fi).y})
			fx.burst("spray", orb.global_position, Vector3.DOWN, SPRAY, null, {"amount": 0.3, "speed": 0.4})
		orb.queue_free()
	var scope: MeshInstance3D = c["scope"]
	if is_instance_valid(scope):
		var sm := scope.material_override as ShaderMaterial
		var f0 := float(sm.get_shader_parameter("fade"))
		fx.animate(scope, 0.18, func(k: float, _t: float) -> void:
			sm.set_shader_parameter("fade", f0 * (1.0 - k)))


func _tick_cannons(delta: float) -> void:
	for fi in _cannons.keys():
		var c: Dictionary = _cannons[fi]
		if not is_acting(fi):
			_end_cannon(fi, false)
			continue
		c["t"] = float(c["t"]) + delta
		var t := float(c["t"])
		var lv := float(fx._info(fi).get("charge", -1.0))
		if lv >= 0.0:
			c["level"] = maxf(float(c["level"]), lv)
		elif lv == -2.0 and t > float(c["at"]):
			c["level"] = minf(1.0, float(c["level"]) + delta / float(c["ct"]))     # online, while held: by time
		var level := float(c["level"])
		var orb: MeshInstance3D = c["orb"]
		if is_instance_valid(orb):
			var swell := clampf(t / 0.3, 0.0, 1.0)
			var wob := 1.0 + 0.07 * sin(t * 21.0) + 0.04 * sin(t * 33.0)
			orb.global_position = fx.anchor(fi, "claw_crusher", Vector3(0, 0, 0.08))
			orb.scale = Vector3.ONE * (0.05 + 0.07 * swell + 0.1 * level) * wob     # up to ~0.45 m across, the claw's size
			orb.rotation = Vector3(t * 5.0, t * 7.0, 0.0)
			(c["mat"] as ShaderMaterial).set_shader_parameter("alpha", swell * (0.85 if fx.reduce_flashes else 1.0))
		var scope: MeshInstance3D = c["scope"]
		if is_instance_valid(scope):
			var reach := float(c["base"]) * lerpf(1.0, float(c["k"]), level)
			var sm := scope.material_override as ShaderMaterial
			sm.set_shader_parameter("radius" if bool(c["cone"]) else "length_m", reach)
			sm.set_shader_parameter("progress", clampf(t / 0.3, 0.0, 1.0) * 1.02)
			AbilityVfx._fit_footprint(scope, reach)
			scope.global_position = fx._ground(fi) + Vector3.UP * 0.03
			scope.rotation.y = fx._yaw(fi)
		# seawater keeps rushing into the claw, faster as it fills
		if t >= float(c["next"]):
			c["next"] = t + 0.24
			fx._converge(fi, "claw_crusher", Vector3.ZERO, 0.22, SPRAY, FOAM, 0.2 + 0.35 * level, "spray")


## The shot: a beam (or the Wide Bore spray) from the crusher claw over the true footprint that hit.
## Riptide's beam flows back toward the claw: it hauls instead of blasting.
func _beam(fi: int, ev: Dictionary, riptide: bool) -> void:
	_end_cannon(fi, true)
	var yaw := float(ev.get("yaw", fx._yaw(fi)))
	var fwd := MathX.forward_of_yaw(yaw)
	var o: Vector3 = ev.get("origin", ev.get("pos", fx._ground(fi)))
	var g := Vector3(o.x, 0.0, o.z)
	var tip := fx.anchor(fi, "claw_crusher", Vector3(0, 0, 0.08))
	var cone := str(ev.get("shape", "line")) == "cone"
	var reach := float(ev.get("radius", 2.6)) if cone else float(ev.get("length", 3.6))
	var width := float(ev.get("width", 0.9))
	var power := clampf(reach / (4.0 if cone else 6.0), 0.4, 1.0)      # how charged it was: the reach tells
	var end_p := g + fwd * reach + Vector3.UP * 0.55
	if cone:
		var cone_deg := float(ev.get("cone_deg", 40.0))
		var half := deg_to_rad(cone_deg) * 0.5
		fx.footprint("brine", "cone", g, yaw, reach, {"cone_deg": cone_deg, "fill": 0.55, "front": 1.0}, 0.8, 0.12)
		fx.jet(tip, fwd, reach, tan(half) * reach, WATER, FOAM, 0.5, {"cover": 0.8, "glow_k": 0.45, "flat": 0.45})
		fx.burst("spray", tip, fwd, SPRAY, null, {"spread": half, "speed": reach * 1.4, "amount": 0.2 + 0.8 * power, "life": 0.9})
		end_p = g + fwd * reach * 0.85 + Vector3.UP * 0.4
	else:
		fx.footprint("brine", "line", g, yaw, 0.0, {"length": reach, "width": width, "fill": 0.55, "front": 1.0}, 0.8, 0.1)
		# the beam: a pressurised column of seawater, a white core of foam down its middle
		var dir := (end_p - tip).normalized()
		var span := tip.distance_to(end_p)
		var flow: Array = [fx.jet(tip, dir, span, width * 0.42, WATER, FOAM, 0.42 + 0.12 * power, {"cover": 0.88, "glow_k": 0.45})]
		if fx.quality >= 1:
			flow.append(fx.jet(tip, dir, span * 0.96, width * 0.16, FOAM, Color(1, 1, 1), 0.34 + 0.1 * power, {"cover": 0.7, "glow_k": 0.7}))
		if riptide:
			for mi: MeshInstance3D in flow:
				(mi.material_override as ShaderMaterial).set_shader_parameter("scroll", Vector2(-0.3, -2.8))
		fx.burst("spray", g + fwd * reach * 0.5 + Vector3.UP * 0.45, (-fwd if riptide else fwd) + Vector3.UP * 0.4, SPRAY, null,
			{"box": Vector3(width * 0.4, 0.12, reach * 0.42), "yaw": yaw, "speed": 1.1, "amount": 0.5 + 0.5 * power})
	# where it breaks: a splash crown, droplets raining back, mist hanging low
	var hit_p := Vector3(end_p.x, 0.0, end_p.z)
	fx.ring_wall(hit_p, 0.15, maxf(width, 0.8) * (0.9 + 0.5 * power), 0.55 + 0.35 * power, WATER, FOAM, 0.45,
		{"add": false, "lean": 1.3, "core": 0.85, "edge_v": 0.2})
	fx.burst("drops", end_p, Vector3.UP - fwd * 0.3, DROP, DROP_LIGHT, {"amount": 0.5 + 0.5 * power, "speed": 1.2 + power, "spread": 0.9, "floor": 0.0})
	fx.burst("mist", end_p, Vector3.UP, MIST, null, {"amount": 0.4 + 0.4 * power, "speed": 0.6})
	if riptide and fx.quality >= 1:
		# the riptide catches at the far end and winds back toward the claw
		fx.vortex(hit_p, 0.55, 0.8, WATER, FOAM, 0.55, {"turns": 1.5, "r0": 0.4, "spin": 9.0, "grow": 0.15})
	# the muzzle: mist bursting off the claw, a cold flash
	fx.burst("mist", tip, fwd, MIST, null, {"amount": 0.4 + 0.3 * power, "speed": 1.0, "spread": 0.5})
	fx.flash_light(tip + fwd * 0.4, COLD, 1.5 + 1.5 * power, 3.5, 0.22)


## The recoil: his legs plough backward through the wet floor, spray kicked up behind the shell.
func _kick(fi: int, ev: Dictionary) -> void:
	var spd := float(ev.get("speed", 2.4))
	var slide := clampf(spd * spd / 44.0, 0.15, 1.2)      # how far the kick shoves him (he brakes at ~22 m/s²)
	var k := clampf(spd / 6.0, 0.3, 1.0)
	var yaw := fx._yaw(fi)
	var back := -MathX.forward_of_yaw(yaw)
	for side: float in [-1.0, 1.0]:
		var foot := fx.fpoint(fi, Vector3(0.95 * side, 0.0, -0.1))
		fx.footprint("brine", "line", foot, yaw + PI, 0.0, {"length": slide + 0.35, "width": 0.3, "fill": 0.7, "front": 0.6, "strength": 0.8}, 1.0, 0.25)
		fx.burst("spray", foot + Vector3.UP * 0.1, back + Vector3.UP * 0.6, SPRAY, null, {"amount": 0.25 + 0.3 * k, "speed": 0.9 + k, "spread": 0.5})
	fx.burst("drops", fx.anchor(fi, "core", Vector3(0, 0.2, -0.3)), back + Vector3.UP, DROP, DROP_LIGHT,
		{"amount": 0.3 + 0.3 * k, "speed": 0.8, "floor": fx._ground(fi).y})


## ---- Whirlpool -----------------------------------------------------------------------------

func _start_whirl(fi: int) -> void:
	_end_whirl(fi)
	var ze := _pool_effect(fi, "whirlpool", "zone")
	var at := str(ze.get("at", "forward:1.6"))
	var ahead := float(at.get_slice(":", 1)) if at.begins_with("forward") else 0.0
	var r := float(ze.get("radius", 2.4))
	# the pool he is about to open, already turning on the floor while the claws stir
	var fp := fx.footprint("brine", "circle", fx.fpoint(fi, Vector3(0, 0, ahead)), 0.0, r, {"fill": 0.15, "front": 0.4, "strength": 0.45, "speed": 2.5}, INF)
	(fp.material_override as ShaderMaterial).set_shader_parameter("progress", 0.0)
	_whirls[fi] = {"fp": fp, "ahead": ahead, "t": 0.0}
	# water streams off both claws as they rise and stir
	for w: String in ["claw_cutter", "claw_crusher"]:
		fx._stream_at(fi, w, Vector3.ZERO, 0.5, "drops", DROP, DROP_LIGHT, {"dir": Vector3.DOWN, "speed": 0.2, "amount": 0.4, "floor": fx._ground(fi).y}, "dredge_whirl")


func _end_whirl(fi: int) -> void:
	var w: Dictionary = _whirls.get(fi, {})
	if w.is_empty():
		return
	_whirls.erase(fi)
	fx.release(fi, "dredge_whirl")
	var fp: MeshInstance3D = w["fp"]
	if is_instance_valid(fp):
		var sm := fp.material_override as ShaderMaterial
		var f0 := float(sm.get_shader_parameter("fade"))
		fx.animate(fp, 0.2, func(k: float, _t: float) -> void:
			sm.set_shader_parameter("fade", f0 * (1.0 - k)))


func _tick_whirls(delta: float) -> void:
	for fi in _whirls.keys():
		var w: Dictionary = _whirls[fi]
		if not is_acting(fi):
			_end_whirl(fi)                # cut off before the claws struck the floor
			continue
		w["t"] = float(w["t"]) + delta
		var t := float(w["t"])
		var fp: MeshInstance3D = w["fp"]
		if is_instance_valid(fp):
			fp.global_position = fx.fpoint(fi, Vector3(0, 0.03, float(w["ahead"])))
			fp.rotation.y = -t * 2.5
			(fp.material_override as ShaderMaterial).set_shader_parameter("progress", clampf(t / 0.45, 0.0, 1.0) * 1.02)


## The claws strike the floor: the water caves in toward the eye of the pool (its true circle) and
## splashes up where each claw hit.
func _whirl_open(fi: int, ev: Dictionary) -> void:
	_end_whirl(fi)
	var p: Vector3 = ev.get("pos", fx._ground(fi))
	var g := Vector3(p.x, 0.0, p.z)
	var r := float(ev.get("radius", 2.4))
	fx.footprint("brine", "circle", g, 0.0, r, {"fill": 0.5, "front": 1.0}, 0.6, 0.1)
	fx.ring_wall(g, r, 0.3, 0.55, WATER, FOAM, 0.5, {"add": false, "lean": 0.75, "core": 0.85, "scroll": Vector2(-0.9, -1.0), "expand": 0.85})
	fx.burst("spray", g + Vector3.UP * 0.2, Vector3.UP, SPRAY, null, {"ring": true, "radius": r * 0.9, "speed": 0.8, "spread": 0.4, "swirl": 4.0, "amount": 0.8})
	fx.burst("mist", g + Vector3.UP * 0.3, Vector3.UP, MIST, null, {"ring": true, "radius": r * 0.6, "speed": 0.4, "amount": 0.5})
	for w: String in ["claw_cutter", "claw_crusher"]:
		var cp := fx.anchor(fi, w)
		var fl := Vector3(cp.x, 0.08, cp.z)
		fx.burst("drops", fl, Vector3.UP, DROP, DROP_LIGHT, {"amount": 0.45, "speed": 1.1, "spread": 0.7, "floor": 0.0})
		fx.burst("spray", fl, Vector3.UP, SPRAY, null, {"amount": 0.35, "speed": 0.9, "spread": 0.5})


## The pool forming (its zone event): water wells up out of the eye.
func _whirl_well(ev: Dictionary) -> void:
	var p: Vector3 = ev.get("pos", Vector3.ZERO)
	fx.burst("bubbles", Vector3(p.x, 0.1, p.z), Vector3.UP, FOAM, FILM, {"radius": 0.4, "amount": 0.6, "speed": 0.6})


## The whirlpool: its true circle as a wet, turning brine pool, a spiral sheet of water winding down
## into the eye, a crest of foam riding round the rim, spray flung off it and bubbles in the eye.
## It follows its zone (Eye of the Storm travels with Dredge) and fades when the zone ends.
func _whirlpool(e: Dictionary) -> Dictionary:
	var r := maxf(float(e.get("radius", 2.4)), 0.3)
	var p: Vector3 = e["pos"]
	var root := Node3D.new()
	fx.add_child(root)
	root.global_position = Vector3(p.x, 0.0, p.z)
	var fp := fx.footprint("brine", "circle", root.global_position, 0.0, r, {"fill": 0.6, "front": 0.0, "speed": 2.5, "stain_a": 0.5}, INF)
	fp.reparent(root)
	fp.position = Vector3.UP * 0.02
	var fmat := fp.material_override as ShaderMaterial
	fmat.set_shader_parameter("pulse", 1.0)
	fmat.set_shader_parameter("progress", 0.0)
	# (the spiral's band stands upright, so it is made tall enough to read from the raised camera)
	var funnel := MeshInstance3D.new()
	funnel.mesh = FxKit.spiral_mesh(2.5, 0.12, 1.0, 0.35)
	var smat := FxKit.flow_material(WATER, FOAM, {"additive": 0.2, "scroll": Vector2(-1.8, 0.0), "noise_scale": Vector2(8.0, 1.5),
		"edge_v": 0.45, "core": 0.6, "core_width": 0.3, "bands": 3.0, "alpha": 0.0})
	funnel.material_override = smat
	funnel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	funnel.scale = Vector3(r * 0.95, 0.45, r * 0.95)
	funnel.position = Vector3.UP * 0.02
	root.add_child(funnel)
	var rim := MeshInstance3D.new()
	rim.mesh = FxKit.wall_mesh(48, 1.08)
	var rmat := FxKit.flow_material(SPRAY, FOAM, {"additive": 0.15, "scroll": Vector2(0.9, -0.5), "noise_scale": Vector2(14.0, 2.0),
		"edge_v": 0.35, "core": 0.75, "core_width": 0.2, "alpha": 0.0})
	rim.material_override = rmat
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rim.scale = Vector3(r, 0.22, r)
	rim.visible = fx.quality >= 1
	root.add_child(rim)
	var spray := fx._attached_stream(root, "spray", SPRAY, null, {"ring": true, "radius": r * 0.92, "speed": 0.45, "swirl": 4.0, "amount": 0.45})
	var eye := fx._attached_stream(root, "bubbles", FOAM, FILM, {"radius": r * 0.22, "speed": 0.45, "amount": 0.5})
	var t0 := fx._clock
	var cur := {"r": r}
	var en := {"node": root, "kind": "zone", "pos": p}
	en["tick"] = func(ze: Dictionary) -> void:
		if not is_instance_valid(root):
			return
		var t := fx._clock - t0
		var q: Vector3 = ze["pos"]
		root.global_position = Vector3(q.x, 0.0, q.z)
		var a := clampf(t / 0.25, 0.0, 1.0) * (0.9 if fx.reduce_flashes else 1.0)
		funnel.rotation.y = -t * 3.6
		rim.rotation.y = -t * 1.3
		fp.rotation.y = -t * 1.8
		smat.set_shader_parameter("alpha", a * 0.85)
		rmat.set_shader_parameter("alpha", a * 0.8)
		fmat.set_shader_parameter("progress", clampf(t / 0.25, 0.0, 1.0) * 1.02)
		# zones can be resized by the simulation (zone reactions): keep drawing the real size
		var nr := maxf(float(ze.get("radius", cur["r"])), 0.3)
		if absf(nr - float(cur["r"])) > 0.005:
			cur["r"] = nr
			fmat.set_shader_parameter("radius", nr)
			AbilityVfx._fit_footprint(fp, nr)
			funnel.scale = Vector3(nr * 0.95, 0.45, nr * 0.95)
			rim.scale = Vector3(nr, 0.22, nr)
	en["end"] = func() -> void:
		for gp: GPUParticles3D in [spray, eye]:
			if gp != null and is_instance_valid(gp):
				# the last spray settles where it was flung while the pool drains away
				var gpos := gp.global_position
				gp.reparent(fx)
				gp.global_position = gpos
				fx.end_stream(gp)
		if is_instance_valid(root):
			fx.animate(root, 0.3, func(k: float, _t: float) -> void:
				smat.set_shader_parameter("dissolve", k)
				rmat.set_shader_parameter("dissolve", k)
				fmat.set_shader_parameter("fade", 1.0 - k))
	return en


## Geyser: the eye erupts as the pool closes, a column of water that rains back down.
func _geyser(ev: Dictionary) -> void:
	var p: Vector3 = ev.get("pos", Vector3.ZERO)
	var g := Vector3(p.x, 0.0, p.z)
	var r := float(ev.get("radius", 1.4))
	fx.footprint("brine", "circle", g, 0.0, r, {"fill": 0.6, "front": 1.0}, 0.9, 0.08)
	fx.jet(g + Vector3.UP * 0.05, Vector3.UP, 2.8, r * 0.45, WATER, FOAM, 0.6, {"cover": 0.85, "glow_k": 0.45})
	if fx.quality >= 1:
		fx.vortex(g, r * 0.5, 2.4, WATER, FOAM, 0.65, {"turns": 1.5, "r0": 0.6, "spin": 6.0, "grow": 0.15})
	fx.ring_wall(g, 0.3, r, 0.45, WATER, FOAM, 0.45, {"add": false, "core": 0.8})
	fx.burst("spray", g + Vector3.UP * 0.3, Vector3.UP, SPRAY, null, {"amount": 1.0, "speed": 2.6, "spread": 0.3})
	fx.burst("drops", g + Vector3.UP * 2.2, Vector3.UP, DROP, DROP_LIGHT, {"amount": 0.9, "speed": 1.0, "spread": 1.3, "radius": r * 0.4, "floor": 0.0})
	fx.burst("mist", g + Vector3.UP * 1.5, Vector3.UP, MIST, null, {"amount": 0.6, "speed": 0.6})
	fx.flash_light(g + Vector3.UP * 1.2, COLD, 2.0, 4.0, 0.3)


## ---- Shell Brace ---------------------------------------------------------------------------

func _brace(fi: int, ev: Dictionary) -> void:
	_end_brace(fi, true)
	var dur := float(ev.get("duration", 3.0))
	var g := fx._ground(fi)
	# the clench: he drops onto his shell and a ring of brine slaps out across the floor
	fx.ring_wall(g, 0.7, 1.3, 0.35, WATER, FOAM, 0.35, {"add": false, "core": 0.8})
	fx.burst("spray", g + Vector3.UP * 0.1, Vector3.UP, SPRAY, null, {"ring": true, "radius": 0.9, "speed": 0.7, "spread": 0.4, "amount": 0.6})
	fx.footprint("brine", "ring", g, 0.0, 1.3, {"inner": 0.75, "fill": 0.5, "front": 0.8, "strength": 0.7}, 0.6, 0.1)
	# the hardened skin: a film of brine sheeting over the shell for as long as the brace holds,
	# barnacles glinting through it
	var skin := MeshInstance3D.new()
	skin.mesh = fx._sphere(0.5, 18)
	var mat := FxKit.flow_material(Color(0.3, 0.6, 0.92, 0.6), FOAM, {"cover": 0.55, "glow_k": 0.4, "fresnel": 1.8, "scroll": Vector2(0.05, 0.5),
		"noise_scale": Vector2(6.0, 4.0), "edge_v": 0.0, "core": 0.3, "core_width": 0.5, "alpha": 0.0})
	skin.material_override = mat
	skin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(skin)
	skin.global_position = fx.anchor(fi, "core")
	skin.scale = SHELL_SIZE
	fx._stream_at(fi, "core", Vector3(0, 0.28, 0), dur, "glints", Color(0.9, 0.95, 1.0), null, {"amount": 0.18, "speed": 0.1, "radius": 0.55}, "dredge_brace")
	_braces[fi] = {"node": skin, "mat": mat, "t": 0.0, "dur": dur}


func _end_brace(fi: int, now := false) -> void:
	var b: Dictionary = _braces.get(fi, {})
	if b.is_empty():
		return
	_braces.erase(fi)
	fx.release(fi, "dredge_brace")
	var skin: MeshInstance3D = b["node"]
	if not is_instance_valid(skin):
		return
	if now:
		skin.queue_free()
		return
	# the shell eases open: the film runs off as droplets
	fx.burst("drops", skin.global_position, Vector3.UP, DROP, DROP_LIGHT, {"amount": 0.4, "speed": 0.4, "spread": 1.3, "radius": 0.5, "floor": fx._ground(fi).y})
	var mat: ShaderMaterial = b["mat"]
	fx.animate(skin, 0.2, func(k: float, _t: float) -> void:
		mat.set_shader_parameter("dissolve", k))


func _tick_braces(delta: float) -> void:
	for fi in _braces.keys():
		var b: Dictionary = _braces[fi]
		b["t"] = float(b["t"]) + delta
		var t := float(b["t"])
		var dur := float(b["dur"])
		if t >= dur or not fx._alive(fi, fx._info(fi)):
			_end_brace(fi)
			continue
		var skin: MeshInstance3D = b["node"]
		if not is_instance_valid(skin):
			_braces.erase(fi)
			continue
		skin.global_position = fx.anchor(fi, "core", Vector3(0, -0.02, 0))
		skin.rotation = Vector3(0.0, fx._yaw(fi), 0.0)
		skin.scale = SHELL_SIZE * (1.0 + 0.02 * sin(t * 4.0))
		var a := clampf(t / 0.15, 0.0, 1.0) * (1.0 - smoothstep(dur - 0.35, dur, t))
		(b["mat"] as ShaderMaterial).set_shader_parameter("alpha", a * (0.8 if fx.reduce_flashes else 0.95))


## Barnacle Crust: shell shards burst off the braced shell at an attacker up close.
func _barnacles(fi: int, ev: Dictionary) -> void:
	var p: Vector3 = ev.get("pos", fx._ground(fi))
	var g := Vector3(p.x, 0.0, p.z)
	var c := fx.anchor(fi, "core", Vector3(0, 0.15, 0))
	fx.burst("shards", c, Vector3.UP, BARNACLE, SHELL, {"amount": 0.7, "speed": 1.1, "spread": 1.3, "floor": g.y})
	fx.burst("spray", c, Vector3.UP, SPRAY, null, {"amount": 0.35, "speed": 0.8})
	fx.ring_wall(g, 0.5, float(ev.get("radius", 1.5)), 0.3, BARNACLE, FOAM, 0.25, {"add": false, "bands": 8.0, "core": 0.6})


## ---- Drilled strikes and spit ----------------------------------------------------------------

## Pistol Shrimp: the Bilge Pump's snap collapses a bubble at the claw, a sharp crack of water.
func _cavitation(fi: int, ev: Dictionary) -> void:
	var c := fx.anchor(fi, "claw_crusher")
	var p: Vector3 = ev.get("pos", c)
	var g := Vector3(p.x, 0.0, p.z)
	fx.burst("glints", c, Vector3.UP, FOAM, Color(0.75, 0.9, 1.0), {"amount": 0.6, "speed": 1.4, "scale": 1.2})
	fx.burst("spray", c, aim_dir(fi), SPRAY, null, {"amount": 0.6, "speed": 1.6, "spread": 0.8})
	fx.burst("mist", c, Vector3.UP, MIST, null, {"amount": 0.4, "speed": 0.8})
	fx.ring_wall(g, 0.1, float(ev.get("radius", 1.1)), 0.25, WATER, FOAM, 0.22, {"add": false, "expand": 0.4, "core": 0.8})
	fx.flash_light(c, COLD, 2.0, 2.5, 0.12)


## Brine Bomb: the spit bursts where it lands, a crown of water over its splash circle.
func _spit_splash(ev: Dictionary) -> void:
	var p: Vector3 = ev.get("pos", Vector3.ZERO)
	var g := Vector3(p.x, 0.0, p.z)
	var r := float(ev.get("radius", 1.6))
	fx.footprint("brine", "circle", g, 0.0, r, {"fill": 0.55, "front": 1.0}, 0.7, 0.1)
	fx.ring_wall(g, 0.2, r, 0.6, WATER, FOAM, 0.45, {"add": false, "lean": 1.25, "core": 0.85})
	fx.burst("drops", g + Vector3.UP * 0.3, Vector3.UP, DROP, DROP_LIGHT, {"amount": 0.8, "speed": 1.4, "spread": 0.8, "floor": 0.0})
	fx.burst("spray", g + Vector3.UP * 0.2, Vector3.UP, SPRAY, null, {"ring": true, "radius": r * 0.4, "speed": 1.0, "amount": 0.7})
