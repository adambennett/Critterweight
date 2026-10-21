extends MovesKitCase
## Dozer's v0.9.18 move pool (docs/kits/f_dozer.md "Movesets", docs/design/MOVESET_COMBAT.md §4):
## every move does what its description says, in Movesets, against a standing Dredge; Classic still
## plays the v0.9.17 kit; every style patches real fields (two of them are played); the effects kit
## (src/view/fx/moves/f_dozer.gd) draws and cleans up its moves headless.

const BULLDOZER := ["snout_jab", "rock_slide", "bulldoze", "dust_bowl"]
const QUARRY := ["snout_jab", "quake_stomp", "boulder_toss", "iron_hide"]
const POOL := ["snout_jab", "horn_lunge", "bulldoze", "dust_bowl", "rock_slide", "boulder_toss", "quake_stomp", "iron_hide"]
const VFX := ["dozer_rockslide", "dozer_rockslide_rock", "dozer_scree", "dozer_boulder", "dozer_boulder_shatter",
	"dozer_quake", "dozer_aftershock", "dozer_iron_hide", "dozer_spikes"]
## Leaf fields a style may create (set on a field the move does not have yet): each is read by the
## engine (MoveDef, PoolMove, EffectsSystem, StatusSet), so a misspelling cannot hide here.
const CREATABLE := ["armor", "armor_level", "on_hit", "speed", "hooks", "armor_all", "count", "spread_deg", "bounce",
	"hold", "charge_time", "charge_at", "charge_scale", "kb_dir"]

var _state := {}         ## effects test: fighter -> Fighter.State the info callable reports


## Effect events of a pool move with one effect type.
func _effects(sim: MatchSim, pool: String, effect: String) -> Array:
	return pool_events(sim, "effect", pool).filter(func(e: Dictionary) -> bool: return str(e.get("effect", "")) == effect)


## Knockdowns of fighter `victim` caused by fighter `by`.
func _knockdowns(sim: MatchSim, victim: int, by := 0) -> Array:
	return sim.events.filter(func(e: Dictionary) -> bool:
		return str(e.get("type", "")) == "knockdown" and int(e.get("fighter", -1)) == victim and int(e.get("by", -1)) == by)


## Dozer with drilled styles {pool move id: style id}: the patches a run or a career applies.
func _styled(styles: Dictionary) -> CreatureDef:
	var d: Dictionary = Content.creature_entry("f_dozer").duplicate(true)
	d["id"] = "t_dozer_styled"
	var pool: Dictionary = d["movepool"]
	for mid in styles:
		var entry: Dictionary = pool[mid]
		var sts: Dictionary = entry["styles"]
		var st: Dictionary = sts[styles[mid]]
		var patch: Array = st["patch"]
		ContentPatch.apply_all(d, patch)
	return CreatureDef.from_dict(d, Callable(), "test")


## MovesKitCase.duel for a creature built here (a styled Dozer) against a standing Dredge.
func _duel_with(c: CreatureDef, loadout: Array, gap: float) -> MatchSim:
	check(c.is_valid(), "the styled Dozer parses: %s" % str(c.errors))
	var arena := ArenaDef.from_dict({"id": "t", "base": "octagon", "radius": 7.0, "spawns": [[0, -gap * 0.5, 0], [0, gap * 0.5, 180]]})
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	sim.setup({"arena": arena, "rules": {"rounds": 1, "round_time": 0, "intro_time": 0.2, "combat": "moves"}, "seed": 7, "fighters": [
		{"creature": c, "team": 0, "source": null, "loadout": loadout},
		{"creature": Content.creature("f_dredge"), "team": 1, "source": null}]})
	return sim


