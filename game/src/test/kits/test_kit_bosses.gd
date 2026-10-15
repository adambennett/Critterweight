extends "res://src/test/kits/npc_kit_case.gd"
## Boss base kits (ENEMIES_BOSSES.md §2): Bilge (boss_bilge), Conduit (boss_conduit),
## Commissioner Snappington (boss_snappington).
## Run: godot --headless --path game --fixed-fps 120 -- --test test_kit_bosses
##      (add --balance for the >= 20-bout tables, --kit-report [--kit-boss id] for ranges)

const BOSSES := ["boss_bilge", "boss_conduit", "boss_snappington"]
const DUMMY := "f_stoke"
## Outside the campaign a boss in a bot slot has 2x the highest fighter HP and no phases
## (ENEMIES_BOSSES.md "Custom rules"); balance bouts use that unless --kit-full-hp.
const BOT_SLOT_HP := 2.0


## boss -> [[label, inputs, seconds]] for every damaging move (hits counted from all slots).
func _moves(boss: String) -> Array:
	return [
		["l1", press("light"), 2.2],
		["l2", string_presses(2, 0.7), 3.2],
		["heavy", press("heavy"), 2.8],
		["grab", press("grab"), 3.0],
		["ability1", press("ability1"), 3.0],
		["ability2", press("ability2"), 4.2],
		["juice", press("juice"), 4.5],
	]


static func _juiced(sim: MatchSim) -> void:
	sim.fighters[0].hype = 100.0


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
				bb.reach_of(b.creature, "l1"), bb._npc_target_bulk(b, a), b.input.move.x, b.input.move.z, str(b.input.is_held(FighterInput.GUARD))])
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
		if a.move != null or line.contains("P("):
			print(line)
	var r := await shoot(boss, DUMMY, gap, steps, secs, [], Callable(_juiced) if label == "juice" else Callable(), 7.0, each)
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
