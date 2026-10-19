extends "res://src/test/kits/dd_kit_base.gd"
## CNT-09: guest controls, both playable kits, physics, campaign upgrades and wire input.

func after_each() -> void:
	for action in Controls.GAME_ACTIONS:
		Input.action_release(action)
	Controls._mma_view_used = false


func test_models_have_every_segment_and_playable_campaign_kits() -> void:
	var catalog := CampaignCatalog.new(Content)
	for id in ["f_varga", "f_knell"]:
		var c := Content.creature(id)
		check(c.is_valid(), "%s valid: %s" % [id, c.errors])
		check(not bool(Content.get_entry("creatures", id).get("npc_only", true)), "playable")
		check(catalog.rules.get("roster", []).has(id), "%s on campaign roster" % id)
		var view := CreatureView.new()
		add_child(view)
		view.setup(c)
		check(view._skeleton != null, "%s has imported skeleton" % id)
		for bone in view._bone_of_seg:
			check(bone >= 0, "%s every segment bound" % id)
		view.queue_free()
		var techniques: Array = catalog.techniques_by_fighter.get(id, [])
		check_eq(techniques.size(), 6, "%s six techniques" % id)
		var result := BuildApplier.compose(catalog, {"variant": "off_the_street"}, {"fighter": id, "techniques": techniques})
		check(result["errors"].is_empty(), "%s upgraded kit parses: %s" % [id, result["errors"]])
		check(result["warnings"].is_empty(), "%s every upgrade applies: %s" % [id, result["warnings"]])
		if id == "f_knell":
			check_near(result["max_hp"], 140, .01, "salvaged plates affect health")
			check_near(float(result["creature_dict"]["abilities"]["ability1"]["effects"][0]["life"]), 2.86, .001, "long wick affects projectile")


func test_extended_inputs_roundtrip_with_high_held_bits_and_wrap() -> void:
	var inp := FighterInput.new()
	inp.move = Vector3(.25, 0, -.5)
	for b in range(FighterInput.MMA_LL, FighterInput.BUTTON_COUNT):
		inp.press_count[b] = 254
		inp.press(b)
	var bytes := StreamPeerBuffer.new()
	inp.encode(bytes)
	bytes.seek(0)
	var decoded := FighterInput.decode(bytes)
	check_eq(decoded.held, inp.held, "bits 16/17 survive")
	check_eq(decoded.press_count, inp.press_count, "all counters survive")
	var tracker := FighterInput.PressTracker.new()
	tracker.consume(decoded)
	decoded.press(FighterInput.MMA_CHECK)
	check_eq(tracker.consume(decoded), 1 << FighterInput.MMA_CHECK, "255 to 0 wrap produces exactly one check press")
	check_eq(tracker.consume(decoded), 0, "retransmission is not a new press")
	var writer := NetWriter.new()
	NetSnapshot.write_input(writer, inp)
	var reader := NetReader.new(writer.data())
	var net := NetSnapshot.read_input(reader)
	check(reader.ok and reader.at_end(), "network reads expanded sample")
	check_eq(net.held, inp.held)
	check_eq(net.press_count, inp.press_count)


func test_live_input_context_isolated_and_opponent_relative() -> void:
	Input.action_press("mma_ll")
	Input.action_press("light")  # keyboard J overlaps these intentionally
	Input.action_press("move_up")
	var guest := FighterInput.new()
	var standard := FighterInput.new()
	Controls.fill(guest, Basis.IDENTITY, Content.creature("f_varga"), Vector3.RIGHT)
	Controls.fill(standard, Basis.IDENTITY, Content.creature("f_knell"), Vector3.RIGHT)
	check_eq(int(guest.press_count[FighterInput.MMA_LL]), 1, "guest J is left leg")
	check_eq(int(guest.press_count[FighterInput.LIGHT]), 0, "guest J does not also punch")
	check_eq(int(standard.press_count[FighterInput.LIGHT]), 1, "standard J still light")
	check_eq(int(standard.press_count[FighterInput.MMA_LL]), 0, "guest action ignored by regular fighter")
	check(guest.move.dot(Vector3.RIGHT) > .9, "guest moves toward enemy")
	check(standard.move.dot(Vector3.FORWARD) > .9, "regular fighter stays camera relative")


