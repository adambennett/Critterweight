class_name NetPartyRuns
extends RefCounted
## A co-op party run played online/LAN: from the lobby (a new run, or a suspended one from a party
## save) to a running CoopSession on every machine, and its fights played as matches of the same
## session. The UI (online lobby, campaign screens through CoopFlow) owns one of these per machine;
## tests drive it the same way.
##
##   host    start_new_as_host(cfg)  deals a NEW run for the session's players and offers it in the
##                                   lobby (seats = their session ids); the CoopSession exists at
##                                   once but is HELD (nothing is decided) until start_host()
##           open_as_host(run_id)    loads its party save, offers the run in the lobby
##                                   (Net.party_open: the run's players become seats, the host takes
##                                   its own) -> start_host() resumes CoopSession.host_resume over
##                                   NetPartyTransport, typically once the members are back
##                                   (Net.member_ids() lists their seats). Members who come later
##                                   play as bots until their rejoin is applied.
##           fights                  whenever the run is at a fight, the host builds the match from
##                                   the run (RunController.match_config: every member's fighter with
##                                   their build and carried HP, the encounter, the party format) and
##                                   plays it on the session (NetServer.start_campaign_match): its own
##                                   fighter locally, each connected member's from their own input
##                                   stream, absent members' by the run's bots (tier capped at
##                                   Contender). The authoritative result goes into
##                                   CoopSession.complete_fight; members verify the run that follows
##                                   from it against their decision logs (tickets). A fight the host's
##                                   game never finished is played again from its start.
##           ref timeouts            CoopSession's pause budget freezes the running match
##                                   (NetServer.set_frozen) for everyone.
##   member  claim(seat)             the lobby offers run R: the member must hold R in its own party
##                                   save ("rejoins by run id") and asks for its seat (a seat it can
##                                   find by profile id / name, or the one the player picked); a NEW
##                                   run's seats are the session ids it was dealt with. Once Net seats
##                                   it, tick() starts CoopSession.member_join and asks for its
##                                   fighter back. The first state the host sends is re-verified
##                                   against the member's own save (check_resumed); if it does not
##                                   check out, the member leaves the party run (failed).
##   both    tick(dt) every frame - start_ticking() does that from a node under Net, whatever screen
##           is up (lobby, campaign screens, a fight).
##
## Seat ids are the run's player ids, so CoopSession sees the member ids the run was played with;
## Net stamps and routes party messages by seat from the connection (authenticated senders).
## Runs that were not started online (non-numeric player ids) cannot be offered.
## Fight Camp: each member's own Cannery levels (FightCamp.meta_levels of their profile) go to the
## host before the deal (request "party.meta", clamped to the installed upgrades' levels) - the
## design's "each player's own Cannery upgrades apply to their own fighter".

const HELLO_EVERY_MS := 1000
const FIGHT_RESULTS_S := 4         ## seconds the end of a campaign fight stays on screen
const META_REQUEST := "party.meta"

## A member left the party run because the host's run did not check out against its own save.
signal failed(reason: String)
## Host: the run's fight could not be set up (UI-ready reason); the run waits at the fight until
## retry_fight() or forfeit_fight().
signal fight_problem(reason: String)
## Member: the host took the run out of the lobby (suspended it); this machine left it. The run
## stays in the party save.
signal ended(reason: String)
## After every tick (UI glue updates timers from it).
signal ticked(dt: float)

static var _member_meta := {}      ## host: session player id -> clamped Cannery levels (Fight Camp)

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
var fight_running := false         ## host: a campaign fight of this run is being played on the session
var fight_error := ""              ## host: why the pending fight could not be started
var fights_played := 0             ## host: fights played on the session (results applied)
var _fight_key := ""
var _hello_ms := 0
var _checked := false
var _ticker: Node = null


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


## This machine's player in the saved run `st`: the seat its own party save remembers (written
## whenever the run was saved here), else by profile id / name (seat_for); "" = cannot tell.
func my_seat_in(st: Dictionary) -> String:
	var kept := store.party_seat(profile_id, slot_of(str(st.get("run_id", ""))))
	if kept != "":
		for p in st.get("players", []):
			if typeof(p) == TYPE_DICTIONARY and str((p as Dictionary).get("id", "")) == kept:
				return kept
	return seat_for(st, profile_id, _player_name())


# =====================================================================================
# Cannery levels of the members (Fight Camp)
# =====================================================================================

## Member: tells the host this player's Cannery levels (once per session; the host keeps them
## for a Fight Camp deal). `prof`: the active profile.
static func send_meta(prof: Dictionary) -> void:
	Net.request(META_REQUEST, {"fight_camp": FightCamp.meta_levels(prof)})


