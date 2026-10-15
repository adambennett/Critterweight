class_name OnlineFlow
extends RefCounted
## UI-side lifecycle of an online session started from the Online screen (MatchFlow's online
## counterpart). Screens are cleared when a match starts (the listen host's MatchScene, a
## client's NetMatchScene), so something outside the screens brings the UI back:
##   match ended         -> the results overlay (online variant: back to the lobby / leave)
##   returned to lobby   -> the lobby screen
##   session lost        -> the Online screen with the reason (host left, kicked, timeout, shut
##                          down); a voluntary leave just ends quietly
## Only sessions the UI started are followed (`active`), so scripted/test sessions that never
## opened the Online screen are left alone. Signal handlers are static methods (no lambdas kept
## in static state - Godot 4.5.1 crashes at exit on those).

static var active := false
static var party_mode := false           ## the host chose "Co-op party run" (the lobby leads with it)
static var party: NetPartyRuns = null    ## this machine's party run in the session (lobby)


## Follows the current session from now on (Online screen: after host() / join()).
static func begin() -> void:
	active = true
	_connect(Net.match_ended, OnlineFlow._on_match_ended)
	_connect(Net.returned_to_lobby, OnlineFlow._on_returned_to_lobby)
	_connect(Net.disconnected, OnlineFlow._on_disconnected)


## Stops following (the player left on purpose, or the session is over).
static func end() -> void:
	active = false
	party_mode = false
	if party != null:
		party.close()
		party = null


static func _connect(sig: Signal, cb: Callable) -> void:
	if not sig.is_connected(cb):
		sig.connect(cb)


## Leaves the session and returns to the Online screen (or the main menu).
static func leave(to_menu := false) -> void:
	end()
	MatchFlow.set_paused(false)
	if Net.is_session_active():
		Net.leave()
	App.goto("main_menu")
	if not to_menu and App.has_screen("online"):
		App.push("online")


static func _on_match_ended(result: Dictionary) -> void:
	if not active or not App.has_screen("results"):
		return
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
	App.goto("lobby")


static func _on_disconnected(reason: Dictionary) -> void:
	if not active:
		return
	active = false
	MatchFlow.set_paused(false)
	var code := int(reason.get("code", 0))
	App.goto("main_menu")
	if App.has_screen("online"):
		App.push("online")
	if code == NetProtocol.R_LEFT:
		return
	show_reason(reason)


## A UI-ready reason (NetProtocol.describe: title, message, details) as an error dialog.
static func show_reason(reason: Dictionary) -> void:
	var body := str(reason.get("message", ""))
	var details: Array = reason.get("details", [])
	if not details.is_empty():
		body += "\n\n" + "\n".join(PackedStringArray(details.slice(0, 8).map(func(x) -> String: return "•  " + str(x))))
	App.dialog(str(reason.get("title", "Disconnected")), body, [{"label": "OK", "id": "ok"}], Callable())
