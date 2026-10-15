extends TestCase
## Generic engine extensions added during the Stoke/Gusto kit pass (fighter.gd / effects.gd
## "Kit extension" blocks), verified on the dev biped so they do not depend on any kit:
##  * hover effects actually lift the fighter (the lift used to be overwritten by the motor) and the
##    legs re-plant once the hover ends;
##  * ground zones ignore hovering fighters;
##  * the "throw" hook event carries the throw direction as "slot";
##  * throws may carry a "stun" (no-knockdown spacing throws).


func _sim(gap := 1.1) -> MatchSim:
	var arena := ArenaDef.from_dict({"id": "t", "base": "octagon", "radius": 5.0, "spawns": [[0, -gap * 0.5, 0], [0, gap * 0.5, 180]]})
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var c := Content.creature("dev_biped")
	sim.setup({"arena": arena, "rules": {"rounds": 1, "round_time": 0, "intro_time": 0.3}, "seed": 5,
		"fighters": [{"creature": c, "team": 0, "source": null}, {"creature": c, "team": 1, "source": null}]})
	return sim


func test_hover_lifts_then_lands_and_replants() -> void:
	var sim := _sim(3.0)
	await step_sim(sim, 0.5)
	var f := sim.fighters[0]
	var y0 := f.pos().y
	sim.effects.fire(f, {"type": "hover", "height": 1.5, "duration": 1.0, "speed": 3.0}, null)
	await step_sim(sim, 0.8)
	check(f.has_flag("hovering"), "hovering")
	check(f.pos().y > y0 + 1.0, "hover lifts the root (%.2f -> %.2f)" % [y0, f.pos().y])
	check(f.motor.tuck, "legs tucked while hovering")
	await step_sim(sim, 1.6)
	check(not f.has_flag("hovering"), "hover ended")
	check(absf(f.pos().y - y0) < 0.15, "back at stance height (%.2f vs %.2f)" % [f.pos().y, y0])
	check(not f.motor.tuck, "legs untucked and re-planted after the hover")


func test_zones_ignore_hovering_fighters() -> void:
	var sim := _sim(3.0)
	await step_sim(sim, 0.5)
	var a := sim.fighters[0]
	var b := sim.fighters[1]
	sim.effects.spawn_zone(a, {"kind": "scorch_patch", "radius": 1.0, "duration": 3.0, "skip_zone_reaction": true}, b.ground_pos())
	sim.effects.fire(b, {"type": "hover", "height": 1.5, "duration": 2.0, "speed": 3.0}, null)
	await step_sim(sim, 1.2)
	check_near(b.health, b.max_health, 0.01, "hovering fighter takes no zone damage")
	check(float(b.statuses.buildup.get("scorch", 0.0)) <= 0.0, "nor zone build-up")
	await step_sim(sim, 1.4)
	check(b.health < b.max_health, "once landed the zone affects it again")


func test_throw_hook_slot_and_throw_stun() -> void:
	var sim := _sim(1.0)
	await step_sim(sim, 0.5)
	var a := sim.fighters[0]
	var b := sim.fighters[1]
	var saved: Dictionary = a.creature.throws   # shared definition: restored below
	a.creature.throws = {"throw_side": {"distance": 2.0, "damage": 3, "knockdown": false, "stun": 0.5}}
	a.hooks.add({"on": "throw", "if": {"slot": "throw_side"}, "do": [{"type": "set_flag", "flag": "side_thrown", "seconds": 5.0}]}, "test")
	a.begin_grab(b, 0, 0)
	check(a.state == Fighter.State.GRABBING, "holding")
	a._do_throw(a.forward().cross(Vector3.UP))
	check(a.has_flag("side_thrown"), "throw hook filtered by slot=throw_side fired")
	check(b.state == Fighter.State.HITSTUN, "no-knockdown throw stuns the victim (%s)" % b.state_name())
	a.creature.throws = saved


## Bot kit tactics (bot_brain.gd "Kit tactics" block): a Heavy press is a tap unless the
## creature's ai block asks for a charge; ability rules fire on their conditions only.
func test_bot_heavy_tap_and_charge_rule() -> void:
	var sim := _sim(3.0)
	await step_sim(sim, 0.5)
	var f := sim.fighters[0]
	var bb := BotBrain.new("regular", 7)
	bb._kit_press_heavy(f, null)
	bb.poll(f, sim, 1.0 / 120.0)
	check(not f.input.is_held(FighterInput.HEAVY), "plain bot Heavy is a tap")
	var cb := BotBrain.new("pro", 7)
	cb.set_personality({"charge_heavy": {"from": "pro", "chance": 1.0}})
	cb._kit_press_heavy(f, null)
	cb.poll(f, sim, 1.0 / 120.0)
	check(f.input.is_held(FighterInput.HEAVY), "charge rule holds Heavy")
	var rb := BotBrain.new("regular", 7)
	rb.set_personality({"charge_heavy": {"from": "pro", "chance": 1.0}})
	rb._kit_press_heavy(f, null)
	rb.poll(f, sim, 1.0 / 120.0)
	check(not f.input.is_held(FighterInput.HEAVY), "charge rule is gated by the profile (Journeyman never charges)")


func test_bot_ability_rules_fire_on_conditions() -> void:
	var sim := _sim(2.5)
	var bb := BotBrain.new("champion", 11)
	bb.set_personality({"abilities": {"ability1": [{"if": ["target_down"], "chance": 1.0}]}})
	sim.set_input_source(0, bb)
	await step_sim(sim, 1.5)
	var used := sim.events.filter(func(e): return e["type"] == "ability" and int(e["fighter"]) == 0 and str(e["slot"]) == "ability1")
	check(used.is_empty(), "rule-only ability is not used while its condition is false")
	sim.fighters[1].knock_down("test", sim.fighters[0])
	# the bot may be in the middle of a 0.66 s Heavy when the target falls: allow it to finish
	var t_down := 0.0
	while t_down < 1.4 and sim.fighters[1].is_down():
		await step_sim(sim, 0.1)
		t_down += 0.1
	used = sim.events.filter(func(e): return e["type"] == "ability" and int(e["fighter"]) == 0 and str(e["slot"]) == "ability1")
	check(not used.is_empty(), "ability fires once the target is down (down for %.1f s)" % t_down)
