extends MovesKitCase
## Varga's v0.9.18 Movesets (docs/kits/f_varga.md, docs/design/MOVESET_COMBAT.md §6): technique
## loadouts validate (one technique per modifier group); a technique replaces exactly the strikes of
## its group in both stances; every technique's effect fires from the real limb + modifier buttons
## (pressed the way MartialStyle reads them); the contextual combinations (Thousand-Fist Flurry,
## Iron Counter, Afterimage Rush, Shockwave Uppercut) trigger in Movesets and never in Classic;
## Classic Varga is the v0.9.17 Varga; the legacy skin never touches his gameplay; and the effects
## kit draws every effect and cleans up, headless. Opponent: the standing dev_biped dummy (the size
## his Cage Rules strikes are authored for).

const AURA_BOXER := ["comet_hook", "pressure_palm", "thunder_chop", "iron_shins"]
const SHOCKWAVE_KICKER := ["spiral_hook", "force_palm", "meteor_hammer", "shockwave_kicks"]
const TECHNIQUES := ["comet_hook", "spiral_hook", "pressure_palm", "force_palm", "meteor_hammer", "thunder_chop", "shockwave_kicks", "iron_shins"]
## the limb-slot kinds each modifier group covers
const GROUP_KINDS := {"hooks": ["hook"], "straights": ["straight"], "overhands": ["overhand"], "kicks": ["bkick", "hkick", "lkick"]}
const MODS := [-1, FighterInput.MMA_MOD1, FighterInput.MMA_MOD2, FighterInput.MMA_MOD3]
const SKIN_KEY := "cosmetic.legacy_varga"
const L := FighterInput.LIGHT
const R := FighterInput.HEAVY
const LL := FighterInput.MMA_LL
const RL := FighterInput.MMA_RL

var _worlds: Array = []
var _state := {}            ## fx tests: fighter -> {state, charge} the view info reports
var _saved_settings := {}   ## the skin test restores these


func after_each() -> void:
	for w in _worlds:
		if is_instance_valid(w):
			(w as Node).queue_free()
	_worlds.clear()
	_state.clear()
	if not _saved_settings.is_empty():
		Settings.values = _saved_settings["values"]
		Settings.path_override = _saved_settings["path"]
		Settings.read_only = _saved_settings["ro"]
		_saved_settings = {}


# =====================================================================================================
# Helpers
# =====================================================================================================

## Varga (fighter 0) against a standing dummy `gap` metres away, in `style`, with `loadout`.
func _duel(style: String, loadout: Array = [], gap := 1.0, heavy_dummy := false) -> MatchSim:
	var arena := ArenaDef.from_dict({"id": "t", "base": "octagon", "radius": 7.0, "spawns": [[0, -gap * 0.5, 0], [0, gap * 0.5, 180]]})
	var foe := Content.creature("dev_biped")
	if heavy_dummy:
		foe = Content.scaled_creature("dev_biped", 1.0, 100.0 / foe.body.total_mass)
	var sim := MatchSim.new()
	sim.running = false
	var world := fresh_world()
	world.add_child(sim)
	_worlds.append(world)
	sim.setup({"arena": arena, "rules": {"rounds": 1, "round_time": 0, "intro_time": 0.2, "combat": style}, "seed": 7, "fighters": [
		{"creature": Content.creature("f_varga"), "team": 0, "source": null, "loadout": loadout},
		{"creature": foe, "team": 1, "source": null}]})
	return sim


func _release_all(f: Fighter) -> void:
	for b in FighterInput.BUTTON_COUNT:
		f.input.set_held(b, false)


## Presses a limb with a strike modifier held (as a player does: the modifier first), for a few
## ticks or `hold` seconds; `check_held` also holds Check. Everything is let go afterwards.
func _press(sim: MatchSim, limb: int, mod: int, hold := 0.0, check_held := false) -> void:
	var v := sim.fighters[0]
	if mod > 0:
		v.input.set_held(int(MODS[mod]), true)
	if check_held:
		v.input.set_held(FighterInput.MMA_CHECK, true)
	v.input.press(limb)
	await step_sim(sim, maxf(hold, 4.0 * DT))
	_release_all(v)


## Steps until `cond` holds (true) or `limit` seconds pass (false).
func _until(sim: MatchSim, cond: Callable, limit: float) -> bool:
	for i in int(limit / DT):
		if bool(cond.call()):
			return true
		await step_sim(sim, DT)
	return bool(cond.call())


## Presses limb + modifier as soon as the running strike has landed and can be cancelled (the
## string continues); false when it ended without landing.
func _chain(sim: MatchSim, limb: int, mod: int) -> bool:
	var v := sim.fighters[0]
	var can_go := func() -> bool:
		return v.state != Fighter.State.ATTACK or v.move == null or (v.move_hit_any and v.state_time >= v.move.cancel_t0)
	var ok: bool = await _until(sim, can_go, 1.5)
	if not ok or v.state != Fighter.State.ATTACK or v.move == null or not v.move_hit_any:
		return false
	await _press(sim, limb, mod)
	return true


func _melee(sim: MatchSim, pool: String) -> Array:
	return pool_events(sim, "hit", pool).filter(func(e: Dictionary) -> bool: return bool(e.get("melee", false)))


func _effect_hits(sim: MatchSim, pool: String) -> Array:
	return pool_events(sim, "hit", pool).filter(func(e: Dictionary) -> bool: return str(e.get("slot", "")) == "effect")


func _vfx(sim: MatchSim, vfx: String, fi := 0) -> Array:
	return sim.events.filter(func(e: Dictionary) -> bool: return str(e.get("type", "")) == "effect" and int(e.get("fighter", -1)) == fi and str(e.get("vfx", "")) == vfx)


func _knocked(sim: MatchSim, fi := 1) -> bool:
	return sim.events.any(func(e: Dictionary) -> bool: return str(e["type"]) == "knockdown" and int(e.get("fighter", -1)) == fi)


## Presses limb + modifier at each gap until the technique's own strike lands in melee; returns
## that duel (still running, right after the hit) or null. `guard`: the dummy holds its guard.
func _land(loadout: Array, limb: int, mod: int, pool: String, gaps: Array, guard := false) -> MatchSim:
	for gap in gaps:
		var sim := _duel("moves", loadout, float(gap))
		await step_sim(sim, 0.4)
		if guard:
			sim.fighters[1].input.set_held(FighterInput.GUARD, true)
			await step_sim(sim, 0.3)
		await _press(sim, limb, mod)
		var landed := func() -> bool: return not _melee(sim, pool).is_empty()
		var ok: bool = await _until(sim, landed, 0.9)
		if ok:
			return sim
	return null


