extends CareerTestCase
## CMP-08 Career saves (SAV-01/02 rules applied to careers): create/save/load round trips exactly
## (seed included), damaged / newer / missing saves are reported and kept, retiring frees a slot
## and can never bring the career back (design contract D3), careers never show up as suspended
## runs, CareerState.check invariants, missing content (D9) and the content block (D1).


func after_each() -> void:
	Saves.simulate_crash_after_tmp = false
	store = null
	super.after_each()


func test_create_save_load_round_trip_is_identical() -> void:
	new_store()
	var ctrl := new_career({"seed": 0}, true)      # a fresh random seed, as in normal play
	check(ctrl.train("power")["ok"], "train a week")
	var o: Dictionary = ctrl.state["offers"][0]
	check(ctrl.accept(str(o["id"])), "accept")
	ctrl.train("rest")
	var r := CareerController.load_career(cat(), store, "tester", 1)
	check(bool(r["ok"]), "loads: %s" % r["error"])
	if not bool(r["ok"]):
		return
	var back: CareerController = r["ctrl"]
	check_eq(sig(back.state), sig(ctrl.state), "the loaded career equals the saved one")
	check_eq(int(back.state["seed"]), int(ctrl.state["seed"]), "the 53-bit seed survives exactly")
	check(back.repairs.is_empty(), "nothing to repair")
	# and both continue identically
	back.train("speed")
	ctrl.train("speed")
	check_eq(sig(back.state["stats"]), sig(ctrl.state["stats"]), "same training after a reload")
	check_eq(int(back.state["booked"]["weeks_left"]), int(ctrl.state["booked"]["weeks_left"]), "same camp")


func test_new_career_basics() -> void:
	var ctrl := new_career({"name": "  An Extremely Long Ring Name  ", "nick": "A Nickname Way Too Long", "fighter": "f_dredge"})
	check_eq(str(ctrl.state["name"]), "An Extremely L", "name trimmed to 14")
	check_eq(str(ctrl.state["nick"]).length(), 16, "nickname at most 16")
	check_eq(int(ctrl.state["money"]), 2000, "start money")
	check_near(float(ctrl.state["pop"]), 2.0, 0.001, "start popularity")
	check_eq(int(ctrl.state["week"]), 1, "week 1")
	check_eq(ctrl.week_label(), "Year 1 · Week 1", "week label")
	check_eq(CareerState.week_label(53), "Year 2 · Week 1", "52-week years")
	var offers: Array = ctrl.state["offers"]
	check(offers.size() >= 2 and offers.size() <= 3, "2-3 offers (%d)" % offers.size())
	for of in offers:
		check(int(of["tier"]) == 0, "a new career only hears from the regional tier")
	check_eq((ctrl.state["log"] as Array).size(), 1, "career start news line")
	check(CareerState.check(cat(), ctrl.state).is_empty(), "a new career is valid: %s" % [CareerState.check(cat(), ctrl.state)])
	var unnamed := new_career({"name": "   ", "nick": ""})
	check_eq(str(unnamed.state["name"]), "You", "an empty name falls back (Cage Rules)")
	var bad := CareerController.create(cat(), {"fighter": "not_a_fighter"})
	check(not bool(bad["ok"]) and bad["ctrl"] == null, "an unknown fighter is refused")


func test_starting_stats_follow_the_fighter() -> void:
	var rules := CareerDefaults.for_catalog(cat())
	for f in cat().available_fighters():
		var st := CareerState.starting_stats(rules, str(f))
		for k in CareerDefaults.STATS:
			check(float(st[k]) >= 0.30 and float(st[k]) <= 0.50, "%s %s starts in ~0.33-0.49 (%.2f)" % [f, k, float(st[k])])
		var rt := CareerState.rating(st)
		check(rt >= 37 and rt <= 43, "%s starts at rating ~40 (%d)" % [f, rt])
	var g := CareerState.starting_stats(rules, "f_gusto")
	check(float(g["speed"]) > float(g["chin"]), "Gusto starts quick but fragile")
	var d := CareerState.starting_stats(rules, "f_dredge")
	check(float(d["chin"]) > float(d["speed"]), "Dredge starts sturdy but slow")
	check_near(float(d["chin"]), snappedf(0.16 + 0.90 * 0.36, 0.01), 0.0001, "Cage Rules formula 0.16 + shape x 0.36")


