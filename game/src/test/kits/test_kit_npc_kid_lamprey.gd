extends "res://src/test/kits/npc_kit_case.gd"
## Kid Lamprey (npc_kid_lamprey) kit: every move connects at its intended range against a
## standing dummy (f_stoke, the roster's reference biped) and misses outside it; push, launch,
## stun, guard, parry, armor, cooldowns, counter stance, grabs/pummel/throws, taunt and JUICE
## behave; Granny's tutorial behaviours work with the real Kid against every roster body; and
## the balance target holds (loses most bouts to a roster bot of the same tier but lands hits).
## Run: godot --headless --path game --fixed-fps 120 -- --test test_kit_npc_kid_lamprey
##      add --balance for the full >= 20-bout tables, --kit-report [--kit-target id] for ranges.

const KID := "npc_kid_lamprey"
const DUMMY := "f_stoke"
const ROSTER := ["f_stoke", "f_dredge", "f_gusto", "f_dozer", "f_slurry", "f_jitters"]
const REACH_CAP := 1.6
## Players whose body keeps the Kid farther than KidScript's fixed 1.05 m approach (tutorial gap).
const KIDSCRIPT_UNREACHABLE := ["f_dozer"]


## [slot, inputs, seconds] for each scripted move; the counted slot is the first entry.
func _moves() -> Array:
	return [
		["l1", press("light"), 1.6],
		["l2", string_presses(2), 1.8],
		["l3", string_presses(3), 2.0],
		["heavy", press("heavy"), 2.0],
		["heavy_charged", hold("heavy", 0.0, 1.1), 3.0],
		["finisher", finisher_presses(2), 2.0],
		["dash_attack", dash_presses(0.12), 2.0],
		["ability1", press("ability1"), 2.0],
	]


## slot -> [near gaps that must land it, far gap that must not, min dmg, max dmg] (vs Stoke).
const RANGES := {
	"l1": [[0.9, 1.0], 1.35, 2.5, 6.5],
	"l2": [[1.0, 1.2], 1.75, 3.0, 8.0],
	"l3": [[0.9, 1.6], 2.3, 3.0, 11.0],
	"heavy": [[1.0, 1.2], 1.65, 6.0, 16.0],
	"heavy_charged": [[1.0, 1.3], 1.85, 10.0, 30.0],
	"finisher": [[1.0, 1.2], 1.9, 5.0, 14.0],
	"dash_attack": [[1.6, 2.0], 3.2, 2.0, 10.0],
	"ability1": [[1.2, 1.6], 2.4, 4.0, 11.0],
}


func test_kit_is_complete_and_valid() -> void:
	var c := Content.creature(KID)
	check(c != null, "Kid Lamprey loads")
	if c == null:
		return
	check(c.is_valid(), "no creature errors: %s" % ", ".join(c.errors))
	check(c.npc_only, "npc_only")
	var raw := Content.creature_entry(KID)
	for slot in ["l1", "l2", "l3", "heavy", "heavy_charged", "finisher", "dash_attack", "grab", "pummel", "taunt"]:
		check(c.moves.has(slot), "move slot %s" % slot)
		check(not bool((raw["moves"] as Dictionary).get(slot, {}).get("_stub", false)), "%s is not a stub" % slot)
	for slot in ["ability1", "ability2", "juice"]:
		check(c.abilities.has(slot), "ability slot %s" % slot)
	for k in ["throw_fwd", "throw_back", "throw_side"]:
		check(c.throws.has(k), "throw %s" % k)
	check_eq(c.light_string, ["l1", "l2", "l3"], "light string")
	check(float(c.cooldowns.get("ability1", 0.0)) > 0.0 and float(c.cooldowns.get("ability2", 0.0)) > 0.0, "ability cooldowns")
	check_near((c.moves["taunt"] as MoveDef).duration, 1.5, 0.01, "taunt 1.5 s")
	check_near((c.abilities["juice"] as MoveDef).duration, 0.5, 0.01, "JUICE activation 0.5 s")
	check(c.body.total_mass >= 55.0 and c.body.total_mass <= 65.0, "about 60 kg (%.1f)" % c.body.total_mass)
	check(c.body.height >= 1.3 and c.body.height <= 1.5, "about 1.4 m tall (%.2f)" % c.body.height)
	check(c.body.chains.has("arm_l") and c.body.chains.has("leg_r"), "biped chains")
	for k in ["health", "walk_speed", "stamina", "poise", "dodge_distance", "dodge_time"]:
		check((raw["stats"] as Dictionary).has(k), "stat %s set" % k)
	check(not (raw["stats"] as Dictionary).has("dodge_speed"), "no unknown dodge_speed stat")
	var hint: Dictionary = (c.ai.get("abilities", {}) as Dictionary).get("ability2", {})
	check(JSON.stringify(hint.get("when", [])).contains("target_winding"), "bot answers wind-ups with Hood Up (kit hint)")


