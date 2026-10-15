extends Node
## Discovers and runs every `test_*.gd` under res://src/test (TestCase subclasses), printing a
## summary and writing JSON results. Exit code = number of failed tests.
## Filter: substring of "path::method" (e.g. "--test persist" or "--test test_saves.gd::test_crash").
## Results file: --test-out <path> (default <user>/captures/test_results.json).

var _results: Array = []


func run(filter: String) -> void:
	var files := _collect("res://src/test")
	files.sort()
	var total := 0
	var failed := 0
	var t_start := Time.get_ticks_msec()
	for path in files:
		var script = load(path)
		if script == null or not (script as GDScript).can_instantiate():
			_results.append({"test": path, "ok": false, "errors": ["script failed to load"], "ms": 0})
			failed += 1
			total += 1
			print("FAIL  %s (load error)" % path)
			continue
		var methods := []
		for m in (script as GDScript).get_script_method_list():
			var mname: String = m["name"]
			if mname.begins_with("test_") and not methods.has(mname):
				methods.append(mname)
		methods.sort()
		for mname in methods:
			var key := "%s::%s" % [path, mname]
			if filter != "" and not key.contains(filter):
				continue
			var tc: TestCase = script.new()
			tc.name = mname
			add_child(tc)
			tc._current = key
			var t0 := Time.get_ticks_msec()
			tc.before_each()
			await tc.call(mname)
			tc.after_each()
			var ms := Time.get_ticks_msec() - t0
			total += 1
			var ok := tc._failures.is_empty()
			if not ok:
				failed += 1
			_results.append({"test": key, "ok": ok, "errors": tc._failures.duplicate(), "ms": ms})
			print("%s  %s (%d ms)" % ["ok  " if ok else "FAIL", key, ms])
			for e in tc._failures:
				print("        " + str(e))
			tc.queue_free()
			await get_tree().process_frame
	var summary := "tests: %d run, %d failed, %d passed in %.1f s" % [total, failed, total - failed, (Time.get_ticks_msec() - t_start) / 1000.0]
	print(summary)
	var out_path: String = get_parent().arg_value("--test-out", Paths.dir("captures").path_join("test_results.json"))
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"summary": summary, "total": total, "failed": failed, "results": _results,
			"version": ProjectSettings.get_setting("application/config/version"), "time": Time.get_datetime_string_from_system()}, "\t"))
		f.close()
	get_tree().quit(failed)


func _collect(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		var p := dir.path_join(n)
		if d.current_is_dir():
			if not n.begins_with("."):
				out.append_array(_collect(p))
		elif n.begins_with("test_") and n.ends_with(".gd"):
			out.append(p)
		n = d.get_next()
	return out
