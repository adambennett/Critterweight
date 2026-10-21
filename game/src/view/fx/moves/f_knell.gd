extends MoveFxKit
## Knell's Movesets effects (v0.9.18): the Night Shade beam pouring out of his porthole, the Hex
## Chain and the tether it leaves on its catch, the Lantern Swarm wisps, and the Toll clapped out over
## his helmet with its echo and counter-shock. Spectral identity, as his v0.9.17 Ghost Light, Veil and
## Last Bell: violet soul-light with a pale core, lantern flames, curling wisps and grave-mist that
## sinks, chains of light and a bell's toll. The drowned diver's weight shows as slow motion (light
## that breathes, rings that roll along the floor, chains that sag), never as fast flicker.
## Everything is anchored to body points (the porthole, the chest gauge, the gauntlets), never to
## authored pose targets, so it stays on him when size matching rescales his poses to a target.
## Records (`_beams`, `_tethers`, `_echoes`) live only while their move does: each ends with the
## move, when its fighter is cut off, or when the catch is gone, and frees everything it made.

const SOUL := Color(0.62, 0.45, 1.0)            ## the violet soul-light (Ghost Light, Last Bell)
const SOUL_HOT := Color(0.95, 0.92, 1.0)        ## its pale core
const SOUL_DEEP := Color(0.42, 0.24, 0.88)      ## deep violet edges
const FLAME := Color(0.6, 0.45, 1.0, 0.9)       ## lantern flames
const WISP := Color(0.68, 0.52, 1.0, 0.7)
const WISP_PALE := Color(0.92, 0.88, 1.0, 0.6)
const MIST := Color(0.5, 0.42, 0.72, 0.35)      ## grave-mist
const BRONZE := Color(1.0, 0.8, 0.5)            ## the struck helmet
## the porthole glass from the helmet's weapon point ("head"), and the helmet's centre (rest space)
const PORT_OFF := Vector3(0, -0.04, 0.13)
const HELMET_OFF := Vector3(0, 0, -0.11)
## the glowing gauge on the chest plate, from the chest's pivot
const GAUGE_OFF := Vector3(0, 0.2, 0.24)
const BEAM_PITCH := -0.1                        ## the beam dips from the porthole toward the target's body
const SHADE_GAP := 0.25                         ## a stream's hit extras on one fighter at most this often (s)

var _beams := {}       ## fighter -> Night Shade beam {outer, omat, core, cmat, glow, gmat, len, full, width, age, ending, end_t}
var _tethers := {}     ## catch (fighter) -> Hex Chain tether {by, rib, sig, smat, pts, w, al, age, dur, out}
var _echoes := {}      ## fighter -> Toll echo {until, next}
var _shade_at := {}    ## fighter -> when Night Shade last drew its touch on it
var _now := 0.0        ## the kit's clock (process)


func vfx_names() -> Array:
	return ["knell_night_shade", "knell_hex_chain", "knell_lantern_wisp", "knell_toll_ring", "knell_toll_echo"]


## The helmet's porthole, where the soul-light (and the beam) comes out.
func port(fi: int) -> Vector3:
	return fx.anchor(fi, "head", PORT_OFF)


func on_sustain(fi: int, ev: Dictionary) -> bool:
	if str(ev.get("pool", "")) != "night_shade":
		return false
	if str(ev.get("phase", "")) == "start":
		_start_beam(fi)
	else:
		_end_beam(fi)
	return true


func on_effect(fi: int, ev: Dictionary) -> bool:
	match str(ev.get("vfx", "")):
		"knell_night_shade":
			_beam_tick(fi, ev)
		"knell_hex_chain":
			_chain_cast(fi)
		"knell_lantern_wisp":
			_swarm_release(fi)
		"knell_toll_ring":
			_toll(fi)
		"knell_toll_echo":
			_start_echo(fi, float(ev.get("duration", 1.0)))
		_:
			return false
	return true


func on_move_start(fi: int, ev: Dictionary) -> bool:
	match str(ev.get("pool", "")):
		"night_shade":
			# the soul behind the glass gathers its light: motes stream into the porthole as he rears back
			fx._converge(fi, "head", PORT_OFF, 0.3, SOUL, SOUL_HOT, 0.55)
			fx._glow_at(fi, "head", PORT_OFF, 0.3, 0.34, SOUL, 0.26)
		"hex_chain":
			# links of light coil around the casting arm while it winds back
			_coil(fi, 0.3)
			fx._converge(fi, "fist_l", Vector3.ZERO, 0.25, SOUL, SOUL_HOT, 0.4, "wisps")
		"lantern_swarm":
			# the gauge on his chest becomes a lantern: wisps gather into it under his cupped hands
			fx._converge(fi, "chest", GAUGE_OFF, 0.28, SOUL, SOUL_HOT, 0.5, "wisps")
			fx._glow_at(fi, "chest", GAUGE_OFF, 0.25, 0.3, SOUL, 0.16)
		"toll":
			# the gauntlets swing up: the soul flares and the helmet starts to hum
			fx._glow_at(fi, "head", PORT_OFF, 0.18, 0.2, SOUL, 0.3)
			fx._converge(fi, "head", HELMET_OFF, 0.18, SOUL, SOUL_HOT, 0.35)
	return false        # the v0.9.17 build-ups still run (Ghost Light, the Veil); inline moves have none


