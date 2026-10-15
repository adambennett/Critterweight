extends "res://src/test/kits/npc_kit_case.gd"
## Minion kits (ENEMIES_BOSSES.md §1): Scrapling (npc_scrapling), its Pelter variant
## (npc_scrapling_pelter, used by Chum Rush as "npc_scrapling#pelter") and Blister (npc_blister).
## Moves connect at range and miss outside it; Lid Up shields only the front; thrown Scraplings
## are projectiles; pack AI lets two attack at once; Pelters keep range and lob bolts; Blisters
## inflate and pop (consuming themselves), death-pop when killed, explode where they land when
## thrown (credited to the thrower, setting off nearby Blisters) and never inflate side by side;
## a Scrapling dies in a few clean hits.
## Run: godot --headless --path game --fixed-fps 120 -- --test test_kit_minions
##      (--kit-report [--kit-target id] prints range tables)

const SCRAP := "npc_scrapling"
const PELTER := "npc_scrapling_pelter"
const BLISTER := "npc_blister"
const DUMMY := "f_stoke"
## Low-hitting attacker for knee-high minions (the 1.5 m stubs' jabs pass over a 1 m gremlin).
const PUNCHER := "npc_kid_lamprey"
## Grabber/thrower with frozen default throws (dev_biped.json is never edited by kit owners).
const THROWER := "dev_biped"


func _scrap_moves() -> Array:
	return [
		["l1", press("light"), 1.8],
		["l2", string_presses(2, 0.45), 2.2],
		["heavy", press("heavy"), 2.2],
		["dash_attack", dash_presses(0.1), 2.0],
	]


func _blister_moves() -> Array:
	return [
		["l1", press("light"), 1.8],
		["heavy", press("heavy"), 2.0],
	]


## slot -> [near gaps that must land, far gap that must not, min clean dmg, max] vs Stoke.
const SCRAP_RANGES := {
	"l1": [[0.6, 1.0], 1.5, 3.0, 7.0],
	"l2": [[0.7, 0.85], 1.5, 1.0, 4.5],
	"heavy": [[0.8, 1.0], 1.5, 5.0, 11.0],
	"dash_attack": [[1.2, 1.6], 2.6, 1.0, 5.0],
}
const BLISTER_RANGES := {
	"l1": [[0.8, 1.2], 2.0, 1.0, 3.5],
	"heavy": [[1.0, 1.6], 2.4, 2.0, 6.0],
}


# ---------------------------------------------------------------------------------------------
# Data

func test_minion_kits_complete_and_valid() -> void:
	for id in [SCRAP, PELTER, BLISTER]:
		var c := Content.creature(id)
		check(c != null, "%s loads" % id)
		if c == null:
			continue
		check(c.is_valid(), "%s has no errors: %s" % [id, ", ".join(c.errors)])
		check(c.npc_only, "%s is npc_only" % id)
		var raw := Content.creature_entry(id)
		check(not (raw["stats"] as Dictionary).has("dodge_speed"), "%s: no unknown dodge_speed stat" % id)
		for slot in ["l1", "heavy", "dash_attack", "grab", "pummel", "taunt"]:
			check(c.moves.has(slot), "%s has %s" % [id, slot])
			check(not bool((raw["moves"] as Dictionary).get(slot, {}).get("_stub", false)), "%s.%s is not a stub" % [id, slot])
		for k in ["throw_fwd", "throw_back", "throw_side"]:
			check(c.throws.has(k), "%s throw %s" % [id, k])
	var s := Content.creature(SCRAP)
	check_eq(s.light_string, ["l1", "l2"], "Pipe Swing -> Lid Bash")
	check_eq((s.moves["l1"] as MoveDef).display_name, "Pipe Swing", "campaign slot convention l1")
	check_eq((s.moves["l2"] as MoveDef).display_name, "Lid Bash", "campaign slot convention l2")
	check_eq((s.abilities["ability1"] as MoveDef).display_name, "Lid Up", "campaign slot convention ability1")
	check(not s.abilities.has("ability2"), "only Pelters carry Bolt Toss")
	var p := Content.creature(PELTER)
	check_eq((p.abilities["ability2"] as MoveDef).display_name, "Bolt Toss", "Pelter ability2")
	check(p.abilities.has("ability1"), "Pelter keeps Lid Up (extends the Scrapling)")
	check(not p.ai.has("pack") and float(p.ai.get("keep_distance", 0.0)) == 4.0, "Pelter keeps 4 m and is not in the melee pack")
	var b := Content.creature(BLISTER)
	var pop: MoveDef = b.abilities["ability1"]
	check_eq(pop.display_name, "Inflate & Pop", "campaign slot convention Blister ability1")
	var types := []
	for e in pop.effects:
		types.append(str(e.get("type", "")))
	check(types.has("area") and types.has("zone"), "Inflate & Pop has the area + zone the loadout recipes patch (%s)" % str(types))
	check_eq(b.element, "sludge", "Blister element")


