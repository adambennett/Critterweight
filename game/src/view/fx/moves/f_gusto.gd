extends MoveFxKit
## Gusto's Movesets effects (v0.9.18, docs/kits/f_gusto.md "Movesets"): the Air Slash crescent, the
## Feather Darts volley, the Twister funnel and the whirl it leaves, Tailwind's slipstream, and what
## his styles add (the lift-off gust, slipstream whirls, the quick-draft dart, the storm's eye).
## Gale identity: air seen because it moves (a crescent's cutting edge, streaks and wing-tip
## contrails, spiralling funnels, feathers riding the gusts) in his teal and white with the dark
## feather tips of his palette, never a flat teal glow. Every vfx name is spelled "gusto_*".
## Budget: meshes are built once per kit and shared; particles go through the pooled bursts plus a
## few attached streams (none at Low quality); ribbons reuse their point arrays; flashes and the
## additive pieces are dimmed under Reduce flashing.

const WIND := Color(0.3, 0.72, 0.76)               ## the gale teal of his v0.9.17 recipes
const WIND_SOFT := Color(0.42, 0.78, 0.8, 0.55)    ## wind puffs
const EDGE := Color(0.8, 0.98, 1.0)                ## a crescent's cutting edge
const WHITE := Color(1, 1, 1)
const FEATHER := Color(0.95, 0.93, 0.85)
const FEATHER_B := Color(0.75, 0.9, 0.9)
const QUILL := Color(0.17, 0.17, 0.17)             ## the dark feather tips (art palette "tips")
const DUST := Color(0.8, 0.77, 0.7, 0.4)
const FUNNEL := Color(0.36, 0.76, 0.8, 0.9)

var _swings := {}          ## fighter -> the Air Slash whip's wing-tip trail (_trail_new + t0/t1)
var _winds := {}           ## fighter -> Tailwind slipstream {until, ending, trails, stream}
var _crescent: ArrayMesh = null
var _streak: ArrayMesh = null
var _dart: ArrayMesh = null
var _dart_mat: StandardMaterial3D = null
var _dart_tail_mat: ShaderMaterial = null
var _last_slash := -9.0    ## when the last crescent appeared (Twin Crescents lean opposite ways)
var _slash_lean := 1.0


func vfx_names() -> Array:
	return ["gusto_air_slash", "gusto_feather_darts", "gusto_twister", "gusto_twister_eddy", "gusto_storm_eye",
		"gusto_tailwind", "gusto_tailwind_dart", "gusto_slipstream_eddy", "gusto_liftoff_gust"]


# =====================================================================================
# Events
# =====================================================================================

func on_move_start(fi: int, ev: Dictionary) -> bool:
	var pool := str(ev.get("pool", ""))
	var lead := _lead(fi, pool)
	match pool:
		"air_slash":
			# the left wing draws back and the air gathers along its edge; the tip leaves a trail
			# through the coil and the whip (cut short at the release)
			fx._converge(fi, "wing_edge_l", Vector3.ZERO, lead, WIND, WHITE, 0.4, "wisps")
			fx.burst("glints", fx.anchor(fi, "wing_edge_l"), Vector3.UP, EDGE, null, {"amount": 0.3, "speed": 0.4})
			_start_swing(fi, lead * 0.55, lead * 0.45 + 0.1)
		"feather_darts":
			# both wings rear back and ruffle: loose down drifts off, light runs along the quills
			for w in ["wing_mid_l", "wing_mid_r"]:
				fx._converge(fi, w, Vector3.ZERO, lead, WIND, WHITE, 0.25, "wisps")
				fx.burst("feathers", fx.anchor(fi, w), Vector3.UP, FEATHER, FEATHER_B, {"amount": 0.2, "speed": 0.5, "floor": fx._ground(fi).y})
			fx.burst("glints", fx.anchor(fi, "core", Vector3(0, 0.1, 0)), Vector3.UP, EDGE, null, {"amount": 0.25, "speed": 0.5, "radius": 0.5})
		"twister":
			# the pirouette: wind starts to circle his feet and climbs with the spin
			var g := fx._ground(fi)
			var spin := fx.vortex(g, 1.0, 1.3, Color(0.32, 0.74, 0.78, 0.8), WHITE, lead + 0.06, {"turns": 2.2, "r0": 0.6, "spin": 11.0, "grow": 0.7, "add": true})
			fx.follow(spin, fi, "__ground", Vector3.ZERO, lead + 0.06)
			fx.burst("dust", g + Vector3.UP * 0.05, Vector3.UP, DUST, null, {"ring": true, "radius": 0.9, "swirl": 6.0, "speed": 0.5, "amount": 0.6})
		"tailwind":
			fx._converge(fi, "core", Vector3.ZERO, lead, WIND, WHITE, 0.35, "wisps")
	return false        # the generic move start still runs (it ends a hover's downdraft)


func on_effect(fi: int, ev: Dictionary) -> bool:
	var pos: Vector3 = ev.get("pos", fx._ground(fi))
	match str(ev.get("vfx", "")):
		"gusto_air_slash":
			_slash_release(fi)
		"gusto_feather_darts":
			_darts_release(fi)
		"gusto_twister":
			_twister_release(fi)
		"gusto_twister_eddy", "gusto_slipstream_eddy":
			_eddy_burst(pos, float(ev.get("radius", 1.3)), false)
		"gusto_storm_eye":
			_eddy_burst(pos, float(ev.get("radius", 1.7)), true)
		"gusto_tailwind":
			_tailwind(fi, ev)
		"gusto_tailwind_dart":
			_tailwind_dart(fi, ev)
		"gusto_liftoff_gust":
			_liftoff(fi, pos, float(ev.get("radius", 1.6)))
		_:
			return false
	return true


