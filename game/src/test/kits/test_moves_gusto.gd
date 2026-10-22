extends MovesKitCase
## Gusto's v0.9.18 move pool (docs/kits/f_gusto.md "Movesets", docs/design/MOVESET_COMBAT.md §4):
## every move does what its description says, in Movesets, against standing Dredges; every style's
## patch lands on the authored content and changes how its move plays; the effects kit draws and
## cleans up its moves headless.

const SKYHOOK := ["wing_snap", "air_slash", "feather_darts", "hang_time"]
const CYCLONE := ["wing_snap", "twister", "gust_bomb", "tailwind"]
const POOL := ["wing_snap", "crosswind_slash", "gust_bomb", "hang_time", "air_slash", "feather_darts", "twister", "tailwind"]
const KIT_VFX := ["gusto_air_slash", "gusto_feather_darts", "gusto_twister", "gusto_twister_eddy", "gusto_storm_eye",
	"gusto_tailwind", "gusto_tailwind_dart", "gusto_slipstream_eddy", "gusto_liftoff_gust"]


func test_pool_and_loadouts() -> void:
	var c := Content.creature("f_gusto")
	for id in POOL:
		check_pool_move("f_gusto", id)
	check_eq(c.pool.size(), 8, "eight moves in the pool")
	check_eq(c.resolve_loadout([]), SKYHOOK, "the default loadout is Skyhook")
	check_eq((c.loadouts["cyclone"] as Dictionary)["moves"], CYCLONE, "Cyclone is the second build")
	var shared := SKYHOOK.filter(func(x) -> bool: return CYCLONE.has(x))
	check_eq(shared, ["wing_snap"], "the two builds share only the basic strike")
	var cats := {}
	for id in POOL:
		cats[id] = (c.pool[id] as PoolMove).category
	check_eq(cats, {"wing_snap": "strike", "crosswind_slash": "strike", "gust_bomb": "projectile", "hang_time": "utility",
		"air_slash": "projectile", "feather_darts": "volley", "twister": "control", "tailwind": "support"}, "categories (§4)")
	var basic: PoolMove = c.pool["wing_snap"]
	check(basic.string == ["l1", "l2", "l3", "finisher"] and basic.dash == "dash_attack", "Wing Snap walks the v0.9.17 string into the Tailspin")
	check_eq((c.pool["crosswind_slash"] as PoolMove).hold, "charge", "Crosswind Slash charges into the Downdraft")
	for id in ["air_slash", "feather_darts", "twister", "tailwind"]:
		var pm: PoolMove = c.pool[id]
		check(pm.stamina_cost() > 0.0 and pm.cooldown >= 4.0 and pm.cooldown <= 12.0, "%s costs stamina and has a real cooldown (%.0f s)" % [id, pm.cooldown])
	# every style's patch lands on the authored content, changes it, and leaves a valid fighter
	var raw: Dictionary = Content.creature_entry("f_gusto")
	for id in POOL:
		var pm: PoolMove = c.pool[id]
		for sid in pm.styles:
			var st: Dictionary = pm.styles[sid]
			var patch: Array = st.get("patch", [])
			var d: Dictionary = raw.duplicate(true)
			var res := ContentPatch.apply_all(d, patch)
			check((res["unmatched"] as Array).is_empty(), "%s.%s: every op lands (%s)" % [id, sid, str(res["unmatched"])])
			check(JSON.stringify(d) != JSON.stringify(raw), "%s.%s changes the fighter" % [id, sid])
			var pc := CreatureDef.from_dict(d, Callable(), "test")
			check(pc.is_valid(), "%s.%s: the drilled fighter is valid: %s" % [id, sid, str(pc.errors)])