func on_hit(fi: int, ev: Dictionary) -> void:
	match str(ev.get("pool", "")):
		"night_shade":
			_shade_touch(ev)
		"hex_chain":
			_chain_bite(fi, ev)
		"lantern_swarm":
			_wisp_flare(ev)
		"toll":
			_counter_shock(fi, ev)


func make_entity(e: Dictionary) -> Dictionary:
	match str(e.get("vfx", "")):
		"knell_hex_chain":
			return _chain_head(e)
		"knell_lantern_wisp":
			return _wisp(e)
	return {}


func process(delta: float) -> void:
	_now += delta
	_update_beams(delta)
	_update_tethers(delta)
	_update_echoes()


## ---- Night Shade ---------------------------------------------------------------------------------

func _start_beam(fi: int) -> void:
	_end_beam(fi, true)
	var lit := _pool_effect(fi, "night_shade", "knell_night_shade")
	# an open tube: the wide end (y = 0) where the beam reaches, the narrow end (y = 1) at the glass
	var outer := MeshInstance3D.new()
	outer.mesh = FxKit.wall_mesh(24, 0.3)
	var omat := FxKit.flow_material(SOUL_DEEP, SOUL_HOT, {"cover": 0.55, "glow_k": 1.0, "scroll": Vector2(0.18, 2.2),
		"noise_scale": Vector2(4.0, 3.0), "edge_v": 0.12, "core": 0.85, "core_width": 0.4, "alpha": 0.0})
	outer.material_override = omat
	outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(outer)
	# a bright core of rays inside it (Medium and High)
	var core: MeshInstance3D = null
	var cmat: ShaderMaterial = null
	if fx.quality >= 1:
		core = MeshInstance3D.new()
		core.mesh = FxKit.wall_mesh(16, 0.6)
		cmat = FxKit.flow_material(SOUL, SOUL_HOT, {"additive": 1.0, "bands": 4.0, "scroll": Vector2(0.0, 3.4), "noise_scale": Vector2(3.0, 6.0),
			"edge_v": 0.08, "core": 0.5, "core_width": 0.7, "alpha": 0.0})
		core.material_override = cmat
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fx.add_child(core)
	# the soul blazing in the glass
	var glow := MeshInstance3D.new()
	glow.mesh = fx._sphere(0.5, 12)
	var gmat := FxKit.flow_material(SOUL, SOUL_HOT, {"additive": 1.0, "fresnel": 1.6, "scroll": Vector2(0.3, -1.0), "noise_scale": Vector2(4.0, 3.0),
		"edge_v": 0.0, "core": 0.5, "core_width": 0.6, "alpha": 0.0})
	glow.material_override = gmat
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(glow)
	var o := port(fi)
	var full := float(lit.get("length", 5.0))
	var width := float(lit.get("width", 0.7))
	var pitch := _beam_pitch(fi, o, full, width)
	_beams[fi] = {"outer": outer, "omat": omat, "core": core, "cmat": cmat, "glow": glow, "gmat": gmat, "len": 0.3,
		"full": full, "width": width, "pitch": pitch, "age": 0.0, "ending": false, "end_t": 0.0}
	fx.flash_light(o, SOUL, 2.5, 4.0, 0.3)
	fx.burst("motes", o, aim_dir(fi, pitch), SOUL, SOUL_HOT, {"amount": 0.6, "speed": 3.0, "spread": 0.3})


## Released (or cut off): the light goes out over a quarter second; `now` frees it at once.
func _end_beam(fi: int, now := false) -> void:
	var b: Dictionary = _beams.get(fi, {})
	if b.is_empty():
		return
	if now:
		_free_beam(b)
		_beams.erase(fi)
		return
	if bool(b["ending"]):
		return
	b["ending"] = true
	# the soul-light dies into grave-mist rolling out of the glass and sinking
	fx.burst("mist", port(fi), aim_dir(fi, -0.4), MIST, null, {"amount": 0.5, "speed": 0.6, "spread": 0.5})


func _free_beam(b: Dictionary) -> void:
	for k in ["outer", "core", "glow"]:
		var n = b[k]
		if is_instance_valid(n) and n is Node:
			(n as Node).queue_free()


