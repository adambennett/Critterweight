extends TestCase

func test_hub_spar_random_opponent_resolves_before_match_build() -> void:
	var config := HubSparring.config("f_stoke", "Test Player", {"opponent": "random"})
	var selected := str(config.get("hub_spar", {}).get("opponent", ""))
	var choices: Array = ["kid_lamprey"]
	choices.append_array(Content.playable_creatures())
	check(selected != "random" and choices.has(selected), "random spar opponent resolves to an available fighter")
	check_eq(str(config.get("fighters", [])[1].get("creature", "")), HubSparring.opponent_creature(selected, "f_stoke"), "match config uses resolved opponent")


func test_fight_camp_random_choice_becomes_a_concrete_fighter_before_start() -> void:
	var resolved := HubBoardStation.resolve_fighter_choice({"fighter": "random", "difficulty": "amateur"}, ["f_stoke", "f_gusto"])
	check(["f_stoke", "f_gusto"].has(str(resolved.get("fighter", ""))), "Fight Camp start never receives the Random marker")
	check_eq(str(resolved.get("difficulty", "")), "amateur", "other card options stay intact")