func test_air_slash_flies_fast_and_cuts_through_a_line() -> void:
	var sim := _match([_entry(Content.creature("f_gusto"), 0, SKYHOOK), _entry(Content.creature("f_dredge"), 1), _entry(Content.creature("f_dredge"), 1)],
		[[0, -3.0, 0], [0, 0.0, 180], [3.0, 3.5, 180]])
	await step_sim(sim, 0.4)
	var a := sim.fighters[1]
	var b := sim.fighters[2]
	var slash: Dictionary = await _shoot(sim, 1, "air_slash")          # Move 2 = Air Slash
	if not check(not slash.is_empty(), "a crescent leaves the wing"):
		return
	var v: Vector3 = slash["vel"]
	check(v.length() > 20.0, "it flies fast (%.1f m/s)" % v.length())
	# the second Dredge steps onto its line, 2.5 m beyond the first
	var p: Vector3 = slash["pos"]
	var dir := Vector3(v.x, 0.0, v.z).normalized()
	var spot := p + dir * (Vector2(a.pos().x - p.x, a.pos().z - p.z).length() + 2.5)
	b.rig.place(Vector3(spot.x, b.rig.ground_y, spot.z), b.facing_yaw)
	b.motor.reset_feet()
	await step_sim(sim, 0.5)
	var struck := {}
	for h in pool_events(sim, "hit", "air_slash"):
		struck[int(h["target"])] = str(h.get("cat", ""))
	check(struck.has(1) and struck.has(2), "one crescent cuts through both fighters on its line (%s)" % str(struck))
	check(struck.values().all(func(cat) -> bool: return str(cat) == "projectile"), "attributed to the projectile")
	check(pool_damage(sim, "air_slash") >= 8.0, "both take its damage (%.1f)" % pool_damage(sim, "air_slash"))
	check(float(a.statuses.buildup.get("gale", 0.0)) > 0.0 or a.statuses.has_element("gale"), "and Winded builds")


func test_air_slash_is_parried_by_a_fresh_guard() -> void:
	var sim := duel("f_gusto", SKYHOOK, "f_dredge", 4.5)
	await step_sim(sim, 0.4)
	var g := sim.fighters[0]
	var d := sim.fighters[1]
	var hp := d.health
	var slash: Dictionary = await _shoot(sim, 1, "air_slash")
	if not check(not slash.is_empty(), "a crescent is in the air"):
		return
	var guarded := false
	var reeling := false
	var t := 0.0
	while t < 0.5:
		var p: Vector3 = slash["pos"]
		# a fresh guard just before it arrives: ~0.09 s out, so the guard is up (it blends in over
		# 0.08 s) and the contact still falls inside the 0.12 s parry window
		if not guarded and Vector2(p.x - d.pos().x, p.z - d.pos().z).length() < 2.6:
			d.input.press(FighterInput.GUARD)
			guarded = true
		await step_sim(sim, DT)
		t += DT
		reeling = reeling or g.state == Fighter.State.HITSTUN
	var parries := sim.events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == "parry" and int(e.get("fighter", -1)) == 1)
	check(guarded and not parries.is_empty(), "the crescent is parried")
	check_near(d.health, hp, 0.01, "the parrier takes nothing")
	check(reeling, "and Gusto is left reeling")


func test_feather_darts_fan_out_and_build_winded() -> void:
	var sim := duel("f_gusto", SKYHOOK, "f_dredge", 2.6)
	await step_sim(sim, 0.4)
	var d := sim.fighters[1]
	var heading: Dictionary = await _volley(sim, 2, "feather_darts", 0.45)       # Move 3 = Feather Darts
	check_eq(heading.size(), 5, "five darts fly")
	var yaws: Array = heading.values()
	yaws.sort()
	var fan := rad_to_deg(float(yaws[yaws.size() - 1]) - float(yaws[0])) if yaws.size() >= 2 else 0.0
	check(fan > 24.0 and fan < 36.0, "in a 30° fan (%.1f°)" % fan)
	await step_sim(sim, 0.3)
	var hits := pool_events(sim, "hit", "feather_darts")
	check(hits.size() >= 2, "up close most of them land (%d of 5)" % hits.size())
	check(hits.all(func(e: Dictionary) -> bool: return str(e.get("cat", "")) == "volley"), "attributed to the volley")
	var bu := float(d.statuses.buildup.get("gale", 0.0))
	check(bu >= 20.0 or d.statuses.has_element("gale"), "and Winded piles on (%.0f)" % bu)


