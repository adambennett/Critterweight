class_name CareerFight
extends RefCounted
## The match config of a booked career bout (design contract §5.2, D4, D6, D9). Headless-ready
## like EncounterBuilder.build_match: ArenaDef, CreatureDefs, the mode and every bot source are
## pre-resolved, so the same config runs presented (App.start_match) or headless
## (HeadlessFightRunner) and plays out the same for the same seed.
##   rules     the "Cage Rules" preset (standard 1v1, 10-point scoring, referee) — or, while that
##             preset is not installed, the Standard Duel + {"scoring": "ten_point", "referee": true}
##             — with rounds 3 (titles 5), the offer's round_time (99 s) and sudden_death false;
##             `combat` is the preset's combat style, written out ("moves" unless it says Classic)
##   seed      RunRng.derive(career seed, "fight/<offer id>"): a bout re-fought after a crash is the
##             same bout (same opponent, bot, arena and seed)
##   fighters  team 0 = the career fighter (kind "player", or a bot for unattended/test runs),
##             team 1 = the opponent with a BotBrain of the offer's bot tier; both built by
##             CareerBuild (same stat -> mod mapping). The career fighter's entry carries its
##             equipped `loadout` and its creature has the drilled styles composed in
##             (CareerMoves; the moves are normalized against the installed creature first). The
##             opponent fights with its creature's default loadout.
##   flags     no_record: true (career results reach the profile only through its own history),
##             context {career: true, variant, career_id, fight_id, title}

const PLAYER_TEAM := 0
const OPPONENT_TEAM := 1
const INTRO_TIME := 2.2         ## MatchMode.INTRO_TIME (rules may set intro_time)
const ROUND_END_TIME := 3.0     ## MatchMode.ROUND_END_TIME
const DECISION_TIME := 6.0      ## the bout-end ceremony under 10-point scoring / the referee (§3.5)
## Standard Duel (content/core/rules/duel.json) for content doubles without rules presets.
const DUEL := {"id": "duel", "name": "Standard Duel", "mode": "standard", "format": "duel", "teams": 2, "players": [2, 2],
	"rounds": 3, "round_time": 99, "win": "ko", "lives": 1, "sudden_death": true, "combat": "moves", "version": 1}


## The preset career bouts start from (a copy).
static func base_rules(catalog: CampaignCatalog, rules: Dictionary) -> Dictionary:
	var content = catalog.content if catalog else null
	var r := {}
	if content != null and content.has_method("get_entry"):
		r = content.get_entry("rules", str(rules.get("rules_preset", "cage_rules")))
		if r.is_empty():
			r = content.get_entry("rules", "duel")
			if not r.is_empty():
				r = r.duplicate(true)
				r["scoring"] = "ten_point"
				r["referee"] = true
	if r.is_empty():
		r = DUEL.duplicate(true)
		r["scoring"] = "ten_point"
		r["referee"] = true
	return r.duplicate(true)


## The bout's rules: the preset with the offer's rounds and round time, no sudden death (career
## bouts can be drawn, as in Cage Rules), and the preset's combat style (Movesets unless it names
## Classic; MOVESET_COMBAT.md §1: a missing key means Movesets).
static func bout_rules(catalog: CampaignCatalog, rules: Dictionary, offer: Dictionary) -> Dictionary:
	var r := base_rules(catalog, rules)
	r["rounds"] = int(offer.get("rounds", rules.get("rounds", 3)))
	r["round_time"] = float(offer.get("round_time", rules.get("round_time", 99.0)))
	r["sudden_death"] = false
	r["combat"] = combat_style(r)
	return r


## "moves" or "classic" for a rules dictionary (a missing or unknown value is Movesets).
static func combat_style(r: Dictionary) -> String:
	return "classic" if str(r.get("combat", "moves")) == "classic" else "moves"


static func fight_seed(st: Dictionary, offer: Dictionary) -> int:
	return RunRng.derive(int(st.get("seed", 1)), "fight/%s" % str(offer.get("id", ""))) & 0x7FFFFFFF


## A safe headless time cap for the bout (design contract D6):
## rounds x (round_time + intro + round end) + decision ceremony + 30 s.
static func max_seconds(offer: Dictionary) -> float:
	var rounds := int(offer.get("rounds", 3))
	return rounds * (float(offer.get("round_time", 99.0)) + INTRO_TIME + ROUND_END_TIME) + DECISION_TIME + 30.0


## "3 × 1:39" (rounds × round length).
static func rounds_label(offer: Dictionary) -> String:
	var t := int(round(float(offer.get("round_time", 99.0))))
	return "%d × %d:%02d" % [int(offer.get("rounds", 3)), int(t / 60.0), t % 60]


## The ring name with the nickname: Rivet "Low Tide" Gravelgut (nickname-less: Rivet Gravelgut).
static func billed_name(name_: String, nick: String) -> String:
	if nick == "":
		return name_
	var parts := name_.split(" ", false, 1)
	if parts.size() == 2:
		return "%s \"%s\" %s" % [parts[0], nick, parts[1]]
	return "%s \"%s\"" % [name_, nick]


