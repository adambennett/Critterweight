extends "res://src/test/kits/npc_kit_case.gd"
## Kid Lamprey (npc_kid_lamprey) kit: every move connects at its intended range against a
## standing dummy and misses outside it, properties (push, launch, stun, guard, parry, armor,
## cooldowns, counter stance, grabs/pummel/throws, JUICE) behave, the tutorial's scripted
## partner behaviours work with the real Kid against every roster body, and the balance target
## holds (loses most bouts to a roster bot of the same tier but lands hits).
## Run: godot --headless --path game --fixed-fps 120 -- --test test_kit_npc_kid_lamprey
##      (add --balance for the full >= 20-bout tables, --kit-report for range tables)

const KID := "npc_kid_lamprey"
const DUMMY := "f_stoke"
const ROSTER := ["f_stoke", "f_dredge", "f_gusto", "f_dozer", "f_slurry", "f_jitters"]


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


func test_zz_debug_contacts() -> void:
	var args := OS.get_cmdline_user_args()
	var di := args.find("--kit-debug")
	if di < 0:
		return
	var slot := args[di + 1]
	var gap := float(args[di + 2])
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
	var r := await shoot(KID, DUMMY, gap, steps, secs, [], Callable(), 6.0, each)
	print("hits ", r["slots"], " glances ", r["glances"])


## Range tables for tuning: `-- --test test_kit_npc_kid_lamprey --kit-report [--kit-target f_x]
## [--kit-move slot]`. Each cell is gap:hits-of-that-slot/its damage(g = glances).
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
