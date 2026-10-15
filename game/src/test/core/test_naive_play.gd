extends TestCase
## UI-12 / AI-01 (brief §11, §13): bot difficulty is real for HUMAN-style play. A naive
## "button-masher" — walks at the opponent, mashes Light with the odd Heavy, never guards or
## dodges — fights bots of each tier in mirror matches with every roster fighter (The Gullet,
## one 45 s round, decision on health):
##   * it wins most bouts against the Punching Bag (the forgiving tier supports naive play), and
##     that bot stays forgiving: slow reactions, no parry taps, visible mistakes;
##   * it mostly loses to a Headliner (>= 70% of bouts) and to a Hall-of-Famer (>= 80%);
##   * against a Journeyman it is roughly even (reported; checked loosely with NAIVE_BOUTS).
## Bouts per fighter: NAIVE_BOUTS (default 2 for the Punching Bag, 1 for the top tiers; the
## Journeyman runs only when NAIVE_BOUTS is set). The tables in docs/BOTS.md use NAIVE_BOUTS=4.

const ROUND := 45.0


class Masher:
	extends InputSource
	var _t := 0.0
	var _last := -1.0
	var _heavy_at := 2.5

	func poll(f: Fighter, _sim, dt: float) -> void:
		_t += dt
		f.input.held = 0
		var tgt := f.target
		if tgt == null or tgt.is_out():
			f.input.move = Vector3.ZERO
			return
		var to := Vector3(tgt.pos().x - f.pos().x, 0.0, tgt.pos().z - f.pos().z)
		f.input.move = to.normalized() if to.length() > 0.7 else to.normalized() * 0.3
		if to.length() < 2.2 and _t - _last > 0.18:
			_last = _t
			if _t >= _heavy_at:
				_heavy_at = _t + 3.0
				f.input.press(FighterInput.HEAVY)
			else:
				f.input.press(FighterInput.LIGHT)


func _roster() -> Array:
	var ids := Content.playable_creatures().filter(func(c): return not str(c).begins_with("dev_"))
	return ids if not ids.is_empty() else ["dev_biped"]


func _bouts_per_fighter(default: int) -> int:
	var e := OS.get_environment("NAIVE_BOUTS")
	return int(e) if e.is_valid_int() and int(e) > 0 else default


## Plays one bout: masher (team 0) vs a bot of `tier` (team 1), same fighter. Returns
## {winner: team (-1 = draw), tally: the bot's decision tally}.
func _bout(cid: String, tier: String, seed_value: int) -> Dictionary:
	var c := Content.creature(cid)
	var brain := BotBrain.new(BotTiers.brain_tier(tier), seed_value)
	brain.set_personality(c.ai)
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	sim.setup({"arena": Content.arena("the_gullet"), "rules": {"mode": "standard", "rounds": 1, "round_time": ROUND},
		"seed": seed_value, "fighters": [{"creature": c, "team": 0, "source": Masher.new(), "kind": "bot"},
			{"creature": c, "team": 1, "source": brain, "kind": "bot"}]})
	await step_sim(sim, ROUND + 8.0)
	var w := int(sim.result.get("winner_team", -1)) if sim.is_finished else -1
	sim.get_parent().queue_free()
	return {"winner": w, "tally": brain.tally}


## Every roster fighter, `n` bouts each: {masher_wins, bot_wins, bouts, per: {cid: "MbM..."}, tally}.
func _series(tier: String, n: int, seed0: int) -> Dictionary:
	var out := {"masher_wins": 0, "bot_wins": 0, "bouts": 0, "per": {}, "tally": {}}
	for cid in _roster():
		var line := ""
		for k in n:
			var r := await _bout(str(cid), tier, seed0 + k * 17)
			var w := int(r["winner"])
			out["bouts"] = int(out["bouts"]) + 1
			if w == 0:
				out["masher_wins"] = int(out["masher_wins"]) + 1
			elif w == 1:
				out["bot_wins"] = int(out["bot_wins"]) + 1
			line += "M" if w == 0 else ("b" if w == 1 else "=")
			for key in r["tally"]:
				out["tally"][key] = int(out["tally"].get(key, 0)) + int(r["tally"][key])
		out["per"][str(cid).trim_prefix("f_")] = line
	print("NAIVE masher vs %s: masher won %d / %d, bot won %d (M = masher, b = bot) %s" % [tier, out["masher_wins"], out["bouts"],
		out["bot_wins"], str(out["per"])])
	return out


func test_a_button_masher_beats_the_punching_bag() -> void:
	var r := await _series("punching_bag", _bouts_per_fighter(2), 900)
	var bouts := int(r["bouts"])
	check(float(r["masher_wins"]) / bouts >= 0.65, "the masher wins most bouts against the easiest bot (%d / %d, %s)" % [r["masher_wins"], bouts, str(r["per"])])
	# and the easiest bot stays forgiving: slow, no parry taps, visible mistakes
	var t: Dictionary = r["tally"]
	check(float(BotBrain.PROFILES[BotTiers.brain_tier("punching_bag")]["reaction"]) >= 0.45, "Punching Bag reactions stay slow")
	check(int(t.get("ans_parry", 0)) + int(t.get("beat_tap", 0)) == 0, "the Punching Bag never taps a parry (%s)" % str(t))
	check(int(t.get("ans_mistake", 0)) >= bouts, "the Punching Bag visibly misreads attacks (%d mistakes in %d bouts)" % [t.get("ans_mistake", 0), bouts])


func test_the_masher_mostly_loses_to_a_headliner() -> void:
	var r := await _series("headliner", _bouts_per_fighter(1), 1300)
	var bouts := int(r["bouts"])
	check(float(r["bot_wins"]) / bouts >= 0.7, "a Headliner beats button-mashing in >= 70%% of bouts (%d / %d, %s)" % [r["bot_wins"], bouts, str(r["per"])])


func test_the_masher_mostly_loses_to_a_hall_of_famer() -> void:
	var r := await _series("hall_of_famer", _bouts_per_fighter(1), 1700)
	var bouts := int(r["bouts"])
	check(float(r["bot_wins"]) / bouts >= 0.8, "a Hall-of-Famer beats button-mashing in >= 80%% of bouts (%d / %d, %s)" % [r["bot_wins"], bouts, str(r["per"])])


## Reported (docs/BOTS.md); with NAIVE_BOUTS set it also checks the split is not lopsided.
func test_zz_a_journeyman_is_about_even_with_the_masher() -> void:
	if OS.get_environment("NAIVE_BOUTS") == "":
		print("NAIVE Journeyman series skipped (set NAIVE_BOUTS)")
		return
	var r := await _series("journeyman", _bouts_per_fighter(2), 2100)
	var share := float(r["masher_wins"]) / maxf(1.0, float(r["bouts"]))
	check(share >= 0.25 and share <= 0.75, "the Journeyman is roughly even with the masher (masher %d / %d)" % [r["masher_wins"], r["bouts"]])
