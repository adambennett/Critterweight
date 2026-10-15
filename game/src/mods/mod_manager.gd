extends Node
## Autoload "Mods": discovers mod packages (folders or .critmod/.zip archives in the user "mods"
## folder, plus the bundled examples), validates them, resolves dependencies into a
## deterministic load order, persists named mod sets, and feeds Content.reload().
##
## Trust model (docs/MODDING.md#trust): packages are DATA ONLY. No script, binary, scene,
## shader or resource-pack file is ever loaded or executed and archives are never mounted into
## res://. Every archive entry is checked (path, name, size, file type) before anything is
## extracted; extracted copies live in a private cache keyed by the archive hash and must match the
## checked listing exactly. Folder packages are walked without following links (symlinks,
## junctions): only the files the walk validated are hashed, copied, exported and handed to
## Content. Packages that change core content ("replaces_core") need the player's explicit
## consent once per version; Content refuses core overrides without it (D-027).

signal mods_changed()

const API_VERSION := 1
const SETS_FORMAT := 1
const ARCHIVE_EXT := ["critmod", "zip"]
const ALLOWED_EXT := ["json", "txt", "md", "png", "jpg", "jpeg", "webp", "ogg", "wav", "glb"]
const ID_PATTERN := "^[a-z0-9_]{3,32}$"
const RESERVED_IDS := ["core", "user"]     ## the base game and the player's own "user:" entries
const KNOWN_CAPABILITIES := ["replaces_core", "large_assets", "scripts"]
const CONSENT_CAPABILITIES := ["replaces_core"]
const MAX_DEPTH := 8                       ## folder levels inside a package
## Names Windows reserves for devices, with or without an extension ("con.json", "LPT1.png").
const WINDOWS_RESERVED := ["CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$",
	"COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "COM¹", "COM²", "COM³",
	"LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9", "LPT¹", "LPT²", "LPT³"]
const BAD_NAME_CHARS := ["<", ">", "\"", "|", "?", "*"]

## Hard limits (tests may lower them). large_assets raises package_bytes to large_package_bytes.
var limits := {"package_bytes": 64 * 1024 * 1024, "large_package_bytes": 256 * 1024 * 1024,
	"file_bytes": 32 * 1024 * 1024, "files": 2000, "path_length": 160, "json_bytes": 4 * 1024 * 1024}
var examples_dir := "res://mods_examples"
var available: Array = []        ## [info Dictionary] sorted by id (see _new_info)
var sets := {"Default": []}      ## set name -> [mod ids]
var active_set := "Default"
var consent := {}                ## "id@version" -> [accepted capabilities]
var load_order: Array = []       ## ids loaded into Content, in order
var load_report := {}            ## id -> [problems found while loading]
var safe_mode := false           ## --safe-mode / --no-mods: start with core content only
var sets_read_only := false      ## modsets.json was written by a newer game version: never rewritten
var sets_error := ""             ## player-facing note about modsets.json ("" when fine)
## Test hook: Callable(dir: String, name: String) -> bool that marks extra entries as links (on top
## of DirAccess.is_link), so the walkers can be tested where links cannot be created.
var link_check := Callable()
## Test hook: import_package() fails while copying the new version (nothing may change then).
var simulate_copy_failure := false
var _sets_path := ""
var _root_override := ""


func _ready() -> void:
	var ua := OS.get_cmdline_user_args()
	safe_mode = ua.has("--safe-mode") or ua.has("--no-mods")
	_sets_path = Paths.file("mods", "modsets.json")
	_load_sets()
	refresh()
	var only := ua.find("--mods")
	if only >= 0 and only + 1 < ua.size():
		enable_only(ua[only + 1].split(",", false))
		return
	if not safe_mode and not enabled_ids().is_empty():
		apply()


func mods_dir() -> String:
	if _root_override != "":
		DirAccess.make_dir_recursive_absolute(_root_override)
		return _root_override
	return Paths.dir("mods")


## Points the manager at another mods folder (tests, dedicated-server config) and reloads its
## mod sets. Pass "" to return to the user mods folder.
func use_root(dir: String) -> void:
	_root_override = dir
	_sets_path = mods_dir().path_join("modsets.json")
	sets = {"Default": []}
	active_set = "Default"
	consent = {}
	sets_read_only = false
	sets_error = ""
	_load_sets()
	refresh()


# ---------------------------------------------------------------------------------------------
# discovery & validation

## Rescans the user mods folder and the bundled examples.
func refresh() -> void:
	var found := {}
	var d := DirAccess.open(mods_dir())
	if d:
		for sub in d.get_directories():
			if sub.begins_with("."):
				continue
			var p := mods_dir().path_join(sub)
			if not FileAccess.file_exists(p.path_join("manifest.json")):
				continue
			if _is_link(d, mods_dir(), sub):
				# never followed: a linked folder could expose anything on the disk
				var li := _new_info(p, "folder")
				li["errors"].append("'%s' is a link (symbolic link or junction); mods never follow links. Copy the folder into the mods folder instead." % sub)
				_offer(found, li)
				continue
			_offer(found, inspect_folder(p, "folder"))
		for f in d.get_files():
			if f.get_extension().to_lower() in ARCHIVE_EXT:
				_offer(found, inspect_archive(mods_dir().path_join(f)))
	# bundled examples ship as archives inside the game package; an installed copy wins
	var ex := DirAccess.open(examples_dir)
	if ex:
		for f2 in ex.get_files():
			if f2.get_extension().to_lower() in ARCHIVE_EXT:
				var info := inspect_archive(examples_dir.path_join(f2), "example")
				var id := str(info["id"])
				if not found.has(id):
					found[id] = info
	available = found.values()
	available.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))
	mods_changed.emit()


## Keeps the newest valid version when two installed packages share an id.
func _offer(found: Dictionary, info: Dictionary) -> void:
	var id := str(info["id"])
	if not found.has(id):
		found[id] = info
		return
	var cur: Dictionary = found[id]
	var newer := compare_versions(str(info["version"]), str(cur["version"])) > 0
	if (info["errors"].is_empty() and not cur["errors"].is_empty()) or (newer and info["errors"].is_empty() == cur["errors"].is_empty()):
		info["warnings"].append("replaces %s %s (%s) which is also installed" % [id, cur["version"], str(cur["path"]).get_file()])
		found[id] = info
	else:
		cur["warnings"].append("an older/invalid copy is ignored: %s" % str(info["path"]).get_file())


