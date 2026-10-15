class_name PolicyObs
extends RefCounted
## obs_v1 — the observation contract shared by AI Lab training, recording and live matches
## (docs/AI_LAB.md "Observation contract"). One encoder instance per controlled fighter; it is
## stateful only for the short history and the perception lag.
##
## Only information a player could perceive is used: own vitals/cooldowns/state (HUD and body
## feel), the opponent's visible body (relative position, velocity, facing), its visible state
## and move phase (animation), its HUD bars, arena walls and props, visible projectiles/zones,
## the round clock, and our own previous action. Never: the opponent's input, buffers, AI state,
## RNG, hidden timers, or anything from the future.
##
## Perception lag: everything about OTHER fighters and their projectiles ("opponent features")
## is taken from the snapshot of the previous decision when `target_lag` = 1 (≈67 ms at 15 Hz),
## so with the action repeat the policy reacts in 67–133 ms — fast, but not frame-perfect.
##
## All features are normalized to roughly [-1, 1]. Layout = NAMES (index = position); changing
## the meaning or order of any feature requires a new version (obs_v2) — policies record the
## version they were trained with and are rejected when it does not match.

const VERSION := "obs_v1"

const NAMES: PackedStringArray = [
	# ---- self (37) ----
	"self_health", "self_stamina", "self_poise", "self_hype", "self_juice_ready", "self_juiced", "self_crash",
	"self_ab1_ready", "self_ab1_cd", "self_ab2_ready", "self_ab2_cd",
	"self_st_neutral", "self_st_acting", "self_st_guard", "self_st_dodge", "self_st_stunned", "self_st_down",
	"self_st_grabbing", "self_st_held", "self_st_other",
	"self_mv_progress", "self_mv_windup", "self_mv_active", "self_mv_cancel",
	"self_mv_light", "self_mv_heavy", "self_mv_ability", "self_mv_grab", "self_charge",
	"self_vel_left", "self_vel_fwd", "self_airborne", "self_evading",
	"self_status_count", "self_status_speed", "self_status_dmg_taken", "self_status_dmg_dealt",
	# ---- target (39, lagged) ----
	"tgt_present", "tgt_rel_left", "tgt_rel_fwd", "tgt_dist", "tgt_bear_sin", "tgt_bear_cos",
	"tgt_face_sin", "tgt_face_cos", "tgt_vel_left", "tgt_vel_fwd",
	"tgt_health", "tgt_stamina", "tgt_hype", "tgt_juiced", "tgt_ab1_cd", "tgt_ab2_cd",
	"tgt_st_neutral", "tgt_st_acting", "tgt_st_guard", "tgt_st_dodge", "tgt_st_stunned", "tgt_st_down",
	"tgt_st_grabbing", "tgt_st_held", "tgt_st_other",
	"tgt_mv_progress", "tgt_mv_windup", "tgt_mv_active", "tgt_mv_recovery",
	"tgt_mv_light", "tgt_mv_heavy", "tgt_mv_ability", "tgt_mv_grab", "tgt_mv_time_to_active",
	"tgt_airborne", "tgt_evading", "tgt_status_count", "tgt_status_speed", "tgt_wall_dist",
	# ---- environment (19) ----
	"wall_fwd", "wall_fwd_left", "wall_left", "wall_back_left", "wall_back", "wall_back_right", "wall_right", "wall_fwd_right",
	"arena_ringout", "enemies_other", "enemy_other_dist",
	"proj_present", "proj_left", "proj_fwd", "proj_vel_left", "proj_vel_fwd",
	"hazard_dist", "hazard_inside", "round_time_left",
	# ---- history (23) ----
	"prev_move_none", "prev_move_toward", "prev_move_away", "prev_move_left", "prev_move_right",
	"prev_move_toward_left", "prev_move_toward_right", "prev_move_away_left", "prev_move_away_right",
	"prev_btn_none", "prev_btn_light", "prev_btn_heavy", "prev_btn_heavy_hold", "prev_btn_guard_hold", "prev_btn_guard_tap",
	"prev_btn_dodge", "prev_btn_grab", "prev_btn_ability1", "prev_btn_ability2", "prev_btn_juice", "prev_btn_taunt",
	"self_dmg_recent", "tgt_dmg_recent",
]
const SIZE := 118
const SELF_START := 0
const TARGET_START := 37
const TARGET_SIZE := 39
const ENV_START := 76
const ENV_SIZE := 19
const HIST_START := 95