## Extras over the generic impact (its element burst still runs).
func on_hit(fi: int, ev: Dictionary) -> void:
	var p: Vector3 = ev.get("point", Vector3.ZERO)
	var parried := bool(ev.get("parried", false))
	var blocked := bool(ev.get("blocked", false))
	match str(ev.get("pool", "")):
		"air_slash":
			if parried:
				# a parried crescent shatters into glints and loose air
				fx.burst("glints", p, Vector3.UP, EDGE, null, {"amount": 0.7, "speed": 1.4})
				fx.burst("wind", p, Vector3.UP, WIND_SOFT, null, {"amount": 0.4, "speed": 1.0, "spread": 1.2})
			elif not blocked:
				_slash_mark(fi, p)
		"feather_darts":
			if not parried:
				fx.burst("feathers", p, Vector3.UP, FEATHER, FEATHER_B, {"amount": 0.12, "speed": 0.9, "floor": _floor_of(ev)})
		"twister":
			if not blocked and not parried:
				# caught: the wind spirals up around the target as it is thrown into the air
				var ti := int(ev.get("target", -1))
				var tg := fx._ground(ti) if ti >= 0 else Vector3(p.x, 0.0, p.z)
				fx.vortex(tg, 0.75, 1.7, FUNNEL, WHITE, 0.5, {"turns": 2.2, "r0": 0.45, "spin": 14.0, "grow": 0.2, "add": true})
				fx.burst("wind", tg + Vector3.UP * 0.4, Vector3.UP, WIND_SOFT, null, {"ring": true, "radius": 0.45, "swirl": 8.0, "speed": 1.6, "amount": 0.6})


func make_entity(e: Dictionary) -> Dictionary:
	match str(e.get("vfx", "")):
		"gusto_air_slash":
			return _crescent_entity(e)
		"gusto_feather_darts":
			return _dart_entity(e)
		"gusto_twister":
			return _twister_entity(e)
		"gusto_twister_eddy", "gusto_slipstream_eddy":
			return _eddy_entity(e, false)
		"gusto_storm_eye":
			return _eddy_entity(e, true)
	return {}


func process(_delta: float) -> void:
	if not _swings.is_empty():
		var now := fx._clock
		for fi in _swings.keys():
			var tr: Dictionary = _swings[fi]
			var live := _alive(fi) and is_acting(fi)
			var over := now > float(tr["t1"]) or not live
			if not _trail_step(tr, live and now >= float(tr["t0"]) and not over, over):
				_swings.erase(fi)
	if not _winds.is_empty():
		for fi in _winds.keys():
			var wd: Dictionary = _winds[fi]
			var on := not bool(wd["ending"]) and fx._clock < float(wd["until"]) and _alive(fi)
			if not on and not bool(wd["ending"]):
				_end_slipstream(fi, false)
			var gp = wd["stream"]
			if on and is_instance_valid(gp):
				# the wind behind him keeps streaming backward as he turns
				var pm := (gp as GPUParticles3D).process_material as ShaderMaterial
				pm.set_shader_parameter("direction", (Vector3.UP * 0.15 - aim_dir(fi)).normalized())
			var trailing := false
			for tr in wd["trails"]:
				if _trail_step(tr, on, not on):
					trailing = true
			if not on and not trailing:
				_winds.erase(fi)


# =====================================================================================
# Air Slash: a crescent of air
# =====================================================================================

func _slash_release(fi: int) -> void:
	var tip := fx.anchor(fi, "wing_edge_l")
	var core := fx.anchor(fi, "core")
	var d := aim_dir(fi)
	var tr: Dictionary = _swings.get(fi, {})
	if not tr.is_empty():
		tr["t1"] = minf(float(tr["t1"]), fx._clock + 0.05)
	# the whip: a bright arc across his front, from left and high to right and low (the cut the blade
	# keeps), the air it split puffing out ahead, feathers shed by the snap
	_cut_arc(core, fx._yaw(fi), 0.85, 1.1, -0.9, tip.y - core.y + 0.15, tip.y - core.y - 0.25, 0.16, 0.18)
	fx.burst("wind", tip, d, WIND_SOFT, null, {"spread": 0.3, "speed": 1.6, "amount": 0.55, "swirl": 3.0})
	fx.burst("glints", tip, d, EDGE, null, {"amount": 0.35, "speed": 0.8})
	fx.burst("feathers", tip, d + Vector3.UP * 0.4, FEATHER, FEATHER_B, {"amount": 0.25, "speed": 0.8, "floor": fx._ground(fi).y})
	fx.flash_light(tip, Color(0.6, 0.95, 1.0), 1.6, 2.5, 0.15)


