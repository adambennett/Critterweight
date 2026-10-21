extends MoveFxKit
## Slurry's Movesets effects (v0.9.18): Poison Darts (venom needles spat in a burst, and the darts
## that stay stuck where they hit), Acid Spray (a hosing fan of acid out of the jaws that follows the
## head and dies with the move), Coil Crush (sludge coils wound round the victim, clenching on every
## squeeze and flying apart on the crush) and Shed Skin (the empty husk left standing in Slurry's pose,
## the slick of the slip, the fresh scales' gleam). Drain Wyrm identity: viscous sludge and venom
## (glossy gobs, drips, sticky darts, toxic greens) and a serpent's coils; nothing burns white-hot and
## nothing flashes hard.
##
## Every piece follows what the simulation says: darts fly with their projectiles and stick only on
## a landed hit, the spray lives exactly while the move sustains, the coils ride their victim only
## while Slurry is still in the move, and each piece frees itself when its move or entity ends.
## Meshes and the dart materials are built once and shared; per frame only existing nodes move.

const GOO := Color(0.3, 0.5, 0.07)              ## dark glossy sludge
const GOO_SHEEN := Color(0.62, 0.86, 0.2)       ## its wet highlight
const VENOM := Color(0.55, 0.92, 0.14)          ## toxic green
const VENOM_HOT := Color(0.86, 1.0, 0.46)       ## the acid's bright core
const ACID_MIST := Color(0.62, 0.86, 0.3, 0.32)
const BARB := Color(0.88, 0.31, 0.69)           ## Slurry's accent (palette "accent"): the darts' barbs
const HUSK := Color(0.76, 0.84, 0.58)           ## a shed skin, pale and translucent
const STUCK_LIFE := 2.5                         ## a stuck dart stays as long as its Venom Dart status
const STUCK_FADE := 0.3
const STUCK_MAX := 3                            ## darts drawn stuck in one fighter at once
const COIL_LIFE := 1.6                          ## safety net: coils never outlive their move by much
const HUSK_LIFE := 1.3

var _sprays := {}            ## fighter -> {node, mat, len, reach, cone, age, ending, end_t}
var _coils := {}             ## fighter (Slurry) -> {node, mesh, mat, victim, r, h, age, squeeze, ending, end_t, burst}
var _stuck: Array = []       ## [{node, victim, seg, local: Transform3D, age}] darts stuck in fighters
var _husks: Array = []       ## shed husks still standing (Node3D roots)
var _shared := {}            ## meshes and materials built once, shared by every dart and husk


func vfx_names() -> Array:
	return ["slurry_dart", "slurry_acid", "slurry_coil_squeeze", "slurry_coil_crush", "slurry_shed_skin", "slurry_shed_slip",
		"slurry_fresh_scales", "slurry_molt_burst"]


## Between the jaws (the fang weapon point, a little forward).
func mouth(fi: int) -> Vector3:
	return fx.anchor(fi, "fang", Vector3(0, 0, 0.05))


func on_move_start(fi: int, ev: Dictionary) -> bool:
	var floor_y := fx._ground(fi).y
	match str(ev.get("pool", "")):
		"poison_darts":
			# venom wells up in the fangs while it rears back
			fx._converge(fi, "fang", Vector3.ZERO, 0.2, VENOM, VENOM_HOT, 0.45)
			fx._stream_at(fi, "fang", Vector3.ZERO, 0.3, "gobs", GOO, GOO_SHEEN,
				{"dir": Vector3.DOWN, "speed": 0.15, "spread": 0.5, "amount": 0.35, "scale": 0.45, "floor": floor_y})
		"acid_spray":
			# the throat fills: acid bubbles gather at the jaws with a hiss of vapour
			fx._converge(fi, "fang", Vector3.ZERO, 0.26, VENOM, VENOM_HOT, 0.5, "bubbles")
			fx.burst("mist", mouth(fi), aim_dir(fi, -0.3), ACID_MIST, null, {"amount": 0.35, "speed": 0.35})
		"coil_crush":
			# the coils tense: goo wrung out of the body, drool from the fangs
			fx.burst("gobs", fx.anchor(fi, "coil_low"), Vector3.UP, GOO, GOO_SHEEN, {"amount": 0.35, "speed": 0.6, "radius": 0.25, "floor": floor_y})
			fx._stream_at(fi, "fang", Vector3.ZERO, 0.3, "gobs", GOO, GOO_SHEEN,
				{"dir": Vector3.DOWN, "speed": 0.1, "amount": 0.3, "scale": 0.5, "floor": floor_y})
		"shed_skin":
			# the old skin loosens: a pale shimmer runs over it
			fx.burst("glints", fx.anchor(fi, "core"), Vector3.UP, HUSK, null, {"amount": 0.45, "radius": 0.35, "speed": 0.3})
	return false        # the generic move start still ends hovers and build-ups


