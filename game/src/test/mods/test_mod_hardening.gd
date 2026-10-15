extends TestCase
## Security/robustness review of the mod system (MOD-02/03/06, D-016, D-027): links in folder
## packages, core overrides without consent, client_only packages carrying gameplay, asset paths
## outside the package, lingering mod tuning, BBCode in mod text, import swaps, unportable entry
## names, hidden characters in ids/versions, zip readers that disagree, read-only newer mod sets.
## Every test works in its own temporary mods folder and restores the real one.

var dir := ""
var _saved_limits := {}
var _links: Array = []           ## junctions/symlinks made by a test (removed in after_each)


func before_each() -> void:
	dir = temp_dir("modsec_%d" % Time.get_ticks_usec())
	_saved_limits = Mods.limits.duplicate()
	Mods.use_root(dir.path_join("installed"))
	Mods.apply()          # start from core content only


func after_each() -> void:
	for l in _links:
		DirAccess.remove_absolute(str(l))     # removes the link itself, never its target
	_links.clear()
	Mods.link_check = Callable()
	Mods.simulate_copy_failure = false
	Mods.limits = _saved_limits
	Mods.use_root("")
	Mods.apply()


# ---------------------------------------------------------------------------------------------
# helpers

func _archive(name_: String, files: Dictionary) -> String:
	var p := dir.path_join(name_)
	var zp := ZIPPacker.new()
	zp.open(p)
	for rel in files:
		zp.start_file(rel)
		zp.write_file(_bytes(files[rel]))
		zp.close_file()
	zp.close()
	return p


func _bytes(v) -> PackedByteArray:
	if typeof(v) == TYPE_DICTIONARY or typeof(v) == TYPE_ARRAY:
		return JSON.stringify(v).to_utf8_buffer()
	if typeof(v) == TYPE_PACKED_BYTE_ARRAY:
		return v
	return str(v).to_utf8_buffer()


func _write(path: String, v) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(_bytes(v))
	f.close()


func _folder(name_: String, files: Dictionary) -> String:
	var p := dir.path_join(name_)
	for rel in files:
		_write(p.path_join(rel), files[rel])
	return p


func _manifest(id: String, version := "1.0.0", extra := {}) -> Dictionary:
	var m := {"id": id, "name": id.capitalize(), "version": version, "game_version": Saves.game_version(), "requires": [], "load_after": [], "capabilities": []}
	m.merge(extra, true)
	return m


func _rules(id: String, extra := {}) -> Dictionary:
	var r := {"id": id, "name": "Test Rules", "mode": "standard", "format": "duel", "teams": 2, "players": [2, 2], "rounds": 1, "round_time": 77}
	r.merge(extra, true)
	return r


func _report(id: String) -> String:
	return "\n".join(PackedStringArray(Mods.load_report.get(id, [])))


func _paths(info: Dictionary) -> Array:
	return (info["_entries"] as Array).map(func(e): return str(e["path"]))


func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path)


## Makes `link` a directory link to `target`: a symbolic link where the OS allows it, otherwise
## (Windows without symlink rights) a junction made by `mklink /J`, given 10 s before it is killed.
## Returns true only if `link` now exists and is a link.
func _make_dir_link(target: String, link: String) -> bool:
	var d := DirAccess.open(link.get_base_dir())
	if d == null:
		return false
	if d.create_link(target, link) == OK and d.is_link(link):
		_links.append(link)
		return true
	if OS.get_name() != "Windows":
		return false
	var pid := OS.create_process("cmd.exe", ["/c", "mklink", "/J", link.replace("/", "\\"), target.replace("/", "\\")])
	if pid <= 0:
		return false
	var t0 := Time.get_ticks_msec()
	while OS.is_process_running(pid) and Time.get_ticks_msec() - t0 < 10000:
		await get_tree().create_timer(0.05).timeout
	if OS.is_process_running(pid):
		OS.kill(pid)
		return false
	if DirAccess.open(link.get_base_dir()).is_link(link):
		_links.append(link)
		return true
	return false


# ---------------------------------------------------------------------------------------------
# A. links in folder mods

