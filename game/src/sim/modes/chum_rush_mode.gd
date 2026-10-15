class_name ChumRushMode
extends MatchMode
## CHUM RUSH (docs/design/MODES.md §2.4): 1–4 players (+ optional ally bots, team 0) survive
## seeded endless waves of minions (team 1) entering through wave gates. Wave n spawns 3+n
## enemies over 10 s (max 16 alive), headliners every 10 waves (bosses at 60% HP, phase 1),
## roster fighters from wave 21. 8 s breaks; every 5th break offers a pick of 3 supplements.
## Revives as in co-op; the run ends when every player is out.
## Score = kills×10 + wave clears×100 + headliner kills×500 − downs×50.

const ALIVE_CAP := 16
const ENEMY_TEAM := 1

var wave := 0
var stage := "break"             ## break | spawning | fighting
var stage_time := 0.0
var to_spawn: Array = []         ## creature ids still to spawn this wave
var spawn_interval := 1.0
var _spawn_t := 0.0
var gates: Array = []
var _gate_i := 0
var kills := 0
var clears := 0
var headliner_kills := 0
var downs := 0
var enemies: Array = []          ## Array[Fighter] alive this wave
var _despawn_at := {}            ## fighter index -> time
var pending_pick := {}           ## fighter index -> [upgrade ids] awaiting a choice
var upgrade_applier: Callable    ## (fighter, upgrade_id) -> void; campaign installs the real one
var player_count := 0


func id() -> String:
	return "chum_rush"


func setup(match_sim) -> void:
	var defaults := {"round_time": 0.0, "rounds": 1, "revive": true, "downed_time": 15.0, "respawn": false, "enemy_health_mult": 1.0,
		"start_wave": 1, "wave_size_mult": 1.0, "headliner_interval": 10, "picks": true, "last_call": false, "night_shift": false}
	for k in defaults:
		if not match_sim.rules.has(k):
			match_sim.rules[k] = defaults[k]
	if bool(match_sim.rules["last_call"]):
		match_sim.rules["round_time"] = 600.0
	super.setup(match_sim)
	for f: Fighter in sim.fighters:
		f.team = 0
		player_count += 1
	wave = int(rules["start_wave"]) - 1
	gates = sim.arena.marker_points("wave_gate").duplicate()
	if gates.size() < 2:
		gates.clear()
		var r := sim.arena.radius - 0.8
		for i in 4:
			var a := TAU * i / 4.0 + PI * 0.25
			gates.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
	stage = "break"
	stage_time = 0.0
	if not upgrade_applier.is_valid():
		upgrade_applier = _basic_apply


func tick_fight(dt: float) -> void:
	stage_time += dt
	for idx in _despawn_at.keys():
		if sim.time >= float(_despawn_at[idx]):
			_despawn_at.erase(idx)
			sim.despawn_fighter(sim.fighters[idx])
	match stage:
		"break":
			if stage_time >= 8.0 and pending_pick.is_empty():
				_start_wave()
		"spawning":
			_spawn_t += dt
			while not to_spawn.is_empty() and _spawn_t >= spawn_interval and _alive_enemies() < ALIVE_CAP:
				_spawn_t -= spawn_interval
				_spawn_one(to_spawn.pop_front())
			if to_spawn.is_empty():
				stage = "fighting"
		"fighting":
			if _alive_enemies() == 0:
				_wave_cleared()
	# players all out -> run over
	var standing := 0
	for f: Fighter in sim.fighters:
		if f.team == 0 and not is_beaten(f):
			standing += 1
	if standing == 0 and player_count > 0:
		end_round(ENEMY_TEAM)


func _alive_enemies() -> int:
	var n := 0
	# slots are reused, so earlier entries may already be freed: check before typing
	for e in enemies:
		if is_instance_valid(e) and not (e as Fighter).despawned and not (e as Fighter).is_out():
			n += 1
	return n


