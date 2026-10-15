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
##                                  once Net seats it, tick() starts CoopSession.member_join (the
##                                  member re-verifies the host's state against its own save) and
##                                  asks for its fighter back.
##   both   tick(dt) every frame.
##
## Seat ids are the run's player ids, so CoopSession sees the member ids the run was played with;
## Net stamps and routes party messages by seat from the connection (authenticated senders).
## Runs that were not started online (non-numeric player ids) cannot be offered.

const HELLO_EVERY_MS := 1000

var catalog: CampaignCatalog
var store: RunStore
var profile: Dictionary
var profile_id := ""
var session: CoopSession = null
var role := ""                     ## "" | "host" | "member"
var run_id := ""
var seat := ""
var state: Dictionary = {}         ## host: the run as loaded from its party save
var _hello_ms := 0


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

## Member: claims this player's seat in the run the host offers. The player must hold that run
## in its own party save; `my_seat` = the seat the player picked ("" = find it). Returns "" once
## the claim is on its way (Net seats us, or reports party_claim_failed).
func claim(my_seat := "") -> String:
	var pt := Net.party()
	if pt.is_empty():
		return "The host has not offered a party run."
	var id := str(pt.get("run_id", ""))
	var r := store.load_slot(profile_id, slot_of(id), catalog)
	if not bool(r.get("ok", false)):
		return "You do not have this party run in your saves (%s)." % str(r.get("error", ""))
	var me := my_seat if my_seat != "" else seat_for(r["state"], profile_id, _player_name())
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
