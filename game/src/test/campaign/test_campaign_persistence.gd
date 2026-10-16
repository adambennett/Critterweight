extends CampaignTestCase
## SAV-01/02/03: suspend/resume, crash recovery, duplicate protection across resumes, damaged /
## missing / newer / content-incompatible saves (clear, non-destructive), migrations, tickets.

var store: RunStore


func before_each() -> void:
	store = RunStore.new(temp_dir("campaign_store_%d" % Time.get_ticks_usec()))


func after_each() -> void:
	Saves.simulate_crash_after_tmp = false
	super.after_each()


func _advance(ctrl: RunController, nodes: int) -> void:
	for i in nodes:
		if ctrl.is_over():
			return
		ctrl.choose_node(str(ctrl.available_nodes()[0]), "p0")
		settle_node(ctrl)


func test_suspend_and_resume_mid_run() -> void:
	var ctrl := new_run({"seed": 606})
	_advance(ctrl, 4)
	check_eq(store.save(ctrl.state, "tester"), OK, "save")
	var r := store.load_slot("tester", "off_the_street", cat())
	check(bool(r["ok"]), "resume ok: %s" % r["error"])
	var resumed := RunController.from_state(cat(), r["state"])
	check_eq(sig(resumed.state), sig(ctrl.state), "resumed state equals the suspended one")
	play_synthetic(resumed)
	check_eq(resumed.phase(), "victory", "a resumed run plays to the end")
	var listed := store.list("tester", cat())
	check_eq(listed.size(), 1, "one suspended run listed")
	check_eq(str(listed[0]["summary"]["variant"]), "off_the_street", "summary")


func test_fresh_seed_run_resumes_identically() -> void:
	var ctrl := new_run({"seed": 0})      # a fresh random seed, as in normal play
	_advance(ctrl, 3)
	store.save(ctrl.state, "tester")
	var r := store.load_slot("tester", "off_the_street", cat())
	check(bool(r["ok"]), "resume: %s" % r["error"])
	check_eq(int(r["state"]["seed"]), int(ctrl.state["seed"]), "the seed survives the save exactly")
	var a := RunController.from_state(cat(), r["state"])
	_advance(a, 3)
	_advance(ctrl, 3)
	check_eq(sig(a.state), sig(ctrl.state), "the resumed run continues exactly like the original")


func test_resume_after_crash_during_write() -> void:
	var ctrl := new_run({"seed": 607})
	_advance(ctrl, 2)
	store.save(ctrl.state, "tester")
	var path := store.slot_path("tester", "off_the_street")
	_advance(ctrl, 1)
	var expected := sig(ctrl.state)
	Saves.simulate_crash_after_tmp = true
	store.save(ctrl.state, "tester")      # "crashes" after the verified temp file
	Saves.simulate_crash_after_tmp = false
	check(FileAccess.file_exists(path + ".tmp"), "the interrupted write left a verified temp file")
	var r := store.load_slot("tester", "off_the_street", cat())
	check(bool(r["ok"]), "recovered: %s" % r["error"])
	check_eq(str(r["recovered_from"]), "tmp", "recovered from the newer temp copy")
	check_eq(sig(r["state"]), expected, "nothing lost")


func test_fight_in_progress_reruns_from_start() -> void:
	var ctrl := new_run({"seed": 608})
	ctrl.choose_node(str(ctrl.available_nodes()[0]), "p0")
	check_eq(ctrl.phase(), "fight", "in a fight")
	var plan := sig(ctrl.current_plan())
	store.save(ctrl.state, "tester")
	var r := store.load_slot("tester", "off_the_street", cat())
	var resumed := RunController.from_state(cat(), r["state"])
	check_eq(resumed.phase(), "fight", "the fight is pending again after resume")
	check_eq(sig(resumed.current_plan()), plan, "same enemies, same arena")
	check(resumed.complete_fight(fake_result(resumed)), "the re-run fight applies once")
	check(not resumed.complete_fight(fake_result(resumed)), "and only once")


func test_no_duplicate_rewards_across_resume() -> void:
	var ctrl := new_run({"seed": 609})
	ctrl.choose_node(str(ctrl.available_nodes()[0]), "p0")
	ctrl.complete_fight(fake_result(ctrl))
	var e: Dictionary = ctrl.pending_for("p0")[0]
	var rid := str(e["rid"])
	var choice := str(e["options"][0])
	ctrl.claim("p0", rid, choice)
	store.save(ctrl.state, "tester")
	var resumed := RunController.from_state(cat(), store.load_slot("tester", "off_the_street", cat())["state"])
	var count := 0
	for s in resumed.player("p0")["supplements"]:
		count += int(s["stacks"])
	check(not resumed.claim("p0", rid, choice), "the same claim after a resume is rejected")
	var count2 := 0
	for s2 in resumed.player("p0")["supplements"]:
		count2 += int(s2["stacks"])
	check_eq(count2, count, "inventory unchanged")


