extends MovesKitCase
## Knell's v0.9.18 move pool (docs/kits/f_knell.md, docs/design/MOVESET_COMBAT.md §4): every move
## does what its description says, in Movesets, against a standing Dredge; every style is a real
## patch that changes how its move plays; the effects kit (src/view/fx/moves/f_knell.gd) draws the
## new moves headless and cleans up after them.

const LAMPLIGHTER := ["sounding_jab", "night_shade", "ghost_light", "through_the_veil"]
const UNDERTOW := ["sounding_jab", "anchor_fist", "hex_chain", "lantern_swarm"]
const POOL := ["sounding_jab", "anchor_fist", "ghost_light", "through_the_veil", "night_shade", "hex_chain", "lantern_swarm", "toll"]
const KIT_VFX := ["knell_night_shade", "knell_hex_chain", "knell_lantern_wisp", "knell_toll_ring", "knell_toll_echo"]

var _vstate := {}        ## effects tests: fighter -> Fighter.State its info reports
var _vout := {}          ## effects tests: fighters reported out of the fight


func test_pool_and_loadouts() -> void:
	var c := Content.creature("f_knell")
	for id in POOL:
		check_pool_move("f_knell", id)
	check_eq(c.resolve_loadout([]), LAMPLIGHTER, "the default loadout is Lamplighter")
	check_eq((c.loadouts["undertow"] as Dictionary)["moves"], UNDERTOW, "Undertow is the second build")
	var shared := LAMPLIGHTER.filter(func(x) -> bool: return UNDERTOW.has(x))
	check_eq(shared, ["sounding_jab"], "the two builds share only the basic strike")
	var cats := {}
	for id in POOL:
		cats[id] = (c.pool[id] as PoolMove).category
	check_eq(cats, {"sounding_jab": "strike", "anchor_fist": "strike", "ghost_light": "projectile", "through_the_veil": "utility",
		"night_shade": "stream", "hex_chain": "control", "lantern_swarm": "volley", "toll": "counter"}, "the categories of §4")
	var jab: PoolMove = c.pool["sounding_jab"]
	check(jab.role == "basic" and jab.string == ["l1", "l2", "l3", "finisher"] and jab.dash == "dash_attack", "the basic strike walks Knell's string")
	var fist: PoolMove = c.pool["anchor_fist"]
	check(fist.role == "heavy" and fist.hold == "charge" and fist.charged == c.moves["heavy_charged"], "Anchor Fist charges into the Deep Anchor")
	check((c.pool["ghost_light"] as PoolMove).move == c.abilities["ability1"] and (c.pool["through_the_veil"] as PoolMove).move == c.abilities["ability2"],
		"the v0.9.17 abilities are in the pool as themselves")
	var shade: PoolMove = c.pool["night_shade"]
	check(shade.hold == "sustain" and shade.drain > 0.0 and shade.aim_turn > 0.0 and shade.max_hold > 1.0, "Night Shade is a sustained, aimed, draining stream")
	for id in ["night_shade", "hex_chain", "lantern_swarm", "toll"]:
		var pm: PoolMove = c.pool[id]
		check(pm.stamina_cost() > 0.0 and pm.cooldown >= 4.0 and pm.cooldown <= 12.0, "%s: a real cooldown and a stamina cost" % id)
		check(pm.move.element == "spectral", "%s: spectral" % id)


## Every style is a valid patch that hits real fields of Knell's content and leaves him valid.
func test_styles_patch_real_fields() -> void:
	var base: Dictionary = Content.creature_entry("f_knell")
	var c := Content.creature("f_knell")
	var bad := []
	for id in POOL:
		var pm: PoolMove = c.pool[id]
		for sid in pm.styles:
			var st: Dictionary = pm.styles[sid]
			if str(st.get("name", "")) == "" or str(st.get("desc", "")).length() < 20:
				bad.append("%s/%s: a name and a description" % [id, sid])
			var patches: Array = st.get("patch", [])
			if patches.is_empty():
				bad.append("%s/%s: no patch" % [id, sid])
			var d: Dictionary = base.duplicate(true)
			for p in patches:
				var err := ContentPatch.validate(p)
				if err != "":
					bad.append("%s/%s: %s" % [id, sid, err])
				elif ContentPatch.apply(d, p) == 0:
					bad.append("%s/%s: %s matches nothing" % [id, sid, str((p as Dictionary).get("path", ""))])
			var styled := CreatureDef.from_dict(d, Callable(), "test")
			if not styled.is_valid():
				bad.append("%s/%s: %s" % [id, sid, str(styled.errors)])
	check(bad.is_empty(), "style problems:\n%s" % "\n".join(bad))


