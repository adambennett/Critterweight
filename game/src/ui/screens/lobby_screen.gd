class_name LobbyScreen
extends Screen
## The session lobby ("lobby"), for listen hosts, their guests and dedicated-server players.
## Left: one vertical list (predictable controller focus) - YOUR fighter / team / spectate /
## ready, the playlist VOTE, HOST controls (rules, arena, playlist voting, bots, skill, AI Lab
## policy, start, copy invite), CO-OP PARTY RUN (start a new one, resume a suspended one through
## party seats, rejoin by run id) and SESSION (rules explained, leave). Right: the players
## (name cards framed by their equipped profile frame, cosmetics, fighter, team, ready, ping) and
## the active rules. Under the list, one help line follows focus (a full help panel does not fit
## beside the players at 1280x800).
## The list is rebuilt only when its shape changes (host/phase/vote/party); otherwise rows are
## updated in place, so focus never jumps while other players change things.
## Session events after a match (results, back to the lobby, host left) are OnlineFlow's.

const TEAM_IDS := [-1, 0, 1, 2, 3]

var _scroll: FocusScroll
var _players: VBoxContainer
var _players_title: Label
var _rules_box: VBoxContainer
var _bar: PromptBar
var _title: Label
var _eyebrow: Label
var _phase: Label
var _shape := ""
var _rows := {}                    ## key -> row/button for in-place updates
var _party_shape := ""
var _tick := 0.0
var _help: Label


