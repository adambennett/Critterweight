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


## The view draws exactly one model, the one `path` names, bound to every body segment, with the
## shading and face rig made for it: the upgraded model has the v0.9.17 finish and a driven face,
## the original keeps its pre-v0.9.17 shading (no material classes) and has no face rig.
func _check_drawn(v: CreatureView, path: String, tag: String) -> void:
	var models := []
	for child in v.get_children():
		if child.has_meta("creature_model"):
			models.append(str(child.get_meta("creature_model")))
	check_eq(models, [path], "%s: exactly one model in the view, %s" % [tag, path.get_file()])
	check_eq(v.loaded_model_path(), path, "%s: the view reports the model it draws" % tag)
	check(v._skeleton != null and v._skeleton.is_inside_tree(), "%s: its skeleton is live" % tag)
	for b in v._bone_of_seg:
		check(b >= 0, "%s: every body segment drives a bone" % tag)
	var legacy := path == CreatureView.VARGA_LEGACY_MODEL
	check_eq(v._fx == null, legacy, "%s: the face rig is %s" % [tag, "absent (the original has none)" if legacy else "driven"])
	var finishes := {}
	var kinds := {}
	for m in v._materials:
		finishes[float(m.get_shader_parameter("finish"))] = true
		kinds[int(m.get_shader_parameter("material_kind"))] = true
	check_eq(finishes.keys(), [0.0] if legacy else [1.0], "%s: the finish on every surface" % tag)
	if legacy:
		check_eq(kinds.keys(), [0], "%s: no material classes" % tag)
	else:
		check(kinds.size() > 1, "%s: surfaces shaded by material class" % tag)


func test_live_swap_keeps_the_rig_and_the_gameplay() -> void:
	Settings.set_value(KEY, false, true, false)
	var varga := Content.creature("f_varga")
	var art_before := JSON.stringify(varga.art, "", true)
	var entry_before := JSON.stringify(Content.get_entry("creatures", "f_varga"), "", true)
	var v := CreatureView.new()
	add_child(v)
	v.setup(varga)
	_check_drawn(v, CreatureView.VARGA_MODEL, "upgraded (default)")
	# toggling the setting swaps the drawn model in place, at once (no new view, same body)
	Settings.set_value(KEY, true, true, false)
	_check_drawn(v, CreatureView.VARGA_LEGACY_MODEL, "legacy")
	await wait_frames(2)
	_check_drawn(v, CreatureView.VARGA_LEGACY_MODEL, "legacy, frames later")
	check_eq(JSON.stringify(varga.art, "", true), art_before, "the shared definition still names the upgraded model: only this screen draws the original")
	check_eq(JSON.stringify(Content.get_entry("creatures", "f_varga"), "", true), entry_before, "Varga's definition untouched by the skin choice")
	Settings.set_value(KEY, false, true, false)
	_check_drawn(v, CreatureView.VARGA_MODEL, "back to the upgraded model")
	await wait_frames(2)
	_check_drawn(v, CreatureView.VARGA_MODEL, "upgraded, frames later")
	v.queue_free()


func _model_node(v: CreatureView) -> Node:
	for child in v.get_children():
		if child.has_meta("creature_model") and not child.is_queued_for_deletion():
			return child
	return null


