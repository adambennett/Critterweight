class_name CoopFlow
extends CampaignFlow
## CampaignFlow for an online party run (docs/CAMPAIGN_SYSTEMS.md "Online party runs"): the same
## campaign screens - map and route vote, reward picks, events, shop, rest, run summary - bound to
## this machine's view of the shared run: the host's authoritative RunController on the host, the
## replica CoopSession keeps from the host's messages on a member. Every decision goes through
## CoopSession.act (the host applies it with exactly the rules of a member's intent; a member sends
## it and the screen waits for the host's answer), so a member can never change the shared run by
## itself.
## The screens follow the shared run: when it changes, the current screen is rebuilt if THIS
## player's part changed (their picks, their shop, the node...), otherwise only the party line
## updates (others' purchases, votes) so focus does not jump; when the run calls for another
## screen the flow moves there - except while a screen shows an outcome the player has not
## acknowledged (an event's result) or a dialog is open.
## Fights are played on the session (NetPartyRuns + NetServer.start_campaign_match): while one is
## presented the screens wait, and OnlineFlow brings the flow back when the session returns to its
## lobby. A ref timeout (pause menu, during fights) uses this player's CoopSession budget.
## Host-only: suspending the run for everyone; retrying or forfeiting a fight that could not be
## set up. Captain: "move on" for absent players (after the absent time). Members: leaving the
## party run (a bot takes over; they rejoin from the lobby by run id).

const SCREENS := ["run_map", "reward", "event", "shop", "rest", "run_summary"]

var runs: NetPartyRuns
var session: CoopSession = null
var started := false               ## the campaign screens took over from the lobby
var _queued := false
var _force := false
var _key := ""
var _event_seen := ""
var _bar_t := 0.0
var _overlay: CanvasLayer = null


static func for_party(r: NetPartyRuns) -> CoopFlow:
	var f := CoopFlow.new()
	f.runs = r
	f.catalog = r.catalog
	f.store = r.store
	r.ticked.connect(f._on_ticked)
	r.ended.connect(f._on_ended)
	r.failed.connect(f._on_ended)
	r.fight_problem.connect(f._on_fight_problem)
	f._attach()
	return f


func is_party() -> bool:
	return true


func is_host() -> bool:
	return session != null and session.is_host()


## Stops following the party run (OnlineFlow.end / the run was left).
func detach() -> void:
	if runs != null:
		for pair in [[runs.ticked, _on_ticked], [runs.ended, _on_ended], [runs.failed, _on_ended], [runs.fight_problem, _on_fight_problem]]:
			if (pair[0] as Signal).is_connected(pair[1]):
				(pair[0] as Signal).disconnect(pair[1])
	_unhook()
	_remove_overlay()


func _attach() -> void:
	if runs == null or runs.session == session:
		return
	_unhook()
	session = runs.session
	if session != null:
		session.changed.connect(_on_changed)
		session.notice.connect(_on_notice)
		session.run_finished.connect(_on_run_finished)
	_sync()


func _unhook() -> void:
	if session != null:
		for pair in [[session.changed, _on_changed], [session.notice, _on_notice], [session.run_finished, _on_run_finished]]:
			if (pair[0] as Signal).is_connected(pair[1]):
				(pair[0] as Signal).disconnect(pair[1])
	session = null


func _sync() -> void:
	if session != null and session.ctrl != null:
		ctrl = session.ctrl
		me = session.me


func save(_st = null) -> void:
	pass     # the party's host saves the run; every member keeps the host's tickets (CoopSession)


# =============================================================================================
# Following the shared run
# =============================================================================================

func _on_ticked(dt: float) -> void:
	_attach()
	if session == null or session.ctrl == null:
		return
	if not started and session.is_live() and OnlineFlow.active and not _presenting():
		show_current()
	_bar_t += dt
	if _bar_t >= 0.5:
		_bar_t = 0.0
		var top := App.top_screen()
		if started and top != null and SCREENS.has(top.screen_name):
			_update_strip(top)
			if top.has_method("refresh_party"):
				top.call("refresh_party")
			# safety net: a change that arrived while a dialog was open (act intro...) is caught up
			# once the screen is free again
			if not _presenting() and top.get("flow") == self and not CampaignUI.has_modal(top) \
					and not (top.has_method("holds_screen") and bool(top.call("holds_screen"))) and _screen_name(current_screen()) != top.screen_name:
				show_current()
	_update_overlay()