func test_folder_links_are_never_followed_validated_copied_exported_or_loaded() -> void:
	var outside := _folder("outside_secret", {"secret.json": {"id": "x", "secret": "never share"},
		"rules/stolen.json": _rules("link_mod:stolen")})
	var src := _folder("link_src", {"manifest.json": _manifest("link_mod"), "rules/own.json": _rules("link_mod:own")})
	var linked: bool = await _make_dir_link(outside, src.path_join("stolen"))
	if not linked:
		print("        (no symlink/junction could be made here: the walker is covered by the injected-link test)")
		return
	# a junction back into the package itself: walking or copying through it would never end
	var loop: bool = await _make_dir_link(src, src.path_join("rules").path_join("loop"))
	check(loop, "junction loop created")
	var info := Mods.inspect_folder(src)
	check(info["errors"].is_empty(), "the package itself is fine: %s" % str(info["errors"]))
	check(not _paths(info).any(func(p): return str(p).begins_with("stolen") or str(p).contains("loop")), "linked content is not listed: %s" % str(_paths(info)))
	check(str(info["warnings"]).contains("stolen") and str(info["warnings"]).contains("link"), "skipped links are reported: %s" % str(info["warnings"]))
	var res := Mods.import_package(src)
	check(res["ok"], "import: %s" % res["message"])
	var installed := Mods.mods_dir().path_join("link_mod")
	check(FileAccess.file_exists(installed.path_join("rules/own.json")), "own files copied")
	check(not DirAccess.dir_exists_absolute(installed.path_join("stolen")) and not FileAccess.file_exists(installed.path_join("stolen/secret.json")), "files behind a link are not copied")
	check(not DirAccess.dir_exists_absolute(installed.path_join("rules/loop")), "the loop is not copied")
	var out := Mods.export_package("link_mod", dir.path_join("share"))
	check(out != "", "exported")
	var listing := Mods.zip_directory(out)
	check(not str(listing).contains("secret") and not str(listing).contains("stolen"), "nothing behind a link is packed: %s" % str(listing))
	# a link placed inside an INSTALLED folder mod is never loaded either
	var linked2: bool = await _make_dir_link(outside.path_join("rules"), installed.path_join("modes"))
	check(linked2, "second link created")
	Mods.refresh()
	check(Mods.set_enabled("link_mod", true)["ok"], "enable")
	Mods.apply()
	check(not Content.get_entry("rules", "link_mod:own").is_empty(), "own content loads")
	check(Content.get_entry("modes", "link_mod:stolen").is_empty(), "JSON behind a link inside the mod folder is not loaded")
	# a linked package folder in the mods folder is refused, not followed
	var linked3: bool = await _make_dir_link(src, Mods.mods_dir().path_join("linked_pkg"))
	check(linked3, "third link created")
	Mods.refresh()
	var li := Mods.info_of("linked_pkg")
	check(not li.is_empty() and str(li["errors"]).contains("link"), "a linked package folder is reported: %s" % str(li))


func test_walker_skips_links_and_import_copies_only_validated_files() -> void:
	# links simulated through the test hook, so this runs wherever links cannot be made
	var src := _folder("walk_src", {"manifest.json": _manifest("walk_mod"), "rules/r.json": _rules("walk_mod:r"),
		"fake_dir_link/evil.json": {"id": "x"}, "rules/fake_file_link.json": _rules("walk_mod:evil")})
	Mods.link_check = func(_d: String, n: String) -> bool: return n in ["fake_dir_link", "fake_file_link.json"]
	var info := Mods.inspect_folder(src)
	check(info["errors"].is_empty(), "valid: %s" % str(info["errors"]))
	check_eq(_paths(info), ["manifest.json", "rules/r.json"], "only real files are listed")
	check(str(info["warnings"]).contains("fake_dir_link/") and str(info["warnings"]).contains("rules/fake_file_link.json"), "both links reported")
	check(Mods.import_package(src)["ok"], "imported")
	var installed := Mods.mods_dir().path_join("walk_mod")
	check(FileAccess.file_exists(installed.path_join("rules/r.json")), "validated file copied")
	check(not FileAccess.file_exists(installed.path_join("fake_dir_link/evil.json")) and not FileAccess.file_exists(installed.path_join("rules/fake_file_link.json")), "link entries never copied")
	var out := Mods.export_package("walk_mod", dir.path_join("share"))
	check(not str(Mods.zip_directory(out)).contains("fake"), "link entries never exported")
	# folders deeper than the documented limit are an error, not silently skipped (or copied)
	Mods.link_check = Callable()
	var deep := _folder("deep_src", {"manifest.json": _manifest("deep_mod"), "a/b/c/d/e/f/g/h/i/deep.json": {"id": "deep_mod:x"}})
	var dinfo := Mods.inspect_folder(deep)
	check(str(dinfo["errors"]).contains("deeper than 8"), "depth limit enforced: %s" % str(dinfo["errors"]))
	check(not Mods.import_package(deep)["ok"], "too-deep package is not imported")


# ---------------------------------------------------------------------------------------------
# B. core overrides need the capability AND consent; nobody replaces another mod's entries

