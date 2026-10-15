class_name Fighter
extends Node3D
## Authoritative gameplay state of one combatant: vitals, state machine, input handling, moves,
## guarding/parrying, dodging, grabs, hit reactions, knockdowns, anti-infinite protection, and
## the special states kits need (hover, steerable charge with carry, counter stance, airborne
## leaps, submerge blinks, JUICE states). The physical body is a child Rig; poses/IK/gait come
## from FighterMotor. MatchSim owns tick order; Combat validates contacts and delivers hits.
##
## Move variants: a creature may define "<slot>@<flag>" moves (e.g. "l1@hovering"); while the
## timed flag is set the variant replaces the slot. JUICE adds the flag "juiced".

enum State { NEUTRAL, ATTACK, GUARD, DODGE, HITSTUN, KNOCKDOWN, DOWN, GETUP, GRABBING, HELD, ABILITY, TAUNT, GUARD_BREAK, KO, DOWNED, CELEBRATE, INACTIVE }
const STATE_NAMES := ["neutral", "attack", "guard", "dodge", "hitstun", "knockdown", "down", "getup", "grabbing", "held", "ability", "taunt", "guard_break", "ko", "downed", "celebrate", "inactive"]

var index := 0
var team := 0
var creature: CreatureDef
var rig: Rig
var motor: FighterMotor
var sim: MatchSim
var hooks: Hooks
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
var shield_hp := 0.0
var _stamina_delay := 0.0
var _poise_delay := 0.0
var lives := -1                  ## -1 = not using lives; modes set this

# ---- state ----
var state := State.NEUTRAL
var state_time := 0.0
var time := 0.0
var move: MoveDef = null
var move_slot := ""
var move_hits := {}              ## target index -> {w: window, t: state_time}
var move_hit_any := false
var last_hit_target: Fighter = null
var move_charge := 0.0           ## 0..1 charge level of the current move
var _charging := false
var _light_step := 0             ## index into the creature's light string
var cooldown_left := {}
var charges_left := {}
var facing_yaw := 0.0
var target: Fighter = null
var _target_sticky := 0.0
var guard_pressed_at := -99.0
var guard_held := false
var _last_parry := -99.0
var dodge_dir := Vector3.ZERO
var _dodge_cd := 0.0
var invuln_until := -1.0
var evade_until := -1.0
var armor_until := -1.0
var armor_level := "all"
var stun_left := 0.0
var _combo_taken := 0
var _combo_timer := 0.0
var _stun_budget := 0.0
var otg_hits := 0
var _taunt_cd := 0.0
var juiced_until := -1.0
var crash_until := -1.0
var juice_armor := ""
var _juice_end_effects: Array = []
var held_by: Fighter = null
var holding: Fighter = null
var _grab_joint: Joint3D = null
var _hold_left := 0.0
var _escape_presses := 0
var _pummels := 0
var thrown_speed := 0.0
var _seg_stagger: PackedFloat32Array = PackedFloat32Array()
var timed_flags := {}            ## name -> expiry time (hovering, juiced, shield, reflect, ...)
var pending_land_stun := 0.0
var _airborne := false
var _air_until := 0.0
var _on_land: Array = []
var _hover_until := -1.0
var _hover_extra := 0.0
var _hover_speed := 3.0
var _charge := {}
var _carried: Fighter = null
var _counter_until := -1.0
var _counter := {}
var _submerge := {}
var _splat := {}
var despawned := false           ## body parked off-world; slot reserved for reuse (see MatchSim)
var focus_point = null           ## Vector3 objective worth facing (set by the mode each tick) or null

# ---- modifiers (upgrades, modes). Multiplicative unless noted. ----
var mods := {"damage": 1.0, "defense": 1.0, "speed": 1.0, "stamina_regen": 1.0, "knockback_taken": 1.0,
	"knockback_dealt": 1.0, "cooldown": 1.0, "hype_gain": 1.0, "poise": 1.0, "heal": 1.0, "size": 1.0,
	"move_speed": 1.0, "max_health": 1.0}
var statuses: StatusSet
var flags := {}                  ## free-form persistent flags (modes, bosses)
var stats_record := {"damage_dealt": 0.0, "damage_taken": 0.0, "hits": 0, "blocks": 0, "parries": 0, "knockdowns": 0, "kos": 0, "throws": 0}


func setup(c: CreatureDef, idx: int, team_id: int, match_sim, pos: Vector3, yaw: float) -> void:
	creature = c
	index = idx
	team = team_id
	sim = match_sim
	display_name = c.display_name
	name = "Fighter%d_%s" % [idx, c.id]
	rig = Rig.new()
	rig.mass_scale = c.stat("weight")
	add_child(rig)
	rig.build(c.body, idx, pos, yaw)
	motor = FighterMotor.new(c.body, rig)
	facing_yaw = yaw
	statuses = StatusSet.new(self)
	hooks = Hooks.new(self)
	for h in c.passives:
		hooks.add(h, "kit")
	_seg_stagger.resize(c.body.segments.size())
	_seg_stagger.fill(0.0)
	reset_vitals()
	motor.reset_feet()


func reset_vitals() -> void:
	max_health = creature.stat("health") * float(mods.get("max_health", 1.0)) + float(mods.get("max_health_add", 0.0))
	health = max_health
	max_stamina = creature.stat("stamina") + float(mods.get("stamina_add", 0.0))
	stamina = max_stamina
	max_poise = creature.stat("poise") * float(mods["poise"]) + float(mods.get("poise_add", 0.0))
	poise = max_poise
	hype = float(mods.get("start_hype", 0.0))
	stun_left = 0.0
	shield_hp = 0.0
	_combo_taken = 0
	_stun_budget = 0.0
	cooldown_left.clear()
	charges_left.clear()
	for slot in creature.abilities:
		charges_left[slot] = int(creature.ability_charges.get(slot, 1))
	timed_flags.clear()
	_set_state(State.NEUTRAL)


