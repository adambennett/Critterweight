class_name CampaignProgression
extends RefCounted
## End-of-run bookkeeping for ONE player's profile (works on a profile Dictionary — the live
## Profiles.current at runtime, a standalone dict in tests; the caller saves it).
##   * Off the Street: statistics, records, history, cosmetics and The Dosage ladder persist;
##     NOTHING that changes starting power (its 50% Clout goes to a cosmetics-only wallet).
##   * Fight Camp: the same plus Clout for Cannery upgrades and camp milestone flags.
##   * Custom runs (custom rules, reduced game speed, debug options) count for statistics and
##     history but never for records, ladder unlocks, cosmetic unlocks or camp milestones; Clout
##     at 50%.
##   * The Bookie's Table: its own record board, Clout at 50%, no ladder progress.
##   * Dose credit belongs to the profile's OWN ladder: a Dose counts (records, badges, ladder,
##     ach_fully_dosed) only when this profile has it unlocked and the difficulty takes Doses
##     (never Sparring) — a co-op guest on the host's Dose 10 earns the clear, not the Dose.
## Idempotent per (run id, player): crediting the same finished run twice does nothing, so a
## resent co-op "run_end" message or a crash between save and credit cannot duplicate rewards.

const MAX_SAVED_BUILDS := 20


static func ensure_fields(profile: Dictionary) -> void:
	if not profile.has("campaign"):
		profile["campaign"] = {}
	var c: Dictionary = profile["campaign"]
	for k in ["credited_runs", "saved_builds"]:
		if not c.has(k):
			c[k] = []
	if not c.has("boards"):
		c["boards"] = {}
	if not profile.has("ladder"):
		profile["ladder"] = {}
	for v in CampaignCatalog.VARIANTS:
		if not profile["ladder"].has(v):
			profile["ladder"][v] = {"unlocked": 1, "cleared": 0}
		if not profile["ladder"][v].has("open"):
			profile["ladder"][v]["open"] = false
	if not profile.has("camp"):
		profile["camp"] = {"clout": 0, "clout_total": 0, "upgrades": {}, "secrets": [], "flags": {}}
	for k2 in ["upgrades", "flags"]:
		if not profile["camp"].has(k2):
			profile["camp"][k2] = {}
	if not profile.has("unlocks"):
		profile["unlocks"] = {"cosmetics": [], "titles": []}
	if not profile["unlocks"].has("cosmetics"):
		profile["unlocks"]["cosmetics"] = []
	if not profile["unlocks"].has("cosmetic_clout"):
		profile["unlocks"]["cosmetic_clout"] = 0
	if not profile.has("records"):
		profile["records"] = {}
	if not profile["records"].has("runs"):
		profile["records"]["runs"] = {}
	for v2 in CampaignCatalog.VARIANTS + ["bookie"]:
		if not profile["records"]["runs"].has(v2):
			profile["records"]["runs"][v2] = {"attempts": 0, "clears": 0, "best_dose": 0}
	if not profile.has("history"):
		profile["history"] = []


## Highest Dose selectable in a variant (0 = only the base card: The Dosage opens after the first
## Amateur-or-harder clear).
static func max_selectable_dose(profile: Dictionary, variant: String) -> int:
	ensure_fields(profile)
	var l: Dictionary = profile["ladder"][variant]
	return clampi(int(l.get("unlocked", 1)), 1, 10) if bool(l.get("open", false)) else 0


## Highest Dose this profile may play — and be credited for — in `variant` on `difficulty`: 0
## while its Dosage is closed, or when the difficulty takes no Doses (Sparring).
static func dose_cap(catalog: CampaignCatalog, profile: Dictionary, variant: String, difficulty: String) -> int:
	if not bool(catalog.difficulty(difficulty).get("dose_allowed", true)):
		return 0
	return max_selectable_dose(profile, variant)


## A requested Dose clamped to what this profile may start (run creation: campaign menu, hub
## sign-up sheet, "Raise the Dose", a co-op host's own profile).
static func clamp_dose(catalog: CampaignCatalog, profile: Dictionary, variant: String, difficulty: String, dose: int) -> int:
	return clampi(dose, 0, dose_cap(catalog, profile, variant, difficulty))


## The ladder rule (CMP-02): clearing the highest unlocked Dose unlocks the next, up to 10 — only
## on this profile's own open ladder (a Dose above it, e.g. a co-op host's, unlocks nothing).
## The first clear on Amateur or harder opens The Dosage (whatever card it was: Dose 1 only).
## Returns the newly unlocked Dose: 1 = The Dosage just opened, 2..10 = that Dose, 0 = none.
static func apply_ladder_clear(profile: Dictionary, variant: String, dose: int, difficulty_ok: bool) -> int:
	ensure_fields(profile)
	if not difficulty_ok:
		return 0
	var l: Dictionary = profile["ladder"][variant]
	if not bool(l.get("open", false)):
		l["open"] = true
		l["unlocked"] = maxi(1, int(l.get("unlocked", 1)))
		return 1
	if dose <= 0:
		return 0
	var unlocked := clampi(int(l.get("unlocked", 1)), 1, 10)
	if dose > unlocked:
		return 0
	l["cleared"] = maxi(int(l.get("cleared", 0)), dose)
	if dose == unlocked and unlocked < 10:
		l["unlocked"] = unlocked + 1
		return unlocked + 1
	return 0


