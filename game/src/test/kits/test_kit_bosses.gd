extends "res://src/test/kits/npc_kit_case.gd"
## Boss base kits (ENEMIES_BOSSES.md §2, docs/kits/bosses.md): Bilge (boss_bilge), Conduit
## (boss_conduit), Commissioner Snappington (boss_snappington). These are the bodies and the
## regular movesets BossMode drives between its scripted patterns (content/core/boss_fights).
## Run: godot --headless --path game --fixed-fps 120 -- --test test_kit_bosses
##      (add --balance for the >= 20-bout tables, --kit-report [--kit-boss id] for ranges)

const BOSSES := ["boss_bilge", "boss_conduit", "boss_snappington"]
const DUMMY := "f_stoke"
## Outside the campaign a boss in a bot slot has 2x the highest fighter HP and no phases
## (ENEMIES_BOSSES.md "Custom rules"); balance bouts use that unless --kit-full-hp.
const BOT_SLOT_HP := 2.0
## ENEMIES_BOSSES.md stat lines: [health, poise]
const DESIGN_STATS := {"boss_bilge": [420.0, 200.0], "boss_conduit": [520.0, 160.0], "boss_snappington": [650.0, 240.0]}
const ROSTER := ["f_stoke", "f_dredge", "f_gusto", "f_dozer", "f_slurry", "f_jitters"]

## boss -> slot -> [near gaps that must land it, far gap that must not (-1 = no limit),
## min dmg, max dmg] against a standing Stoke. "Lands" counts the slot's own hits, its effect
## hits for effect moves, or a grab event for "grab"; damage is the best single landing.
const RANGES := {
	"boss_bilge": {
		"l1": [[2.4, 3.2], 3.8, 12.0, 30.0],        # Chomp: the head lunges out; up close he is inside it
		"l2": [[1.6, 2.0], 3.8, 3.0, 16.0],         # Paw Swat (Chomp > Swat string)
		"heavy": [[1.6, 2.0], 2.8, 5.0, 14.0],      # Shake-Off: radial, short
		"grab": [[2.4, 4.2], 5.2, 0.0, 0.0],        # Lunge-Chomp grabs from range
		"ability1": [[2.4, 4.2], -1.0, 3.0, 12.0],  # Bilge Spit lobs
		"ability2": [[1.6, 4.2], -1.0, 8.0, 20.0],  # Belly Flop lands on the target (4 m leap)
	},
	"boss_conduit": {
		"l1": [[1.6, 2.0], 2.8, 8.0, 22.0],         # Fang Strike arcs down through every height
		"l2": [[1.6, 2.0], 3.6, 5.0, 14.0],         # Whip Tail (180-degree sweep, 2.8 m)
		"heavy": [[1.6, 4.2], 5.2, 8.0, 20.0],      # Coil Slam
		"grab": [[1.6, 2.0], 2.8, 0.0, 0.0],        # Jaw Clamp
		"ability1": [[1.6, 6.0], -1.0, 3.0, 12.0],  # Arc Spit (homing)
	},
	"boss_snappington": {
		"l1": [[1.6, 2.4], 3.0, 4.0, 14.0],         # Claw Jab
		"l2": [[1.6, 2.8], 5.2, 2.0, 10.0],         # Objection! (gavel shockwave, 4 m cone)
		"heavy": [[1.6, 2.0], 3.4, 6.0, 24.0],      # Gavel Claw (its shockwave runs on to 2.8 m)
		"grab": [[2.0, 2.4], 3.4, 0.0, 0.0],        # Snap
		"ability1": [[1.6, 2.4], 3.4, 6.0, 20.0],   # Shell Spin
	},
}


## boss -> [[label, inputs, seconds]] for every damaging move (hits counted from all slots).
func _moves(boss: String) -> Array:
	var c := Content.creature(boss)
	var chain := (c.moves["l1"] as MoveDef).cancel_t0 + 0.03 if c and c.moves.has("l1") else 0.7
	return [
		["l1", press("light"), 2.2],
		["l2", at([{"t0": 0.0, "t1": 0.05, "press": ["light"]}, {"t0": chain, "t1": chain + 0.05, "press": ["light"]}]), 3.2],
		["heavy", press("heavy"), 2.8],
		["grab", press("grab"), 3.0],
		["ability1", press("ability1"), 3.0],
		["ability2", press("ability2"), 4.2],
		["juice", press("juice"), 4.5],
	]


