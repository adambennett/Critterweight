class_name ArenaValidator
## Layout validation (ARENAS.md §3 budget rules, MODES.md markers, ARN-04). Pure function of an
## ArenaDef + the catalog; used by the arena editor's live panel, by tests, by package import and
## (headless) by servers that receive a layout. Every issue names the offending item so the
## editor can select it: issue = {severity, code, message, ref: {kind, index, uid, marker, id}, pos}.
##
## Rules (errors unless noted):
##   unknown_prop · budget (100) · too_many_props (24, markers free) · too_many_hazards (8 timed or
##   destructible-elemental hazards; pads/bumpers/pits/drains are free of that cap) ·
##   too_many_pickups (4) / pickup_limit (per type, 2) · clear_floor (>= 45 % via 0.25 m coverage map)
##   out_of_bounds (props/markers) · pit_not_allowed · pit_no_respawn (respawn marker <= 4 m) ·
##   spawn_outside · spawn_blocked (1.5 m from obstacles/hazards incl. base hazards) · spawn_wall
##   (1.0 m from walls) · spawn_edge (2 m from open edges) · spawn_pit (2 m from pits) ·
##   too_many_spawns · team_clusters_close (cluster centroids >= 6 m) · too_many_markers ·
##   missing_markers (per supported mode) · warnings: overlap, tall_near_wall, no_modes, zone_budget.

const BUDGET := 100
const MAX_PROPS := 24
const MAX_HAZARDS := 8
const MAX_PICKUPS := 4
const MIN_CLEAR := 0.45
const SPAWN_CLEAR := 1.5
const WALL_CLEAR := 1.0
const EDGE_CLEAR := 2.0
const PIT_CLEAR := 2.0
const TEAM_APART := 6.0
const PIT_RESPAWN := 4.0
const TALL_NEAR_WALL := 1.2
const CELL := 0.25
const ZONE_CAP := 24

## Markers each supported mode needs (MODES.md). Keys: spawn = individual spawns, team_clusters =
## spawn clusters A and B, player_cluster = cluster A, goals = team-tagged goals A and B.
const MODE_REQUIREMENTS := {
	"duel": {"spawn": 2},
	"ffa": {"spawn": 8},
	"teams": {"team_clusters": true},
	"coop": {"team_clusters": true},
	"practice": {"spawn": 2},
	"spotlight_hog": {"spotlight_anchor": 3, "spawn": 8},
	"chumball": {"goals": true, "ball_spawn": 1, "team_clusters": true},
	"absolute_unit": {"unit_spawn": 1, "spawn": 8},
	"chum_rush": {"wave_gate": 2, "player_cluster": true},
	"boss": {"boss": 1},
}
const MODE_LABELS := {"duel": "1v1", "ffa": "Free-for-All", "teams": "Teams", "coop": "Co-op", "practice": "Practice",
	"spotlight_hog": "Spotlight Hog", "chumball": "Chumball", "absolute_unit": "Absolute Unit", "chum_rush": "Chum Rush", "boss": "Boss"}