func _update_beams(delta: float) -> void:
	for fi in _beams.keys():
		var b: Dictionary = _beams[fi]
		if not is_instance_valid(b["outer"]):
			_free_beam(b)
			_beams.erase(fi)
			continue
		var outer: MeshInstance3D = b["outer"]
		var age := float(b["age"]) + delta
		b["age"] = age
		if not bool(b["ending"]) and not is_acting(fi):
			_end_beam(fi)                    # cut off (hit, knocked down, KO): the light goes out
		var o := port(fi)
		var pitch := move_toward(float(b["pitch"]), _beam_pitch(fi, o, float(b["full"]), float(b["width"])), delta * 1.6)
		b["pitch"] = pitch
		var fade := 1.0
		if bool(b["ending"]):
			b["end_t"] = float(b["end_t"]) + delta
			var k := clampf(float(b["end_t"]) / 0.25, 0.0, 1.0)
			fade = 1.0 - k
			(b["omat"] as ShaderMaterial).set_shader_parameter("dissolve", k)
			if b["cmat"] != null:
				(b["cmat"] as ShaderMaterial).set_shader_parameter("dissolve", k)
			if k >= 1.0:
				_free_beam(b)
				_beams.erase(fi)
				continue
		else:
			# it reaches out to its length (or to where it meets the floor)
			b["len"] = move_toward(float(b["len"]), _beam_reach(fi, o, pitch, float(b["full"])), delta * 22.0)
		var a := clampf(age / 0.1, 0.0, 1.0) * fade * (0.8 if fx.reduce_flashes else 1.0)
		(b["omat"] as ShaderMaterial).set_shader_parameter("alpha", a * 0.9)
		var d := aim_dir(fi, pitch)
		var x := d.cross(Vector3.UP).normalized()
		var y := -d
		var z := x.cross(y).normalized()
		var l := float(b["len"])
		# it breathes slowly, like the light of something that has been under water a long time
		var r := float(b["width"]) * 0.5 * (1.0 + 0.06 * sin(age * 6.0))
		outer.global_transform = Transform3D(Basis(x * r, y * l, z * r), o + d * l)
		if is_instance_valid(b["core"]):
			(b["core"] as MeshInstance3D).global_transform = Transform3D(Basis(x * r * 0.4, y * l, z * r * 0.4), o + d * l)
			(b["cmat"] as ShaderMaterial).set_shader_parameter("alpha", a)
		if is_instance_valid(b["glow"]):
			var glow: MeshInstance3D = b["glow"]
			glow.global_position = o
			glow.scale = Vector3.ONE * (0.2 + 0.03 * sin(age * 4.0))
			(b["gmat"] as ShaderMaterial).set_shader_parameter("alpha", a)


func _beam_tick(fi: int, ev: Dictionary) -> void:
	var reach := float(ev.get("length", 5.0))
	var width := float(ev.get("width", 0.7))
	var o := port(fi)
	var b: Dictionary = _beams.get(fi, {})
	var pitch := float(b["pitch"]) if not b.is_empty() else _beam_pitch(fi, o, reach, width)
	var d := aim_dir(fi, pitch)
	var seen := _beam_reach(fi, o, pitch, reach)
	if b.is_empty():
		# a tapped Night Shade (never sustained) fires once: a single flash of the beam
		fx.jet(o, d, seen, width * 0.5, SOUL_DEEP, SOUL_HOT, 0.3, {"cover": 0.6, "glow_k": 1.0})
	else:
		b["full"] = reach
		b["width"] = width
	# soul-motes race down the beam, wisps curl off it, grave-mist sinks where it ends
	fx.burst("motes", o + d * 0.2, d, SOUL, SOUL_HOT, {"speed": seen * 1.6, "spread": 0.05, "amount": 0.3, "life": 1.0})
	if fx._rng.randf() < 0.4:
		fx.burst("wisps", o + d * seen * fx._rng.randf_range(0.25, 0.9), Vector3.UP, WISP, WISP_PALE, {"amount": 0.18, "speed": 0.4, "radius": width * 0.3})
	if fx._rng.randf() < 0.3:
		fx.burst("mist", o + d * seen, Vector3.DOWN, MIST, null, {"amount": 0.25, "speed": 0.4, "spread": 1.0})
	# the true footprint glows on the floor now and then (the band that can hit)
	if fx._rng.randf() < 0.25 and ev.has("origin"):
		fx.footprint("spectral", "line", Vector3(ev["origin"]), float(ev.get("yaw", fx._yaw(fi))), 0.0,
			{"length": reach, "width": width, "fill": 0.3, "strength": 0.45, "front": 0.6}, 0.3, 0.05)


## How the beam tilts from the porthole: it dips onto the nearest fighter standing in its band (so it
## pours onto a short target instead of passing over its head), else falls gently with distance. Its
## yaw is always the facing: the band that hits lies on the floor along it.
func _beam_pitch(fi: int, o: Vector3, reach: float, width: float) -> float:
	var f := aim_dir(fi)
	var best := reach
	var want := BEAM_PITCH
	var n := int(fx.fighter_count.call()) if fx.fighter_count.is_valid() else 0
	for i in n:
		if i == fi or not fx._alive(i, fx._info(i)):
			continue
		var c := fx.anchor(i, "core")
		var to := Vector3(c.x - o.x, 0.0, c.z - o.z)
		var along := to.dot(f)
		if along < 0.4 or along > best or (to - f * along).length() > width * 0.5 + 0.4:
			continue
		best = along
		want = clampf(atan2(c.y - o.y, along), -0.35, 0.12)
	return want


