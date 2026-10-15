class_name Cannery
extends RefCounted
## Entry points for THE CANNERY, the Fight Camp hub (docs/HUB_SYSTEMS.md §1). (Named Cannery, not
## Hub: the campaign's co-op loopback transport owns an inner class called Hub.)
##   Cannery.enter({spot, fighter, from})   leave whatever is running and walk into the hub
##                                      (App screen "hub" does the same: App.goto("hub", params))
##   Cannery.build_sim(parent, state, ...)  the hub's MatchSim (used by HubScene and the headless tests)
## params: spot = HubLayout space id to arrive in (default: where you left off), fighter = creature
## id to walk with (default: the Locker's choice, else the first roster fighter), from = "run" |
## "spar" | "tutorial" | "menu" (only changes the welcome line), result = a sparring result.

const RULES := {"id": "hub", "name": "The Cannery", "mode": "hub", "round_time": 0.0, "rounds": 1, "intro_time": 0.0}


static func enter(params := {}) -> void:
	_restore_speed()
	App.clear_screens()
	var scene := HubScene.new()
	App.set_scene(scene)
	scene.start(params)


## Leaves the hub for the main menu (progress is saved first).
static func leave() -> void:
	Profiles.save()
	App.set_scene(null)
	if App.has_screen("main_menu"):
		App.goto("main_menu")
	else:
		App.quit()


## A hub QA/bench command-line value (after "--"): --hub-pos, --hub-bench, --bench-seconds, ...
static func cli(flag: String, fallback := "") -> String:
	var a := OS.get_cmdline_user_args()
	var i := a.find(flag)
	return a[i + 1] if i >= 0 and i + 1 < a.size() else fallback


## Accessibility game speed never applies in the hub (it is a social space, not a fight).
static func _restore_speed() -> void:
	Engine.time_scale = 1.0


## The fighter the player walks with: explicit > Locker loadout > last Fight Camp run > the default
## roster fighter. Always a ROSTER fighter ("f_..."; the dev biped only when no roster is installed),
## preferring kits the campaign can use (parse cleanly) over ones still being authored.
static func pick_fighter(state: HubState, wanted := "") -> String:
	for cand in [wanted, state.loadout_fighter(), str(state.last_run().get("fighter", ""))]:
		var cid := str(cand)
		if cid.begins_with("f_") and Content.creature(cid) != null and Content.get_entry("creatures", cid).size() > 0:
			return cid
	var roster := Content.playable_creatures().filter(func(c): return str(c).begins_with("f_"))
	var usable := roster.filter(func(c): return not CampaignCatalog.shared().resolver.usable_entry(str(c)).is_empty())
	for pool in [usable, roster]:
		if (pool as Array).has(Tutorial.DEFAULT_FIGHTER):
			return Tutorial.DEFAULT_FIGHTER
		if not (pool as Array).is_empty():
			return str((pool as Array)[0])
	var any := Content.playable_creatures()
	return str(any[0]) if not any.is_empty() else "dev_biped"


static func build_sim(parent: Node, state: HubState, fighter_id: String, spot := "main_floor", source: InputSource = null, seed_value := 7) -> MatchSim:
	var sim := MatchSim.new()
	sim.running = false
	parent.add_child(sim)
	var c := Content.creature(fighter_id)
	if c == null:
		c = Content.creature(pick_fighter(state))
	var mode := HubMode.new(state, spot)
	sim.setup({"arena": HubArenaDef.make(), "rules": RULES.duplicate(true), "seed": seed_value, "mode": mode,
		"fighters": [{"creature": c, "team": 0, "source": source, "name": str(state.profile.get("name", "Rookie")), "kind": "player"}]})
	return sim
