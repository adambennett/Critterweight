extends TestCase
## LAB-07 / SAV-02: policy files — exact save/load round trip, strict rejection of corrupted,
## tampered, incompatible, malformed and oversized files, backup recovery, and the library
## operations (save, rename, export, import with id collision, delete). Loading never runs code.

var dir := ""


func before_each() -> void:
	dir = temp_dir("lab_policy_io_%d" % Time.get_ticks_usec())
	PolicyLibrary.user_dir_override = dir.path_join("library")
	PolicyLibrary.clear_cache()


func after_each() -> void:
	PolicyLibrary.user_dir_override = ""
	PolicyLibrary.clear_cache()


func _policy(seed_value := 3) -> PolicyData:
	var p := PolicyData.create_new("dev_biped", PackedInt32Array([16, 8]), "tanh", seed_value)
	p.id = "test_policy_%d" % seed_value
	p.name = "Test Policy"
	p.training = {"approach": "es", "episodes": 123, "metrics": {"reward": 0.03, "curve": [0.1, 1.0 / 3.0, 42.68999862]}}
	return p


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _dict(p: PolicyData) -> Dictionary:
	return JSON.parse_string(PolicyIO.to_text(p))


## Re-signs a modified policy dictionary so only the targeted validation can fail.
func _resign(d: Dictionary) -> Dictionary:
	d["checksum"] = PolicyData.canonical_hash(d)
	return d


func test_round_trip_is_exact() -> void:
	var p := _policy()
	var path := dir.path_join("a.policy.json")
	check_eq(PolicyIO.write_file(path, p), OK, "write")
	var r := PolicyIO.read_file(path)
	check(r["ok"], "read back: %s" % "; ".join(r["errors"]))
	var q: PolicyData = r["policy"]
	check(q.net.params == p.net.params, "weights bit-exact")
	check_eq(q.id, p.id)
	check_eq(q.name, p.name)
	check_eq(q.creature, "dev_biped")
	check(q.net.hidden == p.net.hidden, "architecture")
	check_eq(q.act_mode, p.act_mode)
	check_eq(int(q.training["episodes"]), 123)
	var x := PackedFloat32Array()
	x.resize(PolicyObs.SIZE)
	x[3] = 0.5
	x[40] = -0.25
	check(q.net.forward(x) == p.net.forward(x), "identical behaviour after loading")
	# writing the loaded policy again is stable (floats in metadata survive repeated round trips)
	check_eq(PolicyIO.write_file(path, q), OK, "second write")
	check(PolicyIO.read_file(path)["ok"], "second read")
	check(FileAccess.file_exists(path + ".bak"), "previous version kept as .bak")


func test_rejects_damaged_files() -> void:
	var p := _policy()
	var good := PolicyIO.to_text(p)
	var cases := {
		"truncated": good.substr(0, good.length() / 2),
		"not json": "this is not a policy",
		"empty": "",
		"array": "[1, 2, 3]",
		"other format": JSON.stringify({"format": "something.else", "format_version": 1}),
	}
	# one flipped character inside the base64 weights
	var d := _dict(p)
	var data: String = d["weights"]["data"]
	var mid := data.length() / 2
	d["weights"]["data"] = data.substr(0, mid) + ("A" if data[mid] != "A" else "B") + data.substr(mid + 1)
	cases["flipped weight byte"] = JSON.stringify(d)
	var d2 := _dict(p)
	d2["name"] = "Edited by hand"
	cases["edited without checksum update"] = JSON.stringify(d2)
	for k in cases:
		var path := dir.path_join("bad_%s.policy.json" % str(k).replace(" ", "_"))
		_write_text(path, str(cases[k]))
		var r := PolicyIO.read_one(path)
		check(not r["ok"], "%s must be rejected" % k)
		check(not (r["errors"] as PackedStringArray).is_empty(), "%s gives a reason" % k)


func test_rejects_incompatible_or_malformed_contents() -> void:
	var p := _policy()
	var mutations := {
		"newer format": func(d: Dictionary) -> void: d["format_version"] = 99,
		"old observation contract": func(d: Dictionary) -> void: d["obs"]["version"] = "obs_v0",
		"observation size": func(d: Dictionary) -> void: d["obs"]["size"] = 64,
		"action contract": func(d: Dictionary) -> void: d["act"]["version"] = "act_v9",
		"action heads": func(d: Dictionary) -> void: d["act"]["heads"] = [9, 13],
		"weight count": func(d: Dictionary) -> void: d["weights"]["count"] = 10,
		"architecture inputs": func(d: Dictionary) -> void: d["arch"]["inputs"] = 64,
		"too wide": func(d: Dictionary) -> void: d["arch"]["hidden"] = [100000],
		"too deep": func(d: Dictionary) -> void: d["arch"]["hidden"] = [8, 8, 8, 8, 8, 8],
		"unknown activation": func(d: Dictionary) -> void: d["arch"]["activation"] = "evil()",
		"unknown arch type": func(d: Dictionary) -> void: d["arch"]["type"] = "gdscript",
		"bad id": func(d: Dictionary) -> void: d["id"] = "../../escape",
		"bad mode": func(d: Dictionary) -> void: d["act"]["mode"] = "exec",
		"huge metadata": func(d: Dictionary) -> void: d["training"] = {"blob": "x".repeat(300 * 1024)},
		"weights not base64": func(d: Dictionary) -> void: d["weights"]["data"] = "!!!!" + str(d["weights"]["data"]).substr(4),
	}
	for k in mutations:
		var d := _dict(p)
		(mutations[k] as Callable).call(d)
		var r := PolicyData.from_dict(_resign(d))
		check(not r["ok"], "%s must be rejected" % k)
	# NaN / infinite weights (correctly encoded and signed) are rejected too
	var w := p.net.params.duplicate()
	w[5] = NAN
	w[9] = INF
	var d3 := _dict(p)
	d3["weights"]["data"] = Marshalls.raw_to_base64(w.to_byte_array())
	var r3 := PolicyData.from_dict(_resign(d3))
	check(not r3["ok"], "non-finite weights rejected")
	check("; ".join(r3["errors"]).contains("NaN"), "reason mentions NaN")
	# a policy for another fighter is refused where a specific creature is expected
	var r4 := PolicyData.from_dict(_dict(p), "some_other_fighter")
	check(not r4["ok"], "creature mismatch rejected")