func on_effect(fi: int, ev: Dictionary) -> bool:
	match str(ev.get("vfx", "")):
		"slurry_dart":
			_dart_spit(fi)
		"slurry_acid":
			_acid_tick(fi, ev)
		"slurry_coil_squeeze":
			_squeeze(fi, ev)
		"slurry_coil_crush":
			_crush(fi, ev)
		"slurry_shed_skin":
			_shed(fi)
		"slurry_shed_slip":
			_slip(fi, ev)
		"slurry_fresh_scales":
			_fresh_scales(fi)
		"slurry_molt_burst":
			var mp: Vector3 = ev.get("pos", fx._ground(fi))
			_molt_burst(mp, float(ev.get("radius", 1.1)))
		_:
			return false
	return true


func on_sustain(fi: int, ev: Dictionary) -> bool:
	if str(ev.get("pool", "")) != "acid_spray":
		return false
	if str(ev.get("phase", "")) == "start":
		_start_spray(fi)
	else:
		_end_spray(fi)
	return true


func on_hit(fi: int, ev: Dictionary) -> void:
	match str(ev.get("pool", "")):
		"poison_darts":
			if bool(ev.get("parried", false)):
				return          # swatted away: the parry draws itself
			if bool(ev.get("blocked", false)):
				var bp: Vector3 = ev.get("point", fx._ground(fi))
				fx.burst("gobs", bp, Vector3.UP, GOO, GOO_SHEEN, {"amount": 0.2, "speed": 0.6, "scale": 0.5, "floor": fx._ground(int(ev.get("target", -1))).y})
			else:
				_stick_dart(fi, ev)
		"acid_spray":
			# the acid hisses on whoever it soaks (its ticks are many: now and then)
			if not bool(ev.get("blocked", false)) and fx._rng.randf() < 0.35:
				var ti := int(ev.get("target", -1))
				fx.burst("bubbles", fx.anchor(ti, "core"), Vector3.UP, Color(VENOM, 0.85), null, {"amount": 0.3, "radius": 0.3, "speed": 0.5})
		"coil_crush":
			if bool(ev.get("melee", false)) and not bool(ev.get("blocked", false)):
				_wrap(fi, int(ev.get("target", -1)))       # the lunge caught someone: wind the coils on


func make_entity(e: Dictionary) -> Dictionary:
	if str(e.get("vfx", "")) == "slurry_dart":
		return _dart(e)
	return {}


func process(delta: float) -> void:
	if not _sprays.is_empty():
		_update_sprays(delta)
	if not _coils.is_empty():
		_update_coils(delta)
	_update_stuck(delta)
	var i := _husks.size() - 1
	while i >= 0:
		if not is_instance_valid(_husks[i]):
			_husks.remove_at(i)
		i -= 1


## ---- Poison Darts --------------------------------------------------------------------------------

func _dart_spit(fi: int) -> void:
	var p := mouth(fi)
	var d := aim_dir(fi)
	fx.burst("spray", p, d, Color(VENOM, 0.8), Color(VENOM_HOT, 0.8), {"amount": 0.25, "speed": 0.6, "spread": 0.25})
	fx.burst("gobs", p, d + Vector3.UP * 0.2, GOO, GOO_SHEEN, {"amount": 0.15, "speed": 0.4, "scale": 0.5, "floor": fx._ground(fi).y})


## A dart in flight: hidden until its first step shows which way it flies (projectile nodes face
## their flight along -Z, AbilityVfx._update_entity), trailing a fine venom mist.
func _dart(e: Dictionary) -> Dictionary:
	var root := Node3D.new()
	fx.add_child(root)
	var spawn: Vector3 = e["pos"]
	root.global_position = spawn
	root.visible = false
	_dart_body(root)
	(_res("bead_mat") as ShaderMaterial).set_shader_parameter("alpha", 0.75 if fx.reduce_flashes else 1.0)
	var wake := fx._attached_stream(root, "spray", Color(VENOM, 0.7), null, {"speed": 0.1, "amount": 0.4, "scale": 0.45, "life": 0.6})
	return {"node": root, "kind": "projectile", "pos": spawn, "dir": Vector3.FORWARD,
		"tick": func(e2: Dictionary) -> void:
			if is_instance_valid(root) and not root.visible and Vector3(e2["pos"]).distance_squared_to(spawn) > 1e-6:
				root.visible = true,
		"end": func() -> void:
			if wake != null and is_instance_valid(wake):
				# the mist hangs where the dart was while it fades
				var wp := wake.global_position
				wake.reparent(fx)
				wake.global_position = wp
				fx.end_stream(wake)
			if is_instance_valid(root):
				root.queue_free()}


