extends HubTestCase
## What the Cannery unlocks reaches the rest of the game (docs/HUB_SYSTEMS.md §16):
##   * the two hidden arena looks are real ArenaDef variants: Rooftop full neon replaces the night
##     look once the sign is fixed (match context / App.resolve_match_config), Pier Night is a Chum
##     Rush look offered in the versus setup only once fished up
##   * the Vintage Bellows line pack calls in-match announcing when selected (profile option)
##   * development stand-ins stay hidden in normal play (dev flag only)
##   * Kid Lamprey's real kit replaces the renamed roster stand-in as soon as it parses cleanly
## User data is redirected to a temporary root.

var _root := ""
var _profile := {}


func before_each() -> void:
	App.clear_screens()
	_root = Paths.root
	Paths.root = temp_dir("hub_unl_%d" % Time.get_ticks_usec())
	_profile = Profiles.current
	Profiles.current = Profiles.default_profile("hub_unl", "Unlocker")
	CampaignProgression.ensure_fields(Profiles.current)
	CampaignFlow.force_dev_tools = false


func after_each() -> void:
	App.clear_screens()
	if App.current_scene != null:
		App.set_scene(null)
	CampaignFlow.force_dev_tools = false
	Audio.set_announcer_pack("")
	Paths.root = _root
	Profiles.current = _profile


func _unlock(id: String) -> void:
	HubState.new(Profiles.current).unlock_cosmetic(id)


func _letters(view: ArenaView) -> Array:
	return view.find_children("Letter*", "Label3D", true, false)


func test_rooftop_full_neon_replaces_the_night_look_once_unlocked() -> void:
	var cfg := {"arena": "arena_rooftop", "rules": {"rounds": 1}, "seed": 3, "fighters": []}
	check_eq((App.resolve_match_config(cfg)["arena"] as ArenaDef).variant, "night", "a fresh profile gets the stock night")
	var stock := ArenaView.new()
	add_child(stock)
	stock.build(App.resolve_match_config(cfg)["arena"])
	var dead := _letters(stock).filter(func(l): return not bool((l as Node).get_meta("lit", true)))
	check(dead.size() == 1 and (dead[0] as Label3D).text == "A", "GL_NDCO: the A is a dead tube on a normal night")
	check(stock.find_children("FullNeonBorder", "", true, false).is_empty(), "no extra neon")
	stock.queue_free()
	_unlock("hub_rooftop_neon")
	var a: ArenaDef = App.resolve_match_config(cfg)["arena"]
	check_eq(a.variant, "night_neon", "once the sign is fixed every rooftop match gets the full-neon night")
	var neon := ArenaView.new()
	add_child(neon)
	neon.build(a)
	check(_letters(neon).all(func(l): return bool((l as Node).get_meta("lit", false))), "every GLANDCO letter lit")
	check(not neon.find_children("FullNeonBorder", "", true, false).is_empty(), "with the neon border")
	neon.queue_free()
	# the look is presentation only: same arena geometry and rules
	var base: ArenaDef = Content.arena("arena_rooftop")
	check(a.extent() == base.extent() and a.ringout == base.ringout, "lighting and dressing only")
	await wait_frames(1)


