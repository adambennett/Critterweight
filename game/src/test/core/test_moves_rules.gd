extends MovesKitCase
## v0.9.18 Movesets across the rules (docs/design/MOVESET_COMBAT.md §1, §9): every built-in preset
## and playlist plays Movesets while Classic stays a real, validated rule; the judges credit a
## stream once per second of contact (not per tick) and count it as an attack thrown; the referee
## keeps every Movesets attack off a downed fighter; AI Lab policies (trained on Classic) give way
## to scripted bots in Movesets matches.

const CAGE := {"mode": "standard", "format": "duel", "teams": 2, "players": [2, 2], "rounds": 3, "round_time": 40.0,
	"intro_time": 0.3, "win": "ko", "lives": 1, "sudden_death": true, "scoring": "ten_point", "referee": true, "combat": "moves"}
const FURNACE := ["ember_jab", "flamethrower", "steam_vent", "stoke_the_fire"]


## Stoke (Furnace loadout: the Flamethrower on the second move button) against a standing Dredge,
## under Cage Rules (10-point judges and a referee).
func _cage(gap := 1.6) -> MatchSim:
	var arena := ArenaDef.from_dict({"id": "t", "base": "octagon", "radius": 7.0, "spawns": [[0, -gap * 0.5, 0], [0, gap * 0.5, 180]]})
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	sim.setup({"arena": arena, "rules": CAGE.duplicate(true), "seed": 11, "mode": ModeRegistry.create("standard"), "fighters": [
		{"creature": Content.creature("f_stoke"), "team": 0, "source": null, "loadout": FURNACE},
		{"creature": Content.creature("f_dredge"), "team": 1, "source": null}]})
	return sim


func _to_fight(sim: MatchSim) -> void:
	for i in 60:
		if sim.mode.phase == MatchMode.Phase.FIGHT:
			return
		await step_sim(sim, 0.05)
	check(sim.mode.phase == MatchMode.Phase.FIGHT, "the fight started")


func test_built_in_presets_and_playlists_default_to_movesets() -> void:
	for id in Content.ids("rules"):
		var r: Dictionary = Content.get_entry("rules", str(id))
		if r.is_empty():
			continue
		check_eq(str(r.get("combat", "")), "moves", "the built-in preset %s says Movesets" % id)
	for pid in Content.ids("playlists"):
		var pl: Dictionary = Content.get_entry("playlists", str(pid))
		for e in pl.get("entries", []):
			var rules = e.get("rules", "")
			if typeof(rules) == TYPE_STRING:
				var pr: Dictionary = Content.get_entry("rules", str(rules))
				check(not pr.is_empty() and str(pr.get("combat", "moves")) == "moves", "playlist %s entry %s plays Movesets" % [pid, rules])
			elif typeof(rules) == TYPE_DICTIONARY:
				check(str((rules as Dictionary).get("combat", "moves")) == "moves", "playlist %s inline rules play Movesets" % pid)
	# Classic is a real rule: validated, kept by normalization, applied by the simulation
	var classic: Dictionary = Content.get_entry("rules", "duel").duplicate(true)
	classic["combat"] = "classic"
	check(not RulesValidator.has_errors(RulesValidator.validate(classic)), "a Classic duel validates")
	check_eq(str(RulesValidator.normalize(classic).get("combat", "")), "classic", "normalization keeps Classic")
	var sim := make_sim("", {"rounds": 1, "round_time": 0, "intro_time": 0.2, "combat": "classic"}, [{"creature": "f_stoke", "team": 0}, {"creature": "f_dredge", "team": 1}])
	await step_sim(sim, 0.3)
	check_eq(sim.combat_style(), "classic", "the simulation plays Classic when the rules say so")
	check_eq(sim.fighters[0].combat_style, "classic", "and so do its fighters")
	var sim2 := make_sim("", {"rounds": 1, "round_time": 0, "intro_time": 0.2, "combat": "moves"}, [{"creature": "f_stoke", "team": 0}, {"creature": "f_dredge", "team": 1}])
	await step_sim(sim2, 0.3)
	check_eq(sim2.fighters[0].loadout, FURNACE, "Movesets fighters equip their recommended loadout")