## Every move lands its own slot at its intended range against a standing Stoke, misses beyond
## it, deals damage in its band (judged on its cleanest landing: grazes on guard arms are
## legitimately weaker), keeps every weapon within the 1.6 m reach cap, and leaves the Kid
## upright and inside the cage.
func test_moves_connect_in_range_and_miss_outside() -> void:
	for m in _moves():
		var slot := str(m[0])
		var spec: Array = RANGES[slot]
		var best := 0.0
		for gap in spec[0]:
			var r := await shoot(KID, DUMMY, float(gap), m[1], m[2])
			var dmg := float((r["slot_dmg"] as Dictionary).get(slot, 0.0))
			check(slot_hits(r, slot) >= 1, "%s lands at %.2f m (hits %s, glances %d)" % [slot, gap, str(r["slots"]), int(r["glances"])])
			if slot_hits(r, slot) >= 1:
				best = maxf(best, dmg / float(slot_hits(r, slot)))
			check(float(r["reach"]) <= REACH_CAP, "%s weapon reach %.2f m <= %.1f m" % [slot, r["reach"], REACH_CAP])
			check(float(r["min_up"]) >= 0.8, "%s keeps the Kid upright (%.2f)" % [slot, r["min_up"]])
			check(float(r["max_spin"]) < 12.0, "%s never spins the Kid out (%.1f rad/s)" % [slot, r["max_spin"]])
			check(bool(r["a_inside"]), "%s stays inside the cage" % slot)
		check(best >= float(spec[2]) and best <= float(spec[3]), "%s clean damage %.1f within [%.0f, %.0f]" % [slot, best, spec[2], spec[3]])
		var far := await shoot(KID, DUMMY, float(spec[1]), m[1], m[2])
		check(slot_hits(far, slot) == 0, "%s misses at %.2f m (hits %s)" % [slot, spec[1], str(far["slots"])])


## The light string chains L1 -> L2 -> L3 on a standing target at boxing range, the third hit
## is the shove, the finisher launches, a Heavy stuns.
func test_string_shove_launch_and_stun() -> void:
	var s := await shoot(KID, DUMMY, 1.0, string_presses(3), 2.2)
	for slot in ["l1", "l2", "l3"]:
		check(slot_hits(s, slot) >= 1, "%s lands inside the string (hits %s)" % [slot, str(s["slots"])])
	var l3 := await shoot(KID, DUMMY, 1.0, string_presses(3), 2.2)
	check(float(l3["push"]) >= 0.6, "the string's third hit shoves (%.2f m)" % l3["push"])
	var fin := await shoot(KID, DUMMY, 1.0, finisher_presses(2), 2.2)
	check(slot_hits(fin, "finisher") >= 1, "finisher lands from the cancel window (hits %s)" % str(fin["slots"]))
	check(float(fin["lift"]) >= 0.15, "Gutter Uppercut lifts the target (%.2f m)" % fin["lift"])
	var hv := await shoot(KID, DUMMY, 1.1, press("heavy"), 2.0)
	check(float((hv["b_states"] as Dictionary).get("hitstun", 0.0)) >= 0.25, "Big Swing stuns (%.2f s)" % float((hv["b_states"] as Dictionary).get("hitstun", 0.0)))
	check(float(hv["push"]) >= 0.4, "Big Swing pushes (%.2f m)" % hv["push"])


