class_name HubScene
extends Node3D
## The Cannery as a playable place (docs/HUB_SYSTEMS.md §1): the hub MatchSim (your real fighter,
## the level physics, HubMode), its views (HubView, the fighter's CreatureView, Vfx), the follow
## camera, the HUD, the fades for hatches/ladders/elevator, the hub audio (Cannery Radio, room
## beds, footsteps through the match audio bridge) and the routing of hub events to boards,
## barks and feedback. Created by Cannery.enter(); App.set_scene() frees it when you leave.

const BARK_RANGE := 5.0
const BARK_COOLDOWN := 26.0
const BARK_GLOBAL := 7.0
const FADE_TIME := 0.28

var params := {}
var state: HubState
var services: HubServices
var sim: MatchSim
var mode: HubMode
var view: HubView
var creature_view: CreatureView
var camera: HubCamera
var vfx: Vfx
var hud_layer: CanvasLayer
var hud: HubHud
var fade: ColorRect
var input: HubPlayerInput
var radio_on := true
var _cursor := 0
var _fade_dir := 0.0               ## +1 fading to black, -1 fading in, 0 idle
var _waiting_teleport := false
var _save_t := 0.0
var _time := 0.0
var _bark_t := {}
var _last_bark := -99.0
var _greeted := {}
var _suppress_sub := false
var _last_space := ""


func start(p: Dictionary) -> void:
	params = p
	name = "HubScene"
	state = HubState.new(Profiles.current)
	state.hub()["visits"] = int(state.hub().get("visits", 0)) + 1
	services = HubServices.new(state)
	if str(p.get("demo", "")) != "":
		HubDemo.apply(state, str(p["demo"]))
	var spot := str(p.get("spot", ""))
	if spot == "" or not HubLayout.SPACES.has(spot):
		# first visit: the Main Floor (HUB.md's hub spawn point); later: where you left off
		spot = state.spot() if state.discovered().size() > 1 else "main_floor"
	if bool(HubLayout.space(spot).get("secret", false)) and not _secret_space_open(spot):
		spot = "main_floor"
	var fighter := Cannery.pick_fighter(state, str(p.get("fighter", "")))
	if state.loadout_fighter() == "":
		state.set_loadout_fighter(fighter)
	input = HubPlayerInput.new()
	var t0 := Time.get_ticks_usec()
	sim = Cannery.build_sim(self, state, fighter, spot, input, int(Time.get_ticks_msec() % 100000) + 7)
	Log.i("hub", "sim build ms: %.0f" % ((Time.get_ticks_usec() - t0) / 1000.0))
	mode = sim.mode as HubMode
	mode.auto_transition = false
	mode.dodge_interacts = false
	input.mode = mode
	view = HubView.new()
	add_child(view)
	view.build(mode, state)
	_make_creature_view()
	camera = HubCamera.new()
	add_child(camera)
	camera.target = player().pos()
	camera.set_space(mode.current_space)
	camera.snap()
	input.camera = camera
	vfx = Vfx.new()
	add_child(vfx)
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	hud = HubHud.new()
	hud.scene = self
	hud_layer.add_child(hud)
	var fl := CanvasLayer.new()
	fl.layer = 30
	add_child(fl)
	fade = ColorRect.new()
	fade.color = Color(0.03, 0.03, 0.05, 1.0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fl.add_child(fade)
	_fade_dir = -1.0
	_cursor = sim.event_seq
	_apply_settings()
	Audio.attach_match(sim, 0, {"context": "hub", "arena": "hub_cannery"})
	Audio.crowd_stop(0.1)
	Audio.music("cannery_radio", 1.5, {"diegetic": true})
	_enter_room(mode.current_space)
	if not Audio.subtitle.is_connected(_on_subtitle):
		Audio.subtitle.connect(_on_subtitle)
	if not state.changed.is_connected(_on_state_changed):
		state.changed.connect(_on_state_changed)
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)
	hud.set_space(mode.current_space, view.tod)
	_last_space = mode.current_space
	Platform.set_presence("The Cannery")
	_welcome()
	if str(p.get("cam_yaw", "")) != "":
		camera.yaw = deg_to_rad(float(p["cam_yaw"]))
		camera.snap()
	# QA captures: --hub-pos x,y,z[,yaw_deg] places the fighter inside the arrival space
	# (never split_floats an empty string: Godot 4.5 aborts on it)
	var pos_arg := Cannery.cli("--hub-pos")
	if pos_arg.count(",") >= 2:
		var at := pos_arg.split_floats(",")
		mode.teleport(player(), Vector3(at[0], at[1], at[2]), deg_to_rad(at[3]) if at.size() > 3 else 0.0)
	if str(p.get("board", "")) != "":
		var board := str(p["board"])
		get_tree().create_timer(1.2).timeout.connect(func() -> void: HubDemo.open_board(self, board))
	if OS.get_cmdline_user_args().has("--hub-bench"):
		var bench := HubBench.new()
		bench.scene = self
		add_child(bench)
		bench.run.call_deferred()