func test_pier_night_is_a_hidden_chum_rush_look() -> void:
	var dd: ArenaDef = Content.arena("arena_drydock")
	check(dd.base_def["variants"].has("pier_night"), "Pier Night is a Drydock variant")
	check(ArenaVariants.unlocked_extras(dd, Profiles.current, "chum_rush").is_empty(), "hidden until fished up")
	_unlock("hub_pier_night")
	var looks := ArenaVariants.unlocked_extras(dd, Profiles.current, "chum_rush")
	check(looks.size() == 1 and str(looks[0]["id"]) == "pier_night", "offered for Chum Rush once unlocked")
	check(ArenaVariants.unlocked_extras(dd, Profiles.current, "standard").is_empty(), "a Chum Rush look only")
	# the versus setup's Look row appears for Chum Rush on the Drydock and starts the match in it
	App.push("versus_setup", {"mode": "versus", "fighters": 2})
	await wait_frames(3)
	var vs := App.top_screen()
	vs.setup["rules"] = "chum_rush"
	vs.setup["arena"] = "arena_drydock"
	vs.call("_rebuild", "")
	await wait_frames(2)
	var rows := vs.find_children("*", "OptionRow", true, false).filter(func(r): return str((r as Node).get_meta("focus_key", "")) == "look")
	check_eq(rows.size(), 1, "the Look row is offered")
	vs.setup["look"] = "pier_night"
	var cfg: Dictionary = vs.call("build_config")
	check_eq(str((cfg.get("context", {}) as Dictionary).get("variant", "")), "pier_night", "the match context names the look")
	check_eq((App.resolve_match_config(cfg)["arena"] as ArenaDef).variant, "pier_night", "and the arena resolves to it")
	vs.setup["rules"] = "duel"
	vs.call("_rebuild", "")
	await wait_frames(2)
	rows = vs.find_children("*", "OptionRow", true, false).filter(func(r): return str((r as Node).get_meta("focus_key", "")) == "look")
	check(rows.is_empty(), "no Look row for other rules")
	App.clear_screens()
	# the night sky comes out over the dock
	var pn := ArenaView.new()
	add_child(pn)
	pn.build(dd.with_variant("pier_night"))
	var sky_mat := pn.env.environment.sky.sky_material as ShaderMaterial
	check(float(sky_mat.get_shader_parameter("stars")) > 0.5 and float(sky_mat.get_shader_parameter("moon")) > 0.5, "stars and the moon over Pier Night")
	pn.queue_free()
	await wait_frames(1)


func test_vintage_bellows_calls_matches_when_selected() -> void:
	check(Audio.line_packs().has("vintage_bellows"), "the line pack is installed")
	check(Audio.pack_line_ids("vintage_bellows").size() >= 20, "with a full set of calls")
	var ctx := {"player_index": 0, "fighters": [{"index": 0, "creature": "f_stoke", "name": "COSMO", "team": 0}, {"index": 1, "creature": "f_dredge", "name": "BOT", "team": 1}], "seed": 5}
	Audio.begin_match(ctx)
	check_eq(Audio.announcer_pack, "", "the standard Barnaby by default")
	for i in 6:
		check(not Audio.pick_line("ko", {"kind": ["heavy"]}).begins_with("ann_v73_"), "no 1973 lines unless selected")
	# selected at Barnaby's desk: the profile option the match reads
	var st := HubState.new(Profiles.current)
	st.unlock_cosmetic("hub_pack_vintage_bellows")
	st.set_pack("vintage_bellows", true)
	check_eq(str(Profiles.current.get("announcer_pack", "")), "vintage_bellows", "the desk sets the profile's announcer pack")
	Audio.begin_match(ctx)
	check_eq(Audio.announcer_pack, "vintage_bellows", "matches pick it up")
	for trig in ["intro", "round_start", "ko", "win"]:
		# (the 1973 "It's OVER!" KO call is only for the knockout that ends the fight, v0.9.17)
		check(Audio.pick_line(trig, {"creature": "f_stoke", "kind": ["heavy"], "round": 1, "ends": "fight"}).begins_with("ann_v73_"), "%s is called by 1973 Barnaby" % trig)
	check(Audio.pick_line("tutorial", {"kind": "intro"}).begins_with("ann_v73_") == false, "triggers the pack doesn't cover use the standard bank")
	st.set_pack("vintage_bellows", false)
	Audio.begin_match(ctx)
	check_eq(Audio.announcer_pack, "", "and turning it off at the desk restores the standard calls")
	Audio.end_match()