func test_core_override_without_declared_capability_is_refused() -> void:
	var core_round := int(Content.get_entry("rules", "duel").get("round_time", 0))
	var p := _archive("sneaky.critmod", {"manifest.json": _manifest("sneaky_override"),
		"rules/duel.json": _rules("duel", {"round_time": 33, "override": true, "name": "Duel (sneaky)"}),
		"tuning.json": {"parry_window": 0.5}})
	check(Mods.import_package(p)["ok"], "installed (the problem is found when loading)")
	check(Mods.consent_needed("sneaky_override").is_empty(), "nothing declared, so nothing is asked")
	# even a consent left over for this id@version (e.g. from a copy that did declare it) is not enough
	Mods.grant_consent("sneaky_override", ["replaces_core"])
	check(Mods.set_enabled("sneaky_override", true)["ok"], "enabled")
	Mods.apply()
	check_eq(int(Content.get_entry("rules", "duel").get("round_time", 0)), core_round, "core duel untouched")
	check_eq(Content.origin_of("rules", "duel"), "core", "still the core entry")
	check_near(Tuning.v("parry_window"), float(Tuning.DEFAULTS["parry_window"]), 0.0001, "tuning.json not applied")
	var rep := _report("sneaky_override")
	check(rep.contains("replaces_core") and rep.contains("tuning.json"), "both refusals explained: %s" % rep)


func test_core_override_needs_consent_even_when_declared() -> void:
	var src := _folder("declared_src", {"manifest.json": _manifest("declared_mod", "1.0.0", {"capabilities": ["replaces_core"]}),
		"rules/duel.json": _rules("duel", {"round_time": 44, "override": true})})
	var core_round := int(Content.get_entry("rules", "duel").get("round_time", 0))
	var info := Mods.inspect_folder(src)
	check(info["errors"].is_empty(), "valid package")
	var pkg := {"id": "declared_mod", "version": "1.0.0", "path": src, "manifest": info["manifest"], "hash": info["hash"],
		"files": Mods.validated_files(info), "consent": []}
	# Content itself refuses, whoever calls it (Mods.apply never loads such a mod without consent)
	Content.reload([pkg])
	check_eq(int(Content.get_entry("rules", "duel").get("round_time", 0)), core_round, "no consent: core kept")
	check(str(Content.errors).contains("not allowed it"), "explained: %s" % str(Content.errors))
	pkg["consent"] = ["replaces_core"]
	Content.reload([pkg])
	check_eq(int(Content.get_entry("rules", "duel").get("round_time", 0)), 44, "with consent the override applies")
	# an override of something core does not have is refused
	var src2 := _folder("phantom_src", {"manifest.json": _manifest("phantom_mod", "1.0.0", {"capabilities": ["replaces_core"]}),
		"rules/x.json": _rules("brand_new_bare_id", {"override": true})})
	var info2 := Mods.inspect_folder(src2)
	Content.reload([{"id": "phantom_mod", "version": "1.0.0", "path": src2, "manifest": info2["manifest"], "hash": info2["hash"],
		"files": Mods.validated_files(info2), "consent": ["replaces_core"]}])
	check(Content.get_entry("rules", "brand_new_bare_id").is_empty(), "bare ids cannot be invented with override")
	check(str(Content.errors).contains("no core rules entry"), "explained: %s" % str(Content.errors))