## The flying blade: a crescent (belly ahead, horns trailing) leaning with the wing's diagonal cut,
## an afterimage a beat behind it and streaks off its horns; it breaks up into loose air.
func _crescent_entity(e: Dictionary) -> Dictionary:
	var root := Node3D.new()
	fx.add_child(root)
	root.global_position = e["pos"]
	_face(root, e)
	# a crescent hard on the heels of another (Twin Crescents) leans the other way: an X of cuts
	_slash_lean = -_slash_lean if fx._clock - _last_slash < 0.3 else 1.0
	_last_slash = fx._clock
	var lean := Node3D.new()
	lean.rotation.z = deg_to_rad(-50.0) * _slash_lean
	root.add_child(lean)
	var dim := _dim()
	var mat := FxKit.flow_material(Color(0.6, 0.92, 0.95, 0.95), WHITE, {"additive": 0.8, "scroll": Vector2(-3.5, 0.0),
		"noise_scale": Vector2(5.0, 1.3), "edge_v": 0.35, "edge_u": 0.06, "core": 0.25, "core_width": 0.2, "alpha": dim})
	var blade := _mesh_child(lean, _crescent_mesh(), mat)
	var tails: Array = []
	if fx.quality >= 1:
		var ghost := _mesh_child(lean, _crescent_mesh(), FxKit.flow_material(WIND, Color(0.8, 1.0, 1.0), {"additive": 0.6,
			"scroll": Vector2(-2.0, 0.0), "noise_scale": Vector2(4.0, 1.0), "edge_v": 0.45, "edge_u": 0.1, "core": 0.4, "core_width": 0.3,
			"alpha": 0.45 * dim}))
		ghost.position = Vector3(0, 0, 0.24)
		ghost.scale = Vector3(1.15, 1.0, 1.1)
		var tail_mat := FxKit.flow_material(Color(0.55, 0.88, 0.92, 0.8), WHITE, {"additive": 0.75, "scroll": Vector2(-3.0, 0.0),
			"noise_scale": Vector2(3.0, 1.0), "edge_v": 0.5, "edge_u": 0.12, "core": 0.5, "core_width": 0.3, "alpha": 0.7 * dim})
		for k in 3:                          # off both horns and the belly
			var tl := _mesh_child(lean, _streak_mesh(), tail_mat)
			var w := 0.2 if k == 1 else 0.12
			tl.position = Vector3((k - 1) * 0.46, 0.0, 0.08 if k == 1 else 0.3)
			tl.scale = Vector3(w, w, 0.01)
			tails.append(tl)
	var gusts := fx._attached_stream(root, "wind", WIND_SOFT, null, {"speed": 0.3, "amount": 0.45, "swirl": 4.0})
	var t0 := fx._clock
	return {"node": root, "kind": "projectile", "pos": e["pos"], "dir": Vector3.FORWARD,
		"tick": func(_e2: Dictionary) -> void:
			var t := fx._clock - t0
			# the streaks stretch out as it flies (never back through Gusto's wing); the blade shivers
			var reach := clampf(t / 0.08, 0.01, 1.0) * 1.3
			for tl in tails:
				if is_instance_valid(tl):
					var tn: Node3D = tl
					tn.scale.z = reach
			if is_instance_valid(blade):
				blade.scale = Vector3(1.0 + 0.05 * sin(t * 47.0), 1.0, 1.0),
		"end": func() -> void:
			_release_stream(gusts)
			if not is_instance_valid(root):
				return
			fx.burst("wind", root.global_position, Vector3.UP, WIND_SOFT, null, {"amount": 0.25, "speed": 0.6, "spread": 1.2})
			fx.animate(root, 0.12, func(k: float, _t: float) -> void:
				mat.set_shader_parameter("dissolve", k)
				mat.set_shader_parameter("alpha", (1.0 - k) * dim))}


## A crescent landing: a bright cut drawn across the target where it struck, and the air it carried
## bursting through.
func _slash_mark(fi: int, p: Vector3) -> void:
	var d := aim_dir(fi)
	var side := d.cross(Vector3.UP).normalized() * _slash_lean
	var slant := (Vector3.UP * 0.75 + side * 0.65).normalized()
	_cut_line(p - slant * 0.45 - d * 0.1, p + slant * 0.45 + d * 0.05, 0.16, 0.12)
	fx.burst("wind", p, d, WIND_SOFT, null, {"spread": 0.5, "speed": 1.6, "amount": 0.5, "swirl": 3.0})
	fx.burst("glints", p, d, EDGE, null, {"amount": 0.45, "speed": 1.2})


# =====================================================================================
# Feather Darts: a fan of quills
# =====================================================================================

func _darts_release(fi: int) -> void:
	var p := fx.anchor(fi, "body")
	var yaw := fx._yaw(fi)
	var d := aim_dir(fi)
	var e := _pool_effect(fi, "feather_darts", "gusto_feather_darts")
	var n := maxi(1, int(e.get("count", 5)))
	var spread := deg_to_rad(float(e.get("spread_deg", 30.0)))
	var fl := fx._ground(fi).y
	# the fling: down sheds off both wings as they snap forward, the volley bursts out between them
	# and a streak runs out with each dart
	for w in ["wing_mid_l", "wing_mid_r"]:
		fx.burst("feathers", fx.anchor(fi, str(w)), d + Vector3.UP * 0.2, FEATHER, FEATHER_B, {"spread": 0.5, "speed": 1.0, "amount": 0.2, "floor": fl})
	fx.burst("wind", p, d, WIND_SOFT, null, {"spread": maxf(spread * 0.5, 0.15), "speed": 1.4, "amount": 0.45})
	fx.burst("glints", p, d, EDGE, null, {"amount": 0.25, "speed": 0.6})
	for k in n:
		var off := 0.0 if n == 1 else lerpf(-spread * 0.5, spread * 0.5, float(k) / float(n - 1))
		fx._wind_streak(p + Vector3.DOWN * 0.15, yaw + off, 1.4, 0.2, 0.1)