## A dart's pieces under `root`, pointing along -Z: a glossy black spine, a bead of venom at its tip
## and Slurry's pink barb tuft at its tail.
func _dart_body(root: Node3D) -> void:
	var spine := MeshInstance3D.new()
	spine.mesh = _res("needle") as Mesh
	spine.material_override = _res("needle_mat") as Material
	spine.rotation.x = -PI * 0.5          # the cylinder's narrow top (+Y) to the front (-Z)
	var bead := MeshInstance3D.new()
	bead.mesh = _res("bead") as Mesh
	bead.material_override = _res("bead_mat") as Material
	bead.position = Vector3(0, 0, -0.15)
	var barb := MeshInstance3D.new()
	barb.mesh = _res("barb") as Mesh
	barb.material_override = _res("barb_mat") as Material
	barb.position = Vector3(0, 0, 0.15)
	barb.scale = Vector3(1.0, 1.0, 1.7)
	for n: MeshInstance3D in [spine, bead, barb]:
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(n)


## A dart that hit sticks in its victim on the side facing Slurry and rides the victim's core
## segment until its Venom Dart status would wear off; at most STUCK_MAX per fighter (the oldest
## works loose).
func _stick_dart(fi: int, ev: Dictionary) -> void:
	var ti := int(ev.get("target", -1))
	var v := fx._view(ti)
	if v == null or v.body == null:
		return
	var seg := fx._core_index(ti)
	var seg_t := v.segment_world(seg)
	var core := fx.anchor(ti, "core")
	var into := core - mouth(fi)
	into.y *= 0.35
	if into.length_squared() < 1e-6:
		into = -fx._fwd(ti)
	into = into.normalized()
	# an effect hit lands on the victim's centre: the dart sits on its skin, on Slurry's side
	var flat := Vector3(-into.x, 0.0, -into.z)
	flat = flat.normalized() if flat.length_squared() > 1e-6 else fx._fwd(ti)
	var skin := _support(v.body.segments[seg] as BodyDef.Seg, seg_t.basis.inverse() * flat)
	var p := Vector3(seg_t.origin.x, core.y, seg_t.origin.z) + flat * maxf(skin - 0.04, 0.05) + Vector3.UP * fx._rng.randf_range(-0.1, 0.16)
	var root := Node3D.new()
	fx.add_child(root)
	_dart_body(root)
	var world := Transform3D(Basis.looking_at(into, Vector3.UP if absf(into.y) < 0.95 else Vector3.RIGHT), p)
	root.global_transform = world
	var mine := 0
	for s: Dictionary in _stuck:
		if int(s["victim"]) == ti and float(s["age"]) < STUCK_LIFE:
			mine += 1
	if mine >= STUCK_MAX:
		for s: Dictionary in _stuck:
			if int(s["victim"]) == ti and float(s["age"]) < STUCK_LIFE:
				s["age"] = STUCK_LIFE
				break
	_stuck.append({"node": root, "victim": ti, "seg": seg, "local": seg_t.affine_inverse() * world, "age": 0.0})
	var floor_y := fx._ground(ti).y
	fx.burst("gobs", p, -into + Vector3.UP * 0.3, GOO, GOO_SHEEN, {"amount": 0.2, "speed": 0.5, "scale": 0.5, "floor": floor_y})
	fx.burst("spray", p, -into, Color(VENOM, 0.8), null, {"amount": 0.2, "speed": 0.5})


func _update_stuck(delta: float) -> void:
	var i := _stuck.size() - 1
	while i >= 0:
		var s: Dictionary = _stuck[i]
		var n = s["node"]
		var vi := int(s["victim"])
		var v := fx._view(vi)
		var inf := fx._info(vi)
		s["age"] = float(s["age"]) + delta
		var age := float(s["age"])
		if not is_instance_valid(n) or v == null or bool(inf.get("out", false)) or age >= STUCK_LIFE + STUCK_FADE:
			if is_instance_valid(n):
				(n as Node).queue_free()
			_stuck.remove_at(i)
		else:
			var node: Node3D = n
			node.visible = not bool(inf.get("hidden", false))
			node.global_transform = v.segment_world(int(s["seg"])) * (s["local"] as Transform3D)
			if age > STUCK_LIFE:
				node.scale = Vector3.ONE * maxf(0.01, 1.0 - (age - STUCK_LIFE) / STUCK_FADE)     # works loose
		i -= 1


