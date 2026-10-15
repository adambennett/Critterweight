class_name LabRecording
extends RefCounted
## The player-facing "record my matches for imitation" switch (persisted in
## `<user data>/lab/recording.json`). When it is on, MatchScene wraps the local player's input
## source in a PolicyRecorder, so every normal match adds (obs_v1, act_v1) samples to the
## dataset "human_<creature>" — nothing about the match itself changes. Off by default.

const FILE := "recording.json"

static var _cfg := {}
static var _loaded := false
## tests redirect the switch file
static var config_path_override := ""


static func _path() -> String:
	if config_path_override != "":
		return config_path_override
	return Paths.dir("lab").path_join(FILE)


static func reload() -> void:
	_loaded = false
	_cfg = {}


static func config() -> Dictionary:
	if not _loaded:
		_cfg = LabIO.read_json(_path())
		_loaded = true
	return _cfg


static func is_enabled() -> bool:
	return bool(config().get("enabled", false))


static func set_enabled(on: bool) -> void:
	var c := config()
	c["enabled"] = on
	_cfg = c
	LabIO.write_json(_path(), c)


static func dataset_id_for(creature_id: String) -> String:
	return "human_" + creature_id


## MatchScene hook: returns `src` unchanged unless recording is enabled. `scene` (the match
## scene) lets an early quit still save what was recorded.
static func wrap_player(src: InputSource, entry: Dictionary, scene: Node = null) -> InputSource:
	if not is_enabled():
		return src
	var c: CreatureDef = entry.get("creature") as CreatureDef
	if c == null:
		return src
	var dir := PolicyDataset.ensure(dataset_id_for(c.id), "My %s matches" % c.display_name, c.id, "human")
	Log.i("lab", "recording this match for imitation learning (%s)" % dir)
	var rec := PolicyRecorder.new(src, dir, "human")
	if scene != null:
		scene.tree_exiting.connect(rec.finish)
	return rec