## Guard absorbs most of a hit; a late tap parries and staggers the Kid.
func test_guard_blocks_and_parry_staggers() -> void:
	var open := await shoot(KID, DUMMY, 1.05, press("heavy"), 2.0)
	var guarded := await shoot(KID, DUMMY, 1.05, press("heavy"), 2.0, [{"t0": 0.0, "t1": 3.0, "hold": ["guard"]}])
	check(int(guarded["blocked"]) >= 1, "a guarding Stoke blocks Big Swing (blocked %d, hits %d)" % [guarded["blocked"], guarded["hits"]])
	check(float(guarded["damage"]) <= float(open["damage"]) * 0.35, "guard absorbs most damage (%.1f vs %.1f open)" % [guarded["damage"], open["damage"]])
	var t_hit := float(open["first_hit_t"])
	check(t_hit > 0.0, "open Big Swing timing known")
	var tap := t_hit - 0.05
	var par := await shoot(KID, DUMMY, 1.05, press("heavy"), 2.2, at([{"t0": tap, "t1": tap + 0.05, "press": ["guard"]}, {"t0": tap, "t1": tap + 0.35, "hold": ["guard"]}]))
	check(int(par["parried"]) >= 1, "a late tap parries Big Swing (parried %d, blocked %d, hits %d)" % [par["parried"], par["blocked"], par["hits"]])
	check(float((par["a_states"] as Dictionary).get("hitstun", 0.0)) >= 0.4, "the parried Kid staggers (%.2f s)" % float((par["a_states"] as Dictionary).get("hitstun", 0.0)))
	var jab_open := await shoot(KID, DUMMY, 1.0, press("light"), 1.4)
	var jab_t := float(jab_open["first_hit_t"]) - 0.05
	var jab_par := await shoot(KID, DUMMY, 1.0, press("light"), 1.4, at([{"t0": jab_t, "t1": jab_t + 0.05, "press": ["guard"]}, {"t0": jab_t, "t1": jab_t + 0.3, "hold": ["guard"]}]))
	check(int(jab_par["parried"]) >= 1, "the Sleeve Jab is parryable too (parried %d)" % jab_par["parried"])


## The charged heavy shrugs off lights while it winds up (armor vs lights) and still lands.
func test_charged_heavy_armor_shrugs_lights() -> void:
	var r := await shoot(KID, DUMMY, 1.0, hold("heavy", 0.0, 1.1), 3.0, at([{"t0": 0.5, "t1": 1.3, "press": ["light"], "every": 0.35}]))
	var taken := 0
	for ev in r["events"]:
		if str(ev["type"]) == "hit" and int(ev["fighter"]) == 1 and int(ev["target"]) == 0:
			taken += 1
	check(taken >= 1, "Stoke's jabs reach the charging Kid (%d)" % taken)
	check(float((r["a_states"] as Dictionary).get("hitstun", 0.0)) < 0.05, "no hitstun through the charge (%.2f s)" % float((r["a_states"] as Dictionary).get("hitstun", 0.0)))
	check(slot_hits(r, "heavy_charged") >= 1, "Showboat Haymaker still lands (hits %s)" % str(r["slots"]))