## Host: a member's request (Net.app_request). Returns true if it was a party.meta request.
static func on_request(from_id: int, type: String, payload: Dictionary, cat: CampaignCatalog) -> bool:
	if type != META_REQUEST:
		return false
	var lv = payload.get("fight_camp", {})
	_member_meta[from_id] = clamp_meta(cat, lv if typeof(lv) == TYPE_DICTIONARY else {})
	return true


## Cannery levels as a deal may use them: installed upgrades only, each at most its last level.
static func clamp_meta(cat: CampaignCatalog, levels: Dictionary) -> Dictionary:
	var out := {}
	for id in levels:
		var m: Dictionary = cat.meta.get(str(id), {})
		if m.is_empty():
			continue
		var lv := clampi(int(levels[id]), 0, (m.get("costs", []) as Array).size())
		if lv > 0:
			out[str(id)] = lv
	return out


## The Cannery levels a member reported ({} if they did not).
static func meta_of(session_id: int) -> Dictionary:
	return (_member_meta.get(session_id, {}) as Dictionary).duplicate()


static func forget_meta() -> void:
	_member_meta.clear()


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
	var me := my_seat if my_seat != "" else my_seat_in(st)
	if me == "":
		return "Pick which player you are in this run."
	var info := RunStore.summarize(st)
	var err := Net.party_open(str(st.get("run_id", id)), seats, me, info)
	if err != "":
		return err
	role = "host"
	run_id = str(st.get("run_id", id))
	seat = me
	state = st
	return ""


## The players of the session as a new run's party: [{id, name, fighter, profile_id, meta}] - every
## connected non-spectator (session id = member id), each with their lobby fighter (`fallback`
## when it is not a playable one) and, for Fight Camp, their own Cannery levels.
static func session_party(cat: CampaignCatalog, variant: String, fallback: String, prof: Dictionary) -> Array:
	var out: Array = []
	for p in Net.lobby().get("players", []):
		var pd: Dictionary = p
		if bool(pd.get("spectator", false)) or not bool(pd.get("connected", false)):
			continue
		var sid := int(pd.get("id", 0))
		var cid := str(pd.get("creature", ""))
		if cid == "" or not Content.playable_creatures().has(cid):
			cid = fallback
		var mine := sid == Net.local_peer_id()
		var e := {"id": str(sid), "name": str(pd.get("name", "")), "fighter": cid,
			"profile_id": str(prof.get("id", "")) if mine else ""}
		if variant == "fight_camp":
			e["meta"] = clamp_meta(cat, FightCamp.meta_levels(prof)) if mine else meta_of(sid)
		out.append(e)
	return out


## Host: deals a NEW party run for the players in the session now (`cfg` as for
## CoopSession.host_new; cfg.players ids = their session ids, which become the run's member ids)
## and offers it in the lobby. The run is held until start_host(); members claim their seats
## without needing a save (the offer says "new").
func start_new_as_host(cfg: Dictionary) -> String:
	if not Net.is_host():
		return "Host a session first."
	if session != null or not Net.party().is_empty():
		return "A party run is already on offer."
	var s := CoopSession.host_new(NetPartyTransport.new(), catalog, cfg, store, profile, true)
	if s.ctrl == null:
		return "The party run could not be dealt."
	var st: Dictionary = s.ctrl.state
	var seats := seats_of(st)
	if seats.is_empty():
		s.transport.close()
		return "Every member needs an online member id."
	var info := RunStore.summarize(st)
	info["new"] = true
	info["format"] = str(st.get("coop_format", "simultaneous"))
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


## Host: starts the party run: a new run is released (members seated by now play their own
## fighters, the others are bots until they rejoin), a suspended one is resumed from the save.
func start_host() -> String:
	if role != "host" or state.is_empty():
		return "Open a party run first."
	if Net.local_member_id() != seat:
		return "The party run is no longer open in this session."
	if session != null:
		session.release()
		return ""
	session = CoopSession.host_resume(NetPartyTransport.new(), catalog, state, store, profile)
	return ""


## Host: the seats that are still empty or whose player is away.
func missing_seats() -> Array:
	var out: Array = []
	for s in Net.party().get("seats", []):
		if str(s.get("id", "")) != seat and (int(s.get("session", 0)) <= 0 or not bool(s.get("connected", false))):
			out.append(str(s.get("id", "")))
	return out


## True once the run is on (released / resumed on the host; announced live to a member).
func is_live() -> bool:
	return session != null and session.is_live()


