extends TestCase
## v0.9.18 Movesets engine (docs/design/MOVESET_COMBAT.md §2-3): move pools and loadouts, the move
## inputs, sustained and charged moves, repeating effects, recoil, attribution, tick throttles and
## denied presses, on a test kit built over Stoke's body and Classic moves.

const STREAM_DRAIN := 12.0


## Stoke's content entry with a small test pool: a basic string, the Classic heavy, an inline
## stream (sustained, aimed, repeating cone), an inline charged blast with recoil, Steam Vent.
static func kit(extra := {}) -> CreatureDef:
	var d: Dictionary = Content.creature_entry("f_stoke").duplicate(true)
	d["id"] = "t_stoke_moves"
	d["movepool"] = {
		"jab": {"name": "Test Jab", "category": "strike", "role": "basic", "string": ["l1", "l2", "l3", "finisher"], "dash": "dash_attack"},
		"haymaker": {"name": "Test Haymaker", "category": "blast", "role": "heavy", "use": "heavy", "charged": "heavy_charged", "hold": "charge"},
		"stream": {"name": "Test Stream", "category": "stream", "role": "special", "hold": "sustain", "max_hold": 2.0,
			"drain": STREAM_DRAIN, "aim": {"turn_rate": 2.0}, "cooldown": 5.0, "cost": 4.0,
			"move": {"duration": 0.9, "sustain": [0.3, 0.5], "move_mult": 0.1, "stamina": 4.0, "element": "scorch",
				"effects": [{"t": 0.3, "type": "area", "shape": "cone", "cone_deg": 50, "radius": 3.0, "damage": 1.5,
					"stun": 0.15, "poise": 2.0, "buildup": 5, "element": "scorch", "every": 0.12, "until": "release"}]}},
		"blast": {"name": "Test Blast", "category": "blast", "role": "heavy", "hold": "charge", "cooldown": 6.0,
			"move": {"duration": 1.1, "charge_time": 1.0, "charge_at": 0.2, "stamina": 10.0, "element": "brine",
				"effects": [{"t": 0.45, "type": "area", "shape": "line", "length": 5.0, "width": 0.6, "radius": 1.0, "damage": 8.0,
					"knockback": 4.0, "element": "brine", "charge_scale": {"damage": 2.0, "length": 1.4, "knockback": 2.0}},
					{"t": 0.45, "type": "recoil", "speed": 3.0}]}},
		"vent": {"name": "Steam Vent", "category": "blast", "use": "ability1"},
	}
	d["loadouts"] = {"a": {"name": "Test A", "moves": ["jab", "stream", "blast", "vent"]}, "b": {"name": "Test B", "moves": ["jab", "haymaker"]}}
	d["default_loadout"] = "a"
	d.merge(extra, true)
	return CreatureDef.from_dict(d, Callable(), "test")


func _sim(style := "moves", loadout := [], gap := 2.4) -> MatchSim:
	var c := kit()
	check(c.is_valid(), "the test kit parses: %s" % str(c.errors))
	var arena := ArenaDef.from_dict({"id": "t", "base": "octagon", "radius": 6.0, "spawns": [[0, -gap * 0.5, 0], [0, gap * 0.5, 180]]})
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	sim.setup({"arena": arena, "rules": {"rounds": 1, "round_time": 0, "intro_time": 0.2, "combat": style}, "seed": 5,
		"fighters": [{"creature": c, "team": 0, "source": null, "loadout": loadout},
			{"creature": Content.creature("f_dredge"), "team": 1, "source": null}]})
	return sim


func _events(sim: MatchSim, type: String, fi := 0) -> Array:
	return sim.events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == type and int(e.get("fighter", -1)) == fi)


func _release_all(f: Fighter) -> void:
	for b in FighterInput.BUTTON_COUNT:
		f.input.set_held(b, false)


func test_pools_and_loadouts_validate() -> void:
	var c := kit()
	check(c.is_valid(), "valid: %s" % str(c.errors))
	check_eq(c.resolve_loadout([]), ["jab", "stream", "blast", "vent"], "the default loadout")
	check_eq(c.resolve_loadout(["jab", "haymaker"]), ["jab", "haymaker"], "a valid custom loadout")
	check(c.loadout_problem(["stream", "blast"]) != "", "a loadout without a basic move is refused")
	check(c.loadout_problem(["jab", "jab"]) != "", "a move equipped twice is refused")
	check(c.loadout_problem(["jab", "nope"]) != "", "an unknown move is refused")
	check(c.loadout_problem(["jab", "stream", "blast", "vent", "haymaker"]) != "", "five moves are refused")
	check_eq(c.resolve_loadout(["stream"]), ["jab", "stream", "blast", "vent"], "an invalid wish falls back to the default")
	var vent: PoolMove = c.pool["vent"]
	check(is_equal_approx(vent.cooldown, float(c.cooldowns["ability1"])), "a pool move built on an ability keeps its cooldown")
	check(vent.answers_slot("ability1") and not vent.answers_slot("ability2"), "it answers its own slot")
	var blast: PoolMove = c.pool["blast"]
	check(blast.answers_slot("heavy") and not blast.answers_slot("ability1"), "a heavy-role move answers 'heavy' upgrades")
	check_eq(blast.move.move_class, "heavy", "and hits as a heavy")
	# creatures without a pool get their Classic kit as four moves
	var npc := Content.creature("npc_scrapling")
	check(not npc.pool.is_empty() and npc.loadout_problem(npc.resolve_loadout([])) == "", "a pool derived from the Classic kit")
	var bad: Dictionary = Content.creature_entry("f_stoke").duplicate(true)
	bad["id"] = "t_bad"
	bad["movepool"] = {"x": {"category": "laser", "move": {"duration": 0.5, "effects": [{"t": 0.1, "type": "teleport_everyone"}]}}}
	var bc := CreatureDef.from_dict(bad, Callable(), "test")
	check(bc.errors.size() >= 2, "unknown categories and effect types are reported: %s" % str(bc.errors))


