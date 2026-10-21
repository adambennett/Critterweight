extends MoveFxKit
## Dozer's Movesets effects (v0.9.18): the Rock Slide fault line and the boulders it heaves up as
## cover, the Boulder Toss (dug out of the floor, carried on the shovel snout, flung tumbling,
## shattering into gravel), the Quake Stomp ring and Iron Hide's clamped plates, plus the looks of
## the Scree Field, Aftershock and Spiked Plates styles. Crushing-debris identity: rock that splits
## along cracks, gravel that tumbles and settles, dust that rolls low and heavy, and an armoured
## digger's weight behind every piece. Grit never glows; only struck iron glints.
##
## The cover boulders are prop entities, and a prop's entity vfx is its kind ("boulder"), so the
## v0.9.17 prop look draws the rock itself; this kit draws its arrival, its cracked footing and the
## rubble skirt at its foot, which crumbles when the boulder breaks or expires.

const ROCK := Color(0.44, 0.37, 0.3)
const ROCK_LIGHT := Color(0.64, 0.54, 0.42)
const GRAVEL := Color(0.58, 0.47, 0.34)
const GRAVEL_LIGHT := Color(0.8, 0.68, 0.5)
const DUST := Color(0.74, 0.62, 0.46, 0.55)
const DUST_DARK := Color(0.52, 0.43, 0.32, 0.6)
const IRON := Color(0.58, 0.6, 0.64)
const IRON_GLINT := Color(1.0, 0.93, 0.72)

var _winds := {}         ## fighter -> {id, t, seen}: the wind-up being drawn (its telegraph ends at contact or when cut off)
var _held := {}          ## fighter -> {node, t, dig, lead, dug, seen}: the boulder riding the snout before the toss
var _hides := {}         ## fighter -> {node, mat, t, dur, next}: Iron Hide's clamped plates
var _skirts: Array = []  ## [{node, pos, t, life, next}]: rubble at the foot of a cover boulder


func vfx_names() -> Array:
	return ["dozer_rockslide", "dozer_rockslide_rock", "dozer_scree", "dozer_boulder", "dozer_boulder_shatter",
		"dozer_quake", "dozer_aftershock", "dozer_iron_hide", "dozer_spikes"]


## The move a pool move performs, from the fighter's view (null when unknown).
func _pool_def(fi: int, id: String) -> MoveDef:
	var v := fx._view(fi)
	if v == null or v.creature == null:
		return null
	var pm: PoolMove = v.creature.pool.get(id)
	return pm.move if pm != null else null


# =====================================================================================
# Wind-ups (move start .. contact)
# =====================================================================================

func on_move_start(fi: int, ev: Dictionary) -> bool:
	_end_wind(fi)
	_drop_held(fi, true)
	var id := str(ev.get("pool", ""))
	match id:
		"rock_slide":
			_dig_in(fi, _pool_def(fi, id))
		"boulder_toss":
			_pick_up(fi, _pool_def(fi, id))
		"quake_stomp":
			_gather(fi, _pool_def(fi, id))
		"iron_hide":
			_hunker(fi)
		_:
			return false
	_winds[fi] = {"id": id, "t": 0.0, "seen": false}
	return false        # the generic move-start bookkeeping still runs


## Rock Slide: a fore-hoof scrapes grit back, the shovel snout bites into the floor, and the fault
## line's true footprint creeps out ahead of him until it erupts.
func _dig_in(fi: int, m: MoveDef) -> void:
	var lead := AbilityVfx.first_effect_t(m) if m != null else 0.3
	var line := AbilityVfx.effect_of(m, "area")
	fx._warn(fi, "grit", "line", 0.0, {"length": float(line.get("length", 5.0)), "width": float(line.get("width", 1.3)),
		"fill": 0.18, "front": 0.35, "strength": 0.55}, lead, lead * 2.0, true)
	fx.burst("dust", fx.anchor(fi, "hoof_fr"), -aim_dir(fi) + Vector3.UP * 0.4, DUST, null, {"amount": 0.45, "speed": 0.7})
	fx._later(lead * 0.62, func() -> void:
		if is_acting(fi):
			var s := fx.anchor(fi, "snout")
			var fy := fx._ground(fi).y
			fx.burst("pebbles", s, aim_dir(fi) + Vector3.UP, GRAVEL, GRAVEL_LIGHT, {"amount": 0.5, "speed": 0.8, "floor": fy})
			fx.burst("dust", s, Vector3.UP, DUST_DARK, null, {"amount": 0.4, "speed": 0.5})
			fx.footprint("grit", "circle", Vector3(s.x, fy, s.z), 0.0, 0.45, {"fill": 0.8, "front": 0.6, "stain_a": 0.5}, 1.0, 0.08))