## The screen a current_screen() answer is shown on ("fight": the map until the match starts).
static func _screen_name(want: String) -> String:
	match want:
		"fight":
			return "run_map"
		"summary":
			return "run_summary"
	return want


func _on_changed(reason: String) -> void:
	if reason == "paused" and _presenting():
		Audio.announce_trigger("time", {"kind": "ref_timeout"})     # Barnaby calls it on every machine
	_schedule(reason in ["refused", "live", "host_migrated"])


func _schedule(force := false) -> void:
	_force = _force or force
	if not _queued:
		_queued = true
		_refresh.call_deferred()


## True while a fight of the session is on screen (the host's MatchScene, a member's NetMatchScene).
func _presenting() -> bool:
	return Net.session_state() in ["match", "results"]


func _refresh() -> void:
	_queued = false
	var force := _force
	_force = false
	_sync()
	if not started or session == null or session.ctrl == null or _presenting():
		return
	var top := App.top_screen()
	if top == null or not SCREENS.has(top.screen_name) or top.get("flow") != self:
		return      # another screen is up (pause, settings, a dialog): it stays
	_update_strip(top)
	if CampaignUI.has_modal(top) or (top.has_method("holds_screen") and bool(top.call("holds_screen"))):
		return
	var want := _screen_name(current_screen())
	if want != top.screen_name:
		show_current()
		return
	var k := _view_key(want)
	if k != _key or force:
		_key = k
		top.call("_build")
		_update_strip(top)
	elif top.has_method("refresh_party"):
		top.call("refresh_party")


## What this player's current screen shows (rebuilt only when it changes).
func _view_key(screen: String) -> String:
	var parts: Array = [screen, ctrl.phase(), str(ctrl.state.get("position", "")), int(ctrl.state.get("act", 1)),
		ctrl.player(me), ctrl.pending_for(me), runs.fight_error if is_host() else ""]
	match screen:
		"event":
			parts.append(ctrl.event_view(me))
			parts.append(session.last_event)
		"shop":
			parts.append(ctrl.shop_view(me))
		"rest":
			parts.append(ctrl.session().get("rest", {}).get(me, {}))
			parts.append(ctrl.rest_options(me))
		"run_summary":
			parts.append(report)
	return str(hash(var_to_str(parts)))


func current_screen() -> String:
	if session == null or session.ctrl == null or not session.is_live():
		return "lobby"
	_sync()
	if not ctrl.is_over() and ctrl.phase() != "fight":
		var le := session.last_event
		if not le.is_empty() and str(le.get("node", "")) == str(ctrl.state.get("position", "")) and _event_seen != str(le["node"]):
			return "event"
	return super.current_screen()


## Shows the screen for the shared run's current state (the lobby until the run is on).
func show_current() -> void:
	_sync()
	if session == null or session.ctrl == null or not session.is_live():
		var top0 := App.top_screen()
		if top0 == null or top0.screen_name != "lobby":
			App.goto("lobby")
		return
	if _presenting():
		return
	started = true
	var screen := current_screen()
	if screen == "summary":
		finish()
		return
	var p := {"flow": self}
	if screen == "fight":
		# the host plays it on the session in a moment; the map says so meanwhile
		screen = "run_map"
		p["fight_pending"] = true
		if is_host() and runs.fight_error != "":
			p["fight_error"] = runs.fight_error
	var s := App.goto(screen, p)
	_key = _view_key(screen)
	if s != null:
		_update_strip(s)


func ack_event() -> void:
	_event_seen = str(ctrl.state.get("position", "")) if ctrl else ""


func party_event() -> Dictionary:
	return session.last_event.duplicate() if session != null else {}


func vote_view() -> Dictionary:
	return session.vote_view() if session != null else {}


