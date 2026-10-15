extends TestCase
## ARN-04: the validator catches every rule (budget, counts, clear floor, bounds, spawn safety,
## team clusters, pits, required mode markers) and points at the offending item.


func _base(base := "gullet", modes := ["duel"]) -> Dictionary:
	var d := Content.get_entry("arenas", ArenaCatalog.base_arena_id(base)).duplicate(true)
	d.erase("base_def")
	d.erase("_package")
	d.erase("_file")
	d["id"] = "user:test"
	d["modes"] = modes
	d["props"] = []
	return d


func _codes(d: Dictionary) -> Array:
	var res := ArenaValidator.validate(ArenaDef.from_dict(d))
	var out := []
	for e in res["errors"]:
		out.append(str(e["code"]))
	return out


func _issue(d: Dictionary, code: String) -> Dictionary:
	for e in ArenaValidator.validate(ArenaDef.from_dict(d))["errors"]:
		if str(e["code"]) == code:
			return e
	return {}


func test_clean_base_layouts_pass() -> void:
	for b in ["gullet", "drydock", "crusher", "rooftop"]:
		check(_codes(_base(b)).is_empty(), "%s base layout is valid: %s" % [b, str(_codes(_base(b)))])


func test_over_budget() -> void:
	var d := _base()
	for k in 26:   # 26 x fence (4) = 104 points, placed in a far ring so nothing else trips
		var a := TAU * k / 26.0
		d["props"].append({"type": "prop_bollard", "pos": [cos(a) * 4.6, 0, sin(a) * 4.6]})
	check(_codes(d).has("too_many_props"), "more than 24 props")
	var d2 := _base()
	for k2 in 8:
		d2["props"].append({"type": "prop_drain_pair", "pos": [-4 + k2, 0, 4.2], "pos2": [-4 + k2, 0, -4.2]})
	for k3 in 16:
		d2["props"].append({"type": "prop_fence_segment", "pos": [0, 0, 0], "yaw": 0})
	var c2 := _codes(d2)
	check(c2.has("budget"), "8 drain pairs (40) + 16 fences (64) = 104 > 100: %s" % str(c2))
	check(not c2.has("too_many_props"), "24 props is still within the count cap")
	var res := ArenaValidator.validate(ArenaDef.from_dict(d2))
	check(int(res["stats"]["budget"]) > 100, "budget stat reported")


func test_hazard_and_pickup_caps() -> void:
	var d := _base()
	for k in 9:
		var a := TAU * k / 9.0
		d["props"].append({"type": "prop_brine_barrel", "pos": [cos(a) * 4.8, 0, sin(a) * 4.8]})
	check(_codes(d).has("too_many_hazards"), "9 destructible-elemental hazards > 8")
	var d2 := _base()
	for k2 in 6:
		var a2 := TAU * k2 / 6.0
		d2["props"].append({"type": "prop_spring_pad", "pos": [cos(a2) * 4.6, 0, sin(a2) * 4.6]})
	check(not _codes(d2).has("too_many_hazards"), "spring pads are not in the timed/elemental cap")
	var d3 := _base()
	for k3 in 3:
		d3["props"].append({"type": "prop_chum_bucket", "pos": [-1 + k3, 0, 4.5]})
	check(_codes(d3).has("pickup_limit"), "max 2 chum buckets")
	var d4 := _base()
	for k4 in 5:
		d4["props"].append({"type": "prop_hype_can" if k4 % 2 == 0 else "prop_chum_bucket", "pos": [-2 + k4, 0, 4.6]})
	check(_codes(d4).has("too_many_pickups"), "max 4 pickups")


func test_blocked_spawn_points_at_the_spawn() -> void:
	var d := _base()
	var sp: Array = d["markers"]["spawn"][0]["pos"]
	d["props"].append({"type": "prop_heavy_crate", "pos": [float(sp[0]) + 1.2, 0, float(sp[2])]})
	var e := _issue(d, "spawn_blocked")
	check(not e.is_empty(), "crate next to a spawn blocks it")
	check_eq(str(e.get("ref", {}).get("kind", "")), "marker", "issue references the spawn marker")
	check_eq(str(e.get("ref", {}).get("marker", "")), "spawn", "spawn list")
	check_eq(int(e.get("ref", {}).get("index", -1)), 0, "first spawn")
	var d2 := _base("drydock")
	var mk: Array = d2["markers"]["spawn"]
	mk[0]["pos"] = [-3.0, 0.0, 0.3]   # in the tidal gutter
	check(_codes(d2).has("spawn_blocked"), "spawn inside the gutter's 1.5 m clearance")


