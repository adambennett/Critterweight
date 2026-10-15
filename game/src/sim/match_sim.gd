class_name MatchSim
extends Node3D
## One authoritative match: arena physics, fighters, effect entities, rules/mode and the event
## stream. Runs identically offline, on a listen/dedicated server, and (many at once, in their
## own World3D) inside AI Lab training workers. It never touches rendering, input devices or UI.
##
## Tick order (every physics tick, 120 Hz):
##   1. input sources write each fighter's FighterInput
##   2. fighters advance their state machines, poses and muscles
##   3. Combat validates weapon contacts -> hits
##   4. effects (projectiles/zones/hazards) update
##   5. environment checks (ring-outs, wall slams)
##   6. the mode advances phases/scoring
## then Godot steps the physics world.

signal finished(result: Dictionary)

const MAX_EVENTS := 512

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
var _neutral_input := FighterInput.new()
var _prev_speed := {}            ## fighter index -> root speed last tick (slam detection)
var _fighter_root: Node3D


func _init() -> void:
	combat = Combat.new(self)
	effects = EffectsSystem.new(self)


## config: {arena: ArenaDef, rules: Dictionary, seed: int, mode: MatchMode (optional),
##          fighters: [{creature: CreatureDef, team: int, source: InputSource, name: String}]}
func setup(config: Dictionary) -> void:
	name = "MatchSim"
	arena = config["arena"]
	rules = config.get("rules", {}).duplicate(true)
	seed_value = int(config.get("seed", 1))
	rng.seed = seed_value
	arena_nodes = ArenaBuilder.build(self, arena)
	_fighter_root = Node3D.new()
	_fighter_root.name = "Fighters"
	add_child(_fighter_root)
	var entries: Array = config.get("fighters", [])
	for i in entries.size():
		var e: Dictionary = entries[i]
		var sp := arena.spawn_point(i, entries.size())
		var f := Fighter.new()
		_fighter_root.add_child(f)
		f.setup(e["creature"], i, int(e.get("team", i)), self, sp[0], sp[1])
		f.display_name = str(e.get("name", f.creature.display_name))
		f.controller_kind = str(e.get("kind", "bot"))
		for k in e.get("mods", {}):
			f.mods[k] = float(e["mods"][k])
		f.reset_vitals()
		_apply_rule_mods(f)
		fighters.append(f)
		input_sources.append(e.get("source"))
	ArenaBuilder.spawn_hazards(self, arena)
	mode = config.get("mode", null)
	if mode == null:
		mode = MatchMode.new()
	mode.setup(self)
	emit_event({"type": "match_start", "arena": arena.id, "mode": mode.id(), "seed": seed_value})


func _apply_rule_mods(f: Fighter) -> void:
	f.mods["damage"] = float(f.mods["damage"]) * float(rules.get("damage_mult", 1.0))
	f.mods["knockback_taken"] = float(f.mods["knockback_taken"]) * float(rules.get("knockback_mult", 1.0))
	f.mods["cooldown"] = float(f.mods["cooldown"]) * float(rules.get("cooldown_rate", 1.0))
	f.mods["hype_gain"] = float(f.mods["hype_gain"]) * float(rules.get("hype_mult", 1.0))
	f.mods["max_health"] = float(f.mods.get("max_health", 1.0)) * float(rules.get("health_mult", 1.0))
	f.reset_vitals()


func set_input_source(i: int, src) -> void:
	input_sources[i] = src


func are_enemies(a: Fighter, b: Fighter) -> bool:
	if a == b:
		return false
	return a.team != b.team


func can_hit(a: Fighter, b: Fighter) -> bool:
	if a == b:
		return false
	if a.team == b.team:
		return bool(rules.get("friendly_fire", false))
	return true


func clamp_to_arena(p: Vector3, margin: float) -> Vector3:
	return arena.clamp_point(p, margin) if arena else p


func emit_event(ev: Dictionary) -> void:
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


func step(dt: float) -> void:
	tick_count += 1
	time += dt
	for i in fighters.size():
		var f := fighters[i]
		var src = input_sources[i]
		if src != null and input_enabled and not is_finished:
			src.poll(f, self, dt)
		elif not input_enabled or is_finished:
			# keep press counters in sync so presses during intros are not replayed later
			if src != null:
				src.poll(f, self, dt)
			var held_counts := f.input.press_count
			f.input.move = Vector3.ZERO
			f.input.held = 0
			f.input.press_count = held_counts
			f._buffer.clear()
	for f in fighters:
		f.sim_tick(dt)
	combat.detect_hits()
	effects.update(dt)
	ArenaHazards.step(self, dt)   # arena hazards/props/ring-outs (src/sim/arena_hazards.gd)
	_environment_checks()
	if mode and not is_finished:
		mode.tick(dt)


func _environment_checks() -> void:
	for f in fighters:
		if f.state == Fighter.State.INACTIVE:
			continue
		var p := f.pos()
		# ring-out: fell off an open platform
		if arena.ringout and p.y < -2.5 and not f.is_out():
			emit_event({"type": "ringout", "fighter": f.index})
			on_fighter_depleted(f, _last_attacker(f), {"ringout": true})
		if p.y < -12.0 and not f.flags.get("void_reset", false):
			f.flags["void_reset"] = true
		# wall slam: a knocked-down / thrown body stopping hard next to the fence
		var spd := f.rig.root().linear_velocity.length()
		var prev := float(_prev_speed.get(f.index, 0.0))
		_prev_speed[f.index] = spd
		if f.state == Fighter.State.KNOCKDOWN and prev > Tuning.v("slam_min_speed") and prev - spd > 3.0:
			if not arena.inside(p, 0.9):
				var dmg := minf(Tuning.v("slam_damage_max"), (prev - Tuning.v("slam_min_speed")) * Tuning.v("slam_damage_per_ms") + 4.0)
				combat.apply_simple_damage(_last_attacker(f), f, dmg, "slam")
				emit_event({"type": "slam", "fighter": f.index, "speed": prev, "pos": p})


func _last_attacker(f: Fighter) -> Fighter:
	for k in range(events.size() - 1, -1, -1):
		var ev: Dictionary = events[k]
		if ev["type"] == "hit" and int(ev.get("target", -1)) == f.index and int(ev.get("fighter", -1)) >= 0:
			return fighters[int(ev["fighter"])]
	return null


func on_fighter_depleted(f: Fighter, attacker: Fighter, hit: Dictionary) -> void:
	if f.is_out():
		return
	mode.on_depleted(f, attacker, hit)


## A spawn point away from enemies (respawns).
func safe_spawn_for(f: Fighter) -> Array:
	var best: Array = arena.spawn_point(f.index, fighters.size())
	var best_d := -1.0
	var n := maxi(arena.spawns.size(), 8)
	for i in n:
		var sp := arena.spawn_point(i, n)
		var dmin := INF
		for o in fighters:
			if o != f and not o.is_out():
				dmin = minf(dmin, o.pos().distance_to(sp[0]))
		if dmin > best_d:
			best_d = dmin
			best = sp
	return best


## Puts every fighter back at its spawn with full vitals (between rounds).
func reset_round() -> void:
	effects.entities = effects.entities.filter(func(e): return e["e"].has("hazard"))
	for i in fighters.size():
		var f := fighters[i]
		var sp := arena.spawn_point(i, fighters.size())
		f.respawn(sp[0], sp[1])
		f.lives = int(rules.get("lives", 1))
		f.invuln_until = -1.0
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