func respawn(pos: Vector3, yaw: float) -> void:
	_release_grab()
	_end_carry()
	rig.place(pos, yaw)
	rig.muscle = 1.0
	rig.support = 1.0
	rig.hover_enabled = true
	rig.upright_strength = 1.0
	facing_yaw = yaw
	motor.reset_feet()
	motor.tuck = false
	statuses.clear()
	hooks.clear_temporary()
	juiced_until = -1.0
	crash_until = -1.0
	_airborne = false
	_hover_until = -1.0
	_charge = {}
	_counter_until = -1.0
	_submerge = {}
	_splat = {}
	reset_vitals()
	invuln_until = time + 1.5


## Parks the body off-world and deactivates the fighter (dead minions, departed players).
func despawn() -> void:
	_release_grab()
	_end_carry()
	if held_by:
		held_by._release_grab()
	_interrupt_move()
	_set_state(State.INACTIVE)
	despawned = true
	rig.place(Vector3(0.0, -300.0 - index * 5.0, 0.0), 0.0)
	for rb in rig.bodies:
		rb.freeze = true
		rb.collision_layer = 0
		rb.collision_mask = 0


## Swaps the physical body for another creature definition (e.g. a rescaled "Absolute Unit")
## while keeping identity, team, hooks and statistics.
func rebuild(c: CreatureDef, at: Vector3, yaw: float) -> void:
	_release_grab()
	_end_carry()
	if held_by:
		held_by._release_grab()
	_interrupt_move()
	var old := rig
	old.place(Vector3(0.0, -400.0, 0.0), 0.0)
	for rb in old.bodies:
		rb.freeze = true
		rb.collision_layer = 0
		rb.collision_mask = 0
	old.queue_free()
	creature = c
	rig = Rig.new()
	rig.mass_scale = c.stat("weight")
	add_child(rig)
	rig.build(c.body, index, at, yaw)
	motor = FighterMotor.new(c.body, rig)
	_seg_stagger.resize(c.body.segments.size())
	_seg_stagger.fill(0.0)
	facing_yaw = yaw
	motor.reset_feet()
	_set_state(State.NEUTRAL)
	_emit({"type": "fighter_rebuilt", "creature": c.id, "scale": c.body.scale})


# =====================================================================================
# Queries
# =====================================================================================

func is_out() -> bool:
	return state == State.KO or state == State.DOWNED or state == State.INACTIVE


func is_down() -> bool:
	return state in [State.KNOCKDOWN, State.DOWN, State.GETUP]


func is_evading() -> bool:
	return time < evade_until or time < invuln_until or not _submerge.is_empty()


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


func has_flag(n: String) -> bool:
	if n == "juiced":
		return time < juiced_until
	if n == "hovering":
		return time < _hover_until
	return float(timed_flags.get(n, -1.0)) > time


func set_flag(n: String, seconds: float) -> void:
	timed_flags[n] = maxf(float(timed_flags.get(n, -1.0)), time + seconds)


func clear_flag(n: String) -> void:
	timed_flags.erase(n)


func effective_max_poise() -> float:
	return max_poise * statuses.mult("poise_max")


func counter_active() -> bool:
	return time < _counter_until


func current_move_class() -> String:
	if move and move.move_class != "":
		return move.move_class
	return Combat.move_class(move_slot.split("@")[0])


## Element of a move, honouring per-slot element overrides granted by supplements.
func element_for(m: MoveDef) -> String:
	var ov := str(mods.get("element_" + move_slot.split("@")[0], ""))
	if ov != "":
		return ov
	return m.element if m.element != "" else (creature.element if bool(mods.get("all_moves_elemental", false)) else m.element)


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
	state_time += dt * _time_scale()
	var presses := _tracker.consume(input)
	for b in FighterInput.BUTTON_COUNT:
		if (presses >> b) & 1:
			_buffer.append({"b": b, "t": time})
	var buf_window := Tuning.v("input_buffer")
	while not _buffer.is_empty() and time - float(_buffer[0]["t"]) > buf_window:
		_buffer.pop_front()
	guard_held = input.is_held(FighterInput.GUARD) and not statuses.flag("no_guard")
	_update_timers(dt)
	statuses.tick(dt)
	hooks.tick(dt)
	_update_target(dt)
	_update_specials(dt)
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
	if _hover_until > time:
		rig.hover_height += _hover_extra
		motor.tuck = true
	if sim and sim.profiling:
		var a := Time.get_ticks_usec()
		motor.update(dt)
		var b := Time.get_ticks_usec()
		rig.step(dt)
		sim.prof["motor"] = float(sim.prof.get("motor", 0.0)) + (b - a)
		sim.prof["rig"] = float(sim.prof.get("rig", 0.0)) + (Time.get_ticks_usec() - b)
		return
	motor.update(dt)
	rig.step(dt)


func _time_scale() -> float:
	if state != State.ATTACK and state != State.ABILITY:
		return 1.0
	var s := float(mods.get("move_speed", 1.0)) * statuses.mult("move_speed")
	if stamina < Tuning.v("stamina_low") and move and state_time < move.first_active():
		s *= 0.77
	return s