# ---------------------------------------------------------------------------------------------
# Scrapling

func test_scrapling_moves_connect_in_range_and_miss_outside() -> void:
	for m in _scrap_moves():
		var slot := str(m[0])
		var spec: Array = SCRAP_RANGES[slot]
		var best := 0.0
		for gap in spec[0]:
			var r := await shoot(SCRAP, DUMMY, float(gap), m[1], m[2])
			check(slot_hits(r, slot) >= 1, "Scrapling %s lands at %.2f m (hits %s, glances %d)" % [slot, gap, str(r["slots"]), int(r["glances"])])
			if slot_hits(r, slot) >= 1:
				best = maxf(best, float((r["slot_dmg"] as Dictionary).get(slot, 0.0)) / float(slot_hits(r, slot)))
			check(float(r["reach"]) <= 1.6, "%s reach %.2f m" % [slot, r["reach"]])
			check(float(r["min_up"]) >= 0.75, "%s keeps the Scrapling upright (%.2f)" % [slot, r["min_up"]])
		check(best >= float(spec[2]) and best <= float(spec[3]), "Scrapling %s clean damage %.1f within [%.1f, %.1f]" % [slot, best, spec[2], spec[3]])
		var far := await shoot(SCRAP, DUMMY, float(spec[1]), m[1], m[2])
		check(slot_hits(far, slot) == 0, "Scrapling %s misses at %.2f m (hits %s)" % [slot, spec[1], str(far["slots"])])
	var bash := await shoot(SCRAP, DUMMY, 0.9, string_presses(2, 0.45), 2.2)
	check(float(bash["push"]) >= 0.4, "Lid Bash shoves (%.2f m)" % bash["push"])


## Lid Up: hits from the front are absorbed (90%), the sides and back are open, grabs ignore it.
## (A lobbed bolt is the probe: the stance lid also deflects punches physically, see minions.md.)
func test_lid_up_shields_only_the_front() -> void:
	# (the input tracker primes on the first tick, so the earliest usable press is the second)
	var lid_now := [{"t0": 0.02, "t1": 0.06, "press": ["ability1"]}]
	var jab := at([{"t0": 0.05, "t1": 0.1, "press": ["ability2"]}])
	var front := await _vs(SCRAP, PELTER, 4.0, lid_now, jab, Callable())
	var open := await _vs(SCRAP, PELTER, 4.0, [], jab, Callable())
	var taken_front := 0.0
	var blocked_front := 0
	for ev in front["events"]:
		if str(ev["type"]) == "hit" and int(ev["fighter"]) == 1:
			taken_front += float(ev["damage"])
			blocked_front += 1 if bool(ev["blocked"]) else 0
	var taken_open := 0.0
	for ev in open["events"]:
		if str(ev["type"]) == "hit" and int(ev["fighter"]) == 1:
			taken_open += float(ev["damage"])
	check(blocked_front >= 1, "a bolt from the front is blocked by the lid")
	check(taken_open > 0.0 and taken_front <= taken_open * 0.2, "the lid absorbs ~90%% (%.2f vs %.2f open)" % [taken_front, taken_open])
	# from behind: raising the lid normally snaps it toward the target (attack assist), so the
	# Scrapling holds the stick away; once up, the lid turns at only 1 rad/s
	var behind := func(sim: MatchSim) -> void:
		sim.fighters[0].rig.place(Vector3(0, 0, -2.0), PI)
		sim.fighters[0].facing_yaw = PI
	var lid_away := [{"t0": 0.02, "t1": 0.06, "press": ["ability1"]}, {"t0": 0.0, "t1": 2.2, "move": Vector3(0, 0, -1)}]
	var back := await _vs(SCRAP, PELTER, 4.0, lid_away, jab, behind)
	var taken_back := 0.0
	var blocked_back := 0
	for ev in back["events"]:
		if str(ev["type"]) == "hit" and int(ev["fighter"]) == 1:
			taken_back += float(ev["damage"])
			blocked_back += 1 if bool(ev["blocked"]) else 0
	check(taken_back > 0.0 and blocked_back == 0, "the back is open (%.1f taken, %d blocked)" % [taken_back, blocked_back])
	var grab := await _vs(SCRAP, PUNCHER, 0.95, lid_now, at([{"t0": 0.05, "t1": 0.1, "press": ["grab"]}]), Callable())
	check(count(grab["events"], "grab", "fighter", 1) >= 1, "grabs ignore Lid Up")


