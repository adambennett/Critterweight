class_name UiDevFlags
extends RefCounted
## Development / QA command-line flags, handled by the title screen during a normal boot (main.gd
## always opens "title" first). They never change saved data unless stated.
##   --ui-screen <name>        open a screen directly (with realistic params; see open_screen())
##                             extra names: practice, countdown, match, gallery, results (runs a
##                             short real bot match), pause (starts a match, then pauses it)
##   --ui-tab <id>             settings: start on this tab (display, graphics, audio, input, ...)
##   --ui-device <gamepad|keyboard>   force the prompt glyph family for captures
##   --ui-prompts <xbox|playstation>  force pad glyph style (not persisted)
##   --ui-seed-window <WxH|borderless> persist windowed WxH (or borderless) display settings into
##                             the ACTIVE user root (use with --user-root <dir>), then quit
##   --ui-screen online [--ui-tab host|join|lan] [--ui-recent]   --ui-recent writes two demo
##                             entries into the ACTIVE user root's recent-server list
##   --ui-screen lobby [--ui-port p] [--ui-bots n] [--ui-guests n]   hosts a real session (no LAN
##                             beacons); --ui-guests adds up to 3 scripted guests in this process
## Example (1280x800 evidence capture, isolated user data):
##   godot --path game -- --user-root <tmp> --ui-seed-window 1280x800   (headless ok)
##   godot --path game -- --user-root <tmp> --ui-screen settings --capture out.png --capture-at 3

static func arg(flag: String, fallback := "") -> String:
	var args := OS.get_cmdline_user_args()
	var i := args.find(flag)
	if i >= 0 and i + 1 < args.size() and not args[i + 1].begins_with("--"):
		return args[i + 1]
	return fallback


static func has(flag: String) -> bool:
	return OS.get_cmdline_user_args().has(flag)


## --ui-demo-net (evidence captures): the Online/Lobby screens SHOW this private example address
## instead of the machine's real ones (what is copied or sent never changes).
const DEMO_ADDRESS := "192.168.1.24"


static func shown_addresses(real: Array[String]) -> Array[String]:
	if has("--ui-demo-net"):
		var out: Array[String] = [DEMO_ADDRESS]
		return out
	return real


static func shown_address(real: String) -> String:
	return DEMO_ADDRESS if has("--ui-demo-net") else real


## "" = the real address (Net.invite_text picks it), or the demo one under --ui-demo-net.
static func shown_invite_address() -> String:
	return DEMO_ADDRESS if has("--ui-demo-net") else ""


## Returns true when a flag took over the boot (the title screen then stays idle).
static func handle() -> bool:
	if has("--ui-seed-window"):
		_seed_window(arg("--ui-seed-window", "1920x1080"))
		return true
	var device := arg("--ui-device", "")
	if device != "":
		Controls.last_device = device
		Controls.device_changed.emit(device)
	var style := arg("--ui-prompts", "")
	if style != "":
		Settings.set_value("input.prompts", style, true, false)
	if has("--ui-toasts"):
		var tt := (Engine.get_main_loop() as SceneTree).create_timer(1.2)
		tt.timeout.connect(func() -> void:
			UiNav.toast("Settings saved.", "info", 8.0)
			UiNav.toast("Profile Rookie created.", "success", 8.0)
			UiNav.toast("Controller disconnected.", "warning", 8.0)
			UiNav.toast("Could not write settings.json (disk full?).", "error", 8.0))
	var screen := arg("--ui-screen", "")
	if screen == "" or screen == "title":
		return false
	# open on the next frame (we are inside App.goto("title") right now)
	(Engine.get_main_loop() as SceneTree).process_frame.connect(func() -> void: open_screen(screen), CONNECT_ONE_SHOT)
	return true


static func _seed_window(spec: String) -> void:
	if spec == "borderless":
		Settings.set_value("display.window_mode", "borderless", false)
	else:
		Settings.set_value("display.window_mode", "windowed", false)
		Settings.set_value("display.resolution", spec, false)
	Settings.set_value("access.reduce_motion", false, false)
	print("UI seed: display set to %s in %s" % [spec, Paths.root])
	(Engine.get_main_loop() as SceneTree).quit(0)