## How far the beam is seen to reach: its length, or less where it meets the floor.
func _beam_reach(fi: int, o: Vector3, pitch: float, reach: float) -> float:
	if pitch > -0.02:
		return reach
	return clampf((o.y - fx._ground(fi).y - 0.03) / sin(-pitch), 0.5, reach)


## The beam touching a fighter: the shade gathers on it and grave-mist pools at its feet (the slow).
## Stream ticks land many times a second, so this draws at most every SHADE_GAP per fighter.
func _shade_touch(ev: Dictionary) -> void:
	var vi := int(ev.get("target", -1))
	if vi < 0 or bool(ev.get("blocked", false)) or _now - float(_shade_at.get(vi, -9.0)) < SHADE_GAP:
		return
	_shade_at[vi] = _now
	var p: Vector3 = ev.get("point", fx.anchor(vi, "core"))
	fx.burst("wisps", p, Vector3.UP, WISP, WISP_PALE, {"amount": 0.3, "speed": 0.5, "radius": 0.2})
	fx.burst("mist", fx._ground(vi) + Vector3.UP * 0.1, Vector3.UP, MIST, null, {"amount": 0.35, "speed": 0.3, "radius": 0.4, "ring": true})


## ---- Hex Chain -----------------------------------------------------------------------------------

## A short coil of light winding around the casting forearm (elbow to fist) for `dur` seconds.
func _coil(fi: int, dur: float) -> void:
	if fx.quality <= 0:
		return
	var rib := fx.ribbon(SOUL, SOUL_HOT, true)
	var n := 14
	var pts := []
	var w := []
	var al := []
	pts.resize(n)
	w.resize(n)
	al.resize(n)
	fx.animate(rib, dur, func(k: float, t: float) -> void:
		var a := fx.anchor(fi, "farm_l")
		var b := fx.anchor(fi, "fist_l")
		var ax := (b - a).normalized() if a.distance_squared_to(b) > 1e-6 else Vector3.UP
		var p1 := ax.cross(Vector3.UP).normalized() if absf(ax.y) < 0.95 else Vector3.RIGHT
		var p2 := ax.cross(p1).normalized()
		for i in n:
			var u := float(i) / float(n - 1)
			var ang := u * TAU * 2.5 + t * 9.0
			pts[i] = a.lerp(b, u) + (p1 * cos(ang) + p2 * sin(ang)) * 0.09
			w[i] = 0.035
			al[i] = smoothstep(0.0, 0.3, k) * (1.0 - smoothstep(0.85, 1.0, k)) * sin(u * PI)
		fx.draw_ribbon(rib, pts, w, al))


func _chain_cast(fi: int) -> void:
	# the chain leaves the hand with a crack of violet light
	var h := fx.anchor(fi, "fist_l")
	fx.burst("glints", h, aim_dir(fi), SOUL_HOT, SOUL, {"amount": 0.5, "speed": 1.2})
	fx.burst("wisps", h, aim_dir(fi), WISP, null, {"amount": 0.35, "speed": 0.9, "spread": 0.5})
	fx.flash_light(h, SOUL, 1.6, 2.5, 0.2)


## The chain in flight: a curled barb of light spinning on its end, a pale eye at its heart, and the
## chain itself running back to Knell's hand.
func _chain_head(e: Dictionary) -> Dictionary:
	var owner := _owner_of(e)
	var root := Node3D.new()
	fx.add_child(root)
	root.global_position = e["pos"]
	var spin := Node3D.new()
	root.add_child(spin)
	var barb := MeshInstance3D.new()
	barb.mesh = FxKit.spiral_mesh(0.8, 1.0, 1.0, 0.45)
	barb.material_override = FxKit.flow_material(SOUL, SOUL_HOT, {"additive": 1.0, "scroll": Vector2(-2.0, 0.0), "noise_scale": Vector2(5.0, 1.0),
		"edge_v": 0.4, "core": 0.5, "core_width": 0.4, "alpha": 1.0})
	barb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	barb.scale = Vector3(0.17, 0.12, 0.17)
	barb.rotation = Vector3(PI * 0.5, 0.0, 0.0)        # curled across the flight (the root looks along it)
	spin.add_child(barb)
	var eye := MeshInstance3D.new()
	eye.mesh = fx._sphere(0.07, 10)
	eye.material_override = FxKit.flow_material(SOUL, SOUL_HOT, {"additive": 1.0, "fresnel": 1.4, "edge_v": 0.0, "core": 0.5, "core_width": 0.6, "alpha": 1.0})
	eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(eye)
	var trail := fx._attached_stream(root, "wisps", WISP, WISP_PALE, {"speed": 0.15, "amount": 0.45, "scale": 0.6})
	var rib := fx.ribbon(SOUL_DEEP, SOUL_HOT, true)
	(rib.material_override as ShaderMaterial).set_shader_parameter("bands", 18.0)    # links
	var n := 14 if fx.quality >= 1 else 8
	var pts := []
	var w := []
	var al := []
	pts.resize(n)
	w.resize(n)
	al.resize(n)
	var t0 := _now
	return {"node": root, "kind": "projectile", "pos": e["pos"], "dir": Vector3.FORWARD,
		"tick": func(_e2: Dictionary) -> void:
			var t := _now - t0
			spin.rotation = Vector3(0.0, 0.0, t * 16.0)
			if is_instance_valid(rib) and is_instance_valid(root):
				_draw_chain(rib, _hand(owner, root.global_position), root.global_position, pts, w, al, 0.08, 1.0, t),
		"end": func() -> void:
			_detach(trail)
			var head := root.global_position if is_instance_valid(root) else _hand(owner, Vector3.ZERO)
			if is_instance_valid(root):
				root.queue_free()
			if is_instance_valid(rib):
				# hauled back to the hand (a bite draws its own tether)
				fx.animate(rib, 0.14, func(k: float, _t: float) -> void:
					var hand := _hand(owner, head)
					_draw_chain(rib, hand, head.lerp(hand, k), pts, w, al, 0.05, 1.0 - k, _now))}