func test_pool_and_loadouts() -> void:
	var c := Content.creature("f_dozer")
	for id in POOL:
		check_pool_move("f_dozer", id)
	check_eq(c.pool.size(), 8, "eight moves in the pool")
	check_eq(c.resolve_loadout([]), BULLDOZER, "the default loadout is Bulldozer")
	check_eq((c.loadouts["quarry"] as Dictionary)["moves"], QUARRY, "Quarry is the second build")
	var shared := BULLDOZER.filter(func(x) -> bool: return QUARRY.has(x))
	check_eq(shared, ["snout_jab"], "the two builds share only the basic strike")
	var cats := {}
	for id in POOL:
		cats[id] = (c.pool[id] as PoolMove).category
	check_eq(cats, {"snout_jab": "strike", "horn_lunge": "strike", "bulldoze": "rush", "dust_bowl": "control",
		"rock_slide": "control", "boulder_toss": "projectile", "quake_stomp": "blast", "iron_hide": "support"}, "the categories of §4")
	var basic: PoolMove = c.pool["snout_jab"]
	check(basic.string == ["l1", "l2", "l3", "finisher"] and basic.dash == "dash_attack", "the basic string walks into the Gravel Toss")
	var heavy: PoolMove = c.pool["horn_lunge"]
	check(heavy.role == "heavy" and heavy.hold == "charge" and heavy.charged != null, "Horn Lunge charges into the Quarry Ram")
	check((c.pool["bulldoze"] as PoolMove).answers_slot("ability1") and (c.pool["dust_bowl"] as PoolMove).answers_slot("ability2"),
		"the v0.9.17 abilities keep their slots")
	for id in ["rock_slide", "boulder_toss", "quake_stomp", "iron_hide"]:
		var pm: PoolMove = c.pool[id]
		check(pm.cooldown >= 4.0 and pm.cooldown <= 12.0 and pm.stamina_cost() > 0.0, "%s has a real cooldown and costs stamina" % id)
		check(pm.element == "grit" and not pm.ai.is_empty(), "%s is a Grit move with bot hints" % id)


func test_rock_slide_erupts_launches_and_raises_cover() -> void:
	var sim := duel("f_dozer", BULLDOZER, "f_dredge", 2.6)
	await step_sim(sim, 0.4)
	var s := sim.fighters[0]
	var d := sim.fighters[1]
	var hp := d.health
	var y0 := d.pos().y
	s.input.press(FighterInput.HEAVY)                  # Move 2 = Rock Slide
	await step_sim(sim, 2.0 * DT)
	s.input.set_held(FighterInput.HEAVY, false)
	var peak := y0
	var fastest := 0.0
	for k in 160:                                      # the eruption (0.30 s), the boulders (0.44-0.54 s) and after
		await step_sim(sim, DT)
		peak = maxf(peak, d.pos().y)
		if k > 50:
			fastest = maxf(fastest, d.rig.com_velocity().length())
	var line := _effects(sim, "rock_slide", "area")
	check(line.size() == 1 and str(line[0].get("shape", "")) == "line" and float(line[0].get("length", 0.0)) >= 5.0,
		"a five-metre fault line erupts (%s)" % str(line))
	var hits := pool_events(sim, "hit", "rock_slide")
	check(not hits.is_empty() and d.health < hp, "it hits the fighter standing on it (%.1f)" % pool_damage(sim, "rock_slide"))
	check(not hits.is_empty() and str(hits[0].get("cat", "")) == "control", "attributed to the control move")
	check(peak > y0 + 0.25, "and knocks it up (%.2f m)" % (peak - y0))
	check(d.statuses.has_element("grit") or float(d.statuses.buildup.get("grit", 0.0)) > 0.0, "and builds Caked")
	check_eq(pool_entities(sim, "rock_slide", "prop").size(), 3, "three boulders rise along the crack")
	check(fastest < 9.0, "a boulder rising under a fighter shoves it off, never flings it (%.1f m/s)" % fastest)
	check(sim.arena.inside(d.pos(), 0.0), "and it stays in the cage")
	await step_sim(sim, 3.0)
	check(pool_entities(sim, "rock_slide", "prop").is_empty(), "the boulders crumble after three seconds")