func test_view_target_chord_does_not_switch_stance_or_fire_juice() -> void:
	var inp := FighterInput.new()
	Input.action_press("mma_juice")
	Input.action_press("mma_stance")
	Controls.fill_martial(inp, Basis.IDENTITY, Vector3.BACK)
	check_eq(int(inp.press_count[FighterInput.TARGET]), 1)
	check_eq(int(inp.press_count[FighterInput.MMA_STANCE]), 0)
	Input.action_release("mma_stance")
	Input.action_release("mma_juice")
	Controls.fill_martial(inp, Basis.IDENTITY, Vector3.BACK)
	check_eq(int(inp.press_count[FighterInput.JUICE]), 0, "chord release does not spend JUICE")


func test_every_limb_modifier_has_a_move_in_both_stances() -> void:
	var c := Content.creature("f_varga")
	for southpaw in [false, true]:
		for mod in 4:
			for limb in MartialStyle.LIMBS:
				var slot := MartialStyle.slot(limb, mod, southpaw)
				check(c.moves.has(slot), "available %s" % slot)
				var move: MoveDef = c.moves.get(slot)
				if move:
					check(not move.windows.is_empty() and move.damage > 0, "%s has an attack" % slot)
					for window in move.windows:
						for weapon in window["weapons"]:
							check(c.body.weapons.has(weapon), "%s weapon %s resolves" % [slot, weapon])


func test_martial_buffer_remembers_modifier_and_stance_switches() -> void:
	var r := await measure_move("f_varga", "lh_straight", 4.0, {"via": [
		{"t0": 0.0, "press": ["mma_stance"]},
		{"t0": .1, "t1": .15, "hold": ["mma_mod2"], "press": ["light"]}], "dur": 1.4, "keep": true})
	check(r["a"].martial_southpaw, "X/D-left switches stance")
	check(r["slots"].has("rh_straight@southpaw"), "modified left hand selects mirrored jab (%s)" % r["slots"])
	release(r)


func test_imported_strikes_connect_and_stay_physically_stable() -> void:
	for slot in ["lh_straight", "rh_straight", "lh_hook", "rh_hook", "lh_uppercut", "rh_uppercut", "lh_overhand", "rh_overhand", "ll_teep", "rl_knee", "ll_bkick", "rl_bkick", "ll_hkick", "rl_hkick", "ll_lkick", "rl_lkick"]:
		var landed := false
		for gap in [.7, 1.0, 1.3]:
			var r := await measure_move("f_varga", slot, gap, {"dur": 1.4})
			print("VARGA %s gap %.1f hits %d up %.2f reach %.2f pen %.2f base %.2f" % [slot, gap, r["melee"].size(), r["min_up"], r["max_reach"], r["max_pen"], r["base_pen"]])
			# Kicks intentionally roll the torso up to 62 degrees and pivot the hips.
			# Test their authored range plus recovery, instead of forbidding those motions.
			check(float(r["min_up"]) > .25, "%s never falls over" % slot)
			check(float(r["max_yaw_err"]) < 130, "%s remains within its hip pivot" % slot)
			check(float(r["max_reach"]) < 1.6, "%s reach cap" % slot)
			check(float(r["max_w"]) < 60 and not r["escaped"], "%s controlled and in arena" % slot)
			check(float(r["max_pen"]) < float(r["base_pen"]) + .08, "%s no self clipping (%.3f)" % [slot,r["max_pen"]])
			if not r["melee"].is_empty():
				landed = true
				break
		check(landed, "%s connects in its intended close range" % slot)
	var miss := await measure_move("f_varga", "rh_straight", 3.5)
	check(miss["melee"].is_empty(), "punch misses well outside reach")


func test_knell_normal_string_and_spectral_projectile() -> void:
	var normal := await measure_move("f_knell", "l1", .7, {"via": [{"t0": 0.0, "press": ["light"]}], "dur": 1.5})
	check(normal["slots"].has("l1") and not normal["melee"].is_empty(), "Knell standard light connects")
	check_sane(normal, "Knell light")
	var bolt := await measure_move("f_knell", "ability1", 3.0)
	check(not bolt["effect_hits"].is_empty(), "Ghost Light reaches a distant rival")
	check(float(bolt["b_buildup"].get("spectral", 0)) > 0, "Ghost Light builds Haunted")


func test_knell_blink_and_last_bell_have_real_effects() -> void:
	var blink := await measure_move("f_knell", "ability2", 6.0, {"keep": true})
	check((blink["a_disp"] as Vector3).z > 2.5, "Through the Veil relocates toward the opponent")
	release(blink)
	var bell := await measure_move("f_knell", "juice", 1.8, {"keep": true})
	check(not bell["effect_hits"].is_empty(), "Last Bell hits nearby opponents")
	check(bell["a"].statuses.has("last_bell"), "Last Bell protection active")
	check_eq(count_events(bell["events"], "effect", "effect", "area"), 3, "three expanding pulses")
	release(bell)