# =====================================================================================
# Host: fights on the session
# =====================================================================================

func _drive_fight() -> void:
	var srv: NetServer = Net.server
	if role != "host" or session == null or session.ctrl == null or srv == null or not session.is_live():
		return
	# ref timeout: the running fight freezes for everyone while the budget lasts
	srv.set_frozen(fight_running and session.is_paused() and srv.phase == NetServer.PHASE_MATCH)
	if fight_running or session.ctrl.phase() != "fight" or srv.phase != NetServer.PHASE_LOBBY:
		return
	var key := "%s/%d" % [str(session.ctrl.state.get("position", "")), int(session.ctrl.session().get("fights", 0))]
	if fight_error != "" and key == _fight_key:
		return               # waits for retry_fight() / forfeit_fight()
	_fight_key = key
	fight_error = ""
	var seat_sessions := _seat_sessions()
	var held_seats := _seat_sessions(true)
	var kinds := {}
	for p in session.ctrl.players():
		var pid := str(p["id"])
		if pid == session.me:
			kinds[pid] = "player"
		elif int(seat_sessions.get(pid, 0)) > 0:
			kinds[pid] = "net"
		else:
			kinds[pid] = "bot"
	var built := session.ctrl.match_config({"player_kinds": kinds, "bot_tier_players": "contender"})
	if not (built["errors"] as PackedStringArray).is_empty() or (built["config"] as Dictionary).is_empty():
		_fight_failed("This fight could not be built: %s" % "; ".join(built["errors"]))
		return
	var cfg: Dictionary = built["config"]
	var owners := {}
	var roles: Array = built["roles"]
	for i in roles.size():
		var pid2 := str((roles[i] as Dictionary).get("player_id", ""))
		if pid2 == "" or str((roles[i] as Dictionary).get("role", "")) != "player":
			continue
		if pid2 == session.me:
			owners[i] = Net.local_peer_id()
		elif int(held_seats.get(pid2, 0)) > 0:
			# connected: their own input; reconnecting (seat kept for them): the run's bot until
			# they are back, then their input again (NetServer._bind_rejoin)
			owners[i] = int(held_seats[pid2])
	var plan := session.ctrl.current_plan()
	var info := {"name": str(plan.get("name", "")), "encounter": str(plan.get("encounter", "")), "rule_tags": plan.get("rule_tags", []),
		"format": RunState.party_mode(session.ctrl.state), "stand_in": catalog.resolver.stand_in, "run_id": run_id,
		"node": str(session.ctrl.state.get("position", "")), "tier": str(session.ctrl.session().get("fight", {}).get("tier", ""))}
	var err := srv.start_campaign_match(cfg, owners, info, _bot_for, FIGHT_RESULTS_S)
	if err != "":
		_fight_failed("The fight could not start: %s" % err)
		return
	fight_running = true
	if not srv.match_finished.is_connected(_on_fight_finished):
		srv.match_finished.connect(_on_fight_finished)


## Seat id -> session player id of every seat held by a connected player (the host's own included);
## `held`: also seats kept for a player who is reconnecting.
func _seat_sessions(held := false) -> Dictionary:
	var out := {}
	for s in Net.party().get("seats", []):
		var sd: Dictionary = s
		if int(sd.get("session", 0)) > 0 and (held or bool(sd.get("connected", false))):
			out[str(sd.get("id", ""))] = int(sd["session"])
	return out


## What drives a member's fighter when they drop mid-fight: the run's bot rules.
func _bot_for(f: Fighter) -> InputSource:
	return EncounterBuilder.make_bot(catalog, "contender", int(session.ctrl.state.get("seed", 1)) * 7 + f.index * 131 if session and session.ctrl else f.index, f.creature)


func _fight_failed(why: String) -> void:
	fight_error = why
	Log.w("net", "party run %s: %s" % [run_id, why])
	fight_problem.emit(why)


func _on_fight_finished(result: Dictionary) -> void:
	fight_running = false
	if session == null or session.ctrl == null or not session.is_host():
		return
	if session.ctrl.phase() != "fight":
		return
	if bool(result.get("aborted", false)) or typeof(result.get("campaign")) != TYPE_DICTIONARY:
		# the host's match never finished (its scene was removed): the fight is played again
		_fight_key = ""
		Log.w("net", "party run %s: the fight did not finish (%s); it is played again" % [run_id, str(result.get("abort_reason", "no result"))])
		return
	fights_played += 1
	session.complete_fight(result)


## Host: tries the pending fight again (after fight_problem).
func retry_fight() -> void:
	fight_error = ""
	_fight_key = ""