func test_rock_slide_boulders_stop_shots_for_three_seconds() -> void:
	var sim := duel("f_dozer", BULLDOZER, "f_dredge", 7.0)
	await step_sim(sim, 0.4)
	var s := sim.fighters[0]
	var d := sim.fighters[1]
	await use_slot(sim, 0, 1, 0.0, 0.7)                # Move 2 = Rock Slide: the boulders stand by 0.54 s
	check_eq(pool_entities(sim, "rock_slide", "prop").size(), 3, "three boulders stand between them")
	check(pool_events(sim, "hit", "rock_slide").is_empty(), "a fighter beyond the line is not hit")
	var shot := {"type": "projectile", "speed": 11.0, "offset": [0, 0.6, 0.6], "radius": 0.2, "life": 1.5,
		"damage": 6.0, "knockback": 2.0, "stun": 0.2, "element": "brine"}
	var hp := s.health
	sim.effects.fire(d, shot)                          # Dredge shoots straight down the line at Dozer
	await step_sim(sim, 1.0)
	check(is_equal_approx(s.health, hp), "the boulders stop the shot (%.1f -> %.1f)" % [hp, s.health])
	var chipped := pool_entities(sim, "rock_slide", "prop").filter(func(ent: Dictionary) -> bool: return float(ent["hp"]) < 24.0)
	check_eq(chipped.size(), 1, "the boulder it struck is chipped")
	await step_sim(sim, 2.2)                           # three seconds after they rose
	check(pool_entities(sim, "rock_slide", "prop").is_empty(), "the cover is gone after three seconds")
	sim.effects.fire(d, shot)
	await step_sim(sim, 1.0)
	check(s.health < hp, "and the same shot now lands (%.1f -> %.1f)" % [hp, s.health])


func test_boulder_toss_flies_knocks_down_and_shatters() -> void:
	var sim := duel("f_dozer", QUARRY, "f_dredge", 5.0)
	await step_sim(sim, 0.4)
	await use_slot(sim, 0, 2, 0.0, 0.45)               # Move 3 = Boulder Toss: flung 0.40 s in
	check_eq(pool_entities(sim, "boulder_toss", "projectile").size(), 1, "a boulder is in the air")
	await step_sim(sim, 1.4)
	var hits := pool_events(sim, "hit", "boulder_toss")
	check(hits.size() == 1 and float(hits[0]["damage"]) >= 7.0, "a direct hit lands hard (%s)" % str(hits))
	check(not hits.is_empty() and str(hits[0].get("cat", "")) == "projectile", "attributed to the projectile")
	check(not _knockdowns(sim, 1).is_empty(), "and knocks the fighter down")
	check(_effects(sim, "boulder_toss", "area").is_empty(), "a direct hit does not also shatter on the floor")
	# a fighter who dodges aside while it climbs is missed: it shatters into gravel where he stood
	var miss := duel("f_dozer", QUARRY, "f_dredge", 5.0)
	await step_sim(miss, 0.4)
	var md := miss.fighters[1]
	var spot := md.pos()
	await use_slot(miss, 0, 2, 0.0, 0.45)              # thrown
	md.input.move = Vector3(1, 0, 0)
	md.input.press(FighterInput.DODGE)
	await step_sim(miss, 0.4)
	md.input.move = Vector3.ZERO
	await step_sim(miss, 1.0)
	var shatter := _effects(miss, "boulder_toss", "area")
	check(shatter.size() == 1 and str(shatter[0].get("vfx", "")) == "dozer_boulder_shatter", "a miss shatters where it lands (%s)" % str(shatter))
	if not shatter.is_empty():
		var p: Vector3 = shatter[0]["pos"]
		check(Vector2(p.x - spot.x, p.z - spot.z).length() < 1.2, "on the spot he left (%s, he stood at %s)" % [str(p), str(spot)])
	check(pool_events(miss, "hit", "boulder_toss").is_empty(), "and the dodge saved him (he is %.1f m away)" % md.pos().distance_to(spot))
	check(pool_entities(miss, "boulder_toss").is_empty(), "nothing is left in the air")


func test_quake_stomp_trips_through_a_guard() -> void:
	var sim := duel("f_dozer", QUARRY, "f_dredge", 1.8)
	await step_sim(sim, 0.4)
	var d := sim.fighters[1]
	d.input.set_held(FighterInput.GUARD, true)
	await step_sim(sim, 0.2)
	check(d.state == Fighter.State.GUARD, "Dredge is guarding")
	await use_slot(sim, 0, 1, 0.0, 0.6)                # Move 2 = Quake Stomp: he lands 0.48 s in
	var ring := _effects(sim, "quake_stomp", "area")
	check(ring.size() == 1 and float(ring[0].get("radius", 0.0)) >= 2.4, "a quake ring around him (%s)" % str(ring))
	var hits := pool_events(sim, "hit", "quake_stomp")
	check(not hits.is_empty() and not bool(hits[0].get("blocked", true)), "the guard does not stop it")
	check(not hits.is_empty() and str(hits[0].get("cat", "")) == "blast", "attributed to the blast")
	check(not _knockdowns(sim, 1).is_empty(), "the guarding fighter is tripped")
	d.input.set_held(FighterInput.GUARD, false)
	# a fighter outside the ring keeps its feet
	var far := duel("f_dozer", QUARRY, "f_dredge", 3.4)
	await step_sim(far, 0.4)
	await use_slot(far, 0, 1, 0.0, 0.6)
	check(not _effects(far, "quake_stomp", "area").is_empty(), "the ring goes off")
	check(_knockdowns(far, 1).is_empty() and pool_events(far, "hit", "quake_stomp").is_empty(), "nothing happens beyond 2.4 m")


