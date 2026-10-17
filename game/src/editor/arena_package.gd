class_name ArenaPackage
## Arena content packages: a zip (ZIPPacker/ZIPReader) shaped like a regular content package so
## compatible multiplayer peers and the mod loader can use it:
##   manifest.json            content-package manifest + {format, format_version, kind:"arena_package",
##                            arenas: [{id, file, sha256, content_hash, base}], package_hash}
##   arenas/<slug>.json       format-2 arena layouts (schema arena.schema.json)
##   preview.png              optional thumbnail
## Import never trusts the archive: the central directory is parsed BEFORE anything is
## decompressed (entry count, names, declared sizes, compression ratio, encryption), every path is
## whitelisted (no absolute paths, drive letters, backslashes or ".."), decompressed sizes and
## sha256 hashes must match the manifest, the manifest and every arena are schema-validated and
## their bases must exist. Only then are layouts installed (as saved layouts) for the editor and
## for matches (ArenaLibrary.resolve). Peers compare arenas by id + content_hash (see
## docs/ARENAS_AND_EDITOR.md "Multiplayer").

const FORMAT := "critterweight-arena-package"
const FORMAT_VERSION := 1
const MAX_ZIP_BYTES := 2 * 1024 * 1024
const MAX_ENTRIES := 16
const MAX_JSON_BYTES := 256 * 1024
const MAX_PREVIEW_BYTES := 1024 * 1024
const MAX_TOTAL_BYTES := 2 * 1024 * 1024
const MAX_RATIO := 60.0
const MAX_ARENAS := 8
const NAME_RE := "^(manifest\\.json|preview\\.png|arenas/[a-z0-9_]{1,48}\\.json|arenas/)$"


static func packages_dir() -> String:
	return Paths.dir("packages").path_join("arenas")


static func _canonical_json(d: Dictionary) -> String:
	return JSON.stringify(ArenaDef.canonical(d), "\t", true, true)


## Hash identifying a package's gameplay content: sorted "id|content_hash" lines.
static func package_hash(arena_entries: Array) -> String:
	var lines := []
	for e in arena_entries:
		lines.append("%s|%s" % [str(e["id"]), str(e["content_hash"])])
	lines.sort()
	return "\n".join(lines).sha256_text()


## Writes `layouts` (format-2 dicts) into a package zip. meta: {id, name, version, author, description}.
## Returns {ok, path, hash, error}.
static func export_package(layouts: Array, zip_path: String, meta := {}) -> Dictionary:
	if layouts.is_empty() or layouts.size() > MAX_ARENAS:
		return {"ok": false, "path": zip_path, "hash": "", "error": "a package holds 1-%d arenas" % MAX_ARENAS}
	var files := {}
	var entries := []
	for l in layouts:
		var d: Dictionary = (l as Dictionary).duplicate(true)
		ArenaLibrary._strip_uids(d)
		d.erase("base_def")
		var errs := Schema.validate_named(d, "arena")
		if not errs.is_empty():
			return {"ok": false, "path": zip_path, "hash": "", "error": "; ".join(errs)}
		var a := ArenaDef.from_dict(d)
		if not a.errors.is_empty():
			return {"ok": false, "path": zip_path, "hash": "", "error": "; ".join(a.errors)}
		var fname := "arenas/%s.json" % ArenaEditModel.slug_id(str(d["id"]).replace(":", "_"))
		var text := _canonical_json(d)
		files[fname] = text.to_utf8_buffer()
		entries.append({"id": str(d["id"]), "file": fname, "sha256": text.sha256_text(), "content_hash": a.content_hash(), "base": a.base, "name": a.display_name})
	var first: Dictionary = layouts[0]
	var pid := str(meta.get("id", ArenaEditModel.slug_id(str(first.get("id", "arena")).replace(":", "_"))))
	if pid.length() < 3:
		pid += "_pkg"
	var manifest := {"format": FORMAT, "format_version": FORMAT_VERSION, "kind": "arena_package", "id": pid.substr(0, 32),
		"name": str(meta.get("name", first.get("name", "Arena Package"))).substr(0, 48), "version": str(meta.get("version", "1.0.0")),
		"game_version": str(ProjectSettings.get_setting("application/config/version", "0.0.0")), "author": str(meta.get("author", first.get("author", ""))).substr(0, 48),
		"description": str(meta.get("description", first.get("description", ""))).substr(0, 600),
		"requires": [{"id": "core", "version": str(Content.packages[0]["version"]) if not Content.packages.is_empty() else "1.0.0"}],
		"load_after": [], "capabilities": [], "client_only": false, "arenas": entries,
		"created": Time.get_datetime_string_from_system(true), "package_hash": package_hash(entries)}
	var zp := ZIPPacker.new()
	DirAccess.make_dir_recursive_absolute(zip_path.get_base_dir())
	var err := zp.open(zip_path)
	if err != OK:
		return {"ok": false, "path": zip_path, "hash": "", "error": "cannot create %s: %s" % [zip_path, error_string(err)]}
	zp.start_file("manifest.json")
	zp.write_file(_canonical_json(manifest).to_utf8_buffer())
	zp.close_file()
	for fname2 in files:
		zp.start_file(fname2)
		zp.write_file(files[fname2])
		zp.close_file()
	zp.close()
	return {"ok": true, "path": zip_path, "hash": manifest["package_hash"], "error": "", "manifest": manifest}


