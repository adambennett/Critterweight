class_name MatchSim
extends Node3D
## One authoritative match: arena physics, fighters, effect entities, hittable mode objects,
## rules/mode and the event stream. Runs identically offline, on a listen/dedicated server, and
## (many at once, in their own World3D) inside AI Lab training workers. It never touches
## rendering, input devices or UI.
##
## Tick order (every physics tick, 120 Hz):
##   1. the mode publishes per-fighter focus points (objectives worth facing)
##   2. input sources write each fighter's FighterInput
##   3. fighters advance their state machines, poses and muscles
##   4. Combat validates weapon contacts -> hits (fighters and hittable objects)
##   5. effects (projectiles/zones/props) and arena hazards update
##   6. environment checks (ring-outs, wall slams)
##   7. the mode advances phases/scoring
## then Godot steps the physics world.
##
## Fighter indices are stable for the whole match. Despawned fighters (e.g. dead minions) keep
## their slot in an inactive state until a later spawn reuses it ("fighter_spawned" event).

signal finished(result: Dictionary)

const MAX_EVENTS := 512
const MAX_FIGHTERS := 24

var fighters: Array[Fighter] = []
var combat: Combat
var effects: EffectsSystem
var mode: MatchMode
var arena: ArenaDef
var arena_nodes := {}
var rules := {}
var seed_value := 0
var rng := RandomNumberGenerator.new()
var tick_count := 0
var time := 0.0
var input_enabled := true
var running := true
var paused := false
var is_finished := false
var result := {}
var input_sources: Array = []    ## per fighter: object with poll(fighter, sim, dt)
var events: Array = []           ## ring of recent events (Dictionaries with "seq")
var event_seq := 0
var hittables: Array = []        ## mode objects weapons can strike (see register_hittable)
var hazards = null               ## optional ArenaHazards runner (timed hazards, pickups)
var gravity := 9.81              ## arena gravity_mult x rules gravity_mult (low-grav rules)
var profiling := false           ## bench: accumulate per-section costs (usec) into `prof`
var prof := {}
var _prev_speed := {}            ## fighter index -> root speed last tick (slam detection)
var _fighter_root: Node3D


func _init() -> void:
	combat = Combat.new(self)
	effects = EffectsSystem.new(self)


## config: {arena: ArenaDef, rules: Dictionary, seed: int, mode: MatchMode (optional),
##          fighters: [{creature: CreatureDef, team: int, source: InputSource, name: String, kind, mods}]}
func setup(config: Dictionary) -> void:
	name = "MatchSim"
	arena = config["arena"]
	rules = config.get("rules", {}).duplicate(true)
	seed_value = int(config.get("seed", 1))
	rng.seed = seed_value
	arena_nodes = ArenaBuilder.build(self, arena)
	gravity = 9.81 * arena.gravity_mult * RulesValidator.field_num(rules, "gravity_mult")
	if is_inside_tree():
		PhysicsServer3D.area_set_param(get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, gravity)
	_fighter_root = Node3D.new()
	_fighter_root.name = "Fighters"
	add_child(_fighter_root)
	var entries: Array = config.get("fighters", [])
	for i in entries.size():
		var e: Dictionary = entries[i]
		var sp := arena.spawn_point(i, entries.size())
		_create_fighter(i, e, sp[0], sp[1])
	ArenaBuilder.spawn_hazards(self, arena)
	mode = config.get("mode", null)
	if mode == null:
		mode = MatchMode.new()
	mode.setup(self)
	emit_event({"type": "match_start", "arena": arena.id, "mode": mode.id(), "seed": seed_value})


func _create_fighter(idx: int, e: Dictionary, pos: Vector3, yaw: float) -> Fighter:
	var f := Fighter.new()
	_fighter_root.add_child(f)
	f.setup(e["creature"], idx, int(e.get("team", idx)), self, pos, yaw)
	f.rig.gravity = gravity
	f.display_name = str(e.get("name", f.creature.display_name))
	f.controller_kind = str(e.get("kind", "bot"))
	for k in e.get("mods", {}):
		var mv = e["mods"][k]
		f.mods[k] = mv if typeof(mv) == TYPE_STRING or typeof(mv) == TYPE_BOOL else float(mv)
	for h in e.get("hooks", []):
		f.hooks.add(h, "loadout")
	# Movesets or Classic (the match rule; a missing key is Movesets, docs/design/MOVESET_COMBAT.md §1)
	# with the entry's loadout when it is valid for this creature
	f.set_combat(combat_style(), e.get("loadout", []) if typeof(e.get("loadout", [])) == TYPE_ARRAY else [])
	_apply_rule_mods(f)
	if idx < fighters.size():
		fighters[idx] = f
		input_sources[idx] = e.get("source")
	else:
		fighters.append(f)
		input_sources.append(e.get("source"))
	return f


