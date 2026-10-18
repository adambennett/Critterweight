extends HubTestCase
## CMP-03/CMP-04 upgrade stations: the hub buys Cannery upgrades through HubServices (the one adapter
## to the campaign's FightCamp API), every station lists its upgrades, Clout and gates are
## enforced, purchases change the world (HubUpgradeProps: each upgrade visible, 12+ fixes the
## lights, all 24 swap the cage banner), and Snappington's desk builds a real Fight Camp run.


class FakeBackend:
	extends RefCounted
	var bought := []

	func stations() -> Array:
		return [{"id": "gym_floor"}]

	func list_upgrades(_p: Dictionary, station: String) -> Array:
		return [{"id": "meta_heavy_bag", "name": "Heavy Bag", "station": station, "level": 0, "max_level": 3, "next_cost": 80, "maxed": false, "locked": false, "affordable": true}]

	func buy_upgrade(p: Dictionary, id: String) -> Dictionary:
		bought.append(id)
		p["camp"]["upgrades"][id] = 1
		return {"ok": true, "level": 1, "clout": 0}

	func run_options(_p: Dictionary) -> Dictionary:
		return {"fighters": ["f_stoke"], "difficulties": [{"id": "amateur", "name": "Amateur"}], "doses": [{"level": 0, "name": "Base card"}]}

	func start_run(_p: Dictionary, choices: Dictionary) -> Dictionary:
		return {"ok": str(choices.get("fighter", "")) != "", "error": ""}


func _services(clout := 0) -> HubServices:
	make_hub("f_stoke")
	state.camp()["clout"] = clout
	return HubServices.new(state)


func test_every_station_lists_its_upgrades() -> void:
	var sv := _services()
	check(sv.available(), "the campaign services are installed")
	var total := 0
	var expect := {"gym_floor": 6, "med_bay": 3, "juice_bar": 4, "office": 6, "loading_dock": 3, "boiler_room": 2}
	for st in expect:
		var rows := sv.list_upgrades(str(st))
		check_eq(rows.size(), int(expect[st]), "%s sells %d upgrades" % [st, int(expect[st])])
		total += rows.size()
		for r in rows:
			var d: Dictionary = r
			for k in ["id", "name", "effect", "level", "max_level", "next_cost", "locked", "affordable"]:
				check(d.has(k), "%s row has %s" % [d.get("id", "?"), k])
			check(HubUpgradeProps.ALL_UPGRADES.has(str(d["id"])), "%s has a visible world change" % d["id"])
			check(HubBoardStation.VISIBLE.has(str(d["id"])), "%s's board explains what changes" % d["id"])
	check_eq(total, 24, "24 Cannery upgrades at six stations (HUB.md §4)")
	var ids := []
	for st2 in expect:
		for r2 in sv.list_upgrades(str(st2)):
			ids.append(str(r2["id"]))
	for id in HubUpgradeProps.ALL_UPGRADES:
		check(ids.has(id), "the world knows %s and the campaign sells it" % id)


func test_purchase_flow_spends_clout_and_respects_gates() -> void:
	var sv := _services(0)
	var r0 := sv.buy_upgrade("meta_heavy_bag")
	check(not bool(r0.get("ok", true)), "no Clout, no sale")
	check(str(r0.get("error", "")).contains("Clout"), "and the reason says so")
	state.camp()["clout"] = 1000
	var seen := []
	state.changed.connect(func(kind: String, data: Dictionary) -> void: seen.append([kind, data]))
	var r1 := sv.buy_upgrade("meta_heavy_bag")
	check(bool(r1.get("ok", false)), "bought Heavy Bag")
	check_eq(state.upgrade_level("meta_heavy_bag"), 1, "level 1")
	check_eq(state.clout(), 920, "80 Clout spent")
	check(seen.any(func(x): return str(x[0]) == "upgrade"), "the hub is told (world change)")
	var r2 := sv.buy_upgrade("meta_heavy_bag")
	check(bool(r2.get("ok", false)) and state.upgrade_level("meta_heavy_bag") == 2, "level 2 costs the next price")
	check_eq(state.clout(), 760, "160 more")
	# gated upgrades
	var r3 := sv.buy_upgrade("meta_grappling_dummy")
	check(not bool(r3.get("ok", true)) and str(r3.get("error", "")).contains("locked"), "Grappling Dummy needs Act 1 beaten")
	state.camp()["flags"]["beat_act1"] = true
	var r4 := sv.buy_upgrade("meta_grappling_dummy")
	check(bool(r4.get("ok", false)), "unlocked after beating Act 1")
	# the station board shows the same truth
	var rows := sv.list_upgrades("gym_floor")
	var hb: Dictionary = rows.filter(func(x): return str(x["id"]) == "meta_heavy_bag")[0]
	check_eq(int(hb["level"]), 2, "the board reads level 2")