## A thrown Scrapling is a 6-damage projectile that knocks down the Scraplings it lands on,
## credited to the thrower.
func test_thrown_scrapling_is_a_projectile() -> void:
	var r := await _throw_into_pack(SCRAP, [SCRAP, SCRAP])
	check(int(r["throws"]) == 1, "Stoke throws the Scrapling")
	check(int(r["pack_hits"]) >= 1, "the thrown Scrapling hits the pack (hits %d)" % r["pack_hits"])
	check(int(r["pack_knockdowns"]) >= 1, "and knocks a Scrapling down (%d)" % r["pack_knockdowns"])
	check(float(r["max_hit"]) >= 4.0 and float(r["max_hit"]) <= 8.0, "about 6 damage (%.1f)" % r["max_hit"])


## Pack AI: with four Scraplings on one target at most two swing at once; the rest circle and
## raise their lids when the target swings at them; a nearby KO makes the pack flinch.
func test_scrapling_pack_takes_turns() -> void:
	var sim := _arena_sim([[DUMMY, 0, Vector3(0, 0, 0), InputSource.Scripted.new([{"t0": 1.0, "t1": 12.0, "press": ["light"], "every": 0.9}])],
		[SCRAP, 1, Vector3(1.8, 0, 0), null], [SCRAP, 1, Vector3(-1.8, 0, 0), null], [SCRAP, 1, Vector3(0, 0, 1.8), null], [SCRAP, 1, Vector3(0, 0, -1.8), null]], "regular")
	var dt := 1.0 / Engine.physics_ticks_per_second
	var over := 0
	var ticks := 0
	var lids := 0
	var cursor := 0
	while sim.time < 10.0:
		sim.step(dt)
		await get_tree().physics_frame
		var attacking := 0
		for i in range(1, sim.fighters.size()):
			var f := sim.fighters[i]
			if f.state == Fighter.State.ATTACK and not f.move_slot.begins_with("grab"):
				attacking += 1
		ticks += 1
		if attacking > 2:
			over += 1
		for ev in sim.events_since(cursor):
			cursor = int(ev["seq"])
			if str(ev["type"]) == "ability" and str(ev.get("slot", "")) == "ability1":
				lids += 1
	check(float(over) / float(ticks) < 0.05, "at most two Scraplings swing at once (%.1f%% of ticks over)" % (100.0 * over / ticks))
	check(lids >= 1, "waiting Scraplings raise their lids (%d)" % lids)
	check(sim.fighters[0].stats_record["damage_taken"] > 0.0, "the pack does attack")
	sim.get_parent().queue_free()