func test_rejects_oversized_file_before_parsing() -> void:
	var path := dir.path_join("huge.policy.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{\"pad\": \"")
	var chunk := "0123456789".repeat(10000)
	for k in 45:
		f.store_string(chunk)
	f.store_string("\"}")
	f.close()
	var r := PolicyIO.read_one(path)
	check(not r["ok"], "oversized file rejected")
	check("; ".join(r["errors"]).contains("too large"), "size limit reported: %s" % "; ".join(r["errors"]))


## Unknown fields are inert data: nothing is instantiated or executed while loading.
func test_loading_never_executes_code() -> void:
	var p := _policy()
	var d := _dict(p)
	d["script"] = "res://src/test/lab/test_policy_io.gd"
	d["on_load"] = "OS.execute(\"calc.exe\")"
	d["training"]["object"] = "Object(Node,\"script\":Resource(\"res://evil.gd\"))"
	var r := PolicyData.from_dict(_resign(d))
	check(r["ok"], "extra fields are ignored, not executed: %s" % "; ".join(r["errors"]))
	var q: PolicyData = r["policy"]
	check_eq(typeof(q.training["object"]), TYPE_STRING, "object-looking text stays a plain string")
	check(q.get_script() == PolicyData, "a policy is always plain PolicyData")


func test_recovers_from_backup_when_main_file_is_damaged() -> void:
	var path := dir.path_join("rec.policy.json")
	var p := _policy()
	check_eq(PolicyIO.write_file(path, p), OK)
	p.name = "Second save"
	check_eq(PolicyIO.write_file(path, p), OK)
	_write_text(path, "{ damaged")
	var r := PolicyIO.read_file(path)
	check(r["ok"], "recovered from the .bak copy")
	check(("; ".join(r["warnings"])).contains("recovered"), "recovery is reported")
	check_eq((r["policy"] as PolicyData).name, "Test Policy", "the previous good version")


func test_library_operations() -> void:
	var p := _policy(5)
	p.id = ""
	check_eq(PolicyLibrary.save(p), OK, "save")
	var id := p.id
	check(id.begins_with("u_dev_biped_"), "generated id %s" % id)
	check(PolicyLibrary.get_policy(id) != null, "lookup by id")
	check_eq(PolicyLibrary.compatibility(PolicyLibrary.get_policy(id), "dev_biped"), "", "usable for its fighter")
	check(PolicyLibrary.compatibility(PolicyLibrary.get_policy(id), "other") != "", "not for another fighter")
	check_eq(PolicyLibrary.rename(id, "Renamed  Bot"), OK, "rename")
	PolicyLibrary.clear_cache()
	check_eq(PolicyLibrary.get_policy(id).name, "Renamed  Bot", "rename persisted")
	var listed := false
	for s: Dictionary in PolicyLibrary.list("dev_biped"):
		if str(s.get("id", "")) == id and bool(s["valid"]):
			listed = true
	check(listed, "listed in the library")
	var exported := dir.path_join("export").path_join("copy")
	DirAccess.make_dir_recursive_absolute(exported.get_base_dir())
	check_eq(PolicyLibrary.export_to(id, exported), OK, "export")
	check(FileAccess.file_exists(exported + PolicyIO.EXT), "export adds the extension")
	var imp := PolicyLibrary.import_from(exported + PolicyIO.EXT)
	check(imp["ok"], "import: %s" % "; ".join(imp["errors"]))
	check(str(imp["id"]) != id, "a colliding id is re-assigned on import")
	check(("; ".join(imp["warnings"])).contains("already exists"), "collision explained")
	_write_text(dir.path_join("broken.policy.json"), "{\"format\": \"critterweight.policy\"}")
	var bad := PolicyLibrary.import_from(dir.path_join("broken.policy.json"))
	check(not bad["ok"], "invalid import refused")
	check(not (bad["errors"] as PackedStringArray).is_empty(), "with errors to show")
	check_eq(PolicyLibrary.delete(str(imp["id"])), OK, "delete")
	check(PolicyLibrary.get_policy(str(imp["id"])) == null, "deleted policy is gone")
	check(PolicyLibrary.get_policy("no_such_policy") == null and PolicyLibrary.last_error("no_such_policy") != "", "missing id explained")