static func _juiced(sim: MatchSim) -> void:
	sim.fighters[0].hype = 100.0


## Landings of `label` in a shot: its own hits, effect hits for effect moves, grabs for "grab".
## Returns [count, best single damage].
static func _landed(r: Dictionary, label: String, c: CreatureDef) -> Array:
	if label == "grab":
		return [count(r["events"], "grab", "fighter", 0), 0.0]
	var m: MoveDef = c.moves.get(label, c.abilities.get(label))
	var by_effect := false
	if m != null:
		for e in m.effects:
			if typeof(e) == TYPE_DICTIONARY and (float(e.get("damage", 0.0)) > 0.0 or str(e.get("type", "")) in ["leap", "projectile"]):
				by_effect = true
	var n := 0
	var best := 0.0
	for ev in r["events"]:
		if str(ev["type"]) != "hit" or int(ev["fighter"]) != 0 or int(ev["target"]) != 1 or bool(ev["blocked"]) or bool(ev["parried"]):
			continue
		var sl := str(ev.get("slot", ""))
		if sl == label or (by_effect and sl == "effect"):
			n += 1
			best = maxf(best, float(ev["damage"]))
	return [n, best]


## Fighter 1 was knocked down at some point of the shot.
static func _was_down(r: Dictionary) -> bool:
	var bs: Dictionary = r["b_states"]
	return float(bs.get("knockdown", 0.0)) > 0.0 or float(bs.get("down", 0.0)) > 0.0


static func _first_threat(m: MoveDef) -> float:
	var t := 99.0
	for w in m.windows:
		t = minf(t, float(w["t0"]))
	for e in m.effects:
		if typeof(e) == TYPE_DICTIONARY and (float(e.get("damage", 0.0)) > 0.0 or str(e.get("type", "")) in ["leap", "projectile"]):
			t = minf(t, float(e.get("t", 0.0)))
	return t


# ---------------------------------------------------------------------------------------------
# Kit shape and the BossMode / campaign contract

func test_boss_kits_complete_and_valid() -> void:
	for boss in BOSSES:
		var c := Content.creature(boss)
		check(c != null, "%s loads" % boss)
		if c == null:
			continue
		check(c.is_valid(), "%s parses with no errors: %s" % [boss, ", ".join(c.errors)])
		check(c.npc_only, "%s is npc_only" % boss)
		var raw := Content.creature_entry(boss)
		check(not (raw["stats"] as Dictionary).has("dodge_speed"), "%s: no unknown dodge_speed stat" % boss)
		check_near(c.stat("health"), float(DESIGN_STATS[boss][0]), 0.5, "%s health per design" % boss)
		check_near(c.stat("poise"), float(DESIGN_STATS[boss][1]), 0.5, "%s poise per design" % boss)
		check(c.body.seg_index.has("head"), "%s has a 'head' segment (BossMode grab_throw)" % boss)
		for k in ["throw_fwd", "throw_side", "throw_back"]:
			check(c.throws.has(k), "%s throw %s (BossMode throws use the creature's)" % [boss, k])
		for slot in ["l1", "l2", "heavy", "grab", "pummel", "taunt"]:
			check(c.moves.has(slot), "%s move %s" % [boss, slot])
			check(not bool((raw["moves"] as Dictionary).get(slot, {}).get("_stub", false)), "%s %s is not a stub" % [boss, slot])
		for slot in ["ability1", "ability2", "juice"]:
			check(c.abilities.has(slot), "%s ability %s" % [boss, slot])
		# big readable telegraphs: nothing damaging comes out in under half a second
		for slot in c.moves:
			var m: MoveDef = c.moves[slot]
			if str(slot) in ["pummel", "taunt"]:
				continue
			check(_first_threat(m) >= 0.5, "%s %s telegraphs >= 0.5 s (%.2f)" % [boss, slot, _first_threat(m)])
		for slot in c.abilities:
			var ab: MoveDef = c.abilities[slot]
			check(_first_threat(ab) >= 0.5, "%s %s telegraphs >= 0.5 s (%.2f)" % [boss, slot, _first_threat(ab)])
		# armor through every basic attack's startup
		for slot in ["l1", "l2", "heavy", "grab"]:
			var mv: MoveDef = c.moves[slot]
			var covered := 0.0
			for a in mv.armor:
				if float(a[0]) <= 0.01:
					covered = maxf(covered, float(a[1]))
			check(covered >= minf(0.5, _first_threat(mv)) - 0.01, "%s %s armored through its startup (%.2f)" % [boss, slot, covered])
		var ai: Dictionary = c.ai
		check(float(ai.get("block", 0.0)) <= -1.0 and float(ai.get("dodge", 0.0)) <= -1.0, "%s never blocks or dodges (bot)" % boss)
		check(bool(ai.get("bulky", false)), "%s is bulky for bots fighting it" % boss)
		check((ai.get("rest", []) as Array).size() == 2, "%s rests between attacks (punish window)" % boss)


