extends TestCase
## MOD-01..06: package validation and trust rules, install/upgrade/removal, dependencies and
## deterministic order, consent for core overrides, creature "extends", rule hooks, multiplayer
## comparison. Every test works in its own temporary mods folder and restores the real one.

var dir := ""
var _saved_limits := {}


func before_each() -> void:
	dir = temp_dir("mods_%d" % Time.get_ticks_usec())
	_saved_limits = Mods.limits.duplicate()
	Mods.use_root(dir.path_join("installed"))


func after_each() -> void:
	Mods.limits = _saved_limits
	Mods.use_root("")
	Mods.apply()


## Writes a package archive from {relative path: content (String/PackedByteArray/Dictionary)}.
func _archive(name_: String, files: Dictionary) -> String:
	var p := dir.path_join(name_)
	var zp := ZIPPacker.new()
	zp.open(p)
	for rel in files:
		zp.start_file(rel)
		var v = files[rel]
		if typeof(v) == TYPE_DICTIONARY or typeof(v) == TYPE_ARRAY:
			zp.write_file(JSON.stringify(v).to_utf8_buffer())
		elif typeof(v) == TYPE_PACKED_BYTE_ARRAY:
			zp.write_file(v)
		else:
			zp.write_file(str(v).to_utf8_buffer())
		zp.close_file()
	zp.close()
	return p


func _manifest(id: String, version := "1.0.0", extra := {}) -> Dictionary:
	var m := {"id": id, "name": id.capitalize(), "version": version, "game_version": Saves.game_version(), "requires": [], "load_after": [], "capabilities": []}
	m.merge(extra, true)
	return m


func _rules(id: String, extra := {}) -> Dictionary:
	var r := {"id": id, "name": "Test Rules", "mode": "standard", "format": "duel", "teams": 2, "players": [2, 2], "rounds": 1, "round_time": 77}
	r.merge(extra, true)
	return r


func _base_creature() -> String:
	var ids := Content.playable_creatures()
	return str(ids[0]) if not ids.is_empty() else "dev_biped"


func test_bundled_examples_validate_and_load() -> void:
	var ids := Mods.available.map(func(i): return str(i["id"]))
	for want in ["moon_rules", "rust_bucket", "stoke_variants"]:
		check(want in ids, "example %s is listed" % want)
	for info in Mods.available:
		check(info["errors"].is_empty(), "%s has no errors: %s" % [info["id"], str(info["errors"])])
		check_eq(str(info["kind"]), "example")
	check(Mods.set_enabled("moon_rules", true)["ok"], "enable moon_rules")
	check(Mods.set_enabled("rust_bucket", true)["ok"], "enable rust_bucket")
	var st := Mods.set_enabled("stoke_variants", true)
	check(st["ok"], "enable stoke_variants")
	Mods.apply()
	check_eq(Mods.load_order, ["moon_rules", "rust_bucket", "stoke_variants"], "deterministic order (no deps -> by id)")
	check(not Content.get_entry("rules", "moon_rules:moon_brawl").is_empty(), "mod rules loaded")
	check(not Content.get_entry("playlists", "moon_rules:moon_night").is_empty(), "mod playlist loaded")
	var a := Content.arena("rust_bucket:the_drain")
	check(a != null and a.base == "square", "mod arena loaded and parsed")
	if a:
		check_eq(a.markers_of("goal").size(), 2, "arena mode markers")
	if not Content.creature_entry("f_stoke").is_empty():
		var c := Content.creature("stoke_variants:overheated_stoke")
		var base_ok := Content.creature("f_stoke").is_valid()
		check(c != null and (c.is_valid() or not base_ok), "extended creature is as valid as its base: %s" % (str(c.errors) if c else "null"))
		if c:
			check_eq(c.title, "Overheated")
			check_eq(c.body.segments.size(), Content.creature("f_stoke").body.segments.size(), "body inherited from f_stoke")
	else:
		check((Mods.load_report.get("stoke_variants", []) as Array).size() > 0, "missing base creature is reported, not fatal")
	check(Content.origin_of("rules", "moon_rules:moon_brawl") == "moon_rules", "origin recorded")