func test_night_shade_pours_slows_haunts_and_stops_on_release() -> void:
	var sim := duel("f_knell", LAMPLIGHTER, "f_dredge", 3.0)
	await step_sim(sim, 0.4)
	var k := sim.fighters[0]
	var d := sim.fighters[1]
	var hp := d.health
	var st0 := k.stamina
	k.input.press(FighterInput.HEAVY)             # Move 2 = Night Shade
	await step_sim(sim, 1.4)
	check(k.move_pool_id == "night_shade" and k.sustaining, "still shining while held, past the move's 0.95 s")
	check(d.statuses.has("night_shaded") and d.statuses.speed_mult() < 0.75, "the beam slows what it touches (%.2f)" % d.statuses.speed_mult())
	check(k.stamina < st0 - 6.0 - 11.0 * 0.8, "it drains stamina while held (%.1f -> %.1f)" % [st0, k.stamina])
	k.input.set_held(FighterInput.HEAVY, false)
	var ticks := pool_events(sim, "effect", "night_shade").filter(func(e: Dictionary) -> bool: return str(e["effect"]) == "area")
	check(ticks.size() >= 8, "the beam fires every 0.12 s while held (%d)" % ticks.size())
	check(ticks.all(func(e: Dictionary) -> bool: return bool(e.get("tick", false)) and str(e.get("vfx", "")) == "knell_night_shade"), "as stream ticks, drawn by Knell's kit")
	await step_sim(sim, 0.6)
	var after := pool_events(sim, "effect", "night_shade").size()
	check(after <= ticks.size() + 1, "release puts the light out (%d -> %d)" % [ticks.size(), after])
	check(k.move == null, "and Knell plays out his recovery")
	var hits := pool_events(sim, "hit", "night_shade")
	check(pool_damage(sim, "night_shade") > 6.0 and d.health < hp, "it hurts the Dredge three metres away (%.1f)" % pool_damage(sim, "night_shade"))
	check(not hits.is_empty() and hits.all(func(e: Dictionary) -> bool: return str(e.get("cat", "")) == "stream" and bool(e.get("tick", false))),
		"its hits are the stream's, throttled as ticks")
	check(float(d.statuses.buildup.get("spectral", 0.0)) > 20.0 or d.statuses.has_element("spectral"), "and it builds Haunted")
	var sus := sim.events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == "sustain" and int(e["fighter"]) == 0)
	check(sus.size() == 2 and str(sus[0]["phase"]) == "start" and str(sus[1]["phase"]) == "end", "one sustain start, one end")
	# aiming: with the stick pushed to the side the beam sweeps (slowly) toward it
	var sim2 := duel("f_knell", LAMPLIGHTER, "f_dredge", 3.0)
	await step_sim(sim2, 0.4)
	var k2 := sim2.fighters[0]
	var yaw0 := k2.facing_yaw
	k2.input.press(FighterInput.HEAVY)
	k2.input.move = Vector3(1, 0, 0)
	await step_sim(sim2, 1.0)
	var swept := absf(MathX.wrap_angle(k2.facing_yaw - yaw0))
	check(swept > 0.6 and swept < 2.2, "the stick sweeps the beam at its turn rate (%.2f rad in ~0.85 s)" % swept)
	k2.input.set_held(FighterInput.HEAVY, false)
	k2.input.move = Vector3.ZERO
	await step_sim(sim2, 0.5)