## Final Clout for a player of a finished run (server-side decision in co-op).
static func clout_for(catalog: CampaignCatalog, state: Dictionary, p: Dictionary) -> int:
	var raw := float(p.get("clout", 0))
	var rr := RunRules.compute(catalog, state, p)
	var mult := float(rr.get("clout_mult", 1.0))
	mult *= float(catalog.rules.get("variant_clout_mult", {}).get(str(state.get("variant", "")), 1.0))
	if str(state.get("mode", "")) == "bookie":
		mult *= float(catalog.rules.get("bookie_clout_mult", 0.5))
	if bool(state.get("custom", false)):
		mult *= float(catalog.rules.get("custom_clout_mult", 0.5))
	return int(round(raw * mult))


static func board_of(state: Dictionary) -> String:
	if str(state.get("mode", "")) == "bookie":
		return "bookie"
	return "camp" if str(state.get("variant", "")) == "fight_camp" else "street"


## Credits a finished run to one player's profile. Returns a report for the results card.
static func finish_run(catalog: CampaignCatalog, state: Dictionary, pid: String, profile: Dictionary) -> Dictionary:
	ensure_fields(profile)
	var rep := {"duplicate": false, "clout": 0, "new_dose": 0, "records": [], "cosmetics": [], "ladder_open": false, "dose_ineligible": false}
	var res: Dictionary = state.get("result", {})
	if res.is_empty():
		rep["error"] = "run is not finished"
		return rep
	var run_key := "%s:%s" % [state.get("run_id", ""), pid]
	var credited: Array = profile["campaign"]["credited_runs"]
	if credited.has(run_key):
		rep["duplicate"] = true
		return rep
	credited.append(run_key)
	while credited.size() > 200:
		credited.pop_front()
	var p := RunState.player(state, pid)
	var victory := bool(res.get("victory", false))
	var variant := str(state.get("variant", "off_the_street"))
	var bookie := str(state.get("mode", "")) == "bookie"
	var custom := bool(state.get("custom", false))
	var dose := int(state.get("dose", 0))
	var diff := catalog.difficulty(str(state.get("difficulty", "amateur")))
	var fighter := str(p.get("fighter", ""))
	# decided before this run touches the ladder: the Dose must already be on THIS profile's ladder
	var dose_ok := dose <= 0 or dose <= dose_cap(catalog, profile, variant, str(state.get("difficulty", "amateur")))
	rep["dose_ineligible"] = not dose_ok
	var runs_key := "bookie" if bookie else variant
	var runs: Dictionary = profile["records"]["runs"][runs_key]
	runs["attempts"] = int(runs.get("attempts", 0)) + 1
	if victory:
		runs["clears"] = int(runs.get("clears", 0)) + 1
	# Clout
	var clout := clout_for(catalog, state, p)
	rep["clout"] = clout
	if variant == "fight_camp" and not bookie:
		profile["camp"]["clout"] = int(profile["camp"].get("clout", 0)) + clout
		profile["camp"]["clout_total"] = int(profile["camp"].get("clout_total", 0)) + clout
	elif bookie and variant == "fight_camp":
		profile["camp"]["clout"] = int(profile["camp"].get("clout", 0)) + clout
		profile["camp"]["clout_total"] = int(profile["camp"].get("clout_total", 0)) + clout
	else:
		profile["unlocks"]["cosmetic_clout"] = int(profile["unlocks"].get("cosmetic_clout", 0)) + clout
	# Fight Camp milestones (hub gates; a custom run proves nothing)
	if variant == "fight_camp" and not bookie and not custom:
		var flags: Dictionary = profile["camp"]["flags"]
		var act := int(res.get("act", 1))
		if act >= 2 or victory:
			flags["beat_act1"] = true
		if act >= 3 or victory:
			flags["beat_act2"] = true
		if victory:
			flags["beat_run"] = true
	# ladder + records (never for custom runs; ladder never from the autobattler)
	var standard := str(diff.get("records", "standard")) != "sparring"
	if victory and not custom and not bookie:
		var nd := apply_ladder_clear(profile, variant, dose, bool(diff.get("dose_allowed", true)))
		if nd == 1:
			rep["ladder_open"] = true
		elif nd > 1:
			rep["new_dose"] = nd
		if dose_ok:
			runs["best_dose"] = maxi(int(runs.get("best_dose", 0)), dose)
	# records are kept per Dose: a Dose this profile has not reached has no board of its own here
	if not custom and dose_ok:
		rep["records"] = _update_records(state, p, profile, victory, standard)
	# cosmetics
	var cos: Array = profile["unlocks"]["cosmetics"]
	var new_cos := []
	if not custom:
		for c in p.get("cosmetics", []):
			new_cos.append(str(c))
		if victory and not bookie:
			new_cos.append("title_%s" % fighter)
			if dose >= 1 and dose_ok:
				new_cos.append("badge_dose_%d" % dose)
			if dose >= 5 and dose_ok:
				new_cos.append("jacket_announcer_alt")
			if dose >= 10 and dose_ok:
				new_cos.append("badge_lethal_dose")
				new_cos.append("chant_lethal_dose")
	for c2 in new_cos:
		if not cos.has(c2):
			cos.append(c2)
			(rep["cosmetics"] as Array).append(c2)
	# saved build (AI Lab scenarios, mirror elite)
	var builds: Array = profile["campaign"]["saved_builds"]
	builds.push_front({"run_id": str(state.get("run_id", "")), "fighter": fighter, "techniques": (p.get("techniques", []) as Array).duplicate(),
		"supplements": (p.get("supplements", []) as Array).duplicate(true), "dose": dose, "victory": victory, "variant": variant})
	while builds.size() > MAX_SAVED_BUILDS:
		builds.pop_back()
	# history
	var entry := {"kind": "campaign", "run_id": str(state.get("run_id", "")), "variant": variant, "mode": str(state.get("mode", "")),
		"fighter": fighter, "victory": victory, "act": int(res.get("act", 1)), "dose": dose, "difficulty": str(state.get("difficulty", "")),
		"custom": custom, "time": RunStore.stable_float(snappedf(float(res.get("elapsed", 0.0)), 0.01)), "clout": clout, "party": (state.get("players", []) as Array).size(),
		"seed": str(state.get("seed_text", "")), "kos": int(p.get("stats", {}).get("kos", 0))}
	var hist: Array = profile["history"]
	hist.push_front(entry)
	while hist.size() > 60:
		hist.pop_back()
	rep["history_entry"] = entry
	# platform achievements earned by this run (granted by the caller for the local profile)
	var ach := []
	if victory and not custom and not bookie:
		ach.append("ach_off_the_street" if variant == "off_the_street" else "ach_made_camp")
		ach.append("ach_order_in_court")     # the title fight is Commissioner Snappington
		if dose >= 10 and dose_ok:
			ach.append("ach_fully_dosed")
	rep["achievements"] = ach
	return rep


