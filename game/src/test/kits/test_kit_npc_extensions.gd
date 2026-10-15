extends "res://src/test/kits/npc_kit_case.gd"
## Unit checks of the engine extensions added with the NPC kits (docs/kits/minions.md,
## docs/kits/bosses.md): hook events knocked_out / thrown, the "not" condition, effects fired on
## behalf of the event's other fighter and centred on the event point, lethal self_damage, shield
## statuses (guard_arc / guard_absorb) and the bot kit hints rest / bulky / keep_distance.
## Run: godot --headless --path game --fixed-fps 120 -- --test test_kit_npc_extensions


func test_hook_events_validate_and_not_condition() -> void:
	check(Hooks.validate({"on": "knocked_out", "do": [{"type": "hype", "amount": 5}]}).is_empty(), "knocked_out is a hook event")
	check(Hooks.validate({"on": "thrown", "do": [{"type": "area", "radius": 1.0, "damage": 2}]}).is_empty(), "thrown is a hook event")
	check(not Hooks.validate({"on": "knocked_outt", "do": []}).is_empty(), "unknown events are still rejected")
	var sim := duel("dev_biped", "dev_biped", 1.4)
	await step_sim(sim, 0.2)
	var a := sim.fighters[0]
	check(a.hooks._conditions({"not": {"flag": "spent"}}, {}), "'not' holds while the nested condition fails")
	a.set_flag("spent", 5.0)
	check(not a.hooks._conditions({"not": {"flag": "spent"}}, {}), "'not' fails once the nested condition holds")
	sim.get_parent().queue_free()


## A knocked-out fighter's "knocked_out" hook fires (its death burst hits the fighter beside it)
## unless a "not" condition vetoes it.
func test_knocked_out_hook_fires_unless_vetoed() -> void:
	for veto in [false, true]:
		var sim := duel("dev_biped", "dev_biped", 1.2)
		await step_sim(sim, 0.2)
		var a := sim.fighters[0]
		var b := sim.fighters[1]
		a.hooks.add({"on": "knocked_out", "if": {"not": {"flag": "spent"}}, "do": [{"type": "area", "radius": 2.0, "damage": 6, "knockback": 1.0}]})
		if veto:
			a.set_flag("spent", 9.0)
		var hp0 := b.health
		sim.combat.apply_simple_damage(b, a, 9999.0, "test")
		await step_sim(sim, 0.3)
		check(a.is_out(), "the hooked fighter is knocked out")
		if veto:
			check_near(b.health, hp0, 0.01, "vetoed by 'not': no burst")
		else:
			check(b.health < hp0, "its knocked_out burst hits the fighter beside it (%.1f)" % (hp0 - b.health))
		sim.get_parent().queue_free()


## "thrown" fires on the thrown fighter with the landing point; a delayed effect with
## "source": "other" is fired BY the thrower (credit and targeting are the thrower's) there.
func test_thrown_hook_acts_for_the_thrower_at_the_landing() -> void:
	var sim := duel("dev_biped", "dev_biped", 1.0)
	await step_sim(sim, 0.3)
	var thrower := sim.fighters[0]
	var victim := sim.fighters[1]
	victim.hooks.add({"on": "thrown", "do": [{"type": "set_flag", "flag": "was_thrown", "seconds": 5.0},
		{"type": "delayed", "source": "other", "delay": 0.6, "radius": 1.2, "damage": 5, "knockback": 1.0}]})
	thrower.begin_grab(victim, 0, 0)
	await step_sim(sim, 0.2)
	var cursor := sim.event_seq
	thrower._do_throw(thrower.forward())
	await step_sim(sim, 1.5)
	check(victim.has_flag("was_thrown"), "the thrown fighter's 'thrown' hook fired")
	var credited := false
	for ev in sim.events_since(cursor):
		if str(ev["type"]) == "hit" and int(ev["fighter"]) == thrower.index and int(ev["target"]) == victim.index and str(ev.get("slot", "")) == "effect":
			credited = true
	check(credited, "the burst at the landing spot is the thrower's (hits the thrown fighter, credited to the thrower)")
	sim.get_parent().queue_free()