## ---- Acid Spray ------------------------------------------------------------------------------------

func _start_spray(fi: int) -> void:
	_end_spray(fi, true)
	var reach := 2.0
	var cone := 80.0
	var e := _pool_effect(fi, "acid_spray", "slurry_acid")
	if not e.is_empty():
		reach = float(e.get("radius", reach))
		cone = float(e.get("cone_deg", cone))
	var mi := MeshInstance3D.new()
	mi.mesh = FxKit.wall_mesh(32, 0.04)              # y = 0: the wide end, y = 1: the jaws
	var mat := FxKit.flow_material(VENOM, VENOM_HOT, {"cover": 0.55, "glow_k": 0.5, "scroll": Vector2(0.45, 3.6),
		"noise_scale": Vector2(7.0, 2.6), "edge_v": 0.25, "core": 0.85, "core_width": 0.28, "alpha": 0.0})
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(mi)
	_sprays[fi] = {"node": mi, "mat": mat, "len": 0.15, "reach": reach, "cone": cone, "age": 0.0, "ending": false, "end_t": 0.0}
	fx.burst("spray", mouth(fi), aim_dir(fi, -0.4), Color(VENOM, 0.8), null, {"amount": 0.4, "speed": 1.2, "spread": 0.5})


func _end_spray(fi: int, now := false) -> void:
	var s: Dictionary = _sprays.get(fi, {})
	if s.is_empty():
		return
	if now:
		if is_instance_valid(s["node"]):
			(s["node"] as Node).queue_free()
		_sprays.erase(fi)
		return
	s["ending"] = true
	# the last of it dribbles off the jaws
	fx.burst("gobs", mouth(fi), Vector3.DOWN, GOO, GOO_SHEEN, {"amount": 0.3, "speed": 0.3, "scale": 0.6, "floor": fx._ground(fi).y})


func _update_sprays(delta: float) -> void:
	for fi in _sprays.keys():
		var s: Dictionary = _sprays[fi]
		var n = s["node"]
		if not is_instance_valid(n):
			_sprays.erase(fi)
			continue
		var mi: MeshInstance3D = n
		s["age"] = float(s["age"]) + delta
		if not bool(s["ending"]) and not is_acting(fi):
			s["ending"] = true                      # cut off (hit, knocked down): the spray dies with the move
		var mat: ShaderMaterial = s["mat"]
		if bool(s["ending"]):
			s["end_t"] = float(s["end_t"]) + delta
			var k := clampf(float(s["end_t"]) / 0.2, 0.0, 1.0)
			mat.set_shader_parameter("dissolve", k)
			mat.set_shader_parameter("alpha", 1.0 - k)
			if k >= 1.0:
				mi.queue_free()
				_sprays.erase(fi)
				continue
		else:
			s["len"] = move_toward(float(s["len"]), float(s["reach"]), delta * 12.0)     # it gushes out to its reach
			mat.set_shader_parameter("alpha", clampf(float(s["age"]) / 0.08, 0.0, 1.0) * (0.75 if fx.reduce_flashes else 0.95))
		var from := mouth(fi)
		var d := _jaw_dir(fi, from, float(s["reach"]))
		var x := d.cross(Vector3.UP).normalized()
		var y := -d
		var z := x.cross(y).normalized()
		var l := float(s["len"])
		# a wide, flat fan whose half-width at its end follows the area's angle; it ripples as it pumps
		var half := l * tan(deg_to_rad(float(s["cone"]) * 0.5)) * (1.0 + 0.06 * sin(float(s["age"]) * 23.0))
		mi.global_transform = Transform3D(Basis(x * half, y * l, z * half * 0.32), from + d * l)