func test_damaged_save_reported_and_kept() -> void:
	var path := store.slot_path("tester", "off_the_street")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{\"format\": \"critterweight\", \"kind\": \"campaign_run\", \"version\": 1, \"checksum\": \"x\", \"data\": {")
	f.close()
	var r := store.load_slot("tester", "off_the_street", cat())
	check(not bool(r["ok"]), "a damaged save does not load")
	check(str(r["error"]).contains("damaged"), "clear message: %s" % r["error"])
	check(FileAccess.file_exists(path), "the damaged file is left untouched")


func test_damaged_main_file_recovers_from_backup() -> void:
	var ctrl := new_run({"seed": 610})
	store.save(ctrl.state, "tester")
	_advance(ctrl, 1)
	store.save(ctrl.state, "tester")   # previous save rotated to .bak
	var path := store.slot_path("tester", "off_the_street")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("garbage")
	f.close()
	var r := store.load_slot("tester", "off_the_street", cat())
	check(bool(r["ok"]), "falls back to the backup: %s" % r["error"])
	check_eq(str(r["recovered_from"]), "bak", "recovered from .bak")


func test_missing_save() -> void:
	var r := store.load_slot("nobody", "off_the_street", cat())
	check(not bool(r["ok"]) and not bool(r["exists"]), "missing slot")
	check(str(r["error"]).contains("No suspended run"), "clear message")


func test_removed_content_blocks_resume_non_destructively() -> void:
	var ctrl := new_run({"seed": 611})
	ctrl.player("p0")["supplements"].append({"id": "gone_mod:sup_vanished", "stacks": 1})
	ctrl.player("p0")["techniques"].append("tech_removed_thing")
	store.save(ctrl.state, "tester")
	var r := store.load_slot("tester", "off_the_street", cat())
	check(not bool(r["ok"]), "a run with removed content does not resume")
	check(str(r["error"]).contains("gone_mod:sup_vanished") and str(r["error"]).contains("tech_removed_thing"), "names every missing id: %s" % r["error"])
	check(FileAccess.file_exists(store.slot_path("tester", "off_the_street")), "save kept for when the mod returns")
	# SAV-02 missing-mod case: when the mod (and the technique) are back, the same save resumes
	var c := cat()
	c.supplements["gone_mod:sup_vanished"] = {"id": "gone_mod:sup_vanished", "type": "supplement", "name": "Vanished", "rarity": "otc", "stack": 1, "apply": {}}
	c.techniques["tech_removed_thing"] = {"id": "tech_removed_thing", "name": "Removed Thing", "apply": {}}
	var back := store.load_slot("tester", "off_the_street", c)
	c.supplements.erase("gone_mod:sup_vanished")
	c.techniques.erase("tech_removed_thing")
	check(bool(back["ok"]), "with the mod back, the kept save resumes: %s" % back["error"])
	if bool(back["ok"]):
		check_eq(sig(back["state"]), sig(ctrl.state), "and continues exactly where it was suspended")


func test_newer_format_rejected() -> void:
	var ctrl := new_run({"seed": 612})
	Saves.write_json(store.slot_path("tester", "off_the_street"), RunStore.KIND, 99, ctrl.state)
	var r := store.load_slot("tester", "off_the_street", cat())
	check(not bool(r["ok"]), "newer format not loaded")
	check(str(r["error"]).contains("newer"), "clear message: %s" % r["error"])


func test_migration_from_v0() -> void:
	var ctrl := new_run({"seed": 613})
	var old: Dictionary = ctrl.state.duplicate(true)
	old.erase("claims")
	old.erase("flags")
	old.erase("log")
	old["version"] = 0
	Saves.write_json(store.slot_path("tester", "off_the_street"), RunStore.KIND, 0, old)
	var r := store.load_slot("tester", "off_the_street", cat())
	check(bool(r["ok"]), "v0 save migrates: %s" % r["error"])
	check(bool(r["migrated"]), "flagged as migrated")
	var resumed := RunController.from_state(cat(), r["state"])
	resumed.choose_node(str(resumed.available_nodes()[0]), "p0")
	check_eq(resumed.phase(), "fight", "the migrated run plays")