## Every slot a modifier group covers, in both stances ("lh_hook", "rh_hook@southpaw", ...).
func _group_slots(group: String) -> Array:
	var out: Array = []
	for kind in GROUP_KINDS[group]:
		var sides := ["lh", "rh"] if not str(kind).ends_with("kick") else ["ll", "rl"]
		for side in sides:
			out.append("%s_%s" % [side, kind])
			out.append("%s_%s@southpaw" % [side, kind])
	return out


## Puts Varga back in neutral, rested, in a stance, with nothing buffered.
func _reset(v: Fighter, southpaw: bool) -> void:
	v._interrupt_move()
	v._set_state(Fighter.State.NEUTRAL)
	v.stamina = v.max_stamina
	v.martial_southpaw = southpaw
	v._light_step = 0
	v._buffer.clear()


# =====================================================================================================
# Pool and loadouts
# =====================================================================================================

func test_technique_pool_and_loadouts() -> void:
	var c := Content.creature("f_varga")
	check(c.is_valid(), "Varga parses: %s" % str(c.errors))
	check_eq(c.pool.keys().size(), 8, "eight techniques")
	var groups := {}
	for id in TECHNIQUES:
		var pm := check_pool_move("f_varga", str(id))
		if pm == null:
			continue
		var g := str(pm.martial.get("group", ""))
		check(GROUP_KINDS.has(g), "%s belongs to a modifier group (%s)" % [id, g])
		groups[g] = int(groups.get(g, 0)) + 1
		var slots: Dictionary = pm.martial.get("slots", {})
		var want: Array = _group_slots(g) if GROUP_KINDS.has(g) else []
		want.sort()
		var have: Array = slots.keys()
		have.sort()
		check_eq(have, want, "%s replaces exactly its group's strikes in both stances" % id)
		for s in slots:
			var tm: MoveDef = c.moves.get(str(slots[s]))
			var base: MoveDef = c.moves.get(str(s))
			check(tm != null and tm != base, "%s: %s has its own move (%s)" % [id, s, slots[s]])
			if tm != null and base != null:
				check(tm.windows.size() == base.windows.size() and tm.windows[0]["weapons"] == base.windows[0]["weapons"],
					"%s keeps %s's limb and hit window" % [slots[s], s])
		check(pm.ai.has("range"), "%s has bot hints" % id)
	check_eq(groups, {"hooks": 2, "straights": 2, "overhands": 2, "kicks": 2}, "two techniques per group")
	check_eq(c.default_loadout, "aura_boxer", "Aura Boxer is the default")
	check_eq(c.resolve_loadout([]), AURA_BOXER, "the default loadout is Aura Boxer")
	check_eq((c.loadouts["shockwave_kicker"] as Dictionary)["moves"], SHOCKWAVE_KICKER, "Shockwave Kicker is the second build")
	check(AURA_BOXER.filter(func(x) -> bool: return SHOCKWAVE_KICKER.has(x)).is_empty(), "the two builds share no technique")
	check_eq(c.loadout_problem(AURA_BOXER), "", "A validates")
	check_eq(c.loadout_problem(SHOCKWAVE_KICKER), "", "B validates")
	check_eq(c.loadout_problem(["spiral_hook", "pressure_palm", "meteor_hammer", "iron_shins"]), "", "a mixed loadout validates")
	check(c.loadout_problem(["comet_hook", "spiral_hook", "pressure_palm", "thunder_chop"]) != "", "two techniques for one group are refused")
	check(c.loadout_problem(["comet_hook", "pressure_palm", "thunder_chop"]) != "", "a group without a technique is refused")
	check(c.loadout_problem(["comet_hook", "pressure_palm", "thunder_chop", "ability1"]) != "", "a non-technique is refused")
	check_eq(c.resolve_loadout(["comet_hook", "spiral_hook"]), AURA_BOXER, "an invalid wish falls back to the default")
	# every style is a real patch: it matches on Varga, and his drilled kit still parses
	for id in TECHNIQUES:
		var pm2: PoolMove = c.pool.get(str(id))
		if pm2 == null:
			continue
		for sid in pm2.styles:
			var st: Dictionary = pm2.styles[sid]
			check(str(st.get("name", "")) != "" and str(st.get("desc", "")).length() > 20, "%s.%s is named and described" % [id, sid])
			var patches: Array = st.get("patch", [])
			check(not patches.is_empty(), "%s.%s changes something" % [id, sid])
			for p in patches:
				check_eq(ContentPatch.validate(p), "", "%s.%s patch is well formed" % [id, sid])
			var d: Dictionary = Content.creature_entry("f_varga").duplicate(true)
			var res := ContentPatch.apply_all(d, patches)
			check((res["unmatched"] as Array).is_empty(), "%s.%s: every patch hits (%s)" % [id, sid, str(res["unmatched"])])
			d["id"] = "t_varga_" + str(sid)
			var pc := CreatureDef.from_dict(d, Callable(), "test")
			check(pc.is_valid(), "%s.%s: the drilled kit parses: %s" % [id, sid, str(pc.errors)])