const POS_SCALE := 8.0          ## metres for relative positions
const VEL_SCALE := 6.0          ## m/s for velocities
const PROJ_VEL_SCALE := 15.0
const RAY_DIRS := 8
## cos/sin of the 8 ray angles (0°, 45°, ... counter-clockwise from forward toward the left)
const RAY_C: PackedFloat32Array = [1.0, 0.70710678, 0.0, -0.70710678, -1.0, -0.70710678, 0.0, 0.70710678]
const RAY_S: PackedFloat32Array = [0.0, 0.70710678, 1.0, 0.70710678, 0.0, -0.70710678, -1.0, -0.70710678]
## octagon wall normals (ArenaDef.clamp_point uses n = (cos(k·45°), 0, sin(k·45°)))
const OCT_NX: PackedFloat32Array = [1.0, 0.70710678, 0.0, -0.70710678, -1.0, -0.70710678, 0.0, 0.70710678]
const OCT_NZ: PackedFloat32Array = [0.0, 0.70710678, 1.0, 0.70710678, 0.0, -0.70710678, -1.0, -0.70710678]
const OCT_NX4A := Vector4(1.0, 0.70710678, 0.0, -0.70710678)
const OCT_NX4B := Vector4(-1.0, -0.70710678, 0.0, 0.70710678)
const OCT_NZ4A := Vector4(0.0, 0.70710678, 1.0, 0.70710678)
const OCT_NZ4B := Vector4(0.0, -0.70710678, -1.0, -0.70710678)

var target_lag := 1             ## decisions of perception lag for opponent features (0 or 1)
var _lag_block := PackedFloat32Array()      ## opponent features captured at the previous decision
var _lag_target: Fighter = null
var _lag_other := PackedFloat32Array()      ## [enemies_other, enemy_other_dist, proj x5]
var _prev_self_health := -1.0
var _prev_tgt_health := -1.0
var _lag_tgt_health := -1.0
var _ray := PhysicsRayQueryParameters3D.new()


func _init(lag := 1) -> void:
	target_lag = clampi(lag, 0, 1)
	_ray.collision_mask = Rig.LAYER_PROPS
	_ray.collide_with_areas = false


func reset() -> void:
	_lag_block = PackedFloat32Array()
	_lag_target = null
	_lag_other = PackedFloat32Array()
	_prev_self_health = -1.0
	_prev_tgt_health = -1.0
	_lag_tgt_health = -1.0