## "A Scrapling should die in a few clean hits": body-height lights and Heavies finish one in a
## handful of landed hits (30 HP). Measured with the Kid's kit (stable); the roster stubs' numbers
## are printed for the record only, since their kits are being authored elsewhere.
func test_scrapling_dies_in_a_few_clean_hits() -> void:
	for spec in [[PUNCHER, "light", 0.95, 0.24, true], [PUNCHER, "heavy", 1.0, 1.0, false], ["f_jitters", "light", 0.9, 0.3, false], ["f_dozer", "light", 1.5, 0.5, false]]:
		var sim := duel(str(spec[0]), SCRAP, float(spec[2]), InputSource.Scripted.new([{"t0": 0.3, "t1": 30.0, "press": [spec[1]], "every": spec[3], "move": "to_target"}]), null)
		var dt := 1.0 / Engine.physics_ticks_per_second
		var hits := 0
		var cursor := 0
		var dead := false
		while sim.time < 20.0 and not dead:
			sim.step(dt)
			await get_tree().physics_frame
			for ev in sim.events_since(cursor):
				cursor = int(ev["seq"])
				# a clean hit: unblocked, on a standing Scrapling, a real blow (>= 2), not a graze
				if str(ev["type"]) == "hit" and int(ev["fighter"]) == 0 and not bool(ev["blocked"]) and not bool(ev.get("otg", false)) \
						and float(ev["damage"]) >= 2.0:
					hits += 1
					if OS.get_cmdline_user_args().has("--kit-ttk"):
						print("   hit %s %.1f at %.2f hp %.1f" % [str(ev.get("slot", "")), float(ev["damage"]), sim.time, sim.fighters[1].health])
			dead = sim.fighters[1].is_out()
		print("SCRAPLING TTK: %s %s -> %d clean hits (dead %s, %.1f s)" % [spec[0], spec[1], hits, dead, sim.time])
		if bool(spec[4]):
			check(dead, "%s kills a Scrapling with %ss" % [spec[0], spec[1]])
			check(hits <= (3 if spec[1] == "heavy" else 8), "%s needs only a few clean hits (%d)" % [spec[0], hits])
		sim.get_parent().queue_free()


# ---------------------------------------------------------------------------------------------
# Pelter

func test_pelter_lobs_bolts_and_keeps_distance() -> void:
	var r := await shoot(PELTER, DUMMY, 4.0, at([{"t0": 0.0, "t1": 3.0, "press": ["ability2"], "every": 0.25}]), 3.6)
	var uses := count(r["events"], "ability", "fighter", 0)
	var bolt_hits := 0
	for ev in r["events"]:
		if str(ev["type"]) == "hit" and int(ev["fighter"]) == 0 and str(ev.get("slot", "")) == "effect":
			bolt_hits += 1
			check(float(ev["damage"]) >= 2.0 and float(ev["damage"]) <= 4.0, "a bolt deals ~3 (%.1f)" % ev["damage"])
	check(uses == 2, "Bolt Toss twice in 3 s with a 2 s cooldown (%d)" % uses)
	check(bolt_hits >= 1, "lobbed bolts land on a target 4 m away (%d)" % bolt_hits)
	# the bot backs off to its 4 m and pelts
	var sim := _arena_sim([[DUMMY, 0, Vector3(0, 0, -1.0), InputSource.Scripted.new([])],
		[PELTER, 1, Vector3(0, 0, 0.5), null]], "regular")
	var dt := 1.0 / Engine.physics_ticks_per_second
	var dsum := 0.0
	var n := 0
	var tosses := 0
	var cursor := 0
	while sim.time < 9.0:
		sim.step(dt)
		await get_tree().physics_frame
		if sim.time > 2.0:
			dsum += sim.fighters[0].pos().distance_to(sim.fighters[1].pos())
			n += 1
		for ev in sim.events_since(cursor):
			cursor = int(ev["seq"])
			if str(ev["type"]) == "ability" and int(ev["fighter"]) == 1:
				tosses += 1
	check(dsum / n >= 3.0, "the Pelter keeps its distance (mean %.2f m)" % (dsum / n))
	check(tosses >= 2, "and keeps pelting (%d bolts)" % tosses)
	sim.get_parent().queue_free()


func test_chum_rush_resolves_pelter_variant() -> void:
	var mode := ChumRushMode.new()
	var c := mode._resolve("npc_scrapling#pelter")
	check(c != null and c.id == PELTER, "npc_scrapling#pelter resolves to %s (got %s)" % [PELTER, c.id if c else "null"])
	check(mode._resolve("npc_scrapling").id == SCRAP, "plain ids still resolve")
	check(mode._resolve("npc_blister#nope").id == BLISTER, "unknown variants fall back to the base creature")
	check(mode._resolve("boss_bilge@hp:0.60").id == "boss_bilge", "headliner specs still resolve")