## Info dictionary for one package. Keys starting with "_" are internal: _entries (the validated
## listing: [{path, size}], archive paths without root_prefix), _tops (top-level folder names),
## _root_files, _total (bytes).
func _new_info(path: String, kind: String) -> Dictionary:
	return {"id": path.get_file().get_basename(), "name": path.get_file(), "version": "0.0.0", "author": "", "description": "",
		"path": path, "kind": kind, "manifest": {}, "size": 0, "files": 0, "hash": "", "errors": [],
		"warnings": [], "client_only": false, "capabilities": [], "requires": [], "load_after": [],
		"kinds": [], "root_prefix": "", "_entries": []}


## Inspects a package folder (installed or bundled example).
func inspect_folder(path: String, kind := "folder") -> Dictionary:
	var info := _new_info(path, kind)
	var entries := []
	var notes := {"links": [], "too_deep": []}
	_walk(path, "", entries, 0, notes)
	var links: Array = notes["links"]
	for i in mini(links.size(), 5):
		info["warnings"].append("'%s' is a link (symbolic link or junction) and was skipped: mods never follow links" % links[i])
	if links.size() > 5:
		info["warnings"].append("%d more links were skipped" % (links.size() - 5))
	for t in notes["too_deep"]:
		info["errors"].append("'%s' is nested deeper than %d folders" % [t, MAX_DEPTH])
	_check_entries(info, entries)
	if entries.any(func(e): return str(e["path"]) == "manifest.json"):
		_check_manifest(info, FileAccess.get_file_as_string(path.path_join("manifest.json")))
	elif "manifest.json" in links:
		info["errors"].append("manifest.json is a link; it must be a real file in the package folder")
	else:
		info["errors"].append("no manifest.json at the package root")
	if info["errors"].is_empty():
		info["hash"] = _hash_folder(path, entries)
		if str(info["hash"]) == "":
			info["errors"].append("the folder changed while it was being checked; rescan")
	info["_entries"] = entries
	return info


## True when `name_` inside the folder `dir` is a symbolic link, junction or other reparse point.
func _is_link(d: DirAccess, dir: String, name_: String) -> bool:
	if link_check.is_valid() and bool(link_check.call(dir, name_)):
		return true
	return d.is_link(dir.path_join(name_))


## True when any part of the relative path `rel` under `base` is a link (or no longer opens).
func _link_in_path(base: String, rel: String) -> bool:
	var d := DirAccess.open(base)
	if d == null:
		return true
	var cur := base
	for part in rel.split("/"):
		if _is_link(d, cur, part):
			return true
		cur = cur.path_join(part)
	return false


## Lists a package folder's regular files as [{path, size}] ("/"-separated, relative to `base`).
## Never follows links: symlinks, junctions and other reparse points are left out and named in
## notes.links, so nothing outside the folder is validated, hashed, copied, exported or loaded.
## Hidden names (".git", ".DS_Store"; never packed by tools/mods/pack_mod.py) are skipped. Folders
## deeper than MAX_DEPTH levels are named in notes.too_deep instead of being walked, and the
## listing stops past limits.files + 1 entries (rejected as "too many files").
func _walk(base: String, rel: String, out: Array, depth: int, notes: Dictionary) -> void:
	if out.size() > int(limits["files"]):
		return
	var here := base.path_join(rel) if rel != "" else base
	var d := DirAccess.open(here)
	if d == null:
		return
	for f in d.get_files():
		if f.begins_with("."):
			continue
		var r := rel.path_join(f) if rel != "" else f
		if _is_link(d, here, f):
			notes["links"].append(r)
			continue
		var fa := FileAccess.open(here.path_join(f), FileAccess.READ)
		out.append({"path": r, "size": fa.get_length() if fa else 0})
		if out.size() > int(limits["files"]):
			return
	for sub in d.get_directories():
		if sub.begins_with("."):
			continue
		var rs := rel.path_join(sub) if rel != "" else sub
		if _is_link(d, here, sub):
			notes["links"].append(rs + "/")
			continue
		if depth + 1 > MAX_DEPTH:
			notes["too_deep"].append(rs + "/")
			continue
		_walk(base, rs, out, depth + 1, notes)
		if out.size() > int(limits["files"]):
			return


## Inspects an archive without extracting anything: sizes come from the zip central directory
## (so a "zip bomb" is rejected before a single byte is inflated).
func inspect_archive(path: String, kind := "archive") -> Dictionary:
	var info := _new_info(path, kind)
	var fsize := 0
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa:
		fsize = fa.get_length()
		fa.close()
	if fsize > int(limits["large_package_bytes"]):
		info["errors"].append("archive is %s, over the %s limit" % [_mb(fsize), _mb(int(limits["large_package_bytes"]))])
		return info
	var listing := zip_directory(path)
	if listing.has("error"):
		info["errors"].append(str(listing["error"]))
		return info
	var entries: Array = listing["entries"]
	# common layout: everything inside one top-level folder
	var prefix := _common_root(entries)
	info["root_prefix"] = prefix
	if prefix != "":
		for e in entries:
			e["path"] = str(e["path"]).substr(prefix.length())
	info["_entries"] = entries
	_check_entries(info, entries)
	if not info["errors"].is_empty():
		return info
	var zr := ZIPReader.new()
	if zr.open(path) != OK:
		info["errors"].append("not a readable zip archive")
		return info
	var man_name := prefix + "manifest.json"
	if zr.file_exists(man_name):
		_check_manifest(info, zr.read_file(man_name).get_string_from_utf8())
	else:
		info["errors"].append("no manifest.json at the archive root")
	zr.close()
	if info["errors"].is_empty():
		info["hash"] = FileAccess.get_sha256(path)
	return info