static func open_screen(screen: String) -> void:
	match screen:
		"main_menu":
			var mm := App.goto("main_menu")
			var cat := arg("--ui-open", "")
			if cat != "" and mm != null and mm.has_method("open_category"):
				# after the screen's own deferred focus restore, so the sub-menu keeps focus
				(Engine.get_main_loop() as SceneTree).process_frame.connect(func() -> void: mm.call("open_category", cat), CONNECT_ONE_SHOT)
		"settings":
			App.goto("main_menu")
			App.push("settings", {"tab": arg("--ui-tab", "display")})
		"practice":
			App.goto("main_menu")
			App.push("versus_setup", {"mode": "practice"})
		"versus_setup":
			App.goto("main_menu")
			App.push("versus_setup", {"mode": "versus", "fighters": int(arg("--ui-fighters", "2"))})
		"character_select":
			App.goto("main_menu")
			App.push("character_select", {"mode": "quick"})
		"dialog":
			App.goto("main_menu")
			App.dialog("Reset Audio settings?", "Every Audio option returns to its default value. Your other settings are not touched.",
				[{"label": "Reset", "id": "reset", "danger": true}, {"label": "Cancel", "id": "cancel", "cancel": true}])
		"countdown":
			App.goto("main_menu")
			App.push("settings", {"tab": "display"})
			App.push("dialog", {"title": "Keep these display settings?", "body": "Window mode: Windowed. Reverting automatically in {s} seconds.",
				"buttons": [{"label": "Keep", "id": "keep"}, {"label": "Revert", "id": "revert", "cancel": true}],
				"countdown": 15.0, "timeout_choice": "revert"})
		"text_entry":
			App.goto("main_menu")
			App.push("text_entry", {"title": "Player name", "value": "Rookie", "max_len": 20, "callback": func(_ok: bool, _t: String) -> void: pass})
		"pause":
			_start_sample_match(false)
			var t := (Engine.get_main_loop() as SceneTree).create_timer(2.4)
			t.timeout.connect(func() -> void: MatchFlow.open_pause())
		"ingame_settings":
			_start_sample_match(false)
			var t2 := (Engine.get_main_loop() as SceneTree).create_timer(2.4)
			t2.timeout.connect(func() -> void:
				MatchFlow.open_pause()
				App.push("settings", {"in_game": true, "tab": arg("--ui-tab", "accessibility")}))
		"match":
			_start_sample_match(true)
		"results":
			var cfg := _sample_config(true)
			cfg["rules"] = {"id": "dev_short", "name": "Short round", "mode": "standard", "rounds": 1, "round_time": 7, "lives": 1}
			MatchFlow.launch(cfg)
		"gallery":
			App.goto("ui_gallery")
		"online":
			App.goto("main_menu")
			if has("--ui-recent"):
				# evidence captures: two demo entries in the ACTIVE user root's recent-server list
				Net.remember_server("play.example.net", 7777, "Gullet Nights (dedicated)", true)
				Net.remember_server("192.168.1.24", 7777, "Rookie's session")
			App.push("online", {"tab": arg("--ui-tab", "host")})
		"lobby":
			# hosts a real session (no LAN beacons) so the lobby has something to show;
			# --ui-port <p>, --ui-bots <n>
			App.goto("main_menu")
			App.push("online")
			var cfg := {"lan_discovery": false, "bots": int(arg("--ui-bots", "0")), "creature": OnlineScreen.default_creature()}
			if arg("--ui-port", "") != "":
				cfg["port"] = int(arg("--ui-port", "7777"))
			if Net.host(cfg) == OK:
				OnlineFlow.begin()
				App.push("lobby")
				# --ui-guests <n>: scripted guests in this process (evidence captures), each with a
				# fighter, cosmetics and ready - they are real clients of the hosted session
				for i in clampi(int(arg("--ui-guests", "0")), 0, 3):
					_demo_guest(i, int(Net.server.cfg["port"]))

		_:
			if not App.has_screen(screen):
				Log.e("ui", "--ui-screen: unknown screen '%s'" % screen)
				App.goto("main_menu")
				return
			App.goto("main_menu")
			App.push(screen, {"tab": arg("--ui-tab", "")} if arg("--ui-tab", "") != "" else {})


## A real NetClient in this process that joins the hosted session as a guest (dev captures only).
static func _demo_guest(i: int, port: int) -> void:
	var names := ["Ann", "Bo", "Cy"]
	var c := NetClient.new()
	c.present = false
	c.install_scene = false
	c.name = "DemoGuest%d" % i
	Net.add_child(c)
	c.connect_to_server("127.0.0.1", port, {"name": names[i], "timeout_s": 10})
	var ids := Content.playable_creatures().filter(func(x): return not str(x).begins_with("dev_"))
	c.admitted.connect(func(_w: Dictionary) -> void:
		if not ids.is_empty():
			c.send_lobby(NetProtocol.LQ_CREATURE, str(ids[(i + 1) % ids.size()]))
		var looks := [{"piece": "hub_gold_tooth", "frame": "hub_frame_soaked", "juice": "hub_juice_sizzle"},
			{"back": "hub_replica_belt", "frame": "hub_frame_sign_fixer"}, {}]
		c.send_lobby(NetProtocol.LQ_COSMETICS, looks[i % looks.size()])
		c.send_lobby(NetProtocol.LQ_READY, i != 1))


static func _sample_config(spectate: bool) -> Dictionary:
	var ids := Content.playable_creatures()
	var c0 := str(ids[0]) if not ids.is_empty() else "dev_biped"
	var c1 := str(ids[1 % ids.size()]) if not ids.is_empty() else "dev_biped"
	var n0 := Profiles.player_name() if not spectate else str(Content.get_entry("creatures", c0).get("name", "Bot"))
	var n1 := str(Content.get_entry("creatures", c1).get("name", "Bot"))
	if n1 == n0:
		n1 += " II"
	return {"arena": "the_gullet", "rules": "duel", "spectate": spectate,
		"fighters": [{"creature": c0, "team": 0, "kind": "bot" if spectate else "player", "difficulty": BotTiers.brain_tier("contender"), "name": n0},
			{"creature": c1, "team": 1, "kind": "bot", "difficulty": BotTiers.brain_tier("journeyman"), "name": n1}],
		"ui": {"mode": "spectate" if spectate else "quick"}}


static func _start_sample_match(spectate: bool) -> void:
	MatchFlow.launch(_sample_config(spectate))