func test_equipping_a_technique_changes_only_its_group() -> void:
	var c := Content.creature("f_varga")
	for loadout in [AURA_BOXER, SHOCKWAVE_KICKER, ["spiral_hook", "pressure_palm", "meteor_hammer", "iron_shins"]]:
		var sim := _duel("moves", loadout, 1.6)
		await step_sim(sim, 0.4)
		var v := sim.fighters[0]
		check_eq(v.loadout, loadout, "the loadout is equipped")
		var owner_of := {}
		for id in loadout:
			for s in ((c.pool[id] as PoolMove).martial["slots"] as Dictionary):
				owner_of[str(s)] = str(id)
		# every limb x modifier x stance press, dispatched exactly as a player's press is
		for sp in [false, true]:
			for mod in 4:
				for limb in MartialStyle.LIMBS:
					var key := MartialStyle.slot(limb, mod, sp)
					_reset(v, sp)
					v._buffer = [{"b": limb, "t": v.time, "mma_mod": mod}]
					check(MartialStyle.actions(v, false), "%s starts" % key)
					if owner_of.has(key):
						var tslots: Dictionary = (c.pool[owner_of[key]] as PoolMove).martial["slots"]
						check(v.move == c.moves[str(tslots[key])], "%s is performed by %s (%s)" % [key, owner_of[key], v.move.id if v.move else "none"])
						check_eq(v.move_pool_id, str(owner_of[key]), "%s is attributed to its technique" % key)
					elif mod == 0:
						var aura := MartialStyle.named(key, "aura_" + MartialStyle.kind_of(key))
						check(v.move == c.moves[aura], "%s stays the plain strike, in its aura version (%s)" % [key, v.move.id if v.move else "none"])
						check_eq(v.move_pool_id, "", "%s is not a technique" % key)
					else:
						fail("%s: a modifier strike without a technique in %s" % [key, str(loadout)])
					check_eq(v.move_slot, key, "%s reports its Cage Rules slot" % key)
		_reset(v, false)
	# swapping one technique changes its own group's strikes and nothing else
	var a := _duel("moves", ["comet_hook", "force_palm", "meteor_hammer", "iron_shins"])
	var b := _duel("moves", ["spiral_hook", "force_palm", "meteor_hammer", "iron_shins"])
	var oa: Dictionary = a.fighters[0].move_overrides
	var ob: Dictionary = b.fighters[0].move_overrides
	check_eq(oa.keys().size(), 24, "hooks, straights and overhands (4 slots each) and kicks (12) are replaced")
	check_eq(oa.keys().size(), ob.keys().size(), "the same slots are replaced")
	for s in oa:
		var differs: bool = oa[s] != ob.get(s)
		check_eq(differs, _group_slots("hooks").has(s), "%s differs only if it is a hook" % s)
	check(_duel("classic", AURA_BOXER).fighters[0].move_overrides.is_empty(), "Classic replaces nothing")


# =====================================================================================================
# Techniques, from the real limb + modifier buttons
# =====================================================================================================

func test_hook_techniques_from_the_limb_inputs() -> void:
	# Comet Hook (Hooks + left hand): the hook, and its arc clips what stands in front
	var sim := _duel("moves", AURA_BOXER, 1.0)
	await step_sim(sim, 0.4)
	var v := sim.fighters[0]
	await _press(sim, L, 1)
	check_eq(v.move_slot, "lh_hook", "Hooks + left hand is the lead hook slot")
	check_eq(v.move_pool_id, "comet_hook", "performed as the Comet Hook")
	check(v.move == v.creature.moves["lh_comet_hook"], "with its own move")
	await step_sim(sim, 0.6)
	check(not _vfx(sim, "varga_comet_arc").is_empty(), "the comet arc fires")
	check(not _effect_hits(sim, "comet_hook").is_empty(), "and clips the fighter in front")
	# southpaw: the same buttons are the mirrored technique
	var sp := _duel("moves", AURA_BOXER, 1.0)
	await step_sim(sp, 0.4)
	sp.fighters[0].input.press(FighterInput.MMA_STANCE)
	await step_sim(sp, 0.1)
	_release_all(sp.fighters[0])
	await step_sim(sp, 0.3)
	await _press(sp, L, 1)
	check_eq(sp.fighters[0].move_slot, "rh_hook@southpaw", "southpaw: the left hand throws the rear hook slot")
	check(sp.fighters[0].move == sp.fighters[0].creature.moves["rh_comet_hook@southpaw"], "as the mirrored Comet Hook")
	# Spiral Hook (Hooks + right hand): the vortex pulls, a clean hit turns the target's guard away
	var land: MatchSim = await _land(SHOCKWAVE_KICKER, R, 1, "spiral_hook", [1.0, 0.85, 1.15])
	if not check(land != null, "the Spiral Hook lands at some close range"):
		return
	var d := land.fighters[1]
	var to_v := land.fighters[0].pos() - d.pos()
	var off := absf(MathX.wrap_angle(d.facing_yaw - atan2(to_v.x, to_v.z)))
	check(off > deg_to_rad(35.0), "the hit spins the target away from Varga (%.0f degrees off)" % rad_to_deg(off))
	check(not _vfx(land, "varga_spiral_vortex").is_empty(), "the spiral vortex fires")


func test_straight_techniques_from_the_limb_inputs() -> void:
	# Pressure Palm (Straights + a hand), tapped: the palm throws a small blast that flies
	var sim := _duel("moves", AURA_BOXER, 2.6)
	await step_sim(sim, 0.4)
	var v := sim.fighters[0]
	await _press(sim, L, 2)
	check_eq(v.move_pool_id, "pressure_palm", "Straights + left hand is the Pressure Palm")
	await step_sim(sim, 2.0 * DT)
	check(not v._charging and v.move_charge == 0.0, "a tap does not charge")
	var tap := {"r": 0.0}
	for i in int(0.8 / DT):
		await step_sim(sim, DT)
		for ent in pool_entities(sim, "pressure_palm", "projectile"):
			tap["r"] = maxf(float(tap["r"]), float(ent["radius"]))
	check(float(tap["r"]) > 0.1, "a tapped palm throws an aura blast (radius %.2f)" % float(tap["r"]))
	var tap_hits := _effect_hits(sim, "pressure_palm")
	check(not tap_hits.is_empty(), "the blast reaches a fighter 2.6 m away")
	# held: it charges (frozen in the wind-up, armoured against light hits) and throws a bigger blast
	var ch := _duel("moves", AURA_BOXER, 3.2)
	await step_sim(ch, 0.4)
	var cv := ch.fighters[0]
	cv.input.set_held(FighterInput.MMA_MOD2, true)
	cv.input.press(R)
	var seen := {"r": 0.0, "charge": 0.0, "charging": false, "armour": false}
	for i in int(1.7 / DT):
		await step_sim(ch, DT)
		if i == int(0.5 / DT):
			seen["charging"] = cv._charging and cv.move_charge > 0.3
			seen["armour"] = cv.armor_until > cv.time and cv.armor_level == "lights"
		seen["charge"] = maxf(float(seen["charge"]), cv.move_charge)
		for ent in pool_entities(ch, "pressure_palm", "projectile"):
			seen["r"] = maxf(float(seen["r"]), float(ent["radius"]))
		if i == int(1.15 / DT):
			_release_all(cv)
	check(bool(seen["charging"]), "holding the hand charges the palm")
	check(bool(seen["armour"]), "light hits don't stop the charge")
	check(float(seen["charge"]) > 0.95, "up to a full charge (%.2f)" % float(seen["charge"]))
	check(float(seen["r"]) > float(tap["r"]) * 1.6, "a charged blast is bigger (%.2f vs %.2f)" % [float(seen["r"]), float(tap["r"])])
	var charged := _effect_hits(ch, "pressure_palm")
	check(not charged.is_empty() and not tap_hits.is_empty() and float(charged[0]["damage"]) > float(tap_hits[0]["damage"]) * 2.0,
		"and hits much harder (%s vs %s)" % [str(charged[0]["damage"]) if not charged.is_empty() else "-", str(tap_hits[0]["damage"]) if not tap_hits.is_empty() else "-"])
	# Force Palm: a clean hit sets off the point-blank burst; on a guard it cracks it
	var land: MatchSim = await _land(SHOCKWAVE_KICKER, L, 2, "force_palm", [0.9, 0.75, 1.05])
	if check(land != null, "the Force Palm lands at point-blank range"):
		check(not _vfx(land, "varga_force_palm_burst").is_empty(), "a clean Force Palm bursts")
		check(not _effect_hits(land, "force_palm").is_empty(), "and the burst blows him back")
	var gl: MatchSim = await _land(SHOCKWAVE_KICKER, L, 2, "force_palm", [0.9, 0.75, 1.05], true)
	if check(gl != null, "the Force Palm reaches a guard"):
		var blocked := _melee(gl, "force_palm").filter(func(e: Dictionary) -> bool: return bool(e["blocked"]))
		check(not blocked.is_empty(), "the guard blocked it")
		check(not _vfx(gl, "varga_force_palm_crack").is_empty(), "and the guard cracks")
		check(gl.fighters[1].stamina < gl.fighters[1].max_stamina - 10.0, "a big bite out of the guard's stamina (%.1f left)" % gl.fighters[1].stamina)