# ---------------------------------------------------------------------------------------------
# Blister

func test_blister_moves_connect_in_range_and_miss_outside() -> void:
	for m in _blister_moves():
		var slot := str(m[0])
		var spec: Array = BLISTER_RANGES[slot]
		var best := 0.0
		for gap in spec[0]:
			var r := await shoot(BLISTER, DUMMY, float(gap), m[1], m[2])
			check(slot_hits(r, slot) >= 1, "Blister %s lands at %.2f m (hits %s)" % [slot, gap, str(r["slots"])])
			if slot_hits(r, slot) >= 1:
				best = maxf(best, float((r["slot_dmg"] as Dictionary).get(slot, 0.0)) / float(slot_hits(r, slot)))
			check(float(r["min_up"]) >= 0.8, "Blister %s stays upright" % slot)
		check(best >= float(spec[2]) and best <= float(spec[3]), "Blister %s clean damage %.1f within [%.1f, %.1f]" % [slot, best, spec[2], spec[3]])
		var far := await shoot(BLISTER, DUMMY, float(spec[1]), m[1], m[2])
		check(slot_hits(far, slot) == 0, "Blister %s misses at %.2f m" % [slot, spec[1]])


## Inflate & Pop: 1.2 s armored inflation, then a 2 m pop (12, Sludge 40) and a puddle; the
## Blister is consumed and does not death-pop on top of it.
func test_blister_inflate_and_pop() -> void:
	var each := func(sim: MatchSim, out: Dictionary) -> void:
		for e in sim.effects.entities:
			if str(e["kind"]) == "zone" and str(e.get("zone_kind", "")) == "sludge_puddle":
				out["puddle"] = true
		var k := sim.fighters[1]
		if OS.get_cmdline_user_args().has("--kit-events") and k.move != null:
			var line := "t=%.2f kid %s st=%.2f root(%.2f,%.2f,%.2f) blister(%.2f,%.2f,%.2f) state %s" % [sim.time, k.move_slot, k.state_time,
				k.pos().x, k.pos().y, k.pos().z, sim.fighters[0].pos().x, sim.fighters[0].pos().y, sim.fighters[0].pos().z, Fighter.State.keys()[sim.fighters[0].state]]
			for wn in ["fist_l", "fist_r"]:
				var wd: BodyDef.Weapon = k.creature.body.weapons[wn]
				var wp := k.rig.bodies[wd.seg].global_transform * wd.local
				line += " %s(%.2f,%.2f,%.2f)" % [wn, wp.x, wp.y, wp.z]
			for c in sim.combat.debug_contacts:
				line += " CONTACT vn=%.2f" % c["vn"]
			print(line)
	# the puncher steps in, plants, then jabs (walking through the jab only shoves the Blister)
	var r := await shoot(BLISTER, PUNCHER, 1.3, press("ability1"), 2.2, at([{"t0": 0.4, "t1": 0.6, "move": "to_target"}, {"t0": 0.66, "t1": 0.71, "press": ["light"]}]), Callable(), 6.0, each)
	var pops := []
	var jabbed := false
	if OS.get_cmdline_user_args().has("--kit-events"):
		for ev in r["events"]:
			print("   ", JSON.stringify(ev).substr(0, 200))
	for ev in r["events"]:
		if str(ev["type"]) == "hit" and int(ev["fighter"]) == 0 and str(ev.get("move_class", "")) == "pop":
			pops.append(float(ev["damage"]))
		if str(ev["type"]) == "hit" and int(ev["fighter"]) == 1 and int(ev["target"]) == 0:
			jabbed = true
	check(pops.size() == 1, "exactly one pop hits the puncher (%s)" % str(pops))
	check(jabbed, "the puncher jabbed the inflating Blister (armor keeps it inflating)")
	if pops.size() >= 1:
		check(float(pops[0]) >= 9.0 and float(pops[0]) <= 15.0, "full pop ~12 (%.1f)" % float(pops[0]))
	check(float((r["b_buildup"] as Dictionary).get("sludge", 0.0)) >= 25.0 or (r["b_statuses"] as Array).has("gunked"), "Sludge build-up from the pop")
	check(bool(r.get("puddle", false)), "the pop leaves a sludge puddle")
	check(count(r["events"], "ko", "fighter", 0) == 1, "the Blister is consumed by its pop")
	check(count(r["events"], "ability", "fighter", 0) == 1, "inflated once")