## The campaign's boss fights run on these creatures: each fight's creature parses (CampaignCatalog
## would otherwise fall back to a stand-in), its grab_throw segment exists, and BossMode's pieces
## work on the body: a head-segment grab and the creature's throws, and per-slot element
## overrides (the element cycle) on the boss's melee.
func test_boss_mode_contract() -> void:
	var cat := CampaignCatalog.new(Content)
	var fights := 0
	for fid in cat.boss_fights:
		var bf: Dictionary = cat.boss_fights[fid]
		var cid := str(bf.get("creature", ""))
		if not cid in BOSSES:
			continue
		fights += 1
		check(cat.resolver.exists(cid) and cat.resolver.problems(cid).is_empty(), "%s uses the real %s (%s)" % [fid, cid, ", ".join(cat.resolver.problems(cid))])
		var c := Content.creature(cid)
		for seg in _grab_segments(bf):
			check(c.body.seg_index.has(seg), "%s grab_throw segment '%s' exists on %s" % [fid, seg, cid])
	check(fights >= 3, "all three boss fights reference the boss creatures (%d)" % fights)
	for boss in BOSSES:
		var sim := duel(boss, DUMMY, 1.6, null, null, 6.0)
		await step_sim(sim, 0.6)
		var b := sim.fighters[0]
		var v := sim.fighters[1]
		var hp0 := v.health
		b.begin_grab(v, int(b.creature.body.seg_index["head"]), 0)
		check(b.holding == v, "%s holds a victim by the head segment" % boss)
		await step_sim(sim, 0.4)
		b._do_throw(b.forward())
		await step_sim(sim, 0.3)
		check(v.health < hp0, "%s's throw hurts (%.1f)" % [boss, hp0 - v.health])
		check(v.is_down(), "%s's throw knocks down" % boss)
		sim.get_parent().queue_free()
	# element cycle: BossMode writes mods["element_<slot>"]; the boss's melee hit carries it
	var cyc := func(sim: MatchSim) -> void: sim.fighters[0].mods["element_l1"] = "scorch"
	var r := await shoot("boss_snappington", DUMMY, 2.0, press("light"), 2.2, [], cyc, 6.0)
	var el := ""
	for ev in r["events"]:
		if str(ev["type"]) == "hit" and int(ev["fighter"]) == 0 and str(ev.get("slot", "")) == "l1":
			el = str(ev.get("element", ""))
	check_eq(el, "scorch", "a cycled element rides Snappington's Claw Jab")


static func _grab_segments(o) -> Array:
	var out: Array = []
	if typeof(o) == TYPE_DICTIONARY:
		if str(o.get("type", "")) == "grab_throw":
			out.append(str(o.get("segment", "head")))
		for k in o:
			out.append_array(_grab_segments(o[k]))
	elif typeof(o) == TYPE_ARRAY:
		for x in o:
			out.append_array(_grab_segments(x))
	return out


# ---------------------------------------------------------------------------------------------
# Ranges and properties