func test_overhand_techniques_from_the_limb_inputs() -> void:
	# Meteor Hammer (Overhands + a hand): armoured wind-up, then the floor cracks in a ring
	var sim := _duel("moves", SHOCKWAVE_KICKER, 1.0)
	await step_sim(sim, 0.4)
	var v := sim.fighters[0]
	await _press(sim, R, 3)
	check_eq(v.move_pool_id, "meteor_hammer", "Overhands + right hand is the Meteor Hammer")
	await step_sim(sim, 0.06)
	check(v.armor_until > v.time and v.armor_level == "lights", "light hits don't stop its wind-up")
	await step_sim(sim, 0.8)
	check(not _vfx(sim, "varga_meteor_crack").is_empty(), "the floor cracks")
	check(not _effect_hits(sim, "meteor_hammer").is_empty(), "and the ring hits the fighter standing in it")
	# Thunder Chop: a clean hit sparks and stuns longer than the chop alone
	var land: MatchSim = await _land(AURA_BOXER, L, 3, "thunder_chop", [1.0, 0.85, 1.15])
	if check(land != null, "the Thunder Chop lands"):
		var d := land.fighters[1]
		check(d.state == Fighter.State.HITSTUN and d.stun_left > 0.3, "the spark stuns (%.2f s left)" % d.stun_left)
		check(not _vfx(land, "varga_thunder_spark").is_empty(), "with its spark")


func test_kick_techniques_from_the_limb_inputs() -> void:
	# Shockwave Kicks: the roundhouse throws a wave arc (Hooks + leg)
	var sim := _duel("moves", SHOCKWAVE_KICKER, 1.2)
	await step_sim(sim, 0.4)
	await _press(sim, LL, 1)
	check_eq(sim.fighters[0].move_slot, "ll_bkick", "Hooks + left leg is the lead body kick slot")
	check(sim.fighters[0].move == sim.fighters[0].creature.moves["ll_shockwave_roundhouse"], "performed as the Shockwave Roundhouse")
	await step_sim(sim, 0.8)
	check(not _vfx(sim, "varga_shockwave_arc").is_empty(), "the wave arc fires")
	check(not _effect_hits(sim, "shockwave_kicks").is_empty(), "and hits")
	# the head kick launches a crescent wave that flies (Straights + leg)
	var cr := _duel("moves", SHOCKWAVE_KICKER, 3.5)
	await step_sim(cr, 0.4)
	await _press(cr, RL, 2)
	check(cr.fighters[0].move == cr.fighters[0].creature.moves["rl_crescent_moon_kick"], "Straights + right leg: the Crescent Moon Kick")
	var flying := func() -> bool:
		return not pool_entities(cr, "shockwave_kicks", "projectile").filter(func(ent: Dictionary) -> bool: return str(ent["vfx"]) == "varga_crescent_wave").is_empty()
	var flew: bool = await _until(cr, flying, 0.6)
	check(flew, "a crescent wave flies")
	await step_sim(cr, 0.8)
	check(not _effect_hits(cr, "shockwave_kicks").is_empty(), "and reaches a fighter 3.5 m away")
	# the low kick's quake trips (Overhands + leg)
	var qk := _duel("moves", SHOCKWAVE_KICKER, 1.0)
	await step_sim(qk, 0.4)
	await _press(qk, LL, 3)
	check(qk.fighters[0].move == qk.fighters[0].creature.moves["ll_sweep_quake"], "Overhands + left leg: the Sweep Quake")
	await step_sim(qk, 1.0)
	check(not _vfx(qk, "varga_sweep_quake").is_empty(), "the floor quakes")
	check(_knocked(qk), "and trips the fighter standing there")
	# Iron Shins: the body kick is armoured through its swing (Hooks + leg)
	var ir := _duel("moves", AURA_BOXER, 1.2)
	await step_sim(ir, 0.4)
	await _press(ir, RL, 1)
	var iv := ir.fighters[0]
	check(iv.move == iv.creature.moves["rl_iron_shin"], "Hooks + right leg: the Iron Shin")
	await step_sim(ir, 0.15)
	check(iv.armor_until > iv.time and iv.armor_level == "all_but_heavy", "armoured against all but heavies")
	# the Axe Kick knocks down (Straights + leg)
	var ax: MatchSim = await _land(AURA_BOXER, LL, 2, "iron_shins", [1.2, 1.0, 1.4])
	if check(ax != null, "the Axe Kick lands"):
		await step_sim(ax, 0.2)
		check(_knocked(ax), "and knocks the target down")
		check(not _vfx(ax, "varga_axe_drop").is_empty(), "with its drop")
	# the Leg Breaker slows (Overhands + leg)
	var lb: MatchSim = await _land(AURA_BOXER, RL, 3, "iron_shins", [1.0, 0.85, 1.15])
	if check(lb != null, "the Leg Breaker lands"):
		var d := lb.fighters[1]
		check(d.statuses.has("varga_leg_breaker") and is_equal_approx(d.statuses.speed_mult(), 0.75), "it slows (%.2f)" % d.statuses.speed_mult())
		check(float(d.statuses.buildup.get("scrap", 0.0)) > 20.0 or d.statuses.has_element("scrap"), "and builds Rattled fast")