func test_dev_stand_ins_stay_hidden_in_normal_play() -> void:
	var cat := CampaignCatalog.shared()
	var incomplete := cat.available_fighters().size() < cat.roster().size()
	App.push("campaign_menu", {"variant": "fight_camp"})
	await wait_frames(3)
	check(not _has_button(App.top_screen(), "STAND-INS"), "no stand-in switch in the campaign menu in normal play")
	App.clear_screens()
	App.push("hub_board", {"kind": "run", "scene": null})
	await wait_frames(3)
	check(not _has_button(App.top_screen(), "stand-ins"), "nor on Snappington's sign-up sheet")
	App.clear_screens()
	# behind the dev flag (--dev, --campaign-stand-ins or Settings > Diagnostics > Developer tools)
	CampaignFlow.force_dev_tools = true
	App.push("campaign_menu", {"variant": "fight_camp"})
	await wait_frames(3)
	check(_has_button(App.top_screen(), "STAND-INS") == incomplete, "the dev flag shows it while kits are unfinished (%s)" % str(incomplete))
	App.clear_screens()
	App.push("hub_board", {"kind": "run", "scene": null})
	await wait_frames(3)
	check(_has_button(App.top_screen(), "stand-ins") == incomplete, "on the sign-up sheet too")
	App.clear_screens()
	await wait_frames(1)


func _has_button(root: Node, text: String) -> bool:
	if root == null:
		return false
	for b in root.find_children("*", "BaseButton", true, false):
		if (b as Button) != null and (b as Button).text.contains(text):
			return true
	return false


func test_kid_lamprey_switches_to_his_real_kit_automatically() -> void:
	check(not HubSparring.kid_ready() or Content.creature(HubSparring.KID) != null, "consistent")
	var real_kit := not CampaignCatalog.shared().resolver.usable_entry(HubSparring.KID).is_empty()
	if not real_kit:
		check(HubSparring.kid_creature("f_stoke") != HubSparring.KID, "until his kit exists a roster fighter stands in")
	# a clean kit installed under his id (here: a copy of a finished kit) is picked up automatically
	var donor := Content.creature_entry("f_dredge").duplicate(true)
	donor["id"] = HubSparring.KID
	donor["name"] = "Kid Lamprey"
	donor["npc_only"] = true
	_install(HubSparring.KID, donor)
	check(HubSparring.kid_ready(), "a cleanly parsing kit is ready")
	check_eq(HubSparring.kid_creature("f_stoke"), HubSparring.KID, "sparring uses the real Kid Lamprey")
	var cfg := HubSparring.config("f_stoke", "Cosmo", {"opponent": "kid_lamprey"})
	check_eq(str((cfg["fighters"] as Array)[1]["creature"]), HubSparring.KID, "in the match config")
	# a kit that is still being authored (does not parse cleanly) is not used yet
	var broken := donor.duplicate(true)
	(broken["stats"] as Dictionary)["no_such_stat"] = 1.0
	_install(HubSparring.KID, broken)
	if not CampaignCatalog.shared().resolver.problems(HubSparring.KID).is_empty():
		check(HubSparring.kid_creature("f_stoke") != HubSparring.KID, "an unfinished kit keeps the stand-in")
	_uninstall(HubSparring.KID)
	check_eq(HubSparring.kid_ready(), real_kit, "back to the installed content")


func _install(id: String, d: Dictionary) -> void:
	if not Content.tables.has("minions"):
		Content.tables["minions"] = {}
	if not has_meta("kid_saved"):
		set_meta("kid_saved", (Content.tables["minions"] as Dictionary).get(id, {}))
	Content.tables["minions"][id] = d
	Content.creatures.erase(id)
	CampaignCatalog._invalidate_shared()


func _uninstall(id: String) -> void:
	var saved: Dictionary = get_meta("kid_saved", {})
	if saved.is_empty():
		(Content.tables["minions"] as Dictionary).erase(id)
	else:
		Content.tables["minions"][id] = saved
	remove_meta("kid_saved")
	Content.creatures.erase(id)
	CampaignCatalog._invalidate_shared()