## Where the jaws point: the head's own heading (it hoses side to side within the cone) pitched
## down so the fan meets the floor at the spray's reach.
func _jaw_dir(fi: int, from: Vector3, reach: float) -> Vector3:
	var h := MathX.forward_of_yaw(fx._yaw(fi))
	var v := fx._view(fi)
	if v != null and v.body != null and v.body.seg_index.has("head"):
		var hz := v.segment_world(int(v.body.seg_index["head"])).basis.z
		hz.y = 0.0
		if hz.length_squared() > 0.04 and hz.normalized().dot(h) > 0.5:
			h = hz.normalized()
	var drop := maxf(from.y - fx._ground(fi).y, 0.2)
	var pitch := -atan2(drop * 0.85, reach)
	return (h * cos(pitch) + Vector3.UP * sin(pitch)).normalized()


func _acid_tick(fi: int, ev: Dictionary) -> void:
	var reach := float(ev.get("radius", 2.0))
	var cone := float(ev.get("cone_deg", 80.0))
	var s: Dictionary = _sprays.get(fi, {})
	if not s.is_empty():
		s["reach"] = reach
		s["cone"] = cone
	var from := mouth(fi)
	var d := _jaw_dir(fi, from, reach)
	var half := deg_to_rad(cone) * 0.5
	var floor_y := fx._ground(fi).y
	# droplets fan out and rain onto the floor, heavier gobs arc and splat, the acid hisses where it lands
	fx.burst("spray", from, d, Color(VENOM, 0.85), Color(VENOM_HOT, 0.85), {"speed": reach * 1.7, "spread": half * 0.85, "amount": 0.5, "life": 0.6})
	fx.burst("gobs", from, d + Vector3.UP * 0.15, GOO, GOO_SHEEN, {"speed": reach * 0.9, "spread": half * 0.7, "amount": 0.22, "scale": 0.6, "floor": floor_y})
	var o: Vector3 = ev.get("origin", fx._ground(fi))
	var yaw := float(ev.get("yaw", fx._yaw(fi)))
	var land := Vector3(o.x, floor_y, o.z) + MathX.forward_of_yaw(yaw) * reach * 0.6
	if fx._rng.randf() < 0.5:
		fx.burst("bubbles", land + Vector3.UP * 0.05, Vector3.UP, Color(VENOM, 0.85), null,
			{"box": Vector3(reach * 0.45, 0.02, reach * 0.25), "yaw": yaw, "amount": 0.35, "speed": 0.4})
	if fx._rng.randf() < 0.3:
		fx.burst("mist", land + Vector3.UP * 0.25, Vector3.UP, ACID_MIST, null, {"amount": 0.3, "speed": 0.4, "radius": reach * 0.3})
	# the true footprint shows now and then (the cone that can hit)
	if fx._rng.randf() < 0.25 and ev.has("origin"):
		fx.footprint("sludge", "cone", Vector3(o.x, floor_y, o.z), yaw, reach, {"cone_deg": cone, "strength": 0.5, "front": 0.6, "fill": 0.5}, 0.35, 0.05)


## ---- Coil Crush ------------------------------------------------------------------------------------

## The lunge caught `ti`: thick sludge coils wind up round its body and ride it until the crush (or
## until Slurry is knocked out of the move and lets go).
func _wrap(fi: int, ti: int) -> void:
	var v := fx._view(ti)
	if v == null or v.body == null:
		return
	_end_coil(fi, true)
	var r := _girth(ti, v) + 0.14
	var h := clampf(v.body.height * 0.85, 0.5, 1.6)
	var root := Node3D.new()
	fx.add_child(root)
	var g := fx._ground(ti)
	root.global_position = g
	var mi := MeshInstance3D.new()
	mi.mesh = FxKit.spiral_mesh(2.3, 1.0, 0.82, 0.34)
	var mat := FxKit.flow_material(GOO, GOO_SHEEN, {"additive": 0.15, "fresnel": 1.1, "scroll": Vector2(-0.5, 0.0),
		"noise_scale": Vector2(9.0, 1.4), "edge_v": 0.3, "core": 0.55, "core_width": 0.35, "alpha": 0.0})
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(r, 0.01, r)
	root.add_child(mi)
	_coils[fi] = {"node": root, "mesh": mi, "mat": mat, "victim": ti, "r": r, "h": h, "age": 0.0, "squeeze": -9.0,
		"ending": false, "end_t": 0.0, "burst": 1.0}
	fx.burst("gobs", fx.anchor(ti, "core"), Vector3.UP, GOO, GOO_SHEEN, {"amount": 0.5, "speed": 1.0, "radius": r * 0.6, "floor": g.y})
	fx.footprint("sludge", "circle", g, 0.0, r + 0.2, {"fill": 0.6, "strength": 0.7}, 1.0, 0.15)