## Abilities obey their cooldowns; Latch Lunge drains; Hood Up retaliates against a strike.
func test_abilities_cooldowns_and_counter_stance() -> void:
	var cd := await shoot(KID, DUMMY, 3.0, at([{"t0": 0.0, "t1": 0.05, "press": ["ability1"]}, {"t0": 1.2, "t1": 1.25, "press": ["ability1"]},
		{"t0": 7.4, "t1": 7.45, "press": ["ability1"]}]), 8.6)
	var uses := []
	for ev in cd["events"]:
		if str(ev["type"]) == "ability" and int(ev["fighter"]) == 0:
			uses.append(float(ev.get("tick", 0)) / 120.0)
	check_eq(uses.size(), 2, "Latch Lunge twice in 8 s with a 7 s cooldown (uses at %s)" % str(uses))
	var bite := await shoot(KID, DUMMY, 1.4, press("ability1"), 2.0, [], func(sim: MatchSim) -> void: sim.fighters[0].health = 60.0)
	check(slot_hits(bite, "ability1") >= 1, "Latch Lunge bites (hits %s)" % str(bite["slots"]))
	check(float(bite["a_hp"]) >= 61.9, "the bite drains 2 HP back to the Kid (%.1f)" % bite["a_hp"])
	var hood := await shoot(KID, DUMMY, 0.95, press("ability2"), 2.0, at([{"t0": 0.35, "t1": 0.4, "press": ["light"]}]))
	check(count(hood["events"], "counter") >= 1, "Hood Up retaliates when struck (counters %d)" % count(hood["events"], "counter"))
	check(float(hood["b_hp"]) < float(hood["b_max_hp"]), "the counter jab hurts Stoke (%.1f/%.1f)" % [hood["b_hp"], hood["b_max_hp"]])


## Grab (Latch) beats guard, Rasp pummels drain, the three throws behave.
func test_grab_pummel_and_throws() -> void:
	var g := await shoot(KID, DUMMY, 0.95, grab_presses(0.6, 2), 2.8, [{"t0": 0.0, "t1": 4.0, "hold": ["guard"]}],
		func(sim: MatchSim) -> void: sim.fighters[0].health = 50.0)
	check(count(g["events"], "grab", "fighter", 0) >= 1, "Latch grabs a guarding Stoke")
	check(slot_hits(g, "pummel") >= 2, "two Rasp pummels (hits %s)" % str(g["slots"]))
	check(float(g["a_hp"]) >= 51.9, "Rasp heals the Kid 1 HP per pummel (%.1f)" % g["a_hp"])
	for spec in [["throw_fwd", Vector3(0, 0, 1), true], ["throw_back", Vector3(0, 0, -1), true], ["throw_side", Vector3(1, 0, 0), false]]:
		var t := await shoot(KID, DUMMY, 0.95, grab_presses(0.5, 0, spec[1]), 3.0)
		var kinds := []
		for ev in t["events"]:
			if str(ev["type"]) == "throw" and int(ev["fighter"]) == 0:
				kinds.append(str(ev.get("kind", "")))
		check(kinds.has(spec[0]), "%s performed (throws %s)" % [spec[0], str(kinds)])
		var downed := float((t["b_states"] as Dictionary).get("knockdown", 0.0)) > 0.0
		check(downed == bool(spec[2]), "%s %s the target down" % [spec[0], "knocks" if spec[2] else "does not knock"])
		check(float(t["b_hp"]) < float(t["b_max_hp"]), "%s deals damage" % spec[0])


## Taunt: 1.5 s, no armor, +8 Hype.
func test_taunt_builds_hype() -> void:
	var r := await shoot(KID, DUMMY, 3.0, press("taunt"), 2.0)
	check(count(r["events"], "taunt", "fighter", 0) == 1, "taunt fired")
	check_near(float(r["a_hype"]), 8.0, 0.01, "taunt +8 Hype")
	check_near(float((r["a_states"] as Dictionary).get("taunt", 0.0)), 1.5, 0.05, "taunt lasts 1.5 s")