func _update_timers(dt: float) -> void:
	var cd_rate := float(mods["cooldown"]) * statuses.mult("cooldown_rate")
	for k in cooldown_left.keys():
		if float(cooldown_left[k]) > 0.0:
			cooldown_left[k] = maxf(0.0, float(cooldown_left[k]) - dt * cd_rate)
			if float(cooldown_left[k]) <= 0.0:
				var maxc := int(creature.ability_charges.get(k, 1))
				charges_left[k] = mini(maxc, int(charges_left.get(k, 0)) + 1)
				if int(charges_left[k]) < maxc:
					cooldown_left[k] = float(creature.cooldowns.get(k, 6.0))
	_dodge_cd = maxf(0.0, _dodge_cd - dt)
	_taunt_cd = maxf(0.0, _taunt_cd - dt)
	if _combo_timer > 0.0:
		_combo_timer -= dt
		if _combo_timer <= 0.0:
			_combo_taken = 0
			_stun_budget = 0.0
	if _stamina_delay > 0.0:
		_stamina_delay -= dt
	elif state != State.ATTACK and state != State.ABILITY:
		var regen := eff("stamina_regen") * float(mods["stamina_regen"]) * statuses.stamina_regen_mult()
		if state == State.GUARD:
			regen *= 0.5
		if time < crash_until:
			regen *= 0.5
		stamina = minf(max_stamina, stamina + regen * dt)
	if _poise_delay > 0.0:
		_poise_delay -= dt
	else:
		poise = minf(effective_max_poise(), poise + eff("poise_regen") * statuses.mult("poise_regen") * dt)
	if time >= juiced_until and juiced_until > 0.0:
		_end_juice()


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


## True when the mode's objective (ball, light...) should win facing over the nearest enemy.
func _focus_preferred() -> bool:
	if focus_point == null:
		return false
	var fd := Vector2((focus_point as Vector3).x - pos().x, (focus_point as Vector3).z - pos().z).length()
	if fd > Tuning.v("soft_lock_range"):
		return false
	if target == null or not _target_in_lock_range():
		return true
	return fd < target.pos().distance_to(pos()) * 0.8


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
	if has_flag("hovering"):
		spd = _hover_speed * mult
	var mv := input.move
	if mv.length() > 1.0:
		mv = mv.normalized()
	var fwd := forward()
	var along := mv.dot(fwd)
	if along < -0.3:
		spd *= 0.82
	# crabs (and anything with side_speed) scuttle faster sideways than forward
	var side_speed := eff("side_speed")
	if side_speed > 0.0 and mv.length() > 0.1:
		var sideness := absf(mv.normalized().dot(fwd.cross(Vector3.UP)))
		spd = lerpf(spd, side_speed * mult * speed_mult(), sideness)
	rig.desired_vel = mv * spd
	rig.max_accel = eff("accel")
	if face_target and _focus_preferred():
		var to_f: Vector3 = focus_point - pos()
		_turn_toward(atan2(to_f.x, to_f.z), eff("turn_rate"), dt)
	elif face_target and _target_in_lock_range():
		_turn_toward(_yaw_to_target(), eff("turn_rate"), dt)
	elif mv.length() > 0.2:
		_turn_toward(atan2(mv.x, mv.z), eff("turn_rate"), dt)
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
	if not _airborne:
		_light_step = 0
	_try_actions(false)


## Picks a move for a slot, honouring "<slot>@<flag>" variants for active timed flags.
func _move_variant(slot: String, abilities := false) -> Array:
	var table: Dictionary = creature.abilities if abilities else creature.moves
	for fl in ["hovering", "pad_launched", "juiced", "airborne"]:
		var vkey := "%s@%s" % [slot, fl]
		if table.has(vkey) and (has_flag(fl) or (fl == "airborne" and _airborne)):
			return [table[vkey], vkey]
	if table.has(slot):
		return [table[slot], slot]
	return []


## Starts whatever buffered action is allowed. `from_cancel` = called from a move's cancel window.
func _try_actions(from_cancel: bool) -> bool:
	if sim and sim.mode and sim.mode.intercept_actions(self):
		return true
	if _peek(FighterInput.JUICE) and hype >= 100.0 and creature.abilities.has("juice") and not bool(mods.get("no_juice", false)):
		_consume(FighterInput.JUICE)
		_start_juice()
		return true
	if _peek(FighterInput.DODGE) and _dodge_cd <= 0.0 and stamina >= 4.0 and not statuses.flag("no_dodge") and not _airborne:
		_consume(FighterInput.DODGE)
		_start_dodge()
		return true
	for slot in ["ability1", "ability2"]:
		var b := FighterInput.AB1 if slot == "ability1" else FighterInput.AB2
		if _peek(b) and creature.abilities.has(slot) and int(charges_left.get(slot, 1)) > 0 and not bool(mods.get("no_abilities", false)):
			_consume(b)
			var mv: Array = _move_variant(slot, true)
			var ab: MoveDef = mv[0]
			if stamina >= ab.stamina * 0.5:
				charges_left[slot] = int(charges_left.get(slot, 1)) - 1
				if float(cooldown_left.get(slot, 0.0)) <= 0.0:
					cooldown_left[slot] = float(creature.cooldowns.get(slot, 6.0))
				_start_move(ab, mv[1], State.ABILITY)
				hooks.fire("ability_used", {"slot": slot})
				_emit({"type": "ability", "slot": slot, "id": ab.id})
				return true
	if _peek(FighterInput.GRAB) and sim and sim.mode and sim.mode.on_grab_pressed(self):
		_consume(FighterInput.GRAB)
		return true
	if _peek(FighterInput.GRAB) and creature.moves.has("grab") and not from_cancel and not bool(mods.get("no_grabs", false)):
		_consume(FighterInput.GRAB)
		var gv: Array = _move_variant("grab")
		_start_move(gv[0], gv[1], State.ATTACK)
		return true
	if _peek(FighterInput.HEAVY):
		_consume(FighterInput.HEAVY)
		if from_cancel and _light_step > 0 and creature.moves.has("finisher") and not has_flag("hovering"):
			var fv: Array = _move_variant("finisher")
			_start_move(fv[0], fv[1], State.ATTACK)
		else:
			var hv: Array = _move_variant("heavy")
			_start_move(hv[0], hv[1], State.ATTACK)
			var hm: MoveDef = hv[0]
			_charging = hm.charge_time > 0.0 and not bool(mods.get("auto_charge", false))
		_light_step = 0
		return true
	if _peek(FighterInput.LIGHT):
		_consume(FighterInput.LIGHT)
		if state == State.DODGE or (from_cancel and move_slot == "dodge"):
			if creature.moves.has("dash_attack"):
				var dv: Array = _move_variant("dash_attack")
				_start_move(dv[0], dv[1], State.ATTACK)
				return true
		var string: Array = creature.light_string
		var step := _light_step if from_cancel and _light_step < string.size() else 0
		var slot2: String = string[step]
		var lv: Array = _move_variant(slot2)
		if lv.is_empty():
			lv = _move_variant("l1")
		_start_move(lv[0], lv[1], State.ATTACK)
		_light_step = step + 1
		return true
	if not from_cancel and _peek(FighterInput.TAUNT) and _taunt_cd <= 0.0:
		_consume(FighterInput.TAUNT)
		_taunt_cd = Tuning.v("taunt_cooldown")
		if creature.moves.has("taunt"):
			_start_move(creature.moves["taunt"], "taunt", State.TAUNT)
		gain_hype(Tuning.v("taunt_hype"))
		hooks.fire("taunt", {})
		_emit({"type": "taunt"})
		return true
	if not from_cancel and guard_held:
		_set_state(State.GUARD)
		guard_pressed_at = time if _consume(FighterInput.GUARD) else time - 1.0
		return true
	return false