## The match's combat style: "moves" (the default) or "classic" (rules `combat`).
func combat_style() -> String:
	return "classic" if str(rules.get("combat", "moves")) == "classic" else "moves"


## Rules multipliers are clamped to RulesValidator's ranges here as well: rules may come from mods,
## imported presets or a host, and a non-number or huge value must never reach the physics.
func _apply_rule_mods(f: Fighter) -> void:
	f.mods["damage"] = float(f.mods["damage"]) * RulesValidator.field_num(rules, "damage_mult")
	f.mods["knockback_taken"] = float(f.mods["knockback_taken"]) * RulesValidator.field_num(rules, "knockback_mult")
	f.mods["cooldown"] = float(f.mods["cooldown"]) * RulesValidator.field_num(rules, "cooldown_rate")
	f.mods["hype_gain"] = float(f.mods["hype_gain"]) * RulesValidator.field_num(rules, "hype_mult")
	f.mods["max_health"] = float(f.mods.get("max_health", 1.0)) * RulesValidator.field_num(rules, "health_mult")
	f.mods["stamina_regen"] = float(f.mods["stamina_regen"]) * RulesValidator.field_num(rules, "regen_mult")
	if rules.has("start_hype"):
		f.mods["start_hype"] = RulesValidator.field_num(rules, "start_hype")
	if not bool(rules.get("abilities", true)):
		f.mods["no_abilities"] = true
	if not bool(rules.get("juice", true)):
		f.mods["no_juice"] = true
	if not bool(rules.get("grabs", true)):
		f.mods["no_grabs"] = true
	# data-driven rule extensions (custom rules and rule/mode mods): stat mods and hooks for all.
	# Rules can come from mods, imported presets or a host, so only whitelisted modifiers with
	# clamped finite values are applied (RulesValidator.FIGHTER_MODS).
	var fm := RulesValidator.clean_fighter_mods(rules.get("fighter_mods", {}))
	for k in fm:
		var v = fm[k]
		if typeof(v) == TYPE_BOOL:
			f.mods[k] = v
		elif str(k).ends_with("_add"):
			f.mods[k] = float(f.mods.get(k, 0.0)) + float(v)
		elif k == "start_hype":
			f.mods[k] = clampf(float(f.mods.get(k, 0.0)) + float(v), 0.0, 100.0)
		else:
			f.mods[k] = float(f.mods.get(k, 1.0)) * float(v)
	var fh = rules.get("fighter_hooks", [])
	if typeof(fh) == TYPE_ARRAY:
		for h in fh:
			if typeof(h) == TYPE_DICTIONARY:
				f.hooks.add(h, "rules")
	f.reset_vitals()


## Adds a fighter mid-match (waves, reinforcements, late joiners). Reuses a despawned slot when
## one exists so indices stay small and stable. Returns the new Fighter.
func spawn_fighter(entry: Dictionary, pos: Vector3, yaw: float) -> Fighter:
	var idx := -1
	for i in fighters.size():
		if fighters[i].despawned:
			idx = i
			break
	if idx < 0:
		if fighters.size() >= MAX_FIGHTERS:
			return null
		idx = fighters.size()
	elif idx < fighters.size():
		var old := fighters[idx]
		old.queue_free()
	var f := _create_fighter(idx, entry, pos, yaw)
	f.invuln_until = f.time + float(entry.get("spawn_invuln", 0.5))
	emit_event({"type": "fighter_spawned", "fighter": idx, "creature": f.creature.id, "team": f.team})
	return f


## Removes a fighter's body from the world; its slot stays reserved until reused.
func despawn_fighter(f: Fighter) -> void:
	if f.despawned:
		return
	f.despawn()
	emit_event({"type": "fighter_despawned", "fighter": f.index})


func set_input_source(i: int, src) -> void:
	input_sources[i] = src