## The chain bites: a flash on the catch, and the hex takes hold (unless it was guarded or parried).
func _chain_bite(fi: int, ev: Dictionary) -> void:
	var vi := int(ev.get("target", -1))
	var p: Vector3 = ev.get("point", fx.anchor(vi, "core"))
	fx.burst("glints", p, Vector3.UP, SOUL_HOT, SOUL, {"amount": 0.6, "speed": 1.0})
	if vi < 0 or bool(ev.get("blocked", false)) or bool(ev.get("parried", false)):
		return          # turned aside: no hex takes hold
	fx.burst("wisps", p, Vector3.UP, WISP, WISP_PALE, {"amount": 0.6, "speed": 0.8, "radius": 0.25})
	fx.ring_wall(fx._ground(vi) + Vector3.UP * 0.05, 0.25, 0.8, 0.35, SOUL, SOUL_HOT, 0.35, {"bands": 6.0, "scroll": Vector2(1.5, 0.0)})
	fx.flash_light(p, SOUL, 2.0, 3.0, 0.25)
	_start_tether(fi, vi)


## The hex on a catch: a chain of light from Knell's hand to its body, sagging when it comes close and
## pulled taut when it backs off, a sigil turning on the floor under it, wisps clinging to it. It
## lasts as long as the Hexed status (from the move's content), or until either fighter is gone.
func _start_tether(fi: int, vi: int) -> void:
	_end_tether(vi)
	var st: Dictionary = _pool_effect(fi, "hex_chain", "knell_hex_chain").get("status", {})
	var dur := float(st.get("duration", 2.5))
	var rib := fx.ribbon(SOUL_DEEP, SOUL_HOT, true)
	(rib.material_override as ShaderMaterial).set_shader_parameter("bands", 22.0)
	var n := 16 if fx.quality >= 1 else 8
	var pts := []
	var w := []
	var al := []
	pts.resize(n)
	w.resize(n)
	al.resize(n)
	var sig := fx.footprint("spectral", "ring", fx._ground(vi), 0.0, 0.75, {"inner": 0.5, "fill": 0.5, "strength": 0.8, "speed": 2.0}, INF)
	fx._stream_at(vi, "core", Vector3.ZERO, dur, "wisps", WISP, WISP_PALE, {"amount": 0.25, "speed": 0.15, "radius": 0.2}, "knell_hex")
	_tethers[vi] = {"by": fi, "rib": rib, "sig": sig, "smat": sig.material_override, "pts": pts, "w": w, "al": al,
		"age": 0.0, "dur": dur, "out": -1.0}


func _end_tether(vi: int) -> void:
	var t: Dictionary = _tethers.get(vi, {})
	if t.is_empty():
		return
	_tethers.erase(vi)
	for k in ["rib", "sig"]:
		var n = t[k]
		if is_instance_valid(n) and n is Node:
			(n as Node).queue_free()
	fx.release(vi, "knell_hex")