func _end_coil(fi: int, now := false) -> void:
	var c: Dictionary = _coils.get(fi, {})
	if c.is_empty():
		return
	if now:
		if is_instance_valid(c["node"]):
			(c["node"] as Node).queue_free()
		_coils.erase(fi)
		return
	c["ending"] = true


func _update_coils(delta: float) -> void:
	for fi in _coils.keys():
		var c: Dictionary = _coils[fi]
		var n = c["node"]
		if not is_instance_valid(n):
			_coils.erase(fi)
			continue
		var root: Node3D = n
		var mi: MeshInstance3D = c["mesh"]
		var mat: ShaderMaterial = c["mat"]
		var vi := int(c["victim"])
		c["age"] = float(c["age"]) + delta
		var age := float(c["age"])
		if not bool(c["ending"]) and (not is_acting(fi) or fx._view(vi) == null or age > COIL_LIFE):
			c["ending"] = true          # Slurry was knocked out of the move (or the victim is gone): it lets go
		var tight := 1.0
		var since := age - float(c["squeeze"])
		if since >= 0.0 and since < 0.22:
			tight = 1.0 - 0.22 * sin(since / 0.22 * PI)          # a squeeze: the coils clench and relax
		var wind := clampf(age / 0.14, 0.0, 1.0)                 # winding on: the coils climb the body
		if bool(c["ending"]):
			c["end_t"] = float(c["end_t"]) + delta
			var k := clampf(float(c["end_t"]) / 0.25, 0.0, 1.0)
			mat.set_shader_parameter("dissolve", k)
			mat.set_shader_parameter("alpha", 1.0 - k)
			tight = lerpf(tight, float(c["burst"]), k)           # released (or flung apart by the crush)
			if k >= 1.0:
				root.queue_free()
				_coils.erase(fi)
				continue
		else:
			mat.set_shader_parameter("alpha", wind)
		if fx._view(vi) != null:
			root.global_position = fx._ground(vi)
		var r := float(c["r"]) * tight
		mi.scale = Vector3(r, maxf(float(c["h"]) * wind, 0.01), r)
		mi.rotation.y = age * 1.6        # the coils slide round as they grip


func _squeeze(fi: int, ev: Dictionary) -> void:
	var c: Dictionary = _coils.get(fi, {})
	if c.is_empty() or bool(c["ending"]):
		# nothing in the coils: a dry clench wrings a little goo out of the air
		var p: Vector3 = ev.get("pos", fx._ground(fi))
		fx.burst("gobs", p + Vector3.UP * 0.6, Vector3.UP, GOO, GOO_SHEEN, {"amount": 0.15, "speed": 0.4, "scale": 0.5, "floor": p.y})
		return
	c["squeeze"] = c["age"]
	var vi := int(c["victim"])
	var core := fx.anchor(vi, "core")
	var r := float(c["r"])
	# goo squeezed out between the coils, a wet squelch of droplets all round
	fx.burst("gobs", core, Vector3.UP, GOO, GOO_SHEEN, {"amount": 0.45, "speed": 1.4, "spread": 1.2, "radius": r * 0.7, "floor": fx._ground(vi).y})
	fx.burst("spray", core, Vector3.UP, Color(VENOM, 0.8), null, {"amount": 0.3, "speed": 1.0, "ring": true, "radius": r * 0.8})


func _crush(fi: int, ev: Dictionary) -> void:
	var at: Vector3 = ev.get("pos", fx._ground(fi))
	var r := float(ev.get("radius", 0.85))
	var c: Dictionary = _coils.get(fi, {})
	if not c.is_empty():
		at = fx._ground(int(c["victim"]))
		r = maxf(r, float(c["r"]) + 0.3)
		c["burst"] = 1.9           # the coils fly apart
		c["ending"] = true
	var g := Vector3(at.x, fx._ground(fi).y, at.z)
	fx.footprint("sludge", "circle", g, 0.0, r, {"fill": 0.7, "front": 0.9, "stain_a": 0.5}, 1.1, 0.1)
	fx.ring_wall(g, 0.25, r + 0.3, 0.6, GOO, GOO_SHEEN, 0.4, {"add": false, "lean": 0.75, "core": 0.8, "scroll": Vector2(0.2, -1.0)})
	fx.burst("gobs", g + Vector3.UP * 0.6, Vector3.UP, GOO, GOO_SHEEN, {"amount": 0.9, "speed": 2.4, "spread": 1.1, "floor": g.y})
	fx.burst("drops", g + Vector3.UP * 0.5, Vector3.UP, Color(VENOM, 0.85), Color(VENOM_HOT, 0.85), {"amount": 0.5, "speed": 1.6, "floor": g.y})
	fx.flash_light(g + Vector3.UP * 0.7, VENOM, 1.6, 3.0, 0.25)