func test_twister_rolls_out_lifts_and_leaves_a_whirl() -> void:
	var sim := duel("f_gusto", CYCLONE, "f_dredge", 4.0)
	await step_sim(sim, 0.4)
	var d := sim.fighters[1]
	var y0 := d.pos().y
	var z0 := d.pos().z
	var tw: Dictionary = await _shoot(sim, 1, "twister", 0.8)           # Move 2 = Twister
	if not check(not tw.is_empty(), "a twister rolls out"):
		return
	check(bool(tw["pierce"]) and bool((tw["e"] as Dictionary).get("intercept", false)), "it rolls through fighters and shots")
	var at: Vector3 = tw["pos"]
	await step_sim(sim, 0.2)
	var at2: Vector3 = tw["pos"]
	var speed := Vector2(at2.x - at.x, at2.z - at.z).length() / 0.2
	check(speed > 3.5 and speed < 5.5, "at a walking pace (%.1f m/s)" % speed)
	var top := y0
	var t := 0.0
	while t < 0.8:
		await step_sim(sim, DT)
		t += DT
		top = maxf(top, d.pos().y)
	check(top > y0 + 0.15, "the Dredge is lifted off its feet (%.2f m)" % (top - y0))
	check(d.pos().z > z0 + 0.2, "and thrown along its path (%.2f m)" % (d.pos().z - z0))
	var hits := pool_events(sim, "hit", "twister")
	check(not hits.is_empty() and str(hits[0].get("cat", "")) == "control", "attributed to the control move")
	await step_sim(sim, 0.6)
	var whirl := sim.effects.entities.filter(func(ent: Dictionary) -> bool:
		return str(ent.get("kind", "")) == "zone" and str(ent.get("vfx", "")) == "gusto_twister_eddy")
	if check(not whirl.is_empty(), "where it dies down it leaves a whirl"):
		check(float((whirl[0]["e"] as Dictionary).get("push_out", 0.0)) > 0.0, "that pushes fighters out")


func test_twister_swallows_enemy_shots() -> void:
	var sim := duel("f_gusto", CYCLONE, "f_dredge", 6.0)
	await step_sim(sim, 0.4)
	var g := sim.fighters[0]
	var d := sim.fighters[1]
	var tw: Dictionary = await _shoot(sim, 1, "twister", 0.8)
	if not check(not tw.is_empty(), "a twister rolls out"):
		return
	# the Dredge fires a shot straight down the twister's path at Gusto
	var hp := g.health
	sim.effects.fire(d, {"type": "projectile", "offset": [0, 0.9, 0.6], "speed": 9.0, "radius": 0.25, "life": 1.2,
		"damage": 6, "knockback": 2.0, "stun": 0.3, "element": "brine", "vfx": "orb"})
	var eaten := false
	var rolling := false
	var t := 0.0
	while t < 0.7 and not eaten:
		await step_sim(sim, DT)
		t += DT
		eaten = sim.events.any(func(e: Dictionary) -> bool:
			return str(e["type"]) == "projectile_destroyed" and str(e.get("by", "")) == "intercept" and int(e.get("fighter", -1)) == 0)
		rolling = float(tw["life"]) > 0.0 and float(tw["age"]) < float(tw["life"])
	check(eaten, "the twister swallows the shot")
	check(rolling, "and keeps rolling")
	await step_sim(sim, 0.5)
	check_near(g.health, hp, 0.01, "the shot never reaches Gusto")


