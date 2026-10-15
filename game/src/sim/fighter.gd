class_name Fighter
extends Node3D
## Authoritative gameplay state of one combatant: vitals, state machine, input handling, moves,
## guarding/parrying, dodging, grabs, hit reactions, knockdowns and anti-infinite protection.
## The physical body is a child Rig; poses/IK/gait come from FighterMotor. MatchSim owns the
## tick order and resolves weapon contacts between fighters (see Combat).

enum State { NEUTRAL, ATTACK, GUARD, DODGE, HITSTUN, KNOCKDOWN, DOWN, GETUP, GRABBING, HELD, ABILITY, TAUNT, GUARD_BREAK, KO, DOWNED, CELEBRATE, INACTIVE }
const STATE_NAMES := ["neutral", "attack", "guard", "dodge", "hitstun", "knockdown", "down", "getup", "grabbing", "held", "ability", "taunt", "guard_break", "ko", "downed", "celebrate", "inactive"]

var index := 0
var team := 0
var creature: CreatureDef
var rig: Rig
var motor: FighterMotor
var sim: MatchSim
var display_name := ""
var controller_kind := "bot"     ## player | bot | net | policy | dummy (informational)
var input := FighterInput.new()
var _tracker := FighterInput.PressTracker.new()
var _buffer: Array = []          ## [{b, t}]

# ---- vitals ----
var max_health := 100.0
var health := 100.0
var max_stamina := 100.0
var stamina := 100.0
var max_poise := 100.0
var poise := 100.0
var hype := 0.0
var _stamina_delay := 0.0
var _poise_delay := 0.0
var lives := -1                  ## -1 = not using lives; modes set this

# ---- state ----
var state := State.NEUTRAL
var state_time := 0.0
var time := 0.0
var move: MoveDef = null
var move_slot := ""
var move_hits := {}              ## target index -> window index already hit
var move_hit_any := false
var move_charge := 0.0           ## 0..1 charge level of the current move
var _charging := false
var _light_step := 0             ## 0..3 position in the light string
var _attack_started_from_dodge := false
var cooldown_left := {}
var facing_yaw := 0.0
var target: Fighter = null
var _target_sticky := 0.0
var guard_pressed_at := -99.0
var guard_held := false
var dodge_dir := Vector3.ZERO
var _dodge_cd := 0.0
var invuln_until := -1.0
var evade_until := -1.0
var armor_until := -1.0
var stun_left := 0.0
var _combo_taken := 0
var _combo_timer := 0.0
var _stun_budget := 0.0
var otg_hits := 0
var _taunt_cd := 0.0
var juiced_until := -1.0
var crash_until := -1.0
var held_by: Fighter = null
var holding: Fighter = null
var _grab_joint: Joint3D = null
var _hold_left := 0.0
var _pummels := 0
var thrown_speed := 0.0
var _seg_stagger: PackedFloat32Array = PackedFloat32Array()

# ---- modifiers (upgrades, statuses, modes). Multiplicative unless noted. ----
var mods := {"damage": 1.0, "defense": 1.0, "speed": 1.0, "stamina_regen": 1.0, "knockback_taken": 1.0,
	"knockback_dealt": 1.0, "cooldown": 1.0, "hype_gain": 1.0, "poise": 1.0, "heal": 1.0, "size": 1.0}
var statuses: StatusSet
var flags := {}                  ## free-form per-mode flags (e.g. "has_bomb")
var stats_record := {"damage_dealt": 0.0, "damage_taken": 0.0, "hits": 0, "blocks": 0, "parries": 0, "knockdowns": 0, "kos": 0, "throws": 0}


func setup(c: CreatureDef, idx: int, team_id: int, match_sim, pos: Vector3, yaw: float, size_mult := 1.0) -> void:
	creature = c
	index = idx
	team = team_id
	sim = match_sim
	display_name = c.display_name
	name = "Fighter%d_%s" % [idx, c.id]
	rig = Rig.new()
	rig.mass_scale = c.stat("weight") * pow(size_mult, 3.0) / maxf(0.01, pow(size_mult, 3.0)) * 1.0
	add_child(rig)
	rig.build(c.body, idx, pos, yaw)
	motor = FighterMotor.new(c.body, rig)
	facing_yaw = yaw
	statuses = StatusSet.new(self)
	_seg_stagger.resize(c.body.segments.size())
	_seg_stagger.fill(0.0)
	reset_vitals()
	motor.reset_feet()