func test_damaged_newer_missing_saves_are_reported_and_kept() -> void:
	new_store()
	var path := store.slot_path("tester", 2)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{\"format\": \"critterweight\", \"kind\": \"career\", \"version\": 1, \"checksum\": \"x\", \"data\": {")
	f.close()
	var r := store.load_slot("tester", 2, cat())
	check(not bool(r["ok"]), "a damaged save does not load")
	check(str(r["error"]).contains("damaged"), "clear message: %s" % r["error"])
	check(FileAccess.file_exists(path), "the damaged file is left untouched")
	var rows := store.list("tester", cat())
	check_eq(rows.size(), 3, "three slots listed")
	check(bool(rows[1]["occupied"]) and not bool(rows[1]["ok"]) and str(rows[1]["error"]) != "", "the damaged slot shows its error")
	check(not bool(rows[0]["occupied"]) and not bool(rows[2]["occupied"]), "the other slots are free")
	check_eq(store.free_slot("tester"), 1, "first free slot")
	# newer format
	var ctrl := new_career()
	var p3 := store.slot_path("tester", 3)
	Saves.write_json(p3, CareerStore.KIND, 99, ctrl.state)
	var r3 := store.load_slot("tester", 3, cat())
	check(not bool(r3["ok"]) and bool(r3["newer"]), "a newer-format career is not loaded")
	check(str(r3["error"]).contains("newer"), "clear message: %s" % r3["error"])
	var ra := store.retire("tester", 3)
	check(not bool(ra["ok"]) and FileAccess.file_exists(p3), "a newer-format slot is never moved aside")
	check_eq(store.save(ctrl.state, "tester", 3), ERR_FILE_CANT_WRITE, "nor overwritten")
	# missing
	var rm := store.load_slot("nobody", 1, cat())
	check(not bool(rm["ok"]) and not bool(rm["exists"]), "missing slot")
	check(str(rm["error"]).contains("empty"), "clear message: %s" % rm["error"])
	# the damaged slot can be moved aside, and then it is free
	var mv := store.move_aside("tester", 2)
	check(bool(mv["ok"]) and not store.occupied("tester", 2), "move aside frees the damaged slot")
	check(not FileAccess.file_exists(path), "nothing left in the slot namespace")


func test_damaged_main_recovers_from_backup() -> void:
	new_store()
	var ctrl := new_career({}, true)
	ctrl.train("chin")              # second save: the first rotates to .bak
	var path := store.slot_path("tester", 1)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("garbage")
	f.close()
	var r := store.load_slot("tester", 1, cat())
	check(bool(r["ok"]), "falls back to the backup: %s" % r["error"])
	check_eq(str(r["recovered_from"]), "bak", "recovered from .bak")


## D3: retiring moves every copy aside; the freed slot reads as empty and a career written there
## later can never recover the retired one (not even through a leftover .bak / .tmp).
func test_retire_frees_the_slot_and_never_resurrects() -> void:
	new_store()
	var old := new_career({"name": "Old Timer"}, true)
	old.train("power")
	old.train("speed")            # main + .bak exist now
	Saves.simulate_crash_after_tmp = true
	old.train("chin")             # ...and a verified .tmp (interrupted write)
	Saves.simulate_crash_after_tmp = false
	var path := store.slot_path("tester", 1)
	check(FileAccess.file_exists(path) and FileAccess.file_exists(path + ".bak") and FileAccess.file_exists(path + ".tmp"), "precondition: all three copies")
	var old_id := str(old.state["career_id"])
	var rr := old.retire()
	check(bool(rr["ok"]), "retired: %s" % rr["error"])
	check_eq((rr["moved"] as Array).size(), 3, "all three copies moved aside")
	for p in rr["moved"]:
		check(FileAccess.file_exists(str(p)) and str(p).contains("/retired/"), "kept under retired/: %s" % p)
	check(not store.occupied("tester", 1), "the slot is free")
	check(not bool(store.list("tester", cat())[0]["occupied"]), "and lists as free")
	var rj := Saves.read_json(path, CareerStore.KIND, CareerState.VERSION)
	check(not bool(rj["exists"]) and not bool(rj["ok"]), "read_json finds nothing (exists=false)")
	check(old.store == null, "a retired controller stops autosaving")
	old.train("power")
	check(not store.occupied("tester", 1), "...so it cannot recreate the slot")
	# a new career in the freed slot, then its only copy gets damaged: nothing old comes back
	var fresh := new_career({"name": "New Blood", "seed": 777}, true)
	check(str(fresh.state["career_id"]) != old_id, "a different career")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("garbage")
	f.close()
	var r := store.load_slot("tester", 1, cat())
	check(not bool(r["ok"]) or str(r["state"].get("career_id", "")) != old_id, "the retired career never resurfaces")
	var r2 := Saves.read_json(path, CareerStore.KIND, CareerState.VERSION)
	check(not bool(r2["ok"]), "no leftover copy recovers anything")