func active_fighters() -> Array:
	return fighters.filter(func(f: Fighter): return not f.despawned)


func are_enemies(a: Fighter, b: Fighter) -> bool:
	if a == b:
		return false
	return a.team != b.team


func can_hit(a: Fighter, b: Fighter) -> bool:
	if a == b or b.despawned:
		return false
	if a.team == b.team:
		return bool(rules.get("friendly_fire", false))
	return true


func clamp_to_arena(p: Vector3, margin: float) -> Vector3:
	return arena.clamp_point(p, margin) if arena else p


## Hittable objects (balls, bags, mode targets). entry: {id, body: RigidBody3D, radius,
## on_hit: Callable(attacker: Fighter, dir: Vector3, speed: float, element: String, point: Vector3)}
func register_hittable(entry: Dictionary) -> void:
	hittables.append(entry)


func unregister_hittable(id: String) -> void:
	hittables = hittables.filter(func(h): return str(h["id"]) != id)


func emit_event(ev: Dictionary) -> void:
	if str(ev.get("type", "")) == "hit":
		var ti := int(ev.get("target", -1))
		var ai := int(ev.get("fighter", -1))
		if ti >= 0 and ti < fighters.size() and ai >= 0 and ai != ti:
			fighters[ti].last_attacker_index = ai
			fighters[ti].last_attacked_at = time
	event_seq += 1
	ev["seq"] = event_seq
	ev["tick"] = tick_count
	events.append(ev)
	if events.size() > MAX_EVENTS:
		events.pop_front()


## Events with seq > after_seq (consumers keep their own cursor).
func events_since(after_seq: int) -> Array:
	var out := []
	for ev in events:
		if int(ev["seq"]) > after_seq:
			out.append(ev)
	return out


func _physics_process(dt: float) -> void:
	if not running or paused:
		return
	step(dt)


func _exit_tree() -> void:
	# the world outlives the match (menus, the hub): put its gravity back
	if gravity != 9.81 and get_world_3d():
		PhysicsServer3D.area_set_param(get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY,
			float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)))


func step(dt: float) -> void:
	tick_count += 1
	time += dt
	var t0 := Time.get_ticks_usec() if profiling else 0
	for f in fighters:
		if not f.despawned:
			f.focus_point = mode.focus_point(f) if mode else null
	for i in fighters.size():
		var f := fighters[i]
		if f.despawned:
			continue
		var src = input_sources[i]
		if src != null:
			src.poll(f, self, dt)
		if not input_enabled or is_finished:
			f.input.move = Vector3.ZERO
			f.input.held = 0
			f._buffer.clear()
	var t1 := Time.get_ticks_usec() if profiling else 0
	for f in fighters:
		if not f.despawned:
			f.sim_tick(dt)
	var t2 := Time.get_ticks_usec() if profiling else 0
	combat.detect_hits()
	var t3 := Time.get_ticks_usec() if profiling else 0
	effects.update(dt)
	if hazards != null:
		hazards.update(dt)
	_environment_checks()
	if mode and not is_finished:
		mode.tick(dt)
	if profiling:
		var t4 := Time.get_ticks_usec()
		prof["input"] = float(prof.get("input", 0.0)) + (t1 - t0)
		prof["fighters"] = float(prof.get("fighters", 0.0)) + (t2 - t1)
		prof["combat"] = float(prof.get("combat", 0.0)) + (t3 - t2)
		prof["effects_mode"] = float(prof.get("effects_mode", 0.0)) + (t4 - t3)
		prof["ticks"] = float(prof.get("ticks", 0.0)) + 1.0