func test_tailwind_speeds_gusto_up_and_cheapens_dodges() -> void:
	var sim := duel("f_gusto", CYCLONE, "f_dredge", 3.0)
	await step_sim(sim, 0.4)
	var g := sim.fighters[0]
	var walk: float = await _strafe_speed(sim, g, 1.0)
	var dodge: float = await _dodge_cost(sim, g)
	await use_slot(sim, 0, 3, 0.0, 0.5)              # Move 4 = Tailwind
	check(g.statuses.has("gusto_tailwind"), "the wind is at his back")
	var fast: float = await _strafe_speed(sim, g, -1.0)
	check(fast > walk * 1.18, "he moves faster (%.2f -> %.2f m/s)" % [walk, fast])
	var cheap: float = await _dodge_cost(sim, g)
	check(cheap < dodge - 3.0, "and his dodges cost less (%.1f -> %.1f stamina)" % [dodge, cheap])
	var casts := pool_events(sim, "effect", "tailwind").filter(func(e: Dictionary) -> bool: return str(e.get("vfx", "")) == "gusto_tailwind")
	check(not casts.is_empty(), "one wing beat casts it")
	await step_sim(sim, 3.6)
	check(not g.statuses.has("gusto_tailwind"), "for four seconds")


func test_classic_moves_carry_over() -> void:
	# Cyclone's Gust Bomb (Move 3) throws its v0.9.17 bomb
	var sim := duel("f_gusto", CYCLONE, "f_dredge", 3.5)
	await step_sim(sim, 0.4)
	await use_slot(sim, 0, 2, 0.0, 0.9)
	var bomb := sim.events.filter(func(e: Dictionary) -> bool:
		return str(e["type"]) == "effect" and int(e["fighter"]) == 0 and str(e.get("vfx", "")) in ["gust_bomb", "gust_burst"])
	check(not bomb.is_empty(), "Gust Bomb throws its v0.9.17 bomb")
	check(pool_damage(sim, "gust_bomb") > 0.0, "and it lands")
	# Skyhook's Hang Time (Move 4) lifts him; Wing Snap from the hover is the Dive Peck
	var sky := duel("f_gusto", SKYHOOK, "f_dredge", 2.4)
	await step_sim(sky, 0.4)
	var g := sky.fighters[0]
	await use_slot(sky, 0, 3, 0.0, 0.5)
	check(g.has_flag("hovering"), "Hang Time hovers")
	g.input.press(FighterInput.LIGHT)
	await step_sim(sky, 0.05)
	check_eq(g.move_slot, "l1@hovering", "Wing Snap from the hover is the Dive Peck")
	g.input.set_held(FighterInput.LIGHT, false)
	await step_sim(sky, 1.0)
	# Skyhook's air moves fire from the hover and keep it ("hover and shoot")
	var sky2 := duel("f_gusto", SKYHOOK, "f_dredge", 4.0)
	await step_sim(sky2, 0.4)
	var g2 := sky2.fighters[0]
	await use_slot(sky2, 0, 3, 0.0, 0.3)
	check(g2.has_flag("hovering"), "Hang Time hovers")
	await use_slot(sky2, 0, 1, 0.0, 0.1)      # Air Slash
	check(g2.has_flag("hovering"), "Air Slash fired from the hover keeps Gusto up")
	# Crosswind Slash charges into the Downdraft
	var cw := duel("f_gusto", ["wing_snap", "crosswind_slash"], "f_dredge", 2.0)
	await step_sim(cw, 0.4)
	var c := cw.fighters[0]
	c.input.press(FighterInput.HEAVY)
	await step_sim(cw, 1.3)
	check(c.move_charge > 0.5, "holding charges it (%.2f)" % c.move_charge)
	c.input.set_held(FighterInput.HEAVY, false)
	await step_sim(cw, 0.1)
	check_eq(c.move_slot, "heavy_charged", "release: the Downdraft")
	await step_sim(cw, 1.0)