func test_install_upgrade_downgrade_remove_and_recover() -> void:
	var v1 := _archive("sample_v1.critmod", {"manifest.json": _manifest("sample_mod", "1.0.0"),
		"rules/r.json": _rules("sample_mod:quick", {"round_time": 40})})
	var res := Mods.import_package(v1)
	check(res["ok"], "install: %s" % res["message"])
	check(Mods.set_enabled("sample_mod", true)["ok"], "enable")
	Mods.apply()
	check_eq(int(Content.get_entry("rules", "sample_mod:quick").get("round_time", 0)), 40, "v1 content")
	# upgrade keeps the enabled state and swaps content
	var v2 := _archive("sample_v2.zip", {"sample/manifest.json": _manifest("sample_mod", "1.1.0"),
		"sample/rules/r.json": _rules("sample_mod:quick", {"round_time": 55})})
	res = Mods.import_package(v2)
	check(res["ok"] and str(res["message"]).begins_with("Upgraded"), "upgrade: %s" % res["message"])
	check(Mods.is_enabled("sample_mod"), "still enabled after upgrade")
	check_eq(str(Mods.info_of("sample_mod")["version"]), "1.1.0")
	check_eq(int(Content.get_entry("rules", "sample_mod:quick").get("round_time", 0)), 55, "v2 content (single top-level folder layout)")
	# downgrade needs confirmation
	res = Mods.import_package(v1)
	check(not res["ok"] and bool(res.get("downgrade", false)), "downgrade asks first")
	res = Mods.import_package(v1, true)
	check(res["ok"] and str(res["message"]).begins_with("Downgraded"), "confirmed downgrade")
	# removal: moved aside, id kept in the set and reported missing, content gone
	check(Mods.uninstall("sample_mod"), "uninstall")
	check(Mods.info_of("sample_mod").is_empty(), "no longer installed")
	check("sample_mod" in Mods.missing_in_active(), "reported as missing from the active set")
	check(Content.get_entry("rules", "sample_mod:quick").is_empty(), "content unloaded")
	check(DirAccess.dir_exists_absolute(Mods.mods_dir().path_join(".removed")), "removed package kept aside, not deleted")
	# reinstalling restores the setup without re-enabling by hand
	res = Mods.import_package(v2)
	check(res["ok"], "reinstall")
	check(not Content.get_entry("rules", "sample_mod:quick").is_empty(), "restored on reinstall")
	# export/share round trip
	var out := Mods.export_package("sample_mod", dir.path_join("share"))
	check(out != "" and FileAccess.file_exists(out), "exported archive")
	check(Mods.inspect_archive(out)["errors"].is_empty(), "exported archive re-validates")


func test_unsafe_and_invalid_packages_are_rejected() -> void:
	var cases := {
		"traversal": {"manifest.json": _manifest("evil_one"), "../outside.json": {"id": "x"}},
		"absolute": {"manifest.json": _manifest("evil_two"), "C:/windows/x.json": {"id": "x"}},
		"script": {"manifest.json": _manifest("evil_three"), "rules/hack.gd": "extends Node"},
		"binary": {"manifest.json": _manifest("evil_four"), "bin/tool.exe": PackedByteArray([77, 90])},
		"scripts_cap": {"manifest.json": _manifest("evil_five", "1.0.0", {"capabilities": ["scripts"]})},
		"bad_id": {"manifest.json": _manifest("Bad Id!")},
		"future_game": {"manifest.json": _manifest("too_new", "1.0.0", {"game_version": "9.0.0"})},
		"future_api": {"manifest.json": _manifest("too_new_api", "1.0.0", {"api": 99})},
		"no_manifest": {"rules/r.json": _rules("x:y")},
		"bad_json": {"manifest.json": "{ nope"},
		"client_only_gameplay": {"manifest.json": _manifest("sneaky", "1.0.0", {"client_only": true}), "rules/r.json": _rules("sneaky:r")},
	}
	for k in cases:
		var p := _archive("%s.critmod" % k, cases[k])
		var r := Mods.import_package(p)
		check(not r["ok"], "%s must be rejected" % k)
		check(str(r["message"]).length() > 10, "%s: actionable message (%s)" % [k, r["message"]])
	check(Mods.available.filter(func(i): return str(i["kind"]) == "archive").is_empty(), "nothing rejected was installed")
	# zip bomb: sizes come from the central directory, nothing is inflated
	Mods.limits["file_bytes"] = 4096
	var big := PackedByteArray()
	big.resize(200000)
	var bomb := _archive("bomb.critmod", {"manifest.json": _manifest("bomb_mod"), "rules/big.json": big})
	var info := Mods.inspect_archive(bomb)
	check(not info["errors"].is_empty() and str(info["errors"]).contains("per-file limit"), "oversized entry rejected from the directory: %s" % str(info["errors"]))
	# not an archive at all
	var junk := dir.path_join("junk.critmod")
	var f := FileAccess.open(junk, FileAccess.WRITE)
	f.store_string("definitely not a zip")
	f.close()
	check(not Mods.import_package(junk)["ok"], "garbage file rejected")
	# a mod whose entries do not use its own id prefix is reported by the loader (not fatal)
	var unprefixed := _archive("unprefixed.critmod", {"manifest.json": _manifest("loose_ids"), "rules/r.json": _rules("plain_id")})
	check(Mods.import_package(unprefixed)["ok"], "manifest itself is fine")
	Mods.set_enabled("loose_ids", true)
	Mods.apply()
	check(Content.get_entry("rules", "plain_id").is_empty(), "unprefixed entry not loaded")
	var report := "