func test_iron_hide_shrugs_off_light_hits() -> void:
	var sim := duel("f_dozer", QUARRY, "f_dredge", 2.2)
	await step_sim(sim, 0.4)
	var s := sim.fighters[0]
	var d := sim.fighters[1]
	await use_slot(sim, 0, 3, 0.0, 0.8)                # Move 4 = Iron Hide: the plates lock 0.28 s in
	check(s.statuses.has("iron_hide"), "the plates are locked")
	var used := pool_events(sim, "ability", "iron_hide")
	check(not used.is_empty() and str(used[0].get("cat", "")) == "support", "attributed to the support move")
	check(s.statuses.knockback_taken_mult() < 1.0, "blows shove him less")
	var jab := {"damage": 4.0, "stun": 0.4, "poise": 6.0, "knockback": 3.0, "class": "light"}
	sim.effects.effect_hit(d, s, jab, d.pos())
	await step_sim(sim, 0.05)
	check(s.state != Fighter.State.HITSTUN, "a light hit does not stagger him (%s)" % Fighter.STATE_NAMES[s.state])
	var big := jab.duplicate()
	big["class"] = "heavy"
	sim.effects.effect_hit(d, s, big, d.pos())
	await step_sim(sim, 0.05)
	check(s.state == Fighter.State.HITSTUN, "a heavy one still does (%s)" % Fighter.STATE_NAMES[s.state])
	await step_sim(sim, 4.0)
	check(not s.statuses.has("iron_hide"), "it wears off after four seconds")
	sim.effects.effect_hit(d, s, jab, d.pos())
	await step_sim(sim, 0.05)
	check(s.state == Fighter.State.HITSTUN, "and light hits stagger him again (%s)" % Fighter.STATE_NAMES[s.state])


func test_snout_jab_horn_lunge_and_the_v0917_abilities_carry_over() -> void:
	var sim := duel("f_dozer", BULLDOZER, "f_dredge", 1.6)
	await step_sim(sim, 0.4)
	var s := sim.fighters[0]
	s.input.press(FighterInput.LIGHT)                  # Move 1 = Snout Jab
	await step_sim(sim, 2.0 * DT)
	s.input.set_held(FighterInput.LIGHT, false)
	check(s.move_slot == "l1" and s.move_pool_id == "snout_jab", "Move 1 starts the Snout Jab string (%s)" % s.move_slot)
	await step_sim(sim, 1.0)
	await use_slot(sim, 0, 2, 0.0, 2.0)                # Move 3 = Bulldoze
	check(not _effects(sim, "bulldoze", "charge").is_empty(), "Bulldoze charges as in v0.9.17")
	await use_slot(sim, 0, 3, 0.0, 0.6)                # Move 4 = Dust Bowl
	check(s.statuses.has("dust_bowl"), "Dust Bowl raises its cloud and armour")
	check(not _effects(sim, "dust_bowl", "zone").is_empty(), "with its v0.9.17 dust zone")
	# the heavy is in no recommended build: a custom loadout
	var h := duel("f_dozer", ["snout_jab", "horn_lunge"], "f_dredge", 1.6)
	await step_sim(h, 0.4)
	var hs := h.fighters[0]
	hs.input.press(FighterInput.HEAVY)                 # Move 2 = Horn Lunge, held
	await step_sim(h, 1.2)
	check(hs.move_charge > 0.5, "holding winds it up (%.2f)" % hs.move_charge)
	hs.input.set_held(FighterInput.HEAVY, false)
	await step_sim(h, 0.1)
	check_eq(hs.move_slot, "heavy_charged", "release: the Quarry Ram")
	await step_sim(h, 1.4)