## JUICE: 0.5 s armored activation with a pulse, 6 s Feeding Frenzy (life-steal hits, faster,
## lights do not stagger), then the burnt-out crash (-30 stamina).
func test_juice_feeding_frenzy() -> void:
	var prep := func(sim: MatchSim) -> void:
		sim.fighters[0].hype = 100.0
		sim.fighters[0].health = 60.0
	var each := func(sim: MatchSim, out: Dictionary) -> void:
		var a := sim.fighters[0]
		if a.time < a.juiced_until:
			out["juiced"] = float(out.get("juiced", 0.0)) + 1.0 / Engine.physics_ticks_per_second
			out["stamina_before_crash"] = a.stamina
		if a.statuses.has("juiced"):
			out["speed_mult"] = a.statuses.speed_mult()
		if a.time < a.crash_until and not out.has("stamina_at_crash"):
			out["stamina_at_crash"] = a.stamina
	var r := await shoot(KID, DUMMY, 1.6, at([{"t0": 0.0, "t1": 0.05, "press": ["juice"]}, {"t0": 1.0, "t1": 3.5, "move": "to_target"},
		{"t0": 1.2, "t1": 3.5, "press": ["light"], "every": 0.4}]), 8.4, [], prep, 6.0, each)
	check(count(r["events"], "juice", "fighter", 0) == 1, "JUICE activated")
	check(count(r["events"], "juice_end", "fighter", 0) == 1, "JUICE ended")
	check(float(r.get("juiced", 0.0)) >= 5.9 and float(r.get("juiced", 0.0)) <= 7.0, "Feeding Frenzy lasts ~6 s (%.2f)" % float(r.get("juiced", 0.0)))
	check(float(r.get("speed_mult", 1.0)) > 1.1, "faster while juiced (%.2f)" % float(r.get("speed_mult", 1.0)))
	var pulse := 0
	for ev in r["events"]:
		if str(ev["type"]) == "hit" and int(ev["fighter"]) == 0 and str(ev.get("move_class", "")) == "juice":
			pulse += 1
	check(pulse >= 1, "the activation pulse hits Stoke at 1.6 m")
	check(float(r["a_hp"]) > 60.0, "hits heal the Kid while juiced (%.1f)" % r["a_hp"])
	var before := float(r.get("stamina_before_crash", 0.0))
	var after := float(r.get("stamina_at_crash", before))
	check(r.has("stamina_at_crash") and before - after >= 25.0, "burnt-out crash costs 30 stamina (%.0f -> %.0f)" % [before, after])