## Boulder Toss: the snout digs in and a boulder comes up on it, riding the shovel until the fling
## (grown and dropped in _update_held).
func _pick_up(fi: int, m: MoveDef) -> void:
	var lead := AbilityVfx.first_effect_t(m) if m != null else 0.4
	var r := float(AbilityVfx.effect_of(m, "projectile").get("radius", 0.36))
	var rock := _rock(fx, r, 2 if fx.quality >= 1 else 1)
	rock.scale = Vector3.ONE * 0.01
	fx.follow(rock, fi, "snout", Vector3(0, 0.04 + r * 0.7, -0.06), lead * 2.0 + 0.5)
	_held[fi] = {"node": rock, "t": 0.0, "dig": lead * 0.3, "lead": lead, "dug": false, "seen": false}


## Quake Stomp: loose grit hops on the trembling floor around him, the true ring creeps out under
## him, and dust bursts off the floor as he bounds up.
func _gather(fi: int, m: MoveDef) -> void:
	var lead := AbilityVfx.first_effect_t(m) if m != null else 0.48
	var r := float(AbilityVfx.effect_of(m, "area").get("radius", 2.4))
	var cap := lead * 2.0
	var v := fx._view(fi)
	if m != null and v != null and v.creature != null and v.creature.pool.has("quake_stomp"):
		var pm: PoolMove = v.creature.pool["quake_stomp"]
		if pm.hold == "charge":
			cap += m.charge_time      # Seismic Charge: he may hang at the top of the bound
	fx._warn(fi, "grit", "circle", r, {"fill": 0.1, "front": 0.3, "strength": 0.45}, lead, cap)
	for k in 2:
		fx._later(lead * (0.1 + 0.3 * k), func() -> void:
			if is_acting(fi):
				var g := fx._ground(fi)
				fx.burst("pebbles", g + Vector3.UP * 0.04, Vector3.UP, GRAVEL, GRAVEL_LIGHT, {"radius": r * 0.8, "amount": 0.3, "speed": 0.35, "floor": g.y}))
	fx._later(lead * 0.6, func() -> void:
		if is_acting(fi):
			fx.burst("dust", fx._ground(fi), Vector3.UP, DUST, null, {"ring": true, "radius": 0.7, "amount": 0.55, "speed": 0.8}))


## Iron Hide: dust and grit shaken off his back as he hunkers down.
func _hunker(fi: int) -> void:
	var c := fx.anchor(fi, "core")
	fx.burst("dust", c + Vector3.UP * 0.2, Vector3.UP, DUST, null, {"radius": 0.45, "amount": 0.5, "speed": 0.6})
	fx.burst("pebbles", c + Vector3.UP * 0.3, Vector3.UP, GRAVEL, GRAVEL_LIGHT, {"radius": 0.35, "amount": 0.3, "speed": 0.5, "floor": fx._ground(fi).y})


## The wind-up of fighter fi is over (its move made contact, was cut off, or another began): its
## telegraph fades.
func _end_wind(fi: int) -> void:
	if _winds.erase(fi):
		fx.release(fi, "prep")


# =====================================================================================
# Contact (effect events)
# =====================================================================================

func on_effect(fi: int, ev: Dictionary) -> bool:
	var pos: Vector3 = ev.get("pos", fx._ground(fi))
	var r := float(ev.get("radius", 0.0))
	match str(ev.get("vfx", "")):
		"dozer_rockslide":
			_end_wind(fi)
			_fault_line(fi, ev)
		"dozer_rockslide_rock":
			_heave(pos, maxf(r * 0.5, 0.25), float(ev.get("duration", 3.0)))
		"dozer_scree":
			# the rubble the rocks crumble into (the patch itself is the zone entity)
			fx.burst("pebbles", Vector3(pos.x, 0.15, pos.z), Vector3.UP, GRAVEL, GRAVEL_LIGHT, {"radius": r * 0.6, "amount": 0.5, "speed": 0.8, "floor": 0.0})
			fx.burst("dust", Vector3(pos.x, 0.0, pos.z), Vector3.UP, DUST, null, {"radius": r * 0.6, "amount": 0.45, "speed": 0.5})
		"dozer_boulder":
			_end_wind(fi)
			_fling(fi)
		"dozer_boulder_shatter":
			_shatter(pos, maxf(r, 0.5))
		"dozer_quake":
			_end_wind(fi)
			_quake(Vector3(pos.x, 0.0, pos.z), maxf(r, 0.5))
		"dozer_aftershock":
			_aftershock(Vector3(pos.x, 0.0, pos.z), maxf(r, 0.5), float(ev.get("inner", 0.0)))
		"dozer_iron_hide":
			_end_wind(fi)
			_iron_hide(fi, float(ev.get("duration", 4.0)))
		"dozer_spikes":
			_spikes(fi, pos, r)
		_:
			return false
	return true


## Entity looks: the Boulder Toss rock in flight and a Scree Field patch.
func make_entity(e: Dictionary) -> Dictionary:
	match str(e.get("vfx", "")):
		"dozer_boulder":
			return _boulder(e)
		"dozer_scree":
			return _scree(e)
	return {}


## ---- Rock Slide ----------------------------------------------------------------------------------