static func validate(a: ArenaDef) -> Dictionary:
	var issues: Array = []
	var stats := {"budget": 0, "budget_max": BUDGET, "props": 0, "props_max": MAX_PROPS, "hazards": 0, "hazards_max": MAX_HAZARDS,
		"pickups": 0, "pickups_max": MAX_PICKUPS, "clear_floor": 1.0, "clear_floor_min": MIN_CLEAR, "spawns": 0, "zones": 0}
	for e in a.errors:
		issues.append(_issue("error", "definition", str(e), {"kind": "layout"}))
	if a.base_def.is_empty() and not ArenaDef.BASES.has(a.base):
		return _result(issues, stats)
	var all := a.all_props()
	var pits: Array = []
	var per_type := {}
	# --- props: catalog, counts, budget, bounds ---
	for i in all.size():
		var p: Dictionary = all[i]
		var ref := _prop_ref(a, p)
		var def := ArenaCatalog.prop(str(p["type"]))
		if def.is_empty():
			issues.append(_issue("error", "unknown_prop", "Unknown prop type '%s'." % p["type"], ref, p["pos"]))
			continue
		if str(def["behaviour"]) == "pit":
			pits.append(p)
		if not bool(p.get("builtin", false)):
			stats["budget"] = int(stats["budget"]) + int(def["cost"])
			stats["props"] = int(stats["props"]) + 1
			if bool(def["limited_hazard"]):
				stats["hazards"] = int(stats["hazards"]) + 1
			if str(def["class"]) == "pickup":
				stats["pickups"] = int(stats["pickups"]) + 1
			per_type[def["id"]] = int(per_type.get(def["id"], 0)) + 1
			if not def["on_destroy"].is_empty() and str(def["on_destroy"].get("zone", "")) != "":
				stats["zones"] = int(stats["zones"]) + 1
		if str(def["behaviour"]) != "railing":
			for v in ArenaCatalog.footprint_outline(p, def):
				if not a.on_floor(Vector3(v.x, 0.0, v.y), -0.02):
					issues.append(_issue("error", "out_of_bounds", "%s is outside the playable boundary." % def["name"], ref, p["pos"]))
					break
		if str(def["behaviour"]) == "pit" and not a.allows_pits():
			issues.append(_issue("error", "pit_not_allowed", "Pits are only allowed on bases with open edges (or when the layout flag 'allow_pits' is set).", ref, p["pos"]))
		if float(def["height"]) > TALL_NEAR_WALL and bool(def["solid"]) and a.wall_height > 0.0 and not bool(p.get("builtin", false)):
			if a.near_wall(p["pos"], 1.0 + ArenaCatalog.footprint_size(p, def).length() * 0.5):
				issues.append(_issue("warning", "tall_near_wall", "%s is taller than 1.2 m next to a wall; the camera may not see over it." % def["name"], ref, p["pos"]))
	if int(stats["budget"]) > BUDGET:
		issues.append(_issue("error", "budget", "Over budget: %d / %d points." % [stats["budget"], BUDGET], {"kind": "layout"}))
	if int(stats["props"]) > MAX_PROPS:
		issues.append(_issue("error", "too_many_props", "Too many props: %d / %d." % [stats["props"], MAX_PROPS], {"kind": "layout"}))
	if int(stats["hazards"]) > MAX_HAZARDS:
		issues.append(_issue("error", "too_many_hazards", "Too many hazards: %d / %d." % [stats["hazards"], MAX_HAZARDS], {"kind": "layout"}))
	if int(stats["pickups"]) > MAX_PICKUPS:
		issues.append(_issue("error", "too_many_pickups", "Too many pickups: %d / %d." % [stats["pickups"], MAX_PICKUPS], {"kind": "layout"}))
	for tid in per_type:
		var d := ArenaCatalog.prop(str(tid))
		var mx := int(d.get("max_per_layout", 0))
		if mx > 0 and int(per_type[tid]) > mx:
			var last := _last_of_type(a, str(tid))
			issues.append(_issue("error", "pickup_limit", "At most %d %s per layout (%d placed)." % [mx, d["name"], per_type[tid]], last, last.get("pos", Vector3.ZERO)))
	if int(stats["zones"]) > ZONE_CAP:
		issues.append(_issue("warning", "zone_budget", "%d props can each create a zone; the engine keeps at most %d live zones." % [stats["zones"], ZONE_CAP], {"kind": "layout"}))
	_check_overlaps(a, all, issues)
	# --- clear floor ---
	stats["clear_floor"] = clear_floor_fraction(a)
	if float(stats["clear_floor"]) < MIN_CLEAR:
		issues.append(_issue("error", "clear_floor", "Only %d%% of the floor is clear (minimum %d%%)." % [roundi(float(stats["clear_floor"]) * 100.0), roundi(MIN_CLEAR * 100.0)], {"kind": "layout"}))
	# --- pits need a respawn marker nearby ---
	var respawns: Array = a.markers_of("respawn")
	for pit in pits:
		var ok := false
		for r in respawns:
			if (r["pos"] as Vector3).distance_to(pit["pos"]) <= PIT_RESPAWN:
				ok = true
		if not ok:
			issues.append(_issue("error", "pit_no_respawn", "Pit needs a Respawn point within %.0f m." % PIT_RESPAWN, _prop_ref(a, pit), pit["pos"]))
	# --- markers: bounds, limits ---
	for name_ in a.marker_entries:
		var tdef := ArenaCatalog.prop(ArenaCatalog.marker_type(str(name_)))
		var entries: Array = a.marker_entries[name_]
		for k in entries.size():
			var me: Dictionary = entries[k]
			if not a.on_floor(me["pos"], 0.0) and str(name_) not in ["goal", "wave_gate"]:
				issues.append(_issue("error", "out_of_bounds", "%s marker is outside the playable boundary." % str(name_).capitalize(), _marker_ref(str(name_), k, me), me["pos"]))
			elif str(name_) in ["goal", "wave_gate"] and not a.on_floor(me["pos"], -0.4):
				issues.append(_issue("error", "out_of_bounds", "%s marker is outside the arena." % str(name_).capitalize(), _marker_ref(str(name_), k, me), me["pos"]))
		if not tdef.is_empty() and str(name_) != "spawn":
			var mx2 := int(tdef["marker"]["max"])
			if entries.size() > mx2:
				issues.append(_issue("error", "too_many_markers", "At most %d %s markers." % [mx2, tdef["name"]], _marker_ref(str(name_), entries.size() - 1, entries.back()), (entries.back() as Dictionary)["pos"]))
	# --- spawns ---
	_check_spawns(a, all, pits, issues, stats)
	# --- mode markers ---
	var modes: Array = a.modes.duplicate()
	if modes.is_empty():
		issues.append(_issue("warning", "no_modes", "No supported modes declared; checking 1v1 requirements only.", {"kind": "layout"}))
		modes = ["duel"]
	for m in modes:
		for msg in missing_for_mode(a, str(m)):
			issues.append(_issue("error", "missing_markers", "%s: %s" % [MODE_LABELS.get(str(m), str(m)), msg], {"kind": "layout", "mode": str(m)}))
	return _result(issues, stats)


