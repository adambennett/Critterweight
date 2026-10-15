class_name HubDemo
extends RefCounted
## Development/QA presets for The Cannery (used by `--hub --hub-demo <list>` and the evidence
## captures). They WRITE INTO THE ACTIVE PROFILE, so use them with `--user-root <scratch dir>`.
##   clout        +2000 Clout
##   upgraded     every Cannery upgrade at level 1 (12+ fixes the lights, 24 swaps the banner)
##   half         the first 12 upgrades at level 1 (lights fixed, banner not yet)
##   evening      a Fight Camp run that beat a boss and lost in Act 2 (evening light)
##   night        a Fight Camp title run (night)
##   loss         an Act 1 loss to Bilge (morning)
##   secrets      every secret found (roof open, panel off, sign lit, pier open, pet)
##   toured       every public space discovered (Fast walk unlocked)
## --hub-board <kind[:arg]> opens a board after a second (talk:granny, station:gym_floor, run, spar,
## lockers, records, booth, map, pause, lessons, shop, rest) or starts an activity (activity:drill,
## activity:crates, activity:bag:heavy). --hub-pos x,y,z[,yaw] places the fighter (HubScene).

const UPGRADES := HubUpgradeProps.ALL_UPGRADES


static func apply(state: HubState, presets: String) -> void:
	for raw in presets.split(",", false):
		var p := raw.strip_edges()
		match p:
			"clout":
				state.add_clout(2000, "demo")
			"upgraded", "half":
				var n := UPGRADES.size() if p == "upgraded" else 12
				for i in n:
					state.camp()["upgrades"][UPGRADES[i]] = maxi(1, state.upgrade_level(UPGRADES[i]))
			"evening":
				_run(state, false, 2)
			"night":
				_run(state, true, 3)
			"loss":
				_run(state, false, 1)
			"secrets":
				for id in HubState.SECRETS:
					state.find_secret(str(id))
				for part in HubState.ELEVATOR_PARTS:
					state.give_part(str(part))
				for c in ["hub_gold_tooth", "hub_trash_lid", "hub_replica_belt", "hub_pack_vintage_bellows", "hub_frame_sign_fixer", "hub_juice_sizzle", "hub_pet_blister", "hub_rooftop_neon"]:
					state.unlock_cosmetic(c)
				state.set_flag("scrapling_woken", true)
				state.equip("pet", "hub_pet_blister")
			"toured":
				for s in HubLayout.TOUR:
					state.discover(str(s))
	state.dirty = true


static func _run(state: HubState, victory: bool, act: int) -> void:
	var fighter := state.loadout_fighter() if state.loadout_fighter() != "" else "f_stoke"
	(state.profile["history"] as Array).push_front({"kind": "campaign", "run_id": "demo_%d" % Time.get_ticks_msec(), "variant": "fight_camp", "mode": "campaign",
		"fighter": fighter, "victory": victory, "act": act, "dose": 0, "difficulty": "amateur", "custom": false, "time": 1500.0, "clout": 0,
		"party": 1, "seed": "", "kos": 3 + act})


static func open_board(scene: HubScene, spec: String) -> void:
	var parts := spec.split(":", false)
	if parts.is_empty():
		return
	var kind := parts[0]
	var p := {}
	match kind:
		"activity":
			# --hub-board activity:drill | activity:crates | activity:bag:heavy  (starts it, no board)
			scene.mode.start_activity(parts[1] if parts.size() > 1 else "drill", parts[2] if parts.size() > 2 else "")
			return
		"talk":
			p["npc"] = parts[1] if parts.size() > 1 else "granny"
		"station":
			p["station"] = parts[1] if parts.size() > 1 else "gym_floor"
		"spar":
			p["opponent"] = "kid_lamprey"
	scene.open_board(kind, p)