func _secret_space_open(spot: String) -> bool:
	match spot:
		"roof":
			return state.has_secret("sec_freight_elevator")
		"pier":
			return state.has_secret("sec_pier_ladder")
		"crawlspace":
			return state.has_secret("sec_loose_panel")
	return true


func player() -> Fighter:
	return sim.fighters[0]


## The Locker: walk around as another fighter (the body is rebuilt where you stand).
func switch_fighter(id: String) -> void:
	var c := Content.creature(id)
	var f := player()
	if c == null or c.id == f.creature.id:
		return
	var at := f.ground_pos()
	var yaw := f.facing_yaw
	mode.drop_carried(f)
	f.rebuild(c, at, yaw)
	f.reset_vitals()
	f.display_name = str(state.profile.get("name", "Rookie"))
	state.set_loadout_fighter(id)
	_make_creature_view()
	view.upgrades.refresh()
	Audio.sfx("taunt", f.pos())


func _make_creature_view() -> void:
	if creature_view:
		creature_view.queue_free()
	var f := player()
	creature_view = CreatureView.new()
	add_child(creature_view)
	creature_view.setup(f.creature, Color("#f2f2ec"))
	creature_view.gore_level = int({"full": 2, "reduced": 1, "off": 0}.get(str(Settings.get_value("access.gore")), 2))
	creature_view.snap_transforms(f.rig.segment_transforms())


func _apply_settings() -> void:
	view.apply_quality(Settings.quality())
	camera.shake_scale = float(Settings.get_value("access.camera_shake"))
	vfx.reduce_flashes = bool(Settings.get_value("access.reduce_flashing"))
	vfx.quality = int(Settings.get_value("graphics.effects"))


func _on_setting_changed(key: String, _v) -> void:
	if key.begins_with("graphics.") or key.begins_with("access.") or key == "display.brightness":
		_apply_settings()


func _exit_tree() -> void:
	if Audio.subtitle.is_connected(_on_subtitle):
		Audio.subtitle.disconnect(_on_subtitle)
	if Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.disconnect(_on_setting_changed)
	Audio.end_match()
	if state and state.dirty:
		Profiles.save()
		state.dirty = false


# =====================================================================================
# Frame loop
# =====================================================================================

func _physics_process(dt: float) -> void:
	if sim == null:
		return
	sim.step(dt)
	_process_events()
	creature_view.push_transforms(player().rig.segment_transforms())


func _process(dt: float) -> void:
	if sim == null:
		return
	_time += dt
	creature_view.render(Engine.get_physics_interpolation_fraction())
	creature_view.hype = player().hype / 100.0
	camera.target = player().pos()
	var board := App.top_screen() as HubBoard
	var shift := Vector2.ZERO
	if board != null:
		shift = {"right": Vector2(0.4, 0.0), "bottom": Vector2(0.0, 0.34)}.get(board.align, Vector2.ZERO)
	camera.frame_shift = shift
	view.update(dt, camera, player().pos())
	hud.update_hud(dt, mode, state)
	_update_fade(dt)
	_barks()
	_save_t += dt
	if state.dirty and _save_t > 2.0:
		Profiles.save()
		state.dirty = false
		_save_t = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and App.top_screen() == null and _fade_dir == 0.0:
		get_viewport().set_input_as_handled()
		open_board("pause")


func open_board(kind: String, p := {}) -> void:
	var q: Dictionary = p.duplicate()
	q["kind"] = kind
	q["scene"] = self
	Audio.ui("ui_open")
	App.push("hub_board", q)


func _update_fade(dt: float) -> void:
	if _fade_dir == 0.0:
		return
	var a := fade.color.a + _fade_dir * dt / FADE_TIME
	if _fade_dir > 0.0 and a >= 1.0:
		a = 1.0
		if _waiting_teleport:
			_waiting_teleport = false
			mode.complete_transition()
		_fade_dir = -1.0
	elif _fade_dir < 0.0 and a <= 0.0:
		a = 0.0
		_fade_dir = 0.0
	fade.color.a = a


