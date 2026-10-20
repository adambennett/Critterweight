class_name CreatureFxRig
extends RefCounted
## Expressions and secondary motion for a creature model (v0.9.17, docs/ART_PIPELINE.md §5b).
## Drives the model's optional view bones ("fx_*", children of segment bones, never physics):
##   fx_lid_l / fx_lid_r      eyelids: blinks, squints when hurt or attacking, shut on a knockout
##   fx_eye_l / fx_eye_r      iris + pupil: slide toward what the fighter looks at, small saccades
##   fx_brow_l / fx_brow_r    brows: knit when attacking, lift when hurt or surprised
##   fx_jaw                   mouth: opens on effort, pain, taunts and knockouts; breathes at rest
##   fx_spring_<name>_<n>     crests, fins, ears, chains, hoses, tails: a damped spring per link that
##                            lags behind its parent's motion (and gravity), so they swing and settle
##   fx_glow_*                (reserved) emissive parts the shader animates; nothing to drive here
## Pose space: every fx bone keeps its rest pose (from the GLB) and gets a local rotation/offset on
## top; CreatureView composes rest * fx local after posing the segment bones. Deterministic per
## seed (blink timing) but purely visual: nothing here reads or writes the simulation.

const BLINK_MIN := 2.2
const BLINK_MAX := 5.6
const BLINK_TIME := 0.16
const LID_CLOSE_DEG := 72.0        ## rotation that closes a lid from its modelled (open) pose
const PUPIL_TRAVEL := 0.35         ## of the bone's own "reach" (extras) or 1 cm by default
const SPRING_K := 70.0
const SPRING_DAMP := 9.0
const SPRING_GAIN := 0.045         ## radians per m/s^2 of parent acceleration
const SPRING_MAX := 0.75

var skeleton: Skeleton3D
var bones := {}            ## role -> Array[int] (lid, eye, brow, jaw, spring)
var rest := {}             ## bone index -> Transform3D (local rest)
var local := {}            ## bone index -> Transform3D (procedural local pose this frame)
var params := {}           ## from the GLB extras look.fx: {pupil_reach, lid_axis, jaw_deg, ...}
var mood := "neutral"      ## neutral | attack | hurt | ko | guard | taunt | happy | tired | surprised
var look_target := Vector3.INF
var _t := 0.0
var _blink_at := 2.0
var _blink_phase := -1.0
var _rng := RandomNumberGenerator.new()
var _springs := {}         ## bone -> {angle: Vector2, vel: Vector2, prev: Vector3, prev_v: Vector3}
var _saccade := Vector2.ZERO
var _saccade_at := 0.0
var _mood_amount := {}     ## smoothed expression weights


func _init(sk: Skeleton3D, extras: Dictionary, seed_value: int) -> void:
	skeleton = sk
	params = (extras.get("look", {}) as Dictionary).get("fx", {}) if typeof(extras.get("look", {})) == TYPE_DICTIONARY else {}
	_rng.seed = seed_value
	_blink_at = _rng.randf_range(0.6, 2.4)
	for b in sk.get_bone_count():
		var n := sk.get_bone_name(b)
		if not n.begins_with("fx_"):
			continue
		var role := n.get_slice("_", 1)
		if not bones.has(role):
			bones[role] = []
		(bones[role] as Array).append(b)
		rest[b] = sk.get_bone_rest(b)
		local[b] = Transform3D.IDENTITY


func has_bones() -> bool:
	return not rest.is_empty()


func is_fx_bone(b: int) -> bool:
	return rest.has(b)


