extends TestCase
## ARN-02/05: the editor's command stack round-trips undo/redo exactly; layouts save/load
## (versioned, with format-1 migration); packages export/import round trip and malicious zips
## (path traversal, absolute paths, oversized entries, bad manifests, tampering, zip bombs)
## are rejected before anything is installed.


func _model(id := "layout_crusher_king") -> ArenaEditModel:
	var d := Content.get_entry("arenas", id).duplicate(true)
	d.erase("_package")
	d.erase("_file")
	return ArenaEditModel.from_dict(d)


func _canon(m: ArenaEditModel) -> String:
	return JSON.stringify(ArenaDef.canonical(m.to_dict()), "", true)


func test_command_stack_undo_redo_round_trip() -> void:
	var m := _model()
	var st := ArenaEditCommands.Stack.new(m)
	var states: Array = [_canon(m)]
	# add two props
	var a := m.make_item("prop_crate", Vector3(1, 0, 3))
	var b := m.make_item("prop_fire_barrel", Vector3(-2, 0, -3))
	st.execute(ArenaEditCommands.AddItems.new([a, b]))
	states.append(_canon(m))
	# move + rotate one
	var before := m.get_item(int(a["uid"])).duplicate(true)
	var after := before.duplicate(true)
	after["pos"] = Vector3(1.5, 0, 2.5)
	after["yaw"] = deg_to_rad(45.0)
	st.execute(ArenaEditCommands.ModifyItems.new([[a["uid"], before, after]], "Move"))
	states.append(_canon(m))
	# change a spawn's team, the boundary and the supported modes
	var spawn_uid := -1
	for it in m.items:
		if str(it["type"]) == "marker_spawn":
			spawn_uid = int(it["uid"])
			break
	var sb := m.get_item(spawn_uid).duplicate(true)
	var sa := sb.duplicate(true)
	sa["team"] = 1
	st.execute(ArenaEditCommands.ModifyItems.new([[spawn_uid, sb, sa]], "Team"))
	states.append(_canon(m))
	st.execute(ArenaEditCommands.SetField.new("size", m.size, Vector2(10.5, 10.5)))
	states.append(_canon(m))
	st.execute(ArenaEditCommands.SetField.new("modes", m.modes, ["ffa"]))
	states.append(_canon(m))
	st.execute(ArenaEditCommands.SetField.new("removed_builtins", m.removed_builtins, ["scrap_ne"]))
	states.append(_canon(m))
	# delete the first prop and something from the middle of the list
	st.execute(ArenaEditCommands.RemoveItems.new(m, [int(m.items[0]["uid"]), int(b["uid"])]))
	states.append(_canon(m))
	# whole-document replacement (base change)
	var fresh := ArenaEditModel.new_from_base("rooftop")
	st.execute(ArenaEditCommands.SetState.new(m.snapshot(), fresh.snapshot(), "New layout"))
	states.append(_canon(m))
	check_eq(m.base, "rooftop", "base replaced")
	for k in range(states.size() - 1, 0, -1):
		check(st.can_undo(), "can undo step %d" % k)
		st.undo()
		check_eq(_canon(m), states[k - 1], "undo restores state %d" % (k - 1))
	check(not st.can_undo(), "fully undone")
	for k2 in range(1, states.size()):
		st.redo()
		check_eq(_canon(m), states[k2], "redo reapplies state %d" % k2)
	check(not st.can_redo(), "fully redone")
	# a new command after undo drops the redo branch
	st.undo()
	st.execute(ArenaEditCommands.SetField.new("name", m.name, "Branch"))
	check(not st.can_redo(), "redo history cleared by a new edit")


func test_stack_is_bounded_and_tracks_dirty() -> void:
	var m := _model("layout_gullet_classic")
	var st := ArenaEditCommands.Stack.new(m)
	st.limit = 10
	for i in 25:
		st.execute(ArenaEditCommands.SetField.new("name", m.name, "N%d" % i))
	check_eq(st.done.size(), 10, "history bounded")
	st.mark_clean()
	check(not st.is_dirty(), "clean after save")
	st.execute(ArenaEditCommands.SetField.new("name", m.name, "X"))
	check(st.is_dirty(), "dirty after an edit")
	st.undo()
	check(not st.is_dirty(), "clean again after undoing back to the save point")