# =====================================================================================
# Events
# =====================================================================================

func _process_events() -> void:
	for ev in sim.events_since(_cursor):
		_cursor = int(ev["seq"])
		_on_event(ev)


func _on_event(ev: Dictionary) -> void:
	match str(ev["type"]):
		"hub_interact":
			_on_interact(ev)
		"hub_space":
			_on_space(ev)
		"hub_transition":
			if str(ev["phase"]) == "out":
				_fade_dir = 1.0
				_waiting_teleport = true
				Audio.sfx("ui_open")
		"hub_teleport":
			camera.target = player().pos()
			camera.snap()
			creature_view.snap_transforms(player().rig.segment_transforms())
		"hub_activity":
			_on_activity(ev)
		"hub_score":
			var pts := int(ev.get("points", 0))
			var lbl := str(ev.get("label", ""))
			var txt := ("+%d" % pts) if pts > 0 else lbl
			if pts > 0 and lbl != "":
				txt = "%s  +%d" % [lbl, pts]
			vfx.word(ev["pos"] + Vector3.UP * 0.3, txt, Color("#ffd166") if pts > 0 else Color("#ff8a80"), 52 if pts >= 40 else 40)
		"hub_bag_hit":
			var heavy := bool(ev.get("heavy", false))
			Audio.sfx("hit_heavy" if heavy else "hit_light", ev["pos"])
			vfx.emit("spark", ev["pos"], Vector3.UP, Color(1.0, 0.9, 0.6), 0.6 + float(ev.get("quality", 0.0)))
			camera.add_trauma(0.08 if heavy else 0.03)
			if float(ev.get("quality", 0.0)) > 0.7:
				view.ambient.cheer(0.6)
		"hub_bucket":
			_on_bucket(ev)
		"hub_splash":
			Audio.sfx("prop_burst_brine", ev["pos"])
			vfx.emit("dust", ev["pos"], Vector3.UP, Color(0.75, 0.9, 1.0, 0.8), 1.5)
			vfx.ring(ev["pos"] + Vector3.UP * 0.05, 1.6, Color(0.8, 0.95, 1.0, 0.8), 0.6)
		"hub_land":
			Audio.sfx("land_heavy", ev["pos"], -4.0)
		"hub_pickup":
			Audio.sfx("grab", player().pos())
		"hub_throw":
			Audio.sfx("throw_release", player().pos())
			Audio.sfx("whoosh_heavy" if float(ev.get("charge", 0.0)) > 0.5 else "whoosh_light", player().pos())
		"hub_reveal":
			_on_reveal(ev)
		"hub_secret":
			_on_secret(ev)
		"hub_say":
			_on_say(ev)
		"hub_npc_hit":
			var npc := str(ev["npc"])
			var v := view.npc(npc)
			if v:
				v.flinch()
			npc_say(npc, HubContent.line(npc, "hit", int(_time * 10.0)))
		"hub_catch":
			vfx.word(ev["pos"] + Vector3.UP * 1.0, "GOTCHA!" if int(ev.get("clout", 0)) > 0 else "CAUGHT", Color("#8bd426"), 64)
			Audio.sfx("voice_scrapling_hurt", ev["pos"])
		"hub_fish":
			match str(ev["phase"]):
				"start":
					hud.subtitle("", "You cast off the pier. Stay put for 20 seconds...", 4.0)
				"catch":
					var cid := str(ev.get("cosmetic", ""))
					hud.banner("Reeled in", HubContent.cosmetic_name(cid) if cid != "" else "An old boot", "Saved to your locker." if cid != "" else "Nothing new on the line today.")
					Audio.ui("ui_purchase")
				"cancel":
					hud.subtitle("", "The line goes slack. You wandered off.", 2.5)
		"hub_reaction":
			vfx.word(ev["pos"] + Vector3.UP * 1.0, str(ev.get("name", "REACTION")).to_upper() + "!", Color(1, 0.7, 0.3), 72)
			vfx.emit("burst", ev["pos"], Vector3.UP, Color(1.0, 0.5, 0.2), 1.4)
		"hub_boiler":
			Audio.sfx("zone_steam", HubLayout.BOILER_POS + Vector3.UP, -6.0)
			vfx.emit("dust", HubLayout.BOILER_POS + Vector3(-1.6, 1.6, 0), Vector3.UP, Color(0.9, 0.9, 0.95, 0.6), 0.8)
		"hub_object_hit":
			Audio.sfx("hit_light", ev["pos"], -3.0)
			vfx.emit("spark", ev["pos"], Vector3.UP, Elements.color(str(ev["element"])) if str(ev["element"]) != "" else Color(1, 0.9, 0.6), 0.7)
		"hub_charge":
			Audio.sfx("charge_loop", player().pos(), -8.0)
		"taunt":
			if int(ev.get("fighter", -1)) == 0:
				view.ambient.cheer(0.4)


