class_name OnlineFlow
extends RefCounted
## UI-side lifecycle of an online session started from the Online screen (MatchFlow's online
## counterpart). Screens are cleared when a match starts (the listen host's MatchScene, a
## client's NetMatchScene), so something outside the screens brings the UI back:
##   match ended         -> the results overlay (online variant: back to the lobby / leave);
##                          a co-op party run's fight has no versus results card
##   returned to lobby   -> the lobby screen - or, during an online party run, the campaign screen
##                          the shared run calls for (CoopFlow)
##   session lost        -> the Online screen with the reason (host left, kicked, timeout, shut
##                          down); a voluntary leave just ends quietly. A party run in progress
##                          stays in the party save (the dialog says how to resume it).
## Only sessions the UI started are followed (`active`), so scripted/test sessions that never
## opened the Online screen are left alone. Signal handlers are static methods (no lambdas kept
## in static state - Godot 4.5.1 crashes at exit on those).
## Party runs (docs/NETWORKING.md §14 "Party runs played online"): set_party() hands this machine's
## NetPartyRuns to a ticker under Net and to a CoopFlow, which takes the UI from the lobby to the
## campaign screens once the run is on; drop_party() leaves it. Members send the host their
## Cannery levels once per session (for Fight Camp deals).

static var active := false
static var party_mode := false           ## the host chose "Co-op party run" (the lobby leads with it)
static var party: NetPartyRuns = null    ## this machine's party run in the session (lobby)
static var coop: CoopFlow = null         ## the campaign screens' flow for that party run


## Follows the current session from now on (Online screen: after host() / join()).
static func begin() -> void:
	active = true
	_connect(Net.match_ended, OnlineFlow._on_match_ended)
	_connect(Net.returned_to_lobby, OnlineFlow._on_returned_to_lobby)
	_connect(Net.disconnected, OnlineFlow._on_disconnected)
	_connect(Net.joined, OnlineFlow._on_joined)
	_connect(Net.app_request, OnlineFlow._on_app_request)
	_connect(Net.session_state_changed, OnlineFlow._on_session_state)


## The session ended without a disconnect notice - this machine left it some other way (the pause
## menu's Quit during a fight, a host closing it): stop following it. A client's lost connection
## arrives as `disconnected` first (with its dialog) and has already ended the flow. Checked a
## frame later: Net.host()/join() pass through "offline" when they replace an earlier session.
static func _on_session_state(state: String) -> void:
	if active and state == "offline":
		OnlineFlow._end_if_offline.call_deferred()


static func _end_if_offline() -> void:
	if active and Net.session_state() == "offline":
		end(false)


## Stops following (the player left on purpose, or the session is over). `withdraw` false when the
## whole session is being left: a host's party run is then not withdrawn first (see drop_party).
static func end(withdraw := true) -> void:
	active = false
	party_mode = false
	drop_party(withdraw)
	NetPartyRuns.forget_meta()


static func _connect(sig: Signal, cb: Callable) -> void:
	if not sig.is_connected(cb):
		sig.connect(cb)


## This machine's party run in the session from now on (dealt, offered, or a seat claimed): it is
## ticked whatever the screen, and CoopFlow follows it into the campaign screens.
static func set_party(pr: NetPartyRuns) -> void:
	if party != null and party != pr:
		drop_party()
	party = pr
	pr.start_ticking()
	if coop == null or coop.runs != pr:
		coop = CoopFlow.for_party(pr)


## Leaves this machine's party run (the run itself stays in the party saves). A host leaving the
## session passes `withdraw` false: the members then learn it from the session ending, with the
## note that the run is saved, instead of first seeing the run withdrawn.
static func drop_party(withdraw := true) -> void:
	if coop != null:
		coop.detach()
		coop = null
	if party != null:
		party.close(withdraw)
		party = null


## True while an online party run is on (the campaign screens drive the UI, not the lobby).
static func party_live() -> bool:
	return coop != null and party != null and party.is_live()


## Leaves the session and returns to the Online screen (or the main menu).
static func leave(to_menu := false) -> void:
	end(false)
	MatchFlow.set_paused(false)
	if Net.is_session_active():
		Net.leave()
	App.goto("main_menu")
	if not to_menu and App.has_screen("online"):
		App.push("online")


static func _on_match_ended(result: Dictionary) -> void:
	if not active or not App.has_screen("results"):
		return
	if bool((result.get("entry", {}) as Dictionary).get("campaign", false)):
		return   # a party run's fight: the run's own screens follow (reward, summary)
	# the local player's fighter (host: its own; client: from MATCH_START)
	var me := Net.local_fighter()
	var fighters: Array = []
	for f in result.get("fighters", []):
		var d: Dictionary = (f as Dictionary).duplicate()
		d["kind"] = "player" if int(d.get("index", -1)) == me and me >= 0 else "remote"
		fighters.append(d)
	App.push("results", {"result": result, "config": {"online": true, "fighters": fighters,
		"next_in": int(result.get("next_in", 0)), "ui": {"mode": "online"}}})


static func _on_returned_to_lobby() -> void:
	if not active:
		return
	MatchFlow.set_paused(false)
	if party_live():
		coop.show_current()
		return
	App.goto("lobby")


static func _on_joined(_welcome: Dictionary) -> void:
	if active:
		NetPartyRuns.send_meta(Profiles.current)


static func _on_app_request(from_id: int, type: String, payload: Dictionary) -> void:
	if active and type == NetPartyRuns.META_REQUEST:
		NetPartyRuns.on_request(from_id, type, payload, CampaignFlow.make_catalog(CampaignFlow.dev_tools()))


static func _on_disconnected(reason: Dictionary) -> void:
	if not active:
		return
	var had_run := party != null and party.session != null and party.session.ctrl != null
	end()   # also drops this machine's party run of the lost session
	MatchFlow.set_paused(false)
	var code := int(reason.get("code", 0))
	App.goto("main_menu")
	if App.has_screen("online"):
		App.push("online")
	if code == NetProtocol.R_LEFT:
		return
	if had_run:
		var r := reason.duplicate(true)
		var details: Array = (r.get("details", []) as Array).duplicate()
		details.append("Your party run is saved at its last stop. Join the session again and rejoin it from the lobby, or host it yourself (Co-op party run > Suspended run) if the host is gone.")
		r["details"] = details
		show_reason(r)
		return
	show_reason(reason)


## A UI-ready reason (NetProtocol.describe: title, message, details) as an error dialog.
static func show_reason(reason: Dictionary) -> void:
	var body := str(reason.get("message", ""))
	var details: Array = reason.get("details", [])
	if not details.is_empty():
		body += "\n\n" + "\n".join(PackedStringArray(details.slice(0, 8).map(func(x) -> String: return "•  " + str(x))))
	App.dialog(str(reason.get("title", "Disconnected")), body, [{"label": "OK", "id": "ok"}], Callable())