## One dart: two crossed feather vanes (dark tip, cream vane, grey-teal tail) spinning on their axis,
## a short streak of air behind.
func _dart_entity(e: Dictionary) -> Dictionary:
	var root := Node3D.new()
	fx.add_child(root)
	root.global_position = e["pos"]
	_face(root, e)
	var spin := Node3D.new()
	spin.rotation.z = fx._rng.randf() * TAU
	root.add_child(spin)
	_mesh_child(spin, _dart_mesh(), _dart_material())
	var tail: MeshInstance3D = null
	if fx.quality >= 1:
		tail = _mesh_child(root, _streak_mesh(), _dart_tail_material())
		tail.position = Vector3(0, 0, 0.16)
		tail.scale = Vector3(0.05, 0.05, 0.01)
	var gust: GPUParticles3D = null
	if fx.quality >= 2:
		gust = fx._attached_stream(root, "wind", WIND_SOFT, null, {"speed": 0.15, "amount": 0.15})
	var t0 := fx._clock
	var roll := spin.rotation.z
	return {"node": root, "kind": "projectile", "pos": e["pos"], "dir": Vector3.FORWARD,
		"tick": func(_e2: Dictionary) -> void:
			var t := fx._clock - t0
			if is_instance_valid(spin):
				spin.rotation.z = roll + t * 24.0
			if tail != null and is_instance_valid(tail):
				tail.scale.z = clampf(t / 0.06, 0.02, 1.0) * 0.7,
		"end": func() -> void:
			_release_stream(gust)
			if is_instance_valid(root):
				fx.animate(root, 0.08, func(k: float, _t: float) -> void:
					root.scale = Vector3.ONE * maxf(1.0 - k, 0.01))}


# =====================================================================================
# Twister: a travelling funnel and the whirl it leaves
# =====================================================================================

func _twister_release(fi: int) -> void:
	var g := fx._ground(fi)
	var d := aim_dir(fi)
	var yaw := fx._yaw(fi)
	# the throw: a gust ring off his feet, dust shoved ahead, streaks running out with the funnel
	fx.ring_wall(g + Vector3.UP * 0.05, 0.3, 1.3, 0.3, WIND, WHITE, 0.4, {"bands": 8.0, "scroll": Vector2(1.6, -0.4)})
	fx.burst("dust", g + d * 0.9, d + Vector3.UP * 0.3, DUST, null, {"spread": 0.6, "speed": 1.2, "amount": 0.7})
	fx.burst("wind", fx.anchor(fi, "core"), d, WIND_SOFT, null, {"spread": 0.45, "speed": 1.8, "swirl": 6.0, "amount": 0.6})
	for k in 3:
		fx._wind_streak(g + Vector3.UP * (0.3 + 0.35 * k), yaw + (k - 1) * 0.25, 1.8, 0.3 + 0.05 * k, 0.5 if k % 2 == 0 else -0.5)
	fx.footprint("gale", "circle", g + d, 0.0, 0.8, {"fill": 0.4, "strength": 0.7}, 0.5, 0.1)


## The funnel: an outer spiral widening upward, a counter-turning inner spiral, a banded skin, dust
## skirting its foot and wind climbing it, on its true footprint; it slumps and dissolves where it
## dies down.
func _twister_entity(e: Dictionary) -> Dictionary:
	var r := maxf(float(e.get("radius", 0.7)), 0.3)
	var p: Vector3 = e["pos"]
	var root := Node3D.new()
	fx.add_child(root)
	root.global_position = p
	_face(root, e)
	var base := Node3D.new()                 # on the floor under the projectile's centre
	base.position = Vector3(0, -p.y, 0)
	root.add_child(base)
	var dim := _dim()
	var omat := FxKit.flow_material(FUNNEL, WHITE, {"additive": 0.7, "scroll": Vector2(-2.4, 0.0), "noise_scale": Vector2(8.0, 1.2),
		"edge_v": 0.45, "core": 0.5, "core_width": 0.3, "bands": 3.0, "alpha": 0.95 * dim})
	var outer := _mesh_child(base, FxKit.spiral_mesh(3.0, 0.22, 1.0, 0.24), omat)
	outer.scale = Vector3(r * 1.25, 1.9, r * 1.25)
	var imat := FxKit.flow_material(Color(0.55, 0.88, 0.92, 0.9), WHITE, {"additive": 0.8, "scroll": Vector2(-3.0, 0.0), "noise_scale": Vector2(6.0, 1.0),
		"edge_v": 0.45, "core": 0.5, "core_width": 0.3, "bands": 2.0, "alpha": 0.8 * dim})
	var inner := _mesh_child(base, FxKit.spiral_mesh(2.2, 0.12, 0.6, 0.2), imat)
	inner.scale = Vector3(r, 1.6, r)
	var smat := FxKit.flow_material(Color(0.42, 0.78, 0.82, 0.6), WHITE, {"additive": 0.5, "scroll": Vector2(1.2, -1.5), "noise_scale": Vector2(10.0, 2.0),
		"edge_v": 0.35, "core": 0.3, "core_width": 0.3, "bands": 4.0, "alpha": 0.35 * dim})
	var skin := _mesh_child(base, FxKit.wall_mesh(32, 2.6), smat)
	skin.scale = Vector3(r * 0.42, 1.85, r * 0.42)
	var fp := fx.footprint("gale", "circle", Vector3.ZERO, 0.0, r * 1.1, {"fill": 0.4, "strength": 0.75}, INF)
	fp.reparent(root)                        # flat on the floor (the funnel sways, its footprint does not)
	fp.position = Vector3(0, 0.02 - p.y, 0)
	var dust := fx._attached_stream(base, "dust", DUST, null, {"ring": true, "radius": r * 0.6, "swirl": 7.0, "speed": 0.4, "amount": 0.5})
	var gusts := fx._attached_stream(root, "wind", WIND_SOFT, null, {"dir": Vector3.UP, "speed": 0.6, "swirl": 10.0, "radius": r * 0.5, "amount": 0.6})
	var t0 := fx._clock
	var st := {"next": 0.2}
	return {"node": root, "kind": "projectile", "pos": p, "dir": Vector3.FORWARD,
		"tick": func(_e2: Dictionary) -> void:
			var t := fx._clock - t0
			var grow := clampf(t / 0.15, 0.0, 1.0)
			if is_instance_valid(base):
				base.scale = Vector3(0.4 + 0.6 * grow, maxf(grow, 0.05), 0.4 + 0.6 * grow)
				base.rotation = Vector3(0.07 * sin(t * 5.0), 0.0, 0.07 * sin(t * 6.3 + 1.0))     # it sways as it rolls
			if is_instance_valid(outer):
				outer.rotation.y = -t * 10.0
				inner.rotation.y = t * 7.0
				skin.rotation.y = -t * 4.0
			# feathers and down sucked up its throat now and then
			if t >= float(st["next"]) and fx.quality >= 1 and is_instance_valid(base):
				st["next"] = t + 0.3
				fx.burst("feathers", base.global_position + Vector3.UP * 0.2, Vector3.UP, FEATHER, FEATHER_B, {"spread": 0.6, "speed": 1.5, "amount": 0.1, "floor": 0.0}),
		"end": func() -> void:
			_release_stream(dust)
			_release_stream(gusts)
			if not is_instance_valid(root):
				return
			var fmat: ShaderMaterial = fp.material_override as ShaderMaterial if is_instance_valid(fp) else null
			fx.animate(root, 0.35, func(k: float, _t: float) -> void:
				base.scale = Vector3(1.0 + 0.5 * k, maxf(0.05, 1.0 - 0.8 * k), 1.0 + 0.5 * k)      # it slumps and spreads
				omat.set_shader_parameter("dissolve", k)
				imat.set_shader_parameter("dissolve", k)
				smat.set_shader_parameter("alpha", 0.35 * dim * (1.0 - k))
				if fmat != null:
					fmat.set_shader_parameter("fade", 0.75 * (1.0 - k)))}