func test_styles_change_how_moves_play() -> void:
	# Twin Crescents: a second crescent follows the first
	var twin := _duel_with(_drilled("air_slash", "twin_crescents"), SKYHOOK, 7.0)
	await step_sim(twin, 0.4)
	var crescents: Dictionary = await _volley(twin, 1, "air_slash", 0.6)
	check_eq(crescents.size(), 2, "Twin Crescents: two crescents per press")
	# Quill Storm: seven darts in a wider fan
	var storm := _duel_with(_drilled("feather_darts", "quill_storm"), SKYHOOK, 5.0)
	await step_sim(storm, 0.4)
	var heading: Dictionary = await _volley(storm, 2, "feather_darts", 0.4)
	var yaws: Array = heading.values()
	yaws.sort()
	check(heading.size() == 7 and rad_to_deg(float(yaws[yaws.size() - 1]) - float(yaws[0])) > 44.0, "Quill Storm: seven darts in a 50° fan")
	# Eye of the Storm: the whirl drags fighters in
	var eye := _duel_with(_drilled("twister", "eye_of_the_storm"), CYCLONE, 7.0)
	await step_sim(eye, 0.4)
	await use_slot(eye, 0, 1, 0.0, 1.8)
	var whirl := eye.effects.entities.filter(func(ent: Dictionary) -> bool:
		return str(ent.get("kind", "")) == "zone" and str(ent.get("vfx", "")) == "gusto_storm_eye")
	check(not whirl.is_empty() and float((whirl[0]["e"] as Dictionary).get("push_out", 0.0)) < 0.0, "Eye of the Storm: a whirl that pulls")