func test_purchases_change_the_world() -> void:
	make_hub("f_stoke")
	var view := HubView.new()
	add_child(view)
	view.build(mode, state)
	var up := view.upgrades
	check(not (up.nodes["meta_heavy_bag:1"] as Node3D).visible, "no extra bag before buying")
	state.camp()["upgrades"]["meta_heavy_bag"] = 1
	up.refresh()
	check((up.nodes["meta_heavy_bag:1"] as Node3D).visible, "a new heavy bag appears")
	check(not (up.nodes["meta_heavy_bag:2"] as Node3D).visible, "only as many as levels bought")
	check(not up.lights_fixed(), "the dead fluorescents stay dead below 12 upgrades")
	for i in 12:
		state.camp()["upgrades"][HubUpgradeProps.ALL_UPGRADES[i]] = 1
	up.refresh()
	check(up.lights_fixed(), "12 upgrades: the Main Floor's fluorescents work")
	check(view.dressing.cage_banner.visible, "the Glandco banner still hangs")
	for id in HubUpgradeProps.ALL_UPGRADES:
		state.camp()["upgrades"][id] = 1
	up.refresh()
	check(not view.dressing.cage_banner.visible, "all 24: the Glandco banner comes down")
	check(up.player_banner != null and up.player_banner.visible, "...and your fighter's banner goes up")
	for id2 in HubUpgradeProps.ALL_UPGRADES:
		check((up.nodes[id2 + ":1"] as Node3D).visible, "%s is visible in the world" % id2)
	view.queue_free()


func test_snappington_run_options_and_config() -> void:
	var sv := _services(0)
	state.camp()["upgrades"]["meta_sponsorship"] = 2
	var o := sv.run_options()
	check(o.has("fighters") and o.has("difficulties") and o.has("doses"), "the sign-up sheet has fighters, difficulties and Doses")
	check(not (o["difficulties"] as Array).is_empty(), "difficulties listed")
	check(str((o["difficulties"] as Array)[0].get("name", "")) != "", "with names")
	var cfg := sv.run_config({"fighter": "f_stoke", "difficulty": "amateur", "dose": 0, "seed_text": "cannery"})
	check_eq(str(cfg["variant"]), "fight_camp", "a Fight Camp run")
	check(int(cfg["seed"]) != 0, "a typed seed becomes the run seed")
	var p0: Dictionary = (cfg["players"] as Array)[0]
	check_eq(str(p0["fighter"]), "f_stoke", "with the chosen fighter")
	check_eq(int((p0["meta"] as Dictionary).get("meta_sponsorship", 0)), 2, "carrying the Cannery upgrades into the run")


func test_start_run_hands_over_to_the_campaign() -> void:
	# its own user root and profile: the run it starts is saved, and a suspended Fight Camp run
	# left by an earlier test run must not stand in the way (that path asks first, see the
	# campaign UI tests)
	var old_root := Paths.root
	var old_profile := Profiles.current
	Paths.root = temp_dir("hub_start_%d" % Time.get_ticks_usec())
	Profiles.current = Profiles.default_profile("hub_start", "Start Tester")
	CampaignProgression.ensure_fields(Profiles.current)
	var sv := _services(0)
	var fighters: Array = sv.run_options().get("fighters", [])
	if fighters.is_empty():
		# kits still being authored: the campaign's development stand-ins (marked custom) start the card
		sv.stand_ins = true
		fighters = sv.run_options().get("fighters", [])
		check(not fighters.is_empty(), "stand-ins make the roster available")
		check(not (sv.run_config({"fighter": str(fighters[0])})["custom_reasons"] as Array).is_empty(), "a stand-in run is marked custom")
	var r := sv.start_run({"fighter": str(fighters[0]), "difficulty": "amateur", "dose": 0})
	await wait_frames(3)
	check(bool(r.get("ok", false)), "the run started (%s)" % str(r.get("error", "")))
	var top := App.top_screen()
	check(top != null and str(top.screen_name) in ["run_map", "event", "shop", "rest", "reward"], "the campaign's run screens take over (%s)" % (str(top.screen_name) if top else "none"))
	App.set_scene(null)
	App.clear_screens()
	await wait_frames(2)
	Paths.root = old_root
	Profiles.current = old_profile


