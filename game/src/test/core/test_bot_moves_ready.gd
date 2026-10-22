extends TestCase
## Bot ability hints must follow equipped Movesets charges, including custom slot order.


func test_mapped_ability_uses_equipped_charges() -> void:
	var sim := make_sim("", {"combat": "moves"}, [
		{"creature": "f_stoke", "team": 0, "source": null,
		"loadout": ["steam_vent", "flamethrower", "ember_jab", "stoke_the_fire"]},
		{"creature": "f_dredge", "team": 1, "source": null}])
	var f := sim.fighters[0]
	var bot := BotBrain.new("pro", 18)
	f.charges_left["ability1"] = 1
	f.charges_left["m1"] = 0
	check(not bot._kit_ability_ready(f, "ability1"), "Steam Vent is unavailable on its equipped slot")
	f.charges_left["m1"] = 1
	check(bot._kit_ability_ready(f, "ability1"), "Steam Vent becomes available after recharge")
	f.charges_left["m4"] = 0
	check(not bot._kit_ability_ready(f, "ability2"), "support readiness follows slot four")
	f.charges_left["m4"] = 1
	check(bot._kit_ability_ready(f, "ability2"), "support is available after recharge")
	f.mods["no_abilities"] = true
	check(not bot._kit_ability_ready(f, "ability2"), "ability restriction is respected")


func test_unequipped_abilities_cannot_occupy_a_bot_decision() -> void:
	var sim := make_sim("", {"combat": "moves"}, [
		{"creature": "f_stoke", "team": 0, "source": null,
		"loadout": ["ember_jab", "flamethrower", "cinder_shot", "fire_spin"]},
		{"creature": "f_dredge", "team": 1, "source": null}])
	var f := sim.fighters[0]
	var bot := BotBrain.new("pro", 18)
	check(not bot._kit_ability_ready(f, "ability1"), "unequipped Steam Vent is unavailable")
	check(not bot._kit_ability_ready(f, "ability2"), "unequipped Stoke the Fire is unavailable")
	check(not bot._kit_ability(f, sim.fighters[1], 1.0, Vector3.FORWARD, {}, false),
		"the hint layer yields its decision to an equipped move")


func test_classic_ability_readiness_keeps_original_slots() -> void:
	var sim := make_sim("", {"combat": "classic"}, [
		{"creature": "f_stoke", "team": 0, "source": null},
		{"creature": "f_dredge", "team": 1, "source": null}])
	var f := sim.fighters[0]
	var bot := BotBrain.new("pro", 18)
	f.charges_left["m3"] = 0
	check(bot._kit_ability_ready(f, "ability1"), "Classic ignores Movesets slot charges")
	f.charges_left["ability1"] = 0
	check(not bot._kit_ability_ready(f, "ability1"), "Classic still waits for ability recharge")