func reset_vitals() -> void:
	max_health = creature.stat("health") * float(mods.get("max_health", 1.0))
	health = max_health
	max_stamina = creature.stat("stamina")
	stamina = max_stamina
	max_poise = creature.stat("poise") * float(mods["poise"])
	poise = max_poise
	hype = 0.0
	stun_left = 0.0
	_combo_taken = 0
	_stun_budget = 0.0
	cooldown_left.clear()
	_set_state(State.NEUTRAL)


func respawn(pos: Vector3, yaw: float) -> void:
	_release_grab()
	rig.place(pos, yaw)
	rig.muscle = 1.0
	rig.support = 1.0
	rig.hover_enabled = true
	rig.upright_strength = 1.0
	facing_yaw = yaw
	motor.reset_feet()
	statuses.clear()
	reset_vitals()
	invuln_until = time + 1.5


func is_out() -> bool:
	return state == State.KO or state == State.DOWNED or state == State.INACTIVE


func is_down() -> bool:
	return state in [State.KNOCKDOWN, State.DOWN, State.GETUP]


func is_evading() -> bool:
	return time < evade_until or time < invuln_until


func pos() -> Vector3:
	return rig.root_pos()


func ground_pos() -> Vector3:
	var p := rig.root_pos()
	return Vector3(p.x, rig.ground_y, p.z)


func forward() -> Vector3:
	return MathX.forward_of_yaw(facing_yaw)


func head_pos() -> Vector3:
	var hs: int = creature.body.seg_index.get("head", -1)
	if hs >= 0:
		return rig.bodies[hs].global_position
	return rig.root_pos() + Vector3.UP * 0.4


func health_frac() -> float:
	return clampf(health / max_health, 0.0, 1.0)


func eff(stat_name: String) -> float:
	return creature.stat(stat_name)


func _set_state(s: int) -> void:
	state = s
	state_time = 0.0


func _emit(ev: Dictionary) -> void:
	if sim:
		ev["fighter"] = index
		sim.emit_event(ev)


# =====================================================================================
# Tick
# =====================================================================================

func sim_tick(dt: float) -> void:
	time += dt
	state_time += dt
	var presses := _tracker.consume(input)
	for b in FighterInput.BUTTON_COUNT:
		if (presses >> b) & 1:
			_buffer.append({"b": b, "t": time})
	var buf_window := Tuning.v("input_buffer")
	while not _buffer.is_empty() and time - float(_buffer[0]["t"]) > buf_window:
		_buffer.pop_front()
	guard_held = input.is_held(FighterInput.GUARD)
	_update_timers(dt)
	statuses.tick(dt)
	_update_target(dt)
	match state:
		State.NEUTRAL: _st_neutral(dt)
		State.GUARD: _st_guard(dt)
		State.ATTACK, State.ABILITY, State.TAUNT: _st_move(dt)
		State.DODGE: _st_dodge(dt)
		State.HITSTUN, State.GUARD_BREAK: _st_hitstun(dt)
		State.KNOCKDOWN: _st_knockdown(dt)
		State.DOWN: _st_down(dt)
		State.GETUP: _st_getup(dt)
		State.GRABBING: _st_grabbing(dt)
		State.HELD: _st_held(dt, presses)
		State.KO, State.DOWNED, State.INACTIVE: _st_out(dt)
		State.CELEBRATE: _st_celebrate(dt)
	_apply_stagger(dt)
	rig.yaw_target = facing_yaw
	motor.locomotion_vel = rig.com_velocity()
	motor.update(dt)
	rig.step(dt)


func _update_timers(dt: float) -> void:
	for k in cooldown_left.keys():
		cooldown_left[k] = maxf(0.0, float(cooldown_left[k]) - dt * float(mods["cooldown"]))
	_dodge_cd = maxf(0.0, _dodge_cd - dt)
	_taunt_cd = maxf(0.0, _taunt_cd - dt)
	if _combo_timer > 0.0:
		_combo_timer -= dt
		if _combo_timer <= 0.0:
			_combo_taken = 0
			_stun_budget = 0.0
	if _stamina_delay > 0.0:
		_stamina_delay -= dt
	elif state != State.GUARD or true:
		var regen := eff("stamina_regen") * float(mods["stamina_regen"])
		if state == State.GUARD:
			regen *= 0.35
		if time < crash_until:
			regen *= 0.5
		stamina = minf(max_stamina, stamina + regen * dt)
	if _poise_delay > 0.0:
		_poise_delay -= dt
	else:
		poise = minf(max_poise, poise + eff("poise_regen") * dt)
	if time >= juiced_until and juiced_until > 0.0:
		juiced_until = -1.0
		crash_until = time + Tuning.v("juice_crash")
		_emit({"type": "juice_end"})