func test_effects_kit_draws_and_cleans_up() -> void:
	var view := CreatureView.new()
	add_child(view)
	view.setup(Content.creature("f_gusto"))
	var info := {"out": false}
	var fx := AbilityVfx.new()
	fx.view_of = func(i: int): return view if i == 0 else null
	fx.info_of = func(i: int) -> Dictionary:
		if i != 0:
			return {}
		return {"ground": Vector3.ZERO, "yaw": 0.0, "state": Fighter.State.ABILITY, "juiced": false, "hidden": false, "charge": -1.0, "out": bool(info["out"])}
	fx.fighter_count = func() -> int: return 1
	add_child(fx)
	var kit = fx.moves.kits.get("f_gusto")
	if not check(kit != null, "Gusto's kit is loaded"):
		fx.queue_free()
		view.queue_free()
		return
	for v in KIT_VFX:
		check(fx.moves.by_vfx.get(v) == kit, "the kit draws '%s'" % v)
	for old in ["gust_bomb", "gust_burst", "crosswind", "downdraft", "tailspin", "hurricane", "gale_vortex"]:
		check(not fx.moves.by_vfx.has(old), "v0.9.17's '%s' is left to its recipe" % old)
	# the four moves' wind-ups, their releases and whirls, and the styles' extras
	var n0 := fx.get_child_count()
	for pool in ["air_slash", "feather_darts", "twister", "tailwind"]:
		fx.on_event({"type": "move_start", "fighter": 0, "slot": "mv." + pool, "id": "f_gusto.mv." + pool, "pool": pool, "cat": "test"})
	check((kit._swings as Dictionary).has(0), "the Air Slash whip leaves a wing-tip trail")
	var evs := [{"effect": "projectile", "vfx": "gusto_air_slash"}, {"effect": "projectile", "vfx": "gusto_feather_darts"},
		{"effect": "projectile", "vfx": "gusto_twister"}, {"effect": "zone", "vfx": "gusto_twister_eddy", "radius": 1.3},
		{"effect": "zone", "vfx": "gusto_storm_eye", "radius": 1.7}, {"effect": "zone", "vfx": "gusto_slipstream_eddy", "radius": 1.0},
		{"effect": "buff", "vfx": "gusto_tailwind", "duration": 0.3}, {"effect": "dash", "vfx": "gusto_tailwind_dart", "dir": Vector3(1, 0, 0)},
		{"effect": "area", "vfx": "gusto_liftoff_gust", "radius": 1.6}]
	for e in evs:
		var ev: Dictionary = e
		ev.merge({"type": "effect", "fighter": 0, "pos": Vector3(0, 0, 1), "element": "gale", "pool": "test", "yaw": 0.0, "shape": "circle"})
		check(fx.moves.on_event(0, "f_gusto", ev), "the kit draws its '%s' event" % ev["vfx"])
	check(fx.get_child_count() > n0 + 5, "and leaves effects in the scene (%d nodes)" % (fx.get_child_count() - n0))
	check((kit._winds as Dictionary).has(0), "Tailwind's slipstream follows Gusto")
	for h in [{"pool": "air_slash"}, {"pool": "air_slash", "parried": true}, {"pool": "feather_darts"}, {"pool": "twister"}]:
		var hv: Dictionary = h
		hv.merge({"type": "hit", "fighter": 0, "target": -1, "damage": 6.0, "point": Vector3(0, 1, 2), "element": "gale"})
		fx.on_event(hv)
	# entities: the crescent, a dart, the funnel and both whirls follow their records, then end
	var ents := [
		{"id": 1, "kind": "projectile", "vfx": "gusto_air_slash", "pos": Vector3(0, 1.4, 1), "vel": Vector3(0, 0, 22), "radius": 0.22, "element": "gale", "team": 0},
		{"id": 2, "kind": "projectile", "vfx": "gusto_feather_darts", "pos": Vector3(0.3, 1.2, 1), "vel": Vector3(2, 0, 16), "radius": 0.11, "element": "gale", "team": 0},
		{"id": 3, "kind": "projectile", "vfx": "gusto_twister", "pos": Vector3(0, 0.8, 1.5), "vel": Vector3(0, 0, 4.6), "radius": 0.7, "element": "gale", "team": 0},
		{"id": 4, "kind": "zone", "vfx": "gusto_twister_eddy", "pos": Vector3(0, 0, 4), "radius": 1.3, "element": "gale", "team": 0},
		{"id": 5, "kind": "zone", "vfx": "gusto_storm_eye", "pos": Vector3(2, 0, 4), "radius": 1.7, "element": "gale", "team": 0}]
	fx.sync_entities(ents)
	var nodes := []
	for id in [1, 2, 3, 4, 5]:
		if check(fx._ents.has(id), "entity %d is drawn" % id):
			nodes.append((fx._ents[id] as Dictionary)["node"])
	await wait_vfx_seconds(8.0 / 120.0)
	for en in ents:
		var moved: Dictionary = en
		var p: Vector3 = moved["pos"]
		moved["pos"] = p + Vector3(0, 0, 0.5)
	fx.sync_entities(ents)
	if nodes.size() == 5:
		check((nodes[0] as Node3D).global_position.is_equal_approx(Vector3(0, 1.4, 1.5)), "the crescent flies with its projectile")
		check(is_equal_approx((nodes[2] as Node3D).global_position.z, 2.0), "the funnel rolls with its projectile")
	await wait_vfx_seconds(30.0 / 120.0)
	fx.sync_entities([])
	await wait_vfx_seconds(90.0 / 120.0)
	for nd in nodes:
		check(not is_instance_valid(nd), "every entity look is cleaned up")
	check(not (kit._winds as Dictionary).has(0), "the slipstream ends with the buff")
	check(not (kit._swings as Dictionary).has(0), "the whip's trail fades out")
	fx.queue_free()
	view.queue_free()


# =====================================================================================
# Helpers
# =====================================================================================

func _entry(c: CreatureDef, team: int, loadout := []) -> Dictionary:
	return {"creature": c, "team": team, "source": null, "loadout": loadout}