# =============================================================================================
# Decisions (CoopSession.act: applied on the host, sent from a member)
# =============================================================================================

func error_text() -> String:
	return session.last_error if session != null else "not in a party run"


func _act(type: String, payload: Dictionary) -> bool:
	if session == null or session.ctrl == null:
		return false
	return session.act(type, payload)


func do_claim(rid: String, choice: String) -> bool:
	return _act("pick", {"rid": rid, "choice": choice})


func do_reroll(rid: String) -> bool:
	return _act("reroll", {"rid": rid})


func do_event(choice: String) -> bool:
	return _act("event_choice", {"choice": choice})


func do_shop_buy(slot: String) -> bool:
	return _act("shop_buy", {"slot": slot})


func do_shop_service() -> bool:
	return _act("shop_service", {})


func do_shop_sell(item: String) -> bool:
	return _act("shop_sell", {"item": item})


func do_shop_leave() -> bool:
	return _act("shop_leave", {})


func do_rest(option: String) -> bool:
	return _act("rest", {"option": option})


func do_consume(item: String) -> bool:
	return _act("consume", {"item": item})


func do_learn(move: String, source: String) -> bool:
	return _act("learn", {"move": move, "source": source})


func do_equip(loadout: Array) -> bool:
	return _act("equip", {"loadout": loadout.duplicate()})


func do_drill(move: String, style: String, source: String) -> bool:
	return _act("drill", {"move": move, "style": style, "source": source})


## The map: a reachable stop is this player's VOTE (the party's majority decides, the Captain
## breaks ties - CoopSession). True once the vote is cast / sent.
func choose_node(id: String) -> bool:
	return _act("vote", {"node": id})


## The Captain moves on for absent players (refused before the absent time - the reason says so).
func move_on() -> bool:
	return _act("move_on", {})


## A ref timeout for the running fight (this player's budget): true when called / sent.
func call_timeout() -> bool:
	return _act("pause", {})


func end_timeout() -> bool:
	return _act("resume", {})


func in_fight() -> bool:
	return session != null and session.ctrl != null and session.ctrl.phase() == "fight" and _presenting()


func launch_fight() -> void:
	show_current()


func forfeit_fight() -> void:
	if is_host():
		runs.forfeit_fight()


func retry_fight() -> void:
	if is_host():
		runs.retry_fight()
		show_current()


## Host: suspends the run for everyone (it stays in every member's party save and the host's;
## resume it from the lobby). Member: leaves the party run (a bot plays their fighter; they can
## rejoin from the lobby by run id). Both go back to the lobby.
func suspend() -> void:
	if session != null and is_host():
		session.transport.send("", "notice", {"text": "The host suspended the party run. It is saved; rejoin when they offer it again."})
	OnlineFlow.drop_party()
	App.goto("lobby")


func abandon() -> void:
	suspend()


## The run is over: CoopSession credited this player's own profile (run_finished); the summary.
func finish() -> void:
	App.goto("run_summary", {"flow": self})


func restart(_same_seed: bool, _dose_delta := 0) -> void:
	back_to_lobby()


## After the run: back to the session's lobby (the party run is closed on this machine).
func back_to_lobby() -> void:
	OnlineFlow.drop_party()
	App.goto("lobby")


# =============================================================================================
# Party line, notices, fight overlay
# =============================================================================================

## One status line: every member's state at this node, the Captain, the vote and its timer.
func party_text() -> String:
	if session == null or session.ctrl == null:
		return ""
	var c := session.ctrl
	var vv := session.vote_view()
	var votes: Dictionary = vv.get("votes", {})
	var bits: Array = []
	for p in c.players():
		var pid := str(p["id"])
		var tags: Array = []
		if pid == session.me:
			tags.append("you")
		if pid == c.captain():
			tags.append("Captain")
		if bool(p.get("bot", false)):
			tags.append("bot" if not bool(p.get("connected", true)) else "away")
		var hp := "HP %d/%d" % [int(ceil(float(p.get("hp", 0)))), int(c.max_hp(p))]
		var doing := _doing(c, pid, vv, votes)
		bits.append("%s%s %s%s" % [str(p.get("name", pid)), (" (%s)" % ", ".join(tags)) if not tags.is_empty() else "", hp,
			(" · " + doing) if doing != "" else ""])
	var line := "PARTY  " + "   |   ".join(PackedStringArray(bits))
	if not vv.is_empty():
		line += "   |   %s %d s" % ["GROUP VOTE" if bool(vv.get("event", false)) else "ROUTE VOTE", ceili(float(vv.get("left", 0.0)))]
	if is_host() and runs.fight_error != "":
		line += "   |   FIGHT ON HOLD"
	return line