func _update_tethers(delta: float) -> void:
	for vi in _tethers.keys():
		var t: Dictionary = _tethers[vi]
		if not is_instance_valid(t["rib"]):
			_end_tether(vi)
			continue
		var rib: MeshInstance3D = t["rib"]
		var age := float(t["age"]) + delta
		t["age"] = age
		var by := int(t["by"])
		var a := fx.anchor(by, "fist_l")
		var b := fx.anchor(vi, "core")
		var gone := not fx._alive(by, fx._info(by)) or not fx._alive(vi, fx._info(vi)) or a.distance_to(b) > 9.0
		if float(t["out"]) < 0.0 and (gone or age >= float(t["dur"])):
			t["out"] = 0.0
			fx.release(vi, "knell_hex")
			# the hex lets go: the chain crumbles into wisps along its length
			fx.burst("wisps", a.lerp(b, 0.5), Vector3.UP, WISP, WISP_PALE, {"amount": 0.4, "speed": 0.4, "radius": a.distance_to(b) * 0.3})
		var fade := 1.0
		if float(t["out"]) >= 0.0:
			t["out"] = float(t["out"]) + delta
			fade = 1.0 - clampf(float(t["out"]) / 0.3, 0.0, 1.0)
			if fade <= 0.0:
				_end_tether(vi)
				continue
		# slack when the catch is close, taut when it pulls away; a slow pulse runs along the links
		var slack := clampf(0.45 - a.distance_to(b) * 0.07, 0.04, 0.4)
		var pulse := 0.85 + 0.15 * sin(age * (3.0 if fx.reduce_flashes else 6.0))
		_draw_chain(rib, a, b, t["pts"], t["w"], t["al"], slack, fade * pulse, age)
		if is_instance_valid(t["sig"]):
			var sig: MeshInstance3D = t["sig"]
			sig.global_position = fx._ground(vi) + Vector3.UP * 0.03
			sig.rotation.y = age * 1.2
			(t["smat"] as ShaderMaterial).set_shader_parameter("fade", 0.8 * fade * clampf(age / 0.15, 0.0, 1.0))


## Lays a chain ribbon from `a` to `b` into the arrays it reuses (no per-frame allocation): it sags
## `slack` metres in the middle and shivers a little along its length; `alpha` fades it.
func _draw_chain(rib: MeshInstance3D, a: Vector3, b: Vector3, pts: Array, w: Array, al: Array, slack: float, alpha: float, t: float) -> void:
	var n := pts.size()
	var side := (b - a).cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 1e-6 else Vector3.RIGHT
	for i in n:
		var u := float(i) / float(n - 1)
		var bow := sin(u * PI)
		pts[i] = a.lerp(b, u) + Vector3.DOWN * slack * bow + side * 0.03 * bow * sin(u * 9.0 + t * 8.0)
		w[i] = 0.06 * (0.8 + 0.2 * bow)
		al[i] = alpha * clampf(bow * 4.0 + 0.3, 0.3, 1.0)
	fx.draw_ribbon(rib, pts, w, al)


## Knell's casting hand, or `fallback` when the thrower is unknown or gone.
func _hand(owner: int, fallback: Vector3) -> Vector3:
	if owner < 0 or fx._view(owner) == null:
		return fallback
	return fx.anchor(owner, "fist_l")


## Who threw an entity: its owner locally; online (replicated entities carry none) the nearest Knell.
func _owner_of(e: Dictionary) -> int:
	if e.has("owner"):
		return int(e["owner"])
	var p: Vector3 = e["pos"]
	var best := -1
	var bd := INF
	var n := int(fx.fighter_count.call()) if fx.fighter_count.is_valid() else 0
	for i in n:
		if fx._cid(i) != creature:
			continue
		var dd := fx._ground(i).distance_to(Vector3(p.x, 0.0, p.z))
		if dd < bd:
			bd = dd
			best = i
	return best


## ---- Lantern Swarm -------------------------------------------------------------------------------

func _swarm_release(fi: int) -> void:
	# his arms fly open and the gauge lets the wisps go: a flare of lantern-light, motes scattering into the fan
	var p := fx.anchor(fi, "chest", GAUGE_OFF)
	fx.burst("flames", p, Vector3.UP, FLAME, WISP_PALE, {"amount": 0.6, "scale": 0.8, "spread": 1.2})
	fx.burst("motes", p, aim_dir(fi), SOUL, SOUL_HOT, {"amount": 0.5, "speed": 1.2, "spread": 1.0})
	fx.flash_light(p, SOUL, 1.8, 3.0, 0.25)


## One wisp: a lantern flame with no lantern, a pale core in a violet shell that flickers and bobs
## as it drifts, a flame licking up from it and wisps peeling off behind.
func _wisp(e: Dictionary) -> Dictionary:
	var r := maxf(float(e.get("radius", 0.2)), 0.08)
	var root := Node3D.new()
	fx.add_child(root)
	root.global_position = e["pos"]
	var core := MeshInstance3D.new()
	core.mesh = fx._sphere(r * 0.55, 10)
	core.material_override = FxKit.flow_material(SOUL_HOT, Color(1, 1, 1), {"additive": 1.0, "fresnel": 0.8, "edge_v": 0.0, "core": 0.5, "core_width": 0.7, "alpha": 1.0})
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	var shell := MeshInstance3D.new()
	shell.mesh = fx._sphere(r * 1.1, 12)
	shell.material_override = FxKit.flow_material(SOUL, SOUL_HOT, {"additive": 1.0, "fresnel": 1.8, "scroll": Vector2(0.0, -2.0), "noise_scale": Vector2(5.0, 3.0),
		"edge_v": 0.0, "core": 0.5, "core_width": 0.5, "alpha": 0.85})
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shell)
	var flame := fx._attached_stream(root, "flames", FLAME, WISP_PALE, {"speed": 0.2, "amount": 0.5, "scale": 0.55, "buoyancy": 1.5})
	var trail := fx._attached_stream(root, "wisps", WISP, WISP_PALE, {"speed": 0.1, "amount": 0.4, "scale": 0.5})
	var phase := fx._rng.randf() * TAU
	var amp := 0.06 if fx.reduce_flashes else 0.12
	var t0 := _now
	return {"node": root, "kind": "projectile", "pos": e["pos"], "dir": Vector3.FORWARD,
		"tick": func(_e2: Dictionary) -> void:
			var t := _now - t0
			if is_instance_valid(shell):
				shell.scale = Vector3.ONE * (1.0 + amp * sin(t * 11.0 + phase) + amp * 0.5 * sin(t * 17.0 + phase * 2.0))
				shell.position = Vector3(0.0, 0.04 * sin(t * 5.0 + phase), 0.0),
		"end": func() -> void:
			if is_instance_valid(root):
				# it gutters out where it ends: a last puff of wisps
				var p := root.global_position
				fx.burst("wisps", p, Vector3.UP, WISP, WISP_PALE, {"amount": 0.3, "speed": 0.6, "radius": 0.1})
				fx.burst("motes", p, Vector3.UP, SOUL, SOUL_HOT, {"amount": 0.25, "speed": 1.0})
			_detach(flame)
			_detach(trail)
			if is_instance_valid(root):
				root.queue_free()}