## Builds the observation for fighter `f` at a decision tick. prev_move / prev_button are the
## classes this fighter used during the previous window (0/0 at the start).
func encode(f: Fighter, sim: MatchSim, prev_move: int, prev_button: int) -> PackedFloat32Array:
	var o := PackedFloat32Array()
	o.resize(SIZE)
	var yaw := f.facing_yaw
	var fwd := MathX.forward_of_yaw(yaw)
	var left := Vector3(fwd.z, 0.0, -fwd.x)
	var p := f.pos()
	_encode_self(o, f, fwd, left)
	# opponent features: current snapshot, then swapped with the lagged one if lag is on
	var tgt := f.target
	var cur_block := _target_block(f, tgt, p, fwd, left, sim)
	var cur_other := _other_block(f, tgt, p, fwd, left, sim)
	var use_block := cur_block
	var use_other := cur_other
	if target_lag > 0 and _lag_block.size() == TARGET_SIZE and _lag_target == tgt:
		use_block = _lag_block
		use_other = _lag_other
	_lag_block = cur_block
	_lag_other = cur_other
	_lag_target = tgt
	for k in TARGET_SIZE:
		o[TARGET_START + k] = use_block[k]
	_encode_env(o, f, p, fwd, left, sim, use_other)
	# history
	var h := HIST_START
	o[h + clampi(prev_move, 0, PolicyActions.MOVE_COUNT - 1)] = 1.0
	o[h + PolicyActions.MOVE_COUNT + clampi(prev_button, 0, PolicyActions.BUTTON_COUNT - 1)] = 1.0
	var sh := f.health_frac()
	o[h + 21] = clampf((_prev_self_health - sh) * 5.0, 0.0, 1.0) if _prev_self_health >= 0.0 else 0.0
	_prev_self_health = sh
	# target damage uses the (possibly lagged) target health so it never runs ahead of perception
	var th := use_block[10] if use_block[0] > 0.5 else -1.0
	o[h + 22] = clampf((_lag_tgt_health - th) * 5.0, 0.0, 1.0) if (_lag_tgt_health >= 0.0 and th >= 0.0) else 0.0
	_lag_tgt_health = th
	return o


static func _state_group(st: int) -> int:
	match st:
		Fighter.State.NEUTRAL:
			return 0
		Fighter.State.ATTACK, Fighter.State.ABILITY:
			return 1
		Fighter.State.GUARD:
			return 2
		Fighter.State.DODGE:
			return 3
		Fighter.State.HITSTUN, Fighter.State.GUARD_BREAK:
			return 4
		Fighter.State.KNOCKDOWN, Fighter.State.DOWN, Fighter.State.GETUP:
			return 5
		Fighter.State.GRABBING:
			return 6
		Fighter.State.HELD:
			return 7
	return 8


static func _class_index(f: Fighter) -> int:
	if f.move == null:
		return -1
	match f.current_move_class():
		"light":
			return 0
		"heavy":
			return 1
		"ability", "juice":
			return 2
		"grab":
			return 3
	return -1


func _encode_self(o: PackedFloat32Array, f: Fighter, fwd: Vector3, left: Vector3) -> void:
	o[0] = f.health_frac()
	o[1] = clampf(f.stamina / maxf(f.max_stamina, 1.0), 0.0, 1.0)
	o[2] = clampf(f.poise / maxf(f.effective_max_poise(), 1.0), 0.0, 1.0)
	o[3] = clampf(f.hype / 100.0, 0.0, 1.0)
	var juiced := f.time < f.juiced_until
	o[4] = 1.0 if (f.hype >= 100.0 and f.creature.abilities.has("juice") and not juiced) else 0.0
	o[5] = 1.0 if juiced else 0.0
	o[6] = 1.0 if f.time < f.crash_until else 0.0
	_ability(o, 7, f, "ability1")
	_ability(o, 9, f, "ability2")
	o[11 + _state_group(f.state)] = 1.0
	var acting := (f.state == Fighter.State.ATTACK or f.state == Fighter.State.ABILITY or f.state == Fighter.State.TAUNT) and f.move != null
	if acting:
		var m := f.move
		var t := f.state_time
		o[20] = clampf(t / maxf(m.duration, 0.01), 0.0, 1.0)
		o[21] = 1.0 if t < m.first_active() else 0.0
		o[22] = 1.0 if m.window_index(t) >= 0 else 0.0
		o[23] = 1.0 if t >= m.cancel_t0 else 0.0
		var ci := _class_index(f)
		if ci >= 0:
			o[24 + ci] = 1.0
	o[28] = clampf(f.move_charge, 0.0, 1.0)
	var v := f.rig.root().linear_velocity
	o[29] = clampf(v.dot(left) / VEL_SCALE, -1.0, 1.0)
	o[30] = clampf(v.dot(fwd) / VEL_SCALE, -1.0, 1.0)
	o[31] = 0.0 if f.rig.grounded else 1.0
	o[32] = 1.0 if f.is_evading() else 0.0
	_statuses(o, 33, f, true)