func test_mods_never_replace_other_mods_or_player_entries() -> void:
	var owner := _archive("owner.critmod", {"manifest.json": _manifest("owner_mod"), "rules/r.json": _rules("owner_mod:r", {"round_time": 50})})
	var thief := _archive("thief.critmod", {"manifest.json": _manifest("thief_mod", "1.0.0", {"capabilities": ["replaces_core"], "load_after": ["owner_mod"]}),
		"rules/r.json": {"items": [_rules("owner_mod:r", {"round_time": 5, "override": true}), _rules("user:glass", {"override": true})]}})
	var first := _archive("first.critmod", {"manifest.json": _manifest("first_tweak", "1.0.0", {"capabilities": ["replaces_core"]}),
		"rules/duel.json": _rules("duel", {"round_time": 61, "override": true})})
	var second := _archive("second.critmod", {"manifest.json": _manifest("second_tweak", "1.0.0", {"capabilities": ["replaces_core"]}),
		"rules/duel.json": _rules("duel", {"round_time": 62, "override": true})})
	for p in [owner, thief, first, second]:
		check(Mods.import_package(p)["ok"], "installed %s" % p.get_file())
	for id in ["thief_mod", "first_tweak", "second_tweak"]:
		Mods.grant_consent(id, ["replaces_core"])
	for id in ["owner_mod", "thief_mod", "first_tweak", "second_tweak"]:
		check(Mods.set_enabled(id, true)["ok"], "enabled %s" % id)
	Mods.apply()
	check_eq(int(Content.get_entry("rules", "owner_mod:r").get("round_time", 0)), 50, "another mod's entry is not replaced")
	check_eq(Content.origin_of("rules", "owner_mod:r"), "owner_mod", "origin kept")
	check(Content.get_entry("rules", "user:glass").is_empty(), "no entries in the player's namespace")
	check(_report("thief_mod").contains("belongs to 'owner_mod'") and _report("thief_mod").contains("belongs to 'user'"), "explained: %s" % _report("thief_mod"))
	check_eq(int(Content.get_entry("rules", "duel").get("round_time", 0)), 61, "the first mod in load order replaces the core entry")
	check(_report("second_tweak").contains("already replaced by 'first_tweak'"), "the conflict is reported: %s" % _report("second_tweak"))
	# "user" (the player's namespace) and "core" are reserved mod ids
	var reserved := Mods.import_package(_archive("user.critmod", {"manifest.json": _manifest("user")}))
	check(not reserved["ok"] and str(reserved["message"]).contains("'user'"), "reserved id refused: %s" % reserved["message"])


# ---------------------------------------------------------------------------------------------
# C. client_only packages are presentation only, in any letter case

func test_client_only_packages_cannot_carry_gameplay_in_any_spelling() -> void:
	var cases := {
		"upper": {"Rules/r.json": _rules("co_upper:r")},
		"shout": {"RULES/r.json": _rules("co_shout:r")},
		"dotless_i": {"technıques/t.json": {"id": "co_dotless_i:t"}},
		"tuning": {"tuning.json": {"parry_window": 0.5}},
		"elements": {"Elements.JSON": {"rules": {}}},
		"meta": {"meta_upgrades/m.json": {"id": "co_meta:m"}},
	}
	for k in cases:
		var files: Dictionary = (cases[k] as Dictionary).duplicate()
		files["manifest.json"] = _manifest("co_%s" % k, "1.0.0", {"client_only": true})
		var r := Mods.import_package(_archive("co_%s.critmod" % k, files))
		check(not r["ok"] and str(r["errors"]).contains("client_only"), "%s refused at inspection: %s" % [k, str(r["errors"])])
	# load-time enforcement too (a package that skipped inspection): nothing gameplay is loaded
	var src := _folder("co_src", {"manifest.json": _manifest("co_direct", "1.0.0", {"client_only": true}),
		"Rules/r.json": _rules("co_direct:r"), "tuning.json": {"parry_window": 0.5},
		"announcer/lines.json": {"id": "co_direct:lines", "lines": {"ko": ["Lights out!"]}}})
	Content.reload([])
	var before := Content.content_hash()
	Content.reload([{"id": "co_direct", "version": "1.0.0", "path": src, "hash": "x", "manifest": _manifest("co_direct", "1.0.0", {"client_only": true}),
		"files": ["manifest.json", "Rules/r.json", "tuning.json", "announcer/lines.json"], "consent": ["replaces_core"]}])
	check(Content.get_entry("rules", "co_direct:r").is_empty(), "gameplay folder in another case is not loaded")
	check_near(Tuning.v("parry_window"), float(Tuning.DEFAULTS["parry_window"]), 0.0001, "tuning.json from a client_only package is not applied")
	check(not Content.get_entry("announcer", "co_direct:lines").is_empty(), "presentation content still loads")
	check_eq(Content.content_hash(), before, "gameplay hash unchanged")
	check(str(Content.errors).contains("client_only"), "reported: %s" % str(Content.errors))
	# a gameplay mod with a differently-cased folder loads it nowhere (same result on every OS)
	var g := _archive("cased.critmod", {"manifest.json": _manifest("cased_mod"), "Rules/r.json": _rules("cased_mod:r")})
	var gi := Mods.inspect_archive(g)
	check(str(gi["warnings"]).contains("lowercase"), "case problem explained at inspection: %s" % str(gi["warnings"]))
	check(Mods.import_package(g)["ok"], "installed")
	Mods.set_enabled("cased_mod", true)
	Mods.apply()
	check(Content.get_entry("rules", "cased_mod:r").is_empty(), "not loaded under 'Rules/'")


# ---------------------------------------------------------------------------------------------
# D. asset paths