## ---- Shed Skin -------------------------------------------------------------------------------------

## The old skin left standing in Slurry's pose: a translucent shell over every body part that holds
## a moment, sags toward the floor and flakes away.
func _shed(fi: int) -> void:
	var g := fx._ground(fi)
	fx.burst("drops", fx.anchor(fi, "core"), Vector3.UP, Color(HUSK, 0.7), null, {"amount": 0.45, "speed": 1.0, "radius": 0.3, "floor": g.y})
	fx.burst("mist", g + Vector3.UP * 0.5, Vector3.UP, Color(HUSK, 0.3), null, {"amount": 0.4, "radius": 0.4, "speed": 0.4})
	var v := fx._view(fi)
	if v == null or v.body == null:
		return
	var root := Node3D.new()
	fx.add_child(root)
	root.global_position = g
	var mat := FxKit.flow_material(HUSK, Color(0.95, 1.0, 0.82), {"additive": 0.2, "fresnel": 1.8, "scroll": Vector2(0.05, -0.2),
		"noise_scale": Vector2(6.0, 3.0), "edge_v": 0.0, "core": 0.5, "core_width": 0.6, "alpha": 0.0})
	for s: BodyDef.Seg in v.body.segments:
		var seg_t := v.segment_world(s.index)
		for sh: BodyDef.Shape in s.shapes:
			var mi := _husk_piece(sh, seg_t, g)
			mi.material_override = mat
			root.add_child(mi)
	_husks.append(root)
	var peak := 0.7 if fx.reduce_flashes else 0.85
	fx.animate(root, HUSK_LIFE, func(k: float, age: float) -> void:
		var sag := smoothstep(0.3, 1.0, k)
		root.scale = Vector3(1.0 + 0.1 * sag, maxf(0.05, 1.0 - 0.6 * sag), 1.0 + 0.1 * sag)
		mat.set_shader_parameter("alpha", clampf(age / 0.06, 0.0, 1.0) * (1.0 - smoothstep(0.65, 1.0, k)) * peak)
		mat.set_shader_parameter("dissolve", smoothstep(0.4, 1.0, k)))
	fx._later(0.4, func() -> void:
		fx.burst("feathers", g + Vector3.UP * 0.7, Vector3.UP, HUSK, Color(0.92, 0.95, 0.78), {"amount": 0.6, "radius": 0.35, "speed": 0.5, "floor": g.y}))