## Unlocks the achievements a credited run earned — only for the active local profile (tests
## and remote party members pass other profile dictionaries and get nothing unlocked here).
static func grant_achievements(rep: Dictionary, profile: Dictionary) -> void:
	if not is_same(profile, Profiles.current):
		return
	for a in rep.get("achievements", []):
		Platform.unlock_achievement(str(a))


## Records per fighter x board x difficulty x Dose: fastest clear, fewest knockdowns suffered,
## highest Scrip hoard, no-hit bosses. Returns the list of broken records.
static func _update_records(state: Dictionary, p: Dictionary, profile: Dictionary, victory: bool, standard: bool) -> Array:
	var broken := []
	var board := board_of(state)
	var party := (state.get("players", []) as Array).size()
	var key := "%s|%s|%s|dose%d|p%d" % [board, p.get("fighter", ""), state.get("difficulty", ""), int(state.get("dose", 0)), party]
	var boards: Dictionary = profile["campaign"]["boards"]
	var rec: Dictionary = boards.get(key, {"fastest_clear": 0.0, "fewest_knockdowns": -1, "best_scrip": 0, "no_hit_bosses": [], "standard": standard})
	var st: Dictionary = p.get("stats", {})
	# profile floats must survive the JSON round trip exactly (see RunStore.json_stable)
	var t := RunStore.stable_float(snappedf(float(state.get("result", {}).get("elapsed", 0.0)), 0.01))
	if victory:
		if float(rec["fastest_clear"]) <= 0.0 or (t > 0.0 and t < float(rec["fastest_clear"])):
			rec["fastest_clear"] = t
			broken.append("fastest_clear")
		var kd := int(st.get("knockdowns_taken", 0))
		if int(rec["fewest_knockdowns"]) < 0 or kd < int(rec["fewest_knockdowns"]):
			rec["fewest_knockdowns"] = kd
			broken.append("fewest_knockdowns")
	if int(p.get("scrip", 0)) > int(rec["best_scrip"]):
		rec["best_scrip"] = int(p.get("scrip", 0))
		broken.append("best_scrip")
	for b in st.get("boss_no_hit", []):
		if not (rec["no_hit_bosses"] as Array).has(b):
			(rec["no_hit_bosses"] as Array).append(b)
			broken.append("no_hit:%s" % b)
	boards[key] = rec
	return broken