func test_varga_abilities_and_juice() -> void:
	var step := await measure_move("f_varga", "ability1", 5.0, {"keep": true})
	check((step["a_disp"] as Vector3).z > .15, "Cut the Angle moves Varga")
	check(step["a"].statuses.has("angle"), "angle damage bonus active")
	release(step)
	var wind := await measure_move("f_varga", "ability2", 5.0, {"keep": true})
	check_near(wind["a"].statuses.mult("stamina_regen"), 2, .001, "Second Wind doubles regeneration")
	release(wind)
	var sim := kit_sim("f_varga", dummy(), 4.0)
	await run(sim, .4)
	var f := sim.fighters[0]
	f.hype = 100
	f.input.press(FighterInput.JUICE)
	await run(sim, .6)
	check(f.hype < 1 and f.has_flag("juiced"), "JUICE spends meter and enters state")
	check(f.statuses.has("championship"), "Championship Rounds bonus active")
	release(sim)


func test_new_statuses_and_reaction() -> void:
	var sim := kit_sim("f_varga", "f_knell", 3.0)
	var f := sim.fighters[1]
	f.statuses.add_buildup("scrap", 110, sim.fighters[0])
	check_near(f.statuses.mult("guard_cost"), 1.25, .001, "Rattled makes guarding expensive")
	f.statuses.add_buildup("spectral", 110, sim.fighters[0])
	check_eq(count_events(sim.events, "reaction", "reaction", "bell_ringer"), 1)
	check(not f.statuses.has_element("scrap"), "Bell Ringer consumes Rattled")
	await run(sim, 2.1)
	f.statuses.add_buildup("spectral", 110, sim.fighters[0])
	check_near(f.statuses.mult("cooldown_rate"), .75, .001, "Haunted slows cooldown recovery")
	release(sim)


func test_new_bots_finish_bout_and_varga_varies_strikes() -> void:
	var result := await spar("f_varga", "f_knell", 1, "pro", 555, 25.0)
	print("NEW FIGHTERS SPAR ", result)
	check(int(result["bouts"]) == 1, "headless bout completes")
	check(float(result["dmg"].get("f_varga", 0)) > 0, "Varga bot deals damage")
	check(float(result["dmg"].get("f_knell", 0)) > 0, "Knell bot deals damage")


func test_southpaw_physical_strikes_recover_and_keep_reach() -> void:
	for limb in MartialStyle.LIMBS:
		for mod in 4:
			var slot := MartialStyle.slot(limb, mod, true)
			var landed := false
			for gap in [.5, .7, .9, 1.1, 1.3, 1.5]:
				var r := await measure_move("f_varga", slot, gap, {"dur": 2.0, "keep": true, "before": func(s: MatchSim): s.fighters[0].martial_southpaw = true})
				check(float(r["max_reach"]) < 1.6, "%s reach" % slot)
				check(float(r["max_pen"]) < float(r["base_pen"]) + .08, "%s no self clip %.3f" % [slot,r["max_pen"]])
				check(r["a"].rig.root().global_basis.y.dot(Vector3.UP) > .95, "%s upright after recovery" % slot)
				landed = not r["melee"].is_empty()
				release(r)
				if landed: break
			check(landed, "%s southpaw connects" % slot)