func _on_space(ev: Dictionary) -> void:
	var s := str(ev["space"])
	hud.set_space(s, view.tod)
	camera.set_space(s)
	_enter_room(s)
	if bool(ev.get("first", false)):
		var sd := HubLayout.space(s)
		hud.banner("New place", str(sd.get("name", s)), "Look for %s." % str(sd.get("landmark", "")), 2.4)
		if bool(ev.get("tour_done", false)) and s in HubLayout.TOUR and state.discovered().size() == HubLayout.TOUR.size():
			UiNav.toast("First tour done: the corkboard map's Fast walk is unlocked.", "success", 4.0)
	_last_space = s


func _enter_room(s: String) -> void:
	var room := str(HubLayout.space(s).get("room", "main"))
	Audio.set_room(room)
	# the Loading Dock's sound system plays the Walkout track once bought (HUB.md §6)
	if s == "loading_dock" and state.upgrade_level("meta_walkout") > 0 and radio_on:
		Audio.music("title_night", 1.2, {"diegetic": true})
	elif radio_on and Audio.music_track() != "cannery_radio":
		Audio.music("cannery_radio", 1.2, {"diegetic": true})


func _on_interact(ev: Dictionary) -> void:
	match str(ev["kind"]):
		"npc":
			open_board("talk", {"npc": str(ev["npc"])})
		"station":
			open_board("station", {"station": str(ev["station"])})
		"service":
			_service(str(ev["service"]))
		"object":
			_object(str(ev["id"]))


func _service(service: String) -> void:
	match service:
		"start_run":
			open_board("run")
		"sparring":
			open_board("spar")
		"bookie":
			if not services.open_bookie():
				npc_say("teddy", HubContent.keyed_line("teddy", "bookie_absent"))
		"ai_lab":
			if not services.open_lab():
				npc_say("teddy", HubContent.keyed_line("teddy", "lab_absent"))
		"map":
			open_board("map")
		"lockers":
			open_board("lockers")
		"records":
			open_board("records")
		"booth":
			open_board("booth")
		"rest_preview":
			open_board("rest")
		"rooftop_practice":
			HubSparring.launch(self, {"opponent": "kid_lamprey", "tier": "journeyman", "format": "practice", "arena": "rooftop"})


func _object(id: String) -> void:
	match id:
		"vending":
			Audio.sfx("land_soft", player().pos())
			hud.subtitle("", "CLUNK. A can of Glandco JUICE rolls out. The label says: \"Contents may contain contents.\"", 4.0)
		"radio":
			radio_on = not radio_on
			if radio_on:
				Audio.music("cannery_radio", 0.6, {"diegetic": true})
				npc_say("needles", HubContent.keyed_line("needles", "radio"))
			else:
				Audio.stop_music(0.6)
				hud.subtitle("", "Click. The Juice Bar goes quiet. Needles looks wounded.", 3.0)
		"elevator_gate":
			hud.subtitle("Ludlow", HubContent.keyed_line("ludlow", "parts_intro") + "  (%d of 3 parts)" % state.parts().size(), 5.0)
		"belt_case_locked":
			hud.subtitle("", "The belt case. Locked tight. Probably.", 3.0)
		"belt_case_open":
			hud.subtitle("", "The case stands open. The real belt is \"at the cleaners\".", 3.0)
		"trunk_empty":
			hud.subtitle("", "Mothballs and a pigeon feather. That's all that's left.", 3.0)