func _consume(b: int) -> bool:
	for i in _buffer.size():
		if int(_buffer[i]["b"]) == b:
			_buffer.remove_at(i)
			return true
	return false


func _peek(b: int) -> bool:
	for e in _buffer:
		if int(e["b"]) == b:
			return true
	return false


func spend_stamina(amount: float) -> void:
	stamina = maxf(0.0, stamina - amount)
	_stamina_delay = Tuning.v("stamina_regen_delay")


func speed_mult() -> float:
	var m := float(mods["speed"]) * statuses.speed_mult()
	if stamina < Tuning.v("stamina_low"):
		m *= Tuning.v("stamina_low_speed")
	if time < crash_until:
		m *= Tuning.v("juice_crash_speed")
	if time < juiced_until:
		m *= 1.12
	return m


# =====================================================================================
# Targeting & locomotion
# =====================================================================================

func _update_target(dt: float) -> void:
	if sim == null:
		return
	_target_sticky -= dt
	var switch_req := _consume(FighterInput.TARGET)
	if target != null and (target.is_out() or target.pos().distance_to(pos()) > 14.0):
		target = null
	if target != null and _target_sticky > 0.0 and not switch_req:
		return
	var best: Fighter = null
	var best_score := INF
	var p := pos()
	var dir := input.move if input.move.length() > 0.3 else forward()
	for f: Fighter in sim.fighters:
		if f == self or f.is_out() or not sim.are_enemies(self, f):
			continue
		if switch_req and f == target:
			continue
		var to := f.pos() - p
		to.y = 0.0
		var dist := to.length()
		var ang := absf(dir.signed_angle_to(to, Vector3.UP)) if dist > 0.01 else 0.0
		var score := dist + ang * 1.6
		if score < best_score:
			best_score = score
			best = f
	if best != target:
		target = best
		_target_sticky = Tuning.v("target_sticky")


func _target_in_lock_range() -> bool:
	return target != null and target.pos().distance_to(pos()) <= Tuning.v("soft_lock_range")


func _yaw_to_target() -> float:
	var to := target.pos() - pos()
	return atan2(to.x, to.z)


func _turn_toward(yaw: float, rate: float, dt: float) -> void:
	var diff := MathX.wrap_angle(yaw - facing_yaw)
	var step := rate * dt
	facing_yaw = MathX.wrap_angle(facing_yaw + clampf(diff, -step, step))


func _locomote(dt: float, mult: float, face_target: bool) -> void:
	var spd := eff("walk_speed") * mult * speed_mult()
	var mv := input.move
	if mv.length() > 1.0:
		mv = mv.normalized()
	var fwd := forward()
	if mv.dot(fwd) < -0.3:
		spd *= 0.82
	rig.desired_vel = mv * spd
	rig.max_accel = eff("accel")
	if face_target and _target_in_lock_range():
		_turn_toward(_yaw_to_target(), eff("turn_rate"), dt)
	elif mv.length() > 0.2:
		_turn_toward(atan2(mv.x, mv.z), eff("turn_rate"), dt)
	if motor.base_pose:
		var sp := Vector2(rig.desired_vel.x, rig.desired_vel.z).length()
		motor.overlay_lean = Vector3(sp * 2.5, 0.0, 0.0)


func _clear_overlay() -> void:
	motor.overlay_chains.clear()
	motor.overlay_poles.clear()
	motor.overlay_joints.clear()
	motor.overlay_lean = Vector3.ZERO
	motor.overlay_height = 0.0
	for i in rig.seg_speed.size():
		rig.seg_speed[i] = 1.0


# =====================================================================================
# States
# =====================================================================================

func _st_neutral(dt: float) -> void:
	motor.guard_blend = move_toward(motor.guard_blend, 0.0, dt / Tuning.v("guard_blend_time"))
	_clear_overlay()
	_locomote(dt, 1.0, true)
	_light_step = 0
	_try_actions(false)