## Death Pop: killed before inflating, a Blister bursts at half size (r 1 m, 6) — dangerous in
## melee, harmless at range.
func test_blister_death_pop() -> void:
	var low := func(sim: MatchSim) -> void: sim.fighters[1].health = 1.0
	var melee := await shoot(PUNCHER, BLISTER, 0.95, press("light"), 1.6, [], low)
	var pop_on_puncher := 0.0
	for ev in melee["events"]:
		if str(ev["type"]) == "hit" and int(ev["fighter"]) == 1 and int(ev["target"]) == 0:
			pop_on_puncher += float(ev["damage"])
	check(count(melee["events"], "ko", "fighter", 1) == 1, "the jab kills the Blister")
	check(pop_on_puncher >= 3.0 and pop_on_puncher <= 9.0, "its Death Pop hits the puncher (~6: %.1f)" % pop_on_puncher)
	var ranged := await shoot(PELTER, BLISTER, 4.0, press("ability2"), 2.4, [], low)
	var pop_far := 0.0
	for ev in ranged["events"]:
		if str(ev["type"]) == "hit" and int(ev["fighter"]) == 1 and int(ev["target"]) == 0:
			pop_far += float(ev["damage"])
	check(count(ranged["events"], "ko", "fighter", 1) == 1, "a lobbed bolt kills it at range")
	check(pop_far == 0.0, "killed at range, the Death Pop reaches nobody (%.1f)" % pop_far)


## A thrown Blister is a live bomb: it pops where it lands, credited to the thrower, hurting the
## minions there (and setting off a nearby Blister's Death Pop), never the thrower.
func test_thrown_blister_is_a_live_bomb() -> void:
	var r := await _throw_into_pack(BLISTER, [SCRAP, SCRAP, BLISTER])
	check(int(r["throws"]) == 1, "Stoke throws the Blister")
	check(int(r["pack_hits"]) >= 2, "the landing pop hits the pack (hits %d)" % r["pack_hits"])
	check(float(r["max_hit"]) >= 9.0, "full-size pop damage (%.1f)" % r["max_hit"])
	check(bool(r["blister_chain"]), "the nearby Blister is set off")
	check(float(r["thrower_damage"]) == 0.0, "the thrower takes nothing (%.1f)" % r["thrower_damage"])


## Blisters never inflate within 1.5 m of an inflating Blister.
func test_blisters_never_inflate_side_by_side() -> void:
	var sim := _arena_sim([[DUMMY, 0, Vector3(0, 0, 0), null],
		[BLISTER, 1, Vector3(0.7, 0, 2.2), null], [BLISTER, 1, Vector3(-0.7, 0, 2.2), null], [BLISTER, 1, Vector3(0, 0, 2.9), null]], "pro")
	var dt := 1.0 / Engine.physics_ticks_per_second
	var violations := 0
	var inflations := 0
	var cursor := 0
	while sim.time < 8.0:
		sim.step(dt)
		await get_tree().physics_frame
		for ev in sim.events_since(cursor):
			cursor = int(ev["seq"])
			if str(ev["type"]) == "ability" and int(ev["fighter"]) > 0:
				inflations += 1
				var f := sim.fighters[int(ev["fighter"])]
				for o in sim.fighters:
					if o != f and o.team == f.team and o.state == Fighter.State.ABILITY and o.move_slot == "ability1" and o.pos().distance_to(f.pos()) < 1.5:
						violations += 1
	check(inflations >= 1, "Blisters inflate near their target (%d)" % inflations)
	check(violations == 0, "never next to an inflating Blister (%d violations)" % violations)
	sim.get_parent().queue_free()


# ---------------------------------------------------------------------------------------------
# helpers

