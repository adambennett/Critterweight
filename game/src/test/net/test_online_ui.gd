extends TestCase
## NET-01/05/07, UI-09 (LOOPBACK): the Online and Lobby screens driven like a player - controller
## and keyboard events through the engine's input pipeline, focus checked after every step:
## tabs, back, hosting through the Online screen, the lobby with a real guest, starting a match,
## the online results card, the automatic return to the lobby, leaving; error dialogs for a
## refused join (wrong password, full session, timeout) and for being kicked; joining a host
## running in ANOTHER process through the Join tab (recent server); layout at 1280x800 and
## 1920x1080. Everything runs over 127.0.0.1 on this machine.

const U := preload("res://src/test/net/net_test_util.gd")

var _nodes: Array = []
var _saved := {}
var u = null


## Holds this process to real time (at most `fps` frames per real second) while it plays against a
## host in another, real-time process: the suite runs with --fixed-fps, where frames - and so the
## client's input packets - outrun the clock and the host rightly kicks for an input flood.
## Engine.max_fps does not apply under --fixed-fps, hence the explicit wait.
class RealTimePacer extends Node:
	var fps := 120.0
	var _last_us := 0

	func _ready() -> void:
		process_priority = -1000
		process_mode = Node.PROCESS_MODE_ALWAYS
		_last_us = Time.get_ticks_usec()

	func _process(_delta: float) -> void:
		var next := _last_us + int(1000000.0 / fps)
		var now := Time.get_ticks_usec()
		if now < next:
			OS.delay_usec(next - now)
		_last_us = maxi(Time.get_ticks_usec(), next)


func before_each() -> void:
	_saved = Settings.values.duplicate(true)
	Settings.set_value("network.lan_discovery", false, true, false)
	Settings.set_value("network.timeout", 5, true, false)
	App.clear_screens()


func after_each() -> void:
	OnlineFlow.end()
	if Net.is_session_active():
		Net.leave()
	for n in _nodes:
		if is_instance_valid(n):
			if n is NetServer and (n as NetServer).is_running():
				(n as NetServer).close(NetProtocol.R_SHUTDOWN, "", false, 50)
			n.queue_free()
	_nodes.clear()
	if u:
		u.kill_all()
	u = null
	App.clear_screens()
	if App.current_scene != null:
		App.set_scene(null)
	MatchFlow.set_paused(false)
	for k in _saved:
		Settings.values[k] = _saved[k]
	Settings.apply_all()


# --- helpers ---------------------------------------------------------------------------------

func _port() -> int:
	var seq := int(Engine.get_meta("online_ui_port_seq", 0)) + 1
	Engine.set_meta("online_ui_port_seq", seq)
	return 36000 + (OS.get_process_id() % 400) * 24 + (seq % 12) * 2


func press_joy(button: JoyButton, settle := 2) -> void:
	for down in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.device = 0
		ev.button_index = button
		ev.pressed = down
		ev.pressure = 1.0 if down else 0.0
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await wait_frames(1 if down else settle)


func focus() -> Control:
	return get_viewport().gui_get_focus_owner()


func top_name() -> String:
	var t := App.top_screen()
	return t.screen_name if t != null else "none"


func expect_focus(step: String) -> bool:
	var top := App.top_screen()
	var f := focus()
	var ok := top != null and f != null and is_instance_valid(f) and top.is_ancestor_of(f) and f.is_visible_in_tree()
	return check(ok, "focus lost after '%s' (top=%s, focus=%s)" % [step, top_name(), str(f.get_path()) if f != null else "none"])


func focus_key() -> String:
	var f := focus()
	return str(f.get_meta("focus_key")) if f != null and f.has_meta("focus_key") else ""


## Presses down until the focused control has `key` (focus checked after every press).
func nav_to(key: String, max_steps := 40) -> bool:
	for i in max_steps:
		if focus_key() == key:
			return true
		await press_joy(JOY_BUTTON_DPAD_DOWN)
		expect_focus("navigate to %s (%d)" % [key, i])
	return check(focus_key() == key, "reached '%s' (focus on '%s')" % [key, focus_key()])