func _ability(o: PackedFloat32Array, at: int, f: Fighter, slot: String) -> void:
	if not f.creature.abilities.has(slot):
		return
	var cd := f.cooldown_frac(slot)
	o[at] = 1.0 if cd <= 0.0 else 0.0
	o[at + 1] = cd


func _statuses(o: PackedFloat32Array, at: int, f: Fighter, full: bool) -> void:
	var n := f.statuses.active.size()
	o[at] = clampf(float(n) / 3.0, 0.0, 1.0)
	if n == 0:
		return
	o[at + 1] = clampf(f.statuses.speed_mult() - 1.0, -1.0, 1.0)
	if full:
		o[at + 2] = clampf(f.statuses.damage_taken_mult() - 1.0, -1.0, 1.0)
		o[at + 3] = clampf(f.statuses.damage_dealt_mult() - 1.0, -1.0, 1.0)


## The 39 target features (index 0 == tgt_present), in the frame of `f`.
func _target_block(f: Fighter, t: Fighter, p: Vector3, fwd: Vector3, left: Vector3, sim: MatchSim) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(TARGET_SIZE)
	if t == null or t.is_out():
		return b
	b[0] = 1.0
	var to := t.pos() - p
	to.y = 0.0
	var dist := to.length()
	var lx := to.dot(left)
	var lz := to.dot(fwd)
	b[1] = clampf(lx / POS_SCALE, -1.5, 1.5)
	b[2] = clampf(lz / POS_SCALE, -1.5, 1.5)
	b[3] = clampf(dist / POS_SCALE, 0.0, 2.0)
	if dist > 1e-3:
		b[4] = lx / dist
		b[5] = lz / dist
	else:
		b[5] = 1.0
	# where the target faces relative to the line toward us (cos = 1: looking straight at us)
	var tf := t.forward()
	var back := -to / maxf(dist, 1e-3)
	var tleft := Vector3(back.z, 0.0, -back.x)
	b[6] = tf.dot(tleft)
	b[7] = tf.dot(back)
	var tv := t.rig.root().linear_velocity
	b[8] = clampf(tv.dot(left) / VEL_SCALE, -1.0, 1.0)
	b[9] = clampf(tv.dot(fwd) / VEL_SCALE, -1.0, 1.0)
	b[10] = t.health_frac()
	b[11] = clampf(t.stamina / maxf(t.max_stamina, 1.0), 0.0, 1.0)
	b[12] = clampf(t.hype / 100.0, 0.0, 1.0)
	b[13] = 1.0 if t.time < t.juiced_until else 0.0
	b[14] = t.cooldown_frac("ability1") if t.creature.abilities.has("ability1") else 0.0
	b[15] = t.cooldown_frac("ability2") if t.creature.abilities.has("ability2") else 0.0
	b[16 + _state_group(t.state)] = 1.0
	var acting := (t.state == Fighter.State.ATTACK or t.state == Fighter.State.ABILITY or t.state == Fighter.State.TAUNT) and t.move != null
	if acting:
		var m := t.move
		var st := t.state_time
		var fa := m.first_active()
		b[25] = clampf(st / maxf(m.duration, 0.01), 0.0, 1.0)
		b[26] = 1.0 if st < fa else 0.0
		b[27] = 1.0 if m.window_index(st) >= 0 else 0.0
		var last_end := 0.0
		for w in m.windows:
			last_end = maxf(last_end, float(w["t1"]))
		b[28] = 1.0 if (not m.windows.is_empty() and st > last_end) else 0.0
		var ci := _class_index(t)
		if ci >= 0:
			b[29 + ci] = 1.0
		if st < fa:
			b[33] = clampf((fa - st) / 0.5, 0.0, 1.0)
	b[34] = 0.0 if t.rig.grounded else 1.0
	b[35] = 1.0 if t.is_evading() else 0.0
	_statuses(b, 36, t, false)
	if sim != null and sim.arena != null:
		b[38] = clampf(_boundary_dist(sim.arena, t.pos()) / maxf(sim.arena.radius, 1.0), 0.0, 1.0)
	return b