## A sim with fighters [[creature, team, pos, source]] on a 5 m octagon; null sources become
## BotBrains of `tier` with the creature's personality. Fighters face the arena centre.
func _arena_sim(list: Array, tier: String) -> MatchSim:
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var entries := []
	var spawns := []
	for i in list.size():
		var e: Array = list[i]
		var c := Content.creature(str(e[0]))
		var src = e[3]
		if src == null:
			var bb := BotBrain.new(tier, 500 + i * 13)
			bb.set_personality(c.ai)
			src = bb
		entries.append({"creature": c, "team": int(e[1]), "source": src})
		var p: Vector3 = e[2]
		spawns.append([p.x, p.z, rad_to_deg(atan2(-p.x, -p.z)) if p.length() > 0.01 else 0.0])
	var arena := ArenaDef.from_dict({"id": "kit_pack", "base": "octagon", "radius": 5.0, "spawns": spawns})
	sim.setup({"arena": arena, "rules": {"rounds": 1, "round_time": 0, "intro_time": 0.0}, "seed": 9, "fighters": entries})
	return sim


## `minion` (fighter 0, `minion_steps`) against `attacker` (fighter 1, `attacker_steps`).
func _vs(minion: String, attacker: String, gap: float, minion_steps: Array, attacker_steps: Array, prep: Callable) -> Dictionary:
	return await shoot(minion, attacker, gap, minion_steps, 2.2, attacker_steps, prep)


## dev_biped grabs `thrown` and throws it forward onto `pack` (team 1), placed around the spot
## its default throw (2.5 m x mass ratio) lands. Grab and throw are applied directly so the
## scenario does not depend on any kit's grab reach.
func _throw_into_pack(thrown: String, pack: Array) -> Dictionary:
	var vc := Content.creature(thrown)
	var travel := 2.5 * clampf(sqrt(80.0 / maxf(20.0, vc.body.total_mass * vc.stat("weight"))), 0.5, 1.6)
	var start := Vector3(0, 0, -1.6)
	var land := start + Vector3(0, 0, travel)
	var list := [[THROWER, 0, Vector3(0, 0, -2.5), InputSource.Scripted.new([])], [thrown, 1, start, InputSource.Scripted.new([])]]
	var offsets := [Vector3(0.45, 0, 0), Vector3(-0.45, 0, 0), Vector3(0, 0, 0.6)]
	for i in pack.size():
		list.append([pack[i], 1, land + offsets[i], InputSource.Scripted.new([])])
	var sim := _arena_sim(list, "rookie")
	var dt := 1.0 / Engine.physics_ticks_per_second
	while sim.time < 0.5:
		sim.step(dt)
		await get_tree().physics_frame
	var a := sim.fighters[0]
	a.facing_yaw = 0.0
	a.begin_grab(sim.fighters[1], a.creature.body.seg_index["farm_r"], 0)
	a._do_throw(Vector3(0, 0, 1))
	var out := {"throws": 0, "pack_hits": 0, "pack_knockdowns": 0, "max_hit": 0.0, "thrower_damage": 0.0, "blister_chain": false}
	var cursor := 0
	while sim.time < 3.5:
		sim.step(dt)
		await get_tree().physics_frame
		for ev in sim.events_since(cursor):
			cursor = int(ev["seq"])
			match str(ev["type"]):
				"throw":
					if int(ev["fighter"]) == 0:
						out["throws"] = int(out["throws"]) + 1
				"hit":
					var tg := int(ev["target"])
					if tg >= 2 and int(ev["fighter"]) == 0:
						out["pack_hits"] = int(out["pack_hits"]) + 1
						out["max_hit"] = maxf(float(out["max_hit"]), float(ev["damage"]))
					if tg == 0 and str(ev.get("move", "")) != "throw":
						out["thrower_damage"] = float(out["thrower_damage"]) + float(ev["damage"])
				"knockdown":
					if int(ev["fighter"]) >= 2:
						out["pack_knockdowns"] = int(out["pack_knockdowns"]) + 1
				"ko":
					var ki := int(ev["fighter"])
					if ki >= 2 and sim.fighters[ki].creature.id == BLISTER:
						out["blister_chain"] = true
	sim.get_parent().queue_free()
	return out


# ---------------------------------------------------------------------------------------------
# Tuning aids (opt-in, no assertions)