## The fault line erupting along the area's true footprint: the crack torn open on the floor, a
## ridge of earth heaving along it and slabs splitting up out of it near to far, leaning away from
## the crack, then settling back.
func _fault_line(fi: int, ev: Dictionary) -> void:
	var o: Vector3 = ev.get("origin", ev.get("pos", fx._ground(fi)))
	var origin := Vector3(o.x, 0.0, o.z)
	var yaw := float(ev.get("yaw", fx._yaw(fi)))
	var length := float(ev.get("length", 5.0))
	var width := float(ev.get("width", 1.3))
	var fwd := MathX.forward_of_yaw(yaw)
	var side := fwd.cross(Vector3.UP).normalized()
	fx.footprint("grit", "line", origin, yaw, 0.0, {"length": length, "width": width, "fill": 0.75, "front": 0.9, "stain_a": 0.5}, 2.2, 0.1)
	fx.crest(origin, yaw, length, width * 0.9, 0.5, ROCK, GRAVEL_LIGHT, 0.12, 0.55, {"depth": 0.7, "scroll": Vector2(-0.3, -0.2)})
	var n := 7 if fx.quality >= 2 else (5 if fx.quality == 1 else 3)
	for k in n:
		var u := (float(k) + 0.5) / float(n)
		var p := origin + fwd * (0.6 + (length - 0.6) * u) + side * fx._rng.randf_range(-0.18, 0.18) * width
		var size := lerpf(0.42, 0.3, u) * fx._rng.randf_range(0.85, 1.15)
		var tilt := 0.32 if k % 2 == 0 else -0.32
		fx._later(u * 0.12, func() -> void: _slab(p, size, yaw, tilt))
	var mid := origin + fwd * length * 0.5
	fx.burst("chunks", mid + Vector3.UP * 0.15, Vector3.UP, ROCK, ROCK_LIGHT, {"box": Vector3(width * 0.4, 0.05, length * 0.45), "yaw": yaw, "speed": 1.0, "floor": 0.0})
	fx.burst("pebbles", mid + Vector3.UP * 0.1, Vector3.UP, GRAVEL, GRAVEL_LIGHT, {"box": Vector3(width * 0.45, 0.05, length * 0.48), "yaw": yaw, "speed": 0.9, "floor": 0.0})
	fx.burst("dust", mid, Vector3.UP, DUST, null, {"box": Vector3(width * 0.5, 0.1, length * 0.5), "yaw": yaw, "speed": 0.6, "amount": 1.0, "scale": 1.2})


