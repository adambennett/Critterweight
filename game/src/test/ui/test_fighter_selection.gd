extends TestCase

func test_random_is_offered_for_empty_single_and_full_rosters() -> void:
	check_eq(FighterSelection.with_random([]), ["random"], "empty roster")
	check_eq(FighterSelection.with_random(["f_stoke"]), ["random", "f_stoke"], "single fighter roster")
	check_eq(FighterSelection.with_random(["f_stoke", "f_gusto"]), ["random", "f_stoke", "f_gusto"], "full roster")


func test_random_options_are_unique_and_stay_out_of_playable_ids() -> void:
	check_eq(FighterSelection.with_random(["random", "f_stoke", "f_stoke", ""]), ["random", "f_stoke"], "deduplicated options")


func test_random_resolves_to_a_valid_fighter_and_seed_is_repeatable() -> void:
	var roster := ["f_stoke", "f_gusto", "f_jitters"]
	for seed_value in range(1, 25):
		var picked := FighterSelection.resolve("random", roster, seed_value)
		check(roster.has(picked), "seed %d resolves to a roster fighter" % seed_value)
		check_eq(FighterSelection.resolve("random", roster, seed_value), picked, "seed %d repeats" % seed_value)


func test_fixed_and_invalid_choices_have_stable_fallbacks() -> void:
	var roster := ["f_stoke", "f_gusto"]
	check_eq(FighterSelection.resolve("f_gusto", roster), "f_gusto", "fixed choice")
	check_eq(FighterSelection.resolve("missing", roster), "f_stoke", "invalid choice uses first roster member")
	check_eq(FighterSelection.resolve("random", []), "", "empty roster stays empty")