static func _result(issues: Array, stats: Dictionary) -> Dictionary:
	var errors := []
	var warnings := []
	for it in issues:
		if str(it["severity"]) == "error":
			errors.append(it)
		else:
			warnings.append(it)
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings, "issues": issues, "stats": stats}


static func _issue(sev: String, code: String, msg: String, ref: Dictionary, pos := Vector3.ZERO) -> Dictionary:
	return {"severity": sev, "code": code, "message": msg, "ref": ref, "pos": pos}


static func _prop_ref(a: ArenaDef, p: Dictionary) -> Dictionary:
	if bool(p.get("builtin", false)):
		return {"kind": "builtin", "id": str(p.get("id", "")), "uid": int(p.get("uid", -1)), "index": a.builtins.find(p)}
	return {"kind": "prop", "index": a.props.find(p), "uid": int(p.get("uid", -1)), "id": str(p.get("id", ""))}


static func _marker_ref(name_: String, k: int, me: Dictionary) -> Dictionary:
	return {"kind": "marker", "marker": name_, "index": k, "uid": int(me.get("uid", -1))}


static func _last_of_type(a: ArenaDef, t: String) -> Dictionary:
	for i in range(a.props.size() - 1, -1, -1):
		var p: Dictionary = a.props[i]
		if str(p["type"]) == t:
			var r := _prop_ref(a, p)
			r["pos"] = p["pos"]
			return r
	return {"kind": "layout"}


## Fraction of the floor not covered by solid footprints or pits (0.25 m coverage map).
static func clear_floor_fraction(a: ArenaDef) -> float:
	var ext := a.extent()
	var nx := int(ceil(ext.size.x / CELL))
	var nz := int(ceil(ext.size.y / CELL))
	var blocked := PackedByteArray()
	blocked.resize(nx * nz)
	var floor_cells := 0
	var free_cells := 0
	var solids: Array = []
	for p in a.all_props():
		var def := ArenaCatalog.prop(str(p["type"]))
		if def.is_empty() or not bool(def["solid"]):
			continue
		solids.append([p, def, ArenaCatalog.footprint_aabb(p, def)])
	for s in solids:
		var r: Rect2 = s[2]
		var i0 := clampi(int(floor((r.position.x - ext.position.x) / CELL)), 0, nx - 1)
		var i1 := clampi(int(ceil((r.end.x - ext.position.x) / CELL)), 0, nx - 1)
		var j0 := clampi(int(floor((r.position.y - ext.position.y) / CELL)), 0, nz - 1)
		var j1 := clampi(int(ceil((r.end.y - ext.position.y) / CELL)), 0, nz - 1)
		for i in range(i0, i1 + 1):
			for j in range(j0, j1 + 1):
				var c := Vector2(ext.position.x + (i + 0.5) * CELL, ext.position.y + (j + 0.5) * CELL)
				if ArenaCatalog.footprint_distance(s[0], s[1], c) <= 0.0:
					blocked[j * nx + i] = 1
	for i in nx:
		for j in nz:
			var c2 := Vector3(ext.position.x + (i + 0.5) * CELL, 0.0, ext.position.y + (j + 0.5) * CELL)
			if not a.on_floor(c2, 0.0):
				continue
			floor_cells += 1
			if blocked[j * nx + i] == 0:
				free_cells += 1
	return float(free_cells) / float(maxi(1, floor_cells))