## Reads a zip's central directory: {entries: [{path, size, csize}]} or {error}. Rejects
## encrypted entries, ZIP64 and multi-disk archives (never produced by our tools), and any layout
## where another zip reader could see a different directory: the end record must close the file
## (its comment reaching exactly the end), the directory must end exactly where the end record
## starts (no room for a ZIP64 locator or other data), and the directory must hold exactly the
## declared entries.
static func zip_directory(path: String) -> Dictionary:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return {"error": "cannot open archive"}
	var n := fa.get_length()
	if n < 22:
		return {"error": "not a zip archive (too small)"}
	var tail_len := mini(n, 65557)
	fa.seek(n - tail_len)
	var tail := fa.get_buffer(tail_len)
	var eocd := -1
	for i in range(tail_len - 22, -1, -1):
		if tail[i] == 0x50 and tail[i + 1] == 0x4b and tail[i + 2] == 0x05 and tail[i + 3] == 0x06:
			eocd = i
			break
	if eocd < 0:
		return {"error": "not a zip archive (no end-of-directory record)"}
	if tail.decode_u16(eocd + 4) != 0 or tail.decode_u16(eocd + 6) != 0:
		return {"error": "multi-part zip archives are not supported"}
	var count := tail.decode_u16(eocd + 10)
	var cd_size := tail.decode_u32(eocd + 12)
	var cd_off := tail.decode_u32(eocd + 16)
	var eocd_abs := n - tail_len + eocd
	if count == 0xFFFF or cd_size == 0xFFFFFFFF or cd_off == 0xFFFFFFFF or cd_off + cd_size > n:
		return {"error": "ZIP64 or damaged archives are not supported"}
	if tail.decode_u16(eocd + 8) != count or eocd + 22 + tail.decode_u16(eocd + 20) != tail_len:
		return {"error": "damaged or altered zip archive (end record does not match the file)"}
	if cd_off + cd_size != eocd_abs:
		return {"error": "ZIP64 or altered zip archives are not supported (data between the directory and its end record)"}
	fa.seek(cd_off)
	var cd := fa.get_buffer(cd_size)
	var out := []
	var o := 0
	for k in count:
		if o + 46 > cd.size() or cd.decode_u32(o) != 0x02014b50:
			return {"error": "damaged zip directory"}
		var flags := cd.decode_u16(o + 8)
		var csize := cd.decode_u32(o + 20)
		var usize := cd.decode_u32(o + 24)
		var nlen := cd.decode_u16(o + 28)
		var xlen := cd.decode_u16(o + 30)
		var clen := cd.decode_u16(o + 32)
		if o + 46 + nlen + xlen + clen > cd.size():
			return {"error": "damaged zip directory"}
		var fname := cd.slice(o + 46, o + 46 + nlen).get_string_from_utf8()
		o += 46 + nlen + xlen + clen
		if flags & 1:
			return {"error": "encrypted archive entries are not supported ('%s')" % fname.c_escape()}
		if csize == 0xFFFFFFFF or usize == 0xFFFFFFFF:
			return {"error": "ZIP64 entries are not supported ('%s')" % fname.c_escape()}
		if fname.ends_with("/"):
			continue
		out.append({"path": fname, "size": usize, "csize": csize})
	if o != cd.size():
		return {"error": "damaged zip directory (unexpected data after the last entry)"}
	return {"entries": out}


func _common_root(entries: Array) -> String:
	if entries.is_empty():
		return ""
	var first := str(entries[0]["path"])
	if not first.contains("/"):
		return ""
	var top := first.split("/")[0] + "/"
	for e in entries:
		if not str(e["path"]).begins_with(top):
			return ""
	return top


## Path/name/type/size rules shared by folders and archives. Names must be portable: no hidden
## (dot) names, no Windows device names (con, nul, com1, lpt1 ... with any extension), no trailing
## dot/space (Windows drops them), no < > " | ? * or control characters, and no two names that
## only differ in letter case (they would overwrite each other on Windows).
func _check_entries(info: Dictionary, entries: Array) -> void:
	var errs: Array = info["errors"]
	if entries.size() > int(limits["files"]):
		errs.append("too many files (%d > %d)" % [entries.size(), int(limits["files"])])
		return
	var total := 0
	var kinds := {}
	var tops := {}
	var root_files := []
	var seen_files := {}     ## folded path -> path as written
	var seen_dirs := {}      ## folded folder path -> folder path as written
	for e in entries:
		var p := str(e["path"]).replace("\\", "/")
		var size := int(e["size"])
		total += size
		var parts := p.split("/")
		if p.begins_with("/") or p.contains(":") or parts.has("..") or parts.has(".") or parts.has(""):
			errs.append("unsafe path '%s' (absolute, drive, empty or '..' paths are not allowed)" % p.c_escape())
			continue
		if p.length() > int(limits["path_length"]):
			errs.append("path too long: '%s'" % p.substr(0, 60).c_escape())
			continue
		if parts.size() - 1 > MAX_DEPTH:
			errs.append("'%s' is nested deeper than %d folders" % [p.c_escape(), MAX_DEPTH])
			continue
		var bad_name := _name_problem(p, parts)
		if bad_name != "":
			errs.append(bad_name)
			continue
		var clash := _case_clash(p, parts, seen_files, seen_dirs)
		if clash != "":
			errs.append("'%s' and '%s' differ only in letter case (or are the same name); use distinct names" % [p, clash])
			continue
		if parts.size() > 1:
			tops[parts[0]] = true
		else:
			root_files.append(p)
		var ext := p.get_extension().to_lower()
		if not ext in ALLOWED_EXT:
			if ext in ["gd", "gdc", "cs", "dll", "so", "dylib", "exe", "bat", "cmd", "ps1", "sh", "py", "js", "pck", "gdextension", "tscn", "scn", "tres", "res", "gdshader", "shader"]:
				errs.append("'%s' is code or an engine resource; mods are data-only and may not contain it" % p)
			else:
				errs.append("'%s': file type .%s is not allowed (allowed: %s)" % [p, ext, ", ".join(ALLOWED_EXT)])
			continue
		if size > int(limits["file_bytes"]):
			errs.append("'%s' is %s, over the per-file limit of %s" % [p, _mb(size), _mb(int(limits["file_bytes"]))])
		if ext == "json" and size > int(limits["json_bytes"]):
			errs.append("'%s' is %s, over the JSON limit of %s" % [p, _mb(size), _mb(int(limits["json_bytes"]))])
		if p.contains("/"):
			kinds[p.split("/")[0]] = true
	info["size"] = total
	info["files"] = entries.size()
	info["kinds"] = kinds.keys().filter(func(k): return k in Content.KINDS)
	info["_tops"] = tops.keys()
	info["_root_files"] = root_files
	info["_total"] = total
	# content folders load by their exact lowercase name on every platform (see Content)
	for t in tops:
		var k := Content.kind_alias(str(t))
		if k != "" and k != str(t):
			info["warnings"].append("'%s/' is not loaded: content folders are lowercase ('%s/')" % [t, k])


## Why one entry name is not portable ("" when it is fine).
func _name_problem(p: String, parts: PackedStringArray) -> String:
	for c in parts:
		if c.begins_with("."):
			return "'%s': hidden names (starting with '.') are not allowed" % p.c_escape()
		if c.ends_with(".") or c.ends_with(" "):
			return "'%s': names may not end with a dot or a space (Windows drops them)" % p.c_escape()
		for i in c.length():
			var ch := c.unicode_at(i)
			if ch < 32 or ch == 127 or c[i] in BAD_NAME_CHARS:
				return "'%s': names may not contain control characters or < > \" | ? *" % p.c_escape()
		if c.get_slice(".", 0).strip_edges().to_upper() in WINDOWS_RESERVED:
			return "'%s': '%s' is a reserved device name on Windows" % [p, c]
	return ""