func test_bookie_table_and_lab_terminal_for_real() -> void:
	var old_root := Paths.root
	var old_profile := Profiles.current
	Paths.root = temp_dir("hub_bookie_%d" % Time.get_ticks_usec())
	Profiles.current = Profiles.default_profile("hub_bookie", "Bookie Tester")
	CampaignProgression.ensure_fields(Profiles.current)
	var sv := _services(0)
	if check(App.has_screen("bookie"), "the campaign's Bookie's Table screen is installed"):
		check(sv.open_bookie(), "Teddy's table opens from the Boiler Room")
		await wait_frames(4)
		var top := App.top_screen()
		check(top != null and top.screen_name == "bookie", "the Bookie's Table takes over (%s)" % (top.screen_name if top else "none"))
		if top != null:
			# B on the table's setup page leaves it — back to Teddy, not the campaign menu
			top.on_back()
			await wait_physics(10)
			await wait_frames(4)
			var sc := App.current_scene as HubScene
			check(sc != null, "leaving the table walks back into the Cannery")
			if sc != null:
				check_eq(sc.mode.current_space, "boiler_room", "by Teddy's table")
	App.clear_screens()
	App.set_scene(null)
	var t := App.get_node_or_null("BookieTable")
	if t:
		t.queue_free()
	await wait_frames(2)
	# the AI Lab terminal: opens the Lab owner's screen when it is installed, stays dark otherwise
	if App.has_screen("lab"):
		check(sv.open_lab(), "the AI Lab terminal opens the Lab")
		await wait_frames(4)
		var lab := App.top_screen()
		check(lab != null and lab.screen_name == "lab", "the Lab screen is up")
		if lab != null:
			var fighter_picker := lab.get("_fighter") as OptionButton
			check(fighter_picker != null, "the AI Lab fighter picker is built")
			if fighter_picker != null and fighter_picker.item_count > 0:
				check_eq(fighter_picker.get_item_text(0), "Random", "the AI Lab offers Random")
				fighter_picker.item_selected.emit(0)
				var random_fighter := str(lab.call("_creature_id"))
				check(Content.playable_creatures().has(random_fighter), "AI Lab Random resolves to a playable fighter")
			lab.on_back()
			await wait_physics(10)
			await wait_frames(4)
			var sc2 := App.current_scene as HubScene
			check(sc2 != null and sc2.mode.current_space == "boiler_room", "leaving the Lab walks back to the terminal")
		App.clear_screens()
		App.set_scene(null)
	else:
		check(not sv.open_lab(), "no Lab installed in this build: the terminal stays dark (Teddy says so)")
	await wait_frames(2)
	Paths.root = old_root
	Profiles.current = old_profile


func test_injected_backend_is_used() -> void:
	make_hub("f_stoke")
	var fb := FakeBackend.new()
	var sv := HubServices.new(state, fb)
	check(sv.available(), "available with a backend")
	check_eq(sv.list_upgrades("gym_floor").size(), 1, "rows come from the backend")
	check(bool(sv.buy_upgrade("meta_heavy_bag").get("ok", false)), "purchase goes through the backend")
	check_eq(fb.bought, ["meta_heavy_bag"], "the backend saw the purchase")
	check(bool(sv.start_run({"fighter": "f_stoke"}).get("ok", false)), "run start goes through the backend")