## One body part of the husk: a capsule (or a sphere) over the part's hit shape, placed relative to
## the husk's root at `origin`.
func _husk_piece(sh: BodyDef.Shape, seg_t: Transform3D, origin: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var r := sh.hit_r * 1.08
	var a := seg_t * sh.hit_a
	var b := seg_t * sh.hit_b
	var span := a.distance_to(b)
	mi.mesh = _husk_mesh(r, span)
	if span < 0.01:
		mi.transform = Transform3D(Basis.IDENTITY, a - origin)
	else:
		mi.transform = Transform3D(_along(b - a), (a + b) * 0.5 - origin)
	return mi


func _husk_mesh(r: float, span: float) -> Mesh:
	var key := "husk:%.3f:%.3f" % [r, span]
	if _shared.has(key):
		return _shared[key]
	var m: Mesh = null
	if span < 0.01:
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 12
		sm.rings = 6
		m = sm
	else:
		var cm := CapsuleMesh.new()
		cm.radius = r
		cm.height = span + r * 2.0
		cm.radial_segments = 12
		cm.rings = 3
		m = cm
	_shared[key] = m
	return m


## The slip back out of the skin: a slick smear along the way it slid, goo flicked off the front.
func _slip(fi: int, ev: Dictionary) -> void:
	var d: Vector3 = ev.get("dir", -fx._fwd(fi))
	d.y = 0.0
	d = d.normalized() if d.length_squared() > 1e-4 else -fx._fwd(fi)
	var g := fx._ground(fi)
	fx.footprint("sludge", "line", g, atan2(d.x, d.z), 0.0, {"length": 1.4, "width": 0.55, "fill": 0.65, "front": 0.3, "stain_a": 0.45}, 1.2, 0.3)
	fx.burst("gobs", fx.anchor(fi, "coil_low"), -d + Vector3.UP * 0.5, GOO, GOO_SHEEN, {"amount": 0.3, "speed": 0.8, "floor": g.y})


## The fresh scales gleam wet for as long as the buff really lasts.
func _fresh_scales(fi: int) -> void:
	var dur := 2.5
	var e := _pool_effect(fi, "shed_skin", "slurry_fresh_scales")
	if typeof(e.get("status", null)) == TYPE_DICTIONARY:
		dur = float((e["status"] as Dictionary).get("duration", dur))
	fx._stream_at(fi, "body1", Vector3.ZERO, dur, "glints", Color(0.8, 1.0, 0.6), null, {"amount": 0.25, "speed": 0.15, "radius": 0.2}, "slurry_scales")
	fx._stream_at(fi, "body3", Vector3.ZERO, dur, "glints", Color(0.8, 1.0, 0.6), null, {"amount": 0.2, "speed": 0.1, "radius": 0.25}, "slurry_scales")
	fx.burst("drops", fx.anchor(fi, "body2"), Vector3.UP, Color(0.7, 0.95, 0.5, 0.75), null, {"amount": 0.35, "speed": 0.6, "radius": 0.3, "floor": fx._ground(fi).y})


## Venom Molt (style): the husk bursts into a puddle where Slurry stood.
func _molt_burst(pos: Vector3, r: float) -> void:
	fx.footprint("sludge", "circle", pos, 0.0, r, {"fill": 0.6, "front": 0.9}, 0.8, 0.1)
	fx.ring_wall(pos, 0.2, r, 0.45, GOO, GOO_SHEEN, 0.35, {"add": false, "lean": 0.8, "core": 0.8})
	fx.burst("gobs", pos + Vector3.UP * 0.4, Vector3.UP, GOO, GOO_SHEEN, {"amount": 0.7, "speed": 1.6, "floor": pos.y})
	fx.burst("feathers", pos + Vector3.UP * 0.6, Vector3.UP, HUSK, Color(0.92, 0.95, 0.78), {"amount": 0.4, "radius": 0.3, "speed": 0.8, "floor": pos.y})


## ---- shared ------------------------------------------------------------------------------------------

## The effect of one of this fighter's pool moves drawn under `vfx` ({} when unknown), so effects
## take the numbers the move really uses (drilled styles included).
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


## How far a segment's body reaches from its pivot along a direction in its own frame (the support
## distance of its hit capsules): darts sit on the skin, coils fit round the body.
static func _support(s: BodyDef.Seg, d: Vector3) -> float:
	var best := 0.0
	for sh: BodyDef.Shape in s.shapes:
		best = maxf(best, maxf(sh.hit_a.dot(d), sh.hit_b.dot(d)) + sh.hit_r)
	return best


## A fighter's half-width round its core (the widest of its four sides).
func _girth(fi: int, v: CreatureView) -> float:
	var s: BodyDef.Seg = v.body.segments[fx._core_index(fi)]
	var best := 0.25
	for d: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		best = maxf(best, _support(s, d))
	return best


## A basis whose Y axis runs along `d` (capsule meshes stand along Y).
static func _along(d: Vector3) -> Basis:
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))


## Meshes and materials every dart shares, built on first use.
func _res(key: String) -> Resource:
	if _shared.has(key):
		return _shared[key]
	var r: Resource = null
	match key:
		"needle":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.006
			cm.bottom_radius = 0.028
			cm.height = 0.32
			cm.radial_segments = 6
			cm.rings = 1
			r = cm
		"bead":
			r = fx._sphere(0.034, 8)
		"barb":
			r = fx._sphere(0.03, 6)
		"needle_mat":
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.1, 0.16, 0.05)
			m.roughness = 0.18
			m.metallic_specular = 0.9
			m.rim_enabled = true
			m.rim = 0.6
			m.emission_enabled = true
			m.emission = Color(0.14, 0.3, 0.03)
			r = m
		"bead_mat":
			r = FxKit.flow_material(VENOM, VENOM_HOT, {"additive": 0.7, "fresnel": 1.2, "scroll": Vector2(0.3, -1.0),
				"noise_scale": Vector2(4.0, 3.0), "edge_v": 0.0, "core": 0.5, "core_width": 0.6, "alpha": 1.0})
		"barb_mat":
			var bm := StandardMaterial3D.new()
			bm.albedo_color = BARB
			bm.roughness = 0.55
			r = bm
	_shared[key] = r
	return r
