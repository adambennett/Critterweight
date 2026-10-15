extends TestCase
## CNT-05 / ARENAS.md §2-3: arena hazards are authoritative and deterministic per seed; props
## break into their element zones; Rooftop ring-outs cost 8% HP and respawn at the nearest edge
## marker with invulnerability; team matches start in the team clusters; pickups and drains work.

const DT := 1.0 / 120.0


func _sim(arena, seed_value := 7, rules := {"rounds": 1, "round_time": 0}, n := 2, teams: Array = []) -> MatchSim:
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var a: ArenaDef = arena if arena is ArenaDef else Content.arena(str(arena))
	var fs := []
	for i in n:
		fs.append({"creature": Content.creature("dev_biped"), "team": teams[i] if i < teams.size() else i})
	sim.setup({"arena": a, "rules": rules, "seed": seed_value, "fighters": fs})
	return sim


func _hz(sim: MatchSim) -> ArenaHazards:
	return sim.arena_nodes["hazards"]


func _fight(sim: MatchSim) -> void:
	sim.mode.phase = MatchMode.Phase.FIGHT
	sim.input_enabled = true


func _steps(sim: MatchSim, n: int) -> void:
	for i in n:
		sim.step(DT)


func _layout(props: Array, markers := {}, base := "gullet") -> ArenaDef:
	var d := {"id": "test_layout", "name": "Test", "base": base, "format": 2, "props": props,
		"markers": markers if not markers.is_empty() else {"spawn": [{"pos": [0, 0, -3], "yaw": 0}, {"pos": [0, 0, 3], "yaw": 180}]}}
	return ArenaDef.from_dict(d)


func _zone_of(sim: MatchSim, kind: String) -> bool:
	for e in sim.effects.entities:
		if str(e["kind"]) == "zone" and str(e.get("zone_kind", "")) == kind:
			return true
	return false


func _has_event(sim: MatchSim, type: String) -> bool:
	for ev in sim.events:
		if str(ev["type"]) == type:
			return true
	return false


func test_hazards_cycle_deterministically_for_a_seed() -> void:
	var a := _hz(_sim("arena_crusher", 7))
	var b := _hz(_sim("arena_crusher", 7))
	var c := _hz(_sim("arena_crusher", 8))
	for h in [a, b, c]:
		h.debug_advance(200.0)
	check(a.history["plates"].size() >= 19, "a plate every 10 s (%d)" % a.history["plates"].size())
	check_eq(a.history["plates"], b.history["plates"], "same seed -> same plate order")
	check_eq(a.history["magnet"], b.history["magnet"], "same seed -> same magnet plates")
	check(a.history["plates"] != c.history["plates"] or a.history["magnet"] != c.history["magnet"], "another seed changes the pattern")
	check_eq(a.history["magnet"].size(), 8, "magnet every 25 s")
	var seq: Array = a.history["plates"]
	for k in range(1, seq.size()):
		var p := int(seq[k - 1])
		var q := int(seq[k])
		check(p != q, "never the same plate twice")
		var adj := absi(p % 3 - q % 3) + absi(int(p / 3.0) - int(q / 3.0)) == 1
		check(not adj, "never two adjacent plates in a row (%d -> %d)" % [p, q])
	var r1 := _hz(_sim("arena_rooftop", 11))
	var r2 := _hz(_sim("arena_rooftop", 11))
	r1.debug_advance(100.0)
	r2.debug_advance(100.0)
	check_eq(r1.history["wind"].size(), 5, "gust every 18 s")
	check_eq(r1.history["wind"], r2.history["wind"], "wind directions repeat for the seed")
	for d in r1.history["wind"]:
		check(absf((d as Vector2).length() - 1.0) < 0.001 and ((d as Vector2).x == 0.0 or (d as Vector2).y == 0.0), "cardinal gusts")
	var d1 := _hz(_sim("arena_drydock", 3))
	d1.debug_advance(65.0)
	check_eq(d1.history["gutter"].size(), 3, "gutter floods at 20/40/60 s")
	check_near(float(d1.history["gutter"][0]), 20.0, 0.02, "first flood at 20 s")
	check_eq(d1.history["crane"].size(), 2, "crane every 30 s")