func test_classic_is_unchanged() -> void:
	# the pool changes nothing in Classic: the v0.9.17 inputs reach the v0.9.17 moves
	var sim := duel("f_dozer", [], "f_dredge", 1.6, {"combat": "classic"})
	await step_sim(sim, 0.4)
	var s := sim.fighters[0]
	check(s.combat_style == "classic" and s.loadout.is_empty(), "Classic Dozer fights without a loadout")
	var slots: Array = []
	for b in [FighterInput.LIGHT, FighterInput.LIGHT, FighterInput.LIGHT, FighterInput.HEAVY]:
		s.input.press(b)
		await step_sim(sim, 0.03)
		s.input.set_held(b, false)
		slots.append(s.move_slot)
		var guard := 0
		while s.move != null and s.state_time < maxf(s.move.cancel_t0, s.move.last_active()) + 0.02 and guard < 240:
			await step_sim(sim, DT)
			guard += 1
	check_eq(slots, ["l1", "l2", "l3", "finisher"], "Light, Light, Light, Heavy: the string into the Gravel Toss")
	await step_sim(sim, 1.2)
	s.input.press(FighterInput.HEAVY)
	await step_sim(sim, 1.2)
	s.input.set_held(FighterInput.HEAVY, false)
	await step_sim(sim, 0.1)
	check_eq(s.move_slot, "heavy_charged", "a held Heavy is the Quarry Ram")
	await step_sim(sim, 1.6)
	s.input.press(FighterInput.AB2)
	await step_sim(sim, 0.05)
	s.input.set_held(FighterInput.AB2, false)
	check_eq(s.move_slot, "ability2", "Ability 2 is Dust Bowl")
	await step_sim(sim, 0.4)
	check(s.statuses.has("dust_bowl"), "and raises its cloud")
	var tagged := sim.events.filter(func(e: Dictionary) -> bool: return int(e.get("fighter", -1)) == 0 and e.has("pool"))
	check(tagged.is_empty(), "no Classic event carries a Movesets pool move (%d)" % tagged.size())
	s.cooldown_left["ability2"] = 9.0
	s.hooks.run_inline({"do": [{"type": "cooldown", "slot": "ability2", "add": -3.0}]}, {})
	check_near(float(s.cooldown_left["ability2"]), 6.0, 0.001, "cooldown hooks act on the Classic ability slot")
	await step_sim(sim, 0.6)


func test_styles_patch_real_fields() -> void:
	var raw: Dictionary = Content.creature_entry("f_dozer")
	var c := Content.creature("f_dozer")
	var checked := 0
	for id in POOL:
		var pm: PoolMove = c.pool[id]
		for sid in pm.styles:
			var st: Dictionary = pm.styles[sid]
			check(str(st.get("name", "")) != "" and str(st.get("desc", "")).length() > 20, "%s.%s has a name and a description" % [id, sid])
			var d: Dictionary = raw.duplicate(true)
			for p in st.get("patch", []):
				checked += 1
				var err := ContentPatch.validate(p)
				if not check(err == "", "%s.%s: %s" % [id, sid, err]):
					continue
				var path := str(p.get("path", ""))
				var leaf := path.substr(path.rfind(".") + 1)
				if str(p.get("op", "")) == "set" and not leaf.contains("["):
					# a set that creates its field must create one the engine reads ("remove" only
					# matches a field that exists)
					var had := ContentPatch.apply(d.duplicate(true), {"op": "remove", "path": path}) > 0
					check(had or CREATABLE.has(leaf), "%s.%s: set %s creates a field nothing reads" % [id, sid, path])
				check(ContentPatch.apply(d, p) > 0, "%s.%s: %s %s matches nothing" % [id, sid, str(p.get("op", "")), path])
			var styled := CreatureDef.from_dict(d, Callable(), "test")
			check(styled.is_valid(), "%s with %s still parses: %s" % [id, sid, str(styled.errors)])
	check(checked >= 20, "checked %d style patches" % checked)