func test_judges_credit_a_stream_per_second_of_contact() -> void:
	var sim := _cage()
	await _to_fight(sim)
	var t0: Dictionary = sim.mode.judge.live_tally()[0]
	await use_slot(sim, 0, 1, 2.2, 0.6)     # the Flamethrower, poured for 2.2 s
	var ticks := pool_events(sim, "hit", "flamethrower").filter(func(e: Dictionary) -> bool:
		return bool(e.get("repeat", false)) and not bool(e.get("blocked", false)) and int(e.get("target", -1)) == 1)
	check(ticks.size() >= 8, "the stream ticked on Dredge (%d hits)" % ticks.size())
	var t1: Dictionary = sim.mode.judge.live_tally()[0]
	var landed := int(t1["landed"]) - int(t0["landed"])
	check(landed >= 2 and landed <= 3, "the judges credit about one landed blow per second of contact (%d for %d ticks)" % [landed, ticks.size()])
	check(int(t1["thrown"]) - int(t0["thrown"]) == 1, "the stream is one attack thrown")
	check(float(t1["damage"]) > float(t0["damage"]), "its damage counts in full")


func test_referee_keeps_movesets_attacks_off_a_downed_fighter() -> void:
	var sim := _cage()
	await _to_fight(sim)
	var a := sim.fighters[0]
	var d := sim.fighters[1]
	d.knock_down("poise", a)
	await step_sim(sim, 0.1)
	check(d.is_down(), "Dredge is down")
	var hp := d.health
	var seq0 := sim.event_seq
	# pour the Flamethrower (ticks and the scorch patches it leaves) over the downed fighter
	var b: int = Fighter.MOVE_BUTTONS[1]
	a.input.press(b)
	await step_sim(sim, 1.3)
	a.input.set_held(b, false)
	await step_sim(sim, 0.4)
	check(d.is_down(), "still down on the count")
	var landed := sim.events.filter(func(e: Dictionary) -> bool:
		return int(e["seq"]) > seq0 and str(e["type"]) == "hit" and int(e.get("target", -1)) == 1)
	check(landed.is_empty(), "no Movesets hit lands on a downed fighter (%d did)" % landed.size())
	check(is_equal_approx(d.health, hp), "and no damage gets through (%.1f -> %.1f)" % [hp, d.health])
	check(pool_events(sim, "effect", "flamethrower").size() > 0 or pool_events(sim, "ability", "flamethrower").size() > 0, "the stream itself did pour")


func test_lab_policies_give_way_to_bots_in_movesets() -> void:
	var entry := {"creature": Content.creature("f_stoke"), "policy_id": "f_stoke_es_drill", "difficulty": "pro"}
	var classic := PolicyInputSource.for_match(entry, 3, 0, "classic")
	check(classic is PolicyInputSource, "a Classic match: the policy fights")
	var moves := PolicyInputSource.for_match(entry, 3, 0, "moves")
	check(moves is BotBrain, "a Movesets match: a scripted bot takes the policy's place")


func test_mode_buttons_come_before_moves() -> void:
	# Chumball under its built-in preset (Movesets): the carrier's move buttons throw the ball, as the
	# attack buttons did in Classic, and Grapple still picks it up
	var rules: Dictionary = Content.get_entry("rules", "chumball").duplicate(true)
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var entries := []
	for i in 4:
		entries.append({"creature": Content.creature("f_stoke"), "team": i % 2, "source": null, "kind": "bot"})
	sim.setup({"arena": Content.arena("the_gullet"), "rules": rules, "seed": 5, "fighters": entries, "mode": ModeRegistry.create("chumball")})
	await step_sim(sim, 1.0)
	var mode: ChumballMode = sim.mode
	var f := sim.fighters[0]
	check_eq(f.combat_style, "moves", "Chumball plays Movesets by default")
	mode.ball.linear_velocity = Vector3.ZERO
	mode.ball.global_position = f.pos() + f.forward() * 0.5 + Vector3.UP * 0.3
	check(mode.on_grab_pressed(f), "Grapple picks the ball up")
	var seq0 := sim.event_seq
	f.input.press(FighterInput.LIGHT)          # move 1 (Ember Jab) while carrying
	await step_sim(sim, 0.1)
	var thrown := sim.events.any(func(e: Dictionary) -> bool: return int(e["seq"]) > seq0 and str(e["type"]) == "ball_throw")
	var jabbed := sim.events.any(func(e: Dictionary) -> bool:
		return int(e["seq"]) > seq0 and str(e["type"]) == "move_start" and int(e.get("fighter", -1)) == 0)
	check(thrown and not jabbed, "the carrier's move button throws the ball instead of starting a move")