func test_mod_asset_paths_must_be_validated_package_files() -> void:
	var base := str(Content.playable_creatures()[0]) if not Content.playable_creatures().is_empty() else "dev_biped"
	var bad := {
		"res_glb": {"model": "res://assets/models/creatures/f_stoke.glb"},
		"res_scene": {"model": "res://src/app/main.tscn"},
		"user_path": {"model": "user://x.glb"},
		"drive": {"model": "C:/Windows/notepad.exe"},
		"absolute": {"model": "/etc/passwd"},
		"traversal": {"model": "../outside.glb"},
		"missing": {"model": "models/missing.glb"},
		"wrong_ext": {"model": "models/notes.txt"},
		"bare_word": {"model": "model"},
		"case": {"model": "Models/Real.glb"},
		"nested_list": {"palette": {"primary": "#123456"}, "textures": ["textures/ok.png", "../escape.png"]},
		"backslash": {"icon": "textures\\ok.png"},
	}
	var items := []
	for k in bad:
		items.append({"id": "asset_mod:%s" % k, "extends": base, "name": k, "art": bad[k]})
	items.append({"id": "asset_mod:good", "extends": base, "name": "Good", "art": {"model": "models/real.glb", "palette": {"primary": "#2B6FD9"},
		"hype_feature": "collar light", "textures": ["textures/ok.png"]}, "audio": {"voice": "stoke", "material": "flesh"}})
	var p := _archive("assets.critmod", {"manifest.json": _manifest("asset_mod"), "creatures/c.json": {"items": items},
		"models/real.glb": PackedByteArray([103, 108, 84, 70]), "models/notes.txt": "notes", "textures/ok.png": PackedByteArray([137, 80, 78, 71])})
	check(Mods.import_package(p)["ok"], "installed")
	Mods.set_enabled("asset_mod", true)
	Mods.apply()
	var rep := _report("asset_mod")
	for k in bad:
		check(Content.creature_entry("asset_mod:%s" % k).is_empty(), "%s rejected" % k)
		check(rep.contains("asset_mod:%s: asset path" % k), "%s explained in the load report" % k)
	var good := Content.creature_entry("asset_mod:good")
	check(not good.is_empty(), "valid asset paths load: %s" % rep)
	if not good.is_empty():
		var model := str(good["art"]["model"])
		check(model.is_absolute_path() and model.ends_with("models/real.glb") and not model.begins_with("res://"), "rewritten to the package copy: %s" % model)
		check(Content.is_package_asset(model), "vouched for as a validated package file")
		check(Content.is_package_asset(str(good["art"]["textures"][0])), "list entries are confined too")
		check_eq(str(good["art"]["palette"]["primary"]), "#2B6FD9", "colours stay as they are")
		check_eq(str(good["audio"]["voice"]), "stoke", "audio ids stay as they are")
	check(not Content.is_package_asset("res://assets/models/creatures/f_stoke.glb") and not Content.is_package_asset("C:/Windows/notepad.exe"), "nothing else is vouched for")


# ---------------------------------------------------------------------------------------------
# F. tuning

func test_mod_tuning_is_undone_when_the_mod_is_disabled() -> void:
	var key := "parry_window"
	var default_v := float(Tuning.DEFAULTS[key])
	var p := _archive("tune.critmod", {"manifest.json": _manifest("tune_mod", "1.0.0", {"capabilities": ["replaces_core"]}),
		"tuning.json": {key: 0.5, "guard_damage_mult": "lots"}})
	check(Mods.import_package(p)["ok"], "installed")
	Mods.grant_consent("tune_mod", ["replaces_core"])
	check(Mods.set_enabled("tune_mod", true)["ok"], "enabled")
	Mods.apply()
	check_near(Tuning.v(key), 0.5, 0.0001, "mod tuning applied")
	check_near(Tuning.v("guard_damage_mult"), float(Tuning.DEFAULTS["guard_damage_mult"]), 0.0001, "a non-number is refused")
	check(str(Content.errors).contains("must be a finite number"), "and reported")
	Mods.set_enabled("tune_mod", false)
	Mods.apply()
	check_near(Tuning.v(key), default_v, 0.0001, "default restored after disabling")


# ---------------------------------------------------------------------------------------------
# G. mod text is never BBCode