## Granny's exercises that use the Kid's scripted behaviours succeed against every roster
## body (his string/heavy must reach a 0.9 m jelly and a 2 m crab alike); the dodge, grab and
## freestyle lessons succeed with the default fighter.
func test_tutorial_partner_behaviours() -> void:
	var guard_plan := func(f: Fighter, _sim, _t: float, _mem: Dictionary) -> void:
		f.input.set_held(FighterInput.GUARD, true)
	var parry_plan := func(f: Fighter, sim, t: float, mem: Dictionary) -> void:
		var kid: Fighter = sim.fighters[1]
		if kid.state == Fighter.State.ATTACK and kid.move and kid.state_time < kid.move.first_active():
			var eta := (kid.move.first_active() - kid.state_time) / maxf(0.1, float(kid.mods.get("move_speed", 1.0)))
			if eta < 0.06 and not bool(mem.get("pressed", false)):
				mem["pressed"] = true
				mem["hold_until"] = t + 0.3
				f.input.press(FighterInput.GUARD)
		elif kid.state != Fighter.State.ATTACK:
			mem["pressed"] = false
		if t < float(mem.get("hold_until", -1.0)):
			f.input.set_held(FighterInput.GUARD, true)
	for player in ROSTER:
		if player in KIDSCRIPT_UNREACHABLE:
			# KidScript walks to a fixed 1.05 m root-to-root before swinging; Dozer's snout keeps
			# any partner at >= 1.2 m, so the lesson cannot start (reported to the tutorial owner).
			# The Kid's kit itself still reaches a guarding Dozer from where the bodies meet:
			var blk := await shoot(KID, player, 1.3, string_presses(3), 2.2, [{"t0": 0.0, "t1": 3.0, "hold": ["guard"]}])
			check(int(blk["blocked"]) + int(blk["hits"]) >= 2, "the Kid's string meets a guarding %s at 1.3 m (blocked %d, hits %d)" % [player, blk["blocked"], blk["hits"]])
			continue
		var gr := await tutorial_run(3, player, KID, guard_plan, 45.0)
		check(bool(gr["ok"]), "Hands up with %s: the Kid's string is blocked (%s, %s)" % [player, gr["state"], gr["progress"]])
		var pr := await tutorial_run(7, player, KID, parry_plan, 60.0)
		check(bool(pr["ok"]), "The read with %s: his light and heavy are parryable (%s, %s)" % [player, pr["state"], pr["progress"]])
	var dodge_plan := func(f: Fighter, sim, t: float, mem: Dictionary) -> void:
		var kid: Fighter = sim.fighters[1]
		var mode := sim.mode as TutorialMode
		if mode.stage == 0:
			if kid.state == Fighter.State.ATTACK and kid.move_slot in ["heavy", "heavy_charged"] and not mem.has("dodged_at"):
				mem["dodged_at"] = t
				var to := toward(f, kid.pos())
				f.input.move = Vector3(-to.z, 0, to.x)
				f.input.press(FighterInput.DODGE)
			elif mem.has("dodged_at") and t - float(mem["dodged_at"]) > 1.5:
				mem.erase("dodged_at")
		else:
			var d := f.pos().distance_to(kid.pos())
			if d > 2.6 and f.state == Fighter.State.NEUTRAL:
				f.input.move = toward(f, kid.pos())
			elif f.state == Fighter.State.NEUTRAL and t - float(mem.get("dash", -9.0)) > 1.0:
				mem["dash"] = t
				f.input.move = toward(f, kid.pos())
				f.input.press(FighterInput.DODGE)
			elif f.state == Fighter.State.DODGE:
				f.input.move = toward(f, kid.pos())
				f.input.press(FighterInput.LIGHT)
	# (the roster stubs have no Dash Attack yet: dev_biped's complete kit plays the student here)
	var dr := await tutorial_run(4, "dev_biped", KID, dodge_plan, 60.0)
	check(bool(dr["ok"]), "Not there: the Kid's telegraphed heavy can be dodged (%s, %s)" % [dr["state"], dr["progress"]])
	var grab_plan := func(f: Fighter, sim, t: float, mem: Dictionary) -> void:
		var kid: Fighter = sim.fighters[1]
		if f.state == Fighter.State.GRABBING:
			f.input.move = toward(f, kid.pos())
			if t - float(mem.get("throw", -9.0)) > 0.3:
				mem["throw"] = t
				f.input.press(FighterInput.GRAB)
		elif f.pos().distance_to(kid.pos()) > 0.95 and f.state == Fighter.State.NEUTRAL:
			f.input.move = toward(f, kid.pos())
		elif t - float(mem.get("grab", -9.0)) > 0.8:
			mem["grab"] = t
			f.input.press(FighterInput.GRAB)
	var gt := await tutorial_run(6, DUMMY, KID, grab_plan, 40.0)
	check(bool(gt["ok"]), "Hands on: the guarding Kid can be grabbed and thrown (%s, %s)" % [gt["state"], gt["progress"]])
	var brain := BotBrain.new("champion", 99)
	var free_plan := func(f: Fighter, sim, _t: float, _mem: Dictionary) -> void:
		brain.poll(f, sim, 1.0 / Engine.physics_ticks_per_second)
	var fr := await tutorial_run(9, DUMMY, KID, free_plan, 130.0)
	check(bool(fr["ok"]), "Freestyle: a good player beats the Punching Bag Kid (%s, %s)" % [fr["state"], fr["progress"]])