func test_save_load_round_trip_and_migration() -> void:
	var dir := temp_dir("arena_saves")
	var m := _model("layout_unit_pit")
	m.id = "user:pit_copy"
	m.name = "Pit Copy"
	var sv := ArenaLibrary.save_layout(m.to_dict(true), "", dir)
	check(bool(sv["ok"]), "saved: %s" % sv["error"])
	var ld := ArenaLibrary.load_layout(str(sv["path"]))
	check(bool(ld["ok"]), "loaded: %s" % ld["error"])
	var m2 := ArenaEditModel.from_dict(ld["data"])
	check_eq(_canon(m2), _canon(m), "layout survives save/load")
	check(ArenaLibrary.resolve("user:pit_copy", dir) != null, "saved layouts resolve for matches")
	var listed := ArenaLibrary.list_saved(dir)
	check(listed.size() >= 1 and str(listed[0]["id"]) == "user:pit_copy", "listed")
	# a format-1 file (legacy shape base + spawns array) migrates on load
	var legacy := {"id": "user:old", "name": "Old Cage", "base": "octagon", "radius": 5.5, "spawns": [[0, -2, 0], [0, 2, 180]], "props": [{"type": "crate", "pos": [2, 0, 2]}]}
	var p := dir.path_join("old.arena.json")
	check_eq(Saves.write_json(p, ArenaLibrary.KIND, 1, legacy), OK, "wrote v1")
	var ld2 := ArenaLibrary.load_layout(p)
	check(bool(ld2["ok"]) and bool(ld2["migrated"]), "v1 migrated: %s" % ld2["error"])
	var a := ArenaDef.from_dict(ld2["data"])
	check_eq(a.base, "gullet", "octagon -> gullet")
	check_eq(a.markers_of("spawn").size(), 2, "spawns -> spawn markers")
	check_eq(str(a.props[0]["type"]), "prop_crate", "legacy prop names mapped")
	# corrupt files are reported, never crash
	var bad := dir.path_join("bad.arena.json")
	var f := FileAccess.open(bad, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	check(not bool(ArenaLibrary.load_layout(bad)["ok"]), "corrupt layout rejected")


func test_package_export_import_round_trip() -> void:
	var dir := temp_dir("arena_pkg")
	var install := temp_dir("arena_pkg_install")
	var layouts := []
	for id in ["layout_glandco_showcase", "layout_drydock_pitch"]:
		var d := Content.get_entry("arenas", id).duplicate(true)
		d.erase("_package")
		d.erase("_file")
		layouts.append(d)
	var zip := dir.path_join("showcase.zip")
	var ex := ArenaPackage.export_package(layouts, zip, {"id": "showcase_pack", "name": "Showcase Pack"})
	check(bool(ex["ok"]), "exported: %s" % ex.get("error", ""))
	var im := ArenaPackage.import_package(zip, install)
	check(bool(im["ok"]), "imported: %s" % str(im["errors"]))
	check_eq((im["arenas"] as Array).size(), 2, "both arenas")
	check_eq(str(im["hash"]), str(ex["hash"]), "package hash stable across export/import")
	check_eq((im["installed"] as Array).size(), 2, "installed as saved layouts")
	for d2 in im["arenas"]:
		var orig := Content.arena(str(d2["id"]))
		check_eq(ArenaDef.from_dict(d2).content_hash(), orig.content_hash(), "%s content hash preserved" % d2["id"])
	check(ArenaLibrary.resolve("layout_drydock_pitch", install) != null, "playable after import")


func _zip(path: String, files: Dictionary) -> void:
	var zp := ZIPPacker.new()
	zp.open(path)
	for n in files:
		zp.start_file(n)
		var v = files[n]
		zp.write_file(v if v is PackedByteArray else str(v).to_utf8_buffer())
		zp.close_file()
	zp.close()


func _valid_files() -> Dictionary:
	var dir := temp_dir("arena_pkg_src")
	var d := Content.get_entry("arenas", "layout_crusher_king").duplicate(true)
	d.erase("_package")
	d.erase("_file")
	var zip := dir.path_join("ok.zip")
	ArenaPackage.export_package([d], zip, {"id": "king_pack"})
	var zr := ZIPReader.new()
	zr.open(zip)
	var out := {}
	for n in zr.get_files():
		out[n] = zr.read_file(n)
	zr.close()
	return out


func _rejects(files: Dictionary, why: String, expect := "") -> void:
	var dir := temp_dir("arena_pkg_bad")
	var zip := dir.path_join("bad_%d.zip" % Time.get_ticks_usec())
	_zip(zip, files)
	var install := temp_dir("arena_pkg_bad_install")
	var before := ArenaLibrary.list_saved(install).size()
	var r := ArenaPackage.import_package(zip, install)
	check(not bool(r["ok"]), "%s is rejected" % why)
	check_eq(ArenaLibrary.list_saved(install).size(), before, "%s installs nothing" % why)
	if expect != "":
		check(" ".join(r["errors"]).contains(expect), "%s error mentions '%s': %s" % [why, expect, str(r["errors"])])


func test_malicious_packages_are_rejected() -> void:
	var good := _valid_files()
	check(good.has("manifest.json"), "fixture package built")
	# path traversal and absolute paths
	var t1 := good.duplicate()
	t1["../../evil.json"] = "{}"
	_rejects(t1, "path traversal", "unsafe path")
	var t2 := good.duplicate()
	t2["/etc/passwd"] = "x"
	_rejects(t2, "absolute path", "unsafe path")
	var t3 := good.duplicate()
	t3["arenas\\win.json"] = "{}"
	_rejects(t3, "backslash path", "unsafe path")
	var t4 := good.duplicate()
	t4["scripts/run.gd"] = "extends Node"
	_rejects(t4, "unexpected file type", "unexpected file")
	# oversized entry and zip bomb (1.2 MB of zeros compresses ~1000:1)
	var t6 := good.duplicate()
	var bomb := PackedByteArray()
	bomb.resize(1200 * 1024)
	bomb.fill(0)
	t6["preview.png"] = bomb
	_rejects(t6, "zip bomb / oversized preview", "")
	var t7 := good.duplicate()
	var huge_json := "{\"pad\": \"" + "x".repeat(270 * 1024) + "\"}"
	for n in t7.keys():
		if str(n).begins_with("arenas/"):
			t7[n] = huge_json
	_rejects(t7, "oversized arena json", "too large")
	# manifests: missing, not JSON, wrong format, missing fields
	var t8 := good.duplicate()
	t8.erase("manifest.json")
	_rejects(t8, "missing manifest", "manifest.json is missing")
	var t9 := good.duplicate()
	t9["manifest.json"] = "{ nope"
	_rejects(t9, "manifest not JSON", "not valid JSON")
	var man: Dictionary = JSON.parse_string((good["manifest.json"] as PackedByteArray).get_string_from_utf8())
	var m1 := man.duplicate(true)
	m1["format"] = "something-else"
	var t10 := good.duplicate()
	t10["manifest.json"] = JSON.stringify(m1)
	_rejects(t10, "wrong package format", "not an arena package")
	var m2 := man.duplicate(true)
	m2.erase("version")
	m2["id"] = "Bad Id!"
	var t11 := good.duplicate()
	t11["manifest.json"] = JSON.stringify(m2)
	_rejects(t11, "manifest failing its schema", "manifest")
	# tampering: arena edited after the manifest was written
	var t12 := good.duplicate()
	for n2 in t12.keys():
		if str(n2).begins_with("arenas/"):
			var d: Dictionary = JSON.parse_string((t12[n2] as PackedByteArray).get_string_from_utf8())
			d["props"].append({"type": "prop_fire_barrel", "pos": [0, 0, 0]})
			t12[n2] = JSON.stringify(d)
	_rejects(t12, "tampered arena", "sha256")
	# an arena that fails the schema even though the manifest hash matches
	var bad_arena := {"id": "Bad Id", "name": "", "base": "volcano"}
	var text := JSON.stringify(bad_arena)
	var m3 := man.duplicate(true)
	m3["arenas"][0]["sha256"] = text.sha256_text()
	var t13 := good.duplicate()
	for n3 in t13.keys():
		if str(n3).begins_with("arenas/"):
			t13[n3] = text
	t13["manifest.json"] = JSON.stringify(m3)
	_rejects(t13, "schema-invalid arena", "")
	# too many entries
	var t14 := good.duplicate()
	for i in 20:
		t14["arenas/extra_%d.json" % i] = "{}"
	_rejects(t14, "too many entries", "too many files")