## Every basic move lands at its intended range against a standing Stoke, misses beyond it and
## deals damage in its band; the boss stays upright and inside the cage.
func test_moves_connect_in_range_and_miss_outside() -> void:
	for boss in BOSSES:
		var c := Content.creature(boss)
		var table: Dictionary = RANGES[boss]
		for m in _moves(boss):
			var label := str(m[0])
			if not table.has(label):
				continue
			var spec: Array = table[label]
			var best := 0.0
			for gap in spec[0]:
				var r := await shoot(boss, DUMMY, float(gap), m[1], m[2], [], Callable(), 7.0)
				var got := _landed(r, label, c)
				check(int(got[0]) >= 1, "%s %s lands at %.1f m (slots %s, grabs %d)" % [boss, label, gap, str(r["slots"]), count(r["events"], "grab", "fighter", 0)])
				best = maxf(best, float(got[1]))
				check(float(r["min_up"]) > 0.6, "%s stays upright through %s (%.2f)" % [boss, label, r["min_up"]])
				check(bool(r["a_inside"]), "%s stays inside the cage through %s" % [boss, label])
			if float(spec[1]) > 0.0:
				var far := await shoot(boss, DUMMY, float(spec[1]), m[1], m[2], [], Callable(), 7.0)
				check(int(_landed(far, label, c)[0]) == 0, "%s %s misses at %.1f m" % [boss, label, spec[1]])
			if float(spec[3]) > 0.0:
				check(best >= float(spec[2]) and best <= float(spec[3]), "%s %s damage %.1f within [%.0f, %.0f]" % [boss, label, best, spec[2], spec[3]])


## Armor: light hits landing in a boss's heavy startup neither stagger nor stop it (its armor
## window ignores lights), and the heavy still lands. The pokes are delivered directly (a light
## class hit from the target), so the check does not depend on any roster fighter's reach.
func test_armor_shrugs_lights_in_startup() -> void:
	for boss in BOSSES:
		var poke := func(sim: MatchSim, out: Dictionary) -> void:
			var a := sim.fighters[0]
			var b := sim.fighters[1]
			if a.move_slot == "heavy" and a.state_time >= 0.2 and a.state_time <= 0.45 and int(out.get("pokes", 0)) < 3 \
					and sim.time - float(out.get("poked_at", -9.0)) > 0.1:
				out["pokes"] = int(out.get("pokes", 0)) + 1
				out["poked_at"] = sim.time
				sim.effects.effect_hit(b, a, {"damage": 4.0, "knockback": 1.5, "stun": 0.3, "poise": 6.0, "class": "light"}, b.pos())
				out["still_heavy"] = a.move_slot == "heavy" and a.state == Fighter.State.ATTACK
		var r := await shoot(boss, DUMMY, 1.7, press("heavy"), 2.6, [], Callable(), 7.0, poke)
		var took := 0
		for ev in r["events"]:
			if str(ev["type"]) == "hit" and int(ev["fighter"]) == 1 and int(ev["target"]) == 0:
				took += 1
		check(took >= 2, "%s takes light pokes during its heavy's startup (%d)" % [boss, took])
		check(bool(r.get("still_heavy", false)), "%s keeps winding up through them" % boss)
		check(int(_landed(r, "heavy", Content.creature(boss))[0]) >= 1, "%s's heavy still lands (armor)" % boss)