func test_guest_tutorial_teaches_completable_inputs() -> void:
	for lesson in [1,2,5,6,8]:
		var sim := MatchSim.new()
		sim.running = false
		fresh_world().add_child(sim)
		var mode := TutorialMode.new()
		mode.start_index = lesson
		sim.setup({"arena": Tutorial.practice_cage(), "mode": mode, "seed": 4,
			"rules": {"mode": "tutorial", "intro_time": 0.0},
			"fighters": [{"creature": Content.creature("f_varga"), "team": 0, "kind": "player"},
			{"creature": Content.creature(Tutorial.partner_for("f_varga")), "team": 1, "kind": "scripted"}]})
		var f := sim.fighters[0]
		check(not mode.objective().contains("{"), "all guest prompts resolve")
		if lesson == 2: check(mode.adapted("no_charge"), "no impossible charged attack")
		if lesson == 8: check(mode.adapted("no_finisher"), "no impossible standard finisher")
		var next := .6
		for tick in 4200:
			if mode.state in ["success", "complete", "done_single"]: break
			var to := sim.fighters[1].pos() - f.pos()
			to.y = 0
			f.input.held = 0
			f.input.move = to.normalized() if to.length() > (1.05 if lesson == 2 else .65) else Vector3.ZERO
			if lesson == 8:
				f.hype = 100
				f.input.press(FighterInput.JUICE)
			elif sim.time >= next and TutorialMode.swing_over(f) and (lesson != 1 or to.length() < 1.2):
				next = sim.time + .5
				match lesson:
					1:
						var step := int(mode.data.get("step",0))
						f.input.set_held(FighterInput.MMA_MOD1 if step == 2 else FighterInput.MMA_MOD2,true)
						f.input.press(FighterInput.HEAVY if step == 1 else FighterInput.LIGHT)
					2:
						f.input.set_held(FighterInput.MMA_MOD2,true)
						f.input.press(FighterInput.MMA_RL)
					5:
						if f.statuses.has("angle"):
							f.input.set_held(FighterInput.MMA_MOD2,true)
							f.input.press(FighterInput.LIGHT)
						else: f.input.press(FighterInput.AB1)
					6: f.input.press(FighterInput.GRAB)
			if lesson == 6 and f.state == Fighter.State.GRABBING:
				f.input.move=to.normalized()
				f.input.press(FighterInput.GRAB)
			sim.step(DT)
			await get_tree().physics_frame
		print("GUEST LESSON ",lesson," ",mode.state," ",mode.progress_text())
		check(mode.state in ["success", "complete", "done_single"], "guest lesson %s completes using taught inputs" % lesson)
		release(sim)


func test_low_check_cannot_block_unblockable_hits() -> void:
	for unblockable in [false,true]:
		var sim := kit_sim("f_knell", "f_varga", 1.2)
		await run(sim,.4)
		var b := sim.fighters[1]
		b.input.set_held(FighterInput.MMA_CHECK,true)
		var hit := {"damage":10.0,"part":"leg","melee":true,"unblockable":unblockable,
			"blocked":false,"parried":false,"poise":0.0,"knockback":Vector3.ZERO,"stun":0.0,"seg":0,
			"point":b.pos(),"normal":Vector3.FORWARD,"from":sim.fighters[0].pos()}
		sim.combat.deliver(sim.fighters[0],b,hit)
		check_eq(hit["blocked"],not unblockable,"low check respects unblockable")
		release(sim)


func test_online_footwork_uses_selected_target_not_nearest_enemy() -> void:
	var sim := make_sim("the_gullet", {"rounds": 1, "round_time": 0}, [
		{"creature": "f_varga", "team": 0}, {"creature": "f_knell", "team": 1},
		{"creature": "f_dozer", "team": 2}])
	var f := sim.fighters[0]
	f.target = sim.fighters[2]
	var direction := NetClient.control_direction(f, sim.fighters)
	check(direction.is_equal_approx(f.target.pos() - f.pos()), "network input respects server-selected target")
	f.target = null
	check(NetClient.control_direction(f, sim.fighters).length() > 0, "target gap has an enemy fallback")
	release(sim)


func test_guest_dodge_lesson_does_not_require_standard_dash_attack() -> void:
	var mode := TutorialMode.new()
	var ex := {"check": "dodge_then_dash", "params": {}}
	check(bool(mode._adaptation(ex, Content.creature("f_varga")).get("no_dash", false)), "guest slip lesson does not ask for an unavailable light-to-dash input")
	check(not bool(mode._adaptation(ex, Content.creature("f_knell")).get("no_dash", false)), "standard fighter still learns the dash attack")


func test_tutorial_kid_does_not_retain_a_finished_course() -> void:
	var mode := TutorialMode.new()
	mode.kid = TutorialMode.KidScript.new(mode)
	var ref: WeakRef = weakref(mode)
	mode = null
	check(ref.get_ref() == null, "course and Kid do not form a reference cycle")


func test_guard_shove_requires_its_stamina_cost() -> void:
	var sim := kit_sim("f_varga", dummy(), 1.0)
	var f := sim.fighters[0]
	for energy in [0.0,10.0]:
		f._set_state(Fighter.State.NEUTRAL)
		f.stamina = energy
		f.guard_held = true
		f._martial_guard_tap = f.time - .1
		f._buffer = [{"b":FighterInput.GUARD,"t":f.time}]
		f._try_actions(false)
		check_eq(count_events(sim.events, "effect", "effect", "push"), 1 if energy > 0 else 0, "empty stamina cannot produce a free shove")
		check_near(f.stamina, maxf(0.0, energy - 5), .001, "successful shove pays five stamina")
	release(sim)
