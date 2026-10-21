extends MovesKitCase
## Slurry's v0.9.18 move pool (docs/kits/f_slurry.md "Movesets (v0.9.18)", docs/design/MOVESET_COMBAT.md
## §4): every move does what its description says, in Movesets, against a standing Dredge, and the
## effects kit (src/view/fx/moves/f_slurry.gd) draws and cleans up its events and entities headless.

const VENOMOUS := ["venom_fangs", "poison_darts", "sludge_lob", "drain_dive"]
const SWAMP := ["venom_fangs", "acid_spray", "coil_crush", "shed_skin"]
const POOL := ["venom_fangs", "tail_sweep", "sludge_lob", "drain_dive", "poison_darts", "acid_spray", "coil_crush", "shed_skin"]
const CATEGORY := {"venom_fangs": "strike", "tail_sweep": "strike", "sludge_lob": "projectile", "drain_dive": "utility",
	"poison_darts": "volley", "acid_spray": "stream", "coil_crush": "strike", "shed_skin": "support"}
const KIT_VFX := ["slurry_dart", "slurry_acid", "slurry_coil_squeeze", "slurry_coil_crush", "slurry_shed_skin", "slurry_shed_slip",
	"slurry_fresh_scales", "slurry_molt_burst"]

var _state := {}         ## effects tests: fighter -> Fighter.State the info callable reports
var _ground_at := {}     ## effects tests: fighter -> ground position (default: 2 m apart on X)


func test_pool_and_loadouts() -> void:
	var c := Content.creature("f_slurry")
	for id in POOL:
		var pm := check_pool_move("f_slurry", id)
		if pm != null:
			check_eq(pm.category, str(CATEGORY[id]), "%s is a %s move" % [id, CATEGORY[id]])
	check_eq(c.pool.size(), POOL.size(), "eight moves in the pool")
	check_eq(c.resolve_loadout([]), VENOMOUS, "the default loadout is Venomous")
	check_eq((c.loadouts["swamp"] as Dictionary)["moves"], SWAMP, "Swamp is the second build")
	var shared := VENOMOUS.filter(func(x) -> bool: return SWAMP.has(x))
	check_eq(shared, ["venom_fangs"], "the two builds share only the basic strike")
	check_eq((c.pool["venom_fangs"] as PoolMove).string, ["l1", "l2", "l3", "finisher"], "Venom Fangs walks the Classic string")
	check_eq((c.pool["sludge_lob"] as PoolMove).charges, 2, "Sludge Lob keeps its two charges")
	check((c.pool["tail_sweep"] as PoolMove).hold == "charge" and (c.pool["acid_spray"] as PoolMove).hold == "sustain", "hold types")
	# every drill (style) patch lands on a real field, and the drilled Slurry still parses
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://content/core/creatures/f_slurry.json"))
	for id in POOL:
		var pm2: PoolMove = c.pool[id]
		for sid in pm2.styles:
			var drilled: Dictionary = (raw as Dictionary).duplicate(true)
			var res := ContentPatch.apply_all(drilled, (pm2.styles[sid] as Dictionary)["patch"])
			check((res["unmatched"] as Array).is_empty(), "%s / %s: every patch hits a field (missed %s)" % [id, sid, str(res["unmatched"])])
			var cd := CreatureDef.from_dict(drilled)
			check(cd.is_valid(), "%s / %s: the drilled creature parses (%s)" % [id, sid, str(cd.errors)])