func _on_activity(ev: Dictionary) -> void:
	var act := str(ev["activity"])
	match str(ev["phase"]):
		"countdown":
			Audio.ui("ui_round_card")
			if act == "bag":
				npc_say("granny", HubContent.keyed_line("granny", "bag_start"))
		"start":
			Audio.sfx("ann_bell")
		"cancel":
			hud.banner("Challenge", "Called off", "Walk back over to start again.", 2.0)
		"end":
			Audio.sfx("ann_bell_triple")
			var r: Dictionary = ev["result"]
			match act:
				"bag":
					var tier := int(r["tier"])
					hud.banner("%s  ·  tier %d of 3" % [str((HubContent.activity("bags").get("bags", {}) as Dictionary).get(str(r["bag"]), {}).get("name", "Bag")), tier],
						"%d points" % int(r["score"]), _reward_text(r, "300 · 600 · 1000"), 4.0)
					npc_say("granny", HubContent.keyed_line("granny", ["bag_low", "bag_low", "bag_mid", "bag_high"][clampi(tier, 0, 3)]))
				"drill":
					hud.banner("Chum Cannon drill  ·  tier %d of 3" % int(r["tier"]), "Best streak %d" % int(r["streak"]),
						_reward_text(r, "15 · 30 · 50") + ("   Frame unlocked: Soaked!" if str(r.get("frame", "")) != "" else ""), 4.0)
				"crates":
					hud.banner("Crate Toss  ·  tier %d of 3" % int(r["tier"]), "%d points" % int(r["points"]),
						_reward_text(r, "30 · 60 · 100") + ("   Ludlow wants a word about the gulls..." if bool(r.get("jitters_hint", false)) else ""), 4.0)
			if int(r.get("tier", 0)) >= 2:
				view.ambient.cheer(1.0)


func _reward_text(r: Dictionary, tiers: String) -> String:
	if int(r.get("clout", 0)) > 0:
		return "New tier! +%d Clout." % int(r["clout"])
	if bool(r.get("cancelled", false)):
		return ""
	return "Tiers: %s (Clout once per tier)." % tiers


func _on_bucket(ev: Dictionary) -> void:
	var p: Vector3 = ev["pos"]
	match str(ev["phase"]):
		"fire":
			Audio.sfx("charge_release", p, -2.0)
			vfx.emit("dust", p, Vector3.LEFT, Color(0.9, 0.9, 0.9, 0.5), 0.6)
		"hit":
			Audio.sfx("el_hit_brine", p)
			vfx.emit("dust", p, Vector3.UP, Color(0.55, 0.45, 0.35, 0.9), 1.2)
			camera.add_trauma(0.15)
			vfx.word(p + Vector3.UP * 0.4, "SPLAT! %d" % int(ev.get("drill_hp", 0)), Color("#ff8a80"), 44)
		"parry":
			Audio.sfx("parry", p)
			vfx.ring(p, 1.0, Color(1.0, 0.9, 0.5, 0.9), 0.3, false)
			vfx.word(p + Vector3.UP * 0.4, "POP! +5", Color("#ffd166"), 52)
		"block":
			Audio.sfx("hit_guard", p)
			vfx.emit("spark", p, Vector3.UP, Color(0.6, 0.85, 1.0), 0.6)
		"miss", "splat":
			Audio.sfx("prop_burst_brine", p, -6.0)
			vfx.emit("dust", p, Vector3.UP, Color(0.5, 0.42, 0.33, 0.7), 0.8)


func _on_reveal(ev: Dictionary) -> void:
	view.props.refresh_world()
	match str(ev["what"]):
		"panel":
			Audio.sfx("prop_break_wood", ev["pos"])
			vfx.word(ev["pos"] + Vector3.UP, "CREAK...", Color(0.9, 0.85, 0.7), 48)
		"scrapling":
			Audio.sfx("voice_scrapling_idle", ev["pos"])
			hud.banner("Under the stairs", "Something woke up!", "Grab it before it reaches the roller door!", 2.5)
		"pier_ladder":
			view.ambient.scare_gulls()
			Audio.sfx("flap", ev["pos"])
		"sign":
			Audio.sfx("hazard_plate_live", ev["pos"])
			vfx.ring(ev["pos"], 2.0, Color(1.0, 0.4, 0.8, 0.9), 0.6, false)
		"frost":
			hud.banner("Ice bath", "Something at the bottom", "Reach down: press the interact button.", 3.0)
		"belt_case":
			Audio.sfx("ui_notify")
		"trunk":
			hud.banner("Old steamer trunk", HubContent.cosmetic_name(str(ev.get("cosmetic", ""))), "Saved to your locker.")


func _on_secret(ev: Dictionary) -> void:
	var id := str(ev["id"])
	var d := HubContent.secret(id)
	hud.banner("Secret found  %d / 10" % int(ev.get("count", 0)), str(d.get("name", id)), str(d.get("reward", "")), 4.5)
	Audio.sting("victory")
	Platform.unlock_achievement("ach_confidant")
	view.ambient.cheer(1.0)
	view.props.refresh_world()
	view.upgrades.refresh()
	Profiles.save()
	state.dirty = false


