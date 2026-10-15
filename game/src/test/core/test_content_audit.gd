extends TestCase
## VER-06 content audit over everything the core package ships: no load/schema errors, every
## referenced asset exists, creatures parse with their weapons and chains intact, arenas have safe
## spawns inside their bounds, presets/tutorial/achievements are complete, and the bundled example
## mods validate. Grows as owners add kinds (campaign, arenas, playlists, policies).

const TUTORIAL_CHECKS := ["footwork", "light_string", "heavy_then_charged", "guard_string", "dodge_then_dash",
	"ability_connect", "grab_throw", "parries", "finisher_juice", "win_round"]


func test_core_package_loads_without_errors() -> void:
	Mods.use_root(temp_dir("audit_mods"))
	Mods.apply()
	var errs := Array(Content.errors)
	# stub kits are reported by CreatureDef, not by Content; Content itself must be clean
	check(errs.is_empty(), "content errors: %s" % "\n".join(PackedStringArray(errs.slice(0, 12))))
	Mods.use_root("")
	Mods.apply()


func test_every_creature_parses_and_assets_exist() -> void:
	for kind in Content.CREATURE_KINDS:
		for id in Content.ids(kind):
			var d := Content.get_entry(kind, str(id))
			var c := Content.creature(str(id))
			check(c != null, "%s/%s parses" % [kind, id])
			if c == null:
				continue
			check(c.body != null and c.body.segments.size() >= 3, "%s has a body" % id)
			var model := str(d.get("art", {}).get("model", ""))
			if model != "":
				check(ResourceLoader.exists(model) or FileAccess.file_exists(model), "%s model exists: %s" % [id, model])
			for slot in c.moves:
				var m: MoveDef = c.moves[slot]
				for w in m.windows:
					for wname in (w["weapons"] as PackedStringArray):
						check(c.body.weapons.has(wname), "%s.%s uses weapon '%s' the body defines" % [id, slot, wname])
					check(float(w["t0"]) <= float(w["t1"]) and float(w["t1"]) <= m.duration + 0.001, "%s.%s hit window inside the move" % [id, slot])
				for cname in m.animated_chains:
					check(c.body.chains.has(cname), "%s.%s animates chain '%s' the body defines" % [id, slot, cname])
			for wname in c.body.weapons:
				var wpn: BodyDef.Weapon = c.body.weapons[wname]
				check(wpn.seg >= 0 and wpn.seg < c.body.segments.size(), "%s weapon %s on a real segment" % [id, wname])


func test_arenas_have_safe_spawns_inside_bounds() -> void:
	for id in Content.ids("arenas"):
		var a := Content.arena(str(id))
		check(a != null, "arena %s parses" % id)
		if a == null:
			continue
		check(a.spawns.size() >= 2, "%s has at least 2 spawns" % id)
		for i in a.spawns.size():
			var sp: Vector3 = a.spawns[i][0]
			check(a.inside(sp, 0.6), "%s spawn %d is inside the walls with margin" % [id, i])
			for j in range(i + 1, a.spawns.size()):
				var sp2: Vector3 = a.spawns[j][0]
				check(Vector2(sp.x - sp2.x, sp.z - sp2.z).length() >= 1.2, "%s spawns %d and %d are not on top of each other" % [id, i, j])
			for pr in a.props:
				var pp: Vector3 = pr["pos"]
				check(Vector2(sp.x - pp.x, sp.z - pp.z).length() >= 0.9, "%s spawn %d is clear of prop %s" % [id, i, pr.get("type", "?")])


func test_tutorial_achievements_and_presets_complete() -> void:
	for ex in Tutorial.exercises():
		check(str(ex.get("check", "")) in TUTORIAL_CHECKS, "tutorial %s uses a known check" % ex.get("id", "?"))
	var ach := Content.ids("achievements")
	check(ach.size() >= 10, "achievements defined (%d)" % ach.size())
	for id in ach:
		var d := Content.get_entry("achievements", str(id))
		check(str(d.get("name", "")) != "" and str(d.get("description", "")) != "", "achievement %s has text" % id)
	for id in Content.ids("rules"):
		var r := Content.get_entry("rules", str(id))
		check(ModeRegistry.has(str(r.get("mode", ""))), "rules %s uses a registered mode" % id)


func test_bundled_example_mods_validate() -> void:
	Mods.use_root(temp_dir("audit_examples"))
	var ex := Mods.available.filter(func(i): return str(i["kind"]) == "example")
	check(ex.size() >= 3, "three bundled examples")
	for info in ex:
		check((info["errors"] as Array).is_empty(), "%s validates: %s" % [info["id"], str(info["errors"])])
	Mods.use_root("")