## Bilge: Shake-Off shoves away; Lunge-Chomp grabs and throws; the Belly Flop's ring knocks a
## Soaked target down; Spit leaves sludge puddles.
func test_bilge_signature_moves() -> void:
	var shake := await shoot("boss_bilge", DUMMY, 1.8, press("heavy"), 2.4, [], Callable(), 7.0)
	check(int(_landed(shake, "heavy", Content.creature("boss_bilge"))[0]) >= 1, "Shake-Off hits at 1.8 m")
	check(float(shake["push"]) >= 0.6, "Shake-Off shoves the target away (%.2f m)" % shake["push"])
	var chomp := await shoot("boss_bilge", DUMMY, 3.2, grab_presses(1.2, 0, Vector3.ZERO) + at([{"t0": 1.5, "t1": 1.55, "press": ["heavy"]}]), 3.5, [], Callable(), 7.0)
	check(count(chomp["events"], "grab", "fighter", 0) >= 1, "Lunge-Chomp grabs from 3.2 m")
	check(count(chomp["events"], "throw", "fighter", 0) >= 1, "and throws")
	check(_was_down(chomp), "the throw knocks down")
	var soak := func(sim: MatchSim) -> void: sim.fighters[1].statuses.add_buildup("brine", 300.0, null)
	var flop := await shoot("boss_bilge", DUMMY, 7.0, press("ability2"), 4.0, [], soak, 8.0)
	var wave := 0
	for ev in flop["events"]:
		if str(ev["type"]) == "hit" and int(ev["fighter"]) == 0 and str(ev.get("move_class", "")) == "wave":
			wave += 1
	check(wave >= 1, "the Belly Flop's ring wave reaches a target 3 m past the landing")
	check(_was_down(flop), "the wave trips a Soaked target")
	var puddles := func(sim: MatchSim, out: Dictionary) -> void:
		for e in sim.effects.entities:
			if str(e["kind"]) == "zone" and str(e.get("zone_kind", "")) == "sludge_puddle":
				out["puddle"] = true
	var spit := await shoot("boss_bilge", DUMMY, 3.6, press("ability1"), 3.0, [], Callable(), 7.0, puddles)
	check(bool(spit.get("puddle", false)), "Bilge Spit leaves sludge puddles")


## Conduit: Jaw Clamp discharges when it throws; Arc Spit homes on a side-stepping target; Scrap
## Shuffle blinks away and leaves rubble; Overvolt bursts around him.
func test_conduit_signature_moves() -> void:
	var clamp := await shoot("boss_conduit", DUMMY, 1.8, grab_presses(1.3, 0, Vector3.ZERO) + at([{"t0": 1.6, "t1": 1.65, "press": ["heavy"]}]), 3.2, [], Callable(), 7.0)
	check(count(clamp["events"], "grab", "fighter", 0) >= 1, "Jaw Clamp grabs")
	var discharge := 0
	for ev in clamp["events"]:
		if str(ev["type"]) == "hit" and int(ev["fighter"]) == 0 and str(ev.get("slot", "")) == "effect" and str(ev.get("element", "")) == "static":
			discharge += 1
	check(count(clamp["events"], "throw", "fighter", 0) >= 1 and discharge >= 1, "the throw discharges (static burst hits: %d)" % discharge)
	var strafe := [{"t0": 0.0, "t1": 3.0, "move": Vector3(1, 0, 0)}]
	var spit := await shoot("boss_conduit", DUMMY, 4.0, press("ability1"), 3.0, at(strafe), Callable(), 7.0)
	check(int(_landed(spit, "ability1", Content.creature("boss_conduit"))[0]) >= 1, "Arc Spit homes onto a target walking sideways")
	var track := func(sim: MatchSim, out: Dictionary) -> void:
		if not out.has("p0"):
			out["p0"] = sim.fighters[0].pos()
		out["p1"] = sim.fighters[0].pos()
		for e in sim.effects.entities:
			if str(e["kind"]) == "zone" and str(e.get("zone_kind", "")) == "grit_rubble":
				out["rubble"] = true
	var blink := await shoot("boss_conduit", DUMMY, 3.0, press("ability2"), 2.0, [], Callable(), 7.0, track)
	var moved := Vector3(blink["p1"].x - blink["p0"].x, 0, blink["p1"].z - blink["p0"].z).length()
	check(moved >= 2.0, "Scrap Shuffle relocates him (%.2f m)" % moved)
	check(bool(blink.get("rubble", false)), "and leaves grit rubble where he surfaces")
	var over := await shoot("boss_conduit", DUMMY, 3.0, press("juice"), 3.0, [], Callable(_juiced), 7.0)
	check(float(over["damage"]) >= 10.0, "Overvolt bursts over 3 m (%.1f)" % over["damage"])


