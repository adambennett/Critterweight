extends TestCase
## The v0.9.17 finish (docs/ART_PIPELINE.md §5b) belongs to the art made for it: models whose glb
## extras carry `look` (the upgraded roster). Bosses, minions, the referee, the built-in segment look
## (and the legacy Varga, test_varga_skins) keep the exact v0.9.16 shading, and so do the hub's NPC
## and ambient models, which set no finish at all: the shader's default must be the v0.9.16 look.

const SHADER := "res://src/view/shaders/creature.gdshader"
const ROSTER := ["f_stoke", "f_dredge", "f_gusto", "f_dozer", "f_slurry", "f_jitters", "f_knell", "f_varga"]
const OLDER := ["boss_bilge", "boss_conduit", "boss_snappington", "npc_scrapling", "npc_blister", "npc_kid_lamprey"]

var _saved := {}


func before_each() -> void:
	_saved = Settings.values.duplicate(true)
	Settings.values[CreatureView.LEGACY_VARGA_SETTING] = false      # the upgraded Varga is drawn


func after_each() -> void:
	Settings.values = _saved


func _view(c: CreatureDef) -> CreatureView:
	var v := CreatureView.new()
	add_child(v)
	v.setup(c)
	return v


## The finish values and material classes over a view's surface materials.
func _shading(v: CreatureView) -> Dictionary:
	var finishes := {}
	var kinds := {}
	for m in v._materials:
		finishes[float(m.get_shader_parameter("finish"))] = true
		kinds[int(m.get_shader_parameter("material_kind"))] = true
	return {"finish": finishes.keys(), "kinds": kinds.keys()}


func test_a_material_that_sets_none_of_it_is_the_v0916_shader() -> void:
	var sh: Shader = load(SHADER)
	# even the headless renderer compiles the shader to list its uniforms: none listed = it is broken
	var names: Array = sh.get_shader_uniform_list().map(func(u: Dictionary) -> String: return str(u["name"]))
	check(names.has("tint") and names.has("finish") and names.has("material_kind"), "the creature shader compiles (%d uniforms)" % names.size())
	var m := RegEx.create_from_string("uniform\\s+float\\s+finish\\s*=\\s*([0-9.]+)\\s*;").search(sh.code)
	check(m != null, "the shader declares its finish with a default")
	if m != null:
		check_eq(float(m.get_string(1)), 0.0, "finish defaults to 0, the v0.9.16 look")


func test_only_the_upgraded_roster_gets_the_finish() -> void:
	for id in ROSTER:
		var v := _view(Content.creature(id))
		check(v._look.has("look"), "%s: its model carries the look extras" % id)
		var sh := _shading(v)
		check_eq(sh["finish"], [1.0], "%s: the v0.9.17 finish on every surface" % id)
		check((sh["kinds"] as Array).size() > 1, "%s: shaded by material class (%s)" % [id, str(sh["kinds"])])
		v.queue_free()
	var older := 0
	for id2 in OLDER:
		var c := Content.creature(id2)
		if c == null:
			continue
		older += 1
		var v2 := _view(c)
		check(v2._skeleton != null and not v2._look.has("look"), "%s: its own model, made before v0.9.17" % id2)
		var sh2 := _shading(v2)
		check_eq(sh2["finish"], [0.0], "%s: the v0.9.16 shading" % id2)
		check_eq(sh2["kinds"], [0], "%s: no material classes" % id2)
		v2.queue_free()
	check(older >= 3, "the bosses are checked (%d older models)" % older)
	var ref := _view(RefereeView.make_creature(RefereeView.load_data()))
	check(ref._skeleton != null, "the referee's model loads")
	check_eq(_shading(ref)["finish"], [0.0], "the referee keeps the v0.9.16 shading")
	ref.queue_free()
	var plain := _view(Content.creature("dev_biped"))
	check(plain._skeleton == null, "dev_biped is drawn with the built-in segment look")
	check_eq(_shading(plain)["finish"], [0.0], "which keeps the v0.9.16 shading")
	plain.queue_free()
	await wait_frames(1)


func test_the_gore_piece_keeps_its_models_finish() -> void:
	# {creature: [finish, material class]}: Dozer's chip is lacquered shell, a boss keeps the old look
	var cases := {"f_dozer": [1.0, 5], "boss_bilge": [0.0, 0]}
	for id in cases:
		var v := _view(Content.creature(str(id)))
		var piece := v.detach_piece(Vector3.FORWARD)
		if not check(piece != null, "%s: the gag piece pops off" % id):
			v.queue_free()
			continue
		var meshes := piece.find_children("*", "MeshInstance3D", true, false)
		var pm: ShaderMaterial = (meshes[0] as MeshInstance3D).material_override as ShaderMaterial if not meshes.is_empty() else null
		if check(pm != null, "%s: the piece uses the creature shader" % id):
			var want: Array = cases[id]
			check_eq(float(pm.get_shader_parameter("finish")), float(want[0]), "%s: the piece's finish" % id)
			check_eq(int(pm.get_shader_parameter("material_kind")), int(want[1]), "%s: the piece's material class" % id)
		piece.queue_free()
		v.queue_free()
	await wait_frames(1)