## One slab of the fault line splitting up out of the crack, leaning away from it.
func _slab(p: Vector3, size: float, yaw: float, tilt: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = FxKit.piece_mesh("hex")
	mi.material_override = Materials.toon(ROCK, 0.95, 0.0, 0.25)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(mi)
	mi.rotation = Vector3(fx._rng.randf_range(-0.12, 0.12), yaw + fx._rng.randf_range(-0.35, 0.35), tilt)
	var s0 := Vector3(size * 1.1, size * 2.4, size * 0.75)
	fx.burst("pebbles", p + Vector3.UP * 0.1, Vector3.UP, GRAVEL, GRAVEL_LIGHT, {"amount": 0.25, "speed": 0.9, "floor": p.y})
	fx.animate(mi, 1.1, func(k: float, _t: float) -> void:
		var up := clampf(k / 0.07, 0.0, 1.0)
		var sink := smoothstep(0.6, 1.0, k)
		mi.scale = s0 * maxf(up * (1.0 + 0.2 * sin(up * PI)) * (1.0 - sink * 0.5), 0.01)
		mi.global_position = p + Vector3.UP * (s0.y * 0.25 * up - sink * s0.y * 0.55))


## A cover boulder heaving up out of the crack (r: its physical radius): the floor bursting around
## it, its cracked footing (as long as it stands) and the rubble skirt at its foot.
func _heave(p: Vector3, r: float, dur: float) -> void:
	var g := Vector3(p.x, 0.0, p.z)
	var life := maxf(dur, 0.3)
	fx.burst("chunks", g + Vector3.UP * 0.2, Vector3.UP, ROCK, ROCK_LIGHT, {"radius": r, "amount": 0.45, "speed": 0.8, "floor": 0.0})
	fx.burst("dust", g, Vector3.UP, DUST, null, {"ring": true, "radius": r * 1.2, "amount": 0.55, "speed": 0.7})
	fx.ring_wall(g, r * 0.6, r * 2.2, 0.3, DUST_DARK, GRAVEL_LIGHT, 0.35, {"add": false, "core": 0.3, "bands": 0.0})
	fx.footprint("grit", "circle", g, fx._rng.randf() * TAU, r * 2.0, {"fill": 0.7, "front": 0.0, "stain_a": 0.5}, life, 0.06)
	var root := Node3D.new()
	fx.add_child(root)
	root.global_position = g
	var n := 3 if fx.quality >= 1 else 2
	for k in n:
		var a := TAU * (float(k) + fx._rng.randf_range(0.0, 0.5)) / float(n)
		var s := r * fx._rng.randf_range(0.55, 0.8)
		var piece := MeshInstance3D.new()
		piece.mesh = FxKit.piece_mesh("hex")
		piece.material_override = Materials.toon(ROCK_LIGHT if k % 2 == 0 else ROCK, 0.95, 0.0, 0.25)
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		piece.scale = Vector3(s, s * 1.3, s * 0.8)
		piece.position = Vector3(cos(a), 0.0, sin(a)) * r * 1.15 + Vector3.UP * s * 0.25
		piece.rotation = Vector3(fx._rng.randf_range(-0.4, 0.4), a, fx._rng.randf_range(-0.5, 0.5))
		root.add_child(piece)
	root.scale = Vector3(1.0, 0.01, 1.0)
	_skirts.append({"node": root, "pos": g, "t": 0.0, "life": life, "next": 0.3})


## Whether a prop (the boulder a rubble skirt belongs to) is still drawn at p.
func _boulder_at(p: Vector3) -> bool:
	for en in fx._ents.values():
		var d: Dictionary = en
		if str(d.get("kind", "")) != "prop":
			continue
		var q: Vector3 = d.get("pos", Vector3.INF)
		if Vector2(q.x - p.x, q.z - p.z).length() < 0.4:
			return true
	return false


func _update_skirts(delta: float) -> void:
	var i := _skirts.size() - 1
	while i >= 0:
		var sk: Dictionary = _skirts[i]
		var root: Node3D = sk["node"]
		if not is_instance_valid(root):
			_skirts.remove_at(i)
			i -= 1
			continue
		var t := float(sk["t"]) + delta
		sk["t"] = t
		root.scale = Vector3(1.0, clampf(t / 0.1, 0.01, 1.0), 1.0)
		var gone := t >= float(sk["life"])
		if not gone and t >= float(sk["next"]):
			sk["next"] = t + 0.25
			gone = not _boulder_at(sk["pos"])      # broken (or never arrived): it crumbles with it
		if gone:
			_crumble(root, sk["pos"])
			_skirts.remove_at(i)
		i -= 1


## Rubble settling into the floor in a puff of dust (the node frees itself).
func _crumble(root: Node3D, p: Vector3) -> void:
	fx.burst("pebbles", p + Vector3.UP * 0.15, Vector3.UP, GRAVEL, GRAVEL_LIGHT, {"radius": 0.4, "amount": 0.3, "speed": 0.5, "floor": p.y})
	fx.burst("dust", p, Vector3.UP, DUST, null, {"radius": 0.4, "amount": 0.35, "speed": 0.4})
	fx.animate(root, 0.35, func(k: float, _t: float) -> void:
		root.scale = Vector3(1.0 + 0.2 * k, maxf(1.0 - k, 0.01), 1.0 + 0.2 * k))


## A Scree Field patch (zone): a cracked, gravel-strewn floor with a few rocks lying in it.
func _scree(e: Dictionary) -> Dictionary:
	var r := maxf(float(e.get("radius", 0.9)), 0.3)
	var p: Vector3 = e["pos"]
	var root := Node3D.new()
	fx.add_child(root)
	root.global_position = Vector3(p.x, 0.0, p.z)
	var fp := fx.footprint("grit", "circle", Vector3.ZERO, fx._rng.randf() * TAU, r, {"fill": 0.8, "front": 0.0, "stain_a": 0.55}, INF)
	fp.reparent(root)
	fp.position = Vector3.UP * (0.02 + fx._rng.randf() * 0.01)
	var n := 7 if fx.quality >= 2 else (5 if fx.quality == 1 else 3)
	for k in n:
		var a := fx._rng.randf() * TAU
		var d := sqrt(fx._rng.randf()) * r * 0.8
		var s := fx._rng.randf_range(0.1, 0.22)
		var piece := MeshInstance3D.new()
		piece.mesh = FxKit.piece_mesh("hex")
		piece.material_override = Materials.toon(ROCK if k % 2 == 0 else ROCK_LIGHT, 0.95, 0.0, 0.25)
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		piece.scale = Vector3(s, s * 0.7, s)
		piece.position = Vector3(cos(a) * d, s * 0.15, sin(a) * d)
		piece.rotation = Vector3(fx._rng.randf_range(-0.4, 0.4), fx._rng.randf() * TAU, fx._rng.randf_range(-0.4, 0.4))
		root.add_child(piece)
	root.scale = Vector3(1.0, 0.01, 1.0)
	var t0 := fx._clock
	var en := {"node": root, "kind": "zone", "pos": p}
	en["tick"] = func(ze: Dictionary) -> void:
		var q: Vector3 = ze["pos"]
		root.global_position = Vector3(q.x, 0.0, q.z)
		root.scale = Vector3(1.0, clampf((fx._clock - t0) / 0.12, 0.01, 1.0), 1.0)
	en["end"] = func() -> void:
		if not is_instance_valid(root):
			return
		fx.burst("dust", root.global_position, Vector3.UP, DUST, null, {"radius": r * 0.5, "amount": 0.3, "speed": 0.4})
		var mat := fp.material_override as ShaderMaterial
		var f0 := float(mat.get_shader_parameter("fade")) if mat != null else 0.0
		fx.animate(root, 0.4, func(k2: float, _t: float) -> void:
			root.scale = Vector3(1.0, maxf(1.0 - k2, 0.01), 1.0)
			if mat != null:
				mat.set_shader_parameter("fade", f0 * (1.0 - k2)))
	return en


## ---- Boulder Toss --------------------------------------------------------------------------------

## A lumpy boulder about r in radius under `parent`: a big hex chunk with smaller ones stuck on (no
## two alike). Its body casts a shadow: a lobbed rock's shadow on the floor shows where it lands.
func _rock(parent: Node, r: float, knobs: int) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	var body := MeshInstance3D.new()
	body.mesh = FxKit.piece_mesh("hex")
	body.material_override = Materials.toon(ROCK, 0.95, 0.0, 0.3)
	body.scale = Vector3(r * 2.1, r * 1.9, r * 2.0)
	root.add_child(body)
	for k in knobs:
		var kn := MeshInstance3D.new()
		kn.mesh = FxKit.piece_mesh("hex")
		kn.material_override = Materials.toon(ROCK_LIGHT, 0.95, 0.0, 0.3)
		kn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := TAU * float(k) / float(maxi(knobs, 1)) + fx._rng.randf() * 0.8
		kn.position = Vector3(cos(a) * r * 0.75, fx._rng.randf_range(-0.3, 0.5) * r, sin(a) * r * 0.75)
		kn.scale = Vector3.ONE * r * fx._rng.randf_range(0.8, 1.1)
		kn.rotation = Vector3(fx._rng.randf() * TAU, fx._rng.randf() * TAU, 0.0)
		root.add_child(kn)
	return root


func _update_held(delta: float) -> void:
	for fi in _held.keys():
		var h: Dictionary = _held[fi]
		var rock: Node3D = h["node"]
		if not is_instance_valid(rock):
			_held.erase(fi)
			continue
		var t := float(h["t"]) + delta
		h["t"] = t
		var lead := float(h["lead"])
		var acting := is_acting(fi)
		if acting:
			h["seen"] = true          # online the sampled state can trail the move_start event a little
		if (not acting and (bool(h["seen"]) or t > 0.3)) or t > lead * 2.0 + 0.4:
			_drop_held(fi, true)       # cut off (or never thrown): the rock falls apart on his snout
			continue
		var dig := float(h["dig"])
		if t >= dig and not bool(h["dug"]):
			# the shovel bites the floor: grit sprays, the rock comes up out of a fresh pit
			h["dug"] = true
			var s := fx.anchor(fi, "snout")
			var fy := fx._ground(fi).y
			var at := Vector3(s.x, fy, s.z)
			fx.burst("pebbles", at + Vector3.UP * 0.05, Vector3.UP, GRAVEL, GRAVEL_LIGHT, {"amount": 0.5, "speed": 0.7, "floor": fy})
			fx.burst("dust", at, Vector3.UP, DUST, null, {"amount": 0.45, "speed": 0.6})
			fx.footprint("grit", "circle", at, fx._rng.randf() * TAU, 0.5, {"fill": 0.85, "front": 0.5, "stain_a": 0.55}, 1.4, 0.06)
		var k := clampf((t - dig) / maxf(lead * 0.45, 0.05), 0.0, 1.0)
		rock.scale = Vector3.ONE * maxf(k * (1.0 + 0.08 * sin(k * PI)), 0.01)


## Lets go of the rock on the snout: thrown (the projectile takes over) or crumbling (cut off).
func _drop_held(fi: int, crumble: bool) -> void:
	var h: Dictionary = _held.get(fi, {})
	_held.erase(fi)
	if h.is_empty() or not is_instance_valid(h["node"]):
		return
	var rock: Node3D = h["node"]
	if crumble and rock.scale.x > 0.2:
		var p := rock.global_position
		fx.burst("chunks", p, Vector3.UP, ROCK, ROCK_LIGHT, {"amount": 0.45, "speed": 0.6, "floor": fx._ground(fi).y})
		fx.burst("dust", p, Vector3.UP, DUST, null, {"amount": 0.4, "speed": 0.5})
	rock.queue_free()


## The fling: the held rock leaves the snout in a spray of grit.
func _fling(fi: int) -> void:
	_drop_held(fi, false)
	var s := fx.anchor(fi, "snout")
	fx.burst("dust", s, aim_dir(fi, 0.6), DUST, null, {"amount": 0.5, "speed": 0.9, "spread": 0.6})
	fx.burst("pebbles", s, aim_dir(fi, 0.7), GRAVEL, GRAVEL_LIGHT, {"amount": 0.45, "speed": 1.0, "spread": 0.5, "floor": fx._ground(fi).y})


## The Boulder Toss rock in flight: tumbling end over end, shedding grit and a dust wake.
func _boulder(e: Dictionary) -> Dictionary:
	var r := maxf(float(e.get("radius", 0.36)), 0.12)
	var root := Node3D.new()
	fx.add_child(root)
	root.global_position = e["pos"]
	var rock := _rock(root, r, 2 if fx.quality >= 1 else 1)
	var dust := fx._attached_stream(root, "dust", DUST, null, {"speed": 0.15, "amount": 0.4, "scale": 0.7, "radius": r * 0.5})
	var grit := fx._attached_stream(root, "pebbles", GRAVEL, GRAVEL_LIGHT, {"dir": Vector3.DOWN, "speed": 0.2, "amount": 0.3, "floor": 0.0})
	var spin := Vector3(fx._rng.randf_range(6.0, 9.0), fx._rng.randf_range(-2.0, 2.0), fx._rng.randf_range(-3.0, 3.0))
	var t0 := fx._clock
	var en := {"node": root, "kind": "projectile", "pos": e["pos"], "dir": Vector3.FORWARD}
	en["tick"] = func(_e2: Dictionary) -> void:
		if is_instance_valid(rock):
			rock.rotation = spin * (fx._clock - t0)
	en["end"] = func() -> void:
		_let_go(dust)
		_let_go(grit)
		if is_instance_valid(root):
			# a quiet crumble wherever it stopped: a hit or a landing draws the real break
			fx.burst("dust", root.global_position, Vector3.UP, DUST, null, {"amount": 0.3, "speed": 0.5})
			root.queue_free()
	return en


## Ends a trail emitter where it is (its last particles fade in place).
func _let_go(gp: GPUParticles3D) -> void:
	if gp == null or not is_instance_valid(gp):
		return
	var at := gp.global_position
	gp.reparent(fx)
	gp.global_position = at
	fx.end_stream(gp)


## A boulder that hit the floor bursting into gravel inside the true circle of its splash.
func _shatter(pos: Vector3, r: float) -> void:
	var g := Vector3(pos.x, 0.0, pos.z)
	fx.burst("chunks", g + Vector3.UP * 0.25, Vector3.UP, ROCK, ROCK_LIGHT, {"amount": 0.9, "speed": 1.1, "spread": 1.0, "floor": 0.0, "scale": 1.3})
	fx.burst("pebbles", g + Vector3.UP * 0.15, Vector3.UP, GRAVEL, GRAVEL_LIGHT, {"radius": r * 0.4, "amount": 0.8, "speed": 1.1, "floor": 0.0})
	fx.burst("dust", g + Vector3.UP * 0.1, Vector3.UP, DUST, null, {"ring": true, "radius": r * 0.5, "amount": 0.8, "speed": 0.9, "scale": 1.3})
	fx.ring_wall(g, 0.2, r, 0.35, DUST_DARK, GRAVEL_LIGHT, 0.4, {"add": false, "core": 0.3, "bands": 0.0})
	fx.footprint("grit", "circle", g, fx._rng.randf() * TAU, r, {"fill": 0.6, "front": 0.9, "stain_a": 0.5}, 1.3, 0.08)
	_halves(g, 3 if fx.quality >= 1 else 2, 0.4)


## Big rock fragments thrown out of a break: they tumble a short way, lie still, then sink away.
func _halves(p: Vector3, n: int, r: float) -> void:
	for k in n:
		var mi := MeshInstance3D.new()
		mi.mesh = FxKit.piece_mesh("hex")
		mi.material_override = Materials.toon(ROCK if k % 2 == 0 else ROCK_LIGHT, 0.95, 0.0, 0.3)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fx.add_child(mi)
		var a := TAU * (float(k) + fx._rng.randf_range(0.0, 0.6)) / float(n)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var s := r * fx._rng.randf_range(0.5, 0.65)
		var spin := Vector3(fx._rng.randf_range(-9.0, 9.0), fx._rng.randf_range(-4.0, 4.0), fx._rng.randf_range(-9.0, 9.0))
		var reach := fx._rng.randf_range(0.8, 1.3)
		fx.animate(mi, 1.3, func(k2: float, t: float) -> void:
			var tf := minf(t, 0.42)               # in the air for 0.42 s, then it lies there
			var hop := maxf(0.0, 2.06 * tf - 4.9 * tf * tf)
			var sink := smoothstep(0.7, 1.0, k2)
			mi.global_position = p + dir * reach * (tf / 0.42) + Vector3.UP * (s * 0.3 + hop - sink * s * 0.8)
			mi.rotation = spin * tf
			mi.scale = Vector3.ONE * s * (1.0 - sink * 0.6))


## ---- Quake Stomp ---------------------------------------------------------------------------------

## The quake: the cracked disc under him and cracks running out to the edge of the true ring, a
## low wave of earth and dust rolling out to it, and gravel jumping off the whole floor inside.
func _quake(g: Vector3, r: float) -> void:
	fx.footprint("grit", "circle", g, 0.0, r, {"fill": 0.5, "front": 1.0, "stain_a": 0.5}, 1.6, 0.16)
	var n := 8 if fx.quality >= 1 else 5
	var a0 := fx._rng.randf() * TAU
	for k in n:
		var a := a0 + TAU * float(k) / float(n) + fx._rng.randf_range(-0.2, 0.2)
		fx.footprint("grit", "line", g, a, 0.0, {"length": r * fx._rng.randf_range(0.75, 1.0), "width": 0.14, "fill": 1.0, "front": 0.6, "stain_a": 0.6}, 1.8, 0.14)
	fx.ring_wall(g, 0.4, r, 0.55, DUST_DARK, GRAVEL_LIGHT, 0.55, {"add": false, "bands": 0.0, "core": 0.35, "expand": 0.4, "noise": Vector2(16.0, 3.0)})
	fx.ring_wall(g, 0.3, r * 1.05, 0.22, ROCK, ROCK_LIGHT, 0.4, {"add": false, "bands": 0.0, "core": 0.6, "expand": 0.35})
	fx.burst("chunks", g + Vector3.UP * 0.1, Vector3.UP, ROCK, ROCK_LIGHT, {"radius": r * 0.85, "amount": 0.8, "speed": 0.8, "floor": 0.0})
	fx.burst("pebbles", g + Vector3.UP * 0.05, Vector3.UP, GRAVEL, GRAVEL_LIGHT, {"radius": r, "amount": 0.9, "speed": 0.7, "floor": 0.0})
	fx.burst("dust", g + Vector3.UP * 0.1, Vector3.UP, DUST, null, {"ring": true, "radius": r * 0.9, "amount": 1.0, "speed": 0.8, "scale": 1.4})
	fx.burst("dust", g, Vector3.UP, DUST_DARK, null, {"radius": 0.6, "amount": 0.6, "speed": 0.5, "scale": 1.5})


## The Aftershock style's outer ring (inner .. r) rolling out on its own.
func _aftershock(g: Vector3, r: float, inner: float) -> void:
	fx.footprint("grit", "ring", g, 0.0, r, {"inner": inner, "fill": 0.5, "front": 1.0, "stain_a": 0.45}, 1.2, 0.12)
	fx.ring_wall(g, maxf(inner, 0.3), r, 0.35, DUST_DARK, GRAVEL_LIGHT, 0.45, {"add": false, "bands": 0.0, "core": 0.35, "expand": 0.5})
	fx.burst("dust", g + Vector3.UP * 0.1, Vector3.UP, DUST, null, {"ring": true, "radius": (inner + r) * 0.5, "amount": 0.8, "speed": 0.6})
	fx.burst("pebbles", g + Vector3.UP * 0.05, Vector3.UP, GRAVEL, GRAVEL_LIGHT, {"radius": r, "amount": 0.5, "speed": 0.6, "floor": 0.0})


## ---- Iron Hide -----------------------------------------------------------------------------------

## The clang as the plates lock (struck-metal sparks and glints, a tight shock ring), then a dull
## iron sheen over his body that holds while the buff lasts (`dur`, the effect's duration).
func _iron_hide(fi: int, dur: float) -> void:
	_end_hide(fi)
	var c := fx.anchor(fi, "core")
	var g := fx._ground(fi)
	fx.burst("sparks", c + Vector3.UP * 0.3, Vector3.UP, IRON_GLINT, Color(1, 1, 1), {"amount": 0.5, "speed": 0.8, "floor": g.y})
	fx.burst("glints", c + Vector3.UP * 0.35, Vector3.UP, IRON_GLINT, null, {"radius": 0.5, "amount": 0.7, "speed": 0.6})
	fx.burst("dust", g, Vector3.UP, DUST, null, {"ring": true, "radius": 0.9, "amount": 0.5, "speed": 0.6})
	fx.ring_wall(g + Vector3.UP * 0.05, 0.6, 1.2, 0.7, IRON, IRON_GLINT, 0.3, {"bands": 6.0, "expand": 0.35})
	fx.flash_light(c + Vector3.UP * 0.4, IRON_GLINT, 1.6, 3.0, 0.2)
	var mi := MeshInstance3D.new()
	mi.mesh = fx._sphere(0.5, 16)
	var mat := FxKit.flow_material(IRON, IRON_GLINT, {"additive": 0.35, "fresnel": 2.6, "scroll": Vector2(0.15, -0.4),
		"noise_scale": Vector2(6.0, 3.0), "edge_v": 0.0, "core": 0.5, "core_width": 0.5, "alpha": 0.0})
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(1.0, 0.85, 1.8)        # his long armoured body
	fx.add_child(mi)
	fx.follow(mi, fi, "core", Vector3(0, 0.04, -0.08), dur + 0.6)
	fx._follows[-1]["turn"] = true
	_hides[fi] = {"node": mi, "mat": mat, "t": 0.0, "dur": dur, "next": 0.3}


func _end_hide(fi: int) -> void:
	var h: Dictionary = _hides.get(fi, {})
	_hides.erase(fi)
	if not h.is_empty() and is_instance_valid(h["node"]):
		(h["node"] as Node).queue_free()


func _update_hides(delta: float) -> void:
	for fi in _hides.keys():
		var h: Dictionary = _hides[fi]
		var mi: MeshInstance3D = h["node"]
		if not is_instance_valid(mi):
			_hides.erase(fi)
			continue
		var t := float(h["t"]) + delta
		h["t"] = t
		var dur := float(h["dur"])
		var gone := fx._view(fi) == null or bool(fx._info(fi).get("out", false))
		var k_out := 1.0 if gone else clampf((t - dur) / 0.3, 0.0, 1.0)
		var mat: ShaderMaterial = h["mat"]
		mat.set_shader_parameter("alpha", 0.4 * clampf(t / 0.15, 0.0, 1.0) * (1.0 - k_out) * (0.7 if fx.reduce_flashes else 1.0))
		if k_out >= 1.0:
			mi.queue_free()
			_hides.erase(fi)
			continue
		if t >= float(h["next"]) and t < dur and fx.quality >= 1:
			# light catches a plate edge somewhere along his back
			h["next"] = t + (0.9 if fx.reduce_flashes else 0.45)
			var off := Vector3(fx._rng.randf_range(-0.3, 0.3), 0.35, fx._rng.randf_range(-0.45, 0.6))
			fx.burst("glints", fx.anchor(fi, "core", off), Vector3.UP, IRON_GLINT, null, {"amount": 0.25, "speed": 0.2, "scale": 0.8})


## Spiked Plates: a light hit on the hide answered by grit and iron flakes bursting off the plates
## toward the attacker, inside the true circle of the shove.
func _spikes(fi: int, pos: Vector3, r: float) -> void:
	var c := fx.anchor(fi, "core")
	var g := Vector3(pos.x, 0.0, pos.z)
	var out := Vector3(pos.x - c.x, 0.0, pos.z - c.z)
	var d := out.normalized() if out.length_squared() > 1e-4 else aim_dir(fi)
	fx.burst("shards", c + d * 0.4 + Vector3.UP * 0.2, d + Vector3.UP * 0.3, IRON, ROCK_LIGHT, {"amount": 0.5, "speed": 1.0, "spread": 0.8, "floor": 0.0})
	fx.burst("pebbles", g + Vector3.UP * 0.3, d + Vector3.UP * 0.5, GRAVEL, GRAVEL_LIGHT, {"amount": 0.5, "speed": 1.1, "spread": 0.7, "floor": 0.0})
	fx.ring_wall(g + Vector3.UP * 0.05, 0.2, maxf(r, 0.6), 0.3, IRON, IRON_GLINT, 0.25, {"bands": 6.0, "expand": 0.4})


# =====================================================================================
# Hits (extras over the v0.9.17 impact) and the frame update
# =====================================================================================

func on_hit(_fi: int, ev: Dictionary) -> void:
	var p: Vector3 = ev.get("point", Vector3.ZERO)
	var ti := int(ev.get("target", -1))
	var fy := fx._ground(ti).y if ti >= 0 else 0.0
	match str(ev.get("pool", "")):
		"boulder_toss":
			# the boulder breaks on the body (or on the guard): big fragments and a cloud of grit
			fx.burst("chunks", p, Vector3.UP, ROCK, ROCK_LIGHT, {"amount": 0.8, "speed": 1.0, "spread": 1.1, "floor": fy, "scale": 1.2})
			fx.burst("dust", p, Vector3.UP, DUST, null, {"amount": 0.7, "speed": 0.8, "scale": 1.2})
			_halves(Vector3(p.x, fy, p.z), 2, 0.36)
		"rock_slide":
			if not bool(ev.get("blocked", false)):
				# the ground bursts up under the fighter it launches
				fx.burst("pebbles", Vector3(p.x, fy + 0.05, p.z), Vector3.UP, GRAVEL, GRAVEL_LIGHT, {"radius": 0.4, "amount": 0.5, "speed": 1.3, "floor": fy})
		"quake_stomp":
			if ti >= 0:
				# swept off its feet: dust and gravel kicked up where it stood
				var g := fx._ground(ti)
				fx.burst("dust", g, Vector3.UP, DUST, null, {"ring": true, "radius": 0.5, "amount": 0.6, "speed": 0.7})
				fx.burst("pebbles", g + Vector3.UP * 0.05, Vector3.UP, GRAVEL, GRAVEL_LIGHT, {"radius": 0.5, "amount": 0.4, "speed": 0.9, "floor": g.y})


func process(delta: float) -> void:
	if not _winds.is_empty():
		for fi in _winds.keys():
			var w: Dictionary = _winds[fi]
			w["t"] = float(w["t"]) + delta
			if is_acting(fi):
				w["seen"] = true          # online the sampled state can trail the move_start event a little
			elif bool(w["seen"]) or float(w["t"]) > 0.3:
				_end_wind(fi)             # cut off before contact: the telegraph goes with the move
	if not _held.is_empty():
		_update_held(delta)
	if not _hides.is_empty():
		_update_hides(delta)
	if not _skirts.is_empty():
		_update_skirts(delta)