func test_a_swap_keeps_a_popped_tooth_out_and_a_resend_rebuilds_nothing() -> void:
	Settings.set_value(KEY, false, true, false)
	var holder := Node3D.new()           # the gag piece flies off next to the view
	add_child(holder)
	var v := CreatureView.new()
	holder.add_child(v)
	v.setup(Content.creature("f_varga"))
	v.set_cosmetics([{"kind": "tooth", "color": "#E8B923", "id": "hub_gold_tooth"}])
	var rest: Array[Transform3D] = []
	for s: BodyDef.Seg in v.body.segments:
		rest.append(Transform3D(Basis.IDENTITY, s.pivot))
	v.snap_transforms(rest)
	v.render(1.0)
	if not check_eq(v.cosmetics().size(), 1, "Varga wears the gold tooth"):
		holder.queue_free()
		return
	var piece := v.detach_piece(Vector3.FORWARD)
	check(piece != null and bool(v.cosmetics()[0]["popped"]), "the end-of-fight gag popped it out")
	# the same value again (Reset Graphics re-sends every key of its tab): nothing is rebuilt
	var model := _model_node(v)
	Settings.set_value(KEY, false, true, false)
	check(_model_node(v) == model, "an unchanged setting keeps the drawn model")
	Settings.changed.emit(KEY, Settings.get_value(KEY))
	check(_model_node(v) == model, "so does a re-sent one")
	check(bool(v.cosmetics()[0]["popped"]), "and the tooth is still out")
	# a real swap rebuilds the cosmetics on the new model, but the tooth stays out this round
	Settings.set_value(KEY, true, true, false)
	check(_model_node(v) != model, "the skin swap rebuilt the model")
	var tooth: Dictionary = v.cosmetics()[0] if v.cosmetics().size() == 1 else {}
	check(bool(tooth.get("popped", false)), "the popped tooth stays popped after the swap")
	check(tooth.has("node") and not (tooth["node"] as Node3D).visible, "and out of the mouth")
	v.clear_bruises()
	v.render(1.0)
	check(tooth.has("node") and (tooth["node"] as Node3D).visible, "next round it is back")
	Settings.set_value(KEY, false, true, false)
	holder.queue_free()
	await wait_frames(1)


## The preview's model as drawn: every segment bone on its segment's pivot lifted by the rest sink
## (not on the model's own, unlifted rest pose) and, where the model has a face, the eyes open (its
## lids are modelled shut and only the rig opens them).
func _check_posed(v: CreatureView, sink: float, tag: String) -> void:
	var sk := v._skeleton
	if not check(sk != null, "%s: a skeleton" % tag):
		return
	var worst := 0.0
	for s: BodyDef.Seg in v.body.segments:
		var bi := sk.find_bone(s.id)
		if bi >= 0:
			worst = maxf(worst, sk.get_bone_global_pose(bi).origin.distance_to(s.pivot + Vector3.UP * sink))
	check(worst < 0.002, "%s: the drawn body stands on the pedestal, lifted %.3f m (worst bone %.4f m off)" % [tag, sink, worst])
	var lid := sk.find_bone("fx_lid_l")
	if lid >= 0:
		check(sk.get_bone_pose_scale(lid).y < 0.9, "%s: eyes open (lid at %.2f of its shut height)" % [tag, sk.get_bone_pose_scale(lid).y])


func test_previews_stand_every_fighter_on_the_floor() -> void:
	# Varga's imported body reaches 17.5 cm below its rest floor; previews lift it (both skins)
	var varga := Content.creature("f_varga")
	var sink := CreatureView.rest_sink(varga.body)
	check_near(sink, 0.1749, 0.002, "Varga's rest pose sink")
	for id in ["f_stoke", "f_dredge", "f_gusto", "f_dozer", "f_slurry", "f_jitters", "f_knell"]:
		check(CreatureView.rest_sink(Content.creature(id).body) < 0.02, "%s already stands on its floor" % id)
	Settings.set_value(KEY, false, true, false)
	var preview := FighterPreview.new()
	add_child(preview)
	await wait_frames(1)
	preview.show_fighter(varga)
	var v: CreatureView = preview.model
	# the lowest point of the body's shapes as placed: on the floor (unlifted it would be -sink)
	var lowest := INF
	for s: BodyDef.Seg in v.body.segments:
		var xf := v.segment_world(s.index)
		for sh: BodyDef.Shape in s.shapes:
			var r := sh.size.y * 0.5 if sh.type == BodyDef.SHAPE_BOX else sh.radius
			var ends := [sh.a, sh.b] if sh.type == BodyDef.SHAPE_CAPSULE else [sh.a]
			for p in ends:
				lowest = minf(lowest, (xf * (p as Vector3)).y - r)
	check_near(lowest, 0.0, 0.003, "the lowest body point stands on the floor (unlifted: %.3f)" % -sink)
	check_near(v.segment_world(0).origin.y, varga.body.segments[0].pivot.y + sink, 0.003, "lifted by the sink")
	_check_posed(v, sink, "upgraded")
	# the skin toggled while a preview shows him: previews render once, so the new model is posed at once
	Settings.set_value(KEY, true, true, false)
	_check_posed(v, sink, "legacy")
	Settings.set_value(KEY, false, true, false)
	_check_posed(v, sink, "upgraded again")
	preview.queue_free()
