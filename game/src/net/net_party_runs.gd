class_name NetPartyRuns
extends RefCounted
## Resuming a suspended co-op party run in an online/LAN session: the lobby path from a party
## save (RunStore slot party_<run id>) to a running CoopSession on every machine. The UI (online
## lobby) owns one of these per machine; tests drive it the same way.
##
##   host    open_as_host(run_id)   loads its party save, offers the run in the lobby
##                                  (Net.party_open: the run's players become seats, the host
##                                  takes its own) -> start_host() starts CoopSession.host_resume
##                                  over NetPartyTransport, typically once the members are back
##                                  (Net.member_ids() lists their seats). Members who come later
##                                  play as bots until their rejoin is applied.
##   member claim(seat)             the lobby offers run R: the member must hold R in its own party
##                                  save ("rejoins by run id") and asks for its seat (a seat it can
##                                  find by profile id / name, or the one the player picked);
##                                  once Net seats it, tick() starts CoopSession.member_join and
##                                  asks for its fighter back. The first state the host sends is
##                                  re-verified against the member's own save (check_resumed: same
##                                  run, follows from its decision log, continues the member's
##                                  log); if it does not, the member leaves the party run (failed).
##   both   tick(dt) every frame.
##
## Seat ids are the run's player ids, so CoopSession sees the member ids the run was played with;
## Net stamps and routes party messages by seat from the connection (authenticated senders).
## Runs that were not started online (non-numeric player ids) cannot be offered.

const HELLO_EVERY_MS := 1000

## A member left the party run because the host's run did not check out against its own save.
signal failed(reason: String)

var catalog: CampaignCatalog
var store: RunStore
var profile: Dictionary
var profile_id := ""
var session: CoopSession = null
var role := ""                     ## "" | "host" | "member"
var run_id := ""
var seat := ""
var state: Dictionary = {}         ## the run from this machine's own party save
var error := ""                    ## why the party run was left ("" = fine)
var _hello_ms := 0
var _checked := false


func _init(cat: CampaignCatalog, run_store: RunStore, prof: Dictionary) -> void:
	catalog = cat
	store = run_store
	profile = prof
	profile_id = str(prof.get("id", "default"))


static func slot_of(id: String) -> String:
	return "party_%s" % id


## The run's players as seats [{id, name, fighter}] ([] when an id is not an online member id).
static func seats_of(st: Dictionary) -> Array:
	var out: Array = []
	for p in st.get("players", []):
		if typeof(p) != TYPE_DICTIONARY or not NetProtocol.valid_seat_id(str((p as Dictionary).get("id", ""))):
			return []
		out.append({"id": str(p["id"]), "name": str(p.get("name", "")), "fighter": str(p.get("fighter", ""))})
	return out


## Which player of `st` this machine is: the only one with this profile id (narrowed by name
## when several share it), else the only one with this name; "" when it cannot tell.
static func seat_for(st: Dictionary, prof_id: String, player_name: String) -> String:
	var by_profile: Array = []
	var by_name: Array = []
	for p in st.get("players", []):
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var pd: Dictionary = p
		if str(pd.get("profile_id", "")) == prof_id and prof_id != "":
			by_profile.append(pd)
		if str(pd.get("name", "")) == player_name and player_name != "":
			by_name.append(pd)
	if by_profile.size() == 1:
		return str(by_profile[0]["id"])
	if by_profile.size() > 1:
		var both: Array = by_profile.filter(func(pd: Dictionary) -> bool: return str(pd.get("name", "")) == player_name)
		return str(both[0]["id"]) if both.size() == 1 else ""
	return str(by_name[0]["id"]) if by_name.size() == 1 else ""


func _player_name() -> String:
	var n := str(Settings.get_value("network.player_name"))
	return n if n != "" else str(profile.get("name", ""))


# =====================================================================================
# Host
# =====================================================================================

## Host: offers the suspended party run `id` from this machine's party save in the lobby.
## `my_seat` = which of the run's players the host is ("" = find it by profile id / name).
## Returns "" or a UI-ready reason.
func open_as_host(id: String, my_seat := "") -> String:
	if not Net.is_host():
		return "Host a session first: party runs are resumed from an online or LAN lobby."
	var r := store.load_slot(profile_id, slot_of(id), catalog)
	if not bool(r.get("ok", false)):
		return str(r.get("error", "The party run could not be loaded."))
	var st: Dictionary = r["state"]
	if (st.get("players", []) as Array).size() < 2:
		return "This save is not a party run."
	var seats := seats_of(st)
	if seats.is_empty():
		return "This run was not started in an online session, so it cannot be resumed online."
	var me := my_seat if my_seat != "" else seat_for(st, profile_id, _player_name())
	if me == "":
		return "Pick which player you are in this run."
	var err := Net.party_open(str(st.get("run_id", id)), seats, me, RunStore.summarize(st))
	if err != "":
		return err
	role = "host"
	run_id = str(st.get("run_id", id))
	seat = me
	state = st
	return ""