func test_hex_chain_bites_yanks_and_hexes() -> void:
	var sim := duel("f_knell", UNDERTOW, "f_dredge", 4.5)
	await step_sim(sim, 0.4)
	var k := sim.fighters[0]
	var d := sim.fighters[1]
	var gap0 := k.pos().distance_to(d.pos())
	await use_slot(sim, 0, 2, 0.0, 0.33)          # Move 3 = Hex Chain (cast 0.27 s in)
	check(not pool_entities(sim, "hex_chain", "projectile").is_empty(), "the chain is in the air")
	await step_sim(sim, 0.8)
	var hits := pool_events(sim, "hit", "hex_chain")
	check(not hits.is_empty() and str(hits[0].get("cat", "")) == "control" and float(hits[0]["damage"]) > 2.0, "it bites, attributed to the control move")
	check(d.statuses.has("hexed") and d.statuses.speed_mult() < 0.65 and d.statuses.mult("dash") < 0.65, "the catch is hexed: slowed, dodges cut short")
	var gap1 := k.pos().distance_to(d.pos())
	check(gap1 < gap0 - 0.8, "the chain drags its catch toward Knell (%.2f -> %.2f m)" % [gap0, gap1])
	await step_sim(sim, 2.2)
	check(not d.statuses.has("hexed"), "the hex wears off after 2.5 s")
	# a fighter out of its reach is never caught: a missed cast hauls in nothing
	var far := duel("f_knell", UNDERTOW, "f_dredge", 9.0)
	await step_sim(far, 0.4)
	await use_slot(far, 0, 2, 0.0, 1.2)
	check(pool_events(far, "hit", "hex_chain").is_empty() and not far.fighters[1].statuses.has("hexed"), "nine metres away the chain falls short")
	check(far.fighters[0].move == null, "and Knell has hauled it back in")


func test_lantern_swarm_fans_out_and_homes_in() -> void:
	var sim := duel("f_knell", UNDERTOW, "f_dredge", 4.0)
	await step_sim(sim, 0.4)
	await use_slot(sim, 0, 3, 0.0, 0.34)          # Move 4 = Lantern Swarm (released 0.3 s in)
	var wisps := pool_entities(sim, "lantern_swarm", "projectile")
	check_eq(wisps.size(), 3, "three wisps in the air")
	var spread := 0.0
	for a in wisps:
		for b in wisps:
			var va: Vector3 = a["vel"]
			var vb: Vector3 = b["vel"]
			spread = maxf(spread, Vector2(va.x, va.z).angle_to(Vector2(vb.x, vb.z)))
	check(spread > deg_to_rad(55.0), "they fan out wide (%.0f°)" % rad_to_deg(spread))
	await step_sim(sim, 2.0)
	var hits := pool_events(sim, "hit", "lantern_swarm")
	check(hits.size() >= 2, "they curl in on the target from the side: %d of 3 land" % hits.size())
	check(hits.all(func(e: Dictionary) -> bool: return str(e.get("cat", "")) == "volley"), "attributed to the volley")
	check(pool_damage(sim, "lantern_swarm") >= 7.0, "%.1f damage" % pool_damage(sim, "lantern_swarm"))


## (A Stoke jabs into the echo: his jab comes down the centre line, where Dredge's claws come in
## from the sides and can pass a braced Knell by.)
func test_toll_cleanses_armours_and_counter_shocks() -> void:
	var sim := duel("f_knell", ["sounding_jab", "toll"], "f_stoke", 1.15)
	await step_sim(sim, 0.4)
	var k := sim.fighters[0]
	var s := sim.fighters[1]
	k.statuses.add({"id": "status_scorch", "name": "Sizzle", "element": "scorch", "duration": 5.0})
	k.statuses.add_buildup("brine", 40.0, s)
	check(k.statuses.has_element("scorch"), "Knell walks in Sizzling")
	await use_slot(sim, 0, 1, 0.0, 0.25)          # Move 2 = Toll (rung 0.2 s in)
	check(not k.statuses.has_element("scorch") and float(k.statuses.buildup.get("brine", 0.0)) == 0.0, "the toll shakes off his statuses and build-up")
	check(k.counter_active(), "and its echo is up")
	var hp := s.health
	s.input.press(FighterInput.LIGHT)             # Stoke jabs into the echo
	await step_sim(sim, 0.5)
	var counters := sim.events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == "counter" and int(e.get("fighter", -1)) == 0)
	check(not counters.is_empty(), "the next blow sets off the counter-shock")
	var shock := pool_events(sim, "hit", "toll")
	check(not shock.is_empty() and str(shock[0].get("cat", "")) == "counter" and int(shock[0]["target"]) == 1, "attributed to the counter, on the attacker")
	check(s.health < hp and float(s.statuses.buildup.get("spectral", 0.0)) > 0.0, "it hurts and Haunts Stoke")
	check(k.state != Fighter.State.HITSTUN, "Knell, armoured in the echo, does not stagger")
	# an echo nobody answers dies away with the move
	var quiet := duel("f_knell", ["sounding_jab", "toll"], "f_stoke", 3.0)
	await step_sim(quiet, 0.4)
	await use_slot(quiet, 0, 1, 0.0, 1.4)
	check(not quiet.fighters[0].counter_active() and quiet.fighters[0].move == null, "the echo is over when the move is")