func gain_hype(amount: float) -> void:
	hype = clampf(hype + amount * float(mods["hype_gain"]), 0.0, 100.0)


func _start_move(m: MoveDef, slot: String, st: int) -> void:
	if not slot.ends_with("@hovering") and has_flag("hovering") and slot != "juice":
		_hover_until = -1.0
	move = m
	move_slot = slot
	move_hits.clear()
	move_hit_any = false
	move_charge = 1.0 if bool(mods.get("auto_charge", false)) and m.charge_time > 0.0 else 0.0
	_charging = false
	_charge = {}
	_set_state(st)
	spend_stamina(m.stamina * float(mods.get("stamina_cost", 1.0)))
	# targeting assistance: snap toward the target if roughly in front, else toward input
	var snap := Tuning.v("attack_snap_deg") * float(mods.get("assist", 1.0))
	if _focus_preferred():
		var to_fp: Vector3 = focus_point - pos()
		facing_yaw = atan2(to_fp.x, to_fp.z)
	elif _target_in_lock_range():
		var want := _yaw_to_target()
		if absf(MathX.wrap_angle(want - facing_yaw)) < deg_to_rad(snap) or input.move.length() < 0.2:
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
	hooks.fire("move_start", {"slot": slot.split("@")[0], "move_class": current_move_class()})
	_emit({"type": "move_start", "slot": slot, "id": m.id})
	if sim and not m.effects.is_empty():
		sim.effects.begin_move(self, m)


func _st_move(dt: float) -> void:
	var t := state_time
	var m := move
	if m == null:
		_set_state(State.NEUTRAL)
		return
	if _charging:
		if input.is_held(FighterInput.HEAVY) and move_charge < 1.0 and t >= m.first_active() * 0.7:
			move_charge = minf(1.0, move_charge + dt / m.charge_time)
			state_time -= dt * _time_scale()
			t = state_time
			armor_until = time + 0.05
			armor_level = "lights"
		elif not input.is_held(FighterInput.HEAVY) or move_charge >= 1.0:
			_charging = false
			if move_charge >= 0.35 and creature.moves.has("heavy_charged") and move_slot == "heavy":
				# a long hold switches to the dedicated charged heavy
				var cv: Array = _move_variant("heavy_charged")
				var keep := move_charge
				_start_move(cv[0], cv[1], State.ATTACK)
				move_charge = keep
				return
	motor.guard_blend = move_toward(motor.guard_blend, 0.0, dt / Tuning.v("guard_blend_time"))
	m.apply_overlay(t, motor)
	if not _charge.is_empty():
		_update_charge(dt)
	else:
		var mv := input.move
		var spd := eff("walk_speed") * m.move_mult * speed_mult()
		var lunge := m.lunge_speed(t)
		rig.desired_vel = mv * spd + forward() * lunge
		rig.max_accel = eff("accel") * (1.6 if lunge > 0.0 else 1.0)
		if target and _target_in_lock_range():
			_turn_toward(_yaw_to_target(), m.turn_rate, dt)
	if m.in_ranges(m.armor, t):
		armor_until = time + 0.02
		armor_level = m.armor_level
	if m.in_ranges(m.invuln, t):
		evade_until = time + 0.02
	if sim and not m.effects.is_empty():
		sim.effects.tick_move(self, m, t, dt)
	if move == null or move != m:
		return
	if t >= m.cancel_t0 and (not m.cancel_on_hit or move_hit_any) and state == State.ATTACK:
		if _try_actions(true):
			return
	if t >= m.duration:
		if not move_hit_any and m.kind == "melee" and not m.windows.is_empty():
			spend_stamina(m.stamina * Tuning.v("whiff_stamina_extra"))
		_end_move()


func _end_move() -> void:
	if sim and move and not move.effects.is_empty():
		sim.effects.end_move(self, move)
	if not _charge.is_empty():
		_finish_charge()
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
	# a successful parry grants a short free cancel into anything
	if time - _last_parry < Tuning.v("parry_free_cancel"):
		if _try_actions(false):
			return
	if _peek(FighterInput.DODGE) and _dodge_cd <= 0.0 and not statuses.flag("no_dodge"):
		_consume(FighterInput.DODGE)
		_start_dodge()


