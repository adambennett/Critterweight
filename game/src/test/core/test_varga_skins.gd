extends TestCase
## v0.9.17 Varga skins (docs/ART_REVAMP.md): the upgraded Varga is the default; the controller
## reachable "Legacy Varga skin" setting restores his actual original appearance (the v0.9.16 model,
## byte for byte), persists, is applied by every view (they all draw fighters through
## CreatureView), swaps live, and never touches gameplay data.

const LEGACY_SHA256 := "4fa78a8a66cb46739b793bc095501e3957a5aed27bafe1901141ba4c90d460fc"
const KEY := "cosmetic.legacy_varga"

var _saved := {}


func before_each() -> void:
	_saved = {"values": Settings.values.duplicate(true), "path": Settings.path_override, "ro": Settings.read_only}
	Settings.path_override = temp_dir("varga-skins-%d" % Time.get_ticks_usec()).path_join("settings.json")
	Settings.read_only = false


func after_each() -> void:
	Settings.values = _saved["values"]
	Settings.path_override = _saved["path"]
	Settings.read_only = _saved["ro"]


func test_legacy_asset_is_the_original() -> void:
	if not FileAccess.file_exists(CreatureView.VARGA_LEGACY_MODEL):
		skip("the source GLB is not shipped inside exported builds (checked in the source suite)")
		return
	var legacy := FileAccess.get_sha256(CreatureView.VARGA_LEGACY_MODEL)
	check_eq(legacy, LEGACY_SHA256, "f_varga_legacy.glb is the v0.9.16 f_varga.glb, unchanged")
	var current := FileAccess.get_sha256(CreatureView.VARGA_MODEL)
	check(current != LEGACY_SHA256, "the default Varga is the upgraded model")
	check(ResourceLoader.exists(CreatureView.VARGA_LEGACY_MODEL), "the legacy model is imported")


func test_setting_is_a_persisted_graphics_option() -> void:
	var s := Settings.schema(KEY)
	check_eq(str(s.get("label", "")), "Legacy Varga skin", "exact label")
	check_eq(str(s.get("t", "")), "bool")
	check_eq(bool(s.get("def", true)), false, "the upgraded look is the default")
	check(Settings.keys_in(str(s.get("cat", ""))).has(KEY), "listed on its Settings tab")
	check(not bool(s.get("hidden", false)), "visible")
	var preset := str(Settings.get_value("graphics.preset"))
	Settings.set_value(KEY, true, true, true)
	check_eq(str(Settings.get_value("graphics.preset")), preset, "a cosmetic choice does not turn the quality preset into Custom")
	Settings.values[KEY] = false
	Settings.load_settings()
	check_eq(bool(Settings.get_value(KEY)), true, "persisted across a settings reload")
	Settings.set_value(KEY, false, true, true)
	Settings.values[KEY] = true
	Settings.load_settings()
	check_eq(bool(Settings.get_value(KEY)), false, "and back")


func test_setting_row_works_from_a_controller() -> void:
	Settings.set_value(KEY, false, true, false)
	var row := SettingRows.make(KEY)
	add_child(row)
	check(row is ToggleRow, "an on/off row")
	check_eq(row.focus_mode, Control.FOCUS_ALL, "a focus stop the D-pad reaches")
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	row._gui_input(ev)
	check_eq(bool(Settings.get_value(KEY)), true, "A / accept turns it on")
	row._gui_input(ev)
	check_eq(bool(Settings.get_value(KEY)), false, "and off again")
	row.queue_free()


func test_model_choice_follows_the_setting_for_varga_only() -> void:
	var varga := Content.creature("f_varga")
	check_eq(CreatureView.model_path_for(varga, false), CreatureView.VARGA_MODEL, "default: upgraded model")
	check_eq(CreatureView.model_path_for(varga, true), CreatureView.VARGA_LEGACY_MODEL, "legacy: the original model")
	Settings.set_value(KEY, true, true, false)
	check_eq(CreatureView.model_path_for(varga), CreatureView.VARGA_LEGACY_MODEL, "follows the setting")
	for id in ["f_stoke", "f_dredge", "f_gusto", "f_dozer", "f_slurry", "f_jitters", "f_knell"]:
		var c := Content.creature(id)
		check_eq(CreatureView.model_path_for(c, true), str(c.art.get("model", "")), "%s is not affected" % id)
	Settings.set_value(KEY, false, true, false)


func test_live_swap_keeps_the_rig_and_the_gameplay() -> void:
	Settings.set_value(KEY, false, true, false)
	var varga := Content.creature("f_varga")
	var hash_before := Content.content_hash()
	var entry_before := JSON.stringify(Content.get_entry("creatures", "f_varga"), "", true)
	var v := CreatureView.new()
	add_child(v)
	v.setup(varga)
	check(v._skeleton != null, "upgraded model loaded")
	check_eq(v._finish, 1.0, "upgraded model uses the v0.9.17 finish")
	var bones_new := v._skeleton.get_bone_count() if v._skeleton else 0
	for b in v._bone_of_seg:
		check(b >= 0, "upgraded: every body segment drives a bone")
	# toggling the setting swaps the drawn model in place (no new view, same body)
	Settings.set_value(KEY, true, true, false)
	await wait_frames(2)
	check(v._skeleton != null, "legacy model loaded")
	check_eq(v._finish, 0.0, "legacy model keeps its pre-v0.9.17 shading")
	for b in v._bone_of_seg:
		check(b >= 0, "legacy: every body segment drives a bone")
	check(v.body == varga.body, "same body definition")
	check(bones_new > 0, "bones found")
	check_eq(Content.content_hash(), hash_before, "gameplay content hash identical under both skins (what peers compare)")
	check_eq(JSON.stringify(Content.get_entry("creatures", "f_varga"), "", true), entry_before, "Varga's definition untouched by the skin choice")
	check(Content.creature("f_varga") == varga, "the same creature definition is used")
	Settings.set_value(KEY, false, true, false)
	await wait_frames(2)
	check_eq(v._finish, 1.0, "back to the upgraded model")
	v.queue_free()


func test_previews_stand_every_fighter_on_the_floor() -> void:
	# Varga's imported body reaches 17.5 cm below its rest floor; previews lift it (both skins)
	check_near(CreatureView.rest_sink(Content.creature("f_varga").body), 0.1749, 0.002, "Varga's rest pose sink")
	for id in ["f_stoke", "f_dredge", "f_gusto", "f_dozer", "f_slurry", "f_jitters", "f_knell"]:
		check(CreatureView.rest_sink(Content.creature(id).body) < 0.02, "%s already stands on its floor" % id)
	var preview := FighterPreview.new()
	add_child(preview)
	await wait_frames(1)
	preview.show_fighter(Content.creature("f_varga"))
	var v: CreatureView = preview.model
	var lowest := INF
	for i in v.body.segments.size():
		lowest = minf(lowest, v.segment_world(i).origin.y)
	check(lowest > -0.05, "no body pivot below the pedestal (lowest %.3f)" % lowest)
	check_near(v.segment_world(0).origin.y, Content.creature("f_varga").body.segments[0].pivot.y + 0.1749, 0.003, "lifted by the sink")
	preview.queue_free()