## Starts whatever buffered action is allowed. `from_cancel` = called from a move's cancel window.
func _try_actions(from_cancel: bool) -> bool:
	if _peek(FighterInput.JUICE) and hype >= 100.0 and creature.abilities.has("juice"):
		_consume(FighterInput.JUICE)
		_start_juice()
		return true
	if _peek(FighterInput.DODGE) and _dodge_cd <= 0.0 and stamina >= 4.0:
		_consume(FighterInput.DODGE)
		_start_dodge()
		return true
	for slot in ["ability1", "ability2"]:
		var b := FighterInput.AB1 if slot == "ability1" else FighterInput.AB2
		if _peek(b) and creature.abilities.has(slot) and float(cooldown_left.get(slot, 0.0)) <= 0.0:
			_consume(b)
			var ab: MoveDef = creature.abilities[slot]
			if stamina >= ab.stamina * 0.5:
				_start_move(ab, slot, State.ABILITY)
				cooldown_left[slot] = float(creature.cooldowns.get(slot, 6.0))
				_emit({"type": "ability", "slot": slot, "id": ab.id})
				return true
	if _peek(FighterInput.GRAB) and creature.moves.has("grab") and not from_cancel:
		_consume(FighterInput.GRAB)
		_start_move(creature.moves["grab"], "grab", State.ATTACK)
		return true
	if _peek(FighterInput.HEAVY):
		_consume(FighterInput.HEAVY)
		if from_cancel and _light_step > 0 and creature.moves.has("finisher"):
			_start_move(creature.moves["finisher"], "finisher", State.ATTACK)
		else:
			_start_move(creature.moves["heavy"], "heavy", State.ATTACK)
			_charging = creature.moves["heavy"].charge_time > 0.0
		_light_step = 0
		return true
	if _peek(FighterInput.LIGHT):
		_consume(FighterInput.LIGHT)
		if state == State.DODGE or (from_cancel and move_slot == "dodge") or _attack_started_from_dodge:
			if creature.moves.has("dash_attack"):
				_start_move(creature.moves["dash_attack"], "dash_attack", State.ATTACK)
				return true
		var slot := "l1"
		if from_cancel and _light_step == 1 and creature.moves.has("l2"):
			slot = "l2"
		elif from_cancel and _light_step == 2 and creature.moves.has("l3"):
			slot = "l3"
		_start_move(creature.moves[slot], slot, State.ATTACK)
		_light_step = {"l1": 1, "l2": 2, "l3": 3}[slot]
		return true
	if not from_cancel and _peek(FighterInput.TAUNT) and _taunt_cd <= 0.0:
		_consume(FighterInput.TAUNT)
		_taunt_cd = Tuning.v("taunt_cooldown")
		if creature.moves.has("taunt"):
			_start_move(creature.moves["taunt"], "taunt", State.TAUNT)
		hype = minf(100.0, hype + Tuning.v("taunt_hype") * float(mods["hype_gain"]))
		_emit({"type": "taunt"})
		return true
	if not from_cancel and guard_held:
		_set_state(State.GUARD)
		guard_pressed_at = time if _consume(FighterInput.GUARD) else time - 1.0
		return true
	return false


func _start_move(m: MoveDef, slot: String, st: int) -> void:
	_attack_started_from_dodge = state == State.DODGE
	move = m
	move_slot = slot
	move_hits.clear()
	move_hit_any = false
	move_charge = 0.0
	_charging = false
	_set_state(st)
	spend_stamina(m.stamina)
	# targeting assistance: snap toward the target if roughly in front, else toward input
	if _target_in_lock_range():
		var want := _yaw_to_target()
		if absf(MathX.wrap_angle(want - facing_yaw)) < deg_to_rad(Tuning.v("attack_snap_deg")) or input.move.length() < 0.2:
			facing_yaw = want
		elif input.move.length() > 0.3:
			facing_yaw = atan2(input.move.x, input.move.z)
	elif input.move.length() > 0.3:
		facing_yaw = atan2(input.move.x, input.move.z)
	for i in rig.seg_speed.size():
		rig.seg_speed[i] = 1.0
	if m.speed != 1.0:
		for cname in m.animated_chains:
			var c: BodyDef.Chain = creature.body.chains[cname]
			for si in c.segs:
				rig.seg_speed[si] = m.speed
		for ji in m.animated_joints:
			rig.seg_speed[ji] = m.speed
	_emit({"type": "move_start", "slot": slot, "id": m.id})
	if sim and not m.effects.is_empty():
		sim.effects.begin_move(self, m)


