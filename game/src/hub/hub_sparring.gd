class_name HubSparring
extends RefCounted
## Ring Sparring (HUB.md §3) and the 1973 tape (secret #5): real matches launched from the hub,
## returning to the Cannery when they end (a spar through MatchFlow, so "Restart fight" restarts
## the spar; the tape offers no restart).
##   launch(scene, {opponent, tier, format, low_gravity, hazards, arena}): a 1-round spar in the
##     practice cage (a 6 m mini-Gullet) vs Kid Lamprey (npc_kid_lamprey when the creature exists,
##     else a roster stand-in named Kid Lamprey) or any fighter at any bot tier; format "practice"
##     is PracticeMode (no KO, HUD telemetry). No stakes: matches are not recorded (no_record);
##     the documented one-time rewards (first win vs Kid at Contender: 25 Clout, a per-fighter
##     "beat a Headliner" badge) are paid on return.
##   play_tape(scene): the Commissioner's 1973 title fight, a 40 s AI-vs-AI replay vs a silhouette.

const KID := "npc_kid_lamprey"
const OVERLAY := "res://src/hub/ui/hub_spar_overlay.gd"
const TAPE_OVERLAY := "res://src/hub/ui/hub_tape_overlay.gd"


## The real Kid Lamprey once his kit parses cleanly (the campaign's usability check: installed AND a
## valid CreatureDef with no problems); until then a roster stand-in named Kid Lamprey.
static func kid_ready() -> bool:
	if Content.creature(KID) == null:
		return false
	return not CampaignCatalog.shared().resolver.usable_entry(KID).is_empty()


static func kid_creature(me: String) -> String:
	if kid_ready():
		return KID
	for fallback in ["f_gusto", "f_jitters", "f_stoke"]:
		if fallback != me and Content.creature(fallback) != null:
			return fallback
	return me


static func opponent_creature(opp: String, me: String) -> String:
	if opp == "kid_lamprey" or opp == "":
		return kid_creature(me)
	return opp if Content.creature(opp) != null else kid_creature(me)


static func opponent_name(opp: String) -> String:
	if opp == "kid_lamprey" or opp == "":
		return "Kid Lamprey"
	return str(Content.get_entry("creatures", opp).get("name", opp))


static func arena_for(choices: Dictionary) -> ArenaDef:
	var a: ArenaDef = null
	if str(choices.get("arena", "cage")) == "rooftop":
		for id in Content.ids("arenas"):
			if str(id).contains("rooftop"):
				a = Content.arena(str(id))
				break
	if a == null:
		a = Tutorial.practice_cage()    # the shared content arena "practice_cage" (never mutated here)
	if bool(choices.get("hazards", false)):
		var d := a.to_dict()
		var hz: Array = d.get("hazards", [])
		hz.append({"type": "puddle", "pos": [1.3, 0.0, 0.0], "radius": 0.9, "params": {}})
		hz.append({"type": "fire_grate", "pos": [-1.3, 0.0, 0.4], "radius": 0.7, "params": {}})
		d["hazards"] = hz
		a = ArenaDef.from_dict(d, "hub")
	return a