## Review finding 11: an [INVALID] user policy file (listed with its reason) used to be stuck:
## delete and rename needed a loadable policy. Both now work on the file itself; built-in
## policies stay read-only and nothing outside the user folder is touched.
func test_invalid_user_files_can_be_renamed_and_deleted() -> void:
	var lib := PolicyLibrary.user_dir()
	_write_text(lib.path_join("broken.policy.json"), "{ not a policy")
	_write_text(lib.path_join("broken.policy.json.bak"), "{ also broken")
	_write_text(lib.path_join("My Bot.policy.json"), "{\"format\": \"critterweight.policy\"}")
	var ids := {}
	for s: Dictionary in PolicyLibrary.list():
		if not bool(s.get("valid", true)):
			ids[str(s["id"])] = true
	check(ids.has("broken") and ids.has("My Bot"), "both files are listed as invalid: %s" % str(ids.keys()))
	check_eq(PolicyLibrary.rename("broken", "Kept aside"), OK, "an invalid file can be renamed")
	check(not FileAccess.file_exists(lib.path_join("broken.policy.json")), "old file name gone")
	check(FileAccess.file_exists(lib.path_join("Kept_aside.policy.json")), "renamed to the name's file-safe form")
	check(FileAccess.file_exists(lib.path_join("Kept_aside.policy.json.bak")), "its backup moved along")
	check_eq(PolicyLibrary.delete("Kept_aside"), OK, "an invalid file can be deleted")
	check(not FileAccess.file_exists(lib.path_join("Kept_aside.policy.json")) and not FileAccess.file_exists(lib.path_join("Kept_aside.policy.json.bak")),
		"file and backup removed")
	check_eq(PolicyLibrary.delete("My Bot"), OK, "a file whose name is not a valid id can be deleted too")
	check(not FileAccess.file_exists(lib.path_join("My Bot.policy.json")), "removed")
	check(PolicyLibrary.delete("../escape") != OK, "ids never reach outside the policy folder")
	check(PolicyLibrary.delete("no_such_file") != OK, "a missing file is an error, not a crash")
	var builtin: Array = Content.ids("policies")
	if not builtin.is_empty():
		check(PolicyLibrary.delete(str(builtin[0])) != OK, "built-in policies cannot be deleted")
		check(PolicyLibrary.rename(str(builtin[0]), "x") != OK, "nor renamed")


## Review finding 13: policies shipped by content packages (mods) are size-capped BEFORE they are
## read, like user files; an oversized one is reported and skipped.
func test_content_policies_are_size_capped_before_reading() -> void:
	var pkg := dir.path_join("capmod")
	DirAccess.make_dir_recursive_absolute(pkg.path_join("policies"))
	var f := FileAccess.open(pkg.path_join("policies").path_join("huge.json"), FileAccess.WRITE)
	f.store_string("{\"id\": \"capmod:huge\", \"pad\": \"")
	var chunk := "0123456789".repeat(10000)
	for k in 45:
		f.store_string(chunk)
	f.store_string("\"}")
	f.close()
	var small := _dict(_policy(12))
	small["id"] = "capmod:small"
	_write_text(pkg.path_join("policies").path_join("small.json"), JSON.stringify(_resign(small)))
	var c: Node = load("res://src/data/content.gd").new()
	for k in Content.KINDS:
		(c.get("tables") as Dictionary)[k] = {}
	c.call("_load_package", {"id": "capmod", "path": pkg})
	var tables: Dictionary = c.get("tables")
	var errs: PackedStringArray = c.get("errors")
	check(not (tables["policies"] as Dictionary).has("capmod:huge"), "the oversized policy is not loaded")
	check(("; ".join(errs)).contains("too large"), "and the reason is reported: %s" % "; ".join(errs))
	check((tables["policies"] as Dictionary).has("capmod:small"), "a normal policy in the same package still loads")
	c.free()


## Match setup hook: a missing/incompatible policy never breaks a match (scripted fallback).
func test_match_hook_falls_back_safely() -> void:
	var c := Content.creature("dev_biped")
	var ok_p := _policy(8)
	ok_p.id = ""
	PolicyLibrary.save(ok_p)
	var src := PolicyInputSource.for_match({"creature": c, "policy_id": ok_p.id}, 3, 1)
	check(src is PolicyInputSource, "a valid policy drives the fighter")
	var missing := PolicyInputSource.for_match({"creature": c, "policy_id": "nope"}, 3, 1)
	check(missing is BotBrain, "missing policy -> scripted bot")
	var other := CreatureDef.new()
	other.id = "someone_else"
	var wrong := PolicyInputSource.for_match({"creature": other, "policy_id": ok_p.id}, 3, 1)
	check(wrong is BotBrain, "policy for another fighter -> scripted bot")