## A Movesets match on the test octagon: fighter entries at spawns [[x, z, yaw°], ...].
func _match(fighters: Array, spawns: Array) -> MatchSim:
	var arena := ArenaDef.from_dict({"id": "t", "base": "octagon", "radius": 7.0, "spawns": spawns})
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	sim.setup({"arena": arena, "rules": {"rounds": 1, "round_time": 0, "intro_time": 0.2, "combat": "moves"}, "seed": 7, "fighters": fighters})
	return sim


## `c` (Gusto, perhaps drilled) with `loadout` against a standing Dredge `gap` metres away.
func _duel_with(c: CreatureDef, loadout: Array, gap: float) -> MatchSim:
	return _match([_entry(c, 0, loadout), _entry(Content.creature("f_dredge"), 1)], [[0, -gap * 0.5, 0], [0, gap * 0.5, 180]])


## Gusto with one style drilled: its patch applied to his authored content.
func _drilled(move_id: String, style: String) -> CreatureDef:
	var pm: PoolMove = Content.creature("f_gusto").pool[move_id]
	var st: Dictionary = pm.styles[style]
	var patch: Array = st.get("patch", [])
	var d: Dictionary = Content.creature_entry("f_gusto").duplicate(true)
	ContentPatch.apply_all(d, patch)
	var c := CreatureDef.from_dict(d, Callable(), "test")
	check(c.is_valid(), "%s.%s drills cleanly: %s" % [move_id, style, str(c.errors)])
	return c


## Presses loadout slot `i` of fighter 0 and steps until a projectile of `pool` flies (at most `wait`
## seconds); returns its entity record ({} if none came).
func _shoot(sim: MatchSim, i: int, pool: String, wait := 0.6) -> Dictionary:
	var g := sim.fighters[0]
	var b: int = Fighter.MOVE_BUTTONS[i]
	g.input.press(b)
	var t := 0.0
	var out := {}
	while t < wait and out.is_empty():
		await step_sim(sim, DT)
		t += DT
		if t > 2.5 * DT:
			g.input.set_held(b, false)
		var es := pool_entities(sim, pool, "projectile")
		if not es.is_empty():
			out = es[0]
	g.input.set_held(b, false)
	return out


## Presses loadout slot `i` of fighter 0 for `secs` seconds of play and returns every projectile of
## `pool` seen meanwhile: entity id -> its heading (yaw) when it was first seen.
func _volley(sim: MatchSim, i: int, pool: String, secs: float) -> Dictionary:
	var g := sim.fighters[0]
	var b: int = Fighter.MOVE_BUTTONS[i]
	g.input.press(b)
	var heading := {}
	var t := 0.0
	while t < secs:
		await step_sim(sim, DT)
		t += DT
		if t > 2.5 * DT:
			g.input.set_held(b, false)
		for ent in pool_entities(sim, pool, "projectile"):
			var id := int(ent["id"])
			if not heading.has(id):
				var v: Vector3 = ent["vel"]
				heading[id] = atan2(v.x, v.z)
	g.input.set_held(b, false)
	return heading


## Gusto's ground speed strafing sideways (`side` +1 = world +X) once he is up to speed.
func _strafe_speed(sim: MatchSim, g: Fighter, side: float) -> float:
	g.input.move = Vector3(side, 0, 0)
	await step_sim(sim, 0.35)
	var v := g.rig.com_velocity()
	g.input.move = Vector3.ZERO
	await step_sim(sim, 0.25)
	return Vector2(v.x, v.z).length()


## The stamina one (back) dodge costs Gusto, after his light-dodge refund.
func _dodge_cost(sim: MatchSim, g: Fighter) -> float:
	var s0 := g.stamina
	g.input.press(FighterInput.DODGE)
	await step_sim(sim, 3.0 * DT)
	g.input.set_held(FighterInput.DODGE, false)
	var cost := s0 - g.stamina
	await step_sim(sim, 0.8)
	return cost
