extends TestCase
## LAB-10: the sample policies shipped in content/core/policies pass the same validation as user
## files, are usable by their fighter and carry their training record; and the drill sample
## really plays: on fresh standing-dummy episodes (seeds no training run used) it closes in and
## lands hits, which its untrained starting network does not.

const DRILL_ID := "dev_biped_es_drill"


func test_shipped_policies_validate() -> void:
	var ids := Content.ids("policies")
	check(ids.size() >= 3, "sample policies shipped (%d)" % ids.size())
	for id in ids:
		var p := PolicyLibrary.get_policy(str(id))
		check(p != null, "%s loads (%s)" % [id, PolicyLibrary.last_error(str(id))])
		if p == null:
			continue
		check(PolicyLibrary.is_builtin(str(id)), "%s is built-in (read-only)" % id)
		check_eq(PolicyLibrary.compatibility(p, p.creature), "", "%s is usable by %s" % [id, p.creature])
		check(str(p.training.get("approach", "")) != "", "%s records how it was trained" % id)
		check(p.description != "", "%s has a description" % id)
	var listed := 0
	for s: Dictionary in PolicyLibrary.list("dev_biped"):
		if PolicyLibrary.is_builtin(str(s.get("id", ""))) and bool(s.get("valid", false)):
			listed += 1
	check(listed >= 3, "the Lab's policy list shows the samples (%d)" % listed)


func test_drill_sample_hits_a_standing_dummy() -> void:
	var trained := PolicyLibrary.get_policy(DRILL_ID)
	check(trained != null, "drill sample present (%s)" % PolicyLibrary.last_error(DRILL_ID))
	if trained == null:
		return
	var untrained := PolicyData.create_new("dev_biped", trained.net.hidden, trained.net.activation, 99)
	var hits_trained := await _drill_hits(trained)
	var hits_untrained := await _drill_hits(untrained)
	check(hits_trained >= 4, "the trained sample lands hits on the dummy in 4 episodes (%d)" % hits_trained)
	check(hits_trained > hits_untrained + 2, "more than an untrained network of the same shape (%d vs %d)" % [hits_trained, hits_untrained])


func _drill_hits(p: PolicyData) -> int:
	var runner := LabRunner.new()
	runner.max_worlds = 2
	add_child(runner)
	runner.resolver = func(_it: Dictionary) -> PolicyData: return p
	var scn: Dictionary = LabScenarios.PRESETS["drill_dummy"].duplicate(true)
	scn["round_time"] = 6.0
	var items := []
	for k in 4:
		var ep := LabScenarios.episode(scn, "idle", 777001 + k, "dev_biped", "dev_biped", "standard" if k % 2 == 0 else "random")
		items.append({"i": k, "policy": {"key": "theta"}, "episode": ep})
	runner.add_items(items)
	var dt := 1.0 / Engine.physics_ticks_per_second
	var guard := 0
	while runner.busy() and guard < 6000:
		runner.step(dt)
		await get_tree().physics_frame
		guard += 1
	var hits := 0
	for r: Dictionary in runner.take_results():
		check(not r.has("error"), "episode ran: %s" % str(r.get("error", "")))
		hits += int((r.get("raw", {}) as Dictionary).get("hits", 0))
	runner.queue_free()
	return hits
