extends TestCase
## Per-frame cost of the fighter views (CreatureView.render: bone poses, the v0.9.17 face rig and
## springs, material parameters) for the eight playable fighters, measured headless-free in a window
## so skeletons and materials are live. Uses only APIs present in v0.9.16, so the same file times the
## previous release's views too.
##   godot --path game --resolution 1280x800 -- --user-root <tmp> --test test_view_cost --view-cost <out.json>

const ROSTER := ["f_stoke", "f_dredge", "f_gusto", "f_dozer", "f_slurry", "f_jitters", "f_varga", "f_knell"]
const FRAMES := 600


func test_zz_view_cost() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--view-cost")
	if i < 0 or i + 1 >= args.size():
		return
	var views: Array = []
	var rests: Array = []
	for k in ROSTER.size():
		var c := Content.creature(ROSTER[k])
		var v := CreatureView.new()
		add_child(v)
		v.setup(c)
		var xf: Array[Transform3D] = []
		for s: BodyDef.Seg in c.body.segments:
			xf.append(Transform3D(Basis(), Vector3(k * 2.0, 0.0, 0.0) + s.pivot))
		v.snap_transforms(xf)
		views.append(v)
		rests.append(xf)
	await get_tree().process_frame
	var t_render := 0
	var t_mat := 0
	var t_frame := 0
	var per_view := {}
	for f in FRAMES:
		var t0 := Time.get_ticks_usec()
		for k in views.size():
			var v: CreatureView = views[k]
			# move every segment a little (a fighter in motion: springs, bones and bruises all update)
			var moved: Array[Transform3D] = []
			for j in (rests[k] as Array).size():
				var r: Transform3D = rests[k][j]
				moved.append(Transform3D(r.basis.rotated(Vector3.UP, 0.3 * sin(f * 0.05 + j)), r.origin + Vector3(0.2 * sin(f * 0.07), 0.0, 0.1 * cos(f * 0.05))))
			v.push_transforms(moved)
			if f == 10:
				v.flash(1.0)
				v.add_bruise(0, moved[0].origin, 1.0)
			var a := Time.get_ticks_usec()
			v.render(0.5)
			var b := Time.get_ticks_usec()
			t_render += b - a
			per_view[ROSTER[k]] = int(per_view.get(ROSTER[k], 0)) + (b - a)
			if v.has_method("_update_materials"):
				var c0 := Time.get_ticks_usec()
				v.call("_update_materials")
				t_mat += Time.get_ticks_usec() - c0
		var t1 := Time.get_ticks_usec()
		await get_tree().process_frame
		t_frame += Time.get_ticks_usec() - t0
		var _skip := t1
	var out := {"version": str(ProjectSettings.get_setting("application/config/version", "")), "frames": FRAMES,
		"render_ms_per_frame_all8": snappedf(t_render / 1000.0 / FRAMES, 0.001),
		"materials_ms_per_frame_all8": snappedf(t_mat / 1000.0 / FRAMES, 0.001),
		"frame_ms": snappedf(t_frame / 1000.0 / FRAMES, 0.001), "render_ms_by_fighter": {}}
	for id in per_view:
		out["render_ms_by_fighter"][id] = snappedf(float(per_view[id]) / 1000.0 / FRAMES, 0.001)
	var fo := FileAccess.open(args[i + 1], FileAccess.WRITE)
	fo.store_string(JSON.stringify(out, "\t"))
	fo.close()
	print("VIEW_COST ", JSON.stringify(out))
	for v2 in views:
		(v2 as Node).queue_free()