func test_poison_darts_burst_stick_and_gunk() -> void:
	var sim := duel("f_slurry", VENOMOUS, "f_dredge", 4.0)
	await step_sim(sim, 0.4)
	var s := sim.fighters[0]
	var d := sim.fighters[1]
	s.input.press(FighterInput.HEAVY)                # Move 2 = Poison Darts
	await step_sim(sim, 0.26)
	s.input.set_held(FighterInput.HEAVY, false)
	check(not pool_entities(sim, "poison_darts", "projectile").is_empty(), "a dart is in the air")
	await step_sim(sim, 0.9)
	var shots := pool_events(sim, "effect", "poison_darts").filter(func(e: Dictionary) -> bool: return str(e["effect"]) == "projectile")
	check_eq(shots.size(), 3, "three darts in one burst")
	if shots.size() == 3:
		var gap := int(shots[2]["tick"]) - int(shots[0]["tick"])
		check(gap >= 28 and gap <= 30, "spat 0.12 s apart (%d ticks for two gaps)" % gap)
	var hits := pool_events(sim, "hit", "poison_darts")
	check(hits.size() >= 2, "the darts land (%d)" % hits.size())
	check(not hits.is_empty() and str(hits[0].get("cat", "")) == "volley", "attributed to the volley")
	check(pool_damage(sim, "poison_darts") > 4.0 and pool_damage(sim, "poison_darts") < 10.0, "a poke (%.1f)" % pool_damage(sim, "poison_darts"))
	check(d.statuses.has("slurry_venom_dart"), "a dart sticks")
	var gunk := float(d.statuses.buildup.get("sludge", 0.0))
	check(gunk >= 45.0 or d.statuses.has_element("sludge"), "and the burst builds Gunked (%.0f)" % gunk)
	# a stuck dart feeds Gunked to every later hit
	var before := float(d.statuses.buildup.get("sludge", 0.0))
	sim.effects.effect_hit(s, d, {"damage": 1.0, "stun": 0.0, "poise": 0.0}, s.pos())
	check(float(d.statuses.buildup.get("sludge", 0.0)) >= before + 5.9, "a hit while a dart sticks builds 6 more Gunked")
	# parryable: a guard raised just before a dart arrives swats it and staggers Slurry
	var sim2 := duel("f_slurry", VENOMOUS, "f_dredge", 4.0)
	await step_sim(sim2, 0.4)
	var s2 := sim2.fighters[0]
	var d2 := sim2.fighters[1]
	s2.input.press(FighterInput.HEAVY)
	await step_sim(sim2, 2.0 * DT)
	s2.input.set_held(FighterInput.HEAVY, false)
	var raised := false
	for k in 60:
		if not raised:
			for ent in pool_entities(sim2, "poison_darts", "projectile"):
				if Vector3(ent["pos"]).distance_to(d2.pos()) < 2.4:
					d2.input.press(FighterInput.GUARD)
					raised = true
					break
		await step_sim(sim2, DT)
	var parried := pool_events(sim2, "hit", "poison_darts").filter(func(e: Dictionary) -> bool: return bool(e.get("parried", false)))
	check(not parried.is_empty(), "a dart can be parried")
	var shots2 := pool_events(sim2, "effect", "poison_darts").filter(func(e: Dictionary) -> bool: return str(e["effect"]) == "projectile")
	check(shots2.size() < 3, "the parry staggers Slurry out of the rest of the burst (%d spat)" % shots2.size())


func test_acid_spray_hoses_while_held_and_gunks_fast() -> void:
	var sim := duel("f_slurry", SWAMP, "f_dredge", 1.5)
	await step_sim(sim, 0.4)
	var s := sim.fighters[0]
	var d := sim.fighters[1]
	var st0 := s.stamina
	s.input.press(FighterInput.HEAVY)                # Move 2 = Acid Spray, held
	await step_sim(sim, 1.5)
	check(s.sustaining, "it keeps pouring while held")
	var cones := _acid_cones(sim)
	check(cones.size() >= 8, "the cone fires every 0.15 s while held (%d)" % cones.size())
	check(not cones.is_empty() and is_equal_approx(float(cones[0]["cone_deg"]), 80.0) and is_equal_approx(float(cones[0]["radius"]), 2.0),
		"a short, wide cone: 80 degrees, 2 m")
	check(d.statuses.has_element("sludge"), "the target is Gunked within a second and a half")
	check(d.statuses.has("slurry_corroded"), "and Corroded")
	check(is_equal_approx(d.statuses.mult("poise_regen"), 0.0), "a Corroded fighter recovers no poise")
	check(s.stamina < st0 - 15.0, "holding drains stamina (%.0f -> %.0f)" % [st0, s.stamina])
	s.input.set_held(FighterInput.HEAVY, false)
	await step_sim(sim, 0.1)
	check(not s.sustaining, "releasing stops it")
	var n := _acid_cones(sim).size()
	await step_sim(sim, 0.6)
	check_eq(_acid_cones(sim).size(), n, "no more acid after the release")
	var hits := pool_events(sim, "hit", "acid_spray")
	check(not hits.is_empty() and str(hits[0].get("cat", "")) == "stream", "its hits are attributed to the stream")
	check(pool_damage(sim, "acid_spray") > 8.0, "it burns (%.1f)" % pool_damage(sim, "acid_spray"))
	# the stick swings the spray at its own turn rate: it sweeps, it does not snap round
	var sim2 := duel("f_slurry", SWAMP, "f_dredge", 1.5)
	await step_sim(sim2, 0.4)
	var s2 := sim2.fighters[0]
	var yaw0 := s2.facing_yaw
	s2.input.press(FighterInput.HEAVY)
	s2.input.move = Vector3(1, 0, 0)
	await step_sim(sim2, 0.45)
	var swept := absf(MathX.wrap_angle(s2.facing_yaw - yaw0))
	check(swept > 0.3 and swept < 1.05, "the stick swings it at 2.6 rad/s (%.2f rad in 0.45 s)" % swept)
	s2.input.set_held(FighterInput.HEAVY, false)
	s2.input.move = Vector3.ZERO
	await step_sim(sim2, 0.5)


