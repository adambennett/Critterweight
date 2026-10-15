extends TestCase
## MOD-02: schema validation produces actionable errors.


func test_valid_arena_passes() -> void:
	var errs := Schema.validate_named({"id": "my_mod:pit", "name": "Pit", "base": "circle", "radius": 4.0}, "arena")
	check(errs.is_empty(), "valid: %s" % str(errs))


func test_invalid_arena_reports_paths() -> void:
	var errs := Schema.validate_named({"id": "Bad Id!", "name": "", "base": "hexagon", "radius": 50}, "arena")
	check(errs.size() >= 4, "several errors: %s" % str(errs))
	var joined := "\n".join(errs)
	check(joined.contains("$.base"), "names the field")
	check(joined.contains("radius"), "range error")


func test_manifest_requires_semver() -> void:
	var errs := Schema.validate_named({"id": "abc", "name": "A", "version": "1.0", "game_version": "0.1.0"}, "manifest")
	check(not errs.is_empty(), "rejects non-semver")