func test_basic_heavy_and_v0917_abilities_carry_over() -> void:
	var sim := duel("f_knell", LAMPLIGHTER, "f_stoke", 1.1)
	await step_sim(sim, 0.4)
	var k := sim.fighters[0]
	k.input.press(FighterInput.LIGHT)             # Move 1 = Sounding Jab
	await step_sim(sim, 0.03)
	check_eq(k.move_slot, "l1", "Move 1 opens with the Sounding Jab")
	await step_sim(sim, 0.5)
	var jabs := pool_events(sim, "hit", "sounding_jab")
	check(not jabs.is_empty() and str(jabs[0].get("cat", "")) == "strike", "it lands as the basic strike")
	# Anchor Fist: hold to charge, release into the Deep Anchor
	var hv := duel("f_knell", UNDERTOW, "f_dredge", 1.4)
	await step_sim(hv, 0.4)
	var kh := hv.fighters[0]
	kh.input.press(FighterInput.HEAVY)            # Move 2 = Anchor Fist
	await step_sim(hv, 1.2)
	check(kh.move_charge > 0.5, "holding charges it (%.2f)" % kh.move_charge)
	kh.input.set_held(FighterInput.HEAVY, false)
	await step_sim(hv, 0.1)
	check_eq(kh.move_slot, "heavy_charged", "release: the Deep Anchor")
	await step_sim(hv, 1.0)
	# Ghost Light: the v0.9.17 homing lantern
	var gl := duel("f_knell", LAMPLIGHTER, "f_dredge", 4.0)
	await step_sim(gl, 0.4)
	await use_slot(gl, 0, 2, 0.0, 0.3)            # Move 3 = Ghost Light
	check(not pool_entities(gl, "ghost_light", "projectile").is_empty(), "the lantern is on its way")
	await step_sim(gl, 1.4)
	var lit := pool_events(gl, "hit", "ghost_light")
	check(not lit.is_empty() and str(lit[0].get("cat", "")) == "projectile", "and lands, attributed to it")
	# Through the Veil: sinks and resurfaces along the stick
	var vl := duel("f_knell", LAMPLIGHTER, "f_dredge", 3.0)
	await step_sim(vl, 0.4)
	var kv := vl.fighters[0]
	var x0 := kv.pos().x
	kv.input.move = Vector3(1, 0, 0)
	await use_slot(vl, 0, 3, 0.0, 0.8)            # Move 4 = Through the Veil
	kv.input.move = Vector3.ZERO
	check(not vl.events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == "submerge" and int(e["fighter"]) == 0).is_empty(), "Knell sinks")
	check(kv.pos().x > x0 + 2.0, "and rises along the stick (%.2f m)" % (kv.pos().x - x0))
	# Classic is untouched: the same inputs are Light, Heavy and the abilities, with no pool moves
	var cl := duel("f_knell", LAMPLIGHTER, "f_dredge", 2.0, {"combat": "classic"})
	await step_sim(cl, 0.4)
	var kc := cl.fighters[0]
	kc.input.press(FighterInput.HEAVY)
	await step_sim(cl, 0.05)
	check(kc.move_slot.begins_with("heavy") and kc.move_pool_id == "", "Classic Heavy is the v0.9.17 heavy (%s)" % kc.move_slot)
	kc.input.set_held(FighterInput.HEAVY, false)
	await step_sim(cl, 1.2)