## One rendered frame. bone_global: Callable(bone) -> Transform3D (the bone's world transform as
## CreatureView placed it this frame, before fx); dt: real seconds.
func update(dt: float, bone_global: Callable) -> void:
	_t += dt
	_update_weights(dt)
	var blink := _blink(dt)
	var squint := 0.0
	squint += 0.22 * float(_mood_amount.get("attack", 0.0))
	squint += 0.45 * float(_mood_amount.get("hurt", 0.0))
	squint += 0.3 * float(_mood_amount.get("tired", 0.0))
	squint -= 0.18 * float(_mood_amount.get("surprised", 0.0))
	var closed := maxf(blink, float(_mood_amount.get("ko", 0.0)))
	var lid := clampf(maxf(closed, squint), -0.25, 1.0)
	for b in bones.get("lid", []):
		if str(params.get("lid_mode", "scale")) == "rotate":
			var axis := _vec(params.get("lid_axis", [1, 0, 0]))
			local[b] = Transform3D(Basis(axis.normalized(), deg_to_rad(LID_CLOSE_DEG) * lid), Vector3.ZERO)
		else:
			# the lid is modelled CLOSED below its bone (at the top of the eye): open = squashed to a
			# thin rim, closed = full height (never exactly zero: degenerate normals)
			var open_rim := float(params.get("lid_rest", 0.12))
			local[b] = Transform3D(Basis.from_scale(Vector3(1.0, clampf(lerpf(open_rim, 1.0, maxf(lid, 0.0)), 0.04, 1.0), 1.0)), Vector3.ZERO)
	# eyes follow the opponent (pupil offset in the head's frame), with small saccades
	if _t >= _saccade_at:
		_saccade = Vector2(_rng.randf_range(-0.25, 0.25), _rng.randf_range(-0.15, 0.15))
		_saccade_at = _t + _rng.randf_range(0.6, 1.8)
	var reach := float(params.get("pupil_reach", 0.01)) * PUPIL_TRAVEL / 0.35
	for b in bones.get("eye", []):
		var g: Transform3D = bone_global.call(b)
		var d := Vector2.ZERO
		if look_target != Vector3.INF:
			var to: Vector3 = g.basis.inverse() * (look_target - g.origin)
			if to.length() > 0.05:
				to = to.normalized()
				d = Vector2(to.x, to.y) * 1.4
		d += _saccade
		if float(_mood_amount.get("ko", 0.0)) > 0.5:
			d = Vector2(sin(_t * 9.0), cos(_t * 7.0)) * 0.6       # dazed
		d = d.limit_length(1.0)
		local[b] = Transform3D(Basis.IDENTITY, Vector3(d.x, d.y, 0.0) * reach)
	# brows: knit (inner down) for effort, lift for pain/surprise
	for b in bones.get("brow", []):
		var side := 1.0 if skeleton.get_bone_name(b).ends_with("_l") else -1.0
		var knit := 0.35 * float(_mood_amount.get("attack", 0.0)) + 0.2 * float(_mood_amount.get("guard", 0.0))
		var lift := 0.5 * float(_mood_amount.get("hurt", 0.0)) + 0.6 * float(_mood_amount.get("surprised", 0.0)) + 0.3 * float(_mood_amount.get("happy", 0.0))
		var drop := float(params.get("brow_drop", 0.012))
		local[b] = Transform3D(Basis(Vector3(0, 0, 1), side * 0.35 * (knit - lift * 0.6)), Vector3(0, drop * (lift - knit), 0))
	# jaw: effort, pain, taunts, knockouts, a slow breath at rest
	for b in bones.get("jaw", []):
		var open := 0.08 + 0.06 * sin(_t * 2.4)
		open += 0.5 * float(_mood_amount.get("attack", 0.0)) + 0.8 * float(_mood_amount.get("hurt", 0.0))
		open += 0.9 * float(_mood_amount.get("taunt", 0.0)) + 1.0 * float(_mood_amount.get("ko", 0.0)) + 0.6 * float(_mood_amount.get("happy", 0.0))
		var axis2 := _vec(params.get("jaw_axis", [1, 0, 0]))
		local[b] = Transform3D(Basis(axis2.normalized(), deg_to_rad(float(params.get("jaw_deg", 16.0))) * clampf(open, 0.0, 1.0)), Vector3.ZERO)
	# springs
	for b in bones.get("spring", []):
		_spring(b, dt, bone_global)


func _update_weights(dt: float) -> void:
	for m in ["attack", "hurt", "ko", "guard", "taunt", "happy", "tired", "surprised"]:
		var target := 1.0 if mood == m else 0.0
		var rate := 14.0 if target > 0.5 else 5.0
		_mood_amount[m] = move_toward(float(_mood_amount.get(m, 0.0)), target, rate * dt)


func _blink(dt: float) -> float:
	if _blink_phase < 0.0 and _t >= _blink_at:
		_blink_phase = 0.0
	if _blink_phase >= 0.0:
		_blink_phase += dt
		var p := _blink_phase / BLINK_TIME
		if p >= 1.0:
			_blink_phase = -1.0
			_blink_at = _t + _rng.randf_range(BLINK_MIN, BLINK_MAX)
			if _rng.randf() < 0.18:
				_blink_at = _t + 0.22         # a double blink now and then
			return 0.0
		return sin(p * PI)
	return 0.0


## A damped angular spring per link: the link lags its parent's acceleration (and leans with
## gravity relative to its rest direction), then settles. Chains get looser down the chain.
func _spring(b: int, dt: float, bone_global: Callable) -> void:
	if dt <= 0.0:
		return
	var parent := skeleton.get_bone_parent(b)
	var pg: Transform3D = bone_global.call(parent) if parent >= 0 else Transform3D.IDENTITY
	var here: Vector3 = (pg * (rest[b] as Transform3D)).origin
	var s: Dictionary = _springs.get(b, {})
	if s.is_empty():
		s = {"angle": Vector2.ZERO, "vel": Vector2.ZERO, "prev": here, "prev_v": Vector3.ZERO}
	var v: Vector3 = (here - (s["prev"] as Vector3)) / dt
	var a: Vector3 = (v - (s["prev_v"] as Vector3)) / dt
	s["prev"] = here
	s["prev_v"] = v
	if a.length() > 200.0:
		a = Vector3.ZERO          # a teleport (respawn, ring-out return): do not whip
	var bn := skeleton.get_bone_name(b)
	var last := bn.get_slice("_", bn.get_slice_count("_") - 1)
	var link := int(last) if last.is_valid_int() else 0
	var gain := SPRING_GAIN * (1.0 + 0.35 * link) * float(params.get("spring_gain", 1.0))
	# the force in the parent's frame (x = sideways swing, y = forward/back swing)
	var local_a: Vector3 = pg.basis.inverse() * (-a)
	var force := Vector2(local_a.x, -local_a.z) * gain
	var angle: Vector2 = s["angle"]
	var vel: Vector2 = s["vel"]
	var k := SPRING_K * float(params.get("spring_stiffness", 1.0)) / (1.0 + 0.3 * link)
	var acc := (force * k) - angle * k - vel * SPRING_DAMP
	vel += acc * dt
	angle += vel * dt
	angle = angle.limit_length(SPRING_MAX)
	s["angle"] = angle
	s["vel"] = vel
	_springs[b] = s
	local[b] = Transform3D(Basis(Vector3(0, 0, 1), angle.x) * Basis(Vector3(1, 0, 0), angle.y), Vector3.ZERO)


static func _vec(a) -> Vector3:
	if typeof(a) == TYPE_ARRAY and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.RIGHT
