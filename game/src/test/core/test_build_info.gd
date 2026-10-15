extends TestCase
## DEL-05 / docs/RELEASES.md: the version label testers quote in bug reports.


func after_each() -> void:
	BuildInfo._info = {}
	BuildInfo._loaded = false
	super.after_each()


func test_label_formats() -> void:
	var v := BuildInfo.version()
	check(v.length() >= 5, "a version is set in project.godot (%s)" % v)
	BuildInfo._loaded = true
	BuildInfo._info = {}
	check_eq(BuildInfo.label(), "%s-dev" % v, "running from source")
	BuildInfo._info = {"version": v, "tag": "v" + v, "commit": "abc1234", "dirty": false}
	check_eq(BuildInfo.label(), "%s (abc1234)" % v, "tagged release build")
	BuildInfo._info = {"version": v, "tag": "", "commit": "abc1234", "dirty": true}
	check_eq(BuildInfo.label(), "%s+abc1234.dirty" % v, "untagged build from local changes")