## Hub review #4: the Boiler Room Key (100 Clout at Teddy's ledger) does what it promises — the AI
## Lab offers "My saved builds": your own campaign builds (fighter + techniques + supplements, saved
## at the end of every run) as training opponents, piloted by a Pro bot.
func test_boiler_room_key_trains_against_saved_builds() -> void:
	var sv := _services(150)
	var prof: Dictionary = state.profile
	CampaignProgression.ensure_fields(prof)
	var cat := CampaignCatalog.shared()
	var tech := ""
	for tid in cat.techniques:
		if not ((cat.techniques[tid] as Dictionary).get("apply", {}) as Dictionary).is_empty():
			tech = str(tid)
			break
	var sup := ""
	for sid in cat.supplements:
		if not (((cat.supplements[sid] as Dictionary).get("apply", {}) as Dictionary).get("mods", []) as Array).is_empty():
			sup = str(sid)
			break
	check(tech != "" and sup != "", "the catalog has a technique and a supplement to build with")
	prof["campaign"]["saved_builds"] = [{"run_id": "r1", "fighter": "f_dredge", "techniques": [tech], "supplements": [{"id": sup, "stacks": 1}],
		"dose": 2, "victory": true, "variant": "fight_camp"}]
	check(LabScenarios.saved_build_opponents(prof).is_empty(), "without the key the Lab offers no saved builds")
	check(not LabScenarios.preset_ids_for(prof).has("my_builds"), "...and no 'My saved builds' scenario")
	# bought at Teddy's ledger, through the hub's one adapter
	check(bool(sv.buy_upgrade("meta_boiler_room_key").get("ok", false)), "the key is bought for 100 Clout")
	check(LabScenarios.boiler_room_key(prof), "the profile holds the key")
	var kinds := LabScenarios.saved_build_opponents(prof)
	check_eq(kinds.size(), 1, "the saved build is a training opponent")
	if kinds.is_empty():
		return
	var kind := str(kinds[0])
	check(LabOpponents.is_valid(kind), "a valid Lab opponent")
	check(LabOpponents.display_name(kind).contains("Dredge"), "named after its fighter (%s)" % LabOpponents.display_name(kind))
	check(LabScenarios.preset_ids_for(prof).has("my_builds"), "the 'My saved builds' scenario is offered")
	# a job against it is valid as written (what the Lab hands its worker processes)
	var nj := LabJob.normalize({"creature": "f_stoke", "scenario": {"preset": "my_builds", "opponents": kinds}})
	check((nj["errors"] as PackedStringArray).is_empty(), "the training job is valid (%s)" % "; ".join(nj["errors"]))
	check_eq((nj["job"]["scenario"]["opponents"] as Array), kinds, "and keeps the build as its opponent")
	# an episode against it fights the build: its fighter, with its picks applied
	var comp := LabEpisode.compose_build(LabOpponents.build_of(kind))
	check(comp.get("creature") != null, "the build composes into a fighter")
	var sources: Array = comp.get("sources", [])
	check(sources.has(tech) and sources.has(sup), "with its technique and supplement (%s)" % str(sources))
	var ep := LabScenarios.episode(LabScenarios.PRESETS["my_builds"], kind, 11, "f_stoke", "f_stoke")
	var e := LabEpisode.new()
	var err := e.start(fresh_world(), {"i": 0, "episode": ep, "learner": {"type": "scripted", "kind": "idle"}}, null)
	check_eq(err, "", "the episode starts")
	if err == "":
		check_eq(e.sim.fighters[1].creature.id, "f_dredge", "the opponent is the build's fighter")
		var want: Dictionary = comp.get("mods", {})
		for k in want:
			check_near(float(e.sim.fighters[1].mods.get(k, -999.0)), float(want[k]), 0.0001, "with the build's %s" % k)
		check(e.sim.input_sources[1] is BotBrain, "piloted by a bot")
	# the Lab screen itself lists the scenario and the build (opened from the terminal)
	if App.has_screen("lab"):
		var old_profile := Profiles.current
		Profiles.current = prof
		App.push("lab", {"from_hub": true})
		await wait_frames(4)
		var lab := App.top_screen()
		var texts := []
		for n in lab.find_children("*", "", true, false):
			if n is CheckBox:
				texts.append((n as CheckBox).text)
			elif n is OptionButton:
				for i in (n as OptionButton).item_count:
					texts.append((n as OptionButton).get_item_text(i))
		check(texts.has("My saved builds"), "the Lab offers 'My saved builds'")
		check(texts.has(LabOpponents.display_name(kind)), "and the build as an opponent to tick")
		App.clear_screens()
		Profiles.current = old_profile
		await wait_frames(2)