func _st_move(dt: float) -> void:
	var t := state_time
	var m := move
	# hold-to-charge: freeze the timeline just before the first active frame while held
	if _charging:
		if input.is_held(FighterInput.HEAVY) and move_charge < 1.0 and t >= m.first_active() * 0.7:
			move_charge = minf(1.0, move_charge + dt / m.charge_time)
			state_time -= dt
			t = state_time
			armor_until = time + 0.05
		elif not input.is_held(FighterInput.HEAVY) or move_charge >= 1.0:
			_charging = false
	motor.guard_blend = move_toward(motor.guard_blend, 0.0, dt / Tuning.v("guard_blend_time"))
	m.apply_overlay(t, motor)
	var mv := input.move
	var spd := eff("walk_speed") * m.move_mult * speed_mult()
	var lunge := m.lunge_speed(t)
	rig.desired_vel = mv * spd + forward() * lunge
	rig.max_accel = eff("accel") * (1.6 if lunge > 0.0 else 1.0)
	if target and _target_in_lock_range():
		_turn_toward(_yaw_to_target(), m.turn_rate, dt)
	if m.in_ranges(m.armor, t):
		armor_until = time + 0.02
	if m.in_ranges(m.invuln, t):
		evade_until = time + 0.02
	if sim and not m.effects.is_empty():
		sim.effects.tick_move(self, m, t, dt)
	# chaining / cancels
	if t >= m.cancel_t0 and (not m.cancel_on_hit or move_hit_any) and state == State.ATTACK:
		if _try_actions(true):
			return
	if t >= m.duration:
		if not move_hit_any and m.kind == "melee" and not m.windows.is_empty():
			spend_stamina(m.stamina * Tuning.v("whiff_stamina_extra"))
		if move_slot == "grab":
			# whiffed grab: recovery is part of the move's duration; nothing else to do
			pass
		_end_move()


func _end_move() -> void:
	if sim and move and not move.effects.is_empty():
		sim.effects.end_move(self, move)
	move = null
	move_slot = ""
	_charging = false
	_clear_overlay()
	_set_state(State.GUARD if guard_held else State.NEUTRAL)


func _st_guard(dt: float) -> void:
	motor.guard_blend = move_toward(motor.guard_blend, 1.0, dt / Tuning.v("guard_blend_time"))
	_clear_overlay()
	_locomote(dt, Tuning.v("guard_move_mult"), true)
	if not guard_held:
		_set_state(State.NEUTRAL)
		return
	# guard can be cancelled into dodge, grab-breaks and abilities, not into attacks
	if _peek(FighterInput.DODGE) and _dodge_cd <= 0.0:
		_consume(FighterInput.DODGE)
		_start_dodge()


func _start_dodge() -> void:
	var dir := input.move
	if dir.length() < 0.2:
		dir = -forward()
	dodge_dir = dir.normalized()
	spend_stamina(Tuning.v("dodge_stamina"))
	_dodge_cd = Tuning.v("dodge_cooldown") + eff("dodge_time")
	_set_state(State.DODGE)
	move_slot = "dodge"
	evade_until = time + Tuning.v("dodge_evade_end")
	_emit({"type": "dodge"})


func _st_dodge(dt: float) -> void:
	var dur := eff("dodge_time")
	var t := state_time
	_clear_overlay()
	motor.overlay_lean = Vector3(-8.0 if dodge_dir.dot(forward()) < 0.0 else 8.0, 0.0, 0.0)
	motor.overlay_height = -0.08 * creature.body.scale
	if t < dur:
		rig.desired_vel = dodge_dir * eff("dodge_speed") * speed_mult()
		rig.max_accel = 90.0
		if _peek(FighterInput.LIGHT) and creature.moves.has("dash_attack") and t > dur * 0.35:
			_consume(FighterInput.LIGHT)
			_start_move(creature.moves["dash_attack"], "dash_attack", State.ATTACK)
	elif t < dur + Tuning.v("dodge_recovery"):
		rig.desired_vel = Vector3.ZERO
		rig.max_accel = eff("accel") * 1.5
	else:
		move_slot = ""
		_set_state(State.GUARD if guard_held else State.NEUTRAL)


func _st_hitstun(dt: float) -> void:
	stun_left -= dt
	_clear_overlay()
	rig.desired_vel = Vector3.ZERO
	rig.max_accel = eff("accel") * 0.25
	motor.guard_blend = move_toward(motor.guard_blend, 0.0, dt / 0.1)
	if stun_left <= 0.0:
		_set_state(State.GUARD if guard_held else State.NEUTRAL)


func knock_down(reason := "hit") -> void:
	if state == State.KO:
		return
	_release_grab()
	if held_by:
		held_by._release_grab()
	_set_state(State.KNOCKDOWN)
	move = null
	move_slot = ""
	_clear_overlay()
	rig.muscle = Tuning.v("knockdown_muscle")
	rig.hover_enabled = false
	otg_hits = 0
	poise = max_poise
	stats_record["knockdowns"] += 1
	_emit({"type": "knockdown", "reason": reason})


