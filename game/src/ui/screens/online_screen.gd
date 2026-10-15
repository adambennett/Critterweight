class_name OnlineScreen
extends Screen
## Online play ("online"): host a listen-server session, join one by address, find sessions on
## the local network, or rejoin a recent server (dedicated servers are joined by address too).
## Three tabs (LB/RB): HOST, JOIN, LAN. One vertical list per tab (predictable controller focus),
## a help panel and a CONNECTION panel on the right. Y / R runs the tab's main action.
## Everything defaults from Settings (network.*); the session itself is the Net autoload's.
## After hosting or joining, OnlineFlow follows the session and the lobby screen opens.
## params: {tab: "host" | "join" | "lan"}

const TABS := ["host", "join", "lan"]
const TAB_TITLES := ["Host", "Join", "LAN"]
const FORMAT_NAMES := {"duel": "1 v 1", "ffa": "free-for-all", "teams": "teams", "tag": "tag team", "coop": "co-op"}

var _tabs: TabStrip
var _scroll: FocusScroll
var _help: HelpPanel
var _status_title: Label
var _status: Label
var _status_extra: Label
var _bar: PromptBar
var _session := "match"                  ## host: "match" | "party"
var _host := {"rules": "", "arena": "", "playlist": "", "bots": 0, "tier": BotTiers.DEFAULT, "policy": ""}
var _join := {"address": "", "port": 0, "password": "", "spectate": false}
var _connecting := false
var _focus_by_tab := {}
var _last_tab := ""
var _primary: UiButton = null


func on_enter(p: Dictionary) -> void:
	MenuBackdrop.ensure()
	add_backdrop_gradient(0.97, 0.75)
	_defaults()
	var f := build_frame("Play with others", "Online")
	var body: VBoxContainer = f["body"]
	_tabs = TabStrip.new()
	_tabs.setup(TAB_TITLES, TABS, maxi(0, TABS.find(str(p.get("tab", "host")))))
	_tabs.tab_changed.connect(func(_i: int) -> void: _show_tab())
	body.add_child(_tabs)
	var cols := UiTheme.hbox(UiTheme.GAP_L)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	var left := UiTheme.panel("PanelSolid", 18.0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.5
	cols.add_child(left)
	_scroll = FocusScroll.new(8)
	left.add_child(_scroll)
	var right := UiTheme.vbox(UiTheme.GAP_M)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size = Vector2(560, 0)
	cols.add_child(right)
	var status_panel := UiTheme.panel("PanelPoster")
	right.add_child(status_panel)
	var sv := UiTheme.vbox(UiTheme.GAP_XS)
	status_panel.add_child(sv)
	sv.add_child(UiTheme.label("CONNECTION", "Eyebrow"))
	_status_title = UiTheme.label("", "H3", true)
	sv.add_child(_status_title)
	_status = UiTheme.label("", "Body", true)
	sv.add_child(_status)
	_status_extra = UiTheme.label("", "Caption", true)
	sv.add_child(_status_extra)
	_help = HelpPanel.new(_scroll)
	_help.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_help)
	_bar = f["prompts"]
	Net.joined.connect(_on_joined)
	Net.connection_failed.connect(_on_failed)
	Net.lan_sessions_changed.connect(_on_lan_changed)
	Net.session_state_changed.connect(_on_state)
	_show_tab()
	play_intro()