func test_styles_change_behaviour() -> void:
	# Avalanche: three smaller stones in a fan, none of which knocks down
	var sim := _duel_with(_styled({"boulder_toss": "avalanche"}), QUARRY, 5.0)
	await step_sim(sim, 0.4)
	await use_slot(sim, 0, 2, 0.0, 0.45)
	check_eq(pool_entities(sim, "boulder_toss", "projectile").size(), 3, "Avalanche throws three stones")
	await step_sim(sim, 1.4)
	check(not pool_events(sim, "hit", "boulder_toss").is_empty(), "they land on the fighter")
	check(_knockdowns(sim, 1).is_empty(), "without knocking it down")
	# Seismic Charge: holding hangs at the top of the bound and grows the ring
	var q := _duel_with(_styled({"quake_stomp": "seismic_charge"}), QUARRY, 3.4)
	await step_sim(q, 0.4)
	var s := q.fighters[0]
	s.input.press(FighterInput.HEAVY)                  # Move 2 = Quake Stomp, held
	await step_sim(q, 1.0)
	check(s.move_pool_id == "quake_stomp" and s.move_charge > 0.6, "holding charges the stomp (%.2f)" % s.move_charge)
	s.input.set_held(FighterInput.HEAVY, false)
	await step_sim(q, 0.7)
	var ring := _effects(q, "quake_stomp", "area")
	check(not ring.is_empty() and float(ring[0].get("radius", 0.0)) > 3.0, "the charge widens the ring (%s)" % str(ring))
	check(not _knockdowns(q, 1).is_empty(), "and trips a fighter 3.4 m away")


# =====================================================================================
# Effects kit (headless, like test_move_vfx.gd)
# =====================================================================================

func _fx(views: Array) -> AbilityVfx:
	var fx := AbilityVfx.new()
	fx.view_of = func(i: int): return views[i] if i >= 0 and i < views.size() else null
	fx.info_of = func(i: int) -> Dictionary:
		if i < 0 or i >= views.size():
			return {}
		return {"ground": Vector3(i * 2.5, 0, 0), "yaw": 0.0, "state": int(_state.get(i, Fighter.State.ABILITY)), "juiced": false,
			"hidden": false, "charge": -1.0, "out": false}
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


## Mesh pieces the effects have in the scene (footprints, walls, rocks; pooled emitters excluded).
func _pieces(fx: AbilityVfx) -> int:
	return fx.find_children("*", "MeshInstance3D", true, false).size()


func _effect(vfx: String, effect: String, extra := {}) -> Dictionary:
	var ev := {"type": "effect", "fighter": 0, "effect": effect, "vfx": vfx, "pool": "x", "pos": Vector3(0, 0, 2.0),
		"radius": 1.3, "shape": "circle", "yaw": 0.0, "element": "grit"}
	ev.merge(extra, true)
	return ev