func test_mod_text_cannot_restyle_or_hide_the_mods_screen() -> void:
	var hide := "[font_size=1][color=#00000000]"
	var p := _archive("bb.critmod", {"manifest.json": _manifest("bb_mod", "1.0.0", {"capabilities": ["replaces_core"],
		"name": "[color=#0000]Totally Fine", "author": "[url=https://x]me[/url]", "description": "A nice mod " + hide})})
	check(Mods.import_package(p)["ok"], "installed")
	Mods.load_report["bb_mod"] = ["[b]fake[/b] problem"]
	var screen = load("res://src/mods/ui/mods_screen.gd").new()
	add_child(screen)
	screen.on_enter({})
	screen._show_details("bb_mod")
	var raw: String = screen.details_text()
	var shown: String = screen._details.get_parsed_text()
	check(not raw.contains(hide) and raw.contains("[lb]font_size=1]"), "mod markup is escaped")
	check(shown.contains("A nice mod " + hide), "and shown literally: %s" % shown)
	check(shown.contains("Replaces core content."), "the screen's own warning stays visible")
	check(shown.contains("[color=#0000]Totally Fine") and shown.contains("[url=https://x]me[/url]"), "name and author shown literally")
	check(shown.contains("[b]fake[/b] problem"), "load reports shown literally")
	# the import file dialog is wired up (a method named _import_path collided with Node._import_path)
	check(screen._file_dialog.file_selected.get_connections().size() == 1, "file dialog import is connected")
	screen.on_exit()
	screen.queue_free()
	Mods.load_report.erase("bb_mod")
	check_eq(LabUi.esc("[i]x[/i]"), "[lb]i]x[lb]/i]", "the AI Lab escapes the same way")


# ---------------------------------------------------------------------------------------------
# I. import swaps only after a verified copy

func test_import_never_leaves_the_installed_mod_uninstalled() -> void:
	var v1 := _archive("swap_v1.critmod", {"manifest.json": _manifest("swap_mod", "1.0.0"), "rules/r.json": _rules("swap_mod:r", {"round_time": 40})})
	check(Mods.import_package(v1)["ok"], "v1 installed")
	check(Mods.set_enabled("swap_mod", true)["ok"], "enabled")
	Mods.apply()
	var installed := str(Mods.info_of("swap_mod")["path"])
	var before := FileAccess.get_sha256(installed)
	# importing the installed package itself changes nothing
	var same := Mods.import_package(installed)
	check(same["ok"], "self-import is fine: %s" % same["message"])
	check(FileAccess.file_exists(installed) and FileAccess.get_sha256(installed) == before, "still installed, unchanged")
	check_eq(str(Mods.info_of("swap_mod")["version"]), "1.0.0")
	check(not DirAccess.dir_exists_absolute(Mods.mods_dir().path_join(".removed")), "nothing was moved aside")
	# a failed copy of an upgrade leaves the installed version in place and enabled
	var v2 := _archive("swap_v2.critmod", {"manifest.json": _manifest("swap_mod", "1.1.0"), "rules/r.json": _rules("swap_mod:r", {"round_time": 55})})
	Mods.simulate_copy_failure = true
	var failed := Mods.import_package(v2)
	Mods.simulate_copy_failure = false
	check(not failed["ok"] and str(failed["message"]).contains("Nothing was changed"), "failure reported: %s" % failed["message"])
	check(FileAccess.file_exists(installed) and str(Mods.info_of("swap_mod")["version"]) == "1.0.0", "v1 still installed")
	check(Mods.is_enabled("swap_mod") and int(Content.get_entry("rules", "swap_mod:r").get("round_time", 0)) == 40, "and still loaded")
	# the real upgrade then works and keeps the old copy aside
	var ok := Mods.import_package(v2)
	check(ok["ok"] and str(ok["message"]).begins_with("Upgraded"), "upgrade: %s" % ok["message"])
	check_eq(int(Content.get_entry("rules", "swap_mod:r").get("round_time", 0)), 55, "v2 loaded")
	check(DirAccess.dir_exists_absolute(Mods.mods_dir().path_join(".removed")), "v1 kept in .removed")
	# folder packages: importing the installed folder itself is a no-op as well
	var src := _folder("swap_folder", {"manifest.json": _manifest("swap_folder_mod"), "rules/r.json": _rules("swap_folder_mod:r")})
	check(Mods.import_package(src)["ok"], "folder installed")
	var folder := str(Mods.info_of("swap_folder_mod")["path"])
	check(Mods.import_package(folder)["ok"] and FileAccess.file_exists(folder.path_join("rules/r.json")), "self-import of a folder keeps it installed")


# ---------------------------------------------------------------------------------------------
# L. portable names