## The funnel settling into its whirl (or a dodge leaving one): dust thrown out in a ring, pulled
## in instead for the storm's eye.
func _eddy_burst(pos: Vector3, r: float, pull: bool) -> void:
	var g := Vector3(pos.x, 0.0, pos.z)
	fx.ring_wall(g + Vector3.UP * 0.04, r if pull else 0.3, 0.3 if pull else r, 0.4, WIND, WHITE, 0.45, {"bands": 7.0, "scroll": Vector2(-1.4, 0.0)})
	fx.burst("dust", g + Vector3.UP * 0.1, Vector3.UP, DUST, null, {"ring": true, "radius": r * 0.6, "swirl": 7.0, "speed": -0.5 if pull else 0.7, "amount": 0.7})
	fx.burst("wind", g + Vector3.UP * 0.5, Vector3.UP, WIND_SOFT, null, {"ring": true, "radius": r * 0.5, "swirl": 9.0, "speed": 0.8})
	fx.burst("feathers", g + Vector3.UP * 0.6, Vector3.UP, FEATHER, FEATHER_B, {"amount": 0.25, "speed": 0.9, "floor": 0.0})


## A lingering whirl (the gale_vortex the Twister or a slipstream dodge leaves): a low turning spiral
## on its true circle, wind circling it outward, or inward for the storm's eye, which turns the
## other way and draws its spiral in.
func _eddy_entity(e: Dictionary, pull: bool) -> Dictionary:
	var r := maxf(float(e.get("radius", 1.3)), 0.3)
	var p: Vector3 = e["pos"]
	var root := Node3D.new()
	fx.add_child(root)
	root.global_position = Vector3(p.x, 0.0, p.z)
	var dim := _dim()
	var mat := FxKit.flow_material(Color(0.34, 0.75, 0.79, 0.85), WHITE, {"additive": 0.6, "scroll": Vector2(1.8 if pull else -1.8, 0.0),
		"noise_scale": Vector2(7.0, 1.2), "edge_v": 0.45, "core": 0.5, "core_width": 0.3, "bands": 3.0, "alpha": 0.8 * dim})
	var swirl := _mesh_child(root, FxKit.spiral_mesh(1.8, 1.0 if pull else 0.35, 0.3 if pull else 1.0, 0.3), mat)
	swirl.scale = Vector3(r, 0.55 if not pull else 0.8, r)
	var fp := fx.footprint("gale", "circle", Vector3.ZERO, 0.0, r, {"fill": 0.4, "strength": 0.7}, INF)
	fp.reparent(root)
	fp.position = Vector3.UP * 0.02
	var fmat := fp.material_override as ShaderMaterial
	var gp := fx._attached_stream(root, "wind", WIND_SOFT, null, {"ring": true, "radius": r * 0.9, "swirl": 9.0, "speed": -0.6 if pull else 0.35, "amount": 0.4})
	var t0 := fx._clock
	return {"node": root, "kind": "zone", "pos": p,
		"tick": func(_e2: Dictionary) -> void:
			var t := fx._clock - t0
			if is_instance_valid(swirl):
				swirl.rotation.y = t * (7.0 if pull else -5.0)
				swirl.scale.y = (0.8 if pull else 0.55) * clampf(t / 0.2, 0.1, 1.0),
		"end": func() -> void:
			_release_stream(gp)
			if is_instance_valid(root):
				fx.animate(root, 0.45, func(k: float, _t: float) -> void:
					mat.set_shader_parameter("dissolve", k)
					fmat.set_shader_parameter("fade", 0.7 * (1.0 - k)))}


# =====================================================================================
# Tailwind: the wind at his back
# =====================================================================================