## Snappington: Withdraw blocks from every side and counters; Shell Spin spins upright under
## armor; Title Slam knocks down; while juiced, her ability1 becomes Juice Spray.
func test_snappington_signature_moves() -> void:
	var jab := [{"t0": 0.6, "t1": 0.65, "press": ["light"]}, {"t0": 1.4, "t1": 1.45, "press": ["light"]}]
	var wd := await shoot("boss_snappington", DUMMY, 1.3, press("ability2"), 2.6, at(jab), Callable(), 7.0)
	var blocked := 0
	for ev in wd["events"]:
		if str(ev["type"]) == "hit" and int(ev["fighter"]) == 1 and int(ev["target"]) == 0 and bool(ev["blocked"]):
			blocked += 1
	var countered := count(wd["events"], "counter", "fighter", 0) + int(wd["hits"])
	check(blocked >= 1 or countered >= 1, "Withdraw turns jabs away (blocked %d) or counters (%d)" % [blocked, countered])
	var spin := await shoot("boss_snappington", DUMMY, 2.0, press("ability1"), 2.6, at([{"t0": 0.5, "t1": 0.9, "press": ["light"], "every": 0.15}]), Callable(), 7.0)
	check(float(spin["max_spin"]) >= 5.0, "Shell Spin really spins (%.1f rad/s)" % spin["max_spin"])
	check(float(spin["min_up"]) > 0.6, "and stays upright (%.2f)" % spin["min_up"])
	check(int(_landed(spin, "ability1", Content.creature("boss_snappington"))[0]) >= 1, "the spin lands through jabs (armor)")
	var slam := await shoot("boss_snappington", DUMMY, 3.0, press("juice"), 4.0, [], Callable(_juiced), 7.0)
	check(_was_down(slam), "Title Slam knocks down")
	var spray := await shoot("boss_snappington", DUMMY, 3.0, at([{"t0": 0.0, "t1": 0.05, "press": ["juice"]}, {"t0": 3.6, "t1": 3.65, "press": ["ability1"]}]), 6.0, [], Callable(_juiced), 7.0)
	var spray_used := false
	for ev in spray["events"]:
		if str(ev["type"]) == "move_start" and int(ev["fighter"]) == 0 and str(ev.get("slot", "")).begins_with("ability1@"):
			spray_used = true
	check(spray_used, "juiced, Snappington's ability1 is Juice Spray")


# ---------------------------------------------------------------------------------------------
# Balance

## Smoke: a boss (regular bot, bot-slot HP) and a regular roster bot both land hits and the
## bout ends. With --balance: >= 20 bouts per roster fighter at regular and pro (boss regular).
func test_balance_vs_roster() -> void:
	if not balance_requested():
		for boss in BOSSES:
			var r := await bouts(boss, DUMMY, "regular", "regular", 2, 60.0, 4.0, 2, 300, 6.0, BOT_SLOT_HP)
			print(bout_line("%s vs %s (smoke)" % [boss, DUMMY], r))
			check(int(r["a_hits"]) > 0 and int(r["b_hits"]) > 0, "%s and Stoke both land hits" % boss)
		return
	var args := OS.get_cmdline_user_args()
	var n := 20
	if args.find("--balance-bouts") >= 0:
		n = int(args[args.find("--balance-bouts") + 1])
	var bosses: Array = BOSSES
	if args.find("--kit-boss") >= 0:
		bosses = [args[args.find("--kit-boss") + 1]]
	for boss in bosses:
		for tier in ["regular", "pro"]:
			var boss_wins := 0
			var total := 0
			for target in ROSTER:
				var r := await bouts(boss, target, "regular", tier, n, 90.0, 4.0, 4, 500, 6.0, BOT_SLOT_HP)
				print(bout_line("%s(regular) vs %s %s" % [boss, target, tier], r))
				boss_wins += int(r["a_wins"])
				total += int(r["bouts"])
			print("%s vs the roster at %s: boss wins %d / %d (%.0f%%)" % [boss, tier, boss_wins, total, 100.0 * boss_wins / maxf(1.0, total)])
			if tier == "regular":
				check(boss_wins * 2 > total, "%s beats regular-tier roster bots most of the time (%d/%d)" % [boss, boss_wins, total])
			else:
				check(boss_wins < total, "%s is not unbeatable for pro-tier roster bots (%d/%d)" % [boss, boss_wins, total])