## RunStore.list lists every *.json in runs/<profile>/ as a suspended run: careers live elsewhere.
func test_career_files_are_never_listed_as_runs() -> void:
	var saved_root := Paths.root
	Paths.root = temp_dir("career_root_%d" % Time.get_ticks_usec())
	store = CareerStore.new()
	var ctrl := new_career({}, true)
	ctrl.train("power")
	var path := store.slot_path("tester", 1)
	check(FileAccess.file_exists(path), "the career is on disk")
	check(path.begins_with(Paths.dir("careers")), "under careers/")
	check(not path.begins_with(Paths.dir("runs")) and not path.begins_with(Paths.dir("profiles")), "never under runs/ or profiles/")
	check(RunStore.new().list("tester", cat()).is_empty(), "RunStore.list shows no career")
	# positive control: a real suspended run IS listed, and it is the only entry
	RunStore.new().save(new_run({"seed": 31}).state, "tester")
	var runs := RunStore.new().list("tester", cat())
	check(runs.size() == 1 and str(runs[0]["slot"]) == "off_the_street", "only the run is listed: %s" % [runs])
	Paths.root = saved_root


func test_check_reports_invariants() -> void:
	var ctrl := new_career()
	check(CareerState.check(cat(), ctrl.state).is_empty(), "valid")
	var bad: Dictionary = ctrl.state.duplicate(true)
	bad["stats"]["power"] = 1.5
	bad["money"] = -5
	bad["injury"]["head"] = 140.0
	var probs := CareerState.check(cat(), bad)
	check(probs.size() >= 3, "out-of-range values reported: %s" % [probs])
	var old: Dictionary = ctrl.state.duplicate(true)
	old["version"] = 2
	check(not CareerState.check(cat(), old).is_empty(), "a different version is reported")
	check(CareerState.migrate(ctrl.state, CareerState.VERSION) != null, "v1 passes migrate")
	check(CareerState.migrate(ctrl.state, 0) == null, "no migration from unknown versions (file kept)")
	var dup: Dictionary = ctrl.state.duplicate(true)
	var o: Dictionary = dup["offers"][0]
	dup["booked"] = {"offer": o.duplicate(true), "weeks_left": 2, "plan": [], "in_fight": false}
	check(not CareerState.check(cat(), dup).is_empty(), "a booked fight that is still offered is reported")


## D9: stale offers are re-rolled on load; a booked fight with missing content can be called off
## without penalty; a career whose own fighter is gone does not load (and is kept).
func test_missing_content_handling() -> void:
	new_store()
	var ctrl := new_career({}, true)
	ctrl.state["offers"][0]["opp"]["fighter"] = "gone_mod:f_vanished"
	ctrl.state["offers"][1]["arena"] = "gone_mod:arena_vanished"
	store.save(ctrl.state, "tester", 1)
	var probs := CareerState.check(cat(), ctrl.state)
	check(probs.has("missing offer creature:gone_mod:f_vanished") and probs.has("missing offer arena:gone_mod:arena_vanished"), "missing ids reported: %s" % [probs])
	var r := CareerController.load_career(cat(), store, "tester", 1)
	check(bool(r["ok"]), "stale offers do not block loading: %s" % r["error"])
	var back: CareerController = r["ctrl"]
	check(not back.repairs.is_empty(), "the offers were re-rolled")
	for o in back.state["offers"]:
		check(CareerState.offer_missing(cat(), o).is_empty(), "every new offer can be fought")
	check_eq(int(back.state["week"]), int(ctrl.state["week"]), "same week")
	check_eq(sig(store.load_slot("tester", 1, cat())["state"]["offers"]), sig(back.state["offers"]), "the repair was autosaved")
	# a booked fight whose opponent is gone
	var o2: Dictionary = back.state["offers"][0]
	check(back.accept(str(o2["id"])), "accept")
	back.state["booked"]["offer"]["opp"]["fighter"] = "gone_mod:f_vanished"
	back.state["booked"]["weeks_left"] = 0
	store.save(back.state, "tester", 1)
	var r2 := CareerController.load_career(cat(), store, "tester", 1)
	check(bool(r2["ok"]), "loads: %s" % r2["error"])
	var c2: CareerController = r2["ctrl"]
	check_eq(c2.booked_missing(), ["creature:gone_mod:f_vanished"], "the missing opponent is named")
	check(not c2.begin_fight(), "the fight cannot start")
	check(not (c2.fight_config()["errors"] as PackedStringArray).is_empty(), "and cannot be built")
	var pop := float(c2.state["pop"])
	var week := int(c2.state["week"])
	check(c2.cancel_booked(), "cancelled: %s" % c2.last_error)
	check(not c2.is_booked(), "no longer booked")
	check_eq(int(c2.state["week"]), week, "week unchanged")
	check_near(float(c2.state["pop"]), pop, 0.0001, "no popularity penalty")
	check(not (c2.state["offers"] as Array).is_empty(), "offers re-rolled")
	check(not c2.cancel_booked(), "nothing left to cancel")
	# the career's own fighter is gone: not loadable, file kept
	c2.state["fighter"] = "gone_mod:f_mine"
	store.save(c2.state, "tester", 1)
	var r3 := store.load_slot("tester", 1, cat())
	check(not bool(r3["ok"]), "a career without its fighter does not load")
	check(str(r3["error"]).contains("gone_mod:f_mine"), "names the fighter: %s" % r3["error"])
	check(store.occupied("tester", 1), "and is kept")