# =====================================================================================
# Pre-scan: parse the zip central directory without decompressing anything
# =====================================================================================

static func _u16(b: PackedByteArray, o: int) -> int:
	return b[o] | (b[o + 1] << 8)


static func _u32(b: PackedByteArray, o: int) -> int:
	return b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)


## Returns {ok, error, entries: [{name, method, flags, csize, usize}]}.
static func scan_zip(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "cannot open package", "entries": []}
	var length := f.get_length()
	if length > MAX_ZIP_BYTES:
		return {"ok": false, "error": "package is too large (%d KB > %d KB)" % [int(length / 1024.0), int(MAX_ZIP_BYTES / 1024.0)], "entries": []}
	if length < 22:
		return {"ok": false, "error": "not a zip archive", "entries": []}
	var tail_len := mini(length, 22 + 65535)
	f.seek(length - tail_len)
	var tail := f.get_buffer(tail_len)
	var eocd := -1
	for i in range(tail.size() - 22, -1, -1):
		if tail[i] == 0x50 and tail[i + 1] == 0x4b and tail[i + 2] == 0x05 and tail[i + 3] == 0x06:
			eocd = i
			break
	if eocd < 0:
		return {"ok": false, "error": "not a zip archive (no central directory)", "entries": []}
	var count := _u16(tail, eocd + 10)
	var cd_size := _u32(tail, eocd + 12)
	var cd_off := _u32(tail, eocd + 16)
	if count > MAX_ENTRIES:
		return {"ok": false, "error": "too many files in the package (%d > %d)" % [count, MAX_ENTRIES], "entries": []}
	if cd_off + cd_size > length or cd_size > 64 * 1024:
		return {"ok": false, "error": "corrupt central directory", "entries": []}
	f.seek(cd_off)
	var cd := f.get_buffer(cd_size)
	var entries := []
	var o := 0
	for k in count:
		if o + 46 > cd.size() or _u32(cd, o) != 0x02014b50:
			return {"ok": false, "error": "corrupt central directory entry %d" % k, "entries": []}
		var flags := _u16(cd, o + 8)
		var method := _u16(cd, o + 10)
		var csize := _u32(cd, o + 20)
		var usize := _u32(cd, o + 24)
		var nlen := _u16(cd, o + 28)
		var xlen := _u16(cd, o + 30)
		var clen := _u16(cd, o + 32)
		if o + 46 + nlen > cd.size():
			return {"ok": false, "error": "corrupt file name", "entries": []}
		var name_ := cd.slice(o + 46, o + 46 + nlen).get_string_from_utf8()
		entries.append({"name": name_, "method": method, "flags": flags, "csize": csize, "usize": usize})
		o += 46 + nlen + xlen + clen
	return {"ok": true, "error": "", "entries": entries}