func test_tidal_gutter_soaks_fighters_in_it() -> void:
	var sim := _sim("arena_drydock")
	_fight(sim)
	var f := sim.fighters[0]
	var g := sim.fighters[1]
	f.rig.place(Vector3(-5.0, 0, 0.1), 0.0)   # in the gutter
	g.rig.place(Vector3(-5.0, 0, 3.0), 0.0)   # on the dry side
	var hz := _hz(sim)
	hz.clock = 19.9
	_steps(sim, 160)
	check(float(f.statuses.buildup.get("brine", 0.0)) > 10.0 or f.statuses.has_element("brine"), "flooded gutter adds Brine build-up")
	check(float(g.statuses.buildup.get("brine", 0.0)) == 0.0, "dry floor stays dry")
	check(_has_event(sim, "arena_hazard"), "flood announced as an arena_hazard event")
	check(_zone_of(sim, "brine_puddle"), "gutter registers Brine zones for reactions")


func test_crane_hook_lifts_then_drops() -> void:
	var sim := _sim("arena_drydock")
	_fight(sim)
	var f := sim.fighters[0]
	sim.fighters[1].rig.place(Vector3(-6.0, 0, -3.0), 0.0)
	f.rig.place(Vector3(0.0, 0, 2.3), 0.0)   # on the marked crane circle
	await step_sim(sim, 0.4)
	var hz := _hz(sim)
	hz.clock = 28.3
	var hp := f.health
	var top := 0.0
	for i in 480:
		sim.step(DT)
		await get_tree().physics_frame
		top = maxf(top, f.pos().y)
		if str(hz.hazards[1]["phase"]) == "idle" and hz.history["crane"].size() > 0 and i > 300:
			break
	check(top > f.rig.def.hover_height + 1.4, "hooked fighter is lifted ~2 m (peak %.2f)" % top)
	check(f.health <= hp - 7.0, "dropped for 8 dmg (%.1f -> %.1f)" % [hp, f.health])
	check(f.is_down(), "and knocked down")
	check(_has_event(sim, "arena_hooked") and _has_event(sim, "arena_dropped"), "hook events")


func test_crane_magnet_pulls_and_drops_a_scrap_bundle() -> void:
	var sim := _sim("arena_crusher")
	_fight(sim)
	var hz := _hz(sim)
	hz.clock = 23.4
	_steps(sim, 14)   # telegraph starts at 23.5 and picks the plate
	var mag: Dictionary = hz.hazards[1]
	check_eq(str(mag["phase"]), "telegraph", "1.5 s magnet telegraph")
	var c: Vector2 = mag["data"]["pos"]
	var f := sim.fighters[0]
	var start := Vector3(c.x + 1.8, 0, c.y + 1.8)
	f.rig.place(start, 0.0)
	var other := sim.fighters[1]
	other.rig.place(Vector3(-c.x * 0.2 + (5.0 if c.x < 0 else -5.0), 0, -c.y * 0.2 + (5.0 if c.y < 0 else -5.0)), 0.0)
	var d0 := Vector2(f.pos().x - c.x, f.pos().z - c.y).length()
	_steps(sim, 380)   # rest of the telegraph (to 25 s), the 1.5 s pull, then the drop at 26.5 s
	check(hz.history["magnet"].size() == 1, "one magnet cycle")
	var spawned := 0
	for rec in hz.props:
		if bool(rec["spawned"]):
			spawned += 1
	check_eq(spawned, 1, "a scrap bundle is dropped on the plate")
	check(_has_event(sim, "arena_drop"), "drop event")
	check(f.health < f.max_health, "standing at the centre gets crushed")
	check(d0 > 2.0, "started %.1f m out" % d0)