".join(PackedStringArray(Mods.load_report.get("loose_ids", [])))
	check(report.contains("must start with 'loose_ids:'"), "actionable id error: %s" % report)


func test_dependencies_order_cycles_and_versions() -> void:
	var mk := func(id: String, req: Array, after: Array) -> void:
		var p := _archive("%s.critmod" % id, {"manifest.json": _manifest(id, "1.0.0", {"requires": req, "load_after": after}),
			"rules/r.json": _rules("%s:r" % id)})
		Mods.import_package(p)
	mk.call("base_pack", [], [])
	mk.call("addon_pack", [{"id": "base_pack", "version": "1.0.0"}], [])
	mk.call("late_pack", [], ["addon_pack"])
	mk.call("orphan_pack", [{"id": "not_there"}], [])
	mk.call("cycle_one", [{"id": "cycle_two"}], [])
	mk.call("cycle_two", [{"id": "cycle_one"}], [])
	mk.call("picky_pack", [{"id": "base_pack", "version": "2.0.0"}], [])
	var r := Mods.resolve_order(["late_pack", "addon_pack", "base_pack", "orphan_pack", "cycle_one", "cycle_two", "picky_pack"])
	check_eq(r["order"], ["base_pack", "addon_pack", "late_pack"], "requires + load_after order")
	check(r["errors"].has("orphan_pack") and str(r["errors"]["orphan_pack"]).contains("not installed"), "missing dependency explained")
	check(r["errors"].has("cycle_one") and r["errors"].has("cycle_two"), "cycle detected")
	check(r["errors"].has("picky_pack") and str(r["errors"]["picky_pack"]).contains("2.0.0"), "version requirement explained")
	# the same inputs in another order give the same result
	var r2 := Mods.resolve_order(["picky_pack", "cycle_two", "base_pack", "late_pack", "orphan_pack", "addon_pack", "cycle_one"])
	check_eq(r2["order"], r["order"], "order independent of input order")
	# enabling a mod enables what it requires; disabling a dependency disables dependents
	var en := Mods.set_enabled("addon_pack", true)
	check(en["ok"] and "base_pack" in en["changed"], "dependency auto-enabled: %s" % str(en))
	var dis := Mods.set_enabled("base_pack", false)
	check("addon_pack" in dis["changed"], "dependent disabled with its dependency")


func test_core_override_needs_consent_and_changes_hash() -> void:
	var before := Content.content_hash()
	var dur := _rules("duel", {"round_time": 33, "override": true, "name": "Duel (modded)"})
	var p := _archive("ovr.critmod", {"manifest.json": _manifest("duel_tweak", "1.0.0", {"capabilities": ["replaces_core"]}), "rules/duel.json": dur})
	check(Mods.import_package(p)["ok"], "installed")
	var r := Mods.set_enabled("duel_tweak", true)
	check(not r["ok"] and "replaces_core" in r["needs_consent"], "consent requested first")
	Mods.grant_consent("duel_tweak", ["replaces_core"])
	check(Mods.set_enabled("duel_tweak", true)["ok"], "enabled after consent")
	Mods.apply()
	check_eq(int(Content.get_entry("rules", "duel").get("round_time", 0)), 33, "core preset overridden")
	check(Content.content_hash() != before, "gameplay content hash changed")
	Mods.set_enabled("duel_tweak", false)
	Mods.apply()
	check_eq(Content.content_hash(), before, "hash restored after disabling")