## Styles change how a move plays, not just a number.
func test_styles_change_how_moves_play() -> void:
	# Undertow Beam drags what it touches toward Knell; the plain beam only slows it
	var plain := duel("f_knell", LAMPLIGHTER, "f_dredge", 3.2)
	var drag := _styled_duel("night_shade", "undertow_beam", LAMPLIGHTER, 3.2)
	var gaps := []
	for sim: MatchSim in [plain, drag]:
		await step_sim(sim, 0.4)
		var g0 := sim.fighters[0].pos().distance_to(sim.fighters[1].pos())
		await use_slot(sim, 0, 1, 1.6, 0.1)
		gaps.append(g0 - sim.fighters[0].pos().distance_to(sim.fighters[1].pos()))
	check(float(gaps[0]) < 0.1, "the plain beam does not reel the Dredge in (%.2f m)" % float(gaps[0]))
	check(float(gaps[1]) > 0.5, "the Undertow Beam reels it in (%.2f m)" % float(gaps[1]))
	# Shackle binds without hauling: no yank, a longer and deeper hex
	var shackle := _styled_duel("hex_chain", "shackle", UNDERTOW, 4.5)
	await step_sim(shackle, 0.4)
	var s0 := shackle.fighters[0].pos().distance_to(shackle.fighters[1].pos())
	await use_slot(shackle, 0, 2, 0.0, 1.0)
	var dd := shackle.fighters[1]
	check(dd.statuses.has("hexed") and dd.statuses.speed_mult() < 0.5, "Shackle hexes deeper (%.2f)" % dd.statuses.speed_mult())
	check(s0 - shackle.fighters[0].pos().distance_to(dd.pos()) < 0.4, "without the yank")
	# Corpse Candles: five wisps instead of three
	var candles := _styled_duel("lantern_swarm", "corpse_candles", UNDERTOW, 4.0)
	await step_sim(candles, 0.4)
	await use_slot(candles, 0, 3, 0.0, 0.34)
	check_eq(pool_entities(candles, "lantern_swarm", "projectile").size(), 5, "Corpse Candles throws five wisps")


## A duel like MovesKitCase.duel with Knell drilled in one style of one move.
func _styled_duel(move_id: String, style_id: String, loadout: Array, gap: float) -> MatchSim:
	var d: Dictionary = Content.creature_entry("f_knell").duplicate(true)
	var styles: Dictionary = ((d["movepool"] as Dictionary)[move_id] as Dictionary)["styles"]
	ContentPatch.apply_all(d, (styles[style_id] as Dictionary)["patch"])
	var c := CreatureDef.from_dict(d, Callable(), "test")
	check(c.is_valid(), "%s/%s parses: %s" % [move_id, style_id, str(c.errors)])
	var arena := ArenaDef.from_dict({"id": "t", "base": "octagon", "radius": 7.0, "spawns": [[0, -gap * 0.5, 0], [0, gap * 0.5, 180]]})
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	sim.setup({"arena": arena, "rules": {"rounds": 1, "round_time": 0, "intro_time": 0.2, "combat": "moves"}, "seed": 7, "fighters": [
		{"creature": c, "team": 0, "source": null, "loadout": loadout},
		{"creature": Content.creature("f_dredge"), "team": 1, "source": null}]})
	return sim


# ---- the effects kit, headless ------------------------------------------------------------------

func _fx(views: Array) -> AbilityVfx:
	var fx := AbilityVfx.new()
	fx.view_of = func(i: int): return views[i] if i >= 0 and i < views.size() else null
	fx.info_of = func(i: int) -> Dictionary:
		if i < 0 or i >= views.size():
			return {}
		return {"ground": Vector3(0, 0, i * 3.0), "yaw": 0.0, "state": int(_vstate.get(i, Fighter.State.ABILITY)), "juiced": false,
			"hidden": false, "charge": -1.0, "out": bool(_vout.get(i, false))}
	fx.fighter_count = func() -> int: return views.size()
	add_child(fx)
	return fx


## Views in their rest pose, each standing where its info places it (fighter i at z = 3 i, facing
## +Z), so the anchors (porthole, fists, gauge) sit at their real heights.
func _views(ids: Array) -> Array:
	var out := []
	for i in ids.size():
		var c := Content.creature(str(ids[i]))
		var v := CreatureView.new()
		add_child(v)
		v.setup(c)
		var rest: Array[Transform3D] = []
		for s: BodyDef.Seg in c.body.segments:
			rest.append(Transform3D(Basis.IDENTITY, Vector3(0, 0, i * 3.0) + s.pivot))
		v.snap_transforms(rest)
		out.append(v)
	return out


func _free(fx: AbilityVfx, views: Array) -> void:
	fx.queue_free()
	for v in views:
		(v as Node).queue_free()