func _tailwind(fi: int, ev: Dictionary) -> void:
	var g := fx._ground(fi)
	var back := -aim_dir(fi)
	# the beat: a gust ring off his feet, a spiral of wind climbing him, feathers torn loose behind
	fx.ring_wall(g + Vector3.UP * 0.05, 0.3, 1.4, 0.45, WIND, WHITE, 0.45, {"bands": 10.0, "scroll": Vector2(2.0, -0.6)})
	var sp := fx.vortex(g, 0.7, 1.9, Color(0.35, 0.76, 0.8, 0.85), WHITE, 0.5, {"turns": 2.8, "r0": 0.45, "spin": 12.0, "grow": 0.3, "add": true})
	fx.follow(sp, fi, "__ground", Vector3.ZERO, 0.5)
	fx.burst("feathers", fx.anchor(fi, "core"), back + Vector3.UP * 0.6, FEATHER, FEATHER_B, {"amount": 0.6, "speed": 1.4, "floor": g.y})
	fx.burst("wind", g + Vector3.UP * 0.6 + back * 0.3, back, WIND_SOFT, null, {"spread": 0.6, "speed": 2.2})
	fx.footprint("gale", "circle", g, 0.0, 1.2, {"fill": 0.4, "strength": 0.8}, 0.6, 0.12)
	fx.flash_light(fx.anchor(fi, "core"), Color(0.6, 0.95, 1.0), 1.8, 3.0, 0.25)
	_start_slipstream(fi, _tailwind_duration(fi, ev))


## How long the buff lasts: the event's own duration when it carries one, else the status in the
## fighter's content.
func _tailwind_duration(fi: int, ev: Dictionary) -> float:
	if ev.has("duration"):
		return float(ev["duration"])
	var st = _pool_effect(fi, "tailwind", "gusto_tailwind").get("status", {})
	return float((st as Dictionary).get("duration", 4.0)) if typeof(st) == TYPE_DICTIONARY else 4.0


## While Tailwind lasts: contrails off both wing tips whenever he moves fast, and wind streaming off
## his back. It ends with the buff (or when he is knocked out of the fight).
func _start_slipstream(fi: int, dur: float) -> void:
	_end_slipstream(fi, true)
	var trails: Array = []
	if fx.quality >= 1:
		for w in ["wing_edge_l", "wing_edge_r"]:
			trails.append(_trail_new(fi, str(w), 0.075, 0.3, Color(0.62, 0.92, 0.95, 0.75)))
	var gp := fx._stream_at(fi, "core", Vector3(0, -0.04, -0.3), dur, "wind", WIND_SOFT, null,
		{"dir": -aim_dir(fi), "speed": 0.8, "amount": 0.4, "spread": 0.35, "swirl": 2.0}, "gusto_tailwind")
	_winds[fi] = {"until": fx._clock + dur, "ending": false, "trails": trails, "stream": gp}


## Ends a slipstream: at once (`now`, a new cast) or letting its contrails fade out.
func _end_slipstream(fi: int, now: bool) -> void:
	var wd: Dictionary = _winds.get(fi, {})
	if wd.is_empty():
		return
	fx.release(fi, "gusto_tailwind")
	if not now:
		wd["ending"] = true
		return
	for tr in wd["trails"]:
		if is_instance_valid(tr["rib"]):
			(tr["rib"] as Node).queue_free()
	_winds.erase(fi)


## Quick Draft's dart along the stick: streaks running the way he went, feathers and dust left behind.
func _tailwind_dart(fi: int, ev: Dictionary) -> void:
	var d: Vector3 = ev.get("dir", aim_dir(fi))
	d.y = 0.0
	d = d.normalized() if d.length_squared() > 1e-4 else aim_dir(fi)
	var g := fx._ground(fi)
	var yaw := atan2(d.x, d.z)
	for k in 3:
		fx._wind_streak(g + Vector3.UP * (0.4 + 0.3 * k) - d * 0.5, yaw, 1.8, 0.24, 0.15 * (k - 1))
	fx.burst("feathers", fx.anchor(fi, "core"), -d + Vector3.UP * 0.4, FEATHER, FEATHER_B, {"amount": 0.3, "speed": 1.0, "floor": g.y})
	fx.burst("dust", g, -d + Vector3.UP * 0.3, DUST, null, {"amount": 0.4, "speed": 0.8})


# =====================================================================================
# Hang Time's Lift-off Gust (style)
# =====================================================================================

func _liftoff(fi: int, pos: Vector3, r: float) -> void:
	var g := Vector3(pos.x, 0.0, pos.z)
	# the take-off beat slams the air down and out: its true circle, a low shock ring, dust and down
	fx.footprint("gale", "circle", g, 0.0, r, {"fill": 0.5}, 0.6, 0.08)
	fx.ring_wall(g + Vector3.UP * 0.04, 0.25, r, 0.35, WIND, WHITE, 0.4, {"bands": 9.0, "scroll": Vector2(1.5, -0.5), "expand": 0.4})
	fx.burst("dust", g + Vector3.UP * 0.05, Vector3.UP, DUST, null, {"ring": true, "radius": r * 0.5, "speed": 1.4, "amount": 0.8})
	fx.burst("wind", fx.anchor(fi, "core"), Vector3.DOWN, WIND_SOFT, null, {"spread": 1.1, "speed": 1.6, "amount": 0.6})
	fx.burst("feathers", fx.anchor(fi, "core"), Vector3.UP, FEATHER, FEATHER_B, {"amount": 0.35, "speed": 1.0, "floor": g.y})


# =====================================================================================
# Shared pieces
# =====================================================================================

func _dim() -> float:
	return 0.75 if fx.reduce_flashes else 1.0


func _alive(fi: int) -> bool:
	var inf := fx._info(fi)
	return not inf.is_empty() and not bool(inf.get("out", false)) and not bool(inf.get("hidden", false)) and fx._view(fi) != null