func _start_dodge() -> void:
	var dir := input.move
	if dir.length() < 0.2:
		dir = -forward()
	dodge_dir = dir.normalized()
	spend_stamina(Tuning.v("dodge_stamina") * statuses.mult("dodge_cost") * float(mods.get("dodge_cost", 1.0)))
	_dodge_cd = Tuning.v("dodge_cooldown") + eff("dodge_time")
	_set_state(State.DODGE)
	move_slot = "dodge"
	evade_until = time + Tuning.v("dodge_evade_end")
	hooks.fire("dodge", {})
	_emit({"type": "dodge"})


func _st_dodge(dt: float) -> void:
	var dur := eff("dodge_time")
	var t := state_time
	_clear_overlay()
	motor.overlay_lean = Vector3(-8.0 if dodge_dir.dot(forward()) < 0.0 else 8.0, 0.0, 0.0)
	motor.overlay_height = -0.08 * creature.body.scale
	if t < dur:
		var dist := eff("dodge_distance") * float(mods.get("dodge_distance", 1.0)) * statuses.mult("dash")
		rig.desired_vel = dodge_dir * (dist / maxf(dur, 0.05)) * speed_mult()
		rig.max_accel = 90.0
		if _peek(FighterInput.LIGHT) and creature.moves.has("dash_attack") and t > dur * 0.35:
			_consume(FighterInput.LIGHT)
			var dv: Array = _move_variant("dash_attack")
			_start_move(dv[0], dv[1], State.ATTACK)
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


func knock_down(reason := "hit", by: Fighter = null) -> void:
	if state == State.KO or is_out():
		return
	_release_grab()
	_end_carry()
	if held_by:
		held_by._release_grab()
	_interrupt_move()
	_hover_until = -1.0
	_set_state(State.KNOCKDOWN)
	_clear_overlay()
	rig.muscle = Tuning.v("knockdown_muscle")
	rig.hover_enabled = false
	otg_hits = 0
	poise = effective_max_poise()
	stats_record["knockdowns"] += 1
	hooks.fire("knocked_down", {"other": by})
	if by:
		by.hooks.fire("knockdown_dealt", {"other": self})
		by.gain_hype(6.0)
	_emit({"type": "knockdown", "reason": reason})


func _st_knockdown(_dt: float) -> void:
	rig.desired_vel = Vector3.ZERO
	motor.tuck = true
	if state_time > Tuning.v("knockdown_min") / float(mods.get("getup_speed", 1.0)) and rig.root().linear_velocity.length() < 1.5:
		_set_state(State.DOWN)


func _st_down(_dt: float) -> void:
	rig.desired_vel = Vector3.ZERO
	var wants := input.move.length() > 0.5 or not _buffer.is_empty()
	if (state_time > 0.15 and wants) or state_time > Tuning.v("knockdown_auto_getup") / float(mods.get("getup_speed", 1.0)):
		_buffer.clear()
		_set_state(State.GETUP)
		rig.hover_enabled = true
		rig.upright_strength = 0.0
		invuln_until = time + Tuning.v("getup_time") + Tuning.v("wakeup_invuln")
		_emit({"type": "getup"})


func _st_getup(dt: float) -> void:
	var gt := Tuning.v("getup_time") / float(mods.get("getup_speed", 1.0))
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


func _st_celebrate(_dt: float) -> void:
	rig.desired_vel = Vector3.ZERO
	_clear_overlay()
	motor.overlay_height = absf(sin(state_time * 6.0)) * 0.08


func _st_out(_dt: float) -> void:
	rig.desired_vel = Vector3.ZERO
	# resting tag partners stand and bounce on the apron; everyone else lies there
	var resting := bool(flags.get("resting", false))
	motor.tuck = not resting
	if resting:
		_clear_overlay()
		motor.overlay_height = absf(sin(time * 3.0)) * 0.04


func knock_out(by: Fighter = null) -> void:
	_release_grab()
	_end_carry()
	if held_by:
		held_by._release_grab()
	_interrupt_move()
	_set_state(State.KO)
	_clear_overlay()
	rig.muscle = Tuning.v("ko_muscle")
	rig.hover_enabled = false
	health = 0.0
	if by:
		by.hooks.fire("ko_dealt", {"other": self})
	_emit({"type": "ko", "by": by.index if by else -1})


func set_downed() -> void:
	_release_grab()
	_end_carry()
	_interrupt_move()
	_set_state(State.DOWNED)
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
		_end_carry()
		_interrupt_move()
		_set_state(State.CELEBRATE)


func set_inactive(on: bool) -> void:
	if on:
		_release_grab()
		_interrupt_move()
		_set_state(State.INACTIVE)
		rig.muscle = 0.3
	else:
		rig.muscle = 1.0
		_set_state(State.NEUTRAL)


# =====================================================================================
# JUICE
# =====================================================================================

func _start_juice() -> void:
	hype = 0.0
	var ab: MoveDef = creature.abilities["juice"]
	juiced_until = time + float(creature.juice.get("duration", Tuning.v("juice_duration"))) + ab.duration
	_start_move(ab, "juice", State.ABILITY)
	invuln_until = time + 0.3
	armor_until = time + ab.duration
	armor_level = "all"
	hooks.fire("juice_start", {})
	_emit({"type": "juice", "id": ab.id})


## JUICE state effect: temporary hooks, status-style modifiers, armor, end effects.
func apply_juice_state(e: Dictionary) -> void:
	var dur := float(e.get("duration", creature.juice.get("duration", 6.0)))
	juiced_until = time + dur
	juice_armor = str(e.get("armor", ""))
	for h in e.get("hooks", []):
		hooks.add(h, "juice", dur)
	var st: Dictionary = e.get("status", {}).duplicate(true)
	if not st.is_empty():
		st["id"] = "juiced"
		st["duration"] = dur
		st["source"] = self
		statuses.add(st)
	_juice_end_effects = e.get("end", [])