func _st_knockdown(dt: float) -> void:
	rig.desired_vel = Vector3.ZERO
	motor.tuck = true
	if state_time > Tuning.v("knockdown_min") and rig.root().linear_velocity.length() < 1.2:
		_set_state(State.DOWN)


func _st_down(dt: float) -> void:
	rig.desired_vel = Vector3.ZERO
	var wants := input.move.length() > 0.5 or not _buffer.is_empty()
	if (state_time > 0.25 and wants) or state_time > Tuning.v("knockdown_auto_getup"):
		_buffer.clear()
		_set_state(State.GETUP)
		rig.hover_enabled = true
		rig.upright_strength = 0.0
		invuln_until = time + Tuning.v("getup_time") + Tuning.v("wakeup_invuln")
		_emit({"type": "getup"})


func _st_getup(dt: float) -> void:
	var gt := Tuning.v("getup_time")
	var k := MathX.smooth01(state_time / gt)
	rig.muscle = lerpf(Tuning.v("knockdown_muscle"), 1.0, k)
	rig.upright_strength = k
	motor.tuck = false
	rig.desired_vel = Vector3.ZERO
	if target:
		_turn_toward(_yaw_to_target(), 4.0, dt)
	if state_time >= gt:
		rig.muscle = 1.0
		rig.upright_strength = 1.0
		motor.reset_feet()
		_set_state(State.NEUTRAL)


func _st_celebrate(dt: float) -> void:
	rig.desired_vel = Vector3.ZERO
	_clear_overlay()
	motor.overlay_height = absf(sin(state_time * 6.0)) * 0.08


func _st_out(dt: float) -> void:
	rig.desired_vel = Vector3.ZERO
	motor.tuck = true


func knock_out() -> void:
	_release_grab()
	if held_by:
		held_by._release_grab()
	_set_state(State.KO)
	move = null
	_clear_overlay()
	rig.muscle = Tuning.v("ko_muscle")
	rig.hover_enabled = false
	health = 0.0
	_emit({"type": "ko"})


func set_downed() -> void:
	_release_grab()
	_set_state(State.DOWNED)
	move = null
	_clear_overlay()
	rig.muscle = 0.12
	rig.hover_enabled = false
	health = 0.0
	_emit({"type": "downed"})


func revive(frac: float) -> void:
	health = max_health * frac
	_set_state(State.GETUP)
	rig.hover_enabled = true
	rig.upright_strength = 0.0
	invuln_until = time + 2.0
	_emit({"type": "revived"})


func celebrate() -> void:
	if not is_out():
		_release_grab()
		_set_state(State.CELEBRATE)


func _start_juice() -> void:
	hype = 0.0
	var ab: MoveDef = creature.abilities["juice"]
	juiced_until = time + float(creature.juice.get("duration", Tuning.v("juice_duration")))
	_start_move(ab, "juice", State.ABILITY)
	invuln_until = time + 0.6
	_emit({"type": "juice", "id": ab.id})


# =====================================================================================
# Grabs
# =====================================================================================

## Called by Combat when this fighter's grab move touches `victim`.
func begin_grab(victim: Fighter, my_seg: int, victim_seg: int) -> void:
	if victim.held_by or victim.holding:
		return
	holding = victim
	victim.held_by = self
	_hold_left = Tuning.v("grab_hold_max")
	_pummels = 0
	_set_state(State.GRABBING)
	move = null
	victim._set_state(State.HELD)
	victim.move = null
	victim._clear_overlay()
	var j := Generic6DOFJoint3D.new()
	j.name = "GrabJoint%d" % index
	add_child(j)
	var hand := rig.bodies[my_seg]
	j.global_position = hand.global_position
	j.node_a = j.get_path_to(hand)
	j.node_b = j.get_path_to(victim.rig.bodies[victim_seg])
	for axis in ["x", "y", "z"]:
		j.set("angular_limit_%s/enabled" % axis, false)
	_grab_joint = j
	stats_record["throws"] += 0
	_emit({"type": "grab", "victim": victim.index})


func _release_grab() -> void:
	if _grab_joint:
		_grab_joint.queue_free()
		_grab_joint = null
	if holding:
		var v := holding
		holding = null
		v.held_by = null
		if v.state == State.HELD:
			v._set_state(State.NEUTRAL)
	if state == State.GRABBING:
		_set_state(State.NEUTRAL)