## Builds the booked bout. opts: {player_kind: "player" (default) | "bot", player_bot_tier
## (bot player; default "contender"), player_source: InputSource (replaces the player's input)}.
## Returns {config, errors: PackedStringArray, warnings: [], seed, max_seconds}.
static func build(catalog: CampaignCatalog, rules: Dictionary, st: Dictionary, opts := {}) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := []
	var out := {"config": {}, "errors": errors, "warnings": warnings, "seed": 0, "max_seconds": 0.0}
	var booked: Dictionary = st.get("booked", {})
	if booked.is_empty():
		errors.append("no fight is booked")
		return out
	var offer: Dictionary = booked.get("offer", {})
	var opp: Dictionary = offer.get("opp", {})
	var seed_value := fight_seed(st, offer)
	out["seed"] = seed_value
	out["max_seconds"] = max_seconds(offer)
	# D9: a fight whose fighters are gone is never built from a stand-in or a fallback
	if not CareerState.creature_ok(catalog, str(st.get("fighter", ""))):
		errors.append("the career fighter '%s' is not installed" % st.get("fighter", ""))
	if not CareerState.creature_ok(catalog, str(opp.get("fighter", ""))):
		errors.append("the opponent's fighter '%s' is not installed" % opp.get("fighter", ""))
	if not errors.is_empty():
		return out
	# arena: the offer's (a missing one falls back to a plain cage, reported)
	var arena: ArenaDef = null
	var content = catalog.content
	if content != null and content.has_method("arena"):
		arena = content.arena(str(offer.get("arena", "")))
		if arena == null:
			warnings.append("arena '%s' not installed; using %s" % [offer.get("arena", ""), catalog.rules.get("fallback_arena", "the_gullet")])
			arena = content.arena(str(catalog.rules.get("fallback_arena", "the_gullet")))
	if arena == null:
		arena = ArenaDef.from_dict({"id": "career_fallback", "name": "The Gullet", "base": "octagon", "radius": 5.0})
	# the career fighter's moves against its installed kit: the drilled styles are composed into the
	# creature (before the stats), the equipped loadout travels with the fighter entry
	var kit := CareerMoves.creature(catalog, str(st.get("fighter", "")))
	var moves := CareerMoves.normalize(kit, st.get("moves", {}))
	var me := CareerBuild.compose(catalog, rules, str(st.get("fighter", "")), st.get("stats", {}), st.get("injury", {}), "career_player",
		CareerMoves.drill_effects(kit, moves["drilled"]))
	if me["creature"] == null:
		errors.append_array(me["errors"])
		return out
	warnings.append_array(me["warnings"])
	var them := CareerBuild.compose(catalog, rules, str(opp.get("fighter", "")), opp.get("stats", {}), {}, "career_opponent")
	if them["creature"] == null:
		errors.append_array(them["errors"])
		return out
	warnings.append_array(them["warnings"])
	var me_c: CreatureDef = me["creature"]
	var them_c: CreatureDef = them["creature"]
	var player := {"creature": me_c, "team": PLAYER_TEAM, "name": str(st.get("name", "You")), "mods": (me["mods"] as Dictionary).duplicate(),
		"loadout": (moves["equipped"] as Array).duplicate()}
	var pk := str(opts.get("player_kind", "player"))
	if opts.has("player_source"):
		player["kind"] = "campaign_bot" if pk == "bot" else "net"
		player["source"] = opts["player_source"]
	elif pk == "bot":
		player["kind"] = "campaign_bot"
		player["source"] = EncounterBuilder.make_bot(catalog, str(opts.get("player_bot_tier", "contender")), seed_value + 1, me_c)
	else:
		player["kind"] = "player"
	var tier := str(opp.get("bot_tier", "journeyman"))
	var enemy := {"creature": them_c, "team": OPPONENT_TEAM, "name": str(opp.get("name", them_c.display_name)),
		"mods": (them["mods"] as Dictionary).duplicate(), "kind": "npc",
		"source": EncounterBuilder.make_bot(catalog, tier, seed_value + 13, them_c)}
	var r := bout_rules(catalog, rules, offer)
	var mode := ModeRegistry.create(str(r.get("mode", "standard")))
	out["config"] = {"arena": arena, "rules": r, "seed": seed_value, "mode": mode, "fighters": [player, enemy],
		"no_record": true, "custom": false,
		"context": {"career": true, "variant": str(offer.get("arena_variant", "")), "career_id": str(st.get("career_id", "")),
			"fight_id": str(offer.get("id", "")), "title": bool(offer.get("title", false))}}
	# what the booth knows about the bout (commentary only; never gameplay)
	var rec: Dictionary = st.get("record", {})
	(out["config"]["context"] as Dictionary)["booth"] = {"title": bool(offer.get("title", false)),
		"debut": int(rec.get("w", 0)) + int(rec.get("l", 0)) + int(rec.get("d", 0)) == 0,
		"champion": bool(st.get("champion", false)), "streak": int(st.get("streak", 0)), "tier": int(offer.get("tier", 0))}
	return out