func _acid_cones(sim: MatchSim) -> Array:
	return pool_events(sim, "effect", "acid_spray").filter(func(e: Dictionary) -> bool: return str(e["effect"]) == "area")


func test_coil_crush_ignores_guard_holds_and_crushes() -> void:
	var sim := duel("f_slurry", SWAMP, "f_dredge", 1.7)
	await step_sim(sim, 0.4)
	var s := sim.fighters[0]
	var d := sim.fighters[1]
	d.input.press(FighterInput.GUARD)                # Dredge turtles up
	await step_sim(sim, 0.2)
	check_eq(d.state, Fighter.State.GUARD, "Dredge is guarding")
	var hp := d.health
	s.input.press(FighterInput.AB1)                  # Move 3 = Coil Crush
	await step_sim(sim, 2.0 * DT)
	s.input.set_held(FighterInput.AB1, false)
	await step_sim(sim, 0.55)
	check(d.statuses.has("slurry_coiled"), "the lunge wraps the guarding fighter: Coiled")
	check(d.state != Fighter.State.GUARD and not d.guard_held, "a coiled fighter cannot guard")
	check(d.statuses.flag("no_dodge"), "or dodge")
	await step_sim(sim, 1.0)
	var hits := pool_events(sim, "hit", "coil_crush")
	check(hits.size() >= 4, "the wrap, the squeezes and the crush land (%d)" % hits.size())
	check(hits.all(func(e: Dictionary) -> bool: return not bool(e.get("blocked", false))), "none of it is blocked")
	check(not hits.is_empty() and str(hits[0].get("cat", "")) == "strike" and bool(hits[0].get("melee", false)), "the wrap is a strike")
	var squeezes := pool_events(sim, "effect", "coil_crush").filter(func(e: Dictionary) -> bool: return str(e.get("vfx", "")) == "slurry_coil_squeeze")
	check_eq(squeezes.size(), 3, "three squeezes")
	var crush := pool_events(sim, "effect", "coil_crush").filter(func(e: Dictionary) -> bool: return str(e.get("vfx", "")) == "slurry_coil_crush")
	check_eq(crush.size(), 1, "then the crush")
	check(hp - d.health > 8.0, "it hurts (%.1f)" % (hp - d.health))
	check(float(d.statuses.buildup.get("sludge", 0.0)) > 30.0 or d.statuses.has_element("sludge"), "and Gunks")
	# a whiff: out of reach the lunge catches nothing and Slurry is left in its long recovery
	var sim2 := duel("f_slurry", SWAMP, "f_dredge", 4.5)
	await step_sim(sim2, 0.4)
	var s2 := sim2.fighters[0]
	s2.input.press(FighterInput.AB1)
	await step_sim(sim2, 0.9)
	check(pool_events(sim2, "hit", "coil_crush").is_empty(), "out of reach it catches nothing")
	check_eq(s2.move_pool_id, "coil_crush", "and Slurry is still committed to it")
	check(not sim2.fighters[1].statuses.has("slurry_coiled"), "nobody is coiled")
	await step_sim(sim2, 0.6)