func _wisp_flare(ev: Dictionary) -> void:
	var p: Vector3 = ev.get("point", Vector3.ZERO)
	fx.burst("flames", p, Vector3.UP, FLAME, WISP_PALE, {"amount": 0.45, "scale": 0.7})
	fx.burst("glints", p, Vector3.UP, SOUL_HOT, SOUL, {"amount": 0.35, "speed": 0.8})


## ---- Toll ----------------------------------------------------------------------------------------

## The bronze gauntlets clap over the helmet: glints where they meet (wherever size matching put his
## hands), a ghostly bell swinging over his head, the toll rolling out along the floor and through the
## air at helmet height, and whatever clung to him shaken off in a spray of motes.
func _toll(fi: int) -> void:
	var head := fx.anchor(fi, "head", HELMET_OFF)
	var struck := (fx.anchor(fi, "fist_l") + fx.anchor(fi, "fist_r")) * 0.5
	fx.burst("glints", struck, Vector3.UP, BRONZE, Color(1.0, 0.95, 0.8), {"amount": 0.7, "speed": 1.2, "scale": 1.2, "spread": 2.0})
	fx.burst("sparks", struck, Vector3.UP, BRONZE, null, {"amount": 0.4, "spread": 2.0, "floor": fx._ground(fi).y})
	_ghost_bell(fi, 0.9, 1.0)
	var g := fx._ground(fi)
	fx.ring_wall(g + Vector3.UP * 0.05, 0.3, 2.4, 0.6, SOUL, SOUL_HOT, 0.6, {"bands": 3.0, "scroll": Vector2(0.0, -1.2), "core": 0.5, "core_width": 0.3, "expand": 0.5})
	fx.ring_wall(head, 0.15, 1.1, 0.12, SOUL, SOUL_HOT, 0.4, {"bands": 0.0, "expand": 0.35})
	fx.footprint("spectral", "ring", g, 0.0, 1.6, {"inner": 1.2, "fill": 0.35, "front": 1.0}, 0.8, 0.3)
	fx.burst("motes", fx.anchor(fi, "core"), Vector3.UP, WISP_PALE, SOUL, {"amount": 0.7, "speed": 1.6, "spread": 2.5, "radius": 0.3})
	fx.flash_light(head + Vector3.UP * 0.3, SOUL, 3.0, 4.5, 0.4)


## The echo (the counter stance): the helmet keeps ringing. A sigil ring holds under his boots, the
## bell hangs trembling over him and rings of sound roll out every third of a second, until someone
## strikes him (the counter releases the "stance" pieces), he is cut off, or it dies away.
func _start_echo(fi: int, dur: float) -> void:
	var ring := fx.footprint("spectral", "ring", fx._ground(fi), 0.0, 1.0, {"inner": 0.7, "fill": 0.45, "strength": 0.85, "speed": 2.5}, INF)
	var rmat := ring.material_override as ShaderMaterial
	var rid := ring.get_instance_id()
	fx.follow(ring, fi, "__ground", Vector3.UP * 0.03, dur, func() -> void:
		var o := instance_from_id(rid)
		if o != null:
			fx.animate(o as Node, 0.3, func(k: float, _t: float) -> void:
				rmat.set_shader_parameter("fade", 0.85 * (1.0 - k))))
	fx._follows[-1]["tag"] = "stance"
	_ghost_bell(fi, dur + 0.2, 0.2, "stance")
	fx._stream_at(fi, "core", Vector3(0, -0.1, 0), dur, "wisps", WISP, WISP_PALE, {"amount": 0.3, "speed": 0.2, "radius": 0.45, "ring": true}, "stance")
	_echoes[fi] = {"until": _now + dur, "next": _now + 0.1}