# ---------------------------------------------------------------------------------------------
# Tuning aids (opt-in)

## `--kit-balance-quick <boss> <tier> <n>`: a few bouts vs every roster fighter (tuning aid).
func test_zz_quick_balance() -> void:
	var args := OS.get_cmdline_user_args()
	var qi := args.find("--kit-balance-quick")
	if qi < 0:
		return
	var boss := args[qi + 1]
	var tier := args[qi + 2]
	var n := int(args[qi + 3])
	var boss_tier := tier
	var bt := args.find("--kit-boss-tier")
	if bt >= 0:
		boss_tier = args[bt + 1]
	var hp_scale := 0.0 if args.has("--kit-full-hp") else BOT_SLOT_HP
	for target in ["f_stoke", "f_dredge", "f_gusto", "f_dozer", "f_slurry", "f_jitters"]:
		var r := await bouts(boss, target, boss_tier, tier, n, 90.0, 4.0, 4, 100, 6.0, hp_scale)
		print(bout_line("%s(%s%s) vs %s %s" % [boss, boss_tier, "" if hp_scale > 0.0 else " full HP", target, tier], r))
		if args.has("--kit-slots"):
			for side in ["a", "b"]:
				var per: Dictionary = r.get(side + "_slots", {})
				var parts: Array = []
				for k in per:
					parts.append("%s %.0f" % [k, float(per[k]) / maxf(1.0, float(r["bouts"]))])
				print("    %s dmg/bout by slot: %s" % [side, ", ".join(parts)])


## `--kit-heights`: body heights (strike re-aim uses target / own height).
func test_zz_heights() -> void:
	if not OS.get_cmdline_user_args().has("--kit-heights"):
		return
	for id in BOSSES + ROSTER + ["npc_kid_lamprey", "npc_scrapling", "npc_blister"]:
		var c := Content.creature(id)
		print("%-18s height %.2f" % [id, c.body.height])


## `--kit-campaign-warnings`: campaign references still waiting for content (debug aid).
func test_zz_campaign_warnings() -> void:
	if not OS.get_cmdline_user_args().has("--kit-campaign-warnings"):
		return
	var cat := CampaignCatalog.new(Content)
	cat.validate()
	for w in cat.warnings:
		print("WARN ", w)
	for e in cat.errors:
		print("ERR ", e)


## `--kit-bout <boss> <fighter> <tier> [seed]`: one bout as a timeline (tuning aid).
func test_zz_debug_bout() -> void:
	var args := OS.get_cmdline_user_args()
	var bi := args.find("--kit-bout")
	if bi < 0:
		return
	var ca := Content.creature(args[bi + 1])
	var cb := Content.creature(args[bi + 2])
	var tier := args[bi + 3]
	var seed_value := int(args[bi + 4]) if args.size() > bi + 4 and not args[bi + 4].begins_with("--") else 100
	var ba := BotBrain.new(tier, seed_value * 31 + 1)
	ba.set_personality(ca.ai)
	var bb := BotBrain.new(tier, seed_value * 31 + 2)
	bb.set_personality(cb.ai)
	var sim := duel(ca, cb, 4.0, ba, bb, 6.0, {"round_time": 90.0}, seed_value)
	var dt := 1.0 / Engine.physics_ticks_per_second
	var cursor := 0
	var next_line := 0.0
	while not sim.is_finished and sim.time < 98.0:
		sim.step(dt)
		await get_tree().physics_frame
		var a := sim.fighters[0]
		var b := sim.fighters[1]
		for ev in sim.events_since(cursor):
			cursor = int(ev["seq"])
			var ty := str(ev["type"])
			if ty == "hit":
				print("   %.2f HIT by %d slot %s dmg %.1f%s%s" % [sim.time, int(ev["fighter"]), str(ev.get("slot", "")), float(ev["damage"]),
					" BLOCKED" if bool(ev["blocked"]) else "", " PARRIED" if bool(ev["parried"]) else ""])
			elif ty in ["knockdown", "grab", "throw", "ko", "dodge", "parry", "guard_break"]:
				print("   %.2f %s by %d" % [sim.time, ty, int(ev.get("fighter", -1))])
		if sim.time >= next_line:
			next_line += 0.25
			print("%5.2f d=%.2f A %-9s %-9s hp %.0f st %.0f | B %-9s %-9s hp %.0f st %.0f reach %.2f+%.2f mv(%.1f,%.1f) guard %s" % [sim.time, a.pos().distance_to(b.pos()),
				Fighter.State.keys()[a.state], a.move_slot, a.health, a.stamina, Fighter.State.keys()[b.state], b.move_slot, b.health, b.stamina,
				bb.reach_of(b.creature, "l1"), bb._kit_target_bulk(b, a), b.input.move.x, b.input.move.z, str(b.input.is_held(FighterInput.GUARD))])
	print("winner %s" % str(sim.result.get("winner_team", -1)))
	sim.get_parent().queue_free()


