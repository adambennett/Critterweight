extends TestCase
## LAB-10 (reproducible examples), review finding 7: `--path game` makes the game folder Godot's
## working directory, so every relative path in a documented command must be written from there
## (`../docs/...`, `../runs/...`) — the documented commands used to fail with "job file not
## found". Checks every command line of docs/AI_LAB.md and docs/evidence/lab/README.md (skipped
## when the docs are not next to the game folder, e.g. in an exported build).

const DOCS := ["docs/AI_LAB.md", "docs/evidence/lab/README.md"]
const PATH_FLAGS := ["--lab-worker", "--lab-out", "--user-root", "--runs", "--out", "--policy-file"]


func _repo_root() -> String:
	return ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()


## True for a value that does not depend on the working directory, or is written from game/.
static func path_ok(v: String) -> bool:
	var s := v.strip_edges().trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")
	if s == "" or s.begins_with("<") or s.begins_with("$") or s.begins_with("../") or s.begins_with("..\\"):
		return true
	if s.is_absolute_path() or s.begins_with("res://") or s.begins_with("user://"):
		return true
	return false


func test_documented_commands_resolve_from_the_game_folder() -> void:
	check(path_ok("../docs/evidence/lab/jobs/es_drill_seed101.json") and not path_ok("docs/evidence/lab/jobs/es_drill_seed101.json"),
		"the rule itself")
	var checked := 0
	for rel in DOCS:
		var path := _repo_root().path_join(rel)
		if not FileAccess.file_exists(path):
			continue
		var n := 0
		for line in FileAccess.get_file_as_string(path).split("\n"):
			n += 1
			if not line.contains("--path game"):
				continue
			checked += 1
			var toks := line.replace("`", " ").split(" ", false)
			for i in toks.size() - 1:
				if not PATH_FLAGS.has(toks[i]):
					continue
				var v := toks[i + 1]
				if v.begins_with("--"):
					continue
				for part in v.trim_prefix("\"").trim_suffix("\"").split(";", false):
					check(path_ok(part), "%s:%d: '%s %s' is resolved from game/ (write ../%s)" % [rel, n, toks[i], part, part])
	if checked == 0:
		skip("the docs are not next to this build (exported builds)")
		return
	check(checked >= 10, "documented commands found (%d)" % checked)
