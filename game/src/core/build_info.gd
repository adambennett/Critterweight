class_name BuildInfo
extends RefCounted
## Version and build stamp (docs/RELEASES.md). The version comes from project.godot
## (application/config/version); tools/build/package.ps1 writes res://build_info.json for exports
## with the git tag, commit, dirty flag and build time. Development runs have no stamp.
##   tagged release build:  "0.9.0 (5533dcd)"
##   untagged build:        "0.9.0+5533dcd" (".dirty" when built from uncommitted changes)
##   development run:       "0.9.0-dev"

const STAMP := "res://build_info.json"

static var _info: Dictionary = {}
static var _loaded := false


static func info() -> Dictionary:
	if not _loaded:
		_loaded = true
		if FileAccess.file_exists(STAMP):
			var d = JSON.parse_string(FileAccess.get_file_as_string(STAMP))
			if d is Dictionary:
				_info = d
	return _info


static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


static func commit() -> String:
	return str(info().get("commit", ""))


static func label() -> String:
	var i := info()
	if i.is_empty():
		return "%s-dev" % version()
	if str(i.get("tag", "")) != "":
		return "%s (%s)" % [version(), commit()]
	return "%s+%s%s" % [version(), commit(), ".dirty" if bool(i.get("dirty", false)) else ""]