func test_zz_debug_lid() -> void:
	if not OS.get_cmdline_user_args().has("--kit-lid"):
		return
	var each := func(sim: MatchSim, _out: Dictionary) -> void:
		var k := sim.fighters[1]
		var s := sim.fighters[0]
		if k.move != null:
			var line := "t=%.2f kid %s st=%.2f w=%d" % [sim.time, k.move_slot, k.state_time, k.move.window_index(k.state_time)]
			for w in k.move.windows:
				for wn in w["weapons"]:
					var wd: BodyDef.Weapon = k.creature.body.weapons[wn]
					var wp := k.rig.bodies[wd.seg].global_transform * wd.local
					line += " %s(%.2f,%.2f,%.2f)" % [wn, wp.x, wp.y, wp.z]
			line += " | scrap root (%.2f,%.2f,%.2f) state %s yaw %.2f" % [s.pos().x, s.pos().y, s.pos().z, s.state_name(), s.facing_yaw]
			print(line)
	var r := await shoot(SCRAP, PUNCHER, 0.95, [], 1.8, at([{"t0": 0.05, "t1": 0.1, "press": ["light"]}]), Callable(), 6.0, each)
	for ev in r["events"]:
		if str(ev["type"]) in ["hit", "glance", "move_start"]:
			print(ev)


## `--kit-debug <creature> <slot> <gap> [target]`: per-tick weapon positions and contacts.
func test_zz_debug_contacts() -> void:
	var args := OS.get_cmdline_user_args()
	var di := args.find("--kit-debug")
	if di < 0:
		return
	var who := args[di + 1]
	var slot := args[di + 2]
	var gap := float(args[di + 3])
	var target: String = args[di + 4] if args.size() > di + 4 and not args[di + 4].begins_with("--") else DUMMY
	var steps: Array = []
	var secs := 2.0
	for m in (_scrap_moves() if who != BLISTER else _blister_moves()):
		if str(m[0]) == slot:
			steps = m[1]
			secs = m[2]
	var each := func(sim: MatchSim, _out: Dictionary) -> void:
		var a := sim.fighters[0]
		var b := sim.fighters[1]
		if a.move == null:
			return
		var line := "st=%.3f %s w=%d root(%.2f,%.2f) tgt(%.2f)" % [a.state_time, a.move_slot, a.move.window_index(a.state_time), a.pos().y, a.pos().z, b.pos().z]
		for w in a.move.windows:
			for wn in w["weapons"]:
				var wd: BodyDef.Weapon = a.creature.body.weapons[wn]
				var wp := a.rig.bodies[wd.seg].global_transform * wd.local
				line += " %s(%.2f,%.2f,%.2f)" % [wn, wp.x, wp.y, wp.z]
		for c in sim.combat.debug_contacts:
			line += " CONTACT n=(%.2f,%.2f,%.2f) vn=%.2f" % [c["normal"].x, c["normal"].y, c["normal"].z, c["vn"]]
		print(line)
	var r := await shoot(who, target, gap, steps, secs, [], Callable(), 6.0, each)
	print("hits ", r["slots"], " glances ", r["glances"])


func test_zz_report_ranges() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--kit-report"):
		return
	var targets: Array = ["f_stoke", "f_jitters", "f_gusto", "f_dredge"]
	var ti := args.find("--kit-target")
	if ti >= 0 and ti + 1 < args.size():
		targets = [args[ti + 1]]
	for spec in [[SCRAP, _scrap_moves()], [BLISTER, _blister_moves()]]:
		for target in targets:
			for m in spec[1]:
				var line := "%-13s %-10s %-12s" % [spec[0], target, m[0]]
				for gap in [0.6, 0.8, 1.0, 1.2, 1.4, 1.6, 1.8, 2.2, 2.6]:
					var r := await shoot(spec[0], target, gap, m[1], m[2])
					line += " %.1f:%d/%.0f%s" % [gap, slot_hits(r, str(m[0])), float((r["slot_dmg"] as Dictionary).get(str(m[0]), 0.0)),
						("g%d" % int(r["glances"])) if int(r["glances"]) > 0 else ""]
					if is_equal_approx(gap, 1.0):
						line += "[reach %.2f up %.2f spin %.1f push %.2f]" % [r["reach"], r["min_up"], r["max_spin"], r["push"]]
				print(line)
