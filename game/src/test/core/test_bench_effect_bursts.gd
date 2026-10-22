extends TestCase
## The performance stress input must really execute its held attacks, after a bot's poll.
const Bench := preload("res://src/test/bench.gd")


class ClearInputBot:
	extends InputSource
	func poll(f: Fighter, _sim: MatchSim, _dt: float) -> void:
		f.input.held = 0


func test_stress_driver_holds_a_stream_after_bot_input() -> void:
	var driver := Bench.BurstDriver.new()
	driver.bot = ClearInputBot.new()
	var other := Bench.BurstDriver.new()
	var sim := make_sim("", {"mode": "standard", "combat": "moves", "intro_time": 0.1, "round_time": 0},
		[{"creature": "f_stoke", "team": 0, "source": driver}, {"creature": "f_dredge", "team": 1, "source": other}])
	await step_sim(sim, 0.3)
	var f := sim.fighters[0]
	f.charges_left["m2"] = 0
	f.cooldown_left["m2"] = 10.0
	Bench._all_use_ability(sim, 1)       # second equipped move: Flamethrower
	await step_sim(sim, 1.8)
	var starts := sim.events.filter(func(e: Dictionary) -> bool:
		return e["type"] == "sustain" and e.get("phase", "") == "start" and int(e.get("fighter", -1)) == 0)
	var ticks := sim.events.filter(func(e: Dictionary) -> bool:
		return e["type"] == "effect" and e.get("vfx", "") == "flamethrower")
	check(not starts.is_empty(), "the stress press starts a held stream")
	check(ticks.size() >= 5, "it produces sustained effects, not just a tap (%d)" % ticks.size())
	check(not f.input.is_held(FighterInput.HEAVY), "the synthetic hold is released")
	check(driver.button == -1, "the driver returns to ordinary bot control")


func test_stress_driver_keeps_classic_ability_buttons() -> void:
	var driver := Bench.BurstDriver.new()
	var other := Bench.BurstDriver.new()
	var sim := make_sim("", {"mode": "standard", "combat": "classic", "intro_time": 0.1, "round_time": 0},
		[{"creature": "f_stoke", "team": 0, "source": driver}, {"creature": "f_dredge", "team": 1, "source": other}])
	await step_sim(sim, 0.3)
	Bench._all_use_ability(sim, 0)
	check_eq(driver.button, FighterInput.AB1, "Classic still bursts ability 1 first")
	await step_sim(sim, 0.8)
	check(sim.events.any(func(e: Dictionary) -> bool:
		return e["type"] == "ability" and int(e.get("fighter", -1)) == 0), "the Classic ability actually executes")