## `--kit-debug <boss> <slot label> <gap> [weapon]`: per-tick weapon/projectile positions.
func test_zz_debug_move() -> void:
	var args := OS.get_cmdline_user_args()
	var di := args.find("--kit-debug")
	if di < 0:
		return
	var boss := args[di + 1]
	var label := args[di + 2]
	var gap := float(args[di + 3])
	var target: String = args[di + 4] if args.size() > di + 4 and not args[di + 4].begins_with("--") else DUMMY
	var quiet := args.has("--kit-quiet")
	var steps: Array = []
	var secs := 2.0
	for m in _moves(boss):
		if str(m[0]) == label:
			steps = m[1]
			secs = m[2]
	var each := func(sim: MatchSim, _out: Dictionary) -> void:
		var a := sim.fighters[0]
		var b := sim.fighters[1]
		var line := "t=%.2f %s st=%.2f root(%.2f,%.2f,%.2f) tgt z %.2f" % [sim.time, a.move_slot, a.state_time, a.pos().x, a.pos().y, a.pos().z, b.pos().z]
		for wn in ["jaws", "head", "claw_l", "paw_fl"]:
			var wd: BodyDef.Weapon = a.creature.body.weapons.get(wn)
			if wd:
				var wp := a.rig.bodies[wd.seg].global_transform * wd.local
				line += " %s(%.2f,%.2f,%.2f)" % [wn, wp.x, wp.y, wp.z]
		for e in sim.effects.entities:
			if str(e["kind"]) == "projectile":
				line += " P(%.2f,%.2f,%.2f)" % [e["pos"].x, e["pos"].y, e["pos"].z]
		for c in sim.combat.debug_contacts:
			line += " CONTACT vn=%.2f" % c["vn"]
		if (a.move != null or line.contains("P(")) and not quiet:
			print(line)
	var r := await shoot(boss, target, gap, steps, secs, [], Callable(_juiced) if label == "juice" else Callable(), 7.0, each)
	print("hits %d dmg %.1f grabs %d" % [r["hits"], r["damage"], count(r["events"], "grab", "fighter", 0)])


func test_zz_report_ranges() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--kit-report"):
		return
	var bosses: Array = BOSSES
	var bi := args.find("--kit-boss")
	if bi >= 0 and bi + 1 < args.size():
		bosses = [args[bi + 1]]
	for boss in bosses:
		for target in ["f_stoke", "f_jitters"]:
			for m in _moves(boss):
				var line := "%-16s %-9s %-9s" % [boss, target, m[0]]
				for gap in [1.6, 2.0, 2.4, 2.8, 3.2, 3.6, 4.2, 5.0, 6.0]:
					var r := await shoot(boss, target, gap, m[1], m[2], [], Callable(_juiced) if str(m[0]) == "juice" else Callable(), 7.0)
					var grabs := count(r["events"], "grab", "fighter", 0)
					line += " %.1f:%d/%.0f%s" % [gap, int(r["hits"]) + grabs, float(r["damage"]), ("G" if grabs > 0 else "")]
					if is_equal_approx(gap, 2.4):
						line += "[reach %.2f up %.2f spin %.1f]" % [r["reach"], r["min_up"], r["max_spin"]]
				print(line)