## Host: deals a NEW party run for the players in the session now (`cfg` as for
## CoopSession.host_new; cfg.players ids = their session ids, which become the run's member ids)
## and offers it in the lobby. The CoopSession starts at once; members claim their seats without
## needing a save (the offer says "new").
func start_new_as_host(cfg: Dictionary) -> String:
	if not Net.is_host():
		return "Host a session first."
	if session != null or not Net.party().is_empty():
		return "A party run is already on offer."
	var s := CoopSession.host_new(NetPartyTransport.new(), catalog, cfg, store, profile)
	if s.ctrl == null:
		return "The party run could not be dealt."
	var st: Dictionary = s.ctrl.state
	var seats := seats_of(st)
	if seats.is_empty():
		return "Every member needs an online member id."
	var info := RunStore.summarize(st)
	info["new"] = true
	var err := Net.party_open(str(st.get("run_id", "")), seats, Net.local_member_id(), info)
	if err != "":
		s.transport.close()
		return err
	session = s
	role = "host"
	run_id = str(st.get("run_id", ""))
	seat = Net.local_member_id()
	state = st
	return ""


## Host: starts the party's CoopSession from the loaded run (members seated by now take their
## fighters at once; later ones rejoin at the next node boundary).
func start_host() -> String:
	if role != "host" or state.is_empty():
		return "Open a party run first."
	if session != null:
		return ""
	if Net.local_member_id() != seat:
		return "The party run is no longer open in this session."
	session = CoopSession.host_resume(NetPartyTransport.new(), catalog, state, store, profile)
	return ""


## Host: the seats that are still empty or whose player is away.
func missing_seats() -> Array:
	var out: Array = []
	for s in Net.party().get("seats", []):
		if str(s.get("id", "")) != seat and (int(s.get("session", 0)) <= 0 or not bool(s.get("connected", false))):
			out.append(str(s.get("id", "")))
	return out


# =====================================================================================
# Member
# =====================================================================================

## Member: claims this player's seat in the run the host offers. A resumed run must be in the
## player's own party save (its seat is found there); a NEW run (offer info "new") needs none -
## its seats are the session ids it was dealt with. `my_seat` = the seat the player picked
## ("" = find it). Returns "" once the claim is on its way (Net seats us, or reports
## party_claim_failed).
func claim(my_seat := "") -> String:
	var pt := Net.party()
	if pt.is_empty():
		return "The host has not offered a party run."
	var id := str(pt.get("run_id", ""))
	var fresh := bool((pt.get("info", {}) as Dictionary).get("new", false))
	var r := store.load_slot(profile_id, slot_of(id), catalog)
	var own: Dictionary = {}
	if bool(r.get("ok", false)):
		own = r["state"]
	elif not fresh:
		return "You do not have this party run in your saves (%s)." % str(r.get("error", ""))
	# a new run's seats are the session ids it was dealt with; a resumed one is matched by save
	var me := my_seat
	if me == "":
		me = str(Net.local_peer_id()) if fresh and own.is_empty() else seat_for(own, profile_id, _player_name())
	if me == "":
		return "Pick which player you are in this run."
	var known := false
	for s in pt.get("seats", []):
		known = known or str(s.get("id", "")) == me
	if not known:
		return "That player is not part of the host's run."
	var err := Net.party_claim(me)
	if err != "":
		return err
	role = "member"
	run_id = id
	seat = me
	state = own
	_checked = false
	error = ""
	return ""


## Member side check of the run the host resumed, against this member's own party save: the
## same run (id + seed), a state that follows from its own decision log (RunController.verify),
## and a log that continues ours - the host may be further along (it held a newer checkpoint),
## never behind or different. Returns "" or a UI-ready reason.
static func check_resumed(cat: CampaignCatalog, own: Dictionary, host_state: Dictionary) -> String:
	if str(host_state.get("run_id", "")) != str(own.get("run_id", "")) or int(host_state.get("seed", 0)) != int(own.get("seed", 0)):
		return "The host's run is not the one in your save."
	var v := RunController.verify(cat, host_state)
	if not bool(v["ok"]):
		return "The host's run does not check out (%s)." % str(v["error"])
	var mine: Array = own.get("log", [])
	var theirs: Array = host_state.get("log", [])
	if theirs.size() < mine.size():
		return "The host's save is older than yours (%d decisions, you have %d): the newest save should host." % [theirs.size(), mine.size()]
	for i in mine.size():
		if Saves.checksum(mine[i]) != Saves.checksum(theirs[i]):
			return "The host's run differs from your save at decision %d." % (i + 1)
	return ""


# =====================================================================================
# Both
# =====================================================================================

## Every frame: a seated member joins the host's run (and repeats its hello until the run
## arrives - the host may start its session after we sat down); the CoopSession ticks.
func tick(dt: float) -> void:
	if role == "member" and session == null and Net.party_seat() == seat and seat != "":
		var host_seat := str(Net.party().get("host_seat", ""))
		if host_seat != "":
			session = CoopSession.member_join(NetPartyTransport.new(), catalog, host_seat, store, profile)
			session.rejoin()
			_hello_ms = Time.get_ticks_msec()
	if session == null:
		return
	if role == "member" and session.ctrl == null and Time.get_ticks_msec() - _hello_ms >= HELLO_EVERY_MS:
		_hello_ms = Time.get_ticks_msec()
		session.transport.send(session.host_id, "hello", {"player": session.me})
		session.rejoin()
	if role == "member" and session.ctrl != null and not _checked:
		_checked = true
		# a member of a new run has no save of it yet: CoopSession checks every ticket by its log
		var why := "" if state.is_empty() else check_resumed(catalog, state, session.ctrl.state)
		if why != "":
			error = why
			close()
			failed.emit(why)
			return
	session.tick(dt)


## Leaves the party run (the CoopSession's transport detaches; the seat is given up).
func close() -> void:
	if session != null and session.transport != null:
		session.transport.close()
	session = null
	if role == "host":
		Net.party_close()
	elif role == "member":
		Net.party_leave()
	role = ""