func test_plain_strikes_flare_only_in_movesets() -> void:
	# the plain strikes keep every v0.9.17 number; in Movesets a clean hit flares with gold aura
	var c := Content.creature("f_varga")
	for key in ["lh_uppercut", "rh_uppercut", "ll_teep", "rl_knee", "lh_uppercut@southpaw", "rh_uppercut@southpaw", "rl_teep@southpaw", "ll_knee@southpaw"]:
		var aura: MoveDef = c.moves.get(MartialStyle.named(key, "aura_" + MartialStyle.kind_of(key)))
		var base: MoveDef = c.moves[key]
		if not check(aura != null, "%s has its aura version" % key):
			continue
		check(aura.damage == base.damage and aura.stamina == base.stamina and aura.duration == base.duration and aura.windows == base.windows
			and aura.knockback == base.knockback and aura.keys.size() == base.keys.size(), "%s keeps the strike's numbers" % key)
		check(not aura.on_hit.is_empty() and base.on_hit.is_empty(), "%s only adds the on-hit flare" % key)
	for style in ["moves", "classic"]:
		var sim := _duel(style, [], 1.0)
		await step_sim(sim, 0.4)
		var v := sim.fighters[0]
		var d := sim.fighters[1]
		v._buffer = [{"b": LL, "t": v.time, "mma_mod": 0}]
		MartialStyle.actions(v, false)
		var hit := {"damage": 5.0, "part": "core", "melee": true, "blocked": false, "parried": false, "poise": 5.0, "knockback": Vector3.ZERO,
			"stun": 0.1, "seg": 0, "point": d.pos(), "normal": Vector3.BACK, "from": v.pos(), "move_class": "heavy"}
		sim.combat.deliver(v, d, hit)
		check_eq(_vfx(sim, "varga_pressure_teep").size(), 1 if style == "moves" else 0, "%s: the teep's pressure wave flares only in Movesets" % style)


# =====================================================================================================
# Contextual combinations: Movesets only
# =====================================================================================================

func test_iron_counter_answers_a_strike_in_movesets_only() -> void:
	for style in ["moves", "classic"]:
		var sim := _duel(style, [], 1.0)
		await step_sim(sim, 0.4)
		var v := sim.fighters[0]
		var foe := sim.fighters[1]
		# hold Check, then a straight (Straights + left hand)
		await _press(sim, L, 2, 0.0, true)
		if style == "moves":
			check_eq(v.move_slot, "lh_iron_counter", "Check + a straight is the Iron Counter")
			check(v.statuses.has("varga_iron_counter"), "its counter window is open")
		else:
			check_eq(v.move_slot, "lh_straight", "Classic: Check + a straight is the jab")
			check(not v.statuses.has("varga_iron_counter"), "Classic: no counter")
		var hp := v.health
		var foe_hp := foe.health
		var hit := {"damage": 9.0, "part": "core", "melee": true, "blocked": false, "parried": false, "poise": 12.0,
			"knockback": Vector3(0, 0, -2), "stun": 0.3, "seg": 0, "point": v.pos(), "normal": Vector3.FORWARD, "from": foe.pos(), "move_class": "light"}
		sim.combat.deliver(foe, v, hit)
		if style == "moves":
			check_near(v.health, hp, 0.01, "the strike caught inside the window does nothing")
			check(foe.health < foe_hp - 4.0, "and is answered (%.1f damage)" % (foe_hp - foe.health))
			check_eq(foe.state, Fighter.State.HITSTUN, "the striker is stunned")
			check(not _vfx(sim, "varga_iron_counter_burst").is_empty(), "with the answer burst")
			# one answer per counter: a second strike in the window lands (on armour)
			var hp2 := v.health
			var hit2 := {"damage": 9.0, "part": "core", "melee": true, "blocked": false, "parried": false, "poise": 12.0,
				"knockback": Vector3(0, 0, -2), "stun": 0.3, "seg": 0, "point": v.pos(), "normal": Vector3.FORWARD, "from": foe.pos(), "move_class": "light"}
			sim.combat.deliver(foe, v, hit2)
			check(v.health < hp2 - 4.0, "only the first strike is answered")
			check_eq(v.state, Fighter.State.ATTACK, "and the armour keeps the counter going")
		else:
			check(v.health < hp - 5.0, "Classic: the strike lands")
			check(_vfx(sim, "varga_iron_counter_burst").is_empty(), "Classic: nothing answers it")


func test_thousand_fist_flurry_in_movesets_only() -> void:
	for style in ["moves", "classic"]:
		var sim := _duel(style, [], 1.6)
		await step_sim(sim, 0.4)
		var v := sim.fighters[0]
		# [strikes landed before the running one, modifier of the next press, stamina, flurry expected]
		for row in [[1, 0, 100.0, true], [0, 0, 100.0, false], [1, 1, 100.0, false], [1, 0, 8.0, false]]:
			_reset(v, false)
			v._start_move(v.creature.moves["lh_hook"], "lh_hook", Fighter.State.ATTACK)
			v.move_hit_any = true
			v._light_step = int(row[0])
			v.state_time = v.move.cancel_t0 + 0.01
			v.stamina = float(row[2])
			v._buffer = [{"b": L, "t": v.time, "mma_mod": int(row[1])}]
			check(MartialStyle.actions(v, true), "the press starts something (stamina %.0f)" % float(row[2]))
			var flurry := v.move_slot == "thousand_fist_flurry"
			var want: bool = bool(row[3]) and str(style) == "moves"
			check_eq(flurry, want, "%s, %d landed before this press, modifier %d, stamina %.0f: flurry %s" % [style, int(row[0]) + 1, int(row[1]), float(row[2]), str(want)])
			if float(row[2]) < 12.0:
				check_eq(v.move_slot, "lh_uppercut", "%s: out of stamina for the flurry, the plain hand is the uppercut" % style)
		if style == "moves":
			_reset(v, false)
			v._start_move(v.creature.moves["lh_hook"], "lh_hook", Fighter.State.ATTACK)
			v.move_hit_any = true
			v._light_step = 1
			v.state_time = v.move.cancel_t0 + 0.01
			v._buffer = [{"b": L, "t": v.time, "mma_mod": 0}]
			MartialStyle.actions(v, true)
			var hp := sim.fighters[1].health
			await step_sim(sim, 1.0)
			check_eq(_vfx(sim, "varga_flurry_fist").size(), 6, "six aura fists")
			check(sim.fighters[1].health < hp - 5.0, "that land (%.1f)" % (hp - sim.fighters[1].health))
	# and from real buttons: two Thunder Chops that land, then a plain hand
	var done := false
	for gap in [1.0, 0.85, 1.15]:
		var s := _duel("moves", AURA_BOXER, float(gap), true)
		await step_sim(s, 0.4)
		await _press(s, L, 3)
		var second: bool = await _chain(s, R, 3)
		if not second:
			continue
		var third: bool = await _chain(s, L, 0)
		if not third:
			continue
		check_eq(s.fighters[0].move_slot, "thousand_fist_flurry", "chop, chop (both landed), plain hand: the Thousand-Fist Flurry")
		done = true
		break
	check(done, "a two-strike string lands from real buttons")