func _st_grabbing(dt: float) -> void:
	_clear_overlay()
	_hold_left -= dt
	rig.desired_vel = input.move * eff("walk_speed") * 0.45
	if holding == null or holding.is_out():
		_release_grab()
		return
	if target:
		_turn_toward(_yaw_to_target(), 3.0, dt)
	var throw_dir := Vector3.ZERO
	if _consume(FighterInput.HEAVY) or _consume(FighterInput.GRAB):
		throw_dir = input.move if input.move.length() > 0.3 else forward()
	elif _consume(FighterInput.LIGHT) and _pummels < int(Tuning.v("pummel_max")):
		_pummels += 1
		if sim:
			sim.combat.apply_simple_damage(self, holding, Tuning.v("pummel_damage"), "pummel")
		return
	elif _hold_left <= 0.0:
		throw_dir = forward()
	if throw_dir != Vector3.ZERO:
		var v := holding
		_release_grab()
		var spd := Tuning.v("throw_speed") * float(mods["knockback_dealt"])
		var mass_ratio := sqrt(Tuning.v("ref_mass") / maxf(20.0, v.rig.total_mass))
		v.rig.apply_body_impulse((throw_dir.normalized() * spd + Vector3.UP * Tuning.v("throw_up")) * mass_ratio * v.rig.total_mass)
		if sim:
			sim.combat.apply_simple_damage(self, v, Tuning.v("throw_damage"), "throw")
		v.thrown_speed = spd
		if not v.is_out():
			v.knock_down("throw")
		stats_record["throws"] += 1
		_emit({"type": "throw", "victim": v.index})
		_set_state(State.NEUTRAL)


func _st_held(dt: float, presses: int) -> void:
	_clear_overlay()
	rig.desired_vel = Vector3.ZERO
	if held_by == null:
		_set_state(State.NEUTRAL)
		return
	var n := 0
	for b in FighterInput.BUTTON_COUNT:
		if (presses >> b) & 1:
			n += 1
	if n > 0:
		held_by._hold_left -= Tuning.v("grab_mash_reduce") * n
		if held_by._hold_left <= 0.0:
			var g := held_by
			g._release_grab()
			var away := (pos() - g.pos())
			away.y = 0.0
			away = away.normalized()
			rig.apply_body_impulse(away * 3.0 * rig.total_mass)
			g.rig.apply_body_impulse(-away * 3.0 * g.rig.total_mass)
			_emit({"type": "grab_escape"})


# =====================================================================================
# Taking hits
# =====================================================================================

## Applies a resolved hit (from Combat). Returns a summary used for events.
func receive_hit(h: Dictionary) -> void:
	var attacker: Fighter = h.get("attacker")
	var dmg: float = h["damage"]
	if h.get("parried", false):
		_emit({"type": "parry", "attacker": attacker.index if attacker else -1, "pos": h["point"]})
		hype = minf(100.0, hype + Tuning.v("parry_hype"))
		stats_record["parries"] += 1
		if attacker:
			attacker.stun(Tuning.v("parry_stun"), true)
		return
	health -= dmg
	stats_record["damage_taken"] += dmg
	hype = minf(100.0, hype + dmg * Tuning.v("hype_per_damage_taken") * float(mods["hype_gain"]))
	if attacker:
		attacker.hype = minf(100.0, attacker.hype + dmg * Tuning.v("hype_per_damage_dealt") * float(attacker.mods["hype_gain"]) * float(h.get("hype_mult", 1.0)))
		attacker.stats_record["damage_dealt"] += dmg
		attacker.stats_record["hits"] += 1
	if h.get("blocked", false):
		stats_record["blocks"] += 1
		var drain: float = h.get("guard_drain", 0.0)
		spend_stamina(drain)
		if stamina <= 0.0:
			_emit({"type": "guard_break"})
			stun(Tuning.v("guard_break_stun"), true)
			_set_state(State.GUARD_BREAK)
	# physical reaction
	var seg_i: int = h.get("seg", 0)
	var kb: Vector3 = h.get("knockback", Vector3.ZERO)
	if kb != Vector3.ZERO:
		rig.apply_body_impulse(kb * rig.total_mass)
	var local_imp: Vector3 = h.get("local_impulse", Vector3.ZERO)
	if local_imp != Vector3.ZERO:
		rig.apply_impulse_at(seg_i, local_imp, h["point"])
	stagger(seg_i, clampf(dmg / 18.0, 0.2, 1.0))
	if health <= 0.0:
		if sim:
			sim.on_fighter_depleted(self, attacker, h)
		else:
			knock_out()
		return
	if h.get("blocked", false):
		return
	if is_down():
		otg_hits += 1
		return
	poise -= float(h.get("poise", 0.0)) / float(mods["poise"])
	_poise_delay = Tuning.v("poise_regen_delay")
	if poise <= 0.0 or h.get("knockdown", false):
		knock_down("poise" if poise <= 0.0 else "move")
		return
	if time < armor_until:
		return
	var st: float = h.get("stun", 0.0)
	if st > 0.0:
		stun(st, false)