func test_spawn_near_pit_or_open_edge() -> void:
	var d := _base("rooftop")
	d["markers"]["spawn"][0]["pos"] = [0.0, 0.0, 4.6]   # 1.4 m from the north edge
	check(_codes(d).has("spawn_edge"), "spawn within 2 m of an open edge")
	var d2 := _base("rooftop")
	var sp: Array = d2["markers"]["spawn"][0]["pos"]
	d2["props"].append({"type": "prop_pit", "pos": [float(sp[0]), 0, float(sp[2]) + 2.6]})
	var c := _codes(d2)
	check(c.has("spawn_pit"), "spawn within 2 m of a pit: %s" % str(c))
	var d3 := _base("gullet")
	d3["props"].append({"type": "prop_pit", "pos": [0, 0, 0]})
	var c3 := _codes(d3)
	check(c3.has("pit_not_allowed"), "pits need an open-edge base or the allow_pits flag")
	check(c3.has("pit_no_respawn"), "and a respawn marker within 4 m")
	d3["flags"] = {"allow_pits": true}
	d3["markers"]["respawn"] = [{"pos": [0, 0, 2.6], "yaw": 0}]
	var c4 := _codes(d3)
	check(not c4.has("pit_not_allowed") and not c4.has("pit_no_respawn"), "flag + respawn marker make the pit legal: %s" % str(c4))


func test_missing_mode_markers() -> void:
	var d := _base("crusher", ["spotlight_hog", "chumball", "absolute_unit", "chum_rush"])
	var res := ArenaValidator.validate(ArenaDef.from_dict(d))
	var msgs := []
	for e in res["errors"]:
		if str(e["code"]) == "missing_markers":
			msgs.append(str(e["ref"].get("mode", "")))
	check(not msgs.has("spotlight_hog"), "crusher ships 5 spotlight anchors")
	check(msgs.has("chumball"), "chumball needs goals + ball spawn")
	check(msgs.has("absolute_unit"), "absolute unit needs a unit spawn")
	check(msgs.has("chum_rush"), "chum rush needs wave gates")
	var d2 := _base("gullet", ["ffa"])
	(d2["markers"]["spawn"] as Array).pop_back()
	var ind := 0
	for me in d2["markers"]["spawn"]:
		if int(me.get("team", -1)) < 0:
			ind += 1
	if ind >= 8:
		(d2["markers"]["spawn"] as Array).remove_at(0)
	check(_codes(d2).has("missing_markers"), "FFA needs 8 individual spawns")
	var d3 := _base("gullet", ["boss"])
	d3["markers"].erase("boss")
	check(_codes(d3).has("missing_markers"), "boss layouts need a boss marker")


func test_too_little_clear_floor() -> void:
	var d := _base("crusher", [])
	d["markers"] = {}
	for i in 6:
		for j in 6:
			d["props"].append({"type": "prop_heavy_crate", "pos": [-5.0 + i * 2.0, 0, -5.0 + j * 2.0]})
	var res := ArenaValidator.validate(ArenaDef.from_dict(d))
	check(float(res["stats"]["clear_floor"]) < 0.45, "coverage map sees the crates (%.2f)" % float(res["stats"]["clear_floor"]))
	check(_codes(d).has("clear_floor"), "clear floor rule")


func test_team_clusters_and_bounds() -> void:
	var d := _base("gullet", ["teams"])
	for me in d["markers"]["spawn"]:
		if int(me.get("team", -1)) == 1:
			me["pos"] = [float(me["pos"][0]) - 5.0, 0.0, float(me["pos"][2])]
	check(_codes(d).has("team_clusters_close"), "clusters closer than 6 m")
	var d2 := _base()
	d2["props"].append({"type": "prop_crate", "pos": [7.5, 0, 0]})
	var e := _issue(d2, "out_of_bounds")
	check(not e.is_empty(), "prop outside the cage")
	check_eq(str(e.get("ref", {}).get("kind", "")), "prop", "points at the prop")
	var d3 := _base()
	d3["size"] = [9.0, 9.0]
	d3["props"].append({"type": "prop_bollard", "pos": [5.2, 0, 0]})
	check(_codes(d3).has("out_of_bounds"), "shrinking the boundary strands props outside it")


func test_issue_refs_carry_editor_uids() -> void:
	var m := ArenaEditModel.from_dict(_base())
	var it := m.make_item("prop_heavy_crate", Vector3(30, 0, 0))
	m.insert_item(it)
	var res := ArenaValidator.validate(m.to_arena(true))
	var found := false
	for e in res["errors"]:
		if str(e["code"]) == "out_of_bounds" and int(e["ref"].get("uid", -1)) == int(it["uid"]):
			found = true
	check(found, "the editor can select the offending item by uid")