func test_shockwave_uppercut_in_movesets_only() -> void:
	var launched := false
	for gap in [0.7, 0.8, 0.9]:          # the uppercut's own close range (test_new_fighters lands it at 0.7)
		var sim := _duel("moves", AURA_BOXER, float(gap))
		await step_sim(sim, 0.4)
		var d := sim.fighters[1]
		await _press(sim, L, 0)
		check_eq(sim.fighters[0].move_slot, "lh_shockwave_uppercut", "a plain hand on a target within 1.2 m is the Shockwave Uppercut")
		var y0 := d.pos().y
		var rise := func() -> bool: return d.pos().y - y0 > 0.25
		var up: bool = await _until(sim, rise, 0.9)
		if up:
			check(not _vfx(sim, "varga_shockwave_ring").is_empty(), "the ring rolls out")
			launched = true
			break
	check(launched, "the Shockwave Uppercut launches the target")
	# out of range it stays the plain uppercut, in its aura version
	var far := _duel("moves", AURA_BOXER, 2.0)
	await step_sim(far, 0.4)
	await _press(far, L, 0)
	check_eq(far.fighters[0].move_slot, "lh_uppercut", "a plain hand from 2 m is the uppercut")
	check(far.fighters[0].move == far.fighters[0].creature.moves["lh_aura_uppercut"], "with the aura")
	# Classic: the plain uppercut, close or not
	var cl := _duel("classic", [], 1.0)
	await step_sim(cl, 0.4)
	await _press(cl, L, 0)
	check(cl.fighters[0].move == cl.fighters[0].creature.moves["lh_uppercut"] and cl.fighters[0].move_slot == "lh_uppercut", "Classic: the plain uppercut")


func test_afterimage_rush_in_movesets_only() -> void:
	# stance switch + dodge, in either order, is the rush; too far apart it is a dodge
	for order in ["together", "stance_first", "dodge_first", "too_late"]:
		for style in ["moves", "classic"]:
			var sim := _duel(style, [], 3.5)
			await step_sim(sim, 0.4)
			var v := sim.fighters[0]
			match order:
				"together":
					v.input.press(FighterInput.MMA_STANCE)
					v.input.press(FighterInput.DODGE)
				"stance_first":
					v.input.press(FighterInput.MMA_STANCE)
					await step_sim(sim, 0.1)
					v.input.press(FighterInput.DODGE)
				"dodge_first":
					v.input.press(FighterInput.DODGE)
					await step_sim(sim, 0.08)
					v.input.press(FighterInput.MMA_STANCE)
				"too_late":
					v.input.press(FighterInput.MMA_STANCE)
					await step_sim(sim, 0.45)
					v.input.press(FighterInput.DODGE)
			await step_sim(sim, 4.0 * DT)
			_release_all(v)
			var rush := v.move_slot == "afterimage_rush"
			var want: bool = str(style) == "moves" and str(order) != "too_late"
			check_eq(rush, want, "%s, %s: Afterimage Rush %s" % [style, order, str(want)])
			if rush:
				check(v.martial_southpaw, "the stance switched once")
				var z0 := v.pos().z
				await step_sim(sim, 0.3)
				check(v.pos().z > z0 + 0.9, "a long dash at the target (%.2f m)" % (v.pos().z - z0))
				check(not _vfx(sim, "varga_afterimage_rush").is_empty(), "leaving afterimages")
			elif order != "too_late":
				check(v.state == Fighter.State.DODGE or v.move_slot == "dodge", "%s: a plain dodge" % style)
	# his D-pad abilities stay his abilities in Movesets
	var ab := _duel("moves", [], 3.0)
	await step_sim(ab, 0.4)
	ab.fighters[0].input.press(FighterInput.AB1)
	await step_sim(ab, 0.3)
	check(ab.fighters[0].statuses.has("angle"), "D-pad up is still Cut the Angle in Movesets")


# =====================================================================================================
# Classic Varga is the v0.9.17 Varga; the skin is only a skin
# =====================================================================================================