func _update_echoes() -> void:
	for fi in _echoes.keys():
		var ec: Dictionary = _echoes[fi]
		if _now >= float(ec["until"]) or not is_acting(fi):
			_echoes.erase(fi)
			fx.release(fi, "stance")        # cut off (grappled, knocked down) or over: the echo dies
			continue
		if _now >= float(ec["next"]):
			ec["next"] = _now + (0.33 if fx.quality >= 1 else 0.5)
			fx.ring_wall(fx._ground(fi) + Vector3.UP * 0.05, 0.4, 1.3, 0.25, SOUL, SOUL_HOT, 0.45, {"bands": 0.0, "expand": 0.7, "h_end": 0.2})


## The echo breaks on whoever struck him: the bell's force in a cone from his chest, a toll ring where
## it lands, the bell swinging hard.
func _counter_shock(fi: int, ev: Dictionary) -> void:
	_echoes.erase(fi)
	fx.release(fi, "stance")
	var src := fx.anchor(fi, "core")
	var p: Vector3 = ev.get("point", src + aim_dir(fi))
	var to := p - src
	var dir := to.normalized() if to.length_squared() > 0.01 else aim_dir(fi)
	fx.jet(src, dir, maxf(to.length(), 0.6), 0.55, SOUL_DEEP, SOUL_HOT, 0.35, {"cover": 0.7, "glow_k": 1.0, "flat": 0.6})
	fx.ring_wall(Vector3(p.x, fx._ground(fi).y + 0.05, p.z), 0.2, 1.4, 0.8, SOUL, SOUL_HOT, 0.45, {"bands": 3.0, "scroll": Vector2(0.0, -1.5), "core": 0.5, "expand": 0.4})
	fx.burst("wisps", p, dir, WISP, WISP_PALE, {"amount": 0.8, "speed": 1.2, "spread": 0.8})
	fx.burst("glints", p, Vector3.UP, SOUL_HOT, SOUL, {"amount": 0.7, "speed": 1.3, "scale": 1.3})
	_ghost_bell(fi, 0.7, 1.4)
	fx.flash_light(p, SOUL, 3.5, 4.0, 0.35)


## A ghostly bell over the helmet (Last Bell's) that swings on its crown and fades over `dur` seconds;
## `swing` scales its arc. Tagged, it follows until released, then fades out quickly.
func _ghost_bell(fi: int, dur: float, swing: float, tag := "") -> void:
	var pivot := Node3D.new()
	fx.add_child(pivot)
	var mi := MeshInstance3D.new()
	mi.mesh = FxKit.wall_mesh(32, 0.45)            # wide mouth at the bottom, narrow crown on top
	var mat := FxKit.flow_material(Color(0.45, 0.25, 0.9), Color(0.85, 0.75, 1.0), {"cover": 0.85, "glow_k": 0.9, "scroll": Vector2(0.2, -0.4),
		"noise_scale": Vector2(6.0, 2.0), "edge_v": 0.15, "core": 0.1, "core_width": 0.25, "alpha": 0.0})
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(0.3, 0.36, 0.3)
	mi.position = Vector3(0, -0.36, 0)
	pivot.add_child(mi)
	var st := {"out": INF}            # when it stopped following (released, or its time is up)
	fx.follow(pivot, fi, "head", HELMET_OFF + Vector3(0, 0.72, 0), dur, func() -> void:
		st["out"] = minf(float(st["out"]), _now))
	if tag != "":
		fx._follows[-1]["tag"] = tag
	var dim := 0.7 if fx.reduce_flashes else 1.0
	fx.animate(pivot, dur + 0.2, func(_k: float, t: float) -> void:
		var u := clampf(t / 0.6, 0.0, 1.0)
		pivot.rotation = Vector3(sin(u * TAU * 1.5) * 0.4 * swing * (1.0 - u) + 0.05 * swing * sin(t * 13.0), fx._yaw(fi), 0.0)
		var gone := clampf((_now - float(st["out"])) / 0.15, 0.0, 1.0)
		mat.set_shader_parameter("alpha", smoothstep(0.0, 0.08, t) * (1.0 - gone) * 0.9 * dim)
		if gone >= 1.0:
			pivot.queue_free())


## ---- Shared --------------------------------------------------------------------------------------

## One effect of one of the fighter's pool moves, from the view's copy of its content ({} if unknown).
func _pool_effect(fi: int, pool_id: String, vfx: String) -> Dictionary:
	var v := fx._view(fi)
	if v == null or v.creature == null:
		return {}
	var pm: PoolMove = v.creature.pool.get(pool_id)
	if pm == null or pm.move == null:
		return {}
	for e in pm.move.effects:
		if typeof(e) == TYPE_DICTIONARY and str((e as Dictionary).get("vfx", "")) == vfx:
			return e
	return {}


## Leaves an attached emitter's wake where it is to fade out (its carrier is going away).
func _detach(gp: GPUParticles3D) -> void:
	if gp == null or not is_instance_valid(gp):
		return
	var p := gp.global_position
	gp.reparent(fx)
	gp.global_position = p
	fx.end_stream(gp)
