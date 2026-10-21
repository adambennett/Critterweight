extends TestCase
## v0.9.18 Movesets on the network (protocol 7, docs/design/MOVESET_COMBAT.md §9): loadout requests
## are cleaned, roster entries carry the combat style and loadout, snapshots carry charges per
## cooldown slot, and an online client's mirror fighter shows the server's loadout.


func test_loadout_requests_are_cleaned() -> void:
	check_eq(NetProtocol.clean_loadout(["ember_jab", "flamethrower", "steam_vent", "stoke_the_fire", "extra"]),
		["ember_jab", "flamethrower", "steam_vent", "stoke_the_fire"], "at most four moves")
	check_eq(NetProtocol.clean_loadout(["ok_id", "Bad Id!", "ok_id", 42]), ["ok_id", "42"], "plain ids only, no duplicates")
	check_eq(NetProtocol.clean_loadout("nope"), [], "not a list")


func test_roster_carries_combat_style_and_loadout() -> void:
	var w := NetWriter.new(NetProtocol.S_ROSTER)
	NetSnapshot.encode_roster(w, [{"slot": 0, "gen": 1, "creature": "f_stoke", "scale": 1.0, "team": 0, "name": "STOKE", "kind": "net",
		"despawned": false, "tags": [], "combat": "moves", "loadout": ["ember_jab", "flamethrower", "steam_vent", "stoke_the_fire"]},
		{"slot": 1, "gen": 1, "creature": "f_dredge", "scale": 1.0, "team": 1, "name": "DREDGE", "kind": "bot",
		"despawned": false, "tags": [], "combat": "classic", "loadout": []}])
	var r := NetReader.new(w.data())
	r.u8()
	var out := NetSnapshot.decode_roster(r)
	check(r.ok and out.size() == 2, "decodes")
	check_eq(str(out[0]["combat"]), "moves", "style")
	check_eq(out[0]["loadout"], ["ember_jab", "flamethrower", "steam_vent", "stoke_the_fire"], "loadout")
	check_eq(str(out[1]["combat"]), "classic", "Classic fighters say so")


func test_snapshot_carries_charges_and_the_mirror_shows_the_loadout() -> void:
	var sim := make_sim("", {"rounds": 1, "round_time": 0, "combat": "moves"}, [{"creature": "f_stoke", "team": 0}, {"creature": "f_dredge", "team": 1}])
	await step_sim(sim, 0.3)
	var f := sim.fighters[0]
	check_eq(f.loadout, ["ember_jab", "flamethrower", "steam_vent", "stoke_the_fire"], "Stoke's default loadout")
	f.charges_left["m3"] = 0
	f.cooldown_left["m3"] = 4.5
	var gens := PackedByteArray()
	gens.resize(sim.fighters.size())
	gens.fill(1)
	var r := NetReader.new(NetSnapshot.encode_body(sim, gens))
	var snap := NetSnapshot.decode_body(r)
	check(not snap.is_empty(), "snapshot decodes")
	var fd: Dictionary = (snap["fighters"] as Array)[0]
	check(is_equal_approx(float((fd["cooldowns"] as Dictionary).get("m3", 0.0)), 4.5), "the cooldown of slot m3 travels")
	check_eq(int((fd["charges"] as Dictionary).get("m3", -1)), 0, "and its charges")
	check_eq(int((fd["charges"] as Dictionary).get("m2", -1)), 1, "a ready slot has its charge")