## Host: gives up the pending fight - one that cannot be played (content missing), or the one in
## progress (the host's pause menu): it counts as a lost fight for the party. A running match is
## ended for everyone (its own result is not applied).
func forfeit_fight() -> void:
	if role != "host" or session == null or session.ctrl == null or session.ctrl.phase() != "fight":
		return
	fight_error = ""
	session.complete_fight({"campaign": {"won": false, "time": 0.0, "players": {}, "error": "forfeit"}})
	var srv: NetServer = Net.server
	if fight_running and srv != null and srv.phase == NetServer.PHASE_MATCH:
		srv.notice("The host forfeited the fight.")
		srv.end_match_now("the host forfeited the fight")


# =====================================================================================
# Member
# =====================================================================================

## Member: claims this player's seat in the run the host offers. A resumed run must be in the
## player's own party save (its seat is found there); a NEW run (offer info "new") needs none -
## its seats are the session ids it was dealt with. `my_seat` = the seat the player picked
## ("" = find it). Returns "" once the claim is on its way (Net seats us, or reports
## party_claim_failed) - or at once when this session already holds that seat (a reconnect).
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
	# a new run's seats are the session ids it was dealt with; a resumed one is matched by save;
	# a player who reconnected while their seat was kept for them already holds it
	var me := my_seat
	if me == "":
		me = Net.party_seat()
	if me == "":
		me = str(Net.local_peer_id()) if fresh and own.is_empty() else my_seat_in(own)
	if me == "":
		return "Pick which player you are in this run."
	var known := false
	for s in pt.get("seats", []):
		known = known or str(s.get("id", "")) == me
	if not known:
		return "That player is not part of the host's run."
	if Net.party_seat() != me:
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
		# both sides as a save stores them (JSON fixed point): a live state's floats (fight results)
		# are written a little differently than they are read back
		if Saves.checksum(RunStore.json_stable(mine[i])) != Saves.checksum(RunStore.json_stable(theirs[i])):
			return "The host's run differs from your save at decision %d." % (i + 1)
	return ""


# =====================================================================================
# Both
# =====================================================================================

## Every frame: a seated member joins the host's run (and repeats its hello until the run
## arrives - the host may start its session after we sat down); the CoopSession ticks; the host
## plays the run's fights on the session.
func tick(dt: float) -> void:
	if role == "member" and session == null and Net.party_seat() == seat and seat != "":
		var host_seat := str(Net.party().get("host_seat", ""))
		if host_seat != "":
			session = CoopSession.member_join(NetPartyTransport.new(), catalog, host_seat, store, profile)
			session.rejoin()
			_hello_ms = Time.get_ticks_msec()
	if session == null:
		ticked.emit(dt)
		return
	if role == "member" and str(Net.party().get("run_id", "")) != run_id:
		# the host withdrew / suspended the run (or offers another one): this machine leaves it
		error = "The host suspended the party run. It is saved: rejoin when the host offers it again."
		close()
		ended.emit(error)
		ticked.emit(dt)
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
	if role == "host":
		_drive_fight()
	ticked.emit(dt)


## Ticks this party run every frame from a node under Net (process mode always), whatever the
## UI shows; stopped by close().
func start_ticking() -> void:
	if _ticker != null and is_instance_valid(_ticker):
		return
	var t := Ticker.new()
	t.runs = self
	t.name = "PartyRunTicker"
	Net.add_child(t)
	_ticker = t


## Leaves the party run (the CoopSession's transport detaches; the seat is given up). A host in
## the middle of a fight ends that match (the run stays at the fight, saved at the last node).
## `withdraw` false when the host is leaving the whole session: the run is not withdrawn first, so
## the members learn from the session ending (with the note that their party save keeps the run).
func close(withdraw := true) -> void:
	if _ticker != null and is_instance_valid(_ticker):
		(_ticker as Ticker).runs = null
		_ticker.queue_free()
	_ticker = null
	var srv: NetServer = Net.server
	if srv != null and srv.match_finished.is_connected(_on_fight_finished):
		srv.match_finished.disconnect(_on_fight_finished)
	if role == "host" and fight_running and srv != null and srv.phase == NetServer.PHASE_MATCH:
		srv.end_match_now("the party run was suspended")
	fight_running = false
	if session != null and session.transport != null:
		session.transport.close()
	session = null
	if role == "host":
		if withdraw:
			Net.party_close()
	elif role == "member":
		Net.party_leave()
	role = ""


class Ticker:
	extends Node
	var runs: NetPartyRuns = null

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(dt: float) -> void:
		if runs != null:
			runs.tick(dt)