func test_electrified_plate_zaps_and_mats_insulate() -> void:
	var sim := _sim("arena_crusher")
	_fight(sim)
	var hz := _hz(sim)
	hz.clock = 8.95
	_steps(sim, 12)   # -> telegraph at 9 s picks the plate
	var plates: Dictionary = hz.hazards[0]
	check_eq(str(plates["phase"]), "telegraph", "1 s telegraph before the plate goes live")
	var cell: Rect2 = sim.arena.grid_cells(plates["def"])[int(plates["data"]["cell"])]
	var f := sim.fighters[0]
	f.rig.place(Vector3(cell.get_center().x + 1.3, 0, cell.get_center().y - 1.3), 0.0)
	var hp := f.health
	_steps(sim, 125)
	check_eq(str(plates["phase"]), "active", "plate live")
	check(f.health < hp - 4.0, "8 dmg on entry (%.1f -> %.1f)" % [hp, f.health])
	check(float(f.statuses.buildup.get("static", 0.0)) >= 30.0 or f.statuses.has_element("static"), "Static build-up from the plate")
	# rubber mats insulate: a fighter on the centre mat inside a live rect is never zapped
	var g := sim.fighters[1]
	g.rig.place(Vector3(0.2, 0, -0.2), 0.0)
	var hp2 := g.health
	var data := {"inside": {}, "acc": {}}
	hz._electrify(Rect2(-2, -2, 4, 4), plates["def"], data, DT, true)
	check_eq(g.health, hp2, "mat is insulated")
	check(not data["inside"].has(g.index), "fighter on a mat never counts as on the plate")


func test_destructible_props_break_into_their_zones() -> void:
	var a := _layout([
		{"type": "prop_fire_barrel", "pos": [-3, 0, 0]}, {"type": "prop_sludge_drum", "pos": [3, 0, 0]},
		{"type": "prop_brine_barrel", "pos": [0, 0, 3.5]}, {"type": "prop_battery", "pos": [0, 0, -3.5]},
		{"type": "prop_gravel_sack", "pos": [3.5, 0, 3.5]}, {"type": "prop_crate", "pos": [-3.5, 0, -3.5]}])
	var sim := _sim(a)
	_fight(sim)
	var f := sim.fighters[0]
	f.rig.place(Vector3(-3.0, 0, 1.0), 0.0)    # next to the fire barrel
	sim.fighters[1].rig.place(Vector3(4.6, 0, -4.0), 0.0)
	var hp := f.health
	var hz := _hz(sim)
	var expect := {"prop_fire_barrel": "scorch_patch", "prop_sludge_drum": "sludge_puddle", "prop_brine_barrel": "brine_puddle",
		"prop_battery": "static_field", "prop_gravel_sack": "grit_rubble"}
	for rec in hz.props:
		var p: Vector3 = rec["pos"]
		if (rec["proxies"] as Array).is_empty():
			hz.damage_prop(int(rec["i"]), 500.0)          # low props: no blocking proxies
		else:
			sim.effects.hit_props(p + Vector3.UP * 0.4, 0.6, 500.0)   # the Combat -> effects path
	_steps(sim, 2)
	for rec in hz.props:
		check(bool(rec["destroyed"]), "%s destroyed" % rec["type"])
		if rec["body"] is Node3D:
			check((rec["body"] as Node3D).global_position.y < -50.0, "%s body parked" % rec["type"])
	for t in expect:
		check(_zone_of(sim, str(expect[t])), "%s leaves a %s" % [t, expect[t]])
	check(f.health < hp, "fire barrel burst burns the fighter beside it")
	var n := 0
	for ev in sim.events:
		if str(ev["type"]) == "arena_prop_destroyed":
			n += 1
	check_eq(n, 6, "one destroyed event per prop")
	# rounds restore the arena
	sim.reset_round()
	_steps(sim, 1)
	for rec in hz.props:
		check(not bool(rec["destroyed"]), "%s restored next round" % rec["type"])
		check_near(float(rec["hp"]), float(rec["hp_max"]), 0.01, "full HP again")