func test_move_inputs_follow_the_style() -> void:
	var sim := _sim("moves")
	await step_sim(sim, 0.4)
	var a := sim.fighters[0]
	check_eq(a.combat_style, "moves", "Movesets from the rule")
	check_eq(a.loadout, ["jab", "stream", "blast", "vent"], "the default loadout equipped")
	a.input.press(FighterInput.HEAVY)
	await step_sim(sim, 0.05)
	check_eq(a.move_pool_id, "stream", "Move 2 (the Heavy input) starts the move in slot 2")
	_release_all(a)
	await step_sim(sim, 1.5)
	var c := _sim("classic")
	await step_sim(c, 0.4)
	var ca := c.fighters[0]
	check_eq(ca.combat_style, "classic", "Classic from the rule")
	ca.input.press(FighterInput.HEAVY)
	await step_sim(c, 0.05)
	check(ca.move_slot.begins_with("heavy") and ca.move_pool_id == "", "Classic Heavy is the heavy (%s)" % ca.move_slot)
	# the basic string walks its steps, the last one is the finisher
	var s := _sim("moves")
	await step_sim(s, 0.4)
	var sa := s.fighters[0]
	var slots: Array = []
	for k in 4:
		sa.input.press(FighterInput.LIGHT)
		await step_sim(s, 0.03)
		slots.append(sa.move_slot)
		_release_all(sa)
		var guard := 0
		while sa.move != null and sa.state_time < sa.move.cancel_t0 + 0.02 and guard < 200:
			await step_sim(s, 1.0 / 120.0)
			guard += 1
		if sa.move != null and sa.move.windows.size() > 0:
			while sa.move != null and sa.state_time < sa.move.last_active() + 0.01 and guard < 300:
				await step_sim(s, 1.0 / 120.0)
				guard += 1
	check_eq(slots, ["l1", "l2", "l3", "finisher"], "press after press walks the string into its finisher")


func test_sustained_stream_repeats_drains_and_ends_on_release() -> void:
	var sim := _sim()
	await step_sim(sim, 0.4)
	var a := sim.fighters[0]
	var st0 := a.stamina
	a.input.press(FighterInput.HEAVY)
	await step_sim(sim, 1.2)
	check(a.move_pool_id == "stream" and a.sustaining, "still flaming while held, past the move's 0.9 s length")
	var fx := _events(sim, "effect").filter(func(e: Dictionary) -> bool: return str(e.get("pool", "")) == "stream")
	check(fx.size() >= 6, "the cone repeats every 0.12 s while held (%d)" % fx.size())
	check(fx.all(func(e: Dictionary) -> bool: return bool(e.get("repeat", false))), "repeating fire is tick fire")
	check(a.stamina < st0 - 4.0 - STREAM_DRAIN * 0.6, "it drains stamina while held (%.1f -> %.1f)" % [st0, a.stamina])
	a.input.set_held(FighterInput.HEAVY, false)
	var n := fx.size()
	await step_sim(sim, 0.6)
	var after := _events(sim, "effect").filter(func(e: Dictionary) -> bool: return str(e.get("pool", "")) == "stream").size()
	check(after <= n + 1, "release stops the stream (%d -> %d)" % [n, after])
	check(a.move == null, "and plays out its recovery")
	var sus := _events(sim, "sustain")
	check(sus.size() >= 2 and str(sus[0]["phase"]) == "start" and str(sus[-1]["phase"]) == "end", "sustain start/end events for views and commentary")
	# the target took throttled ticks
	var hits := sim.events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == "hit" and int(e["fighter"]) == 0 and str(e.get("pool", "")) == "stream")
	check(not hits.is_empty(), "stream ticks hit the opponent in front")
	check(hits.all(func(e: Dictionary) -> bool: return bool(e.get("repeat", false)) and str(e.get("cat", "")) == "stream"), "attributed ticks")
	check(a.hype < 15.0, "a stream's ticks build little hype (%.1f)" % a.hype)
	check(sim.fighters[1].state != Fighter.State.HITSTUN or sim.fighters[1].stun_left <= 0.3, "no stun-lock")