func _end_juice() -> void:
	juiced_until = -1.0
	juice_armor = ""
	crash_until = time + Tuning.v("juice_crash")
	hooks.remove_source("juice")
	statuses.remove("juiced")
	for ef in _juice_end_effects:
		if typeof(ef) == TYPE_DICTIONARY:
			match str(ef.get("type", "")):
				"stamina":
					stamina = maxf(0.0, stamina + float(ef.get("amount", -30.0)))
				_:
					if sim:
						sim.effects.fire(self, ef, null)
	_juice_end_effects = []
	hooks.fire("juice_end", {})
	_emit({"type": "juice_end"})


# =====================================================================================
# Special states: hover, charge/carry, counter, airborne, submerge, splat, flinch
# =====================================================================================

func _update_specials(dt: float) -> void:
	if _airborne:
		var landed := rig.grounded and rig.ground_dist < rig.hover_height + 0.1 and time > _air_until - 0.15
		if landed or time > _air_until + 0.8:
			_land()
	if not _submerge.is_empty() and time >= float(_submerge["until"]):
		var dest: Vector3 = _submerge["dest"]
		rig.place(Vector3(dest.x, rig.ground_y, dest.z), facing_yaw)
		motor.reset_feet()
		var emerge: Array = _submerge["on_emerge"]
		_submerge = {}
		clear_flag("submerged")
		for ef in emerge:
			if sim:
				sim.effects.fire(self, ef, null)
	if not _splat.is_empty():
		if time > float(_splat["until"]):
			_splat = {}
		else:
			var spd := rig.root().linear_velocity.length()
			if spd > 2.0 and sim and (not sim.arena.inside(pos(), 0.75) or _near_blocking_prop()):
				var by: Fighter = _splat["by"]
				var params: Dictionary = _splat["params"]
				_splat = {}
				var dmg := float(params.get("damage", 4.0)) + float(by.mods.get("splat_damage_add", 0.0) if by else 0.0)
				sim.combat.apply_simple_damage(by, self, dmg, "wall_splat", {"stun": float(params.get("stun", 0.3)), "poise": float(params.get("poise", 0.0)) + float(by.mods.get("splat_poise_add", 0.0) if by else 0.0), "knockdown": bool(params.get("knockdown", false))})
				if by:
					by.hooks.fire("wall_splat", {"other": self})
				_emit({"type": "splat", "pos": pos(), "by": by.index if by else -1})


func _near_blocking_prop() -> bool:
	for ent in sim.effects.entities:
		if ent["kind"] == "prop" and ent.get("body") != null:
			if Vector2(pos().x - ent["pos"].x, pos().z - ent["pos"].z).length() < float(ent["radius"]) + 0.6:
				return true
	for b in sim.arena_nodes.get("props", []):
		var n := b as Node3D
		if n and not (n is RigidBody3D) and n.global_position.distance_to(pos()) < 1.0:
			return true
	return false


func arm_splat(by: Fighter, params: Dictionary) -> void:
	_splat = {"by": by, "until": time + float(params.get("window", 0.7)), "params": params}


func start_hover(height: float, duration: float, speed: float) -> void:
	_hover_until = time + duration * float(mods.get("hover_duration", 1.0))
	_hover_extra = height
	_hover_speed = speed
	_emit({"type": "hover"})


func begin_airborne(on_land: Array, air_time: float) -> void:
	_airborne = true
	_air_until = time + air_time
	_on_land = on_land
	rig.support = 0.0
	rig.hover_enabled = false
	motor.tuck = true


func _land() -> void:
	_airborne = false
	rig.support = 1.0
	if not is_down() and not is_out():
		rig.hover_enabled = true
		motor.tuck = false
		motor.reset_feet()
	for ef in _on_land:
		if sim and typeof(ef) == TYPE_DICTIONARY:
			sim.effects.fire(self, ef, null)
	_on_land = []
	hooks.fire("land", {})
	_emit({"type": "land", "pos": ground_pos()})
	if pending_land_stun > 0.0:
		stun(pending_land_stun, true)
		pending_land_stun = 0.0


func begin_submerge(dest: Vector3, delay: float, on_emerge: Array) -> void:
	_submerge = {"dest": dest, "until": time + delay, "on_emerge": on_emerge}
	set_flag("submerged", delay)
	_emit({"type": "submerge", "pos": ground_pos(), "dest": dest})


## Steerable charge (e.g. Bulldoze): {speed, distance, steer_deg, carry, wall_stagger, splat{}}.
func start_charge(e: Dictionary) -> void:
	_charge = e.duplicate()
	_charge["dist"] = 0.0
	_charge["max"] = float(e.get("distance", 6.0)) * float(mods.get("charge_distance", 1.0))
	_charge["speed"] = float(e.get("speed", 7.0)) * float(mods.get("charge_speed", 1.0))


func _update_charge(dt: float) -> void:
	var steer := deg_to_rad(float(_charge.get("steer_deg", 20.0))) * float(mods.get("charge_steer", 1.0))
	if input.move.length() > 0.3:
		_turn_toward(atan2(input.move.x, input.move.z), steer, dt)
	var spd := float(_charge["speed"])
	rig.desired_vel = forward() * spd
	rig.max_accel = 60.0
	_charge["dist"] = float(_charge["dist"]) + spd * dt
	if bool(_charge.get("carry", true)) and _carried == null and move_hit_any and last_hit_target and not last_hit_target.is_out():
		_carried = last_hit_target
		_carried.stun(1.2, true)
		_emit({"type": "carry", "victim": _carried.index})
	if _carried:
		var front := pos() + forward() * (0.9 * creature.body.scale) + Vector3.UP * 0.2
		var delta := front - _carried.pos()
		_carried.rig.apply_body_impulse((delta * 6.0 + forward() * spd - _carried.rig.com_velocity()) * _carried.rig.total_mass * dt * 8.0)
	var hit_wall := sim != null and not sim.arena.inside(pos() + forward() * 0.9, 0.3)
	if hit_wall or float(_charge["dist"]) >= float(_charge["max"]):
		_finish_charge(hit_wall)
		_end_move()