static func config(me: String, player_name: String, choices: Dictionary) -> Dictionary:
	var opp := str(choices.get("opponent", "kid_lamprey"))
	if opp == "random":
		var opponents: Array[String] = ["kid_lamprey"]
		opponents.append_array(Content.playable_creatures())
		opp = FighterSelection.resolve("random", opponents)
	var tier := str(choices.get("tier", "journeyman"))
	var practice := str(choices.get("format", "spar")) == "practice"
	var rules := {"id": "hub_spar", "name": "Ring Sparring", "mode": "practice" if practice else "standard", "rounds": 1,
		"round_time": 0.0 if practice else 90.0, "intro_time": 1.5, "lives": 1}
	if practice:
		# the practice dummy fights back at the chosen tier (read by PracticeMode at setup, so a
		# restarted practice spar keeps it)
		rules["dummy_behavior"] = "bot"
		rules["dummy_tier"] = BotTiers.brain_tier(tier)
	if bool(choices.get("low_gravity", false)):
		rules["gravity_mult"] = 0.5
	# where you walk back in: the rooftop ring's practice returns to the roof, the cage to the Main Floor
	var spot := str(choices.get("return_spot", "roof" if str(choices.get("arena", "cage")) == "rooftop" else "main_floor"))
	return {"arena": arena_for(choices), "rules": rules, "seed": int(Time.get_ticks_msec() % 100000) + 3, "no_record": true,
		"audio_context": "versus", "music": "combat_a", "overlay_script": OVERLAY,
		"hub_spar": {"opponent": opp, "tier": tier, "format": "practice" if practice else "spar", "fighter": me, "spot": spot},
		"fighters": [{"creature": me, "team": 0, "kind": "player", "name": player_name},
			{"creature": opponent_creature(opp, me), "team": 1, "kind": "bot", "difficulty": BotTiers.brain_tier(tier), "name": opponent_name(opp)}]}


static func launch(scene: Node, choices: Dictionary) -> MatchScene:
	var me: String = scene.call("player").creature.id
	var st: HubState = scene.get("state")
	var cfg := config(me, Profiles.player_name(st.profile), choices)
	Profiles.save()
	var spar: Dictionary = cfg["hub_spar"]
	# through MatchFlow: the pause menu's "Restart fight" restarts THIS spar (not whatever match was
	# launched before it, a lesson for instance) and the restart walks back into the Cannery too
	return MatchFlow.launch(cfg, func(result: Dictionary) -> void: finished(spar, result))


## Match over (or left early from the overlay): pay the one-time rewards and walk back in where the
## spar started (the cage: the Main Floor; the rooftop ring: the roof).
static func finished(spar: Dictionary, result: Dictionary) -> void:
	var won := int(result.get("winner_team", -2)) == 0 and not bool(result.get("left", false))
	var st := HubState.new(Profiles.current)
	var rec := st.spar_record(str(spar.get("opponent", "")), str(spar.get("tier", "")), won, str(spar.get("fighter", "")))
	Profiles.save()
	Cannery.enter({"spot": str(spar.get("spot", "main_floor")), "from": "spar", "spar": {"won": won, "opponent": str(spar.get("opponent", "")), "tier": str(spar.get("tier", "")),
		"clout": int(rec["clout"]), "badge": str(rec["badge"])}})


static func play_tape(_scene: Node) -> MatchScene:
	var champ := "boss_snappington" if Content.creature("boss_snappington") != null else "f_dredge"
	var shadow := "f_dozer" if Content.creature("f_dozer") != null else "dev_biped"
	var cfg := {"arena": "the_gullet", "seed": 1973, "no_record": true, "spectate": true, "music": "title_night", "audio_context": "versus",
		"overlay_script": TAPE_OVERLAY,
		"rules": {"id": "tape_1973", "name": "1973 Title Fight", "mode": "standard", "rounds": 1, "round_time": 40.0, "intro_time": 1.0, "lives": 1},
		"fighters": [{"creature": champ, "team": 0, "kind": "bot", "difficulty": BotTiers.brain_tier("headliner"), "name": "Snappington ('73)"},
			{"creature": shadow, "team": 1, "kind": "bot", "difficulty": BotTiers.brain_tier("headliner"), "name": "???"}]}
	Profiles.save()
	var ms := App.start_match(cfg, func(_r: Dictionary) -> void: Cannery.enter({"spot": "booth", "from": "tape"}))
	# a tape is watched, not fought: no "Restart fight" (and never into an earlier, unrelated match)
	MatchFlow.last_config = {}
	if ms:
		ms.camera.mode = FightCamera.Mode.SPECTATE
	return ms