func test_inconsistent_state_rejected() -> void:
	var ctrl := new_run({"seed": 614})
	_advance(ctrl, 1)
	var bad: Dictionary = ctrl.state.duplicate(true)
	bad["position"] = "a1r6l0"     # not reachable from the recorded path
	bad["phase"] = "reward"
	store.save(bad, "tester")
	var r := store.load_slot("tester", "off_the_street", cat())
	check(not bool(r["ok"]), "inconsistent run rejected")
	check(str(r["error"]).contains("cannot be resumed"), "clear message: %s" % r["error"])


## Review #10: a crash can leave a slot with only its verified .tmp and/or its .bak — load_slot
## recovers from those, so the suspended-runs list must show the slot too (and abandoning a
## broken one moves every copy aside, so no leftover brings it back).
func test_slots_with_only_tmp_or_bak_are_listed() -> void:
	var ctrl := new_run({"seed": 617})
	store.save(ctrl.state, "tester")
	var path := store.slot_path("tester", "off_the_street")
	_advance(ctrl, 1)
	Saves.simulate_crash_after_tmp = true
	store.save(ctrl.state, "tester")          # verified .tmp written, then "crash"
	Saves.simulate_crash_after_tmp = false
	DirAccess.rename_absolute(path, path + ".bak")   # ...and the main file had just been rotated
	check(not FileAccess.file_exists(path), "precondition: no main file, only .tmp and .bak")
	var r := store.load_slot("tester", "off_the_street", cat())
	check(bool(r["ok"]), "load_slot recovers it: %s" % r["error"])
	var listed := store.list("tester", cat())
	check_eq(listed.size(), 1, "the recoverable run is listed")
	if listed.size() == 1:
		check_eq(str(listed[0]["slot"]), "off_the_street", "under its slot name")
		check(bool(listed[0]["ok"]), "and resumable from the list")
	DirAccess.remove_absolute(path + ".tmp")
	check_eq(store.list("tester", cat()).size(), 1, "a slot with only its .bak is listed too")
	# a broken run that is abandoned: every copy moved aside, nothing left to list
	var f := FileAccess.open(path + ".bak", FileAccess.WRITE)
	f.store_string("garbage")
	f.close()
	var listed2 := store.list("tester", cat())
	check(listed2.size() == 1 and not bool(listed2[0]["ok"]), "a damaged leftover is listed with its error")
	store.quarantine("tester", "off_the_street")
	check(store.list("tester", cat()).is_empty(), "quarantine moves every copy aside")
	check_eq(RunStore.slot_of_file("off_the_street.json.bak.damaged-5"), "", "quarantined copies are no slots")


func test_party_ticket_integrity() -> void:
	var ctrl := new_run({"seed": 615})
	var t := RunStore.make_ticket(ctrl.state, "p0")
	check(RunStore.ticket_valid(t), "fresh ticket valid")
	t["state"]["players"][0]["scrip"] = 99999
	check(not RunStore.ticket_valid(t), "a tampered ticket is rejected")


## Godot's JSON reader brings some 17-digit floats back one ulp off; real fight results produce
## such values all the time. Saves and tickets must still verify (RunStore.json_stable).
func test_floats_json_cannot_round_trip_still_save_and_travel() -> void:
	# find such a value (about 1 in 7 random doubles; a source literal is already "parsed")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var nasty := 0.0
	for i in 1000:
		var x := rng.randf_range(10.0, 900.0)
		if float(JSON.parse_string(JSON.stringify([x], "", false, true))[0]) != x:
			nasty = x
			break
	check(nasty != 0.0, "precondition: found a float that does not survive one JSON round trip")
	var ctrl := new_run({"seed": 616})
	_advance(ctrl, 2)
	ctrl.state["elapsed"] = nasty
	ctrl.player("p0")["hp"] = nasty * 0.7
	ctrl.player("p0")["hype_carry"] = 1.0 / 3.0
	check_eq(store.save(ctrl.state, "tester"), OK, "the save verifies")
	var r := store.load_slot("tester", "off_the_street", cat())
	check(bool(r["ok"]), "and loads: %s" % r["error"])
	check_near(float(r["state"]["elapsed"]), nasty, 0.000001, "value kept (to the ulp)")
	var t := RunStore.make_ticket(ctrl.state, "p0")
	var wire = JSON.parse_string(JSON.stringify(t, "", false, true))
	check(RunStore.ticket_valid(wire), "a ticket survives the wire")
	var prof := Profiles.default_profile("t", "T")
	ctrl.abandon()
	ctrl.state["result"]["elapsed"] = nasty
	CampaignProgression.finish_run(cat(), ctrl.state, "p0", prof)
	var h: Dictionary = prof["history"][0]
	var back := float(JSON.parse_string(JSON.stringify([h["time"]], "", false, true))[0])
	check_eq(back, float(h["time"]), "profile history times survive JSON exactly")