func on_exit() -> void:
	for pair in [[Net.joined, _on_joined], [Net.connection_failed, _on_failed], [Net.lan_sessions_changed, _on_lan_changed],
			[Net.session_state_changed, _on_state]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	if not _connecting and Net.is_lan_discovery_active():
		Net.stop_lan_discovery()


func on_resume() -> void:
	super()
	_update_status()


func default_focus() -> Control:
	var fs := _scroll.focusables()
	return fs[0] if not fs.is_empty() else null


func tab() -> String:
	return _tabs.current_id()


# --- defaults --------------------------------------------------------------------------------

func _defaults() -> void:
	var rules := online_rules()
	_host["rules"] = "duel" if rules.has("duel") else (str(rules[0]) if not rules.is_empty() else "duel")
	var arenas := Content.ids("arenas")
	_host["arena"] = "the_gullet" if arenas.has("the_gullet") or arenas.is_empty() else str(arenas[0])
	_host["tier"] = BotTiers.default_tier()
	var recent := Net.recent_servers()
	_join["port"] = int(Settings.get_value("network.port"))
	if not recent.is_empty():
		_join["address"] = str(recent[0]["address"])
		_join["port"] = int(recent[0]["port"])


## Rules presets that can be played online: everything but local-only modes (practice, tutorial,
## campaign fights), the player's own saved presets included.
static func online_rules() -> Array:
	var out: Array = []
	for id in Content.ids("rules"):
		var r := Content.get_entry("rules", str(id))
		var m := str(r.get("mode", "standard"))
		if m in ["practice", "tutorial", "campaign"] or str(id) == "practice":
			continue
		out.append(str(id))
	return out


static func rules_label(id: String) -> String:
	var r := Content.get_entry("rules", id)
	var n := str(r.get("name", id))
	var fmt := str(FORMAT_NAMES.get(str(r.get("format", "")), ""))
	if RulePresets.is_user(id):
		n += " (yours)"
	return "%s · %s" % [n, fmt] if fmt != "" else n


# --- tabs ------------------------------------------------------------------------------------

func _show_tab() -> void:
	var t := tab()
	if t != "lan" and Net.is_lan_discovery_active() and not _connecting:
		Net.stop_lan_discovery()
	match t:
		"host":
			_build_host()
		"join":
			_build_join()
		"lan":
			if bool(Settings.get_value("network.lan_discovery")):
				Net.start_lan_discovery()
			_build_lan()
	_update_prompts()
	_update_status()


func _update_prompts() -> void:
	var action := {"host": "Host session", "join": "Join", "lan": "Refresh"}.get(tab(), "") as String
	_bar.set_prompts([{"actions": ["ui_accept"], "text": "Select"}, {"actions": ["ui_left", "ui_right"], "text": "Change"},
		{"actions": ["ui_tab_prev", "ui_tab_next"], "text": "Tabs", "call": func() -> void: _tabs.step(1)},
		{"actions": ["ui_alt"], "text": action, "call": _primary_action},
		{"actions": ["ui_cancel"], "text": "Back", "call": App.back}])


func _primary_action() -> void:
	match tab():
		"host":
			_do_host()
		"join":
			_do_join()
		"lan":
			_refresh_lan()


func _begin_list() -> VBoxContainer:
	var prev := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if prev != null and _scroll.is_ancestor_of(prev) and prev.has_meta("focus_key"):
		_focus_by_tab[_last_tab] = str(prev.get_meta("focus_key"))
	_last_tab = tab()
	_scroll.clear()
	_primary = null
	return _scroll.content


func _end_list(focus_key := "") -> void:
	_scroll.wrap_focus.call_deferred()
	var k := focus_key if focus_key != "" else str(_focus_by_tab.get(tab(), ""))
	_focus_key.call_deferred(k)


func _focus_key(key: String) -> void:
	if not is_top():
		return
	for f in _scroll.focusables():
		if key != "" and f.has_meta("focus_key") and str(f.get_meta("focus_key")) == key:
			f.grab_focus()
			return
	var d := default_focus()
	if d:
		d.grab_focus()


func _keyed(c: Control, key: String) -> Control:
	c.set_meta("focus_key", key)
	return c


func _section(c: VBoxContainer, text: String) -> void:
	c.add_child(UiTheme.spacer(false, 6))
	c.add_child(UiTheme.label(text.to_upper(), "Eyebrow"))


# --- HOST ------------------------------------------------------------------------------------

func _build_host(focus_key := "") -> void:
	var c := _begin_list()
	if Net.is_session_active():
		_add_session_banner(c)
	_section(c, "Session")
	var st := OptionRow.new("Session")
	st.setup(["match", "party"], ["Matches", "Co-op party run"], _session)
	st.set_help("Session", "Matches: everyone fights under the rules below, again and again from the lobby.\n"
		+ "Co-op party run: a campaign run played together; you start a new one or resume a suspended one in the lobby.")
	st.value_changed.connect(func(v) -> void:
		_session = str(v)
		_build_host("session"))
	c.add_child(_keyed(st, "session"))
	if _session == "match":
		var ids := online_rules()
		var names: Array[String] = []
		for id in ids:
			names.append(rules_label(str(id)))
		var rr := OptionRow.new("Rules")
		rr.setup(ids, names, _host["rules"])
		rr.set_help("Rules preset", str(Content.get_entry("rules", str(_host["rules"])).get("description", "")),
			"Your own presets from the Rules Editor are listed too: the full rules travel to every player.")
		rr.value_changed.connect(func(v) -> void:
			_host["rules"] = str(v)
			rr.set_help("Rules preset", str(Content.get_entry("rules", str(v)).get("description", "")),
				"Your own presets from the Rules Editor are listed too: the full rules travel to every player.")
			_help.show_help(rr.help_title, rr.help_text, rr.help_extra))
		c.add_child(_keyed(rr, "rules"))
		var a_ids := Content.ids("arenas")
		if a_ids.is_empty():
			a_ids = ["the_gullet"]
		var a_names: Array[String] = []
		for id in a_ids:
			var nm := str(Content.get_entry("arenas", str(id)).get("name", str(id).capitalize()))
			a_names.append(nm + (" (yours)" if str(id).begins_with(ArenaLibrary.PREFIX) else ""))
		var ar := OptionRow.new("Arena")
		ar.setup(a_ids, a_names, _host["arena"])
		ar.set_help("Arena", "Where the fights happen. Your own layouts from the Arena Editor are sent to the other players before each match.")
		ar.value_changed.connect(func(v) -> void: _host["arena"] = str(v))
		c.add_child(_keyed(ar, "arena"))
		var pl_ids: Array = [""]
		var pl_names: Array[String] = ["Off"]
		for id in Content.ids("playlists"):
			pl_ids.append(str(id))
			pl_names.append("Vote: " + str(Content.get_entry("playlists", str(id)).get("name", str(id))))
		var pr := OptionRow.new("Playlist")
		pr.setup(pl_ids, pl_names, _host["playlist"])
		pr.set_help("Playlist voting", "Off: you choose the rules and arena in the lobby. A playlist: players vote between a few of its entries before each match; you start the winner.")
		pr.value_changed.connect(func(v) -> void: _host["playlist"] = str(v))
		c.add_child(_keyed(pr, "playlist"))
		_section(c, "Bots")
		var b_ids: Array = []
		var b_names: Array[String] = []
		for n in 8:
			b_ids.append(n)
			b_names.append("No bots" if n == 0 else ("%d bot" % n if n == 1 else "%d bots" % n))
		var br := OptionRow.new("Bots")
		br.setup(b_ids, b_names, int(_host["bots"]))
		br.set_help("Bots", "Bots fill free fighter slots up to the rules' player count.")
		br.value_changed.connect(func(v) -> void: _host["bots"] = int(v))
		c.add_child(_keyed(br, "bots"))
		var tr := OptionRow.new("Bot skill")
		tr.setup(BotTiers.ids(), BotTiers.names(), _host["tier"])
		tr.set_help("Bot skill: %s" % BotTiers.display_name(str(_host["tier"])), BotTiers.blurb(str(_host["tier"])))
		tr.value_changed.connect(func(v) -> void:
			_host["tier"] = str(v)
			tr.set_help("Bot skill: %s" % BotTiers.display_name(str(v)), BotTiers.blurb(str(v)))
			_help.show_help(tr.help_title, tr.help_text))
		c.add_child(_keyed(tr, "tier"))
		var po_ids: Array = [""]
		var po_names: Array[String] = ["Scripted bots"]
		for pe in PolicyLibrary.list():
			if typeof(pe) == TYPE_DICTIONARY and bool(pe.get("valid", false)) and po_ids.size() < 40:
				po_ids.append(str(pe.get("id", "")))
				var cn := str(Content.get_entry("creatures", str(pe.get("creature", ""))).get("name", pe.get("creature", "")))
				po_names.append("%s (%s)" % [str(pe.get("name", pe.get("id", ""))), cn])
		var por := OptionRow.new("AI Lab policy")
		por.setup(po_ids, po_names, _host["policy"])
		por.set_help("AI Lab policy", "Bots can be driven by a policy you trained in the AI Lab (each bot then fights as the policy's own fighter). Only your machine runs it; the other players need nothing.")
		por.value_changed.connect(func(v) -> void: _host["policy"] = str(v))
		c.add_child(_keyed(por, "policy"))
	else:
		var note := UiTheme.label("In the lobby you start a new party run or resume a suspended one: each member gets their seat back by the run's id.", "Caption", true)
		c.add_child(note)
	_section(c, "Your session")
	for key in ["network.player_name", "network.max_players", "network.password", "network.lan_discovery", "network.port"]:
		var row := SettingRows.make(key)
		c.add_child(_keyed(row, key))
	c.add_child(UiTheme.spacer(false, 6))
	_primary = UiButton.new("Host session", "PrimaryButton", "online")
	_primary.custom_minimum_size = Vector2(0, 76)
	_primary.set_help("Host session", "Opens your session on UDP port %d and takes you to the lobby. Shortcut: Y / R." % int(Settings.get_value("network.port")))
	_primary.pressed.connect(_do_host)
	c.add_child(_keyed(_primary, "host"))
	_end_list(focus_key)


func _add_session_banner(c: VBoxContainer) -> void:
	var t := UiTheme.label("You are in a session.", "Warning", true)
	c.add_child(t)
	var open := UiButton.new("Open the lobby", "PrimaryButton", "team")
	open.set_help("Open the lobby", "Back to the players of your current session.")
	open.pressed.connect(func() -> void: App.push("lobby"))
	c.add_child(_keyed(open, "open_lobby"))
	var lv := UiButton.new("Leave the session", "", "quit")
	lv.set_help("Leave the session", "Disconnects you (a host closes the session for everyone).")
	lv.pressed.connect(_confirm_leave)
	c.add_child(_keyed(lv, "leave"))


func _confirm_leave() -> void:
	var host := Net.is_host()
	App.dialog("Leave the session?", "Everyone in your session is disconnected." if host else "You can join again later.",
		[{"label": "Leave", "id": "leave", "danger": true}, {"label": "Stay", "id": "stay", "cancel": true}],
		func(id: String) -> void:
			if id == "leave":
				OnlineFlow.end()
				Net.leave()
				_show_tab())


func host_config() -> Dictionary:
	var cfg := {"creature": default_creature()}
	if _session == "match":
		cfg.merge({"rules": str(_host["rules"]), "arena": str(_host["arena"]), "bots": int(_host["bots"]),
			"bot_difficulty": BotTiers.brain_tier(str(_host["tier"]))})
		if str(_host["policy"]) != "":
			cfg["bot_policy"] = [str(_host["policy"])]
		if str(_host["playlist"]) != "":
			cfg["playlist"] = str(_host["playlist"])
	return cfg


## The fighter a player enters a lobby with (changed there): the first playable fighter that is
## not a development stand-in (the server's own fallback is simply the first playable one).
static func default_creature() -> String:
	var ids := Content.playable_creatures()
	for id in ids:
		var tags = Content.get_entry("creatures", str(id)).get("tags", [])
		if not str(id).begins_with("dev_") and not (tags is Array and (tags as Array).has("dev")):
			return str(id)
	return str(ids[0]) if not ids.is_empty() else ""


func _do_host() -> void:
	if _connecting:
		return
	if Net.is_session_active():
		App.dialog("Already in a session", "Leave your current session before hosting a new one.", [{"label": "OK", "id": "ok"}])
		return
	var err := Net.host(host_config())
	if err != OK:
		Audio.sfx("ui_error")
		OnlineFlow.show_reason(Net.last_failure if not Net.last_failure.is_empty() else
			NetProtocol.describe(NetProtocol.R_LOCAL_ERROR, ["Could not open UDP port %d." % int(Settings.get_value("network.port"))]))
		_update_status()
		return
	Audio.sfx("ui_accept")
	OnlineFlow.begin()
	OnlineFlow.party_mode = _session == "party"
	App.push("lobby")


# --- JOIN ------------------------------------------------------------------------------------

func _build_join(focus_key := "") -> void:
	var c := _begin_list()
	if Net.is_session_active():
		_add_session_banner(c)
	_section(c, "Server")
	var ad := TextFieldRow.new("Address")
	ad.setup(str(_join["address"]), 120)
	ad.placeholder = "IP address or name"
	ad.set_help("Address", "The host's IP address or name, e.g. 192.168.1.20 (local network) or the address they sent you. You can type \"address:port\" with a keyboard.")
	ad.value_changed.connect(_on_address_typed)
	c.add_child(_keyed(ad, "address"))
	var pt := TextFieldRow.new("Port")
	pt.setup(str(int(_join["port"])), 5)
	pt.numeric = true
	pt.min_number = 1
	pt.max_number = 65535
	pt.set_help("Port", "UDP port of the session (the host's Settings > Network > Host port; 7777 by default).")
	pt.value_changed.connect(func(v) -> void: _join["port"] = int(str(v)))
	c.add_child(_keyed(pt, "port"))
	var pw := TextFieldRow.new("Password")
	pw.setup(str(_join["password"]), 32, true)
	pw.placeholder = "(none)"
	pw.set_help("Password", "Only needed when the host set one.")
	pw.value_changed.connect(func(v) -> void: _join["password"] = str(v))
	c.add_child(_keyed(pw, "password"))
	var sp := ToggleRow.new("Join as spectator")
	sp.setup(bool(_join["spectate"]))
	sp.set_help("Join as spectator", "Watch the fights without taking a fighter slot. You can switch in the lobby.")
	sp.value_changed.connect(func(v) -> void: _join["spectate"] = bool(v))
	c.add_child(_keyed(sp, "spectate"))
	c.add_child(_keyed(SettingRows.make("network.player_name"), "network.player_name"))
	c.add_child(UiTheme.spacer(false, 6))
	_primary = UiButton.new("Join", "PrimaryButton", "online")
	_primary.custom_minimum_size = Vector2(0, 76)
	_primary.set_help("Join", "Connects to the server above. Listen hosts and dedicated servers are joined the same way. Shortcut: Y / R.")
	_primary.pressed.connect(_do_join)
	c.add_child(_keyed(_primary, "join"))
	var recent := Net.recent_servers()
	if not recent.is_empty():
		_section(c, "Recent servers")
		for e in recent:
			var d: Dictionary = e
			var label := "%s  ·  %s:%d" % [str(d["name"]) if str(d["name"]) != "" else "Server", str(d["address"]), int(d["port"])]
			var b := UiButton.new(label, "", "restart")
			b.set_help("Recent server" + ("  ·  dedicated" if bool(d.get("dedicated", false)) else ""),
				"Joins %s:%d again. X / Delete: forget it." % [str(d["address"]), int(d["port"])])
			b.set_meta("recent", d)
			b.pressed.connect(func() -> void:
				_join["address"] = str(d["address"])
				_join["port"] = int(d["port"])
				_do_join())
			c.add_child(_keyed(b, "recent:%s:%d" % [str(d["address"]), int(d["port"])]))
	_end_list(focus_key)


## "address:port" typed with a keyboard fills both fields.
func _on_address_typed(v) -> void:
	var text := str(v).strip_edges()
	_join["address"] = text
	if text.count(":") == 1 or text.begins_with("["):
		var parsed := Net.parse_address(text, int(_join["port"]))
		if str(parsed["error"]) == "":
			_join["address"] = str(parsed["address"])
			_join["port"] = int(parsed["port"])
			_build_join("address")


func _do_join() -> void:
	if _connecting:
		return
	if Net.is_session_active():
		App.dialog("Already in a session", "Leave your current session before joining another.", [{"label": "OK", "id": "ok"}])
		return
	var parsed := Net.parse_address(str(_join["address"]), int(_join["port"]))
	if str(parsed["error"]) != "":
		Audio.sfx("ui_error")
		UiNav.toast(str(parsed["error"]), "error")
		_focus_key("address")
		return
	join_server(str(parsed["address"]), int(parsed["port"]), str(_join["password"]), bool(_join["spectate"]))


## Starts connecting (also used by LAN and recent entries). The lobby opens once admitted.
func join_server(address: String, port: int, password: String, spectate := false) -> void:
	_connecting = true
	OnlineFlow.begin()
	OnlineFlow.party_mode = false
	var err := Net.join(address, port, password, {"spectator": spectate, "creature": default_creature()})
	if err != OK:
		_connecting = false
		OnlineFlow.end()
		Audio.sfx("ui_error")
		OnlineFlow.show_reason(Net.last_failure if not Net.last_failure.is_empty() else
			NetProtocol.describe(NetProtocol.R_LOCAL_ERROR, ["Could not start connecting to %s:%d (%s)." % [address, port, error_string(err)]]))
	_update_status()


func _on_joined(_w: Dictionary) -> void:
	_connecting = false
	if not is_inside_tree():
		return
	Audio.sfx("ui_accept")
	if App.top_screen() == self:
		App.push("lobby")
	_update_status()


func _on_failed(reason: Dictionary) -> void:
	_connecting = false
	OnlineFlow.end()
	if not is_inside_tree():
		return
	Audio.sfx("ui_error")
	OnlineFlow.show_reason(reason)
	_update_status()


# --- LAN -------------------------------------------------------------------------------------

func _build_lan(focus_key := "") -> void:
	var c := _begin_list()
	if not bool(Settings.get_value("network.lan_discovery")):
		c.add_child(UiTheme.label("LAN discovery is off, so this list stays empty.", "Warning", true))
		var on := UiButton.new("Turn LAN discovery on", "PrimaryButton", "online")
		on.set_help("LAN discovery", "Finds sessions on your local network and lets yours be found (Settings > Network).")
		on.pressed.connect(func() -> void:
			Settings.set_value("network.lan_discovery", true)
			Net.start_lan_discovery()
			_build_lan("lan_on"))
		c.add_child(_keyed(on, "lan_on"))
		_end_list(focus_key)
		return
	var sessions := Net.lan_sessions()
	if sessions.is_empty():
		var l := UiTheme.label("Looking for sessions on your network...  Hosts must have LAN discovery on.", "BodyMuted", true)
		c.add_child(l)
	for s in sessions:
		var d: Dictionary = s
		var players := "%d/%d" % [int(d.get("players", 0)), int(d.get("max_players", 0))]
		var what := "%s @ %s" % [str(d.get("rules", "")), str(d.get("arena", ""))]
		var text := "%s  ·  %s  ·  %s players%s" % [str(d.get("name", "Session")), what, players, "  ·  in a match" if bool(d.get("in_match", false)) else ""]
		var icon := "lock" if bool(d.get("password", false)) else ("error" if not bool(d.get("compatible", true)) else "online")
		var b := UiButton.new(text, "", icon)
		var lines: Array = d.get("compat_lines", [])
		var detail := "%s:%d%s%s" % [UiDevFlags.shown_address(str(d.get("address", ""))), int(d.get("port", 0)), "  ·  dedicated server" if bool(d.get("dedicated", false)) else "",
			"  ·  password" if bool(d.get("password", false)) else ""]
		if bool(d.get("compatible", true)):
			b.set_help(str(d.get("name", "Session")), "Joins this session. " + detail)
		else:
			b.set_help("Not compatible: " + str(d.get("name", "Session")), "\n".join(PackedStringArray(lines.map(func(x) -> String: return "•  " + str(x)))) + "\n" + detail)
		b.pressed.connect(_join_lan.bind(d))
		c.add_child(_keyed(b, "lan:%s" % str(d.get("instance", ""))))
	_end_list(focus_key)


func _join_lan(d: Dictionary) -> void:
	if not bool(d.get("compatible", true)):
		Audio.sfx("ui_error")
		var lines: Array = d.get("compat_lines", [])
		App.dialog("Can't join %s" % str(d.get("name", "this session")), "\n".join(PackedStringArray(lines.map(func(x) -> String: return "•  " + str(x)))),
			[{"label": "OK", "id": "ok"}], Callable())
		return
	var addr := str(d.get("address", ""))
	var port := int(d.get("port", 0))
	if bool(d.get("password", false)):
		App.push("text_entry", {"title": "Password for %s" % str(d.get("name", "the session")), "value": "", "max_len": 32, "secret": true,
			"callback": func(ok: bool, text: String) -> void:
				if ok:
					join_server(addr, port, text)})
		return
	join_server(addr, port, "")


func _refresh_lan() -> void:
	Net.stop_lan_discovery()
	if bool(Settings.get_value("network.lan_discovery")):
		Net.start_lan_discovery()
	_build_lan()
	UiNav.toast("Looking for sessions on your network...", "info", 2.0)


func _on_lan_changed(_sessions: Array) -> void:
	if tab() == "lan" and is_inside_tree():
		var f := get_viewport().gui_get_focus_owner()
		var key := str(f.get_meta("focus_key")) if f != null and _scroll.is_ancestor_of(f) and f.has_meta("focus_key") else ""
		_build_lan(key)


# --- status ----------------------------------------------------------------------------------

func _on_state(_s: String) -> void:
	_update_status()


func _update_status() -> void:
	if _status == null:
		return
	var extra := ""
	match Net.session_state():
		"offline":
			_status_title.text = "Not connected"
			_status.text = "Host a session for friends, or join one by address or from your local network."
			var addrs := UiDevFlags.shown_addresses(Net.local_addresses())
			extra = ("This computer: %s" % ", ".join(PackedStringArray(addrs.slice(0, 2)))) if not addrs.is_empty() else ""
		"connecting":
			_status_title.text = "Connecting..."
			_status.text = "Waiting for %s:%d to answer. B / Esc cancels." % [str(Net.client.address) if Net.client else "?", int(Net.client.port) if Net.client else 0]
		_:
			var l := Net.lobby()
			_status_title.text = ("Hosting  %s" % str(l.get("name", ""))) if Net.is_host() else ("Connected to  %s" % str(l.get("name", "")))
			_status.text = "%d player%s in the session." % [(l.get("players", []) as Array).size(), "" if (l.get("players", []) as Array).size() == 1 else "s"]
			if Net.is_host():
				extra = Net.invite_text(UiDevFlags.shown_invite_address())
	_status_extra.text = extra
	_status_extra.visible = extra != ""


# --- input -----------------------------------------------------------------------------------

func on_back() -> bool:
	if _connecting:
		_connecting = false
		OnlineFlow.end()
		Net.leave()
		UiNav.toast("Connection cancelled.", "info")
		_update_status()
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not is_top():
		return
	if event.is_action_pressed("ui_tab_next") or event.is_action_pressed("ui_tab_prev"):
		get_viewport().set_input_as_handled()
		_tabs.step(1 if event.is_action_pressed("ui_tab_next") else -1)
		return
	if event.is_action_pressed("ui_alt"):
		get_viewport().set_input_as_handled()
		_primary_action()
		return
	if event.is_action_pressed("ui_extra"):
		var f := get_viewport().gui_get_focus_owner()
		if f != null and f.has_meta("recent"):
			get_viewport().set_input_as_handled()
			var d: Dictionary = f.get_meta("recent")
			Net.forget_server(str(d["address"]), int(d["port"]))
			UiNav.toast("Forgot %s:%d." % [str(d["address"]), int(d["port"])], "info")
			_build_join()
			return
	super(event)