func until(pred: Callable, timeout_s: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < end:
		if pred.call():
			return true
		await wait_frames(2)
	return bool(pred.call())


func find_label(root: Node, text: String) -> Label:
	if root == null:
		return null
	for l in root.find_children("*", "Label", true, false):
		if (l as Label).text.contains(text) and (l as Label).is_visible_in_tree():
			return l as Label
	return null


func toast_has(text: String) -> bool:
	if UiNav.instance == null:
		return false
	for e in UiNav.instance.toasts.history:
		if str((e as Dictionary)["text"]).contains(text):
			return true
	return false


func open_online(tab := "host") -> Screen:
	App.goto("main_menu")
	await wait_frames(3)
	App.push("online", {"tab": tab})
	await wait_frames(4)
	return App.top_screen()


func guest(port: int, opts: Dictionary) -> NetClient:
	var c := NetClient.new()
	c.present = false
	c.install_scene = false
	add_child(c)
	_nodes.append(c)
	var o := {"timeout_s": 5}
	o.merge(opts, true)
	c.connect_to_server("127.0.0.1", port, o)
	return c


# --- tests -----------------------------------------------------------------------------------

## The main menu offers Online; the screen opens focused; LB/RB walk HOST -> JOIN -> LAN and back
## with focus inside every tab; B returns to the main menu.
func test_online_screen_tabs_focus_and_back() -> void:
	await wait_frames(2)
	App.goto("main_menu")
	await wait_frames(4)
	var mm := App.top_screen()
	var online_btn := false
	for b in mm.find_children("*", "UiButton", true, false):
		if (b as UiButton).route == "online" or (b as UiButton).text.to_lower().contains("online"):
			online_btn = true
	check(online_btn, "the main menu shows Online now that the screen exists")
	var s := await open_online()
	check_eq(top_name(), "online", "online opens")
	expect_focus("open online")
	check_eq((s as OnlineScreen).tab(), "host", "starts on HOST")
	check(find_label(s, "Not connected") != null, "the connection panel says not connected")
	for want in ["join", "lan", "host"]:
		await press_joy(JOY_BUTTON_RIGHT_SHOULDER, 4)
		check_eq((s as OnlineScreen).tab(), want, "RB moves to %s" % want)
		expect_focus("tab %s" % want)
		await press_joy(JOY_BUTTON_DPAD_DOWN)
		expect_focus("navigate in %s" % want)
	await press_joy(JOY_BUTTON_LEFT_SHOULDER, 4)
	check_eq((s as OnlineScreen).tab(), "lan", "LB goes back")
	check(find_label(s, "LAN discovery is off") != null, "with discovery off the LAN tab says so and offers to turn it on")
	await press_joy(JOY_BUTTON_B, 4)
	check_eq(top_name(), "main_menu", "B returns to the main menu")
	expect_focus("back from online")


## Host through the Online screen, a real guest joins, start the match from the lobby (Y), the
## online results card, the automatic return to the lobby, leave with the confirmation.
func test_host_lobby_match_and_back_to_lobby() -> void:
	await wait_frames(2)
	var port := _port()
	Settings.set_value("network.port", port, true, false)
	var s := await open_online("host")
	check(await nav_to("host"), "reached Host session")
	await press_joy(JOY_BUTTON_A, 6)
	check(await until(func() -> bool: return top_name() == "lobby", 4.0), "hosting opens the lobby (top=%s)" % top_name())
	check(Net.is_host(), "the session is hosted")
	expect_focus("lobby opened")
	var lob := App.top_screen()
	check(find_label(lob, "HOST") != null and find_label(lob, "YOU") != null, "the host's own row is shown")
	var hl := find_label(lob, "Your fighter:")
	check(hl != null and hl.size.y >= 20.0, "the help line under the list describes the focused row (%s)" % (str(hl.size) if hl else "missing"))
	var g := guest(port, {"name": "Guesty"})
	check(await until(func() -> bool: return g.state == NetClient.State.LOBBY, 6.0), "a guest joins")
	check(await until(func() -> bool: return find_label(App.top_screen(), "GUESTY") != null, 3.0), "the guest's name card appears")
	# copy invite (host only)
	check(await nav_to("invite"), "reached Copy invite")
	await press_joy(JOY_BUTTON_A, 4)
	check(toast_has("Invite copied"), "copy invite confirms with a toast")
	# rules explained
	check(await nav_to("explain"), "reached the rules explanation")
	await press_joy(JOY_BUTTON_A, 4)
	check_eq(top_name(), "dialog", "the explanation opens")
	check(find_label(App.top_screen(), "never pause") != null, "it explains the online restrictions")
	await press_joy(JOY_BUTTON_B, 4)
	check_eq(top_name(), "lobby", "B closes it")
	expect_focus("after the explanation")
	# a short match, then results come back quickly
	check_eq(Net.host_set("rules_override", {"rounds": 1, "round_time": 6, "sudden_death": false}), "", "short rules for the test (a draw at the bell)")
	Net.server.cfg["results_time"] = 2
	await press_joy(JOY_BUTTON_Y, 4)
	check(await until(func() -> bool: return App.current_scene is MatchScene, 4.0), "Y starts the match")
	check(await until(func() -> bool: return top_name() == "results", 30.0), "the online results card shows")
	if top_name() == "results":
		check(find_label(App.top_screen(), "Back to the lobby in") != null, "it says the lobby comes back by itself")
		expect_focus("results")
	check(await until(func() -> bool: return top_name() == "lobby", 12.0), "the lobby comes back after the results (top=%s)" % top_name())
	expect_focus("back in the lobby")
	# leave: B asks first
	await press_joy(JOY_BUTTON_B, 4)
	check_eq(top_name(), "dialog", "B asks before leaving")
	await press_joy(JOY_BUTTON_A, 6)
	check(await until(func() -> bool: return not Net.is_session_active(), 3.0), "leaving closes the session")
	check_eq(top_name(), "online", "back on the Online screen")
	expect_focus("after leaving")


## Joining a host in ANOTHER process through the Join tab (its recent-server entry), readying
## with Y, playing the match the host starts, and being returned to the lobby.
func test_join_other_process_through_screens() -> void:
	await wait_frames(2)
	# this process is the client: real-time frames, or the host (real time, other process) sees an
	# input flood (the suite runs with --fixed-fps, where frames outrun the clock)
	var pacer := RealTimePacer.new()
	add_child(pacer)
	_nodes.append(pacer)
	u = U.new(self, "online_ui_join")
	var port: int = u.base_port
	var host: int = u.spawn("host", ["--net-client", "--net-host", "--port", port, "--name", "Hosty", "--script", "aggressive",
		"--creature", "f_stoke", "--host-start-after-players", "2", "--rules", "duel", "--rounds", "1", "--round-time", "8",
		"--no-sudden-death", "--results-time", "3",
		"--host-auto-start-limit", "1", "--host-start-when-ready", "--quit-after", "90", "--result", u.result_path("Hosty")])
	var r0: Dictionary = await u.wait_json(u.result_path("Hosty"), func(d: Dictionary) -> bool: return bool(d.get("connected", false)), U.SERVER_READY_S)
	check(bool(r0.get("connected", false)), "the host process is up")
	Net.remember_server("127.0.0.1", port, "Hosty's session")
	var s := await open_online("join")
	check_eq((s as OnlineScreen).tab(), "join", "on the Join tab")
	check(await nav_to("recent:127.0.0.1:%d" % port), "the recent server is listed")
	await press_joy(JOY_BUTTON_A, 4)
	check(await until(func() -> bool: return top_name() == "lobby", 10.0), "joining opens the lobby (top=%s)" % top_name())
	expect_focus("joined lobby")
	check(Net.is_client(), "connected as a client")
	check(await until(func() -> bool: return App.top_screen() is LobbyScreen and not (App.top_screen() as LobbyScreen).me().is_empty(), 5.0),
		"the lobby lists this player")
	await press_joy(JOY_BUTTON_Y, 4)
	check(await until(func() -> bool: return bool((App.top_screen() as LobbyScreen).me().get("ready", false)) if App.top_screen() is LobbyScreen else false, 3.0) \
		or App.current_scene is NetMatchScene, "Y readies up")
	check(await until(func() -> bool: return App.current_scene is NetMatchScene, 15.0), "the host's match starts here (NetMatchScene)")
	check(await until(func() -> bool: return top_name() == "results", 30.0), "the online results card shows")
	check(await until(func() -> bool: return top_name() == "lobby", 15.0), "back in the lobby after the results (top=%s)" % top_name())
	expect_focus("back in the lobby")
	# leaving through the lobby (B, confirm)
	await press_joy(JOY_BUTTON_B, 4)
	await press_joy(JOY_BUTTON_A, 6)
	check(await until(func() -> bool: return not Net.is_session_active(), 3.0), "left the session")
	check_eq(top_name(), "online", "back on the Online screen")
	check(Net.recent_servers().any(func(e: Dictionary) -> bool: return int(e["port"]) == port), "the server stays in the recent list")


## Refused joins explain themselves in a dialog: wrong password, full session, nobody answering;
## and a kicked player lands on the Online screen with the reason.
func test_join_errors_and_kick_show_reasons() -> void:
	await wait_frames(2)
	var port := _port()
	var srv := NetServer.new()
	add_child(srv)
	_nodes.append(srv)
	check_eq(srv.start({"name": "Locked", "port": port, "lan_discovery": false, "password": "sesame", "max_players": 1,
		"max_spectators": 0, "timeout": 5, "rejoin_grace": 5, "kick_ban_seconds": 2}, true), OK, "a locked server")
	var pl := NetPlaylist.from_dict({"id": "t", "name": "T", "entries": [{"rules": "duel", "arena": "the_gullet", "weight": 1}]}, "test")
	pl.validate()
	srv.set_playlist(pl)
	var s := await open_online("join") as OnlineScreen
	s.join_server("127.0.0.1", port, "wrong")
	check(await until(func() -> bool: return top_name() == "dialog", 8.0), "a wrong password opens a dialog")
	check(find_label(App.top_screen(), "assword") != null, "it names the password problem")
	await press_joy(JOY_BUTTON_A, 4)
	check_eq(top_name(), "online", "OK returns to the Online screen")
	expect_focus("after the password dialog")
	# a different game version (refused on this side before anything else): both versions shown
	OnlineFlow.begin()
	check_eq(Net.join("127.0.0.1", port, "sesame", {"test_game_version": "9.9.9"}), OK, "joining with another game version")
	check(await until(func() -> bool: return top_name() == "dialog", 8.0), "a version mismatch opens a dialog")
	check(find_label(App.top_screen(), "9.9.9") != null and find_label(App.top_screen(), NetProtocol.game_version()) != null,
		"it shows both game versions")
	await press_joy(JOY_BUTTON_A, 4)
	check_eq(top_name(), "online", "OK returns to the Online screen")
	# full: one player already in
	var first := guest(port, {"name": "First", "password": "sesame"})
	check(await until(func() -> bool: return first.state == NetClient.State.LOBBY, 6.0), "someone takes the only place")
	s.join_server("127.0.0.1", port, "sesame")
	check(await until(func() -> bool: return top_name() == "dialog", 8.0), "a full session opens a dialog")
	check(find_label(App.top_screen(), "full") != null or find_label(App.top_screen(), "Full") != null, "it says the session is full")
	await press_joy(JOY_BUTTON_A, 4)
	# nobody answering at all
	s.join_server("127.0.0.1", _port(), "")
	check(find_label(App.top_screen(), "Connecting") != null, "the connection panel shows the attempt")
	check(await until(func() -> bool: return top_name() == "dialog", 12.0), "no answer ends in a dialog")
	check(find_label(App.top_screen(), "Could not reach") != null, "it says nobody answered")
	await press_joy(JOY_BUTTON_A, 4)
	expect_focus("after the timeout dialog")
	# kicked from a session joined through the screen
	first.leave()
	await wait_frames(10)
	s.join_server("127.0.0.1", port, "sesame")
	check(await until(func() -> bool: return top_name() == "lobby", 8.0), "joined (top=%s)" % top_name())
	srv.kick(Net.local_peer_id(), "testing kicks")
	check(await until(func() -> bool: return top_name() == "dialog", 8.0), "a kick opens a dialog")
	check(find_label(App.top_screen(), "testing kicks") != null, "with the host's reason")
	await press_joy(JOY_BUTTON_A, 4)
	check_eq(top_name(), "online", "and leaves the player on the Online screen")
	expect_focus("after the kick")


## LAN tab (same machine): an announced session is listed with its name, rules and players and a
## lock when it has a password; choosing it asks for the password on the on-screen keyboard.
func test_lan_tab_lists_sessions_and_asks_for_password() -> void:
	await wait_frames(2)
	Settings.set_value("network.lan_discovery", true, true, false)
	var port := _port()
	var dport := port + 1          # a private discovery port: other game instances on this PC keep 7779
	var srv := NetServer.new()
	add_child(srv)
	_nodes.append(srv)
	check_eq(srv.start({"name": "Basement Cage", "port": port, "lan_discovery": true, "discovery_port": dport, "password": "sesame",
		"max_players": 4, "timeout": 5}, true), OK, "a password-protected server announcing on the LAN")
	check_eq(Net.start_lan_discovery(dport), OK, "the browser listens on the test's discovery port")
	var s := await open_online("lan")
	check_eq((s as OnlineScreen).tab(), "lan", "on the LAN tab")
	var entry: UiButton = null
	var finder := func() -> bool:
		for b in App.top_screen().find_children("*", "UiButton", true, false):
			if (b as UiButton).text.contains("Basement Cage"):
				entry = b
				return true
		return false
	check(await until(finder, 6.0), "the session is listed")
	if entry == null:
		return
	check(entry.text.contains("0/4 players"), "with its player count (%s)" % entry.text)
	check(await nav_to(str(entry.get_meta("focus_key"))), "the entry takes focus")
	check(find_label(App.top_screen(), "Joins this session") != null, "the help says what A does")
	await press_joy(JOY_BUTTON_A, 4)
	check_eq(top_name(), "text_entry", "a locked session asks for the password first")
	await press_joy(JOY_BUTTON_B, 4)
	check_eq(top_name(), "online", "B cancels back to the list")
	expect_focus("after cancelling the password")
	Net.stop_lan_discovery()


## UI-10 at 1280x800 and 1920x1080: the footer prompts stay on screen and no text is under 18 px
## on the Online screen (every tab) and on a host's lobby with a guest.
func test_online_layout_fits_and_text_is_readable() -> void:
	await wait_frames(2)
	var root := get_tree().root
	var old := root.size
	var port := _port()
	Settings.set_value("network.port", port, true, false)
	for res in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = res
		await wait_frames(3)
		var vr := get_viewport().get_visible_rect()
		var px_per_du := get_viewport().get_final_transform().get_scale().y
		var s := await open_online("host")
		for t in ["host", "join", "lan"]:
			(s as OnlineScreen)._tabs.select(OnlineScreen.TABS.find(t))
			await wait_frames(3)
			_audit(App.top_screen(), "online/%s@%dx%d" % [t, res.x, res.y], vr, px_per_du)
		check_eq(Net.host({"port": port, "lan_discovery": false}), OK, "host for the lobby layout")
		OnlineFlow.begin()
		var g := guest(port, {"name": "Layout Guest"})
		App.push("lobby")
		await until(func() -> bool: return g.state == NetClient.State.LOBBY, 5.0)
		await wait_frames(40)
		_audit(App.top_screen(), "lobby@%dx%d" % [res.x, res.y], vr, px_per_du)
		OnlineFlow.end()
		Net.leave()
		g.leave()
		App.clear_screens()
		await wait_frames(6)
	root.size = old
	await wait_frames(2)


func _audit(s: Screen, tag: String, vr: Rect2, px_per_du: float) -> void:
	if not check(s != null, "%s: screen open" % tag):
		return
	var bars := 0
	for b in s.find_children("*", "PromptBar", true, false):
		var bar := b as Control
		if not bar.is_visible_in_tree():
			continue
		bars += 1
		var r := bar.get_global_rect()
		check(r.end.y <= vr.end.y + 1.0 and r.position.y >= vr.position.y - 1.0 and r.end.x <= vr.end.x + 1.0,
			"%s: footer prompts on screen (bar %s, view %s)" % [tag, str(r), str(vr.size)])
	check(bars > 0, "%s: has a prompt bar" % tag)
	var smallest := 999.0
	var smallest_text := ""
	var collapsed: Array = []
	for n in s.find_children("*", "", true, false):
		var size_du := 0
		var text := ""
		if n is Label and (n as Label).is_visible_in_tree():
			text = (n as Label).text
			size_du = (n as Label).get_theme_font_size("font_size")
			if text.strip_edges() != "" and (n as Label).size.y < float(size_du) * 0.8:
				collapsed.append(text.substr(0, 30))
		elif n is Button and (n as Button).is_visible_in_tree():
			text = (n as Button).text
			size_du = (n as Button).get_theme_font_size("font_size")
		if text.strip_edges() == "":
			continue
		var px := size_du * px_per_du
		if px < smallest:
			smallest = px
			smallest_text = text
	check(smallest >= 18.0 - 0.01, "%s: smallest text '%s' is %.1f px (< 18 px)" % [tag, smallest_text.substr(0, 30), smallest])
	check(collapsed.is_empty(), "%s: labels squeezed below one line of text: %s" % [tag, str(collapsed)])