## Path whitelist + traversal guard for one archive entry name.
static func safe_entry_name(name_: String) -> String:
	if name_ == "" or name_.length() > 80:
		return "empty or overlong file name"
	if name_.begins_with("/") or name_.contains("\\") or name_.contains("..") or name_.contains(":") or name_.contains("//"):
		return "unsafe path '%s'" % name_
	# full match: PCRE's "$" would also accept a name ending in a line break
	if not Schema.full_match(NAME_RE, name_):
		return "unexpected file '%s'" % name_.c_escape()
	return ""


# =====================================================================================
# Import
# =====================================================================================

## Validates and (unless dry_run) installs a package. Returns
## {ok, errors: [], warnings: [], manifest, arenas: [dicts], hash, installed: [paths]}.
static func import_package(zip_path: String, install_dir := "", dry_run := false) -> Dictionary:
	var res := {"ok": false, "errors": [], "warnings": [], "manifest": {}, "arenas": [], "hash": "", "installed": []}
	var scan := scan_zip(zip_path)
	if not bool(scan["ok"]):
		res["errors"].append(scan["error"])
		return res
	var names := {}
	var total := 0
	for e in scan["entries"]:
		var n := str(e["name"])
		var bad := safe_entry_name(n)
		if bad != "":
			res["errors"].append(bad)
			continue
		if names.has(n):
			res["errors"].append("duplicate file '%s'" % n)
		names[n] = e
		if int(e["flags"]) & 1:
			res["errors"].append("encrypted entries are not allowed ('%s')" % n)
		if int(e["method"]) not in [0, 8]:
			res["errors"].append("unsupported compression in '%s'" % n)
		var usize := int(e["usize"])
		var cap := MAX_PREVIEW_BYTES if n == "preview.png" else MAX_JSON_BYTES
		if n.ends_with("/"):
			cap = 0
		if usize > cap:
			res["errors"].append("'%s' is too large (%d KB > %d KB)" % [n, int(usize / 1024.0), int(cap / 1024.0)])
		if int(e["csize"]) > 0 and float(usize) / float(e["csize"]) > MAX_RATIO:
			res["errors"].append("'%s' has a suspicious compression ratio" % n)
		total += usize
	if total > MAX_TOTAL_BYTES:
		res["errors"].append("package expands to more than %d KB" % int(MAX_TOTAL_BYTES / 1024.0))
	if not names.has("manifest.json"):
		res["errors"].append("manifest.json is missing")
	if not (res["errors"] as Array).is_empty():
		return res
	var zr := ZIPReader.new()
	if zr.open(zip_path) != OK:
		res["errors"].append("cannot read the package")
		return res
	var mbytes := zr.read_file("manifest.json")
	if mbytes.size() != int(names["manifest.json"]["usize"]):
		res["errors"].append("manifest.json size does not match the archive directory")
		zr.close()
		return res
	var json := JSON.new()
	if json.parse(mbytes.get_string_from_utf8()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		res["errors"].append("manifest.json is not valid JSON")
		zr.close()
		return res
	var manifest: Dictionary = json.data
	res["manifest"] = manifest
	for e2 in Schema.validate_named(manifest, "manifest", "manifest"):
		res["errors"].append(e2)
	if str(manifest.get("format", "")) != FORMAT:
		res["errors"].append("manifest: not an arena package (format '%s')" % str(manifest.get("format", "")))
	if int(manifest.get("format_version", 0)) < 1 or int(manifest.get("format_version", 0)) > FORMAT_VERSION:
		res["errors"].append("manifest: unsupported package format version %s" % str(manifest.get("format_version", "?")))
	var list = manifest.get("arenas", null)
	if typeof(list) != TYPE_ARRAY or (list as Array).is_empty() or (list as Array).size() > MAX_ARENAS:
		res["errors"].append("manifest: 'arenas' must list 1-%d arenas" % MAX_ARENAS)
		list = []
	if not (res["errors"] as Array).is_empty():
		zr.close()
		return res
	var entries_for_hash := []
	for ae in list:
		if typeof(ae) != TYPE_DICTIONARY:
			res["errors"].append("manifest: bad arena entry")
			continue
		var file := str(ae.get("file", ""))
		if not names.has(file) or not file.begins_with("arenas/"):
			res["errors"].append("manifest lists '%s' which is not in the package" % file)
			continue
		var bytes := zr.read_file(file)
		if bytes.size() != int(names[file]["usize"]):
			res["errors"].append("'%s' size does not match the archive directory" % file)
			continue
		var text := bytes.get_string_from_utf8()
		if text.sha256_text() != str(ae.get("sha256", "")):
			res["errors"].append("'%s' failed its sha256 check" % file)
			continue
		var j2 := JSON.new()
		if j2.parse(text) != OK or typeof(j2.data) != TYPE_DICTIONARY:
			res["errors"].append("'%s' is not valid JSON" % file)
			continue
		var d: Dictionary = j2.data
		var serrs := Schema.validate_named(d, "arena", file)
		if not serrs.is_empty():
			res["errors"].append_array(serrs)
			continue
		if d.has("base_def"):
			res["errors"].append("'%s' defines a base; packages may only reference installed bases" % file)
			continue
		var a := ArenaDef.from_dict(d)
		if not a.errors.is_empty():
			res["errors"].append("%s: %s" % [file, "; ".join(a.errors)])
			continue
		if str(ae.get("id", "")) != a.id:
			res["errors"].append("%s: id does not match the manifest" % file)
			continue
		var want_hash := str(ae.get("content_hash", ""))
		if a.content_hash() != want_hash and a.content_hash_legacy() != want_hash:
			res["errors"].append("%s: content hash mismatch" % file)
			continue
		var v := ArenaValidator.validate(a)
		for ve in v["errors"]:
			res["warnings"].append("%s: %s" % [a.display_name, ve["message"]])
		res["arenas"].append(d)
		entries_for_hash.append({"id": a.id, "content_hash": want_hash})
	zr.close()
	if not (res["errors"] as Array).is_empty():
		res["arenas"] = []
		return res
	res["hash"] = package_hash(entries_for_hash)
	if str(manifest.get("package_hash", res["hash"])) != res["hash"]:
		res["errors"].append("package hash mismatch")
		res["arenas"] = []
		return res
	res["ok"] = true
	if dry_run:
		return res
	for d2 in res["arenas"]:
		var sv := ArenaLibrary.save_layout(d2, "", install_dir)
		if bool(sv["ok"]):
			res["installed"].append(sv["path"])
		else:
			res["warnings"].append("could not install %s: %s" % [str(d2.get("id", "")), sv["error"]])
	var keep := packages_dir().path_join("%s-%s.zip" % [str(manifest.get("id", "arena")), str(res["hash"]).substr(0, 8)])
	if install_dir == "" and zip_path != keep:
		DirAccess.make_dir_recursive_absolute(keep.get_base_dir())
		DirAccess.copy_absolute(zip_path, keep)
	return res


## For network transfer: validates and installs a package received as bytes.
static func import_bytes(bytes: PackedByteArray, install_dir := "") -> Dictionary:
	if bytes.size() > MAX_ZIP_BYTES:
		return {"ok": false, "errors": ["package is too large"], "warnings": [], "arenas": [], "hash": "", "installed": []}
	var tmp := Paths.dir("downloads").path_join("incoming_%d.zip" % Time.get_ticks_usec())
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "errors": ["cannot write a temporary file"], "warnings": [], "arenas": [], "hash": "", "installed": []}
	f.store_buffer(bytes)
	f.close()
	var r := import_package(tmp, install_dir)
	DirAccess.remove_absolute(tmp)
	return r


## Packages available locally for import (packages/arenas and downloads): [{path, name, size}].
static func list_local() -> Array:
	var out := []
	for d in [packages_dir(), Paths.dir("downloads")]:
		var da := DirAccess.open(d)
		if da == null:
			continue
		for f in da.get_files():
			if f.ends_with(".zip"):
				var fa := FileAccess.open(d.path_join(f), FileAccess.READ)
				out.append({"path": d.path_join(f), "name": f, "size": fa.get_length() if fa else 0})
	return out