func test_charged_blast_scales_and_recoils() -> void:
	var sim := _sim()
	await step_sim(sim, 0.4)
	var a := sim.fighters[0]
	var z0 := a.pos().z
	a.input.press(FighterInput.AB1)
	await step_sim(sim, 1.2)              # full charge
	check(a.move_charge > 0.95 and a.move_pool_id == "blast", "holding charges the blast (%.2f)" % a.move_charge)
	a.input.set_held(FighterInput.AB1, false)
	await step_sim(sim, 0.6)
	var fx := _events(sim, "effect").filter(func(e: Dictionary) -> bool: return str(e.get("pool", "")) == "blast" and str(e["effect"]) == "area")
	check(not fx.is_empty() and float(fx[0].get("length", 0.0)) > 6.5, "full charge lengthens the beam (%s)" % str(fx))
	check(a.pos().z < z0 - 0.15, "recoil pushes the shooter back (%.2f -> %.2f)" % [z0, a.pos().z])
	check(float(a.cooldown_left.get("m3", 0.0)) > 0.0, "and starts its cooldown")


func test_denied_presses_are_reported() -> void:
	var sim := _sim()
	await step_sim(sim, 0.4)
	var a := sim.fighters[0]
	a.stamina = 0.0
	a.input.press(FighterInput.AB1)
	await step_sim(sim, 0.05)
	_release_all(a)
	var den := _events(sim, "move_denied")
	check(not den.is_empty() and str(den[0]["why"]) == "stamina", "no stamina: a denied press, not silence (%s)" % str(den))
	check(a.move == null, "nothing started")
	a.input.press(FighterInput.LIGHT)
	await step_sim(sim, 0.05)
	check_eq(a.move_pool_id, "jab", "a basic strike still starts with no stamina")
	_release_all(a)
	await step_sim(sim, 1.0)
	a.stamina = a.max_stamina
	a.charges_left["m3"] = 0
	a.cooldown_left["m3"] = 4.0
	a.input.press(FighterInput.AB1)
	await step_sim(sim, 0.05)
	var den2 := _events(sim, "move_denied").filter(func(e: Dictionary) -> bool: return str(e["why"]) == "cooldown")
	check(not den2.is_empty(), "on cooldown: a denied press")


func test_hooks_translate_classic_slots() -> void:
	var sim := _sim()
	await step_sim(sim, 0.4)
	var a := sim.fighters[0]
	a.hooks.add({"on": "move_start", "if": {"slot": "heavy"}, "do": [{"type": "set_flag", "flag": "heavy_hook", "seconds": 5.0}]}, "test")
	a.hooks.add({"on": "move_start", "if": {"slot": "ability1"}, "do": [{"type": "set_flag", "flag": "vent_hook", "seconds": 5.0}]}, "test")
	# mods can name a pool move or a category
	a.hooks.add({"on": "move_start", "if": {"move": "blast"}, "do": [{"type": "set_flag", "flag": "blast_id_hook", "seconds": 5.0}]}, "test")
	a.hooks.add({"on": "move_start", "if": {"move_category": "stream"}, "do": [{"type": "set_flag", "flag": "stream_cat_hook", "seconds": 5.0}]}, "test")
	a.input.press(FighterInput.AB1)        # the blast: role heavy
	await step_sim(sim, 0.05)
	check(a.has_flag("heavy_hook") and not a.has_flag("vent_hook"), "a 'heavy' hook reaches a heavy-role move only")
	check(a.has_flag("blast_id_hook") and not a.has_flag("stream_cat_hook"), "a 'move' condition names the pool move; another category does not fire")
	_release_all(a)
	await step_sim(sim, 1.6)
	a.input.press(FighterInput.AB2)        # Steam Vent, built on ability1
	await step_sim(sim, 0.05)
	check(a.has_flag("vent_hook"), "an 'ability1' hook reaches the move built on ability1")
	# a cooldown action naming ability1 acts on the loadout slot holding it
	a.hooks.run_inline({"do": [{"type": "cooldown", "slot": "ability1", "set": 0.0}]}, {})
	check(int(a.charges_left.get("m4", 0)) == 1, "cooldown hooks resolve Classic slots to loadout slots")


func test_single_blows_are_not_repeats() -> void:
	# a regression: the repeat flag once shared the event's "tick" key, which emit_event fills with the
	# simulation tick, so every hit read as a stream tick (no hit pause, judges crediting once a second)
	var sim := _sim("moves", [], 1.1)
	await step_sim(sim, 0.4)
	var a := sim.fighters[0]
	a.input.press(FighterInput.LIGHT)     # the jab (the basic string)
	await step_sim(sim, 0.7)
	var hits := _events(sim, "hit")
	check(not hits.is_empty(), "the jab lands")
	check(hits.all(func(e: Dictionary) -> bool: return not bool(e.get("repeat", false)) and typeof(e.get("tick")) == TYPE_INT),
		"a single blow is not a repeat, and its tick is the simulation tick")