func _environment_checks() -> void:
	for f in fighters:
		if f.state == Fighter.State.INACTIVE or f.despawned:
			continue
		var p := f.pos()
		# containment: a walled cage never loses a fighter. The collision walls are tall, but an
		# extreme impulse can still tunnel a rig through; pull it back and report it.
		if arena.wall_height > 0.01 and p.y > -1.0 and not arena.inside(p, -0.45):
			var back := arena.clamp_point(p, 0.75)
			f.rig.shift(Vector3(back.x - p.x, 0.0, back.z - p.z))
			emit_event({"type": "escaped", "fighter": f.index, "pos": p})
			Log.w("sim", "fighter %d left the cage at (%.2f, %.2f, %.2f); pulled back" % [f.index, p.x, p.y, p.z])
			p = f.pos()
		# ring-out: fell off an open edge
		if p.y < -2.5 and not f.is_out():
			emit_event({"type": "ringout", "fighter": f.index})
			if mode:
				mode.on_ringout(f, _last_attacker(f))
			else:
				on_fighter_depleted(f, _last_attacker(f), {"ringout": true})
		# cage slam: a knocked-down / thrown body stopping hard against the fence
		var spd := f.rig.root().linear_velocity.length()
		var prev := float(_prev_speed.get(f.index, 0.0))
		_prev_speed[f.index] = spd
		if f.state == Fighter.State.KNOCKDOWN and prev > Tuning.v("slam_min_speed") and prev - spd > 3.0:
			if not arena.inside(p, 0.9):
				var dmg := minf(Tuning.v("slam_damage_max"), (prev - Tuning.v("slam_min_speed")) * Tuning.v("slam_damage_per_ms") + 4.0)
				combat.apply_simple_damage(_last_attacker(f), f, dmg, "slam")
				emit_event({"type": "slam", "fighter": f.index, "speed": prev, "pos": p})


func _last_attacker(f: Fighter) -> Fighter:
	var li := f.last_attacker_index
	if li >= 0 and li < fighters.size() and li != f.index and not fighters[li].despawned:
		return fighters[li]
	for k in range(events.size() - 1, -1, -1):
		var ev: Dictionary = events[k]
		if ev["type"] == "hit" and int(ev.get("target", -1)) == f.index and int(ev.get("fighter", -1)) >= 0:
			var a := int(ev["fighter"])
			if a < fighters.size() and not fighters[a].despawned:
				return fighters[a]
	return null


func last_attacker_of(f: Fighter) -> Fighter:
	return _last_attacker(f)


func on_fighter_depleted(f: Fighter, attacker: Fighter, hit: Dictionary) -> void:
	if f.is_out():
		return
	mode.on_depleted(f, attacker, hit)


## A spawn point away from enemies (respawns).
func safe_spawn_for(f: Fighter, avoid: Vector3 = Vector3.INF, min_dist := 0.0) -> Array:
	var best: Array = arena.spawn_point(f.index % maxi(1, arena.spawns.size()), fighters.size())
	var best_d := -1.0
	var n := maxi(arena.spawns.size(), 8)
	for i in n:
		var sp := arena.spawn_point(i, n)
		var dmin := INF
		for o in fighters:
			if o != f and not o.is_out() and not o.despawned and are_enemies(f, o):
				dmin = minf(dmin, o.pos().distance_to(sp[0]))
		if avoid != Vector3.INF:
			var da := Vector2(sp[0].x - avoid.x, sp[0].z - avoid.z).length()
			if da < min_dist:
				dmin = minf(dmin, da - 100.0)
			else:
				dmin = minf(dmin, da)
		if dmin > best_d:
			best_d = dmin
			best = sp
	return best


## Puts every fighter back at its spawn with full vitals (between rounds).
func reset_round() -> void:
	effects.entities = effects.entities.filter(func(e): return e["e"].has("hazard"))
	var alive := active_fighters()
	for i in fighters.size():
		var f := fighters[i]
		if f.despawned:
			continue
		var sp := arena.spawn_point(i, alive.size())
		f.respawn(sp[0], sp[1])
		f.lives = mode.initial_lives() if mode else int(rules.get("lives", 1))
		f.invuln_until = -1.0
	if mode:
		mode.on_round_reset()
	emit_event({"type": "round_reset"})


func finish(res: Dictionary) -> void:
	if is_finished:
		return
	is_finished = true
	result = res
	finished.emit(res)


## Lightweight per-fighter snapshot for HUDs, bots and replays.
func fighter_view(f: Fighter) -> Dictionary:
	return {"index": f.index, "team": f.team, "name": f.display_name, "creature": f.creature.id,
		"health": f.health, "max_health": f.max_health, "stamina": f.stamina, "max_stamina": f.max_stamina,
		"poise": f.poise, "max_poise": f.max_poise, "hype": f.hype, "state": f.state_name(),
		"juiced": f.time < f.juiced_until, "lives": f.lives, "statuses": f.statuses.summary(),
		"cooldowns": {"ability1": f.cooldown_frac("ability1"), "ability2": f.cooldown_frac("ability2")}}