static func _check_overlaps(a: ArenaDef, all: Array, issues: Array) -> void:
	var solids: Array = []
	for p in all:
		var def := ArenaCatalog.prop(str(p["type"]))
		if def.is_empty() or not bool(def["solid"]):
			continue
		solids.append([p, def, ArenaCatalog.footprint_aabb(p, def)])
	for i in solids.size():
		for k in range(i + 1, solids.size()):
			var ra: Rect2 = solids[i][2]
			var rb: Rect2 = solids[k][2]
			if not ra.grow(-0.05).intersects(rb.grow(-0.05)):
				continue
			# deeper test: any outline point of one strictly inside the other
			var hit := false
			for v in ArenaCatalog.footprint_outline(solids[k][0], solids[k][1]):
				if ArenaCatalog.footprint_distance(solids[i][0], solids[i][1], v) < -0.08:
					hit = true
					break
			if not hit:
				var c: Vector3 = solids[k][0]["pos"]
				hit = ArenaCatalog.footprint_distance(solids[i][0], solids[i][1], Vector2(c.x, c.z)) < 0.0
			if hit:
				var p2: Dictionary = solids[k][0]
				if str(p2["type"]) == "prop_fence_segment" and str(solids[i][0]["type"]) == "prop_fence_segment":
					continue   # fence panels may cross at the corners of an interior cage
				issues.append(_issue("warning", "overlap", "%s overlaps %s." % [solids[k][1]["name"], solids[i][1]["name"]], _prop_ref(a, p2), p2["pos"]))


static func _check_spawns(a: ArenaDef, all: Array, pits: Array, issues: Array, stats: Dictionary) -> void:
	var entries: Array = a.markers_of("spawn")
	stats["spawns"] = entries.size()
	var blockers: Array = []
	for p in all:
		var def := ArenaCatalog.prop(str(p["type"]))
		if def.is_empty():
			continue
		if bool(def["solid"]) or bool(def["hazard"]):
			blockers.append([p, def])
	var base_fp := base_hazard_footprints(a)
	var individual := 0
	var per_team := {}
	var centroid := {}
	for k in entries.size():
		var me: Dictionary = entries[k]
		var pos: Vector3 = me["pos"]
		var ref := _marker_ref("spawn", k, me)
		var team := int(me["team"])
		if team < 0:
			individual += 1
		else:
			per_team[team] = int(per_team.get(team, 0)) + 1
			centroid[team] = (centroid.get(team, Vector3.ZERO) as Vector3) + pos
		if not a.on_floor(pos, 0.0):
			issues.append(_issue("error", "spawn_outside", "Spawn point is off the floor.", ref, pos))
			continue
		if a.near_wall(pos, WALL_CLEAR):
			issues.append(_issue("error", "spawn_wall", "Spawn point is closer than %.1f m to a wall." % WALL_CLEAR, ref, pos))
		if a.has_open_edges() and a.edge_distance(pos, true) < EDGE_CLEAR:
			issues.append(_issue("error", "spawn_edge", "Spawn point is within %.0f m of an open edge." % EDGE_CLEAR, ref, pos))
		var p2 := Vector2(pos.x, pos.z)
		for b in blockers:
			var def2: Dictionary = b[1]
			var need := PIT_CLEAR if str(def2["behaviour"]) == "pit" else SPAWN_CLEAR
			var dd := ArenaCatalog.footprint_distance(b[0], def2, p2)
			if dd < need:
				var code := "spawn_pit" if str(def2["behaviour"]) == "pit" else "spawn_blocked"
				issues.append(_issue("error", code, "Spawn point is %.1f m from %s (needs %.1f m)." % [maxf(dd, 0.0), def2["name"], need], ref, pos))
				break
		for fp in base_fp:
			var d2 := _base_fp_distance(fp, p2)
			if d2 < SPAWN_CLEAR:
				issues.append(_issue("error", "spawn_blocked", "Spawn point is %.1f m from the %s (needs %.1f m)." % [maxf(d2, 0.0), fp["label"], SPAWN_CLEAR], ref, pos))
				break
	if individual > 8:
		issues.append(_issue("error", "too_many_spawns", "At most 8 individual spawn points (%d placed)." % individual, {"kind": "layout"}))
	for t in per_team:
		if int(per_team[t]) > 4:
			issues.append(_issue("error", "too_many_spawns", "Team %s cluster has %d spawns (max 4)." % [_team_letter(int(t)), per_team[t]], {"kind": "layout"}))
	if per_team.has(0) and per_team.has(1):
		var c0: Vector3 = (centroid[0] as Vector3) / float(per_team[0])
		var c1: Vector3 = (centroid[1] as Vector3) / float(per_team[1])
		if Vector2(c0.x - c1.x, c0.z - c1.z).length() < TEAM_APART:
			issues.append(_issue("error", "team_clusters_close", "Team clusters are only %.1f m apart (minimum %.0f m)." % [Vector2(c0.x - c1.x, c0.z - c1.z).length(), TEAM_APART], {"kind": "layout"}, c0))