func test_self_damage_lethal_only_when_asked() -> void:
	var sim := duel("dev_biped", "dev_biped", 2.0)
	await step_sim(sim, 0.2)
	var a := sim.fighters[0]
	sim.effects.fire(a, {"type": "self_damage", "amount": 999.0}, null)
	check_near(a.health, 1.0, 0.01, "plain self_damage leaves 1 HP")
	check(not a.is_out(), "and never knocks out")
	sim.effects.fire(a, {"type": "self_damage", "amount": 999.0, "lethal": true}, null)
	await step_sim(sim, 0.1)
	check(a.is_out(), "lethal self_damage knocks out (through the mode, like any depletion)")
	sim.get_parent().queue_free()


func test_shield_status_guards_its_arc() -> void:
	var sim := duel("dev_biped", "dev_biped", 2.0)
	await step_sim(sim, 0.3)
	var a := sim.fighters[0]
	var front := a.pos() + a.forward() * 1.5
	var back := a.pos() - a.forward() * 1.5
	check(not a.guards_against(front), "no shield, no guard: not guarding")
	a.statuses.add({"id": "lid_up", "duration": 5.0, "guard_arc": 120.0, "guard_absorb": 0.9})
	check(a.guards_against(front), "a 120-degree shield blocks from the front")
	check(not a.guards_against(back), "but not from behind")
	check_near(a.shield_damage_mult(0.3), 0.1, 0.001, "guard_absorb replaces the guard's absorption")
	a.statuses.add({"id": "withdrawn", "duration": 5.0, "guard_arc": 360.0})
	check(a.guards_against(back), "a 360-degree shell blocks from every side")
	sim.get_parent().queue_free()


## Bot hints: "rest" spaces a unit's attacks; "bulky" targets extend the attacker's reach to
## their nearest body part and open up during long recoveries; "keep_distance" is the ranged
## shorthand (range +- 0.4 and an implicit hint for the longest-reaching ability).
func test_bot_hints_rest_bulky_and_keep_distance() -> void:
	var starts := {}
	for rest in [false, true]:
		var bot := BotBrain.new("regular", 77)
		var ai := {"aggression": 0.4}
		if rest:
			ai["rest"] = [1.5, 1.5]
		bot.set_personality(ai)
		var sim := duel("dev_biped", "dev_biped", 1.0, bot, null)
		var n := 0
		var cursor := 0
		var t := 0.0
		while t < 10.0:
			await step_sim(sim, 0.1)
			t += 0.1
			for ev in sim.events_since(cursor):
				cursor = int(ev["seq"])
				if str(ev["type"]) == "move_start" and int(ev["fighter"]) == 0:
					n += 1
		starts[rest] = n
		sim.get_parent().queue_free()
	check(int(starts[true]) < int(starts[false]), "a resting bot starts fewer attacks (%d vs %d in 10 s)" % [starts[true], starts[false]])
	var sim2 := duel("dev_biped", "boss_bilge", 3.0)
	await step_sim(sim2, 0.3)
	var brain := BotBrain.new("regular", 5)
	var bulk := brain._kit_target_bulk(sim2.fighters[0], sim2.fighters[1])
	check(bulk > 0.5, "Bilge's head is in reach long before his root (bulk %.2f m)" % bulk)
	check_near(brain._kit_target_bulk(sim2.fighters[1], sim2.fighters[0]), 0.0, 0.001, "an ordinary target adds nothing")
	var recov := {"slot": "heavy", "st": 1.4, "state": Fighter.State.ATTACK}
	var windup := {"slot": "heavy", "st": 0.3, "state": Fighter.State.ATTACK}
	check(brain._kit_opening(recov, sim2.fighters[1]), "a bulky boss's heavy recovery is an opening")
	check(not brain._kit_opening(windup, sim2.fighters[1]), "its wind-up is not")
	check(not brain._kit_opening(recov, sim2.fighters[0]), "ordinary bodies never get openings from this hint")
	sim2.get_parent().queue_free()
	var ranged := BotBrain.new("regular", 6)
	ranged.set_personality({"prefers": "ranged", "keep_distance": 4.0})
	check_eq(ranged._kit_range(), [3.6, 4.4], "keep_distance 4 is a range of 3.6..4.4 m")
	var pel := Content.creature("npc_scrapling_pelter")
	check(not ranged._kit_hint_for(pel, "ability2").is_empty(), "its longest-reaching ability (Bolt Toss) gets an implicit hint")
	check(ranged._kit_hint_for(pel, "ability1").is_empty(), "other abilities stay generic")