func test_shed_skin_cleanses_evades_and_slips_back() -> void:
	var sim := duel("f_slurry", SWAMP, "f_dredge", 1.6)
	await step_sim(sim, 0.4)
	var s := sim.fighters[0]
	var d := sim.fighters[1]
	s.statuses.add_buildup("scorch", 150.0, d)       # Sizzling
	s.statuses.add_buildup("static", 40.0, d)
	check(s.statuses.has_element("scorch"), "Slurry is Sizzling")
	var z0 := s.pos().z
	s.input.press(FighterInput.AB2)                  # Move 4 = Shed Skin
	await step_sim(sim, 0.2)
	s.input.set_held(FighterInput.AB2, false)
	check(s.is_evading(), "nothing can touch it while it slips out")
	await step_sim(sim, 0.5)
	check(not s.statuses.has_element("scorch"), "the Sizzle is washed off")
	check(float(s.statuses.buildup.get("static", 0.0)) <= 0.0, "and the build-up")
	check(s.statuses.has("slurry_fresh_scales"), "fresh scales")
	check(s.pos().z < z0 - 0.5, "it slides back out of its skin (%.2f m)" % (z0 - s.pos().z))
	var fx := pool_events(sim, "effect", "shed_skin")
	check(fx.any(func(e: Dictionary) -> bool: return str(e.get("effect", "")) == "cleanse"), "the cleanse is attributed to Shed Skin")
	var used := pool_events(sim, "ability", "shed_skin")
	check(not used.is_empty() and str(used[0].get("cat", "")) == "support", "a support move")
	# the fresh scales take half build-up while they last
	s.statuses.add_buildup("brine", 40.0, d)
	check_near(float(s.statuses.buildup.get("brine", 0.0)), 20.0, 0.5, "fresh scales halve build-up")
	await step_sim(sim, 2.2)
	check(not s.statuses.has("slurry_fresh_scales"), "for 2.5 seconds")


func test_venom_fangs_lob_and_dive_carry_over() -> void:
	var sim := duel("f_slurry", VENOMOUS, "f_dredge", 1.3)
	await step_sim(sim, 0.4)
	var s := sim.fighters[0]
	for wait in [0.3, 0.46, 0.3, 0.7]:
		s.input.press(FighterInput.LIGHT)            # Move 1 = Venom Fangs, pressed again in each cancel window
		await step_sim(sim, 2.0 * DT)
		s.input.set_held(FighterInput.LIGHT, false)
		await step_sim(sim, float(wait))
	var steps := pool_events(sim, "move_start", "venom_fangs").map(func(e: Dictionary) -> String: return str(e.get("slot", "")))
	check_eq(steps, ["l1", "l2", "l3", "finisher"], "Venom Fangs walks its string into the Venom Spit")
	await step_sim(sim, 0.3)
	s.input.press(FighterInput.AB1)                  # Move 3 = Sludge Lob
	await step_sim(sim, 0.35)
	s.input.set_held(FighterInput.AB1, false)
	var lob := pool_events(sim, "effect", "sludge_lob")
	check(not lob.is_empty() and str(lob[0].get("vfx", "")) == "glob", "Sludge Lob throws its v0.9.17 glob")
	check_eq(int(s.charges_left.get("m3", 0)), 1, "one of its two charges is spent")
	var thrown := pool_events(sim, "ability", "sludge_lob")
	check(not thrown.is_empty() and str(thrown[0].get("cat", "")) == "projectile", "attributed to the projectile move")
	await step_sim(sim, 0.8)
	s.input.press(FighterInput.AB2)                  # Move 4 = Drain Dive
	await step_sim(sim, 0.4)
	s.input.set_held(FighterInput.AB2, false)
	check(s.is_evading(), "Drain Dive: untouchable under the floor")
	var dive := sim.events.filter(func(e: Dictionary) -> bool: return str(e.get("type", "")) == "submerge" and int(e.get("fighter", -1)) == 0)
	check(not dive.is_empty(), "it submerges")
	await step_sim(sim, 0.8)


func test_tail_sweep_charges_into_rear_and_crash() -> void:
	var sim := duel("f_slurry", ["venom_fangs", "tail_sweep"], "f_dredge", 1.6)
	await step_sim(sim, 0.4)
	var s := sim.fighters[0]
	s.input.press(FighterInput.HEAVY)                # Move 2 = Tail Sweep, held
	await step_sim(sim, 1.3)
	check(s.move_charge > 0.5, "holding rears up (%.2f)" % s.move_charge)
	s.input.set_held(FighterInput.HEAVY, false)
	await step_sim(sim, 0.1)
	check_eq(s.move_slot, "heavy_charged", "release: Rear & Crash")
	await step_sim(sim, 1.2)
	check(not pool_events(sim, "hit", "tail_sweep").is_empty(), "the crash lands, attributed to Tail Sweep")