func test_unportable_entry_names_are_rejected() -> void:
	var cases := {
		"device": {"rules/con.json": _rules("nm_device:r")},
		"device_ext": {"rules/aux.tar.json": _rules("nm_device_ext:r")},
		"com": {"textures/COM1.png": PackedByteArray([1])},
		"lpt": {"Lpt9.txt": "x"},
		"nul_folder": {"nul/x.json": {"id": "nm_nul_folder:x"}},
		"dotfile": {"rules/.hidden.json": _rules("nm_dotfile:r")},
		"dot_folder": {".rules/r.json": _rules("nm_dot_folder:r")},
		"trailing_dot": {"rules./r.json": _rules("nm_trailing_dot:r")},
		"trailing_space": {"rules /r.json": _rules("nm_trailing_space:r")},
		"bad_char": {"rules/a?b.json": _rules("nm_bad_char:r")},
		"control": {"rules/a\u0001.json": _rules("nm_control:r")},
		"case_files": {"rules/A.json": _rules("nm_case_files:a"), "rules/a.json": _rules("nm_case_files:b")},
		"case_folders": {"Rules/a.json": _rules("nm_case_folders:a"), "rules/b.json": _rules("nm_case_folders:b")},
		"file_vs_folder": {"textures/x.png": PackedByteArray([1]), "Textures/x.png/y.png": PackedByteArray([2])},
		"empty_part": {"rules//r.json": _rules("nm_empty_part:r")},
	}
	for k in cases:
		var files: Dictionary = (cases[k] as Dictionary).duplicate()
		files["manifest.json"] = _manifest("nm_%s" % k)
		var info := Mods.inspect_archive(_archive("nm_%s.critmod" % k, files))
		check(not info["errors"].is_empty(), "%s rejected" % k)
		check(str(info["errors"]).length() > 20, "%s explained: %s" % [k, str(info["errors"])])
	check(str(Mods.inspect_archive(dir.path_join("nm_device.critmod"))["errors"]).contains("reserved device name"), "device names named as such")
	check(str(Mods.inspect_archive(dir.path_join("nm_case_files.critmod"))["errors"]).contains("letter case"), "case collisions named as such")
	check(str(Mods.inspect_archive(dir.path_join("nm_dotfile.critmod"))["errors"]).contains("hidden"), "hidden names named as such")
	# a normal package is unaffected
	var fine := Mods.inspect_archive(_archive("nm_fine.critmod", {"manifest.json": _manifest("nm_fine"), "rules/console.json": _rules("nm_fine:r"), "textures/com10.png": PackedByteArray([1])}))
	check(fine["errors"].is_empty(), "names that only start like device names are fine: %s" % str(fine["errors"]))


# ---------------------------------------------------------------------------------------------
# M. no hidden characters in ids and versions

func test_ids_and_versions_with_whitespace_or_control_characters_are_rejected() -> void:
	check(not Schema.full_match("^[0-9]+[.][0-9]+[.][0-9]+$", "1.0.0\n"), "a trailing line break does not match ^...$")
	check(Schema.full_match("^[0-9]+[.][0-9]+[.][0-9]+$", "1.0.0"), "the plain version does")
	# the other whole-name checks use the same rule (arena package entries, AI policy ids)
	check(ArenaPackage.safe_entry_name("arenas/x.json\n") != "" and ArenaPackage.safe_entry_name("arenas/x.json") == "", "arena package names matched whole")
	var pd := PolicyData.create_new("dev_biped", PackedInt32Array([4]), "tanh", 1).to_dict()
	pd["id"] = "policy_id\n"
	check(str(PolicyData.from_dict(pd)["errors"]).contains("invalid id"), "policy ids matched whole")
	var cases := {
		"id_newline": _manifest("ws_id\n"),
		"version_newline": _manifest("ws_version", "1.0.0\n"),
		"version_space": _manifest("ws_version_space", " 1.0.0"),
		"game_version": _manifest("ws_game", "1.0.0", {"game_version": Saves.game_version() + "\n"}),
		"requires": _manifest("ws_requires", "1.0.0", {"requires": [{"id": "core\n", "version": "1.0.0"}]}),
		"requires_version": _manifest("ws_requires_v", "1.0.0", {"requires": [{"id": "core", "version": "1.0.0\t"}]}),
		"load_after": _manifest("ws_after", "1.0.0", {"load_after": ["other mod"]}),
		"nbsp": _manifest("ws_nbsp", "1.0.0\u00a0"),
	}
	for k in cases:
		var r := Mods.import_package(_archive("ws_%s.critmod" % k, {"manifest.json": cases[k]}))
		check(not r["ok"], "%s rejected" % k)
	# content entry ids are checked by the same full-match schema rule
	var p := _archive("ws_entry.critmod", {"manifest.json": _manifest("ws_entry"), "rules/r.json": _rules("ws_entry:r\n")})
	check(Mods.import_package(p)["ok"], "manifest fine")
	Mods.set_enabled("ws_entry", true)
	Mods.apply()
	check(Content.get_entry("rules", "ws_entry:r\n").is_empty(), "entry id with a line break is refused")
	check(_report("ws_entry").contains("does not match"), "explained: %s" % _report("ws_entry"))