func test_weapons_damage_low_props_without_proxies() -> void:
	var sim := _sim(_layout([{"type": "prop_gravel_sack", "pos": [0, 0, 0]}]))
	_fight(sim)
	var hz := _hz(sim)
	var rec: Dictionary = hz.props[0]
	check((rec["proxies"] as Array).is_empty(), "a 0.6 m sack is not a wall-splat surface")
	var f := sim.fighters[0]
	var m: MoveDef = f.creature.moves["l1"]
	f.move = m
	f.move_slot = "l1"
	f.state = Fighter.State.ATTACK
	f.state_time = (float(m.windows[0]["t0"]) + float(m.windows[0]["t1"])) * 0.5
	var w: BodyDef.Weapon = f.creature.body.weapons.get(m.windows[0]["weapons"][0])
	var wp := f.rig.bodies[w.seg].global_transform * w.local
	(rec["body"] as Node3D).global_position = Vector3(wp.x, 0.3, wp.z)
	var hp := float(rec["hp"])
	hz._tick_props(DT, true)
	check_near(float(rec["hp"]), hp - m.damage * 0.5, 0.01, "half the move's damage per overlapping tick")


func test_props_take_damage_before_breaking() -> void:
	var sim := _sim(_layout([{"type": "prop_heavy_crate", "pos": [0, 0, 0]}]))
	_fight(sim)
	var hz := _hz(sim)
	var rec: Dictionary = hz.props[0]
	sim.effects.hit_props(Vector3(0, 0.5, 0), 0.6, 30.0)
	_steps(sim, 1)
	check(not bool(rec["destroyed"]), "80 HP crate survives 30 dmg")
	check_near(float(rec["hp"]), 50.0, 0.01, "HP tracked across proxies")
	sim.effects.hit_props(Vector3(0, 0.5, 0), 0.6, 60.0)
	_steps(sim, 1)
	check(bool(rec["destroyed"]), "breaks at 0 HP")


func test_rooftop_ringout_respawns_at_nearest_edge_marker() -> void:
	var sim := _sim("arena_rooftop")
	_fight(sim)
	var f := sim.fighters[0]
	var hp := f.max_health
	f.rig.place(Vector3(0.0, 0.0, 7.4), 0.0)   # just past the north edge
	var parked := false
	for i in 400:
		sim.step(DT)
		await get_tree().physics_frame
		if f.state == Fighter.State.INACTIVE:
			parked = true
			break
	check(parked, "falling off the roof parks the fighter (ring-out)")
	check_near(f.health, hp * 0.92, 0.6, "ring-out costs 8% max HP")
	check(not sim.is_finished and sim.mode.alive_teams().size() == 2, "a ringed-out fighter is still alive for the mode")
	await step_sim(sim, 2.7)
	check(f.state != Fighter.State.INACTIVE, "back after 2.5 s")
	var want: Vector3 = _hz(sim).respawn_point_near(Vector3(0, 0, 7.4))[0]
	check(Vector2(f.pos().x - want.x, f.pos().z - want.z).length() < 0.8, "respawned at the nearest edge marker %s (at %s)" % [want, f.pos()])
	check(f.invuln_until > f.time, "respawn invulnerability")
	check(_has_event(sim, "ringout") and _has_event(sim, "ringout_return"), "ring-out events")


func test_ringout_eliminates_rule() -> void:
	var sim := _sim("arena_rooftop", 7, {"rounds": 1, "round_time": 0, "ringout_eliminates": true})
	_fight(sim)
	var f := sim.fighters[0]
	f.rig.place(Vector3(0.0, 0.0, 7.4), 0.0)
	for i in 400:
		sim.step(DT)
		await get_tree().physics_frame
		if f.is_out():
			break
	check(f.state == Fighter.State.KO, "rules.ringout_eliminates knocks out instead")


## A mode that overrides on_ringout (like Absolute Unit's unit) decides; the arena only returns
## fighters the mode leaves standing.
class RingoutKoMode extends MatchMode:
	func on_ringout(f: Fighter, attacker: Fighter) -> void:
		f.health = 0.0
		on_depleted(f, attacker, {"ringout": true})