## Puts the fighter in hitstun, honouring combo protection (stun budget + burst).
func stun(seconds: float, ignore_budget: bool) -> void:
	if is_out() or is_down():
		return
	if state in [State.ATTACK, State.ABILITY, State.TAUNT]:
		_interrupt_move()
	if state == State.GRABBING:
		_release_grab()
	if state == State.HELD:
		return
	if not ignore_budget:
		_combo_taken += 1
		_combo_timer = Tuning.v("combo_window")
		var scale := maxf(Tuning.v("combo_stun_min"), 1.0 - Tuning.v("combo_stun_step") * maxf(0, _combo_taken - 1))
		seconds *= scale
		_stun_budget += seconds
		if _stun_budget > Tuning.v("stun_budget"):
			_burst()
			return
	stun_left = maxf(stun_left, seconds)
	if state != State.GUARD_BREAK:
		_set_state(State.HITSTUN)


func _interrupt_move() -> void:
	if sim and move and not move.effects.is_empty():
		sim.effects.end_move(self, move)
	move = null
	move_slot = ""
	_charging = false
	_clear_overlay()


## Automatic combo breaker: shoves attackers away and grants brief invulnerability.
func _burst() -> void:
	_combo_taken = 0
	_stun_budget = 0.0
	stun_left = 0.0
	invuln_until = time + Tuning.v("burst_invuln")
	_set_state(State.NEUTRAL)
	if sim:
		for f: Fighter in sim.fighters:
			if f != self and not f.is_out() and f.pos().distance_to(pos()) < 2.5:
				var away := f.pos() - pos()
				away.y = 0.0
				f.rig.apply_body_impulse(away.normalized() * Tuning.v("burst_knockback") * f.rig.total_mass)
	_emit({"type": "burst"})


func combo_damage_scale() -> float:
	return maxf(Tuning.v("combo_dmg_min"), 1.0 - Tuning.v("combo_dmg_step") * maxf(0, _combo_taken - 1))


func stagger(seg_i: int, amount: float) -> void:
	_seg_stagger[seg_i] = maxf(_seg_stagger[seg_i], amount)
	var s: BodyDef.Seg = creature.body.segments[seg_i]
	if s.parent >= 0:
		_seg_stagger[s.parent] = maxf(_seg_stagger[s.parent], amount * 0.6)


func _apply_stagger(dt: float) -> void:
	var rec := dt / Tuning.v("stagger_recover")
	var floor_m := Tuning.v("stagger_muscle")
	for i in _seg_stagger.size():
		if _seg_stagger[i] > 0.0:
			_seg_stagger[i] = maxf(0.0, _seg_stagger[i] - rec)
		rig.seg_muscle[i] = 1.0 - (1.0 - floor_m) * _seg_stagger[i]


func heal(amount: float) -> void:
	if is_out():
		return
	health = minf(max_health, health + amount * float(mods["heal"]) * statuses.heal_mult())


## True if this fighter is currently guarding against an attack arriving from `from_pos`.
func guards_against(from_pos: Vector3) -> bool:
	if state != State.GUARD or motor.guard_blend < 0.5:
		return false
	var to := from_pos - pos()
	to.y = 0.0
	if to.length() < 0.01:
		return true
	return absf(forward().signed_angle_to(to, Vector3.UP)) <= deg_to_rad(Tuning.v("guard_front_arc_deg"))


func in_parry_window() -> bool:
	return state == State.GUARD and time - guard_pressed_at <= Tuning.v("parry_window")


func is_winding_up() -> bool:
	return (state == State.ATTACK or state == State.ABILITY) and move != null and state_time < move.first_active()


# =====================================================================================
# Observation helpers (AI, HUD, network)
# =====================================================================================

func state_name() -> String:
	return STATE_NAMES[state]


func cooldown_frac(slot: String) -> float:
	var total := float(creature.cooldowns.get(slot, 1.0))
	return clampf(float(cooldown_left.get(slot, 0.0)) / maxf(total, 0.01), 0.0, 1.0)