## [enemies_other, enemy_other_dist, proj_present, proj_left, proj_fwd, proj_vel_left, proj_vel_fwd]
func _other_block(f: Fighter, t: Fighter, p: Vector3, fwd: Vector3, left: Vector3, sim: MatchSim) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(7)
	b[1] = 1.0
	if sim == null:
		return b
	var others := 0
	var nearest := INF
	for o: Fighter in sim.fighters:
		if o == f or o == t or o.is_out() or not sim.are_enemies(f, o):
			continue
		others += 1
		nearest = minf(nearest, Vector2(o.pos().x - p.x, o.pos().z - p.z).length())
	b[0] = clampf(float(others) / 3.0, 0.0, 1.0)
	if others > 0:
		b[1] = clampf(nearest / POS_SCALE, 0.0, 1.0)
	# nearest hostile projectile
	var best_d := INF
	var best: Dictionary = {}
	for ent: Dictionary in sim.effects.entities:
		if str(ent["kind"]) != "projectile":
			continue
		if int(ent["owner"]) == f.index or (int(ent["team"]) == f.team and not bool(sim.rules.get("friendly_fire", false))):
			continue
		var ep: Vector3 = ent["pos"]
		var d := Vector2(ep.x - p.x, ep.z - p.z).length()
		if d < best_d:
			best_d = d
			best = ent
	if not best.is_empty() and best_d < POS_SCALE * 1.5:
		var rel: Vector3 = (best["pos"] as Vector3) - p
		var vel: Vector3 = best["vel"]
		b[2] = 1.0
		b[3] = clampf(rel.dot(left) / POS_SCALE, -1.5, 1.5)
		b[4] = clampf(rel.dot(fwd) / POS_SCALE, -1.5, 1.5)
		b[5] = clampf(vel.dot(left) / PROJ_VEL_SCALE, -1.0, 1.0)
		b[6] = clampf(vel.dot(fwd) / PROJ_VEL_SCALE, -1.0, 1.0)
	return b