func test_classic_varga_is_unchanged() -> void:
	var c := Content.creature("f_varga")
	# the v0.9.17 strike data (as imported from Cage Rules)
	var m: MoveDef = c.moves["lh_straight"]
	check(m.damage == 5.7 and m.stamina == 3.5 and m.duration == 0.34 and m.windows[0]["t0"] == 0.07 and m.windows[0]["t1"] == 0.23, "the jab is the v0.9.17 jab")
	m = c.moves["rl_hkick"]
	check(m.damage == 10.26 and m.stamina == 10.0 and m.duration == 0.9 and m.windows[0]["t0"] == 0.21, "the head kick is the v0.9.17 head kick")
	check(is_equal_approx((c.moves["ll_teep"] as MoveDef).knockback, 4.0), "the teep still pushes")
	for sp in [false, true]:
		for mod in 4:
			for limb in MartialStyle.LIMBS:
				var mv: MoveDef = c.moves[MartialStyle.slot(limb, mod, sp)]
				check(mv.effects.is_empty() and mv.on_hit.is_empty() and mv.charge_time == 0.0 and mv.armor.is_empty(), "%s has no Movesets additions" % mv.id)
	var sim := _duel("classic", AURA_BOXER, 1.0)
	await step_sim(sim, 0.4)
	var v := sim.fighters[0]
	check(v.loadout.is_empty() and v.move_overrides.is_empty(), "Classic equips nothing")
	for sp in [false, true]:
		for mod in 4:
			for limb in MartialStyle.LIMBS:
				var key := MartialStyle.slot(limb, mod, sp)
				_reset(v, sp)
				v._light_step = 3
				v._buffer = [{"b": limb, "t": v.time, "mma_mod": mod}]
				check(MartialStyle.actions(v, false), "Classic %s starts" % key)
				check(v.move == c.moves[key] and v.move_slot == key and v.move_pool_id == "", "Classic %s is the Cage Rules strike" % key)
				check_eq(v._light_step, 0, "Classic %s resets the string step as in v0.9.17" % key)
	_reset(v, false)
	# a stance switch is only a stance switch
	v.input.press(FighterInput.MMA_STANCE)
	await step_sim(sim, 0.1)
	check(v.martial_southpaw, "the stance switches")
	check(not v.has_flag(MartialStyle.STANCE_FLAG), "Classic keeps no combination state")
	# real buttons: every Classic press is the plain Cage Rules strike, with no Movesets effects
	_release_all(v)
	await step_sim(sim, 0.4)
	for pair in [[L, 1], [R, 2], [L, 3], [LL, 1], [RL, 2], [LL, 3], [L, 0], [R, 2]]:
		await _press(sim, int(pair[0]), int(pair[1]), 0.0, int(pair[1]) == 2)
		await step_sim(sim, 0.9)
	var varga_fx := sim.events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == "effect" and str(e.get("vfx", "")).begins_with("varga_"))
	check(varga_fx.is_empty(), "no Movesets effects in Classic (%d)" % varga_fx.size())
	check(sim.events.filter(func(e: Dictionary) -> bool: return str(e.get("pool", "")) != "").is_empty(), "and nothing is attributed to a technique")
	var starts := sim.events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == "move_start" and int(e["fighter"]) == 0)
	for e in starts:
		check(c.moves.has(str(e["slot"])) and (c.moves[str(e["slot"])] as MoveDef).id == str(e["id"]), "Classic %s is its own Cage Rules move" % str(e["slot"]))


func test_legacy_skin_never_touches_his_gameplay() -> void:
	_saved_settings = {"values": Settings.values.duplicate(true), "path": Settings.path_override, "ro": Settings.read_only}
	Settings.path_override = temp_dir("varga-moves-skin-%d" % Time.get_ticks_usec()).path_join("settings.json")
	Settings.read_only = false
	var varga := Content.creature("f_varga")
	var entry := JSON.stringify(Content.get_entry("creatures", "f_varga"), "", true)
	var hash0 := Content.content_hash()
	var runs := {}
	for legacy in [false, true]:
		Settings.set_value(SKIN_KEY, legacy, true, false)
		check_eq(CreatureView.model_path_for(varga), CreatureView.VARGA_LEGACY_MODEL if legacy else CreatureView.VARGA_MODEL, "the skin follows the setting")
		check(Content.creature("f_varga") == varga, "the same creature definition (legacy %s)" % str(legacy))
		check_eq(JSON.stringify(Content.get_entry("creatures", "f_varga"), "", true), entry, "his content is untouched (legacy %s)" % str(legacy))
		check_eq(Content.content_hash(), hash0, "the content hash is unchanged (legacy %s)" % str(legacy))
		for style in ["moves", "classic"]:
			var bout: Array = await _scripted_bout(style)
			runs["%s/%s" % [str(legacy), style]] = bout
			# the view side works with this skin and style too: the kit draws on this model
			var views := _views(["f_varga", "dev_biped"])
			var fx := _fx(views)
			await wait_frames(30)
			var base := _pieces(fx)
			fx.on_event({"type": "effect", "fighter": 0, "effect": "dash", "vfx": "varga_afterimage_rush", "pos": Vector3.ZERO,
				"dir": Vector3.FORWARD, "speed": 6.0, "time": 0.26, "yaw": 0.0, "radius": 0.0, "shape": "circle", "element": "", "move": ""})
			await wait_frames(20)
			check(_pieces(fx) > base, "the rush's afterimages draw on the %s model (%s)" % ["legacy" if legacy else "upgraded", style])
			_free_fx(fx, views)
	check_eq(runs["false/moves"], runs["true/moves"], "the legacy skin plays the same Movesets bout")
	check_eq(runs["false/classic"], runs["true/classic"], "the legacy skin plays the same Classic bout")
	check(runs["false/moves"] != runs["false/classic"], "while the combat style does change it")


## A short bout from fixed button presses: the moves Varga performed, in order.
func _scripted_bout(style: String) -> Array:
	var sim := _duel(style, [], 1.1)
	await step_sim(sim, 0.4)
	for pair in [[L, 1], [R, 2], [LL, 3], [L, 0], [RL, 1]]:
		await _press(sim, int(pair[0]), int(pair[1]))
		await step_sim(sim, 0.9)
	var out: Array = []
	for e in sim.events:
		if str(e["type"]) == "move_start" and int(e["fighter"]) == 0:
			out.append("%s|%s|%s" % [str(e["slot"]), str(e["id"]), str(e.get("pool", ""))])
	return out


# =====================================================================================================
# Effects kit
# =====================================================================================================

func _fx(views: Array) -> AbilityVfx:
	var fx := AbilityVfx.new()
	fx.view_of = func(i: int): return views[i] if i >= 0 and i < views.size() else null
	fx.info_of = func(i: int) -> Dictionary:
		if i < 0 or i >= views.size():
			return {}
		var st: Dictionary = _state.get(i, {})
		return {"ground": Vector3(0, 0, i * 1.2), "yaw": 0.0 if i == 0 else PI, "state": int(st.get("state", Fighter.State.ATTACK)), "juiced": false,
			"hidden": false, "charge": float(st.get("charge", -1.0)), "out": false}
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


func _free_fx(fx: AbilityVfx, views: Array) -> void:
	fx.queue_free()
	for v in views:
		(v as Node).queue_free()


## Non-particle nodes under the effects root (particle emitters are pooled and stay).
func _pieces(fx: AbilityVfx) -> int:
	var n := 0
	for ch in fx.get_children():
		if not (ch is GPUParticles3D):
			n += 1
	return n


