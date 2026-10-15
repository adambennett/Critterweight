extends TestCase
## ARN-04/05, CNT-05: every shipped base arena and example layout loads, resolves its base and
## validates clean; the ArenaDef public API (clamp_point, inside, spawn_point, marker_points,
## markers_of, to_dict/from_dict) keeps working for both format-2 and legacy arenas.

const BASE_ARENAS := ["arena_gullet", "arena_drydock", "arena_crusher", "arena_rooftop"]
const LAYOUTS := ["layout_gullet_classic", "layout_glandco_showcase", "layout_drydock_pitch", "layout_crusher_king",
	"layout_rooftop_gauntlet", "layout_unit_pit"]


func test_catalog_has_full_palette() -> void:
	ArenaCatalog.reload()
	check(ArenaCatalog.errors.is_empty(), "catalog schema errors: %s" % str(ArenaCatalog.errors))
	var spec := ["prop_crate", "prop_heavy_crate", "prop_sponsor_board", "prop_fence_segment", "prop_tire_stack", "prop_bollard",
		"prop_fire_barrel", "prop_sludge_drum", "prop_brine_barrel", "prop_battery", "prop_gravel_sack", "prop_fan_unit",
		"prop_steam_vent", "prop_electric_plate", "prop_spring_pad", "prop_bumper", "prop_pit", "prop_drain_pair",
		"prop_heavy_bag", "prop_chum_bucket", "prop_hype_can", "prop_ramp", "marker_spawn", "marker_boss",
		"marker_spotlight_anchor", "marker_goal", "marker_ball_spawn", "marker_wave_gate", "marker_unit_spawn"]
	for id in spec:
		var p := ArenaCatalog.prop(id)
		check(not p.is_empty(), "catalog has %s" % id)
		check(bool(p.get("palette", false)), "%s is in the editor palette" % id)
	check_eq(ArenaCatalog.prop("prop_fan_unit")["cost"], 4, "fan cost")
	check_eq(ArenaCatalog.prop("prop_drain_pair")["cost"], 5, "drain pair cost")
	check_eq(ArenaCatalog.palette("markers").size() >= 7, true, "marker tab")
	for b in ["gullet", "drydock", "crusher", "rooftop"]:
		check(not ArenaCatalog.base(b).is_empty(), "base %s registered" % b)
	check_eq(ArenaCatalog.base_ids().slice(0, 4), ["gullet", "drydock", "crusher", "rooftop"], "canonical base order")


func test_every_base_and_layout_loads_and_validates() -> void:
	for id in BASE_ARENAS + LAYOUTS + ["the_gullet"]:
		var a := Content.arena(id)
		if not check(a != null, "%s loads" % id):
			continue
		check(a.errors.is_empty(), "%s errors %s" % [id, str(a.errors)])
		check(not a.base_def.is_empty(), "%s resolved its base" % id)
		var res := ArenaValidator.validate(a)
		var msgs := []
		for e in res["errors"]:
			msgs.append(str(e["message"]))
		check(bool(res["ok"]), "%s validates: %s" % [id, "; ".join(msgs)])
		check(float(res["stats"]["clear_floor"]) >= ArenaValidator.MIN_CLEAR, "%s clear floor" % id)


func test_base_arenas_ship_required_markers() -> void:
	for id in BASE_ARENAS:
		var a := Content.arena(id)
		var individual := 0
		for me in a.markers_of("spawn"):
			if int(me["team"]) < 0:
				individual += 1
		check_eq(individual, 8, "%s has 8 spawns" % id)
		check_eq(a.team_spawns(0).size(), 4, "%s team A cluster" % id)
		check_eq(a.team_spawns(1).size(), 4, "%s team B cluster" % id)
		check_eq(a.markers_of("boss").size(), 1, "%s boss marker" % id)