func _floor_of(ev: Dictionary) -> float:
	var ti := int(ev.get("target", -1))
	return fx._ground(ti).y if ti >= 0 else 0.0


## The MoveDef of one of the fighter's pool moves, from the view's own content (null if unknown).
func _pool_move(fi: int, pool: String) -> MoveDef:
	var v := fx._view(fi)
	if v == null or v.creature == null:
		return null
	var pm: PoolMove = v.creature.pool.get(pool)
	return pm.move if pm != null else null


## The effect of a pool move with this vfx name ({} when not found).
func _pool_effect(fi: int, pool: String, vfx: String) -> Dictionary:
	var m := _pool_move(fi, pool)
	if m == null:
		return {}
	for e in m.effects:
		if typeof(e) == TYPE_DICTIONARY and str((e as Dictionary).get("vfx", "")) == vfx:
			return e
	return {}


## When a pool move's first effect fires (its wind-up), from the fighter's content.
func _lead(fi: int, pool: String) -> float:
	var m := _pool_move(fi, pool)
	return AbilityVfx.first_effect_t(m) if m != null else 0.25


func _mesh_child(parent: Node3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Points a projectile's look along its flight from the first frame (the views keep it so).
func _face(node: Node3D, e: Dictionary) -> void:
	var v: Vector3 = e.get("vel", Vector3.ZERO)
	if v.length_squared() > 1e-6:
		var dn := v.normalized()
		node.global_basis = Basis.looking_at(dn, Vector3.UP if absf(dn.y) < 0.95 else Vector3.RIGHT)


## Lets an entity's attached particles fade where they are instead of vanishing with it.
func _release_stream(gp: GPUParticles3D) -> void:
	if gp == null or not is_instance_valid(gp):
		return
	var gpos := gp.global_position
	gp.reparent(fx)
	gp.global_position = gpos
	fx.end_stream(gp)


## The Air Slash whip: the left wing tip leaves a trail from `delay` for `length` seconds.
func _start_swing(fi: int, delay: float, length: float) -> void:
	var old: Dictionary = _swings.get(fi, {})
	if not old.is_empty() and is_instance_valid(old["rib"]):
		(old["rib"] as Node).queue_free()
	_swings.erase(fi)
	if fx.quality <= 0:
		return
	var tr := _trail_new(fi, "wing_edge_l", 0.16, 0.12, Color(0.55, 0.9, 0.95, 0.9))
	tr["t0"] = fx._clock + delay
	tr["t1"] = fx._clock + delay + length
	_swings[fi] = tr


## A ribbon traced by one of a fighter's anchors (a wing tip): it samples the anchor while it
## emits (when it has moved) and fades `life` seconds behind it. Its arrays are reused.
func _trail_new(fi: int, anchor_name: String, width: float, life: float, c: Color) -> Dictionary:
	return {"rib": fx.ribbon(c, WHITE, true), "fi": fi, "anchor": anchor_name, "w": width, "life": life,
		"pts": [], "ts": [], "dp": [], "dw": [], "da": []}


## One frame of a trail. Returns false once it is `over` and has faded out (its ribbon is freed).
func _trail_step(tr: Dictionary, emit: bool, over: bool) -> bool:
	var rib: MeshInstance3D = tr["rib"]
	if not is_instance_valid(rib):
		return false
	var now := fx._clock
	var pts: Array = tr["pts"]
	var ts: Array = tr["ts"]
	if emit:
		var p := fx.anchor(int(tr["fi"]), str(tr["anchor"]))
		var last: Vector3 = pts[pts.size() - 1] if not pts.is_empty() else Vector3(INF, INF, INF)
		if last.distance_squared_to(p) > 0.0004:
			pts.append(p)
			ts.append(now)
	var life := float(tr["life"])
	while not ts.is_empty() and now - float(ts[0]) > life:
		pts.pop_front()
		ts.pop_front()
	var n := pts.size()
	if n < 2:
		(rib.mesh as ImmediateMesh).clear_surfaces()
		if over:
			rib.queue_free()
			return false
		return true
	var dp: Array = tr["dp"]
	var dw: Array = tr["dw"]
	var da: Array = tr["da"]
	dp.resize(n)
	dw.resize(n)
	da.resize(n)
	var w := float(tr["w"])
	var dim := _dim()
	for i in n:
		var k := clampf(1.0 - (now - float(ts[i])) / life, 0.0, 1.0)
		dp[i] = pts[i]
		dw[i] = w * k
		da[i] = k * dim
	fx.draw_ribbon(rib, dp, dw, da)
	return true


## A bright arc swept around `c` (a wing's whip): from yaw offset a0 to a1 (radians from the facing),
## tilting from h0 to h1 metres above c, its head running ahead of a fading tail, in `dur` seconds.
func _cut_arc(c: Vector3, yaw: float, r: float, a0: float, a1: float, h0: float, h1: float, dur: float, width: float) -> void:
	if fx.quality <= 0:
		return
	var mi := fx.ribbon(EDGE, WHITE, true)
	var n := 12
	var pts := []
	var w := []
	var al := []
	pts.resize(n)
	w.resize(n)
	al.resize(n)
	var dim := _dim()
	fx.animate(mi, dur, func(k: float, _t: float) -> void:
		var head := clampf(k * 1.5, 0.0, 1.0)
		var tail := clampf(k * 1.5 - 0.5, 0.0, 1.0)
		var fade := (1.0 - smoothstep(0.6, 1.0, k)) * dim
		for i in n:
			var f := float(i) / float(n - 1)
			var u := lerpf(tail, head, f)
			var a := yaw + lerpf(a0, a1, u)
			pts[i] = c + Vector3(sin(a) * r, lerpf(h0, h1, u), cos(a) * r)
			w[i] = width * f
			al[i] = f * fade
		fx.draw_ribbon(mi, pts, w, al))


## A straight cut flashing from a to b (a crescent stamped across its target).
func _cut_line(a: Vector3, b: Vector3, dur: float, width: float) -> void:
	if fx.quality <= 0:
		return
	var mi := fx.ribbon(EDGE, WHITE, true)
	var pts := [a, a, a]
	var w := [0.0, width, 0.0]
	var al := [0.0, 0.0, 0.0]
	var dim := _dim()
	fx.animate(mi, dur, func(k: float, _t: float) -> void:
		var reach := clampf(k * 3.0, 0.0, 1.0)
		pts[1] = a.lerp(b, reach * 0.5)
		pts[2] = a.lerp(b, reach)
		var fade := (1.0 - smoothstep(0.4, 1.0, k)) * dim
		al[0] = fade * 0.3
		al[1] = fade
		al[2] = fade * 0.6
		fx.draw_ribbon(mi, pts, w, al))


# =====================================================================================
# Meshes (built once per kit, shared by every instance)
# =====================================================================================

## The Air Slash blade: a crescent in the XZ plane flying toward -Z (its node's forward), belly ahead
## at the origin, horns trailing; u runs along the arc, v across the blade (0 = the cutting edge).
func _crescent_mesh() -> ArrayMesh:
	if _crescent != null:
		return _crescent
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 24
	var rc := 0.58
	var half := deg_to_rad(64.0)
	var prev_a := Vector3.ZERO
	var prev_b := Vector3.ZERO
	for i in steps + 1:
		var u := float(i) / float(steps)
		var th := lerpf(-half, half, u)
		var nrm := Vector3(sin(th), 0.0, -cos(th))
		var c := Vector3(0.0, 0.0, rc) + nrm * rc
		var w := 0.2 * pow(maxf(cos(th / half * PI * 0.5), 0.0), 0.7)
		var a := c + nrm * w * 0.35
		var b := c - nrm * w * 0.65
		if i > 0:
			var u0 := float(i - 1) / float(steps)
			for v in [[prev_a, Vector2(u0, 0)], [b, Vector2(u, 1)], [prev_b, Vector2(u0, 1)], [prev_a, Vector2(u0, 0)], [a, Vector2(u, 0)], [b, Vector2(u, 1)]]:
				st.set_uv(v[1])
				st.add_vertex(v[0])
		prev_a = a
		prev_b = b
	st.generate_normals()
	_crescent = st.commit()
	return _crescent


## A streak of air one metre long along +Z, tapering to nothing: two crossed strips (flat and upright)
## so it reads from any side; u runs along it.
func _streak_mesh() -> ArrayMesh:
	if _streak != null:
		return _streak
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 6
	for across in [Vector3.RIGHT, Vector3.UP]:
		var x: Vector3 = across
		for i in steps:
			var z0 := float(i) / float(steps)
			var z1 := float(i + 1) / float(steps)
			var a0 := Vector3(0, 0, z0) - x * 0.5 * (1.0 - z0)
			var b0 := Vector3(0, 0, z0) + x * 0.5 * (1.0 - z0)
			var a1 := Vector3(0, 0, z1) - x * 0.5 * (1.0 - z1)
			var b1 := Vector3(0, 0, z1) + x * 0.5 * (1.0 - z1)
			for v in [[a0, Vector2(z0, 0)], [b1, Vector2(z1, 1)], [b0, Vector2(z0, 1)], [a0, Vector2(z0, 0)], [a1, Vector2(z1, 0)], [b1, Vector2(z1, 1)]]:
				st.set_uv(v[1])
				st.add_vertex(v[0])
	st.generate_normals()
	_streak = st.commit()
	return _streak


## A feather dart along -Z: two crossed vanes, dark tip, cream vane, grey-teal tail (vertex colours).
func _dart_mesh() -> ArrayMesh:
	if _dart != null:
		return _dart
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tip := Vector3(0, 0, -0.18)
	var tail := Vector3(0, 0, 0.17)
	for across in [Vector3.RIGHT, Vector3.UP]:
		var x: Vector3 = across
		var l1 := Vector3(0, 0, -0.04) + x * 0.036
		var r1 := Vector3(0, 0, -0.04) - x * 0.036
		var l2 := Vector3(0, 0, 0.1) + x * 0.03
		var r2 := Vector3(0, 0, 0.1) - x * 0.03
		_tri(st, tip, l1, r1, QUILL, FEATHER, FEATHER)
		_tri(st, l1, l2, r1, FEATHER, FEATHER_B, FEATHER)
		_tri(st, r1, l2, r2, FEATHER, FEATHER_B, FEATHER_B)
		_tri(st, l2, tail, r2, FEATHER_B, QUILL, FEATHER_B)
	_dart = st.commit()
	return _dart


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)


func _dart_material() -> StandardMaterial3D:
	if _dart_mat == null:
		_dart_mat = StandardMaterial3D.new()
		_dart_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED     # flat feathers read in any light
		_dart_mat.vertex_color_use_as_albedo = true
		_dart_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _dart_mat


func _dart_tail_material() -> ShaderMaterial:
	if _dart_tail_mat == null:
		_dart_tail_mat = FxKit.flow_material(Color(0.55, 0.88, 0.92, 0.7), WHITE, {"additive": 0.7, "scroll": Vector2(-3.0, 0.0),
			"noise_scale": Vector2(3.0, 1.0), "edge_v": 0.5, "edge_u": 0.15, "core": 0.5, "core_width": 0.3, "alpha": 0.6 * _dim()})
	return _dart_tail_mat