func _finish_charge(hit_wall := false) -> void:
	var c := _charge
	_charge = {}
	if c.is_empty():
		return
	if hit_wall:
		if _carried and not _carried.is_out():
			var sp: Dictionary = c.get("splat", {"damage": 5.0, "stun": 0.4, "knockdown": true})
			var by := self
			sim.combat.apply_simple_damage(by, _carried, float(sp.get("damage", 5.0)) + float(mods.get("splat_damage_add", 0.0)), "wall_splat", {"stun": float(sp.get("stun", 0.4)), "knockdown": bool(sp.get("knockdown", true)), "poise": float(mods.get("splat_poise_add", 0.0))})
			hooks.fire("wall_splat", {"other": _carried})
			_emit({"type": "splat", "pos": _carried.pos(), "by": index})
		elif float(c.get("wall_stagger", 0.6)) > 0.0:
			_end_carry()
			stun(float(c.get("wall_stagger", 0.6)), true)
			_emit({"type": "wall_bonk"})
	_end_carry()


func _end_carry() -> void:
	_carried = null


## Counter stance (e.g. Anchor Drop): {duration, counter: {damage, poise, buildup, element}}.
func start_counter(e: Dictionary) -> void:
	_counter_until = time + float(e.get("duration", 2.5))
	_counter = e.get("counter", {})
	armor_until = _counter_until
	armor_level = "all"
	statuses.add({"id": "anchored", "name": "Anchored", "duration": float(e.get("duration", 2.5)), "knockback_taken": float(e.get("knockback_taken", 0.5))})


func fire_counter(attacker: Fighter) -> void:
	if attacker == null or sim == null:
		return
	var e: Dictionary = _counter.duplicate()
	e["kb_dir"] = "away"
	sim.effects.effect_hit(self, attacker, e, pos())
	_emit({"type": "counter", "victim": attacker.index})


## Micro-flinch (Jolted pulses, live puddles): interrupts charges, holds, grabs, channels and
## hovering; otherwise just a visible twitch.
func flinch(seconds: float) -> void:
	if is_out() or is_down():
		return
	var interrupt := _charging or state in [State.GRABBING, State.HELD] or (state == State.ABILITY and move and move.channel) or has_flag("hovering") or not _charge.is_empty()
	if interrupt:
		_hover_until = -1.0
		stun(seconds, true)
	stagger(0, 0.5)
	_emit({"type": "flinch", "interrupted": interrupt})


# =====================================================================================
# Grabs
# =====================================================================================

func begin_grab(victim: Fighter, my_seg: int, victim_seg: int) -> void:
	if victim.held_by or victim.holding:
		return
	holding = victim
	victim.held_by = self
	_hold_left = Tuning.v("grab_hold_max") * float(victim.mods.get("held_time_mult", 1.0))
	victim._escape_presses = 0
	_pummels = 0
	_interrupt_move()
	_set_state(State.GRABBING)
	victim._interrupt_move()
	victim._set_state(State.HELD)
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
	hooks.fire("grab_start", {"other": victim})
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
		var pm: MoveDef = creature.moves.get("pummel")
		var pdmg := pm.damage if pm else Tuning.v("pummel_damage")
		if sim:
			var hp := {"attacker": self, "damage": pdmg, "point": holding.pos(), "normal": Vector3.UP, "seg": 0, "part": "core",
				"blocked": false, "parried": false, "counter": false, "knockback": Vector3.ZERO, "local_impulse": Vector3.ZERO,
				"stun": 0.0, "poise": 4.0, "knockdown": false, "hype_mult": 1.0, "element": pm.element if pm else creature.element,
				"buildup": pm.buildup if pm else 0.0, "move": "pummel", "slot": "pummel", "move_class": "grab", "unblockable": true,
				"from": pos(), "melee": false, "status": {}, "splat": {}, "ignore_evade": true}
			sim.combat.deliver(self, holding, hp)
		return
	elif _hold_left <= 0.0:
		throw_dir = forward()
	if throw_dir != Vector3.ZERO:
		_do_throw(throw_dir)


func _do_throw(throw_dir: Vector3) -> void:
	var v := holding
	_release_grab()
	# pick the throw flavour by direction relative to facing: fwd / side / back
	var rel := throw_dir.normalized()
	var fwd := forward()
	var kind := "throw_fwd"
	if rel.dot(fwd) < -0.4:
		kind = "throw_back"
	elif absf(rel.dot(fwd.cross(Vector3.UP))) > 0.6:
		kind = "throw_side"
	var td: Dictionary = creature.throws.get(kind, creature.throws.get("throw_fwd", {}))
	var dist := float(td.get("distance", 2.5)) * float(mods.get("throw_distance", 1.0))
	var mass_ratio := clampf(sqrt(Tuning.v("ref_mass") / maxf(20.0, v.rig.total_mass)), 0.5, 1.6)
	var air := 0.55
	var horiz := rel * (dist * mass_ratio / air)
	var vy := (sim.gravity if sim else 9.81) * air * 0.5 + float(td.get("up", 0.0))
	v.rig.apply_body_impulse((horiz + Vector3.UP * vy - v.rig.com_velocity()) * v.rig.total_mass)
	if sim:
		var dmg := float(td.get("damage", Tuning.v("throw_damage")))
		sim.combat.apply_simple_damage(self, v, dmg, "throw")
		if td.has("buildup") and creature.element != "":
			v.statuses.add_buildup(creature.element, float(td["buildup"]), self)
	v.thrown_speed = horiz.length()
	v.arm_splat(self, {"damage": 4.0 + float(mods.get("splat_damage_add", 0.0)), "stun": 0.3, "poise": float(mods.get("splat_poise_add", 0.0)), "window": 1.0})
	if bool(td.get("knockdown", true)) and not v.is_out():
		v.knock_down("throw", self)
	stats_record["throws"] += 1
	hooks.fire("throw", {"other": v})
	_emit({"type": "throw", "victim": v.index, "kind": kind})
	_set_state(State.NEUTRAL)