# ---- the effects kit (headless) ---------------------------------------------------------------------

func _fx(views: Array) -> AbilityVfx:
	var fx := AbilityVfx.new()
	fx.view_of = func(i: int): return views[i] if i >= 0 and i < views.size() else null
	fx.info_of = func(i: int) -> Dictionary:
		if i < 0 or i >= views.size():
			return {}
		return {"ground": _ground_at.get(i, Vector3(i * 2.0, 0, 0)), "yaw": 0.0, "state": int(_state.get(i, Fighter.State.ABILITY)),
			"juiced": false, "hidden": false, "charge": -1.0, "out": false}
	fx.fighter_count = func() -> int: return views.size()
	add_child(fx)
	return fx


func _views(ids: Array) -> Array:
	var out := []
	for id in ids:
		var v := CreatureView.new()
		add_child(v)
		v.setup(Content.creature(str(id)))
		out.append(v)
	return out


func _free(fx: AbilityVfx, views: Array) -> void:
	fx.queue_free()
	for v in views:
		(v as Node).queue_free()


## Moves every segment of a view by `by` (as if its fighter had stepped there).
func _shift(v: CreatureView, by: Vector3) -> void:
	var xf: Array[Transform3D] = []
	for i in v.body.segments.size():
		xf.append(v.segment_world(i).translated(by))
	v.snap_transforms(xf)


func test_effects_kit_is_registered_under_its_names() -> void:
	var views := _views(["f_slurry", "f_dredge"])
	var fx := _fx(views)
	var kit = fx.moves.kits.get("f_slurry")
	check(kit != null, "Slurry's kit is loaded")
	for v in KIT_VFX:
		check(fx.moves.by_vfx.get(v) == kit, "the kit draws '%s'" % v)
	for v in ["glob", "spit", "drain", "wave", "slurp", "sludge_puddle", "zone", "area"]:
		check(not fx.moves.by_vfx.has(v), "the shared look '%s' is not taken over" % v)
	var c := Content.creature("f_slurry")
	for id in ["poison_darts", "acid_spray", "coil_crush", "shed_skin"]:
		for e in (c.pool[id] as PoolMove).move.effects:
			var vfx := str((e as Dictionary).get("vfx", ""))
			check(KIT_VFX.has(vfx), "%s: its '%s' effect is drawn by the kit" % [id, vfx])
	_free(fx, views)


func test_darts_fly_stick_ride_and_clean_up() -> void:
	var views := _views(["f_slurry", "f_dredge"])
	var fx := _fx(views)
	var kit = fx.moves.kits["f_slurry"]
	var ent := {"id": 1, "kind": "projectile", "vfx": "slurry_dart", "pos": Vector3(0, 1.4, 0.4), "radius": 0.1, "element": "sludge", "team": 0}
	fx.sync_entities([ent])
	check(fx._ents.has(1), "a dart is drawn by the kit")
	var dart: Node3D = (fx._ents[1] as Dictionary)["node"]
	check(not dart.visible, "hidden until its first step gives it a heading")
	var ent2 := ent.duplicate()
	ent2["pos"] = Vector3(0.5, 1.3, 0.4)
	fx.sync_entities([ent2])
	check(dart.visible and dart.global_position.is_equal_approx(Vector3(0.5, 1.3, 0.4)), "it flies with its projectile")
	check(dart.global_basis.z.dot(-Vector3(0.5, -0.1, 0.0).normalized()) > 0.99, "nose first")
	fx.sync_entities([])
	await wait_frames(4)
	check(not is_instance_valid(dart), "a dart that is gone is cleaned up")
	# landed darts stick in Dredge (at most three at once), ride him and work loose
	var hit := {"type": "hit", "fighter": 0, "target": 1, "pool": "poison_darts", "cat": "volley", "damage": 2.6, "point": Vector3(2, 0.9, 0),
		"normal": Vector3.UP, "blocked": false, "parried": false, "element": "sludge"}
	for k in 4:
		fx.on_event(hit)
	var stuck: Array = kit._stuck
	check_eq(stuck.size(), 4, "each landed dart sticks")
	check_eq(stuck.filter(func(st: Dictionary) -> bool: return float(st["age"]) < 2.5).size(), 3, "three at most stay (the oldest works loose)")
	var parried := hit.duplicate()
	parried["parried"] = true
	fx.on_event(parried)
	check_eq((kit._stuck as Array).size(), 4, "a parried dart does not stick")
	var newest: Node3D = (stuck[3] as Dictionary)["node"]
	var p0 := newest.global_position
	_shift(views[1], Vector3(0, 0, 1))
	await wait_frames(2)
	check(newest.global_position.distance_to(p0 + Vector3(0, 0, 1)) < 0.01, "a stuck dart rides its victim")
	fx.quality = 0
	fx.sync_entities([ent])
	check(fx._ents.has(1), "at Low quality the dart (a combat cue) is still drawn")
	fx.sync_entities([])
	await wait_frames(int(3.0 * Engine.physics_ticks_per_second))
	check((kit._stuck as Array).is_empty() and not is_instance_valid(newest), "the stuck darts work loose and are cleaned up")
	_free(fx, views)