func _doing(c: RunController, pid: String, vv: Dictionary, votes: Dictionary) -> String:
	if not vv.is_empty():
		if votes.has(pid):
			return "voted %s" % _option_name(c, str(votes[pid]), bool(vv.get("event", false)))
		return "voting" if (vv.get("voters", []) as Array).has(pid) else ""
	match c.phase():
		"shop":
			return "done" if bool(c.shop_view(pid).get("done", true)) else "shopping"
		"rest":
			return "done" if bool(c.session().get("rest", {}).get(pid, {}).get("done", true)) else "resting"
		"reward":
			return "picking" if not c.pending_for(pid).is_empty() else "done"
		"event":
			var ev: Dictionary = c.session().get("event", {})
			if str(ev.get("decider", "")) == pid:
				return "deciding"
		"fight":
			return "fighting"
	if not c.pending_for(pid).is_empty():
		return "picking"
	return ""


func _option_name(c: RunController, opt: String, event: bool) -> String:
	if event:
		for ch in c.event_view(me).get("choices", []):
			if str((ch as Dictionary).get("id", "")) == opt:
				return str((ch as Dictionary).get("label", opt))
		return opt
	var t := c.visible_type(opt)
	return str(CampaignUI.NODE_NAMES.get(t, t)) if t != "mystery" else "?"


func _update_strip(s: Control) -> void:
	if s == null or not is_instance_valid(s) or not s.has_meta("party_strip"):
		return
	var l = s.get_meta("party_strip")
	if l is Label and is_instance_valid(l):
		(l as Label).text = party_text()


func _on_notice(text: String) -> void:
	if started and OnlineFlow.active and text != "":
		UiNav.toast(text, "info", 4.0)


func _on_run_finished(rep: Dictionary) -> void:
	report = rep
	# CoopSession credited the profile dictionary the party run was given: the active profile
	if runs != null and is_same(runs.profile, Profiles.current):
		Profiles.save()
	_schedule(true)


func _on_ended(reason: String) -> void:
	OnlineFlow.drop_party()
	if reason != "":
		UiNav.toast(reason, "info", 6.0)
	var top := App.top_screen()
	if top != null and (SCREENS.has(top.screen_name) or top.screen_name == "lobby"):
		App.goto("lobby")


func _on_fight_problem(_why: String) -> void:
	_force = true
	if started and not _presenting():
		show_current()


## REF TIMEOUT banner over a presented party fight (host MatchScene / member NetMatchScene).
func _update_overlay() -> void:
	if not _presenting() or session == null:
		_remove_overlay()
		return
	var scene = App.current_scene
	if scene == null or not is_instance_valid(scene):
		return
	if _overlay == null or not is_instance_valid(_overlay) or _overlay.get_parent() != scene:
		_remove_overlay()
		_overlay = CanvasLayer.new()
		_overlay.name = "PartyFightOverlay"
		_overlay.layer = 6
		var l := Label.new()
		l.name = "Banner"
		l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		l.offset_top = 262
		l.offset_left = -520
		l.offset_right = 520
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 40)
		l.add_theme_constant_override("outline_size", 10)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		l.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overlay.add_child(l)
		scene.add_child(_overlay)
	var pv := session.pause_view()
	var banner := _overlay.get_node("Banner") as Label
	banner.visible = bool(pv.get("paused", false))
	if banner.visible:
		banner.text = "REF TIMEOUT  ·  called by %s  ·  %d s" % [session.name_of(str(pv.get("by", ""))), ceili(float(pv.get("left", 0.0)))]


func _remove_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