func test_example_layout_budgets_match_spec() -> void:
	var expect := {"layout_gullet_classic": 0, "layout_glandco_showcase": 27, "layout_drydock_pitch": 18,
		"layout_crusher_king": 16, "layout_rooftop_gauntlet": 18, "layout_unit_pit": 49}
	for id in expect:
		var res := ArenaValidator.validate(Content.arena(id))
		check_eq(int(res["stats"]["budget"]), int(expect[id]), "%s budget" % id)
	var king := Content.arena("layout_crusher_king")
	var plates_on := false
	for h in king.hazard_defs():
		if str(h["type"]) == "plate_grid":
			plates_on = true
	check(not plates_on, "Crusher King disables the electrified plates")


func test_base_geometry_and_dimensions() -> void:
	var g := Content.arena("arena_gullet")
	check_eq(g.shape, "octagon")
	check_near(g.radius, 6.0, 0.001, "12 m flat-to-flat")
	check(g.inside(Vector3(5.5, 0, 0), 0.0) and not g.inside(Vector3(6.2, 0, 0), 0.0), "octagon flat at 6 m")
	check(not g.inside(Vector3(4.4, 0, 4.4), 0.0), "diagonal flat cuts the corner")
	var d := Content.arena("arena_drydock")
	check_eq(d.size, Vector2(16, 10), "drydock 16 x 10")
	check(d.on_floor(Vector3(7.9, 0, 4.9)) and not d.on_floor(Vector3(8.1, 0, 0)), "drydock rect bounds")
	var r := Content.arena("arena_rooftop")
	check(r.ringout and r.has_open_edges(), "rooftop has open edges")
	check(not r.on_floor(Vector3(6.0, 0, 5.0)), "NE notch is cut out")
	check(not r.on_floor(Vector3(-6.0, 0, -5.0)), "SW notch is cut out")
	check(r.on_floor(Vector3(6.0, 0, -5.0)) and r.on_floor(Vector3(-6.0, 0, 5.0)), "other corners are floor")
	check(r.inside(Vector3(20, 0, 0), 0.5), "open edges never count as walls")
	var cl := r.clamp_point(Vector3(6.5, 0, 5.5), 0.3)
	check(r.on_floor(cl, 0.29), "clamp lands on the floor with margin")
	var c := Content.arena("arena_crusher")
	check_eq(c.grid_cells(c.hazard_defs()[0]).size(), 9, "3 x 3 plates")


func test_spawn_point_spreads_fighters() -> void:
	var g := Content.arena("arena_gullet")
	var a: Vector3 = g.spawn_point(0, 2)[0]
	var b: Vector3 = g.spawn_point(1, 2)[0]
	check_near(a.distance_to(b), 6.0, 0.05, "1v1 spawns 6 m apart")
	var seen := {}
	for i in 8:
		seen[str(g.spawn_point(i, 8)[0])] = true
	check_eq(seen.size(), 8, "8 distinct spawns for 8 fighters")
	# legacy arenas keep spawns[i]
	var legacy := ArenaDef.from_dict({"id": "t", "base": "octagon", "radius": 5.0, "spawns": [[0, -1, 0], [0, 1, 180], [1, 0, 90]]})
	check_eq(legacy.spawn_point(1, 2)[0], Vector3(0, 0, 1), "legacy order")


func test_round_trip_to_dict_from_dict() -> void:
	for id in LAYOUTS:
		var a := Content.arena(id)
		var b := ArenaDef.from_dict(a.to_dict())
		check_eq(b.content_hash(), a.content_hash(), "%s hash survives a round trip" % id)
		check_eq(b.props.size(), a.props.size(), "%s props" % id)
		check_eq(b.markers_of("spawn").size(), a.markers_of("spawn").size(), "%s spawns" % id)
	var legacy := ArenaDef.from_dict({"id": "old", "base": "square", "radius": 4.0, "spawns": [[0, -1, 0]], "markers": {"goal": [[1, 2]]}})
	check_eq(legacy.marker_points("marker_goal").size(), 1, "legacy markers by prefixed name")
	var back := ArenaDef.from_dict(legacy.to_dict())
	check_eq(back.base, "square", "legacy base kept")
	check_eq(back.spawns.size(), 1, "legacy spawns kept")