func on_enter(_p: Dictionary) -> void:
	MenuBackdrop.ensure()
	add_backdrop_gradient(0.97, 0.78)
	var f := build_frame("Online lobby", "Lobby")
	var header: VBoxContainer = f["header"]
	_eyebrow = header.get_child(0) as Label
	_title = header.get_child(1) as Label
	_phase = UiTheme.label("", "Caption", true)
	header.add_child(_phase)
	var body: VBoxContainer = f["body"]
	var cols := UiTheme.hbox(UiTheme.GAP_L)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	var left := UiTheme.panel("PanelSolid", 18.0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.25
	cols.add_child(left)
	var lv := UiTheme.vbox(UiTheme.GAP_S)
	left.add_child(lv)
	_scroll = FocusScroll.new(8)
	lv.add_child(_scroll)
	# (no overrun trimming: a trimmed Label reports a 1 px minimum height and collapses in the box)
	_help = UiTheme.label("", "Caption", true)
	_help.max_lines_visible = 2
	lv.add_child(_help)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	var right := UiTheme.vbox(UiTheme.GAP_M)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size = Vector2(640, 0)
	cols.add_child(right)
	var poster := UiTheme.panel("PanelPoster")
	poster.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(poster)
	var pv := UiTheme.vbox(UiTheme.GAP_S)
	poster.add_child(pv)
	_players_title = UiTheme.label("PLAYERS", "Eyebrow")
	pv.add_child(_players_title)
	var ps := ScrollContainer.new()
	ps.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ps.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.add_child(ps)
	_players = UiTheme.vbox(UiTheme.GAP_S)
	_players.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ps.add_child(_players)
	var rules_panel := UiTheme.panel("PanelSolid", 16.0)
	right.add_child(rules_panel)
	_rules_box = UiTheme.vbox(UiTheme.GAP_XS)
	rules_panel.add_child(_rules_box)
	_bar = f["prompts"]
	_bar.set_prompts([{"actions": ["ui_accept"], "text": "Select"}, {"actions": ["ui_left", "ui_right"], "text": "Change"},
		{"actions": ["ui_alt"], "text": "Start match" if Net.is_host() else "Ready", "call": _alt_action},
		{"actions": ["ui_cancel"], "text": "Leave", "call": App.back}])
	Net.lobby_changed.connect(_on_lobby)
	Net.notice.connect(_on_notice)
	Net.party_changed.connect(_on_party_changed)
	Net.party_claim_failed.connect(_on_claim_failed)
	_refresh(true)
	play_intro()


func on_exit() -> void:
	for pair in [[Net.lobby_changed, _on_lobby], [Net.notice, _on_notice], [Net.party_changed, _on_party_changed],
			[Net.party_claim_failed, _on_claim_failed]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	if is_inside_tree() and get_viewport().gui_focus_changed.is_connected(_on_focus_changed):
		get_viewport().gui_focus_changed.disconnect(_on_focus_changed)


## The help line under the list: the focused row's help ("Title: text"), or nothing.
func _on_focus_changed(c: Control) -> void:
	if _help == null or not is_instance_valid(_help) or c == null or not is_instance_valid(c) or not _scroll.is_ancestor_of(c):
		return
	var title := str(c.get("help_title")) if "help_title" in c else ""
	var body := str(c.get("help_text")) if "help_text" in c else ""
	body = body.get_slice("\n", 0)
	_help.text = ("%s: %s" % [title, body]) if title != "" and body != "" else body


func on_resume() -> void:
	super()
	_refresh(true)


func default_focus() -> Control:
	var fs := _scroll.focusables()
	return fs[0] if not fs.is_empty() else null


func lobby() -> Dictionary:
	return Net.lobby()


func me() -> Dictionary:
	var pid := Net.local_peer_id()
	for p in lobby().get("players", []):
		if int((p as Dictionary).get("id", 0)) == pid:
			return p
	return {}


func _process(dt: float) -> void:
	# (the party run itself is ticked under Net - NetPartyRuns.start_ticking - whatever the screen)
	if OnlineFlow.party != null or not Net.party().is_empty():
		var ps := _party_state_key()
		if ps != _party_shape:
			_refresh(true)
	# pings, countdowns and the host's live lobby change without a broadcast: refresh twice a second
	_tick += dt
	if _tick >= 0.5:
		_tick = 0.0
		_refresh(false)


# --- refresh ---------------------------------------------------------------------------------

func _on_lobby(_l: Dictionary) -> void:
	_refresh(false)


func _on_party_changed(_pt: Dictionary) -> void:
	_refresh(true)


func _on_notice(text: String) -> void:
	if is_top():
		UiNav.toast(text, "info", 4.0)


func _on_claim_failed(reason: String) -> void:
	if OnlineFlow.party != null and OnlineFlow.party.role == "member" and OnlineFlow.party.session == null:
		OnlineFlow.drop_party()
	UiNav.toast("Seat refused: %s" % reason, "error")
	_refresh(true)


## The list's shape: anything that adds or removes rows.
func _shape_key() -> String:
	var l := lobby()
	var v: Dictionary = l.get("vote", {})
	var keys: Array = []
	for c in v.get("candidates", []):
		keys.append(str((c as Dictionary).get("key", "")))
	var opts: Dictionary = l.get("options", {})
	return "|".join(PackedStringArray([str(Net.is_host()), str(l.get("phase", "")), str(bool(me().get("spectator", false))),
		str(bool(v.get("open", false))), ",".join(PackedStringArray(keys)), str((opts.get("rules", []) as Array).size()),
		str((opts.get("arenas", []) as Array).size()), str((opts.get("bot_policies", []) as Array).size()),
		str((l.get("playlist", {}) as Dictionary).get("id", "")), _party_state_key()]))


func _party_state_key() -> String:
	var pt := Net.party()
	var pr := OnlineFlow.party
	var seats: Array = []
	for s in pt.get("seats", []):
		seats.append("%s=%d" % [str((s as Dictionary).get("id", "")), int((s as Dictionary).get("session", 0))])
	var run := ""
	if pr != null and pr.session != null and pr.session.ctrl != null:
		run = "%s/%s" % [str(pr.session.ctrl.state.get("position", "")), str(pr.is_live())]
	return "%s#%s#%s#%s#%s#%s" % [str(pt.get("run_id", "")), ",".join(PackedStringArray(seats)), str(pr != null),
		str(pr != null and pr.session != null), run, Net.party_seat()]


func _refresh(force: bool) -> void:
	if not is_inside_tree():
		return
	var l := lobby()
	if l.is_empty() and not Net.is_session_active():
		return
	_title.text = str(l.get("name", "Lobby")).to_upper()
	_eyebrow.text = ("ONLINE LOBBY  ·  YOU HOST" if Net.is_host() else ("DEDICATED SERVER" if bool(l.get("dedicated", false)) else "ONLINE LOBBY")).to_upper()
	_phase.text = _phase_text(l)
	_update_players(l)
	_update_rules(l)
	var shape := _shape_key()
	if force or shape != _shape:
		_shape = shape
		_party_shape = _party_state_key()
		_rebuild()
	else:
		_update_values(l)


func _phase_text(l: Dictionary) -> String:
	var cd := float(l.get("countdown", -1.0))
	match str(l.get("phase", "")):
		"lobby":
			if cd > 0.0:
				return "Next match in %d s - ready up!" % ceili(cd)
			return "Waiting for the host to start the match." if not Net.is_host() else "Start the match when everyone is ready (Y / R)."
		"match":
			return "A match is running. You join the next one."
		"results":
			return "Results - back to the lobby in a moment."
	return ""


# --- list ------------------------------------------------------------------------------------

func _rebuild() -> void:
	var prev := get_viewport().gui_get_focus_owner()
	var key := str(prev.get_meta("focus_key")) if prev != null and _scroll.is_ancestor_of(prev) and prev.has_meta("focus_key") else ""
	_scroll.clear()
	_rows.clear()
	var c := _scroll.content
	var l := lobby()
	var mine := me()
	_section(c, "You")
	var pr := PickRow.new("Fighter")
	_set_pick(pr, str(mine.get("creature", "")))
	pr.set_help("Your fighter", "Who you fight as in the next match. Opens the character select.")
	pr.activated.connect(_pick_fighter)
	c.add_child(_keyed(pr, "fighter"))
	var tr := OptionRow.new("Team")
	var tnames: Array[String] = ["Automatic"]
	for t in 4:
		tnames.append("Team %s" % UiTheme.team_letter(t))
	tr.setup(TEAM_IDS, tnames, int(mine.get("team", -1)) if TEAM_IDS.has(int(mine.get("team", -1))) else -1)
	tr.set_help("Team", "Team formats put you on this team when they can. Automatic balances the teams. Duels and free-for-alls ignore it.")
	tr.value_changed.connect(func(v) -> void: Net.set_team(int(v)))
	c.add_child(_keyed(tr, "team"))
	var sp := ToggleRow.new("Spectate")
	sp.setup(bool(mine.get("spectator", false)))
	sp.set_help("Spectate", "Watch the next matches instead of fighting (when the session has a spectator place free).")
	sp.value_changed.connect(func(v) -> void: Net.set_spectator(bool(v)))
	c.add_child(_keyed(sp, "spectate"))
	if not Net.is_host():
		var rd := ToggleRow.new("Ready")
		rd.setup(bool(mine.get("ready", false)))
		rd.set_help("Ready", "Tells the host you are set. On dedicated servers the match starts early when everyone is ready. Shortcut: Y / R.")
		rd.value_changed.connect(func(v) -> void: Net.set_ready(bool(v)))
		c.add_child(_keyed(rd, "ready"))
		_rows["ready"] = rd
	_rows["fighter"] = pr
	_rows["team"] = tr
	_rows["spectate"] = sp
	var vote: Dictionary = l.get("vote", {})
	if bool(vote.get("open", false)) and not (vote.get("candidates", []) as Array).is_empty():
		_section(c, "Vote for the next match")
		var cands: Array = vote["candidates"]
		for i in cands.size():
			var cd: Dictionary = cands[i]
			var b := UiButton.new(_vote_text(cd, i), "", "star")
			b.set_help("Vote", "%s on %s (%s). The most votes win; a tie goes to the playlist's favourite." % [str(cd.get("rules_name", "")), str(cd.get("arena_name", "")), str(cd.get("mode", ""))])
			b.pressed.connect(func() -> void:
				Net.vote(i)
				UiNav.toast("Voted for %s." % str(cd.get("name", "")), "success", 2.0))
			c.add_child(_keyed(b, "vote%d" % i))
			_rows["vote%d" % i] = b
	if Net.is_host():
		_build_host(c, l)
	if OnlineFlow.party_mode or Net.is_host() or not Net.party().is_empty() or OnlineFlow.party != null:
		_build_party(c)
	_section(c, "Session")
	var ex := UiButton.new("Rules and online restrictions", "", "rules")
	ex.set_help("Rules and online restrictions", "What the host's rules are and what works differently online.")
	ex.pressed.connect(_explain)
	c.add_child(_keyed(ex, "explain"))
	var lv := UiButton.new("Close the session" if Net.is_host() else "Leave the session", "", "quit")
	lv.set_help("Leave", "Everyone is disconnected when the host leaves." if Net.is_host() else "You can join again later.")
	lv.pressed.connect(_confirm_leave)
	c.add_child(_keyed(lv, "leave"))
	_scroll.wrap_focus.call_deferred()
	_focus_key.call_deferred(key)


func _build_host(c: VBoxContainer, l: Dictionary) -> void:
	_section(c, "Host")
	var st: Dictionary = l.get("settings", {})
	var opts: Dictionary = l.get("options", {})
	var r_ids: Array = []
	var r_names: Array[String] = []
	var allowed := OnlineScreen.online_rules()
	for id in opts.get("rules", []):
		if allowed.has(str(id)):
			r_ids.append(str(id))
			r_names.append(OnlineScreen.rules_label(str(id)))
	if r_ids.is_empty():
		r_ids = [str(st.get("rules", "duel"))]
		r_names = [str(st.get("rules_name", "Rules"))]
	var rr := OptionRow.new("Rules")
	rr.setup(r_ids, r_names, str(st.get("rules", "")))
	rr.set_help("Rules preset", str(Content.get_entry("rules", str(st.get("rules", ""))).get("description", "")), "Used when you start the next match (not with playlist voting).")
	rr.value_changed.connect(func(v) -> void: _host_set("rules", str(v)))
	c.add_child(_keyed(rr, "h_rules"))
	_rows["h_rules"] = rr
	var a_ids: Array = []
	var a_names: Array[String] = []
	for id in opts.get("arenas", []):
		a_ids.append(str(id))
		var nm := str(Content.get_entry("arenas", str(id)).get("name", str(id).capitalize()))
		a_names.append(nm + (" (yours)" if str(id).begins_with(ArenaLibrary.PREFIX) else ""))
	if a_ids.is_empty():
		a_ids = [str(st.get("arena", "the_gullet"))]
		a_names = [str(st.get("arena_name", "Arena"))]
	var ar := OptionRow.new("Arena")
	ar.setup(a_ids, a_names, str(st.get("arena", "")))
	ar.set_help("Arena", "Your own layouts are sent to the players before the match.")
	ar.value_changed.connect(func(v) -> void: _host_set("arena", str(v)))
	c.add_child(_keyed(ar, "h_arena"))
	_rows["h_arena"] = ar
	var pl_ids: Array = [""]
	var pl_names: Array[String] = ["Off"]
	for id in Content.ids("playlists"):
		pl_ids.append(str(id))
		pl_names.append("Vote: " + str(Content.get_entry("playlists", str(id)).get("name", str(id))))
	var pr := OptionRow.new("Playlist")
	pr.setup(pl_ids, pl_names, str((l.get("playlist", {}) as Dictionary).get("id", "")))
	pr.set_help("Playlist voting", "Players vote between a few entries of the playlist; Start match plays the winner.")
	pr.value_changed.connect(func(v) -> void: _host_set("playlist", str(v)))
	c.add_child(_keyed(pr, "h_playlist"))
	var b_ids: Array = []
	var b_names: Array[String] = []
	for n in 8:
		b_ids.append(n)
		b_names.append("No bots" if n == 0 else ("%d bot" % n if n == 1 else "%d bots" % n))
	var br := OptionRow.new("Bots")
	br.setup(b_ids, b_names, clampi(int(st.get("bots", 0)), 0, 7))
	br.set_help("Bots", "Bots join the next match on top of the players, up to the rules' fighter count.")
	br.value_changed.connect(func(v) -> void: _host_set("bots", int(v)))
	c.add_child(_keyed(br, "h_bots"))
	_rows["h_bots"] = br
	var tier := BotTiers.default_tier()
	for t in BotTiers.ids():
		if BotTiers.brain_tier(t) == str(st.get("bot_difficulty", "")):
			tier = t
	var tr := OptionRow.new("Bot skill")
	tr.setup(BotTiers.ids(), BotTiers.names(), tier)
	tr.set_help("Bot skill", BotTiers.blurb(tier))
	tr.value_changed.connect(func(v) -> void: _host_set("bot_difficulty", BotTiers.brain_tier(str(v))))
	c.add_child(_keyed(tr, "h_tier"))
	var po_ids: Array = [""]
	var po_names: Array[String] = ["Scripted bots"]
	for pe in opts.get("bot_policies", []):
		po_ids.append(str((pe as Dictionary).get("id", "")))
		po_names.append(str((pe as Dictionary).get("name", (pe as Dictionary).get("id", ""))))
	var cur_pol: Array = st.get("bot_policy", [])
	var por := OptionRow.new("AI Lab policy")
	por.setup(po_ids, po_names, str(cur_pol[0]) if not cur_pol.is_empty() and po_ids.has(str(cur_pol[0])) else "")
	por.set_help("AI Lab policy", "Bots driven by a policy you trained in the AI Lab (only your machine runs it; it is named by its checksum in the match info).")
	por.value_changed.connect(func(v) -> void: _host_set("bot_policy", [str(v)] if str(v) != "" else []))
	c.add_child(_keyed(por, "h_policy"))
	var start := UiButton.new("Start match", "PrimaryButton", "fight")
	start.custom_minimum_size = Vector2(0, 76)
	start.set_help("Start match", "Starts the next match with everyone who is not spectating (and the bots). Shortcut: Y / R.")
	start.pressed.connect(_start_match)
	c.add_child(_keyed(start, "start"))
	var inv := UiButton.new("Copy invite", "", "copy")
	inv.set_help("Copy invite", "Copies a line with your address, port and how to join, to paste into a chat.\n" + Net.invite_text(UiDevFlags.shown_invite_address()))
	inv.pressed.connect(_copy_invite)
	c.add_child(_keyed(inv, "invite"))


func _host_set(key: String, value) -> void:
	var err := Net.host_set(key, value)
	if err != "":
		Audio.sfx("ui_error")
		UiNav.toast(err.capitalize() if err.length() < 2 else err[0].to_upper() + err.substr(1), "error")
		_refresh(true)


func _vote_text(cd: Dictionary, i: int) -> String:
	var tally: Array = (lobby().get("vote", {}) as Dictionary).get("tally", [])
	var n := int(tally[i]) if i < tally.size() else 0
	var mine := int(me().get("vote", -1)) == i
	return "%s  ·  %d vote%s%s" % [str(cd.get("name", "Entry %d" % (i + 1))), n, "" if n == 1 else "s", "  ·  YOUR VOTE" if mine else ""]


func _section(c: VBoxContainer, text: String) -> void:
	c.add_child(UiTheme.spacer(false, 6))
	c.add_child(UiTheme.label(text.to_upper(), "Eyebrow"))


func _keyed(n: Control, key: String) -> Control:
	n.set_meta("focus_key", key)
	return n


func _focus_key(key: String) -> void:
	if not is_top():
		return
	for f in _scroll.focusables():
		if key != "" and f.has_meta("focus_key") and str(f.get_meta("focus_key")) == key:
			f.grab_focus()
			return
	var cur := get_viewport().gui_get_focus_owner()
	if cur == null or not is_ancestor_of(cur):
		var d := default_focus()
		if d:
			d.grab_focus()


func _update_values(l: Dictionary) -> void:
	var mine := me()
	if _rows.has("fighter"):
		_set_pick(_rows["fighter"] as PickRow, str(mine.get("creature", "")))
	if _rows.has("team"):
		(_rows["team"] as OptionRow).set_value(int(mine.get("team", -1)) if TEAM_IDS.has(int(mine.get("team", -1))) else -1)
	if _rows.has("spectate"):
		(_rows["spectate"] as ToggleRow).set_value(bool(mine.get("spectator", false)))
	if _rows.has("ready"):
		(_rows["ready"] as ToggleRow).set_value(bool(mine.get("ready", false)))
	var st: Dictionary = l.get("settings", {})
	if _rows.has("h_rules"):
		(_rows["h_rules"] as OptionRow).set_value(str(st.get("rules", "")))
	if _rows.has("h_arena"):
		(_rows["h_arena"] as OptionRow).set_value(str(st.get("arena", "")))
	if _rows.has("h_bots"):
		(_rows["h_bots"] as OptionRow).set_value(clampi(int(st.get("bots", 0)), 0, 7))
	var cands: Array = (l.get("vote", {}) as Dictionary).get("candidates", [])
	for i in cands.size():
		if _rows.has("vote%d" % i):
			(_rows["vote%d" % i] as UiButton).text = _vote_text(cands[i], i)


func _set_pick(pr: PickRow, cid: String) -> void:
	if cid == "" or Content.get_entry("creatures", cid).is_empty():
		pr.set_choice("Server default", "The host's game picks one for you", UiIcons.tex("random"))
		return
	var d := Content.get_entry("creatures", cid)
	var el := str(d.get("element", ""))
	pr.set_choice(str(d.get("name", cid)).to_upper(), str(d.get("title", "")), UiIcons.element_tex(el) if el != "" else UiIcons.tex("fight"))


# --- players and rules (right column) --------------------------------------------------------

func _update_players(l: Dictionary) -> void:
	for ch in _players.get_children():
		ch.queue_free()
	var plist: Array = l.get("players", [])
	var fighters := 0
	for p in plist:
		if not bool((p as Dictionary).get("spectator", false)):
			fighters += 1
	_players_title.text = "PLAYERS  ·  %d / %d%s" % [fighters, int(l.get("max_players", 0)),
		("  ·  %d watching" % (plist.size() - fighters)) if plist.size() > fighters else ""]
	var pid := Net.local_peer_id()
	for p in plist:
		_players.add_child(player_row(p, int((p as Dictionary).get("id", 0)) == pid))


## One player's row: the name card (framed by their equipped profile frame) with their fighter,
## cosmetics and status, plus a team chip. Not a focus stop.
static func player_row(p: Dictionary, is_me: bool) -> Control:
	var row := UiTheme.hbox(UiTheme.GAP_S)
	row.add_child(TeamChip.new(int(p.get("team", -1)) if int(p.get("team", -1)) >= 0 else -1, 34))
	var card := UiTheme.vbox(0)
	var tags: PackedStringArray = PackedStringArray()
	if bool(p.get("host", false)):
		tags.append("HOST")
	if is_me:
		tags.append("YOU")
	var name := UiTheme.label(str(p.get("name", "?")).to_upper() + ("  ·  " + "  ·  ".join(tags) if not tags.is_empty() else ""), "Value")
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card.add_child(name)
	var cid := str(p.get("creature", ""))
	var cname := str(Content.get_entry("creatures", cid).get("name", cid)) if cid != "" else "Fighter: host's choice"
	var state := "spectating" if bool(p.get("spectator", false)) else ("READY" if bool(p.get("ready", false)) else "not ready")
	if not bool(p.get("connected", true)):
		state = "reconnecting..."
	var ping := int(p.get("ping", 0))
	card.add_child(UiTheme.label("%s  ·  %s%s" % [cname, state, ("  ·  %d ms" % ping) if ping > 0 else ""], "Caption"))
	var cos: Dictionary = p.get("cosmetics", {})
	var wear: PackedStringArray = PackedStringArray()
	for slot in cos:
		if str(slot) == "frame":
			continue
		var it := Content.get_entry("hub", str(cos[slot]))
		wear.append(str(it.get("name", cos[slot])))
	if not wear.is_empty():
		card.add_child(UiTheme.label("Wears: " + ", ".join(wear), "Caption"))
	var framed := ProfileFrame.wrap(card, ProfileFrame.style(Net.cosmetics_profile(p)), 27)
	framed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(framed)
	if bool(p.get("ready", false)) and not bool(p.get("spectator", false)):
		row.add_child(UiIcons.rect("check", 34, UiTheme.SUCCESS))
	return row


func _update_rules(l: Dictionary) -> void:
	for ch in _rules_box.get_children():
		ch.queue_free()
	_rules_box.add_child(UiTheme.label("ACTIVE RULES", "Eyebrow"))
	for line in rules_summary(l).slice(0, 4):
		_rules_box.add_child(UiTheme.label(str(line), "Caption", true))


## Short lines for the rules panel: the next match and what is different online.
static func rules_summary(l: Dictionary) -> Array:
	var st: Dictionary = l.get("settings", {})
	var out: Array = []
	var pl: Dictionary = l.get("playlist", {})
	if not pl.is_empty():
		out.append("Playlist: %s - players vote for the next match." % str(pl.get("name", pl.get("id", ""))))
	else:
		out.append("%s on %s." % [str(st.get("rules_name", st.get("rules", ""))), str(st.get("arena_name", st.get("arena", "")))])
	var bots := int(st.get("bots", 0))
	if bots > 0:
		var pol: Array = st.get("bot_policy", [])
		out.append("%d bot%s%s." % [bots, "" if bots == 1 else "s", (" driven by AI Lab policy %s" % str(pol[0])) if not pol.is_empty() else ""])
	out.append("Online: no pausing, full game speed, the host's game decides every hit and result.")
	out.append("Aim assist: %s." % ("each player's own setting" if bool(st.get("player_assist", true)) else "normal for everyone (server rule)"))
	return out


## The full explanation (Rules and online restrictions).
static func rules_explained(l: Dictionary) -> String:
	var st: Dictionary = l.get("settings", {})
	var rid := str(st.get("rules", ""))
	var r := Content.get_entry("rules", rid)
	var lines: PackedStringArray = PackedStringArray()
	var pl: Dictionary = l.get("playlist", {})
	if not pl.is_empty():
		lines.append("PLAYLIST  %s: before each match the players vote between a few of its entries; %s." % [str(pl.get("name", "")),
			"the server starts the winner when everyone is ready or the countdown ends" if bool(l.get("dedicated", false)) else "the host starts the winner"])
	lines.append("RULES  %s%s" % [str(st.get("rules_name", rid)), (": " + str(r.get("description", ""))) if str(r.get("description", "")) != "" else "."])
	var parts: PackedStringArray = PackedStringArray()
	if r.has("rounds"):
		parts.append("%d round%s" % [int(r["rounds"]), "" if int(r["rounds"]) == 1 else "s"])
	if float(r.get("round_time", 0)) > 0.0:
		parts.append("%d s rounds" % int(r["round_time"]))
	if int(r.get("lives", 0)) > 0:
		parts.append("%d li%s" % [int(r["lives"]), "fe" if int(r["lives"]) == 1 else "ves"])
	if not parts.is_empty():
		lines.append("        " + ", ".join(parts) + ".")
	if RulePresets.is_user(rid):
		lines.append("        A preset the host made: the full rules are sent to everyone and checked on every machine.")
	lines.append("ARENA  %s%s" % [str(st.get("arena_name", st.get("arena", ""))),
		" (the host's own layout, sent to you before the match)" if str(st.get("arena", "")).begins_with(ArenaLibrary.PREFIX) else "."])
	lines.append("ONLINE  The host's game (or the server) runs the fight and decides every hit, result and reward; your controller input travels to it.")
	lines.append("        Matches never pause and always run at full speed: Game speed and Pause apply offline only.")
	lines.append("        Aim assist: %s." % ("your own setting (low / normal / high)" if bool(st.get("player_assist", true)) else "normal for everyone - this server's rule"))
	lines.append("        Your cosmetics and profile frame are looks only; everyone sees them.")
	lines.append("        Everyone needs the same game version and the same gameplay mods.")
	var bots := int(st.get("bots", 0))
	if bots > 0:
		var pol: Array = st.get("bot_policy", [])
		lines.append("BOTS  %d, %s%s." % [bots, str(st.get("bot_difficulty", "")),
			(", driven by the host's AI Lab policy " + str(pol[0])) if not pol.is_empty() else ""])
	return "\n".join(lines)


func _explain() -> void:
	App.dialog("Rules and online restrictions", rules_explained(lobby()), [{"label": "OK", "id": "ok"}], Callable())


# --- actions ---------------------------------------------------------------------------------

func _pick_fighter() -> void:
	App.push("character_select", {"mode": "pick", "title": "Your fighter", "current": str(me().get("creature", "")),
		"allow_random": true, "on_pick": func(id: String) -> void:
			var chosen := FighterSelection.resolve(id, Content.playable_creatures())
			Net.set_creature(chosen)
			if _rows.has("fighter"):
				_set_pick(_rows["fighter"] as PickRow, chosen)})


func _start_match() -> void:
	if not Net.is_host():
		return
	if OnlineFlow.party != null and OnlineFlow.party.role == "host":
		# a party run is on offer / on: Start starts it (or goes back to it), never a versus match
		if OnlineFlow.party_live():
			OnlineFlow.coop.show_current()
			return
		var pe := OnlineFlow.party.start_host()
		if pe != "":
			UiNav.toast(pe, "error")
		_refresh(true)
		return
	var err := Net.host_start()
	if err != "":
		Audio.sfx("ui_error")
		App.dialog("Can't start yet", err[0].to_upper() + err.substr(1) + ".", [{"label": "OK", "id": "ok"}], Callable())


func _copy_invite() -> void:
	var text := Net.invite_text()
	DisplayServer.clipboard_set(text)
	UiNav.toast("Invite copied: paste it to your friends.", "success")


func _alt_action() -> void:
	if Net.is_host():
		_start_match()
	elif _rows.has("ready"):
		var rd := _rows["ready"] as ToggleRow
		rd.set_value(not rd.get_value())
		Net.set_ready(rd.get_value())


func _confirm_leave() -> void:
	App.dialog("Close the session?" if Net.is_host() else "Leave the session?",
		"Everyone in your session is disconnected." if Net.is_host() else "You can join again later.",
		[{"label": "Leave", "id": "leave", "danger": true}, {"label": "Stay", "id": "stay", "cancel": true}],
		func(id: String) -> void:
			if id == "leave":
				OnlineFlow.leave())


func on_back() -> bool:
	_confirm_leave()
	return true


# --- co-op party run -------------------------------------------------------------------------

const PARTY_VARIANTS := [["off_the_street", "Off the Street"], ["fight_camp", "Fight Camp"]]
const PARTY_FORMATS := [["simultaneous", "Simultaneous (default)"], ["tag", "Tag-team"]]
static var party_variant := "off_the_street"    ## the host's choices for the next new party run
static var party_format := "simultaneous"
static var party_difficulty := "amateur"


func _build_party(c: VBoxContainer) -> void:
	_section(c, "Co-op party run")
	var pt := Net.party()
	var pr := OnlineFlow.party
	if OnlineFlow.party_live():
		_build_party_live(c, pr)
		return
	if pr == null and not Net.is_host() and Net.party_seat() != "" and not pt.is_empty():
		# reconnected while our seat was kept for us: take the run up again at once
		_claim_seat.call_deferred()
		c.add_child(UiTheme.label("You still hold your seat: rejoining the run...", "Success", true))
		return
	if pt.is_empty():
		if not Net.is_host():
			c.add_child(UiTheme.label("The host has not offered a party run.", "BodyMuted", true))
			return
		var saves := party_saves()
		if not saves.is_empty():
			var ids: Array = []
			var names: Array[String] = []
			for s in saves:
				ids.append(str(s["run_id"]))
				names.append(str(s["label"]))
			var sr := OptionRow.new("Suspended run")
			sr.setup(ids, names, ids[0])
			sr.set_help("Resume a party run", "A party run you played online and saved. Its members get their seats back by the run's id; empty seats are played by bots.")
			c.add_child(_keyed(sr, "p_save"))
			var off := UiButton.new("Offer this run", "PrimaryButton", "campaign")
			off.set_help("Offer this run", "Shows the run in everyone's lobby so its members can take their seats again.")
			off.pressed.connect(func() -> void: _offer_saved(str(sr.get_value())))
			c.add_child(_keyed(off, "p_offer"))
		var vr := OptionRow.new("Campaign")
		vr.setup(PARTY_VARIANTS.map(func(e): return e[0]), _names_of(PARTY_VARIANTS), party_variant)
		vr.set_help("Campaign", "Off the Street: everyone starts fresh. Fight Camp: each player's own Cannery upgrades apply to their own fighter; Clout goes to each player's own Cannery.")
		vr.value_changed.connect(func(v) -> void: party_variant = str(v))
		c.add_child(_keyed(vr, "p_variant"))
		var fr := OptionRow.new("Co-op format")
		fr.setup(PARTY_FORMATS.map(func(e): return e[0]), _names_of(PARTY_FORMATS), party_format)
		fr.set_help("Co-op format", "Simultaneous: everyone fights at once (downed allies are revived by holding Grab next to them). Tag-team: one fighter in at a time; the benched partners tag in, cheer and call assists.")
		fr.value_changed.connect(func(v) -> void: party_format = str(v))
		c.add_child(_keyed(fr, "p_format"))
		var cat := _catalog()
		var d_ids: Array = cat.difficulty_ids()
		var d_names: Array[String] = []
		for did in d_ids:
			d_names.append(str(cat.difficulty(str(did)).get("name", str(did).capitalize())))
		if not d_ids.has(party_difficulty) and not d_ids.is_empty():
			party_difficulty = str(d_ids[0])
		var dr := OptionRow.new("Difficulty")
		dr.setup(d_ids, d_names, party_difficulty)
		dr.set_help("Difficulty", "The whole party plays this difficulty.")
		dr.value_changed.connect(func(v) -> void: party_difficulty = str(v))
		c.add_child(_keyed(dr, "p_difficulty"))
		var nw := UiButton.new("Deal a new party run", "", "plus")
		nw.set_help("New party run", "Deals a new card for everyone who is not spectating (each with their lobby fighter). They take their seats, then you start the run.")
		nw.pressed.connect(_new_party_run)
		c.add_child(_keyed(nw, "p_new"))
		return
	# a run is on offer (dealt or suspended), not started yet
	var info: Dictionary = pt.get("info", {})
	c.add_child(UiTheme.label("%s  ·  Act %d  ·  %s%s" % [str(info.get("variant", "")).replace("_", " ").capitalize(), int(info.get("act", 1)),
		"Tag-team" if str(info.get("format", "")) == "tag" else "Simultaneous", "  ·  new" if bool(info.get("new", false)) else ""], "BodyStrong", true))
	var seats: Array = pt.get("seats", [])
	for s in seats:
		var sd: Dictionary = s
		var who := "free"
		if int(sd.get("session", 0)) > 0:
			who = "taken" if not bool(sd.get("connected", false)) else "back"
			for p in lobby().get("players", []):
				if int((p as Dictionary).get("id", 0)) == int(sd["session"]):
					who = "%s is here" % str((p as Dictionary).get("name", "?"))
		var fname := str(Content.get_entry("creatures", str(sd.get("fighter", ""))).get("name", sd.get("fighter", "")))
		c.add_child(UiTheme.label("%s (%s)  ·  %s" % [str(sd.get("name", "")), fname, who], "Body"))
	if Net.is_host():
		var go := UiButton.new("Start the party run", "PrimaryButton", "campaign")
		go.set_help("Start the party run", "Starts the run with the members who are here; anyone missing is played by a bot until they rejoin.")
		go.pressed.connect(func() -> void:
			if OnlineFlow.party == null:
				return
			var e := OnlineFlow.party.start_host()
			if e != "":
				UiNav.toast(e, "error")
			_refresh(true))
		c.add_child(_keyed(go, "p_start"))
		var wd := UiButton.new("Withdraw the offer", "", "close")
		wd.set_help("Withdraw", "Takes the run out of the lobby (a suspended run stays in your saves; a new one is dropped).")
		wd.pressed.connect(func() -> void:
			OnlineFlow.drop_party()
			Net.party_close()
			_refresh(true))
		c.add_child(_keyed(wd, "p_withdraw"))
		return
	if Net.party_seat() != "":
		c.add_child(UiTheme.label("You have your seat. The run starts when the host starts it.", "Success", true))
		return
	var fresh := bool(info.get("new", false))
	var saved := RunStore.new().load_slot(CampaignFlow.profile_key(), NetPartyRuns.slot_of(str(pt.get("run_id", ""))), _catalog())
	if not fresh and not bool(saved.get("ok", false)):
		c.add_child(UiTheme.label("This run is not in your saves: only its members can rejoin it.", "BodyMuted", true))
		return
	var rj := UiButton.new("Take my seat" if fresh else "Rejoin this run", "PrimaryButton", "campaign")
	rj.set_help("Rejoin", "Claims your seat in the host's run by its id (your own save is checked against the host's).")
	rj.pressed.connect(_claim_seat)
	c.add_child(_keyed(rj, "p_claim"))


static func _names_of(pairs: Array) -> Array[String]:
	var out: Array[String] = []
	for e in pairs:
		out.append(str(e[1]))
	return out


## The run is on: the campaign screens play it; the lobby only leads back there.
func _build_party_live(c: VBoxContainer, pr: NetPartyRuns) -> void:
	var s := pr.session
	var st: Dictionary = s.ctrl.state
	c.add_child(UiTheme.label("The party run is on  ·  Act %d  ·  %s" % [int(st.get("act", 1)), str(st.get("variant", "")).replace("_", " ").capitalize()], "BodyStrong", true))
	var back := UiButton.new("Back to the party run", "PrimaryButton", "campaign")
	back.set_help("Back to the run", "The run's map, picks, shops and fights (the run went on while you were here).")
	back.pressed.connect(func() -> void:
		if OnlineFlow.coop != null:
			OnlineFlow.coop.show_current())
	c.add_child(_keyed(back, "p_back"))
	var lv := UiButton.new("Suspend the party run" if Net.is_host() else "Leave the party run", "", "close")
	lv.set_help("Suspend" if Net.is_host() else "Leave", "Everyone goes back to the lobby; the run stays in every member's party save to resume later." if Net.is_host()
		else "A bot plays your fighter until you rejoin (by the run's id).")
	lv.pressed.connect(func() -> void:
		if OnlineFlow.coop != null:
			OnlineFlow.coop.suspend()
		else:
			OnlineFlow.drop_party()
		_refresh(true))
	c.add_child(_keyed(lv, "p_suspend"))


var _cat_cache: CampaignCatalog = null


func _catalog() -> CampaignCatalog:
	if _cat_cache == null:
		_cat_cache = CampaignFlow.make_catalog(CampaignFlow.dev_tools())
	return _cat_cache


## The active profile's suspended party runs this machine can offer: [{run_id, label}].
static func party_saves() -> Array:
	var cat := CampaignFlow.make_catalog(CampaignFlow.dev_tools())
	var out: Array = []
	for e in RunStore.new().list(CampaignFlow.profile_key(), cat):
		var d: Dictionary = e
		if not str(d.get("slot", "")).begins_with("party_") or not bool(d.get("ok", false)):
			continue
		var sm: Dictionary = d.get("summary", {})
		out.append({"run_id": str(sm.get("run_id", "")), "label": "%s · Act %d · %d players" % [str(sm.get("variant", "")).replace("_", " ").capitalize(),
			int(sm.get("act", 1)), int(sm.get("players", 0))]})
	return out


func _party_runs() -> NetPartyRuns:
	return NetPartyRuns.new(_catalog(), RunStore.new(), Profiles.current)


func _offer_saved(run_id: String) -> void:
	var pr := _party_runs()
	var err := pr.open_as_host(run_id)
	if err != "":
		Audio.sfx("ui_error")
		App.dialog("Can't offer this run", err, [{"label": "OK", "id": "ok"}], Callable())
		return
	OnlineFlow.set_party(pr)
	UiNav.toast("Run offered: its members can rejoin now.", "success")
	_refresh(true)


## A new party run for the session's players (2-4, not spectating): the host's campaign, format
## and difficulty; each player's lobby fighter; for Fight Camp each player's own Cannery levels.
static func party_config(cat: CampaignCatalog, variant: String, fmt: String, difficulty: String) -> Dictionary:
	var players := NetPartyRuns.session_party(cat, variant, OnlineScreen.default_creature(), Profiles.current)
	var reasons: Array = [CampaignFlow.REASON_STAND_INS] if cat.resolver.stand_in != "" else []
	return {"seed": 0, "variant": variant, "difficulty": difficulty, "dose": 0, "created_at": int(Time.get_unix_time_from_system()),
		"players": players, "coop_format": fmt, "custom": not reasons.is_empty(), "custom_reasons": reasons}


func _new_party_run() -> void:
	var cfg := party_config(_catalog(), party_variant, party_format, party_difficulty)
	var n := (cfg["players"] as Array).size()
	if n < 2 or n > 4:
		Audio.sfx("ui_error")
		App.dialog("Party runs are for 2-4 players", "There are %d players (not spectating) in the session." % n, [{"label": "OK", "id": "ok"}], Callable())
		return
	var pr := _party_runs()
	var err := pr.start_new_as_host(cfg)
	if err != "":
		Audio.sfx("ui_error")
		App.dialog("Can't start a party run", err, [{"label": "OK", "id": "ok"}], Callable())
		return
	OnlineFlow.set_party(pr)
	UiNav.toast("Party run dealt: the others take their seats, then start it.", "success")
	_refresh(true)


func _claim_seat() -> void:
	if OnlineFlow.party != null:
		return
	var pr := _party_runs()
	var err := pr.claim()
	if err != "":
		Audio.sfx("ui_error")
		App.dialog("Can't take a seat", err, [{"label": "OK", "id": "ok"}], Callable())
		return
	OnlineFlow.set_party(pr)
	_refresh(true)


# --- input -----------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if is_top() and event.is_action_pressed("ui_alt"):
		get_viewport().set_input_as_handled()
		_alt_action()
		return
	super(event)