# ---------------------------------------------------------------------------------------------
# N. the central-directory reader and Godot's zip reader must agree

func test_zip_directory_and_zip_reader_must_agree() -> void:
	var good := _archive("agree.critmod", {"manifest.json": _manifest("agree_mod"), "rules/r.json": _rules("agree_mod:r")})
	var bytes := FileAccess.get_file_as_bytes(good)
	check(not Mods.zip_directory(good).has("error"), "a plain archive is fine")
	var eocd := bytes.size() - 22
	check(bytes.decode_u32(eocd) == 0x06054b50, "test archive ends with its end record")
	# a ZIP64 locator squeezed between the directory and the end record
	var loc := PackedByteArray([0x50, 0x4b, 0x06, 0x07, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0])
	var z64 := bytes.slice(0, eocd) + loc + bytes.slice(eocd)
	# bytes appended after the end record, and bytes prepended before the first entry
	var tail := bytes + PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])
	var head := PackedByteArray([9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9]) + bytes
	for c in [["zip64_locator", z64], ["trailing_data", tail], ["prepended_data", head]]:
		var path := dir.path_join("%s.critmod" % c[0])
		_write(path, c[1])
		var listing := Mods.zip_directory(path)
		check(listing.has("error"), "%s refused: %s" % [c[0], str(listing)])
		check(not Mods.import_package(path)["ok"], "%s not installable" % c[0])
	# extraction requires Godot's reader to list exactly the checked entries
	var info := Mods.inspect_archive(good)
	check(info["errors"].is_empty(), "inspected")
	var short := info.duplicate(true)
	(short["_entries"] as Array).pop_back()
	check_eq(Mods._extract(short), "", "an entry the check did not see is never unpacked")
	var renamed := info.duplicate(true)
	(renamed["_entries"] as Array)[0]["path"] = "other.json"
	check_eq(Mods._extract(renamed), "", "listings must match name for name")
	var resized := info.duplicate(true)
	(resized["_entries"] as Array)[0]["size"] = int((resized["_entries"] as Array)[0]["size"]) + 1
	check_eq(Mods._extract(resized), "", "sizes must match")
	check(Mods._extract(info) != "", "the matching listing unpacks")
	# an archive swapped after it was checked is not unpacked under the old hash
	var swap := _archive("swap.critmod", {"manifest.json": _manifest("agree_swap"), "rules/r.json": _rules("agree_swap:r")})
	check(Mods.import_package(swap)["ok"], "installed")
	var installed := str(Mods.info_of("agree_swap")["path"])
	Mods.set_enabled("agree_swap", true)
	var other := _archive("swap_other.critmod", {"manifest.json": _manifest("agree_swap"), "rules/r.json": _rules("agree_swap:r", {"round_time": 11}), "rules/extra.json": _rules("agree_swap:extra")})
	_write(installed, FileAccess.get_file_as_bytes(other))
	Mods.apply()       # no rescan: the listing on record is the checked one
	check(Content.get_entry("rules", "agree_swap:extra").is_empty(), "swapped archive content not loaded")
	check(_report("agree_swap").contains("could not unpack"), "explained: %s" % _report("agree_swap"))


# ---------------------------------------------------------------------------------------------
# E (mod sets). a newer modsets.json is never rewritten

func test_newer_mod_sets_file_is_left_untouched() -> void:
	var root := dir.path_join("newer_root")
	DirAccess.make_dir_recursive_absolute(root)
	var path := root.path_join("modsets.json")
	Saves.write_json(path, "modsets", Mods.SETS_FORMAT + 1, {"active": "Future", "sets": {"Future": ["x"]}, "consent": {}, "new_field": 1})
	var before := _text(path)
	Mods.use_root(root)
	check(Mods.sets_read_only and Mods.sets_error.contains("newer"), "read-only with a player-facing note")
	Mods.save_set_as("Another")
	Mods.set_enabled("moon_rules", true)
	Mods.grant_consent("moon_rules", ["replaces_core"])
	check_eq(_text(path), before, "modsets.json unchanged")
	check(not FileAccess.file_exists(path + ".bak") and not FileAccess.file_exists(path + ".tmp"), "nothing rotated or staged")
	check(DirAccess.get_files_at(root).size() == 1, "no quarantine copy either: %s" % str(DirAccess.get_files_at(root)))