func test_mode_ringout_override_is_honoured() -> void:
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var fs := []
	for i in 2:
		fs.append({"creature": Content.creature("dev_biped"), "team": i})
	sim.setup({"arena": Content.arena("arena_rooftop"), "rules": {"rounds": 1, "round_time": 0}, "seed": 3, "fighters": fs, "mode": RingoutKoMode.new()})
	_fight(sim)
	var f := sim.fighters[0]
	f.rig.place(Vector3(0.0, 0.0, 7.4), 0.0)
	for i in 400:
		sim.step(DT)
		await get_tree().physics_frame
		if f.is_out():
			break
	check(f.state == Fighter.State.KO, "the mode's on_ringout override decides (KO)")
	check(_hz(sim).pending_ringouts.is_empty(), "no arena return queued for an eliminated fighter")


## The rules editor's Arena switches (RulesValidator: hazards, hazard_timer_mult, ringouts).
func test_rules_switch_hazards_timers_and_ringouts() -> void:
	var off := _sim("arena_crusher", 7, {"rounds": 1, "round_time": 0, "hazards": false})
	_fight(off)
	_steps(off, 1500)   # 12.5 s: the first plate event (10 s) would have fired
	check(not bool(_hz(off).view_state()["enabled"]), "hazards off")
	check(_hz(off).history["plates"].is_empty(), "no plate event with hazards off")
	var slow := _hz(_sim("arena_crusher", 7, {"rounds": 1, "round_time": 0, "hazard_timer_mult": 2.0}))
	check_near(float(slow.hazards[0]["next"]), 20.0, 0.01, "timer x2: first plate event at 20 s instead of 10 s")
	check_near(float(slow.hazards[0]["period"]), 20.0, 0.01, "and every 20 s")
	var rules := RulesValidator.normalize({})
	check(bool(rules.get("hazards", false)) and float(rules.get("hazard_timer_mult", 0.0)) == 1.0 and bool(rules.get("ringouts", false)),
		"the switches are real rules with defaults (rules editor rows)")
	var guarded := _sim("arena_rooftop", 7, {"rounds": 1, "round_time": 0, "ringouts": false})
	var open := _sim("arena_rooftop", 7, {"rounds": 1, "round_time": 0})
	check_eq((open.arena_nodes["walls"] as Array).size(), 0, "rooftop: no walls while ring-outs are on")
	check((guarded.arena_nodes["walls"] as Array).size() >= 8, "ring-outs off: guard walls on every open edge")


## A mode that runs its own arena hazards (campaign fights: CampaignMatchMode.hazards) takes
## over: the base's timed hazards stay off and their decals hide, so nothing fires twice.
class OwnHazardsMode extends MatchMode:
	var hazards = RefCounted.new()


func test_campaign_style_modes_own_the_hazards() -> void:
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var fs := []
	for i in 2:
		fs.append({"creature": Content.creature("dev_biped"), "team": i})
	sim.setup({"arena": Content.arena("arena_crusher"), "rules": {"rounds": 1, "round_time": 0}, "seed": 7, "fighters": fs, "mode": OwnHazardsMode.new()})
	_fight(sim)
	_steps(sim, 1500)
	check(not _hz(sim).hazards_live(), "base hazards yield to the mode's own")
	check(_hz(sim).history["plates"].is_empty() and _hz(sim).history["magnet"].is_empty(), "no base hazard fired")
	check(not bool(_hz(sim).view_state()["enabled"]), "the view hides the base hazard decals")


func test_team_matches_start_in_team_clusters() -> void:
	var sim := _sim("arena_drydock", 5, {"rounds": 1, "round_time": 0}, 4, [0, 0, 1, 1])
	var a := sim.arena
	for f in sim.fighters:
		var slot := 0 if f.team == 0 else 1
		var best := INF
		for me in a.team_spawns(slot):
			best = minf(best, Vector2(f.pos().x - me["pos"].x, f.pos().z - me["pos"].z).length())
		check(best < 0.3, "fighter %d starts in cluster %d" % [f.index, slot])
	var duel := _sim("arena_drydock", 5)
	check(duel.fighters[0].pos().distance_to(duel.fighters[1].pos()) > 5.0, "1v1 uses opposite ring spawns")