## Balance: at Punching Bag / Journeyman the Kid loses most bouts to a roster bot of the same
## tier but lands hits. The default run is a short smoke; --balance runs >= 20 bouts per roster
## fighter and tier and prints the table recorded in docs/kits/npc_kid_lamprey.md.
func test_balance_vs_roster() -> void:
	if not balance_requested():
		var smoke := await bouts(KID, DUMMY, "rookie", "rookie", 4, 45.0)
		print(bout_line("smoke kid vs f_stoke rookie", smoke))
		check(int(smoke["a_hits"]) >= 4, "the Kid lands hits (%d in 4 bouts)" % smoke["a_hits"])
		check(int(smoke["b_hits"]) >= 4, "Stoke lands hits (%d in 4 bouts)" % smoke["b_hits"])
		return
	var total := {"a": 0, "n": 0}
	for tier in ["rookie", "regular"]:
		for target in ROSTER:
			var r := await bouts(KID, target, tier, tier, 20, 60.0)
			print(bout_line("kid vs %s %s" % [target, tier], r))
			total["a"] = int(total["a"]) + int(r["a_wins"])
			total["n"] = int(total["n"]) + int(r["bouts"])
			check(float(r["a_hits"]) / maxf(1.0, float(r["bouts"])) >= 2.0, "the Kid lands hits vs %s at %s" % [target, tier])
			check(float(r["a_wins"]) / maxf(1.0, float(r["bouts"])) <= 0.5, "the Kid loses most bouts vs %s at %s (%d/%d)" % [target, tier, r["a_wins"], r["bouts"]])
	print("KID OVERALL win rate %.0f%% over %d bouts" % [100.0 * float(total["a"]) / maxf(1.0, float(total["n"])), total["n"]])
	var mirror := await bouts(KID, KID, "regular", "regular", 20, 60.0)
	print(bout_line("kid mirror regular", mirror))


# ---------------------------------------------------------------------------------------------
# Tuning aids (opt-in, no assertions)

## `--kit-tut <exercise index> <player id>`: traces the Kid's moves, distances and contacts in a
## real tutorial run with the player holding guard.
func test_zz_debug_tutorial() -> void:
	var args := OS.get_cmdline_user_args()
	var di := args.find("--kit-tut")
	if di < 0:
		return
	var index := int(args[di + 1])
	var player := args[di + 2]
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var mode := TutorialMode.new()
	mode.start_index = index
	sim.setup({"arena": Tutorial.practice_cage(), "seed": 4, "mode": mode,
		"rules": {"id": "tutorial", "name": "Tutorial", "mode": "tutorial", "round_time": 0.0, "intro_time": 0.0},
		"fighters": [{"creature": Content.creature(player), "team": 0, "source": null, "kind": "player"},
			{"creature": Content.creature(KID), "team": 1, "source": null, "kind": "scripted"}]})
	sim.set_input_source(0, Driver.new(func(f: Fighter, _s, _t: float, _m: Dictionary) -> void: f.input.set_held(FighterInput.GUARD, true)))
	var dt := 1.0 / Engine.physics_ticks_per_second
	var cursor := 0
	var kid := sim.fighters[1]
	var p := sim.fighters[0]
	while sim.time < 14.0 and mode.state == "active":
		sim.step(dt)
		await get_tree().physics_frame
		for ev in sim.events_since(cursor):
			cursor = int(ev["seq"])
			var t := str(ev["type"])
			if t == "move_start" and int(ev["fighter"]) == 1:
				print("%.2f kid %s dist %.2f player %s guard_blend %.2f (heights kid %.2f player %.2f strike scale %.2f)" % [sim.time, ev["slot"], kid.pos().distance_to(p.pos()), p.state_name(), p.motor.guard_blend,
					kid.creature.body.height, p.creature.body.height, kid.motor.strike_height_scale])
			elif t == "hit" or t == "glance":
				print("%.2f %s f%d->f%d blocked=%s slot=%s" % [sim.time, t, ev.get("fighter", -1), ev.get("target", -1), ev.get("blocked", false), ev.get("slot", "")])
		if kid.move != null and kid.move.window_index(kid.state_time) >= 0:
			var line := "   %.3f %s" % [sim.time, kid.move_slot]
			for wn in kid.move.windows[kid.move.window_index(kid.state_time)]["weapons"]:
				var wd: BodyDef.Weapon = kid.creature.body.weapons[wn]
				var wp := kid.rig.bodies[wd.seg].global_transform * wd.local
				line += " %s(%.2f,%.2f,%.2f)" % [wn, wp.x, wp.y, wp.z]
			line += " | player root (%.2f,%.2f,%.2f)" % [p.pos().x, p.pos().y, p.pos().z]
			for c in sim.combat.debug_contacts:
				line += " contact n=(%.2f,%.2f,%.2f) vn=%.2f" % [c["normal"].x, c["normal"].y, c["normal"].z, c["vn"]]
			print(line)
	print("state ", mode.state, " ", mode.progress_text())