func _encode_env(o: PackedFloat32Array, f: Fighter, p: Vector3, fwd: Vector3, left: Vector3, sim: MatchSim, other: PackedFloat32Array) -> void:
	var e := ENV_START
	var arena: ArenaDef = sim.arena if sim != null else null
	var radius := arena.radius if arena != null else 5.0
	var max_d := radius * 2.0
	var space: PhysicsDirectSpaceState3D = null
	if sim != null and arena != null and (not arena.props.is_empty() or _has_prop_entities(sim)):
		space = f.get_world_3d().direct_space_state
		_ray.exclude = f.rig.rids
	var octagon := arena != null and arena.base == "octagon"
	var num_a := Vector4()
	var num_b := Vector4()
	if octagon:
		# distance to each wall plane along its normal (positive inside the cage)
		num_a = (Vector4.ONE * radius - (OCT_NX4A * p.x + OCT_NZ4A * p.z)).maxf(0.01)
		num_b = (Vector4.ONE * radius - (OCT_NX4B * p.x + OCT_NZ4B * p.z)).maxf(0.01)
	for k in RAY_DIRS:
		# k = 0 forward, then counter-clockwise seen from above: fwd-left, left, back-left, ...
		var d := fwd * RAY_C[k] + left * RAY_S[k]
		var dist := max_d
		if octagon:
			# ray/plane distances for all 8 walls at once; walls behind the ray get a huge value
			var ta := num_a / (OCT_NX4A * d.x + OCT_NZ4A * d.z).maxf(1e-6)
			var tb := num_b / (OCT_NX4B * d.x + OCT_NZ4B * d.z).maxf(1e-6)
			var tm := ta.min(tb)
			dist = minf(dist, maxf(0.0, minf(minf(tm.x, tm.y), minf(tm.z, tm.w))))
		elif arena != null:
			dist = minf(dist, _ray_to_boundary(arena, p, d))
		if space != null:
			_ray.from = Vector3(p.x, 0.6, p.z)
			_ray.to = _ray.from + d * dist
			var hit := space.intersect_ray(_ray)
			if not hit.is_empty():
				dist = minf(dist, Vector2((hit["position"] as Vector3).x - p.x, (hit["position"] as Vector3).z - p.z).length())
		o[e + k] = clampf(dist / max_d, 0.0, 1.0)
	o[e + 8] = 1.0 if (arena != null and arena.ringout) else 0.0
	o[e + 9] = other[0]
	o[e + 10] = other[1]
	for k in 5:
		o[e + 11 + k] = other[2 + k]
	# nearest hostile zone (hazards and enemy zones)
	var hz_d := INF
	var inside := false
	if sim != null:
		for ent: Dictionary in sim.effects.entities:
			if str(ent["kind"]) != "zone":
				continue
			var owner := int(ent["owner"])
			if owner == f.index:
				continue
			if owner >= 0 and owner < sim.fighters.size() and not sim.are_enemies(f, sim.fighters[owner]):
				continue
			if bool((ent["e"] as Dictionary).get("cosmetic", false)):
				continue
			var zp: Vector3 = ent["pos"]
			var edge := Vector2(zp.x - p.x, zp.z - p.z).length() - float(ent["radius"])
			if edge <= 0.0:
				inside = true
			hz_d = minf(hz_d, maxf(edge, 0.0))
	o[e + 16] = clampf(hz_d / 5.0, 0.0, 1.0) if hz_d < INF else 1.0
	o[e + 17] = 1.0 if inside else 0.0
	o[e + 18] = 1.0
	if sim != null and sim.mode != null:
		var rt := float(sim.rules.get("round_time", 0.0))
		if rt > 0.0:
			o[e + 18] = clampf(sim.mode.round_timer / rt, 0.0, 1.0)


static func _has_prop_entities(sim: MatchSim) -> bool:
	for ent: Dictionary in sim.effects.entities:
		if str(ent["kind"]) == "prop":
			return true
	return false


## Distance along horizontal unit direction d from p to the arena's playable boundary.
static func _ray_to_boundary(a: ArenaDef, p: Vector3, d: Vector3) -> float:
	var r := a.radius
	var best := r * 2.0
	match a.base:
		"square":
			if absf(d.x) > 1e-6:
				best = minf(best, ((r if d.x > 0.0 else -r) - p.x) / d.x)
			if absf(d.z) > 1e-6:
				best = minf(best, ((r if d.z > 0.0 else -r) - p.z) / d.z)
		"octagon":
			for i in 8:
				var nx := OCT_NX[i]
				var nz := OCT_NZ[i]
				var dn := d.x * nx + d.z * nz
				if dn > 1e-6:
					best = minf(best, (r - (p.x * nx + p.z * nz)) / dn)
		_:
			var px := Vector2(p.x, p.z)
			var dv := Vector2(d.x, d.z)
			var b := px.dot(dv)
			var c := px.length_squared() - r * r
			var disc := b * b - c
			if disc >= 0.0:
				best = minf(best, -b + sqrt(disc))
	return maxf(best, 0.0)


## Distance from p to the nearest boundary edge (used for "cornered" cues).
static func _boundary_dist(a: ArenaDef, p: Vector3) -> float:
	var r := a.radius
	match a.base:
		"square":
			return maxf(0.0, minf(r - absf(p.x), r - absf(p.z)))
		"octagon":
			var best := r
			for i in 8:
				best = minf(best, r - (p.x * OCT_NX[i] + p.z * OCT_NZ[i]))
			return maxf(best, 0.0)
	return maxf(0.0, r - Vector2(p.x, p.z).length())