## The earlier entry `p` collides with when letter case is ignored ("" if none): the same file
## twice, or a file named like a folder another entry uses.
func _case_clash(p: String, parts: PackedStringArray, seen_files: Dictionary, seen_dirs: Dictionary) -> String:
	var folded := Content.fold(p)
	if seen_files.has(folded):
		return str(seen_files[folded])
	if seen_dirs.has(folded):
		return str(seen_dirs[folded]) + "/"
	var prefix := ""
	for i in parts.size() - 1:
		prefix = parts[i] if i == 0 else prefix + "/" + parts[i]
		var fp := Content.fold(prefix)
		if seen_files.has(fp):
			return str(seen_files[fp])
		if seen_dirs.has(fp) and str(seen_dirs[fp]) != prefix:
			return str(seen_dirs[fp]) + "/"
	prefix = ""
	for i in parts.size() - 1:
		prefix = parts[i] if i == 0 else prefix + "/" + parts[i]
		seen_dirs[Content.fold(prefix)] = prefix
	seen_files[folded] = p
	return ""


func _check_manifest(info: Dictionary, text: String) -> void:
	var errs: Array = info["errors"]
	var json := JSON.new()
	if json.parse(text) != OK:
		errs.append("manifest.json: JSON error at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return
	if typeof(json.data) != TYPE_DICTIONARY:
		errs.append("manifest.json must be an object")
		return
	var m: Dictionary = json.data
	info["manifest"] = m
	for e in Schema.validate_named(m, "manifest", "manifest.json"):
		errs.append(e)
	var id := str(m.get("id", ""))
	info["id"] = id if id != "" else info["id"]
	info["name"] = str(m.get("name", info["id"]))
	info["version"] = str(m.get("version", "0.0.0"))
	info["author"] = str(m.get("author", ""))
	info["description"] = str(m.get("description", ""))
	info["client_only"] = bool(m.get("client_only", false))
	info["capabilities"] = m.get("capabilities", []) if typeof(m.get("capabilities")) == TYPE_ARRAY else []
	info["requires"] = m.get("requires", []) if typeof(m.get("requires")) == TYPE_ARRAY else []
	info["load_after"] = m.get("load_after", []) if typeof(m.get("load_after")) == TYPE_ARRAY else []
	if id in RESERVED_IDS or not Schema.full_match(ID_PATTERN, id):
		errs.append("manifest id '%s' must be 3-32 lowercase letters, digits or _ and not %s" % [id.c_escape(), " or ".join(RESERVED_IDS.map(func(r): return "'%s'" % r))])
	# ids and versions end up in file names, consent keys and handshakes: no hidden characters
	var texts := [["id", m.get("id")], ["version", m.get("version")], ["game_version", m.get("game_version")]]
	for r in info["requires"]:
		if typeof(r) == TYPE_DICTIONARY:
			texts.append(["requires id", (r as Dictionary).get("id")])
			texts.append(["requires version", (r as Dictionary).get("version")])
	for la in info["load_after"]:
		texts.append(["load_after", la])
	for tv in texts:
		if typeof(tv[1]) == TYPE_STRING and has_space_or_control(str(tv[1])):
			errs.append("manifest %s '%s' must not contain spaces, line breaks or control characters" % [tv[0], str(tv[1]).c_escape()])
	var gv := str(m.get("game_version", ""))
	if gv != "" and not game_version_ok(gv):
		errs.append("made for game version %s; this build is %s (incompatible)" % [gv, Saves.game_version()])
	if int(m.get("api", API_VERSION)) > API_VERSION:
		errs.append("needs mod API v%d; this build supports v%d" % [int(m.get("api", 0)), API_VERSION])
	for c in info["capabilities"]:
		if not str(c) in KNOWN_CAPABILITIES:
			errs.append("unknown capability '%s'" % str(c))
		elif str(c) == "scripts":
			errs.append("declares 'scripts': this game never runs mod code (data-only mods), so the package cannot be used")
	if int(info.get("_total", 0)) > int(limits["package_bytes"]) and not "large_assets" in info["capabilities"]:
		errs.append("package is %s, over %s; large packages must declare the 'large_assets' capability" % [_mb(int(info["_total"])), _mb(int(limits["package_bytes"]))])
	if info["client_only"]:
		# presentation only: no gameplay (or other non-presentation) folder in any letter case and no
		# root singletons; Content enforces the same rule again when it loads the package
		for t in info.get("_tops", []):
			var k := Content.kind_alias(str(t))
			if k != "" and not k in Content.PRESENTATION_KINDS:
				errs.append("client_only packages may only change presentation, but it contains '%s/'%s" % [t, " (gameplay content)" if k in Content.GAMEPLAY_KINDS else ""])
		for rf in info.get("_root_files", []):
			if Content.singleton_alias(str(rf)) != "":
				errs.append("client_only packages may only change presentation, but it contains '%s' (global game values)" % rf)


## True when `s` contains whitespace or control characters (including Unicode spaces).
static func has_space_or_control(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if c <= 32 or (c >= 127 and c <= 160) or c == 0x1680 or (c >= 0x2000 and c <= 0x200F) or c in [0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF]:
			return true
	return false


## Hash over the validated entries' names and contents; "" if a path became a link meanwhile.
func _hash_folder(path: String, entries: Array) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var paths := entries.map(func(e): return str(e["path"]))
	paths.sort()
	for p in paths:
		if _link_in_path(path, str(p)):
			return ""
		ctx.update(str(p).to_utf8_buffer())
		ctx.update(FileAccess.get_sha256(path.path_join(p)).to_utf8_buffer())
	return ctx.finish().hex_encode()


## Reads one validated package file for copying or packing. Re-checks that no part of its path
## became a link and that its size is still the validated one before reading anything.
## Returns {ok, data, error}.
func _read_entry(base: String, e: Dictionary) -> Dictionary:
	var rel := str(e["path"])
	if _link_in_path(base, rel):
		return {"ok": false, "data": PackedByteArray(), "error": "'%s' became a link" % rel}
	var fa := FileAccess.open(base.path_join(rel), FileAccess.READ)
	if fa == null:
		return {"ok": false, "data": PackedByteArray(), "error": "cannot read '%s'" % rel}
	var n := fa.get_length()
	if n != int(e["size"]) or n > int(limits["file_bytes"]):
		return {"ok": false, "data": PackedByteArray(), "error": "'%s' changed after it was checked" % rel}
	var data := fa.get_buffer(n)
	if data.size() != n:
		return {"ok": false, "data": PackedByteArray(), "error": "cannot read '%s'" % rel}
	return {"ok": true, "data": data, "error": ""}


## Copies exactly the validated `entries` of folder `src` into `dst` (never through a link,
## nothing the walk did not validate). Returns "" or the problem.
func _copy_entries(src: String, dst: String, entries: Array) -> String:
	if entries.size() > int(limits["files"]):
		return "too many files"
	for e in entries:
		var r := _read_entry(src, e)
		if not r["ok"]:
			return str(r["error"])
		var out := dst.path_join(str(e["path"]))
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		var fa := FileAccess.open(out, FileAccess.WRITE)
		if fa == null:
			return "cannot write %s" % out
		fa.store_buffer(r["data"])
		fa.close()
	return ""


## Deletes a temporary copy made by _copy_entries (only the files it wrote, then empty folders).
func _remove_copy(dst: String, entries: Array) -> void:
	var dirs := {}
	for e in entries:
		var rel := str(e["path"])
		DirAccess.remove_absolute(dst.path_join(rel))
		var d := rel.get_base_dir()
		while d != "":
			dirs[d] = true
			d = d.get_base_dir()
	var ordered: Array = dirs.keys()
	ordered.sort_custom(func(a, b): return str(a).length() > str(b).length())
	for d2 in ordered:
		DirAccess.remove_absolute(dst.path_join(str(d2)))
	DirAccess.remove_absolute(dst)


static func _mb(b: int) -> String:
	return "%.1f MB" % (b / 1048576.0)


## "1.2.3" vs "1.10.0" -> -1/0/1
static func compare_versions(a: String, b: String) -> int:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in 3:
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return 1 if x > y else -1
	return 0


## Version requirement: "*", "1.2.0" / ">=1.2.0" (at least, same major; for 0.x the same minor),
## "=1.2.0" (exact).
static func version_satisfies(have: String, want: String) -> bool:
	want = want.strip_edges()
	if want == "" or want == "*":
		return true
	if want.begins_with("="):
		return compare_versions(have, want.substr(1)) == 0
	want = want.trim_prefix(">=").trim_prefix("^")
	var h := have.split(".")
	var w := want.split(".")
	if int(h[0]) != int(w[0]):
		return false
	if int(w[0]) == 0 and (h.size() < 2 or w.size() < 2 or int(h[1]) != int(w[1])):
		return false
	return compare_versions(have, want) >= 0


func game_version_ok(want: String) -> bool:
	return version_satisfies(Saves.game_version(), want)


# ---------------------------------------------------------------------------------------------
# enabling, sets, consent

func info_of(id: String) -> Dictionary:
	for i in available:
		if str(i["id"]) == id:
			return i
	return {}


func enabled_ids() -> Array:
	return (sets.get(active_set, []) as Array).duplicate()


func is_enabled(id: String) -> bool:
	return id in enabled_ids()


## Capabilities of `id` that still need the player's consent before it can be enabled.
func consent_needed(id: String) -> Array:
	var info := info_of(id)
	if info.is_empty():
		return []
	var have: Array = consent.get("%s@%s" % [id, info["version"]], [])
	return (info["capabilities"] as Array).filter(func(c): return str(c) in CONSENT_CAPABILITIES and not c in have)


func grant_consent(id: String, caps: Array) -> void:
	var info := info_of(id)
	if info.is_empty():
		return
	var key := "%s@%s" % [id, info["version"]]
	var have: Array = consent.get(key, [])
	for c in caps:
		if not c in have:
			have.append(c)
	consent[key] = have
	_save_sets()


## Enables/disables a mod in the active set. Enabling also enables its (available) dependencies;
## disabling also disables mods that depend on it. Returns {ok, changed: [ids], message,
## needs_consent: [caps]}. Call apply() afterwards (the Mods screen does) to reload content.
func set_enabled(id: String, on: bool) -> Dictionary:
	var ids := enabled_ids()
	var changed := []
	if on:
		var info := info_of(id)
		if info.is_empty():
			return {"ok": false, "changed": [], "message": "'%s' is not installed" % id, "needs_consent": []}
		if not info["errors"].is_empty():
			return {"ok": false, "changed": [], "message": "%s cannot be enabled: %s" % [info["name"], info["errors"][0]], "needs_consent": []}
		var need := consent_needed(id)
		if not need.is_empty():
			return {"ok": false, "changed": [], "message": "%s needs your consent first" % info["name"], "needs_consent": need}
		var queue := [id]
		while not queue.is_empty():
			var cur: String = queue.pop_front()
			if cur in ids:
				continue
			ids.append(cur)
			changed.append(cur)
			for r in info_of(cur).get("requires", []):
				var rid := str((r as Dictionary).get("id", "")) if typeof(r) == TYPE_DICTIONARY else str(r)
				if rid != "core" and not info_of(rid).is_empty() and not rid in ids:
					queue.append(rid)
	else:
		var queue2 := [id]
		while not queue2.is_empty():
			var cur2: String = queue2.pop_front()
			if not cur2 in ids:
				continue
			ids.erase(cur2)
			changed.append(cur2)
			for other in ids:
				for r in info_of(str(other)).get("requires", []):
					var rid2 := str((r as Dictionary).get("id", "")) if typeof(r) == TYPE_DICTIONARY else str(r)
					if rid2 == cur2:
						queue2.append(other)
	ids.sort()
	sets[active_set] = ids
	_save_sets()
	var msg := ""
	if changed.size() > 1:
		msg = ("Also enabled: %s" if on else "Also disabled (they depend on it): %s") % ", ".join(changed.slice(1))
	return {"ok": true, "changed": changed, "message": msg, "needs_consent": []}


## Uses exactly these mods (dedicated servers, --mods, tests). Unknown ids are reported.
func enable_only(ids: Array) -> Dictionary:
	var ok := []
	var missing := []
	for i in ids:
		var id := str(i).strip_edges()
		if id == "":
			continue
		if info_of(id).is_empty():
			missing.append(id)
		else:
			ok.append(id)
	ok.sort()
	sets[active_set] = ok
	apply()
	return {"enabled": load_order.duplicate(), "missing": missing}


func use_set(name_: String) -> bool:
	if not sets.has(name_):
		return false
	active_set = name_
	_save_sets()
	apply()
	return true


func save_set_as(name_: String, ids: Array = []) -> String:
	var n := name_.strip_edges().substr(0, 40)
	if n == "":
		n = "Set %d" % (sets.size() + 1)
	sets[n] = ids.duplicate() if not ids.is_empty() else enabled_ids()
	_save_sets()
	return n


func rename_set(old: String, new_name: String) -> bool:
	var n := new_name.strip_edges().substr(0, 40)
	if not sets.has(old) or n == "" or sets.has(n):
		return false
	sets[n] = sets[old]
	sets.erase(old)
	if active_set == old:
		active_set = n
	_save_sets()
	return true


func delete_set(name_: String) -> bool:
	if not sets.has(name_) or sets.size() <= 1:
		return false
	sets.erase(name_)
	if active_set == name_:
		active_set = sets.keys()[0]
		apply()
	_save_sets()
	return true


## Mods referenced by the active set that are not installed (kept so reinstalling restores them).
func missing_in_active() -> Array:
	return enabled_ids().filter(func(id): return info_of(str(id)).is_empty())


func _load_sets() -> void:
	var r := Saves.read_json(_sets_path, "modsets", SETS_FORMAT)
	if not r["ok"]:
		if r["exists"]:
			Log.w("mods", "mod sets unreadable (%s); starting with an empty set" % r["error"])
			if r["newer"]:
				# never rewrite what a newer game saved: changes this session are not stored
				sets_read_only = true
				sets_error = "Your mod sets were saved by a newer version of the game. This version leaves that file untouched, so mod set changes made now are not saved."
				Log.w("mods", "%s is read-only for this session (written by a newer game version)" % _sets_path.get_file())
			else:
				Saves.quarantine(_sets_path)
		return
	var d: Dictionary = r["data"]
	var s = d.get("sets", {})
	if typeof(s) == TYPE_DICTIONARY and not s.is_empty():
		sets = s
	active_set = str(d.get("active", "Default"))
	if not sets.has(active_set):
		active_set = sets.keys()[0]
	consent = d.get("consent", {}) if typeof(d.get("consent")) == TYPE_DICTIONARY else {}


func _save_sets() -> void:
	if sets_read_only:
		return
	Saves.write_json(_sets_path, "modsets", SETS_FORMAT, {"active": active_set, "sets": sets, "consent": consent})


# ---------------------------------------------------------------------------------------------
# load order & applying

## Deterministic order: dependencies (requires) and soft load_after first, ties by id.
## Returns {order: [ids], errors: {id: [messages]}}; mods with errors are left out.
func resolve_order(ids: Array) -> Dictionary:
	var errors := {}
	var pool := {}
	for i in ids:
		var id := str(i)
		var info := info_of(id)
		if info.is_empty():
			errors[id] = ["not installed"]
			continue
		if not info["errors"].is_empty():
			errors[id] = (info["errors"] as Array).duplicate()
			continue
		if not consent_needed(id).is_empty():
			errors[id] = ["needs consent for: %s" % ", ".join(consent_needed(id))]
			continue
		pool[id] = info
	# drop mods whose requirements are missing/disabled/wrong version (repeat until stable)
	var changed := true
	while changed:
		changed = false
		for id in pool.keys():
			for r in pool[id]["requires"]:
				var rid := str((r as Dictionary).get("id", "")) if typeof(r) == TYPE_DICTIONARY else str(r)
				var want := str((r as Dictionary).get("version", "*")) if typeof(r) == TYPE_DICTIONARY else "*"
				if rid == "core":
					if not version_satisfies(str(Content.packages[0]["version"]) if not Content.packages.is_empty() else "1.0.0", want):
						errors[id] = errors.get(id, []) + ["needs core content %s" % want]
						pool.erase(id)
						changed = true
						break
					continue
				if not pool.has(rid):
					var why := "requires '%s' %s, which is %s" % [rid, want, "not enabled" if not info_of(rid).is_empty() else "not installed"]
					errors[id] = errors.get(id, []) + [why]
					pool.erase(id)
					changed = true
					break
				if not version_satisfies(str(pool[rid]["version"]), want):
					errors[id] = errors.get(id, []) + ["requires '%s' %s but %s is installed" % [rid, want, pool[rid]["version"]]]
					pool.erase(id)
					changed = true
					break
	# Kahn's algorithm with a sorted ready list
	var indeg := {}
	var edges := {}
	for id in pool:
		indeg[id] = 0
		edges[id] = []
	for id in pool:
		var deps := []
		for r in pool[id]["requires"]:
			deps.append(str((r as Dictionary).get("id", "")) if typeof(r) == TYPE_DICTIONARY else str(r))
		for la in pool[id]["load_after"]:
			deps.append(str(la))
		for dep in deps:
			if pool.has(dep) and dep != id and not id in edges[dep]:
				edges[dep].append(id)
				indeg[id] += 1
	var ready := indeg.keys().filter(func(k): return indeg[k] == 0)
	ready.sort()
	var order := []
	while not ready.is_empty():
		var cur: String = ready.pop_front()
		order.append(cur)
		for nx in edges[cur]:
			indeg[nx] -= 1
			if indeg[nx] == 0:
				ready.append(nx)
				ready.sort()
	for id in pool:
		if not id in order:
			errors[id] = errors.get(id, []) + ["dependency cycle (check requires/load_after)"]
	return {"order": order, "errors": errors}


## Reloads Content with core + the active set's mods. Problems are kept per mod in load_report.
func apply() -> void:
	load_report.clear()
	var ids := [] if safe_mode else enabled_ids()
	var res := resolve_order(ids)
	for id in res["errors"]:
		load_report[id] = (res["errors"][id] as Array).duplicate()
	var pkgs := []
	load_order.clear()
	for id in res["order"]:
		var info := info_of(id)
		var path := str(info["path"])
		if str(info["kind"]) in ["archive", "example"]:
			path = _extract(info)
			if path == "":
				load_report[id] = ["could not unpack the archive (it changed since it was checked, or does not match its checked listing); rescan and try again"]
				continue
		# Content reads only these validated files, and only overrides core with this consent
		pkgs.append({"id": id, "version": info["version"], "path": path, "manifest": info["manifest"], "hash": info["hash"],
			"files": validated_files(info), "consent": (consent.get("%s@%s" % [id, info["version"]], []) as Array).duplicate()})
		load_order.append(id)
	Content.reload(pkgs)
	for e in Content.errors:
		var pid := str(e).get_slice("/", 0).get_slice(":", 0)
		if pid in load_order:
			var arr: Array = load_report.get(pid, [])
			arr.append(str(e))
			load_report[pid] = arr
	Log.i("mods", "loaded %d mod(s): %s" % [load_order.size(), ", ".join(load_order) if not load_order.is_empty() else "(none)"])
	mods_changed.emit()


## Relative "/"-separated paths of a package's validated files (what Content may read).
func validated_files(info: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for e in info.get("_entries", []):
		out.append(str(e["path"]).replace("\\", "/"))
	return out


## Unpacks a checked archive into its hash-keyed cache folder. Refuses (returns "") unless the
## file still has the checked hash and Godot's zip reader lists exactly the entries that
## zip_directory() validated, with the same sizes: the two readers must agree on every byte that
## is extracted.
func _extract(info: Dictionary) -> String:
	var dst := mods_dir().path_join(".cache").path_join("%s-%s-%s" % [info["id"], info["version"], str(info["hash"]).substr(0, 12)])
	if FileAccess.file_exists(dst.path_join(".complete")):
		return dst
	var src := str(info["path"])
	if str(info["hash"]) == "" or FileAccess.get_sha256(src) != str(info["hash"]):
		Log.w("mods", "%s changed since it was checked; not unpacked" % src.get_file())
		return ""
	var prefix := str(info.get("root_prefix", ""))
	var want := {}           ## full entry name -> validated size
	for e in info.get("_entries", []):
		want[prefix + str(e["path"])] = int(e["size"])
	var zr := ZIPReader.new()
	if zr.open(src) != OK:
		return ""
	var seen := {}
	for f in zr.get_files():
		if f.ends_with("/"):
			continue
		if seen.has(f) or not want.has(f):
			Log.w("mods", "%s: the zip reader sees '%s', which was not checked; not unpacked" % [src.get_file(), f.c_escape()])
			zr.close()
			return ""
		seen[f] = true
	if seen.size() != want.size():
		Log.w("mods", "%s: the zip reader and the checked listing disagree; not unpacked" % src.get_file())
		zr.close()
		return ""
	DirAccess.make_dir_recursive_absolute(dst)
	for f2 in want:
		var full := str(f2)
		var rel := full.substr(prefix.length()).replace("\\", "/")
		# defence in depth: the entry list was validated in inspect_archive
		if rel.begins_with("/") or rel.contains(":") or rel.split("/").has("..") or not rel.get_extension().to_lower() in ALLOWED_EXT:
			zr.close()
			return ""
		var data := zr.read_file(full)
		if data.size() != int(want[full]):
			Log.w("mods", "%s: '%s' unpacked to a different size than checked; not unpacked" % [src.get_file(), rel])
			zr.close()
			return ""
		var out := dst.path_join(rel)
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		var fa := FileAccess.open(out, FileAccess.WRITE)
		if fa == null:
			zr.close()
			return ""
		fa.store_buffer(data)
		fa.close()
	zr.close()
	var mark := FileAccess.open(dst.path_join(".complete"), FileAccess.WRITE)
	if mark:
		mark.store_string(str(info["hash"]))
	return dst


# ---------------------------------------------------------------------------------------------
# install / upgrade / remove / share

## Imports a package (archive file or folder) into the user mods folder after validating it.
## Same id: a newer version upgrades in place (keeping its enabled state), the same version is
## reinstalled, an older one needs allow_downgrade. Returns {ok, id, message, errors}.
## The new copy is written under a temporary name and verified first; only then is the installed
## version moved aside (to mods/.removed) and the copy renamed into place, so a failed import never
## leaves the mod uninstalled. Importing the installed package itself changes nothing.
func import_package(src: String, allow_downgrade := false) -> Dictionary:
	src = src.replace("\\", "/")
	var info: Dictionary
	if DirAccess.dir_exists_absolute(src):
		info = inspect_folder(src, "folder")
	elif FileAccess.file_exists(src) and src.get_extension().to_lower() in ARCHIVE_EXT:
		info = inspect_archive(src)
	else:
		return {"ok": false, "id": "", "message": "Not a mod package: %s (expected a folder or .critmod/.zip)" % src.get_file(), "errors": []}
	if not info["errors"].is_empty():
		return {"ok": false, "id": info["id"], "message": "%s was rejected: %s" % [src.get_file(), info["errors"][0]], "errors": (info["errors"] as Array).duplicate()}
	var id := str(info["id"])
	var cur := info_of(id)
	var verb := "Installed"
	var installed := not cur.is_empty() and str(cur["kind"]) != "example"
	if installed:
		var c := compare_versions(str(info["version"]), str(cur["version"]))
		if c < 0 and not allow_downgrade:
			return {"ok": false, "id": id, "message": "%s %s is older than the installed %s; confirm to downgrade" % [info["name"], info["version"], cur["version"]], "errors": [], "downgrade": true}
		verb = "Upgraded" if c > 0 else ("Reinstalled" if c == 0 else "Downgraded")
		if _same_path(src, str(cur["path"])):
			# the installed package itself: nothing to copy, nothing to move aside
			refresh()
			return {"ok": true, "id": id, "message": "%s is already installed (%s %s)" % [src.get_file(), info["name"], info["version"]], "errors": []}
	var is_archive := str(info["kind"]) == "archive"
	var dst := mods_dir().path_join("%s-%s.critmod" % [id, info["version"]] if is_archive else id)
	var tmp := mods_dir().path_join(".importing-%s-%d%s" % [id, Time.get_ticks_usec(), ".part" if is_archive else ""])
	var problem := _stage_copy(src, tmp, info)
	if problem != "":
		return {"ok": false, "id": id, "message": "Could not copy %s into the mods folder: %s. Nothing was changed." % [src.get_file(), problem], "errors": [problem]}
	# swap: the old version is kept in mods/.removed, never deleted
	var moved := {}          ## original path -> where it was moved
	for old in ([str(cur["path"])] if installed else []) + [dst]:
		if (FileAccess.file_exists(old) or DirAccess.dir_exists_absolute(old)) and not moved.has(old):
			var aside := _move_aside(old)
			if aside == "":
				_unstage(tmp, info)
				_restore(moved)
				return {"ok": false, "id": id, "message": "Could not replace the installed copy of %s. Nothing was changed." % info["name"], "errors": []}
			moved[old] = aside
	if DirAccess.rename_absolute(tmp, dst) != OK:
		_unstage(tmp, info)
		_restore(moved)
		return {"ok": false, "id": id, "message": "Could not move %s into place. Nothing was changed." % src.get_file(), "errors": []}
	refresh()
	if is_enabled(id):
		apply()
	return {"ok": true, "id": id, "message": "%s %s %s" % [verb, info["name"], info["version"]], "errors": []}


## Copies a validated package to the temporary name `tmp` and checks the copy is exactly what was
## validated (same hash). Returns "" or the problem (and leaves nothing behind).
func _stage_copy(src: String, tmp: String, info: Dictionary) -> String:
	if simulate_copy_failure:
		return "simulated copy failure"
	if str(info["kind"]) == "archive":
		if not _copy_file(src, tmp):
			DirAccess.remove_absolute(tmp)
			return "the file could not be copied"
		if FileAccess.get_sha256(tmp) != str(info["hash"]):
			DirAccess.remove_absolute(tmp)
			return "the file changed while it was being copied"
		return ""
	var entries: Array = info["_entries"]
	var err := _copy_entries(src, tmp, entries)
	if err == "":
		var check := inspect_folder(tmp, "folder")
		if not check["errors"].is_empty() or str(check["hash"]) != str(info["hash"]):
			err = "the folder changed while it was being copied"
	if err != "":
		_remove_copy(tmp, entries)
	return err


func _unstage(tmp: String, info: Dictionary) -> void:
	if str(info["kind"]) == "archive":
		DirAccess.remove_absolute(tmp)
	else:
		_remove_copy(tmp, info["_entries"])


## Puts packages moved aside by a failed import back where they were.
func _restore(moved: Dictionary) -> void:
	for orig in moved:
		DirAccess.rename_absolute(str(moved[orig]), str(orig))


static func _same_path(a: String, b: String) -> bool:
	var x := a.replace("\\", "/").simplify_path().trim_suffix("/")
	var y := b.replace("\\", "/").simplify_path().trim_suffix("/")
	return x.to_lower() == y.to_lower() if OS.get_name() == "Windows" else x == y


## Removes an installed package (moved to mods/.removed, never deleted outright). The id stays
## in mod sets so reinstalling it restores the setup; until then it is reported as missing.
func uninstall(id: String) -> bool:
	var info := info_of(id)
	if info.is_empty() or str(info["kind"]) == "example":
		return false
	_move_aside(str(info["path"]))
	refresh()
	if is_enabled(id):
		apply()
	return true


## Moves a package into mods/.removed under a name that is not taken yet (a rename onto an
## existing file would replace it). Returns the new path, or "" if it could not be moved.
func _move_aside(path: String) -> String:
	var bin := mods_dir().path_join(".removed")
	DirAccess.make_dir_recursive_absolute(bin)
	var stem := "%d_%s" % [int(Time.get_unix_time_from_system() * 1000.0), path.trim_suffix("/").get_file()]
	var dst := bin.path_join(stem)
	var n := 2
	while FileAccess.file_exists(dst) or DirAccess.dir_exists_absolute(dst):
		dst = bin.path_join("%s_%d" % [stem, n])
		n += 1
	return dst if DirAccess.rename_absolute(path, dst) == OK else ""


## Byte copy that also works for files inside the game package (res://).
func _copy_file(src: String, dst: String) -> bool:
	var data := FileAccess.get_file_as_bytes(src)
	if data.is_empty() and FileAccess.get_open_error() != OK:
		return false
	var fa := FileAccess.open(dst, FileAccess.WRITE)
	if fa == null:
		return false
	fa.store_buffer(data)
	fa.close()
	return true


## Writes a shareable .critmod archive of an installed or example package into `dst_dir`
## (default: the user "packages" folder). Returns the archive path or "". A folder package is
## checked again first and only its validated files are packed (links are never followed).
func export_package(id: String, dst_dir := "") -> String:
	var info := info_of(id)
	if info.is_empty() or not info["errors"].is_empty():
		return ""
	if dst_dir == "":
		dst_dir = Paths.dir("packages")
	DirAccess.make_dir_recursive_absolute(dst_dir)
	var out := dst_dir.path_join("%s-%s.critmod" % [id, info["version"]])
	if str(info["kind"]) in ["archive", "example"]:
		return out if _copy_file(str(info["path"]), out) else ""
	var base := str(info["path"])
	var fresh := inspect_folder(base, str(info["kind"]))
	if not fresh["errors"].is_empty() or str(fresh["id"]) != id:
		return ""
	out = dst_dir.path_join("%s-%s.critmod" % [id, fresh["version"]])
	var entries: Array = (fresh["_entries"] as Array).duplicate()
	entries.sort_custom(func(a, b): return str(a["path"]) < str(b["path"]))
	var zp := ZIPPacker.new()
	if zp.open(out) != OK:
		return ""
	for e in entries:
		var r := _read_entry(base, e)
		if not r["ok"]:
			zp.close()
			DirAccess.remove_absolute(out)
			return ""
		zp.start_file(str(e["path"]))
		zp.write_file(r["data"])
		zp.close_file()
	zp.close()
	return out


# ---------------------------------------------------------------------------------------------
# compatibility (multiplayer, saves)

## [{id, version, hash, client_only}] for every loaded package (core first).
func fingerprint() -> Array:
	return Content.package_list()


## Compares our gameplay packages with a peer's/server's list. Presentation-only (client_only)
## packages never block. Returns {compatible, missing, extra, mismatched, messages}.
func compare(remote: Array) -> Dictionary:
	var mine := {}
	for p in fingerprint():
		if not bool(p.get("client_only", false)):
			mine[str(p["id"])] = p
	var theirs := {}
	for p in remote:
		if typeof(p) == TYPE_DICTIONARY and not bool(p.get("client_only", false)):
			theirs[str(p.get("id", ""))] = p
	var missing := []
	var extra := []
	var mismatched := []
	var msgs := []
	for id in theirs:
		if not mine.has(id):
			missing.append(id)
			msgs.append("Missing mod: %s %s (install it, then enable it)" % [id, theirs[id].get("version", "?")])
		elif str(mine[id]["version"]) != str(theirs[id].get("version", "")) or (str(theirs[id].get("hash", "")) != "" and str(mine[id].get("hash", "")) != "" and str(mine[id]["hash"]) != str(theirs[id]["hash"])):
			mismatched.append(id)
			msgs.append("Different version of %s: you have %s, the host has %s" % [id, mine[id]["version"], theirs[id].get("version", "?")])
	for id in mine:
		if not theirs.has(id):
			extra.append(id)
			msgs.append("You have %s %s enabled but the host does not (disable it to join)" % [id, mine[id]["version"]])
	return {"compatible": missing.is_empty() and extra.is_empty() and mismatched.is_empty(), "missing": missing,
		"extra": extra, "mismatched": mismatched, "messages": msgs}


## For saves (runs, presets, arenas) that recorded the packages they used: what is missing now.
## Never modifies anything. Returns {ok, missing: [ids], changed: [ids], message}.
func check_requirements(recorded: Array) -> Dictionary:
	var now := {}
	for p in fingerprint():
		now[str(p["id"])] = p
	var missing := []
	var changed := []
	for p in recorded:
		if typeof(p) != TYPE_DICTIONARY or bool(p.get("client_only", false)):
			continue
		var id := str(p.get("id", ""))
		if not now.has(id):
			missing.append(id)
		elif str(now[id]["version"]) != str(p.get("version", "")):
			changed.append(id)
	var msg := ""
	if not missing.is_empty():
		msg = "Needs mod(s) that are not loaded: %s. Enable or reinstall them to continue; nothing was changed." % ", ".join(missing)
	elif not changed.is_empty():
		msg = "Made with different versions of: %s. It may behave differently." % ", ".join(changed)
	return {"ok": missing.is_empty(), "missing": missing, "changed": changed, "message": msg}