func _on_say(ev: Dictionary) -> void:
	var npc := str(ev["npc"])
	var key := str(ev.get("key", ""))
	var text := ""
	if key.begins_with("line:"):
		text = HubContent.keyed_line(npc, key.substr(5))
	elif key.begins_with("text:"):
		text = key.substr(5)
	var vars: Dictionary = ev.get("vars", {})
	text = HubContent.fill(text, vars)
	if text != "":
		npc_say(npc, text)


func _on_state_changed(kind: String, data: Dictionary) -> void:
	match kind:
		"clout":
			hud.clout_gain(int(data.get("amount", 0)), str(data.get("reason", "")))
		"upgrade":
			view.upgrades.refresh()
			view.props.refresh_world()
		"cosmetic":
			if str(data.get("id", "")) == "hub_pet_blister":
				state.equip("pet", "hub_pet_blister")
		"loadout":
			pass


## An NPC speaks: a bubble over their head plus their voice (babble for speakers with a grain bank).
func npc_say(npc: String, text: String, seconds := 4.0) -> void:
	if text == "":
		return
	var v := view.npc(npc)
	if v:
		v.say(text, seconds)
	var d := HubContent.npc(npc)
	_suppress_sub = v != null and v.global_position.distance_to(player().pos()) < 14.0
	Audio.say(str(d.get("speaker", npc)), text, 40)
	_suppress_sub = false
	if v == null or v.global_position.distance_to(player().pos()) >= 14.0:
		hud.subtitle(HubContent.npc_name(npc), text, seconds)


func _on_subtitle(speaker: String, text: String, seconds: float) -> void:
	if _suppress_sub:
		return
	# announcer lines from the fight bridge (rare in the hub) and PA calls
	hud.subtitle(speaker.capitalize(), text, seconds)


## Ambient barks: NPCs you walk past say something (their run reaction the first time this visit).
func _barks() -> void:
	if App.top_screen() != null or _time - _last_bark < BARK_GLOBAL:
		return
	var pp := player().pos()
	for key in HubLayout.NPC_SPOTS:
		var v := view.npc(str(key))
		if v == null:
			continue
		if v.global_position.distance_to(pp) > BARK_RANGE or absf(v.global_position.y - (pp.y - player().rig.hover_height)) > 2.0:
			continue
		if _time - float(_bark_t.get(key, -99.0)) < BARK_COOLDOWN:
			continue
		_bark_t[key] = _time
		_last_bark = _time
		var text := ""
		if not _greeted.has(key):
			_greeted[key] = true
			text = HubContent.run_line(str(key), state, int(_time))
		if text == "":
			text = HubContent.fill(HubContent.line(str(key), "barks", int(_time * 3.0) + state.secrets_found()), HubContent.run_context(state))
		npc_say(str(key), text)
		return


func _welcome() -> void:
	var from := str(params.get("from", ""))
	match from:
		"spar":
			var res: Dictionary = params.get("spar", {})
			var won := bool(res.get("won", false))
			if str(res.get("opponent", "")) == "kid_lamprey":
				get_tree().create_timer(1.0).timeout.connect(func() -> void:
					npc_say("kid", HubContent.keyed_line("kid", "after_loss_kid" if won else "after_win_kid")))
			var bits := []
			if int(res.get("clout", 0)) > 0:
				bits.append("+%d Clout" % int(res["clout"]))
			if str(res.get("badge", "")) != "":
				bits.append("Headliner badge earned")
			hud.banner("Ring sparring", "You won" if won else "Back to work", "   ".join(PackedStringArray(bits)), 3.0)
			if won:
				view.ambient.cheer(1.0)
		"tutorial":
			hud.banner("Granny's corner", "Lesson over", "Hands up. Chin down.", 2.4)
		"tape":
			hud.banner("Broadcast Booth", "That was 1973", "The Vintage Bellows line pack is yours.", 3.0)
		"bookie":
			hud.banner("Boiler Room", "Back from the table", "", 2.4)
			get_tree().create_timer(0.8).timeout.connect(func() -> void: npc_say("teddy", HubContent.keyed_line("teddy", "bookie_back")))
		_:
			var tod := str({"morning": "Morning shift", "evening": "Evening session", "night": "After hours"}.get(view.tod, ""))
			hud.banner(str(tod), "The Cannery", "Fight Camp's home. Talk, train, spend Clout, find what's hidden.", 3.2)