## D1: the shipped block equals the code defaults; a missing or partial block stays playable.
func test_content_block_and_defaults() -> void:
	var block = cat().rules.get("career", {})
	check(typeof(block) == TYPE_DICTIONARY and not (block as Dictionary).is_empty(), "campaign_rules.json carries a career block")
	var defaults := CareerDefaults.rules()
	for k in block:
		if not str(k).begins_with("_"):
			check(defaults.has(k), "content key '%s' is a known career rule" % k)
	check_eq(sig(CareerDefaults.for_catalog(cat())), sig(defaults), "the core block mirrors CareerDefaults")
	check(Content.errors.is_empty() or not "\n".join(Content.errors).contains("campaign_rules"), "the ladder entry still validates")
	# no block at all
	var bare := CampaignCatalog.new(Content, STAND_IN)
	bare.rules.erase("career")
	var c1 := new_career({}, false, bare)
	check(not (c1.state["offers"] as Array).is_empty(), "defaults alone run a career")
	# a partial block merges key by key
	var part := CampaignCatalog.new(Content, STAND_IN)
	part.rules["career"] = {"start": {"money": 5000}, "tiers": ["A", "B", "C", "D"]}
	var c2 := new_career({}, false, part)
	check_eq(int(c2.state["money"]), 5000, "overridden key")
	check_near(float(c2.state["pop"]), 2.0, 0.001, "sibling keys keep their defaults")
	check_eq(c2.standing()["tier_name"], "A", "arrays are replaced whole")
	check_eq((c2.rules["orgs"] as Array).size(), 9, "untouched arrays keep their defaults")


func test_slot_rules() -> void:
	new_store()
	var a := new_career({"slot": 1}, true)
	var dup := CareerController.create(cat(), {"fighter": "f_stoke"}, store, "tester", 1)
	check(not bool(dup["ok"]), "an occupied slot is never overwritten by a new career")
	var bad := CareerController.create(cat(), {"fighter": "f_stoke"}, store, "tester", 4)
	check(not bool(bad["ok"]), "only slots 1-3")
	new_career({"slot": 2, "fighter": "f_gusto", "name": "Second"}, true)
	var rows := store.list("tester", cat())
	check(bool(rows[0]["ok"]) and bool(rows[1]["ok"]) and not bool(rows[2]["occupied"]), "two careers, one free slot")
	var s: Dictionary = rows[1]["summary"]
	check_eq(str(s["name"]), "Second", "slot summary name")
	check_eq(str(s["fighter"]), "f_gusto", "slot summary fighter")
	check_eq(str(s["record_text"]), "0-0", "slot summary record")
	check(str(s["week_label"]).begins_with("Year 1"), "slot summary date")
	check(int(s["saved_at"]) > 0, "slot summary last saved")
	check(str(s["standing"]) != "", "slot summary standing")
	check_eq(str(a.summary()["name"]), "Tester", "controller summary")