func test_kit_registers_and_draws_the_beam() -> void:
	var views := _views(["f_knell", "f_dredge"])
	var fx := _fx(views)
	check(fx.moves != null and fx.moves.kits.has("f_knell"), "Knell's kit is loaded")
	var kit = fx.moves.kits["f_knell"]
	for v in KIT_VFX:
		check(fx.moves.by_vfx.get(v) == kit, "the kit draws '%s'" % v)
	check(not fx.moves.by_vfx.has("ring") and not fx.moves.by_vfx.has("orb"), "the v0.9.17 Last Bell and Ghost Light recipes are not taken over")
	var shade := {"type": "effect", "fighter": 0, "effect": "area", "vfx": "knell_night_shade", "pool": "night_shade", "tick": true, "pos": Vector3.ZERO,
		"origin": Vector3.ZERO, "radius": 0.0, "length": 5.0, "width": 0.7, "shape": "line", "yaw": 0.0, "element": "spectral"}
	fx.on_event({"type": "move_start", "fighter": 0, "slot": "mv.night_shade", "id": "f_knell.mv.night_shade", "pool": "night_shade", "cat": "stream"})
	fx.on_event({"type": "sustain", "fighter": 0, "phase": "start", "pool": "night_shade", "slot": "m2"})
	check((kit._beams as Dictionary).has(0), "a sustain start lights the beam")
	var outer: Node3D = (kit._beams[0] as Dictionary)["outer"]
	for k in 4:
		fx.on_event(shade)
		fx.on_event({"type": "hit", "fighter": 0, "target": 1, "pool": "night_shade", "cat": "stream", "tick": true, "damage": 1.5,
			"point": Vector3(0, 1, 3), "element": "spectral", "blocked": false})
		await wait_frames(6)
	var beam: Dictionary = kit._beams.get(0, {})
	check(not beam.is_empty() and float(beam["len"]) > 2.0, "the beam reaches out toward its length (%s)" % str(beam.get("len", 0)))
	check(outer.global_position.distance_to(kit.port(0)) > 1.0, "from the porthole, along the facing")
	fx.on_event({"type": "sustain", "fighter": 0, "phase": "end", "pool": "night_shade", "slot": "m2"})
	await wait_frames(45)
	check(not (kit._beams as Dictionary).has(0) and not is_instance_valid(outer), "releasing puts it out and frees it")
	# cut off: Knell is hit mid-beam (no end event reaches the effects first)
	fx.on_event({"type": "sustain", "fighter": 0, "phase": "start", "pool": "night_shade", "slot": "m2"})
	await wait_frames(4)
	_vstate[0] = Fighter.State.HITSTUN
	await wait_frames(45)
	check(not (kit._beams as Dictionary).has(0), "an interrupted beam dies with the move")
	_vstate.erase(0)
	# a tapped Night Shade fires once, without a sustain: a flash of the beam, nothing left behind
	fx.on_event(shade)
	check(not (kit._beams as Dictionary).has(0), "a single tick leaves no beam running")
	_free(fx, views)