func test_effects_kit_draws_and_cleans_up() -> void:
	var views := _views(["f_dozer", "f_dredge"])
	var fx := _fx(views)
	check(fx.moves != null and fx.moves.kits.has("f_dozer"), "Dozer's kit is loaded")
	var kit = fx.moves.kits.get("f_dozer")
	for v in VFX:
		check(fx.moves.by_vfx.get(v) == kit, "the kit draws '%s'" % v)
	for v in ["gravel_spray", "landslide", "dust_bowl", "boulder", "rubble", "stomp_pulse", "charge"]:
		check(not fx.moves.by_vfx.has(v), "the v0.9.17 look '%s' stays with the v0.9.17 recipes" % v)
	await wait_frames(40)                              # the intro warm-up pieces are gone
	var base := _pieces(fx)
	# Rock Slide: the line telegraph creeps out during the dig and goes when the line erupts
	fx.on_event({"type": "move_start", "fighter": 0, "slot": "m2", "id": "f_dozer.mv.rock_slide", "pool": "rock_slide", "cat": "control"})
	await wait_frames(20)
	check((kit._winds as Dictionary).has(0) and _pieces(fx) > base, "the dig draws its wind-up")
	fx.on_event(_effect("dozer_rockslide", "area", {"shape": "line", "length": 5.0, "width": 1.3, "origin": Vector3.ZERO, "pool": "rock_slide"}))
	check(not (kit._winds as Dictionary).has(0), "the eruption ends the wind-up")
	fx.on_event(_effect("dozer_rockslide_rock", "prop", {"radius": 0.8, "duration": 0.6, "pool": "rock_slide"}))
	check((kit._skirts as Array).size() == 1, "a boulder heaves up with rubble at its foot")
	# Boulder Toss: a rock rides the snout from the dig until the throw, then the projectile takes over
	fx.on_event({"type": "move_start", "fighter": 0, "slot": "m3", "id": "f_dozer.mv.boulder_toss", "pool": "boulder_toss", "cat": "projectile"})
	await wait_frames(50)
	check((kit._held as Dictionary).has(0), "a boulder comes up on the snout")
	fx.on_event(_effect("dozer_boulder", "projectile", {"pool": "boulder_toss"}))
	check(not (kit._held as Dictionary).has(0), "the throw lets go of it")
	fx.sync_entities([{"id": 1, "kind": "projectile", "vfx": "dozer_boulder", "pos": Vector3(0, 1.2, 1.0), "radius": 0.36, "element": "grit", "team": 0},
		{"id": 2, "kind": "zone", "vfx": "dozer_scree", "pos": Vector3(1, 0, 3), "radius": 0.9, "element": "grit", "team": 0}])
	check(fx._ents.has(1) and fx._ents.has(2), "the boulder and a scree patch are drawn")
	var rock: Node3D = (fx._ents[1] as Dictionary)["node"]
	var scree: Node3D = (fx._ents[2] as Dictionary)["node"]
	fx.sync_entities([{"id": 1, "kind": "projectile", "vfx": "dozer_boulder", "pos": Vector3(0, 1.6, 2.0), "radius": 0.36, "element": "grit", "team": 0},
		{"id": 2, "kind": "zone", "vfx": "dozer_scree", "pos": Vector3(1, 0, 3), "radius": 0.9, "element": "grit", "team": 0}])
	check(rock.global_position.is_equal_approx(Vector3(0, 1.6, 2.0)), "the boulder flies with its projectile")
	# every other contact, and the hits
	for ev in [_effect("dozer_boulder_shatter", "area", {"pool": "boulder_toss"}),
			_effect("dozer_quake", "area", {"radius": 2.4, "shape": "ring", "pool": "quake_stomp"}),
			_effect("dozer_aftershock", "area", {"radius": 3.6, "inner": 2.1, "shape": "ring", "pool": "quake_stomp"}),
			_effect("dozer_spikes", "area", {"pos": Vector3(0, 0, 1.0), "pool": "iron_hide"}),
			_effect("dozer_scree", "zone", {"radius": 0.9, "pool": "rock_slide"}),
			_effect("dozer_iron_hide", "buff", {"duration": 0.4, "pool": "iron_hide"})]:
		fx.on_event(ev)
	for pool in ["boulder_toss", "rock_slide", "quake_stomp"]:
		fx.on_event({"type": "hit", "fighter": 0, "target": 1, "pool": pool, "cat": "x", "damage": 6.0, "point": Vector3(2.5, 0.6, 0.0),
			"element": "grit", "blocked": false})
	check((kit._hides as Dictionary).has(0), "Iron Hide clamps a sheen over him")
	await wait_frames(4)
	check(_pieces(fx) > base + 20, "the contacts draw (%d pieces over %d)" % [_pieces(fx), base])
	fx.sync_entities([])
	# a toss cut off before the throw drops its rock
	fx.on_event({"type": "move_start", "fighter": 0, "slot": "m3", "id": "f_dozer.mv.boulder_toss", "pool": "boulder_toss", "cat": "projectile"})
	await wait_frames(30)
	check((kit._held as Dictionary).has(0), "a second boulder comes up")
	_state[0] = Fighter.State.HITSTUN
	await wait_frames(10)
	check(not (kit._held as Dictionary).has(0), "a cut-off toss drops its rock")
	_state.erase(0)
	await wait_frames(320)                             # the longest pieces (the fault line's crack) are 2.2 s
	check(not is_instance_valid(rock) and not is_instance_valid(scree), "the entity looks are cleaned up")
	check((kit._hides as Dictionary).is_empty() and (kit._skirts as Array).is_empty() and (kit._winds as Dictionary).is_empty(),
		"the hide, the rubble and the wind-ups are gone")
	check(_pieces(fx) <= base, "every piece is cleaned up (%d left, %d before)" % [_pieces(fx), base])
	fx.queue_free()
	for v in views:
		(v as Node).queue_free()