func _st_held(_dt: float, presses: int) -> void:
	_clear_overlay()
	rig.desired_vel = Vector3.ZERO
	if held_by == null:
		_set_state(State.NEUTRAL)
		return
	if statuses.has("encrusted") and state_time < float(statuses.get_status("encrusted").get("grab_lock", 1.0)):
		return
	var n := 0
	for b in FighterInput.BUTTON_COUNT:
		if (presses >> b) & 1:
			n += 1
	if n > 0:
		_escape_presses += n
		if _escape_presses >= int(Tuning.v("grab_escape_presses")):
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

func _armor_covers(move_class: String) -> bool:
	var level := ""
	if time < armor_until:
		level = armor_level
	if juice_armor != "" and time < juiced_until:
		level = juice_armor if level == "" else level
	if statuses.flag("armor_all"):
		level = "all"
	elif level == "" and statuses.flag("armor_lights"):
		level = "lights"
	match level:
		"all":
			return move_class != "grab"
		"lights":
			return move_class == "light"
		"all_but_heavy":
			return move_class != "heavy" and move_class != "grab"
	return false


## Applies a resolved hit (from Combat.deliver).
func receive_hit(h: Dictionary) -> void:
	var attacker: Fighter = h.get("attacker")
	var dmg: float = h["damage"]
	if h.get("parried", false):
		_emit({"type": "parry", "attacker": attacker.index if attacker else -1, "pos": h["point"]})
		gain_hype(Tuning.v("parry_hype"))
		_last_parry = time
		stats_record["parries"] += 1
		if attacker:
			attacker.stun(Tuning.v("parry_stun"), true)
		return
	health -= dmg
	stats_record["damage_taken"] += dmg
	var mc := str(h.get("move_class", ""))
	if attacker and attacker != self and dmg > 0.0:
		var gain: float = float({"light": 2.0, "heavy": 4.0, "ability": 3.0, "juice": 0.0}.get(mc, 1.0))
		attacker.gain_hype(float(gain) * float(h.get("hype_mult", 1.0)))
		gain_hype(2.0 if mc == "heavy" else 1.0)
		attacker.stats_record["damage_dealt"] += dmg
		attacker.stats_record["hits"] += 1
		attacker.last_hit_target = self
	if h.get("blocked", false):
		stats_record["blocks"] += 1
		var drain: float = h.get("guard_drain", 0.0)
		spend_stamina(drain)
		var low_heavy := mc == "heavy" and stamina < Tuning.v("stamina_low")
		if stamina <= 0.0 or low_heavy:
			_emit({"type": "guard_break"})
			stun(Tuning.v("guard_break_stun"), true)
			_set_state(State.GUARD_BREAK)
	# physical reaction
	var seg_i: int = h.get("seg", 0)
	var kb: Vector3 = h.get("knockback", Vector3.ZERO)
	var armored := _armor_covers(mc)
	if armored:
		kb *= 0.3
	if kb != Vector3.ZERO:
		rig.apply_body_impulse(kb * rig.total_mass)
	var local_imp: Vector3 = h.get("local_impulse", Vector3.ZERO)
	if local_imp != Vector3.ZERO and not armored:
		rig.apply_impulse_at(seg_i, local_imp, h["point"])
	stagger(seg_i, clampf(dmg / 18.0, 0.2, 1.0) * (0.3 if armored else 1.0))
	if health <= 0.0:
		if sim:
			sim.on_fighter_depleted(self, attacker, h)
		else:
			knock_out(attacker)
		return
	if h.get("blocked", false):
		return
	if is_down():
		otg_hits += 1
		return
	var pdmg := float(h.get("poise", 0.0)) / float(mods["poise"])
	if mc == "heavy":
		pdmg *= statuses.mult("heavy_poise_taken")
	poise -= pdmg
	_poise_delay = Tuning.v("poise_regen_delay")
	if poise <= 0.0 or (h.get("knockdown", false) and not armored):
		if not (armored and poise > 0.0):
			knock_down("poise" if poise <= 0.0 else "move", attacker)
			return
	if armored:
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
	if not _charge.is_empty():
		_charge = {}
		_end_carry()
	move = null
	move_slot = ""
	_charging = false
	if rig:
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


func in_parry_window(_attacker = null) -> bool:
	return state == State.GUARD and time - guard_pressed_at <= Tuning.v("parry_window") + float(mods.get("parry_window_add", 0.0))


func is_winding_up() -> bool:
	return (state == State.ATTACK or state == State.ABILITY) and move != null and state_time < move.first_active()


# =====================================================================================
# Observation helpers (AI, HUD, network)
# =====================================================================================

func state_name() -> String:
	return STATE_NAMES[state]


func cooldown_frac(slot: String) -> float:
	if int(charges_left.get(slot, 1)) > 0:
		return 0.0
	var total := float(creature.cooldowns.get(slot, 1.0))
	return clampf(float(cooldown_left.get(slot, 0.0)) / maxf(total, 0.01), 0.0, 1.0)