func test_kit_chain_wisps_and_tether_draw_and_clean_up() -> void:
	var views := _views(["f_knell", "f_dredge"])
	var fx := _fx(views)
	var kit = fx.moves.kits["f_knell"]
	# online entities carry no owner: the chain still runs back to the nearest Knell
	fx.sync_entities([{"id": 1, "kind": "projectile", "vfx": "knell_hex_chain", "pos": Vector3(0, 1.3, 0.8), "radius": 0.3, "element": "spectral", "team": 0},
		{"id": 2, "kind": "projectile", "vfx": "knell_lantern_wisp", "pos": Vector3(0.3, 1.3, 0.6), "radius": 0.2, "element": "spectral", "team": 0},
		{"id": 3, "kind": "projectile", "vfx": "knell_lantern_wisp", "pos": Vector3(-0.3, 1.3, 0.6), "radius": 0.2, "element": "spectral", "team": 0}])
	check(fx._ents.has(1) and fx._ents.has(2) and fx._ents.has(3), "the chain and the wisps are drawn")
	var head: Node3D = (fx._ents[1] as Dictionary)["node"]
	var wisp: Node3D = (fx._ents[2] as Dictionary)["node"]
	fx.sync_entities([{"id": 1, "kind": "projectile", "vfx": "knell_hex_chain", "pos": Vector3(0, 1.2, 2.0), "radius": 0.3, "element": "spectral", "team": 0},
		{"id": 2, "kind": "projectile", "vfx": "knell_lantern_wisp", "pos": Vector3(0.6, 1.25, 1.2), "radius": 0.2, "element": "spectral", "team": 0},
		{"id": 3, "kind": "projectile", "vfx": "knell_lantern_wisp", "pos": Vector3(-0.6, 1.25, 1.2), "radius": 0.2, "element": "spectral", "team": 0}])
	await wait_frames(2)
	check(head.global_position.is_equal_approx(Vector3(0, 1.2, 2.0)), "the chain's barb flies with its projectile")
	check(wisp.global_position.is_equal_approx(Vector3(0.6, 1.25, 1.2)), "and so do the wisps")
	# the bite: the chain lands on the Dredge and the hex holds it on a tether
	fx.on_event({"type": "hit", "fighter": 0, "target": 1, "pool": "hex_chain", "cat": "control", "damage": 4.0, "point": Vector3(0, 1.0, 3.0),
		"element": "spectral", "blocked": false})
	fx.sync_entities([])
	check((kit._tethers as Dictionary).has(1), "a bite tethers the catch")
	var rib: Node3D = (kit._tethers[1] as Dictionary)["rib"]
	await wait_frames(40)
	check(not is_instance_valid(head) and not is_instance_valid(wisp), "the chain head and the wisps are cleaned up")
	check((kit._tethers as Dictionary).has(1) and is_instance_valid(rib), "the tether holds while the hex does")
	await wait_frames(320)
	check(not (kit._tethers as Dictionary).has(1) and not is_instance_valid(rib), "and lets go when the hex wears off (2.5 s)")
	# a guarded chain hexes nobody; a tether whose catch is gone lets go at once
	fx.on_event({"type": "hit", "fighter": 0, "target": 1, "pool": "hex_chain", "cat": "control", "damage": 1.0, "point": Vector3(0, 1.0, 3.0),
		"element": "spectral", "blocked": true})
	check(not (kit._tethers as Dictionary).has(1), "a blocked chain leaves no tether")
	fx.on_event({"type": "hit", "fighter": 0, "target": 1, "pool": "hex_chain", "cat": "control", "damage": 4.0, "point": Vector3(0, 1.0, 3.0),
		"element": "spectral", "blocked": false})
	_vout[1] = true
	await wait_frames(60)
	check(not (kit._tethers as Dictionary).has(1), "a tether to a fighter out of the fight lets go")
	_vout.erase(1)
	_free(fx, views)


func test_kit_toll_rings_echoes_and_breaks_on_the_counter() -> void:
	var views := _views(["f_knell", "f_dredge"])
	var fx := _fx(views)
	var kit = fx.moves.kits["f_knell"]
	var stance := func() -> Array: return fx._follows.filter(func(f: Dictionary) -> bool: return int(f["fi"]) == 0 and str(f.get("tag", "")) == "stance")
	fx.on_event({"type": "move_start", "fighter": 0, "slot": "mv.toll", "id": "f_knell.mv.toll", "pool": "toll", "cat": "counter"})
	fx.on_event({"type": "effect", "fighter": 0, "effect": "cleanse", "vfx": "knell_toll_ring", "pos": Vector3.ZERO, "pool": "toll", "element": "", "radius": 0.0, "yaw": 0.0})
	fx.on_event({"type": "effect", "fighter": 0, "effect": "counter_stance", "vfx": "knell_toll_echo", "pos": Vector3.ZERO, "pool": "toll", "element": "",
		"radius": 0.0, "yaw": 0.0, "duration": 1.0})
	check((kit._echoes as Dictionary).has(0) and not (stance.call() as Array).is_empty(), "the echo rings on around Knell")
	await wait_frames(30)
	# the Dredge strikes him: the counter event lets go of the echo, the counter-shock hits back
	fx.on_event({"type": "counter", "fighter": 0, "victim": 1})
	fx.on_event({"type": "hit", "fighter": 0, "target": 1, "pool": "toll", "cat": "counter", "damage": 9.0, "point": Vector3(0, 1.0, 2.6),
		"element": "spectral", "blocked": false})
	check(not (kit._echoes as Dictionary).has(0), "the counter-shock breaks the echo")
	await wait_frames(60)
	check((stance.call() as Array).is_empty(), "and its pieces let go")
	# unanswered, the echo dies away by itself
	fx.on_event({"type": "effect", "fighter": 0, "effect": "counter_stance", "vfx": "knell_toll_echo", "pos": Vector3.ZERO, "pool": "toll", "element": "",
		"radius": 0.0, "yaw": 0.0, "duration": 0.5})
	await wait_frames(90)
	check(not (kit._echoes as Dictionary).has(0) and (stance.call() as Array).is_empty(), "an echo nobody answers fades out")
	_free(fx, views)