func test_effects_kit_draws_and_cleans_up() -> void:
	for quality in [2, 0]:
		_state.clear()
		var views := _views(["f_varga", "dev_biped"])
		var fx := _fx(views)
		fx.configure(quality, quality == 0)
		await wait_frames(30)
		var kit = fx.moves.kits.get("f_varga")
		if not check(kit != null, "Varga's kit is loaded"):
			_free_fx(fx, views)
			return
		for v in kit.vfx_names():
			check(fx.moves.by_vfx.get(str(v)) == kit, "the kit draws '%s'" % v)
			check(str(v).begins_with("varga_"), "%s is named as Varga's" % v)
		var base := _pieces(fx)
		# the technique build-ups (a move start of every technique)
		for pair in [["comet_hook", "lh_comet_hook"], ["spiral_hook", "rh_spiral_hook"], ["pressure_palm", "lh_pressure_palm"],
				["force_palm", "rh_force_palm@southpaw"], ["meteor_hammer", "lh_meteor_hammer"], ["thunder_chop", "rh_thunder_chop"],
				["shockwave_kicks", "ll_shockwave_roundhouse"], ["iron_shins", "rl_axe_kick"]]:
			fx.on_event({"type": "move_start", "fighter": 0, "slot": "x", "id": "f_varga." + str(pair[1]), "pool": str(pair[0]), "cat": "strike"})
		# every effect it names
		var moves_of := {"varga_comet_arc": "lh_comet_hook", "varga_shockwave_arc": "rl_shockwave_roundhouse@southpaw",
			"varga_pressure_blast": "rh_pressure_palm", "varga_crescent_wave": "ll_crescent_moon_kick"}
		for v in kit.vfx_names():
			var ev := {"type": "effect", "fighter": 0, "effect": "area", "vfx": str(v), "pos": Vector3(0, 0, 0.9), "origin": Vector3.ZERO,
				"radius": 1.2, "cone_deg": 110.0, "shape": "cone", "yaw": 0.0, "element": "scrap", "move": "f_varga." + str(moves_of.get(str(v), "")),
				"dir": Vector3.FORWARD, "speed": 6.0, "time": 0.26}
			check(fx.moves.on_event(0, "f_varga", ev), "'%s' is drawn by the kit" % v)
		for k in 6:
			fx.on_event({"type": "effect", "fighter": 0, "effect": "area", "vfx": "varga_flurry_fist", "pos": Vector3(0, 0, 0.85), "radius": 0.6,
				"shape": "circle", "yaw": 0.0, "element": "scrap", "move": "f_varga.thousand_fist_flurry"})
			await wait_frames(4)
		fx.on_event({"type": "hit", "fighter": 0, "target": 1, "pool": "pressure_palm", "slot": "effect", "point": Vector3(0, 1.2, 1.2), "damage": 9.0,
			"blocked": false, "melee": false})
		fx.on_event({"type": "hit", "fighter": 0, "target": 1, "pool": "comet_hook", "slot": "lh_hook", "point": Vector3(0, 1.4, 0.9), "damage": 7.0,
			"blocked": false, "melee": true})
		await wait_frames(2)
		check(_pieces(fx) > base, "the effects are drawn")
		# the Pressure Palm's aura gathers while it charges and goes when it is let go
		fx.on_event({"type": "move_start", "fighter": 0, "slot": "lh_straight", "id": "f_varga.lh_pressure_palm", "pool": "pressure_palm", "cat": "projectile"})
		_state[0] = {"state": Fighter.State.ATTACK, "charge": 0.6}
		await wait_frames(20)
		var palm: Dictionary = kit._palms.get(0, {})
		check(not palm.is_empty() and palm.get("node") != null, "a charging palm gathers aura")
		_state[0] = {"state": Fighter.State.ATTACK, "charge": -1.0}
		await wait_frames(20)
		check(not (kit._palms as Dictionary).has(0), "letting go ends it")
		# a charge cut off by a hit ends too
		fx.on_event({"type": "move_start", "fighter": 0, "slot": "lh_straight", "id": "f_varga.lh_pressure_palm", "pool": "pressure_palm", "cat": "projectile"})
		_state[0] = {"state": Fighter.State.ATTACK, "charge": 0.3}
		await wait_frames(10)
		_state[0] = {"state": Fighter.State.HITSTUN, "charge": -1.0}
		await wait_frames(10)
		check(not (kit._palms as Dictionary).has(0), "an interrupted charge ends")
		_state.clear()
		# entities: the blast, the crescent and the crater are drawn, follow their entity and clean up
		var ents := func(z: float) -> Array:
			return [{"id": 1, "kind": "projectile", "vfx": "varga_pressure_blast", "pos": Vector3(0, 1.3, z), "radius": 0.48, "element": "scrap", "team": 0},
				{"id": 2, "kind": "projectile", "vfx": "varga_crescent_wave", "pos": Vector3(0, 1.5, z), "radius": 0.42, "element": "scrap", "team": 0},
				{"id": 3, "kind": "zone", "vfx": "varga_meteor_crater", "pos": Vector3(0, 0, 1.0), "radius": 1.4, "element": "", "team": 0}]
		fx.sync_entities(ents.call(0.6))
		check(fx._ents.has(1) and fx._ents.has(2) and fx._ents.has(3), "the blast, the crescent and the crater are drawn")
		var blast: Node3D = (fx._ents[1] as Dictionary)["node"]
		var wave: Node3D = (fx._ents[2] as Dictionary)["node"]
		var crater: Node3D = (fx._ents[3] as Dictionary)["node"]
		for k in 6:
			fx.sync_entities(ents.call(0.6 + 0.3 * k))
			await wait_frames(2)
		check(is_equal_approx(blast.global_position.z, 2.1), "the blast flies with its projectile (%.2f)" % blast.global_position.z)
		check(is_equal_approx(wave.global_position.z, 2.1), "the crescent flies with its projectile")
		fx.sync_entities([])
		# everything fades and frees itself
		await wait_frames(360)
		check(not is_instance_valid(blast) and not is_instance_valid(wave) and not is_instance_valid(crater), "entity looks are freed")
		check_eq(_pieces(fx), base, "quality %d: every piece is cleaned up" % quality)
		check((kit._palms as Dictionary).is_empty(), "no palm left gathering")
		_free_fx(fx, views)
		await wait_frames(2)