func test_acid_spray_lives_while_sustained_and_dies_with_the_move() -> void:
	var views := _views(["f_slurry", "f_dredge"])
	var fx := _fx(views)
	var kit = fx.moves.kits["f_slurry"]
	var start := {"type": "sustain", "fighter": 0, "phase": "start", "pool": "acid_spray", "slot": "m2"}
	var stop := {"type": "sustain", "fighter": 0, "phase": "end", "pool": "acid_spray", "slot": "m2"}
	fx.on_event(start)
	check((kit._sprays as Dictionary).has(0), "a sustain start opens the spray")
	for k in 4:
		fx.on_event({"type": "effect", "fighter": 0, "effect": "area", "vfx": "slurry_acid", "pool": "acid_spray", "pos": Vector3.ZERO,
			"origin": Vector3.ZERO, "radius": 2.0, "cone_deg": 80.0, "shape": "cone", "yaw": 0.0, "element": "sludge"})
		await wait_frames(6)
	var sp: Dictionary = kit._sprays.get(0, {})
	check(not sp.is_empty() and float(sp.get("len", 0.0)) > 1.2, "it gushes out toward its reach (%s)" % str(sp.get("len", 0)))
	if sp.is_empty():
		_free(fx, views)
		return
	var mi: MeshInstance3D = sp["node"]
	var half := mi.global_transform.basis.x.length()
	check(absf(half - float(sp["len"]) * tan(deg_to_rad(40.0))) < float(sp["len"]) * 0.1, "its fan is as wide as the 80 degree cone (%.2f m)" % half)
	fx.on_event(stop)
	await wait_frames(30)
	check(not (kit._sprays as Dictionary).has(0) and not is_instance_valid(mi), "releasing ends it")
	# cut off: a hit stuns Slurry mid-spray (no end event reaches the effects first)
	fx.on_event(start)
	await wait_frames(4)
	_state[0] = Fighter.State.HITSTUN
	await wait_frames(30)
	check(not (kit._sprays as Dictionary).has(0), "an interrupted spray dies with the move")
	_state.erase(0)
	# Reduce flashing dims it
	fx.reduce_flashes = true
	fx.on_event(start)
	await wait_frames(20)
	var sp2: Dictionary = kit._sprays.get(0, {})
	check(not sp2.is_empty() and float((sp2["mat"] as ShaderMaterial).get_shader_parameter("alpha")) <= 0.76, "Reduce flashing dims the acid")
	fx.on_event(stop)
	await wait_frames(30)
	_free(fx, views)