func test_zz_debug_contacts() -> void:
	var args := OS.get_cmdline_user_args()
	var di := args.find("--kit-debug")
	if di < 0:
		return
	var slot := args[di + 1]
	var gap := float(args[di + 2])
	var target: String = args[di + 3] if args.size() > di + 3 and not args[di + 3].begins_with("--") else DUMMY
	var tsteps: Array = [{"t0": 0.0, "t1": 9.0, "hold": ["guard"]}] if args.has("--kit-guard") else []
	var steps: Array = []
	var secs := 2.0
	for m in _moves():
		if str(m[0]) == slot:
			steps = m[1]
			secs = m[2]
	var each := func(sim: MatchSim, _out: Dictionary) -> void:
		var a := sim.fighters[0]
		if a.move == null:
			return
		var wi := a.move.window_index(a.state_time)
		var line := "t=%.3f st=%.3f %s w=%d" % [sim.time, a.state_time, a.move_slot, wi]
		for w in a.move.windows:
			for wn in w["weapons"]:
				var wd: BodyDef.Weapon = a.creature.body.weapons[wn]
				var wp := a.rig.bodies[wd.seg].global_transform * wd.local
				var v := a.rig.point_velocity(wd.seg, wp)
				line += " %s(%.2f,%.2f,%.2f v=%.1f,%.1f,%.1f)" % [wn, wp.x, wp.y, wp.z, v.x, v.y, v.z]
		for c in sim.combat.debug_contacts:
			line += " CONTACT n=(%.2f,%.2f,%.2f) vn=%.2f" % [c["normal"].x, c["normal"].y, c["normal"].z, c["vn"]]
		print(line)
	var r := await shoot(KID, target, gap, steps, secs, tsteps, Callable(), 6.0, each)
	print("hits ", r["slots"], " blocked ", r["blocked"], " glances ", r["glances"])


## Range tables: `-- --test test_kit_npc_kid_lamprey --kit-report [--kit-target f_x]
## [--kit-move slot]`. Each cell is gap:hits-of-that-slot/its damage (gN = glances).
func test_zz_report_ranges() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--kit-report"):
		return
	var targets: Array = ROSTER
	var ti := args.find("--kit-target")
	if ti >= 0 and ti + 1 < args.size():
		targets = [args[ti + 1]]
	var only := ""
	var mi := args.find("--kit-move")
	if mi >= 0 and mi + 1 < args.size():
		only = args[mi + 1]
	for target in targets:
		for m in _moves():
			if only != "" and str(m[0]) != only:
				continue
			var line := "%-10s %-13s" % [target, m[0]]
			for gap in [0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.6, 1.8, 2.0, 2.2, 2.6]:
				var r := await shoot(KID, target, gap, m[1], m[2])
				line += " %.1f:%d/%.0f%s" % [gap, slot_hits(r, str(m[0])), float((r["slot_dmg"] as Dictionary).get(str(m[0]), 0.0)),
					("g%d" % int(r["glances"])) if int(r["glances"]) > 0 else ""]
				if is_equal_approx(gap, 1.0):
					line += "[reach %.2f up %.2f push %.2f lift %.2f]" % [r["reach"], r["min_up"], r["push"], r["lift"]]
			print(line)