func test_client_only_mods_do_not_affect_compatibility() -> void:
	var before := Content.content_hash()
	var p := _archive("cosmetic.critmod", {"manifest.json": _manifest("cosmetic_lines", "1.0.0", {"client_only": true}),
		"announcer/lines.json": {"id": "cosmetic_lines:extra", "lines": {"ko": ["Lights out, folks!"]}}})
	check(Mods.import_package(p)["ok"], "presentation mod installs")
	Mods.set_enabled("cosmetic_lines", true)
	Mods.apply()
	check_eq(Content.content_hash(), before, "presentation mod leaves the gameplay hash alone")
	var core_only := [{"id": "core", "version": str(Content.packages[0]["version"]), "hash": "", "client_only": false}]
	check(Mods.compare(core_only)["compatible"], "client-only mod never blocks joining")
	# a gameplay mod on our side only -> 'extra'; on theirs only -> 'missing'
	var g := _archive("gp.critmod", {"manifest.json": _manifest("gameplay_bits"), "rules/r.json": _rules("gameplay_bits:r")})
	Mods.import_package(g)
	Mods.set_enabled("gameplay_bits", true)
	Mods.apply()
	var c := Mods.compare(core_only)
	check(not c["compatible"] and "gameplay_bits" in c["extra"], "extra gameplay mod reported")
	var theirs := Mods.fingerprint().duplicate(true)
	theirs.append({"id": "server_only", "version": "2.0.0", "hash": "x", "client_only": false})
	var c2 := Mods.compare(theirs)
	check("server_only" in c2["missing"] and str(c2["messages"]).contains("Missing mod: server_only"), "missing mod named with version")
	var req := Mods.check_requirements(theirs)
	check(not req["ok"] and "server_only" in req["missing"] and str(req["message"]).contains("nothing was changed"), "save requirement check is non-destructive")


func test_creature_extends_merges_and_validates() -> void:
	var base := _base_creature()
	var base_def := Content.creature(base)
	var drop_slot := ""
	for slot in ["taunt", "finisher", "dash_attack", "pummel", "heavy_charged"]:
		if base_def.moves.has(slot) and not slot in base_def.light_string:
			drop_slot = slot
			break
	var over := {"id": "ext_test:variant", "extends": base, "name": "Variant", "stats": {"power": 1.2},
		"moves": {"heavy": {"damage": 21}}, "art": {"palette": {"primary": "#123456"}}}
	if drop_slot != "":
		over["moves"][drop_slot] = null
	var bad := {"id": "ext_test:broken", "extends": "no_such_creature", "name": "Broken"}
	var loop_a := {"id": "ext_test:loop_a", "extends": "ext_test:loop_b", "name": "A"}
	var loop_b := {"id": "ext_test:loop_b", "extends": "ext_test:loop_a", "name": "B"}
	var p := _archive("ext.critmod", {"manifest.json": _manifest("ext_test"), "creatures/v.json": {"items": [over, bad, loop_a, loop_b]}})
	check(Mods.import_package(p)["ok"], "installed")
	Mods.set_enabled("ext_test", true)
	Mods.apply()
	var c := Content.creature("ext_test:variant")
	check(c != null and c.is_valid(), "variant valid")
	if c:
		check_eq(c.display_name, "Variant")
		check_near(float(c.moves["heavy"].damage), 21.0, 0.001, "overridden move field")
		check_near(float(c.moves["heavy"].duration), float(base_def.moves["heavy"].duration), 0.001, "other move fields inherited")
		check_eq(c.body.segments.size(), base_def.body.segments.size(), "body inherited")
		if drop_slot != "":
			check(not c.moves.has(drop_slot), "null removes slot %s" % drop_slot)
	check(Content.creature_entry("ext_test:broken").is_empty(), "unknown parent rejected")
	check(Content.creature_entry("ext_test:loop_a").is_empty(), "cycle rejected")
	check(str(Mods.load_report.get("ext_test", [])).contains("circular"), "cycle explained")


func test_rule_hooks_mods_and_gravity_reach_fighters() -> void:
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var c := Content.creature(_base_creature())
	sim.setup({"arena": Content.arena("the_gullet"), "seed": 5, "mode": ModeRegistry.create("standard"),
		"rules": _rules("x", {"gravity_mult": 0.5, "fighter_mods": {"damage": 1.5, "no_grabs": true},
			"fighter_hooks": [{"id": "rule_hook", "on": "hit_dealt", "do": [{"type": "hype", "amount": 1}]}]}),
		"fighters": [{"creature": c, "team": 0, "source": null}, {"creature": c, "team": 1, "source": null}]})
	check_near(sim.gravity, 9.81 * 0.5, 0.001, "rules gravity")
	check_near(float(PhysicsServer3D.area_get_param(sim.get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY)), 9.81 * 0.5, 0.01, "world gravity applied")
	check_near(sim.fighters[0].rig.gravity, 9.81 * 0.5, 0.001, "rig support uses the same gravity")
	check_near(float(sim.fighters[0].mods["damage"]), 1.5, 0.001, "fighter_mods multiply")
	check(bool(sim.fighters[1].mods.get("no_grabs", false)), "fighter_mods flags")
	check(sim.fighters[0].hooks.list.any(func(h): return str(h.get("id", "")) == "rule_hook"), "rule hook installed")
	# fighters stay upright and grounded under low gravity
	await step_sim(sim, 2.0)
	for f in sim.fighters:
		check(f.rig.grounded and f.pos().y < 2.0, "fighter %d grounded under low gravity (y=%.2f)" % [f.index, f.pos().y])