func test_coils_wind_on_squeeze_crush_and_let_go() -> void:
	var views := _views(["f_slurry", "f_dredge"])
	var fx := _fx(views)
	var kit = fx.moves.kits["f_slurry"]
	var wrap := {"type": "hit", "fighter": 0, "target": 1, "pool": "coil_crush", "cat": "strike", "damage": 4.0, "point": Vector3(2, 0.7, 0),
		"normal": Vector3.UP, "blocked": false, "parried": false, "element": "sludge", "melee": true}
	var squeeze := {"type": "effect", "fighter": 0, "effect": "area", "vfx": "slurry_coil_squeeze", "pool": "coil_crush", "pos": Vector3(1.6, 0, 0),
		"radius": 0.8, "shape": "circle", "yaw": 0.0, "element": "sludge"}
	var crush := squeeze.duplicate()
	crush["vfx"] = "slurry_coil_crush"
	crush["radius"] = 0.85
	fx.on_event(wrap)
	check((kit._coils as Dictionary).has(0), "the wrap winds coils round the victim")
	var c: Dictionary = kit._coils.get(0, {})
	if c.is_empty():
		_free(fx, views)
		return
	var root: Node3D = c["node"]
	var mi: MeshInstance3D = c["mesh"]
	check_eq(int(c["victim"]), 1, "round the fighter it caught")
	await wait_frames(24)
	check(root.global_position.is_equal_approx(Vector3(2, 0, 0)), "at its feet")
	var r0 := mi.scale.x
	check(r0 > 0.8, "wide enough to wrap a crab's shell (%.2f m)" % r0)
	fx.on_event(squeeze)
	await wait_frames(12)
	check(mi.scale.x < r0 * 0.9, "a squeeze clenches the coils (%.2f)" % mi.scale.x)
	await wait_frames(30)
	check(absf(mi.scale.x - r0) < 0.02, "and they relax")
	_ground_at[1] = Vector3(2, 0, 1)
	await wait_frames(2)
	check(root.global_position.is_equal_approx(Vector3(2, 0, 1)), "the coils ride their victim")
	fx.on_event(crush)
	await wait_frames(40)
	check(not (kit._coils as Dictionary).has(0) and not is_instance_valid(root), "the crush flings them apart")
	# cut off: knocked out of the move, Slurry lets go
	fx.on_event(wrap)
	var root2: Node3D = (kit._coils[0] as Dictionary)["node"]
	_state[0] = Fighter.State.HITSTUN
	await wait_frames(40)
	check(not is_instance_valid(root2), "interrupted, it lets go")
	_state.erase(0)
	# a whiffed squeeze and crush draw without coils
	fx.on_event(squeeze)
	fx.on_event(crush)
	await wait_frames(4)
	check(not (kit._coils as Dictionary).has(0), "a whiff winds nothing")
	_free(fx, views)


func test_shed_skin_leaves_a_husk_that_flakes_away() -> void:
	var views := _views(["f_slurry", "f_dredge"])
	var fx := _fx(views)
	var kit = fx.moves.kits["f_slurry"]
	var shed := {"type": "effect", "fighter": 0, "effect": "cleanse", "vfx": "slurry_shed_skin", "pool": "shed_skin", "pos": Vector3.ZERO,
		"radius": 0.0, "shape": "circle", "yaw": 0.0, "element": ""}
	fx.on_event(shed)
	check_eq((kit._husks as Array).size(), 1, "the old skin is left standing")
	var parts := 0
	for s: BodyDef.Seg in Content.creature("f_slurry").body.segments:
		parts += s.shapes.size()
	if (kit._husks as Array).is_empty():
		_free(fx, views)
		return
	var husk: Node3D = kit._husks[0]
	check_eq(husk.get_child_count(), parts, "a shell over every body part")
	fx.on_event({"type": "effect", "fighter": 0, "effect": "dash", "vfx": "slurry_shed_slip", "pool": "shed_skin", "pos": Vector3.ZERO,
		"radius": 0.0, "shape": "circle", "yaw": 0.0, "element": "", "dir": Vector3(0, 0, -1)})
	fx.on_event({"type": "effect", "fighter": 0, "effect": "buff", "vfx": "slurry_fresh_scales", "pool": "shed_skin", "pos": Vector3.ZERO,
		"radius": 0.0, "shape": "circle", "yaw": 0.0, "element": ""})
	fx.on_event({"type": "effect", "fighter": 0, "effect": "area", "vfx": "slurry_molt_burst", "pool": "shed_skin", "pos": Vector3.ZERO,
		"radius": 1.1, "shape": "circle", "yaw": 0.0, "element": "sludge"})
	await wait_frames(int(1.6 * Engine.physics_ticks_per_second))
	check(not is_instance_valid(husk) and (kit._husks as Array).is_empty(), "it sags and flakes away")
	fx.quality = 0
	fx.on_event(shed)
	check_eq((kit._husks as Array).size(), 1, "at Low quality the husk is still drawn")
	_free(fx, views)