func _start_wave() -> void:
	wave += 1
	stage = "spawning"
	stage_time = 0.0
	_spawn_t = 0.0
	enemies = enemies.filter(func(e): return is_instance_valid(e) and not e.despawned and not e.is_out())
	to_spawn = _composition(wave)
	spawn_interval = 10.0 / maxf(1.0, to_spawn.size())
	# downed timers reset each wave
	for idx in _downed_at.keys():
		_downed_at[idx] = sim.time
	sim.emit_event({"type": "wave_start", "wave": wave, "count": to_spawn.size()})


## Seeded wave composition (MODES.md §2.4). Returns creature ids (+ "@hp:<frac>" for headliners).
func _composition(n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = sim.seed_value * 7919 + n
	var hl := int(rules["headliner_interval"])
	var loop := int(floor(float(n - 1) / 30.0))
	var k := ((n - 1) % 30) + 1
	var out := []
	if hl > 0 and k % hl == 0:
		var bosses := ["boss_bilge", "boss_conduit", "boss_snappington"]
		out.append("%s@hp:%.2f" % [bosses[mini(int(k / hl) - 1, 2)], 0.6 * (1.0 + 0.1 * loop)])
		for i in 2:
			out.append("npc_scrapling")
		return out
	var count := int(round((3 + n) * float(rules["wave_size_mult"])))
	for i in count:
		var pick := "npc_scrapling"
		if k >= 5 and rng.randf() < 0.3:
			pick = "npc_blister"
		elif k >= 5 and rng.randf() < 0.2:
			pick = "npc_scrapling#pelter"
		out.append(pick)
	if k >= 21:
		var roster := Content.playable_creatures().filter(func(c): return not str(c).begins_with("dev_"))
		if not roster.is_empty():
			out[0] = roster[rng.randi_range(0, roster.size() - 1)]
	return out


## Spawn specs: "<id>", "<id>@hp:<frac>" (headliners) and "<id>#<variant>" (minion variants):
## a variant resolves to the creature "<id>_<variant>" (e.g. npc_scrapling#pelter ->
## npc_scrapling_pelter, docs/kits/minions.md) and falls back to the base creature.
func _resolve(id_: String) -> CreatureDef:
	var spec := id_.split("@")[0]
	var base := spec.split("#")[0]
	var c: CreatureDef = null
	if spec.contains("#"):
		c = Content.creature(spec.replace("#", "_"))
	if c == null:
		c = Content.creature(base)
	if c == null:
		c = Content.creature("dev_biped")
	return c


func _spawn_one(spec: String) -> void:
	var c := _resolve(spec)
	if c == null:
		return
	var gate: Vector3 = gates[_gate_i % gates.size()]
	_gate_i += 1
	var yaw := atan2(-gate.x, -gate.z)
	var tier := "rookie" if wave < 8 else ("regular" if wave < 20 else "pro")
	var bot := BotBrain.new(tier, sim.seed_value * 31 + wave * 101 + _gate_i)
	bot.set_personality(c.ai)
	var entry := {"creature": c, "team": ENEMY_TEAM, "source": bot, "kind": "bot", "name": c.display_name, "spawn_invuln": 0.8}
	if bool(rules["night_shift"]) and c.element == "":
		entry["mods"] = {"all_moves_elemental": true}
	var f := sim.spawn_fighter(entry, sim.clamp_to_arena(gate, 0.7), yaw)
	if f == null:
		return
	f.lives = 0
	f.max_health *= float(rules["enemy_health_mult"])
	f.health = f.max_health
	if spec.contains("@hp:"):
		var frac := float(spec.split("@hp:")[1])
		f.max_health *= frac * 3.0
		f.health = f.max_health
		f.flags["headliner"] = true
		f.flags["boss"] = true
	enemies.append(f)
	sim.emit_event({"type": "gate_spawn", "fighter": f.index, "gate": gate})


func _wave_cleared() -> void:
	clears += 1
	stage = "break"
	stage_time = 0.0
	sim.emit_event({"type": "wave_cleared", "wave": wave})
	if bool(rules["picks"]) and wave % 5 == 0:
		_offer_picks()


func _offer_picks() -> void:
	var pool := Content.ids("supplements")
	if pool.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = sim.seed_value * 104729 + wave
	for f: Fighter in sim.fighters:
		if f.team != 0 or f.despawned:
			continue
		var choices := []
		for i in 3:
			choices.append(pool[rng.randi_range(0, pool.size() - 1)])
		pending_pick[f.index] = choices
		# local players choose in the pick panel, remote players ("net") through a mode.pick
		# request to the server (which also times out unanswered picks); others take the first
		if f.controller_kind != "player" and f.controller_kind != "net":
			choose_pick(f.index, 0)
	sim.emit_event({"type": "pick_offered", "wave": wave})


## Called by the UI (player) or automatically (bots) to take one of the offered upgrades.
func choose_pick(fighter_index: int, choice: int) -> void:
	if not pending_pick.has(fighter_index):
		return
	var opts: Array = pending_pick[fighter_index]
	pending_pick.erase(fighter_index)
	if choice >= 0 and choice < opts.size():
		upgrade_applier.call(sim.fighters[fighter_index], str(opts[choice]))
		sim.emit_event({"type": "pick_taken", "fighter": fighter_index, "upgrade": str(opts[choice])})


## Minimal applier until the campaign's build system is installed: stat mods + hooks.
func _basic_apply(f: Fighter, upgrade_id: String) -> void:
	var u := Content.get_entry("supplements", upgrade_id)
	for k in u.get("mods", {}):
		var v = u["mods"][k]
		if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
			if str(k).ends_with("_add"):
				f.mods[k] = float(f.mods.get(k, 0.0)) + float(v)
			else:
				f.mods[k] = float(f.mods.get(k, 1.0)) * float(v)
	for h in u.get("hooks", []):
		f.hooks.add(h, "supplement:" + upgrade_id)


func on_depleted(f: Fighter, attacker: Fighter, hit: Dictionary) -> void:
	if f.team == ENEMY_TEAM:
		f.knock_out(attacker)
		kills += 1
		if f.flags.get("headliner", false):
			headliner_kills += 1
		if attacker:
			attacker.stats_record["kos"] += 1
		_despawn_at[f.index] = sim.time + 2.5
		sim.emit_event({"type": "elimination", "fighter": f.index, "by": attacker.index if attacker else -1})
		return
	downs += 1
	super.on_depleted(f, attacker, hit)


func check_round_over() -> void:
	pass


func score() -> int:
	return kills * 10 + clears * 100 + headliner_kills * 500 - downs * 50


func on_timeout() -> void:
	end_round(0)


func build_result() -> Dictionary:
	var r := super.build_result()
	r["wave"] = wave
	r["score"] = score()
	r["kills"] = kills
	r["clears"] = clears
	r["headliner_kills"] = headliner_kills
	r["downs"] = downs
	return r


func hud_status() -> String:
	match stage:
		"break":
			if not pending_pick.is_empty():
				return "Wave %d cleared — pick a supplement!" % wave
			return "Break — wave %d in %ds" % [wave + 1, ceili(8.0 - stage_time)]
		"spawning":
			return "WAVE %d — they're coming through the gates" % wave
	return "WAVE %d — %d left" % [wave, _alive_enemies()]


func hud_state() -> Dictionary:
	return {"rows": [{"label": "Wave", "value": wave, "team": 0}, {"label": "Score", "value": score(), "team": 0}],
		"status": hud_status(), "picks": pending_pick.duplicate()}


func view_state() -> Dictionary:
	var v := super.view_state()
	v["gates"] = gates
	# where each gate meets the fence (the doorway is drawn there, not inside the cage)
	var walls := []
	for g: Vector3 in gates:
		var dir := Vector3(g.x, 0.0, g.z).normalized()
		walls.append(sim.arena.clamp_point(dir * sim.arena.radius * 3.0, 0.0) if dir != Vector3.ZERO else g)
	v["gate_walls"] = walls
	v["wave"] = wave
	v["stage"] = stage
	v["open_gate"] = (gates[(_gate_i - 1) % gates.size()] if _gate_i > 0 else Vector3.INF) if stage == "spawning" else Vector3.INF
	return v


func bot_objective(f: Fighter) -> Dictionary:
	return super.bot_objective(f) if f.team == 0 else {}