func test_pickups_heal_hype_and_respawn() -> void:
	var sim := _sim(_layout([{"type": "prop_chum_bucket", "pos": [2, 0, 0]}, {"type": "prop_hype_can", "pos": [-2, 0, 0]}]))
	_fight(sim)
	var f := sim.fighters[0]
	var g := sim.fighters[1]
	f.health = 50.0
	f.rig.place(Vector3(2, 0, 0), 0.0)
	g.rig.place(Vector3(-2, 0, 0), 0.0)
	g.hype = 10.0
	_steps(sim, 2)
	check_near(f.health, 65.0, 0.01, "chum bucket heals 15")
	check_near(g.hype, 35.0, 0.01, "JUICE can gives 25 hype")
	var hz := _hz(sim)
	check(not bool(hz.props[0]["available"]) and not bool(hz.props[1]["available"]), "both consumed")
	check_near(float(hz.props[0]["respawn_at"]) - sim.time, 30.0, 0.05, "bucket respawns in 30 s")
	check_near(float(hz.props[1]["respawn_at"]) - sim.time, 45.0, 0.05, "can respawns in 45 s")
	hz.props[0]["respawn_at"] = sim.time
	_steps(sim, 1)
	check(bool(hz.props[0]["available"]), "respawned")


func test_drain_pair_teleports_with_cooldown() -> void:
	var sim := _sim(_layout([{"type": "prop_drain_pair", "pos": [-3, 0, 0], "pos2": [3, 0, 0]}]))
	_fight(sim)
	var f := sim.fighters[0]
	sim.fighters[1].rig.place(Vector3(0, 0, 4.5), 0.0)
	f.rig.place(Vector3(-4.5, 0, 0), 0.0)
	_steps(sim, 1)
	f.rig.place(Vector3(-3, 0, 0), 0.0)
	_steps(sim, 2)
	check(f.has_flag("submerged"), "stepping on a drain submerges")
	_steps(sim, 70)
	check(Vector2(f.pos().x - 3.0, f.pos().z).length() < 0.6, "pops out of the other drain (at %s)" % f.pos())
	f.rig.place(Vector3(-3, 0, 0), 0.0)
	_steps(sim, 3)
	check(not f.has_flag("submerged"), "3 s cooldown")


func test_fan_and_wind_push_but_hover_ignores_wind() -> void:
	var sim := _sim(_layout([{"type": "prop_fan_unit", "pos": [-4, 0, 0], "yaw": 90}]))
	_fight(sim)
	var f := sim.fighters[0]
	f.rig.place(Vector3(-2.5, 0, 0), 0.0)
	sim.fighters[1].rig.place(Vector3(0, 0, 4.5), 0.0)
	var x0 := f.pos().x
	_steps(sim, 120)
	check_near(f.pos().x - x0, 1.5, 0.1, "fan pushes 1.5 m/s along its line")
	var roof := _sim("arena_rooftop")
	_fight(roof)
	var hz := _hz(roof)
	var a := roof.fighters[0]
	var b := roof.fighters[1]
	a.rig.place(Vector3(-2.5, 0, -2.0), 0.0)
	b.rig.place(Vector3(2.5, 0, 2.0), 0.0)
	b.start_hover(1.0, 5.0, 2.0)
	var pa := a.pos()
	var pb := b.pos()
	hz.clock = 16.4
	_steps(roof, 330)   # telegraph 16.5-18, gust 18-19
	var dir: Vector2 = hz.history["wind"][0]
	var moved := Vector2(a.pos().x - pa.x, a.pos().z - pa.z)
	check_near(moved.dot(dir), 1.5, 0.15, "gust pushes 1.5 m")
	check(Vector2(b.pos().x - pb.x, b.pos().z - pb.z).length() < 0.05, "hovering ignores the wind")