static func _team_letter(t: int) -> String:
	return ["A", "B", "C", "D"][clampi(t, 0, 3)]


## Footprints of base hazards that spawns must keep clear of: [{kind: rect|circle, rect|center+r, label}].
static func base_hazard_footprints(a: ArenaDef) -> Array:
	var out := []
	for h in a.hazard_defs():
		match str(h.get("type", "")):
			"tidal_gutter":
				out.append({"kind": "rect", "rect": a.strip_rect(h), "label": str(h.get("label", "tidal gutter")).to_lower()})
			"crane_hook":
				for s in h.get("spots", []):
					out.append({"kind": "circle", "center": s, "r": float(h.get("radius", 0.75)), "label": str(h.get("label", "crane hook")).to_lower()})
	return out


static func _base_fp_distance(fp: Dictionary, p: Vector2) -> float:
	if str(fp["kind"]) == "circle":
		return p.distance_to(fp["center"]) - float(fp["r"])
	var r: Rect2 = fp["rect"]
	var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
	var dz := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
	if r.has_point(p):
		return -minf(minf(p.x - r.position.x, r.end.x - p.x), minf(p.y - r.position.y, r.end.y - p.y))
	return Vector2(dx, dz).length()


## Human-readable list of what a mode still needs on this layout ([] = satisfied).
static func missing_for_mode(a: ArenaDef, mode: String) -> Array:
	var req: Dictionary = MODE_REQUIREMENTS.get(mode.trim_prefix("mode_"), {})
	var out := []
	var individual := 0
	for me in a.markers_of("spawn"):
		if int(me["team"]) < 0:
			individual += 1
	if req.has("spawn") and individual < int(req["spawn"]):
		out.append("needs %d individual spawn points (has %d)" % [int(req["spawn"]), individual])
	if bool(req.get("team_clusters", false)) and (a.team_spawns(0).is_empty() or a.team_spawns(1).is_empty()):
		out.append("needs team spawn clusters A and B")
	if bool(req.get("player_cluster", false)) and a.team_spawns(0).is_empty():
		out.append("needs a player spawn cluster (team A)")
	for key in ["spotlight_anchor", "ball_spawn", "unit_spawn", "wave_gate", "boss"]:
		if req.has(key) and a.markers_of(key).size() < int(req[key]):
			out.append("needs %d %s marker%s (has %d)" % [int(req[key]), str(key).replace("_", " "), "s" if int(req[key]) > 1 else "", a.markers_of(key).size()])
	if bool(req.get("goals", false)):
		var teams := {}
		for g in a.markers_of("goal"):
			teams[int(g["team"])] = true
		if not (teams.has(0) and teams.has(1)):
			out.append("needs two goals tagged team A and team B")
	return out