func test_schema_accepts_layouts_and_rejects_bad_base() -> void:
	for id in LAYOUTS:
		var errs := Schema.validate_named(Content.arena(id).to_dict(), "arena")
		check(errs.is_empty(), "%s schema: %s" % [id, str(errs)])
	check(not Schema.validate_named({"id": "x", "name": "X", "base": "volcano"}, "arena").is_empty(), "unknown core base rejected")
	check(Schema.validate_named({"id": "m:x", "name": "X", "base": "m:volcano"}, "arena").is_empty(), "namespaced mod base accepted")


## A match context can pick the look (campaign gullet_day / gullet_title); gameplay is unchanged.
func test_context_variant_changes_only_the_look() -> void:
	var a := Content.arena("arena_gullet")
	var day := a.with_variant("day")
	check_eq(day.variant, "day", "variant applied")
	check(day != a and a.variant == "night", "a copy; the shared content arena is untouched")
	check_eq(day.all_props().size(), a.all_props().size(), "same props")
	check_eq(day.spawns.size(), a.spawns.size(), "same spawns")
	check(a.with_variant("off_the_street") == a and a.with_variant("") == a, "unknown names are ignored")
	var cfg := App.resolve_match_config({"arena": "arena_gullet", "rules": {"mode": "standard"}, "seed": 1,
		"fighters": [], "context": {"campaign": true, "variant": "title_night"}})
	check_eq((cfg["arena"] as ArenaDef).variant, "title_night", "App applies context.variant")


## Format-1 files (the bundled rust_bucket mod's "The Drain") keep validating and loading:
## [x, z, yaw] spawns with yaws past 50, and marker objects whose pos is the floor form [x, z].
func test_format1_mod_arena_still_loads() -> void:
	var d := {"id": "m:drain", "name": "Drain", "base": "square", "radius": 5.5, "wall_height": 2.2, "theme": "can",
		"spawns": [[0, -3.0, 0], [0, 3.0, 180], [-3.0, 0, 270]],
		"props": [{"type": "crate", "pos": [-4.2, 0, -4.2]}, {"type": "low_wall", "pos": [0, 0, -4.6]}],
		"hazards": [{"type": "shock_plate", "pos": [0, 0, 0], "radius": 1.1}],
		"markers": {"spotlight": [[-2.5, -2.5]], "goal": [{"pos": [-5.3, 0], "team": 0}, {"pos": [5.3, 1.0], "team": 1}]}}
	var errs := Schema.validate_named(d, "arena")
	check(errs.is_empty(), "format-1 file validates: %s" % str(errs))
	var a := ArenaDef.from_dict(d)
	check(a.errors.is_empty(), "parses: %s" % str(a.errors))
	check_eq(a.base, "square", "legacy shape kept")
	var goals := a.markers_of("goal")
	check_eq(goals.size(), 2, "goal markers")
	if goals.size() == 2:
		check_eq(goals[0]["pos"], Vector3(-5.3, 0, 0), "[x, z] marker pos is a floor point")
		check_eq(goals[1]["pos"], Vector3(5.3, 0, 1.0), "z comes second in the floor form")
		check_eq(int(goals[1]["team"]), 1, "marker team kept")
	check_eq(a.spawn_point(2, 3)[1], deg_to_rad(270.0), "spawn yaw in degrees")
	check_eq(a.marker_points("spotlight_anchor").size(), 1, "older 'spotlight' markers feed Spotlight Hog's anchors")
	var mod_a := Content.arena("rust_bucket:the_drain")
	if mod_a != null:
		check_eq(mod_a.markers_of("goal").size(), 2, "the bundled example's goals")
