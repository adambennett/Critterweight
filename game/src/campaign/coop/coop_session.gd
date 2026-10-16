class_name CoopSession
extends RefCounted
## Co-op campaign party (2–4 members, both variants) over a PartyTransport (CAMPAIGN.md §11).
## The host owns the authoritative RunController (server decides rewards, Scrip, Clout, rolls);
## members send intents and mirror the state. Rules implemented here:
##   * Trust: who sent a message is the TRANSPORT's peer id (`from`), never a payload field.
##     Members accept host-only messages (run_state, ticket, run_end, notices...) only from the
##     current host, and host_changed only from the successor the election rule picks. Tickets
##     and the final result must be this party's run (run id + seed) and must follow from their
##     own decision log (RunController.verify) before a member saves or credits them.
##   * Route voting: VOTE_TIME s per map step, majority / Captain tie-break (RouteVote); bots and
##     disconnected members abstain. Group events vote the same way — every member's choice on
##     a group event is a vote, never a decision — and offer only choices the whole party can
##     pay for; a choice that still fails is dropped from the next vote and the error broadcast
##     (nothing left: PASS), so a group event always resolves. Personal events are decided by
##     the first member who answers (fighter-specific ones by the matching player).
##   * Per-player picks: every member claims only their own pending rewards (own sub-seed,
##     separate inventories and Scrip); the claim ledger rejects duplicates and resent messages.
##   * Run ownership: the host saves the run; after every node every member receives a party
##     ticket (state + checksum) and keeps it as a local replica checkpoint. Party slots are
##     cleared when the run ends.
##   * Disconnect: the member's slot is piloted by a bot (tier capped at Contender) and their
##     decisions are auto-chosen; they rejoin at the next node boundary with their state.
##   * Absent members: after ABSENT s idle at a decision point the Captain can "move on"
##     (auto-choose for them); after twice that the host moves on by itself (no softlock).
##   * Host departure: members wait HOST_WAIT s; then the next connected member in Captain
##     order resumes as host from their replica (last node boundary; a fight in progress is
##     re-run from its start). If everyone leaves the run stays suspended in every member's
##     party slot and the original host can resume it later and invite the same or new members.
##   * Pause: a "ref timeout" freezes the current fight for up to PAUSE_BUDGET s per player per
##     run; menus never pause.
##   * Progression: at run end the host sends the final state; each member credits ONLY their
##     own profile (CampaignProgression.finish_run, idempotent per run and player) with the run
##     rebuilt from its log — Dose credit then follows that member's own ladder.
##   * Start: a run dealt in a lobby can be HELD (host_new(..., hold = true)) while members take
##     their seats: nothing is decided until release(); run_state carries "live" so members know
##     when the run is on (the UI then leaves the lobby for the campaign screens).
## Views for screens on every machine (host and members alike): vote_view(), pause_view(),
## fight_view(), is_live(). Member-side views are built from the host's messages only.
## Time is advanced explicitly with tick(dt) (loopback tests run timers instantly).

signal changed(reason: String)
signal notice(text: String)
signal fight_ready()
signal run_finished(report: Dictionary)

var transport: PartyTransport
var catalog: CampaignCatalog
var me := ""
var host_id := ""
var ctrl: RunController
var store: RunStore
var profile_id := ""
var profile: Dictionary = {}
var clock := 0.0
var vote: RouteVote = null
var event_vote: RouteVote = null
var ticket: Dictionary = {}           ## last node-boundary checkpoint (members' replica)
var waiting_host := false
var host_lost_at := -1.0
var suspended := false
var pause_by := ""
var pause_started := -1.0
var pause_until := -1.0
var pause_left := {}                  ## player id -> seconds of ref timeout budget left
var last_seen := {}                   ## player id -> clock
var decision_since := 0.0
var _decision_key := ""
var _fight_announced := ""
var _run_end_sent := false
var _credited := false
var _rejoin: Array = []
var _was_bot := {}
var _run_id := ""                     ## member: the party's run (from the host's first run_state)
var _run_seed := 0
var _verified: RunController = null   ## member: the run rebuilt from the last accepted ticket's log
var _host_claim := ""                 ## member: the successor's host_changed, held until the old host is gone
var _event_dropped := {}              ## host: {node, ids} group-event choices that failed this node
var held := false                     ## host: dealt but not started (members are taking their seats)
var live := false                     ## member: the host's run is on (run_state "live")
var last_error := ""                  ## why the local player's last act() was refused (host-side acts)
var vote_info := {}                   ## member: the open vote as the host announced it
var pause_info := {}                  ## member: {paused, by, until, budget} from paused/resumed
var fight_info := {}                  ## member: the last fight_start announcement
## The latest event outcome at this node, for every machine's event screen (presentation only;
## the node may already be complete and its event gone from the state): {node, title, choice,
## by, texts}. The host fills it when an event resolves and sends it with run_state.
var last_event := {}


func _init(t: PartyTransport, cat: CampaignCatalog, member_id: String) -> void:
	transport = t
	catalog = cat
	me = member_id
	t.message_received.connect(_on_message)
	t.peer_left.connect(_on_peer_left)
	t.peer_joined.connect(_on_peer_joined)


func coop_rules() -> Dictionary:
	return catalog.rules.get("coop", {})


func is_host() -> bool:
	return me == host_id


func state() -> Dictionary:
	return ctrl.state if ctrl else {}


## Host: starts a new party run. cfg.players must list every member (ids == transport ids). The
## Dose is clamped to what the host's own profile may play (members are credited by their own).
## `hold`: the run waits (no votes, no decisions) until release() - members take their seats first.
static func host_new(t: PartyTransport, cat: CampaignCatalog, cfg: Dictionary, run_store: RunStore = null, prof: Dictionary = {}, hold := false) -> CoopSession:
	var s := CoopSession.new(t, cat, t.local_id())
	s.host_id = s.me
	s.store = run_store
	s.profile = prof
	s.profile_id = str(prof.get("id", s.me))
	s.held = hold
	var c: Dictionary = cfg.duplicate(true)
	if not prof.is_empty():
		c["dose"] = CampaignProgression.clamp_dose(cat, prof, str(c.get("variant", "off_the_street")), str(c.get("difficulty", "amateur")), int(c.get("dose", 0)))
	s.ctrl = RunController.start_run(cat, c)
	s._init_budgets()
	s._after_change("start")
	return s


## Host: starts a held run (members who are not here yet are played by bots until they rejoin).
func release() -> void:
	if not is_host() or not held or ctrl == null:
		return
	held = false
	for p in ctrl.players():
		var pid := str(p["id"])
		var here := pid == me or transport.peers().has(pid)
		p["connected"] = here
		p["bot"] = not here
	_rejoin.clear()          # everyone here already has their fighter; latecomers rejoin as usual
	decision_since = clock
	_after_change("live")


## True once the run is on: the host released it (or resumed / migrated it), or - on a member -
## the host's run_state said so.
func is_live() -> bool:
	if ctrl == null:
		return false
	return not held if is_host() else live


## Host: resumes a suspended party run (any member's replica or the host's own save).
static func host_resume(t: PartyTransport, cat: CampaignCatalog, st: Dictionary, run_store: RunStore = null, prof: Dictionary = {}) -> CoopSession:
	var s := CoopSession.new(t, cat, t.local_id())
	s.host_id = s.me
	s.store = run_store
	s.profile = prof
	s.profile_id = str(prof.get("id", s.me))
	s.ctrl = RunController.from_state(cat, st)
	for p in s.ctrl.players():
		var connected := str(p["id"]) == s.me or t.peers().has(str(p["id"]))
		p["connected"] = connected
		p["bot"] = not connected
	s._init_budgets()
	s._after_change("resume")
	return s


## Member: joins a party whose host is `host`.
static func member_join(t: PartyTransport, cat: CampaignCatalog, host: String, run_store: RunStore = null, prof: Dictionary = {}) -> CoopSession:
	var s := CoopSession.new(t, cat, t.local_id())
	s.host_id = host
	s.store = run_store
	s.profile = prof
	s.profile_id = str(prof.get("id", s.me))
	t.send(host, "hello", {"player": s.me})
	return s


func _init_budgets() -> void:
	for pid in RunState.player_ids(ctrl.state):
		if not pause_left.has(pid):
			pause_left[pid] = float(coop_rules().get("pause_budget", 30.0))


# =============================================================================================
# Ticking
# =============================================================================================

func tick(dt: float) -> void:
	clock += dt
	transport.poll(dt)
	if suspended:
		return
	if is_host():
		_host_tick()
	else:
		_member_tick()
	transport.poll(0.0)


func _host_tick() -> void:
	if ctrl == null or held:
		return
	# a ref timeout belongs to its fight: it ends with the budget, or when the fight is over
	if pause_until > 0.0 and (clock >= pause_until or ctrl.phase() != "fight"):
		_resume_pause(pause_by)
	_track_decision_point()
	var phase := ctrl.phase()
	# a vote belongs to its decision point: never resolve a stale one at the next node
	if phase != "map":
		vote = null
	if phase != "event":
		event_vote = null
	if phase == "map":
		_apply_rejoins()
		if vote == null:
			_open_vote()
		elif vote.all_voted() or clock >= vote.deadline:
			_resolve_vote()
	elif phase == "event" and bool(ctrl.session().get("event", {}).get("group", false)):
		if event_vote == null:
			_open_event_vote()
		elif event_vote.all_voted() or clock >= event_vote.deadline:
			_resolve_event_vote()
	elif phase == "fight":
		var key := "%s/%d" % [ctrl.state.get("position", ""), int(ctrl.session().get("fights", 0))]
		if _fight_announced != key:
			_fight_announced = key
			transport.send("", "fight_start", {"encounter": str(ctrl.current_plan().get("encounter", "")),
				"name": str(ctrl.current_plan().get("name", "")), "rule_tags": ctrl.current_plan().get("rule_tags", [])})
			fight_ready.emit()
	_auto_decide_for_absent()
	if ctrl.is_over() and not _run_end_sent:
		_run_end_sent = true
		transport.send("", "run_end", {"state": ctrl.state})
		_credit_self(ctrl.state)


func _member_tick() -> void:
	if waiting_host and clock - host_lost_at >= float(coop_rules().get("host_wait", 60.0)):
		_elect_new_host()


func _track_decision_point() -> void:
	var key := "%s|%s|%d" % [ctrl.phase(), ctrl.state.get("position", ""), (ctrl.state.get("log", []) as Array).size()]
	if key != _decision_key:
		_decision_key = key
		decision_since = clock


# =============================================================================================
# Host: votes, auto-decisions, rejoins, pause
# =============================================================================================

func _humans() -> Array:
	var out := []
	for p in ctrl.players():
		if not bool(p.get("bot", false)) and bool(p.get("connected", true)):
			out.append(str(p["id"]))
	return out


func _open_vote() -> void:
	var opts := ctrl.available_nodes()
	if opts.is_empty():
		return
	vote = RouteVote.new(opts, _humans(), ctrl.captain(), clock + float(coop_rules().get("vote_time", 10.0)),
		int(ctrl.state.get("seed", 1)), "%s/%d" % [ctrl.state.get("position", "start"), int(ctrl.state.get("act", 1))])
	transport.send("", "vote_open", {"options": opts, "captain": vote.captain, "seconds": float(coop_rules().get("vote_time", 10.0)),
		"voters": vote.voters})
	changed.emit("vote")


func _resolve_vote() -> void:
	var r := vote.result()
	var counts := vote.counts()
	vote = null
	if ctrl.choose_node(str(r["option"]), ctrl.captain()):
		transport.send("", "vote_result", {"node": r["option"], "reason": r["reason"], "tie": r["tie"], "counts": counts})
		_after_change("route")


## Opens the vote on a group event: only choices the Captain may take AND every member can pay
## their share of, minus any that already failed at this node. Nothing left: the party passes.
func _open_event_vote() -> void:
	var node := str(ctrl.state.get("position", ""))
	if str(_event_dropped.get("node", "")) != node:
		_event_dropped = {"node": node, "ids": []}
	var opts := []
	for id in EventRunner.available_choices(ctrl, ctrl.session().get("event", {}), ctrl.captain()):
		if not (_event_dropped["ids"] as Array).has(id):
			opts.append(str(id))
	if opts.is_empty():
		var before_ev := ctrl.event_view(ctrl.captain())
		if ctrl.choose_event(ctrl.captain(), EventRunner.PASS):
			_note_event(before_ev, "party")
			transport.send("", "notice", {"text": "Nobody can take any of these options: the party moves on."})
			_after_change("event_pass")
		return
	event_vote = RouteVote.new(opts, _humans(), ctrl.captain(), clock + float(coop_rules().get("vote_time", 10.0)),
		int(ctrl.state.get("seed", 1)), "event/%s/%d" % [node, (_event_dropped["ids"] as Array).size()])
	transport.send("", "vote_open", {"options": opts, "captain": event_vote.captain, "event": true, "seconds": float(coop_rules().get("vote_time", 10.0)),
		"voters": event_vote.voters})
	changed.emit("vote")


## Applies the group event vote. A choice that fails (a member's Scrip changed since the vote
## opened) is never offered again at this node; the error goes to every member and a new vote
## opens on the next tick — the vote can never repeat the same failing pick forever.
func _resolve_event_vote() -> void:
	var r := event_vote.result()
	var counts := event_vote.counts()
	var opt := str(r["option"])
	event_vote = null
	var before_ev := ctrl.event_view(ctrl.captain())
	if ctrl.choose_event(ctrl.captain(), opt):
		_note_event(before_ev, "party")
		transport.send("", "vote_result", {"event": true, "choice": opt, "reason": r["reason"], "tie": r["tie"], "counts": counts})
		_after_change("event_vote")
		return
	(_event_dropped["ids"] as Array).append(opt)
	var text := "The party's pick '%s' could not be done (%s); vote again." % [opt, ctrl.last_error]
	transport.send("", "error", {"text": text, "type": "event_choice"})
	notice.emit(text)
	changed.emit("vote")


## Disconnected members are decided for immediately; idle ones after 2x the absent time
## (the Captain may "move on" after 1x).
func _auto_decide_for_absent(force := false) -> void:
	if ctrl.is_over() or ctrl.phase() in ["map", "fight"]:
		return
	var absent := float(coop_rules().get("absent_time", 60.0))
	var pids := []
	var all_idle := true
	for p in ctrl.players():
		var pid := str(p["id"])
		var idle := clock - maxf(float(last_seen.get(pid, 0.0)), decision_since)
		var away := bool(p.get("bot", false)) or force or (pid != me and idle >= absent * 2.0)
		if away:
			pids.append(pid)
		elif not bool(p.get("bot", false)):
			all_idle = false
	if pids.is_empty():
		return
	if ctrl.phase() == "event":
		# a shared personal event is decided by whoever answers first: bots never pre-empt a
		# connected human unless the event belongs to them or everyone is away
		var ev: Dictionary = ctrl.session().get("event", {})
		var decider := str(ev.get("decider", ""))
		if bool(ev.get("group", false)):
			return
		if decider != "" and pids.has(decider):
			pids = [decider]
		elif not (all_idle or force):
			pids = []
		else:
			pids = [pids[0]]
	if pids.is_empty():
		return
	var before_ev := ctrl.event_view(str(pids[0])) if ctrl.phase() == "event" else {}
	var log_n := (ctrl.state.get("log", []) as Array).size()
	if CampaignAutoPilot.settle(ctrl, pids):
		var lg: Array = ctrl.state.get("log", [])
		for i in range(log_n, lg.size()):
			if str((lg[i] as Dictionary).get("k", "")) == "event" and not before_ev.is_empty():
				_note_event(before_ev, str(pids[0]))
				break
		_after_change("auto")


func _apply_rejoins() -> void:
	if _rejoin.is_empty():
		return
	for pid in _rejoin:
		var p := ctrl.player(str(pid))
		if p.is_empty():
			continue
		p["bot"] = false
		p["connected"] = true
		last_seen[str(pid)] = clock
		transport.send("", "notice", {"text": "%s is back and takes over their fighter." % p.get("name", pid)})
		notice.emit("%s rejoined." % p.get("name", pid))
	_rejoin.clear()
	_after_change("rejoin")


func request_pause(pid: String) -> bool:
	if ctrl == null or ctrl.phase() != "fight":
		last_error = "a ref timeout can only be called during a fight"
		return false
	if pause_until > 0.0:
		last_error = "the fight is already paused"
		return false
	if float(pause_left.get(pid, 0.0)) <= 0.0:
		last_error = "your ref timeouts for this run are used up"
		return false
	pause_by = pid
	pause_started = clock
	pause_until = clock + float(pause_left[pid])
	transport.send("", "paused", {"by": pid, "seconds": float(pause_left[pid]), "budget": pause_left.duplicate()})
	notice.emit("Ref timeout called by %s (%d s)." % [name_of(pid), int(pause_left[pid])])
	changed.emit("paused")
	return true


func _resume_pause(pid: String) -> void:
	if pause_until < 0.0 or (pid != pause_by and pid != ""):
		return
	pause_left[pause_by] = maxf(0.0, float(pause_left.get(pause_by, 0.0)) - (clock - pause_started))
	pause_by = ""
	pause_until = -1.0
	pause_started = -1.0
	transport.send("", "resumed", {"budget": pause_left.duplicate()})
	notice.emit("Fight resumed.")
	changed.emit("resumed")


func is_paused() -> bool:
	if is_host():
		return pause_until > 0.0
	return bool(pause_info.get("paused", false))


## The ref timeout as every machine sees it: {paused, by, left (s), budget: {pid: s}}.
func pause_view() -> Dictionary:
	if is_host():
		return {"paused": pause_until > 0.0, "by": pause_by, "left": maxf(0.0, pause_until - clock) if pause_until > 0.0 else 0.0,
			"budget": pause_left.duplicate()}
	var v := pause_info.duplicate()
	v["left"] = maxf(0.0, float(v.get("until", 0.0)) - clock) if bool(v.get("paused", false)) else 0.0
	if not v.has("budget"):
		v["budget"] = {}
	return v


## Seconds of ref timeout this machine's player has left in the run.
func my_pause_budget() -> float:
	var b: Dictionary = pause_view().get("budget", {})
	return float(b.get(me, coop_rules().get("pause_budget", 30.0)))


## The vote on screen for every machine: {} or {open, event, options, votes {voter: option},
## voters, captain, left (s)}.
func vote_view() -> Dictionary:
	if is_host():
		var v: RouteVote = vote if vote != null else event_vote
		if v == null:
			return {}
		return {"open": true, "event": v == event_vote, "options": v.options.duplicate(), "votes": v.votes.duplicate(),
			"voters": v.voters.duplicate(), "captain": v.captain, "left": maxf(0.0, v.deadline - clock)}
	if vote_info.is_empty() or not bool(vote_info.get("open", false)):
		return {}
	var out := vote_info.duplicate(true)
	out["left"] = maxf(0.0, float(out.get("until", 0.0)) - clock)
	return out


## The fight being set up / played at this node: {encounter, name, rule_tags} ({} = none).
func fight_view() -> Dictionary:
	if ctrl == null or ctrl.phase() != "fight":
		return {}
	if not fight_info.is_empty():
		return fight_info.duplicate()
	var plan := ctrl.current_plan()
	return {"encounter": str(plan.get("encounter", "")), "name": str(plan.get("name", "")), "rule_tags": plan.get("rule_tags", [])}


func name_of(pid: String) -> String:
	if ctrl != null:
		var p := ctrl.player(pid)
		if not p.is_empty():
			return str(p.get("name", pid))
	return pid


## Host: applies a finished fight (from the network match or a headless run).
func complete_fight(result: Dictionary) -> bool:
	if not is_host():
		return false
	var ok := ctrl.complete_fight(result)
	_after_change("fight")
	return ok


## Remembers an event's outcome right after it resolved (`before` = its view just before).
func _note_event(before: Dictionary, by: String) -> void:
	var chosen := ""
	var log_v: Array = ctrl.state.get("log", [])
	for i in range(log_v.size() - 1, -1, -1):
		if str((log_v[i] as Dictionary).get("k", "")) == "event":
			chosen = str((log_v[i] as Dictionary).get("d", {}).get("choice", ""))
			break
	var label_text := chosen
	for c in before.get("choices", []):
		if str((c as Dictionary).get("id", "")) == chosen:
			label_text = str((c as Dictionary).get("label", chosen))
	last_event = {"node": str(ctrl.state.get("position", "")), "title": str(before.get("title", "Event")), "choice": label_text,
		"by": by, "texts": ctrl.last_texts.duplicate()}


func _after_change(reason: String) -> void:
	var msg := {"state": ctrl.state, "host": host_id, "reason": reason, "live": not held}
	if not last_event.is_empty() and str(last_event.get("node", "")) == str(ctrl.state.get("position", "")):
		msg["event"] = last_event
	transport.send("", "run_state", msg)
	if ctrl.phase() == "map" or ctrl.is_over():
		ticket = RunStore.make_ticket(ctrl.state, host_id)
		transport.send("", "ticket", ticket)
		if store:
			if ctrl.is_over():
				store.clear(profile_id, RunStore.slot_for(ctrl.state))   # a finished run is no suspended run
			else:
				store.save(ctrl.state, profile_id, RunStore.slot_for(ctrl.state))
				store.save_party_seat(profile_id, RunStore.slot_for(ctrl.state), me)
	changed.emit(reason)


# =============================================================================================
# Messages
# =============================================================================================

func _on_message(from: String, type: String, payload: Dictionary) -> void:
	if is_host():
		_host_message(from, type, payload)
	else:
		_member_message(from, type, payload)


## Applies a member's (or the host's own) intent. Returns whether it was accepted; a refused one
## leaves the reason in last_error and is answered with "error" (to a member).
func _host_message(from: String, type: String, payload: Dictionary) -> bool:
	if ctrl == null:
		return false
	last_seen[from] = clock
	last_error = ""
	var ok := true
	match type:
		"hello":
			transport.send(from, "run_state", {"state": ctrl.state, "host": host_id, "reason": "hello", "live": not held})
			if not ticket.is_empty():
				transport.send(from, "ticket", ticket)
			if ctrl.is_over():
				# a member who was away when the run ended still gets the final result to credit
				transport.send(from, "run_end", {"state": ctrl.state})
			var vv := vote_view()
			if not vv.is_empty():
				# a member arriving mid-vote sees it at once (and may still vote)
				transport.send(from, "vote_open", {"options": vv["options"], "captain": vv["captain"], "seconds": vv["left"],
					"event": vv["event"], "voters": vv["voters"]})
				transport.send(from, "vote_update", {"votes": vv["votes"], "event": vv["event"]})
			return true
	if held and not type in ["rejoin", "move_on", "pause", "resume"]:
		return _refuse(from, type, "the run has not started yet")
	match type:
		"vote":
			if vote == null:
				return _refuse(from, type, "no route vote is open")
			if not vote.cast(from, str(payload.get("node", ""))):
				return _refuse(from, type, "'%s' is not a stop you can vote for" % str(payload.get("node", "")))
			transport.send("", "vote_update", {"votes": vote.votes})
			changed.emit("vote")
			return true
		"event_choice":
			if ctrl.phase() == "event" and bool(ctrl.session().get("event", {}).get("group", false)):
				# a group event is never decided by one member: their choice is their vote
				if event_vote == null:
					_open_event_vote()
				if event_vote == null:
					return true       # resolved without a vote (nothing anyone could take)
				if not event_vote.cast(from, str(payload.get("choice", ""))):
					return _refuse(from, type, "'%s' is not one of the options the party can take" % str(payload.get("choice", "")))
				transport.send("", "vote_update", {"votes": event_vote.votes, "event": true})
				changed.emit("vote")
				return true
			var before_ev := ctrl.event_view(from)
			ok = ctrl.choose_event(from, str(payload.get("choice", "")))
			if ok:
				_note_event(before_ev, from)
		"pick":
			ok = ctrl.claim(from, str(payload.get("rid", "")), str(payload.get("choice", "")))
		"reroll":
			ok = ctrl.reroll(from, str(payload.get("rid", "")))
		"shop_buy":
			ok = ctrl.shop_buy(from, str(payload.get("slot", "")))
		"shop_service":
			ok = ctrl.shop_service(from)
		"shop_sell":
			ok = ctrl.shop_sell(from, str(payload.get("item", "")))
		"shop_leave":
			ok = ctrl.shop_leave(from)
		"rest":
			ok = ctrl.rest_choose(from, str(payload.get("option", "")))
		"consume":
			ok = ctrl.use_consumable(from, str(payload.get("item", "")))
		"pause":
			if not request_pause(from):
				return _refuse(from, type, last_error)
			return true
		"resume":
			if pause_until < 0.0 or from != pause_by:
				return _refuse(from, type, "only whoever called the ref timeout can end it early")
			_resume_pause(from)
			return true
		"rejoin":
			if not ctrl.player(from).is_empty():
				_rejoin.append(from)
				if ctrl.phase() == "map" and not held:
					_apply_rejoins()
			return true
		"move_on":
			if from != ctrl.captain():
				return _refuse(from, type, "only the Captain can move on for absent players")
			if clock - decision_since < float(coop_rules().get("absent_time", 60.0)):
				return _refuse(from, type, "absent players get %d s before the Captain can move on" % int(coop_rules().get("absent_time", 60.0)))
			_auto_decide_for_absent(true)
			return true
		_:
			return false
	if not ok:
		return _refuse(from, type, ctrl.last_error)
	_after_change(type)
	return true


func _refuse(from: String, type: String, text: String) -> bool:
	last_error = text
	if from != me:
		transport.send(from, "error", {"text": text, "type": type})
	return false


## The local player's intent (UI): applied at once on the host (same rules as members' intents;
## false + last_error when refused), sent to the host from a member (true = sent; a refusal comes
## back as a notice).
func act(type: String, payload: Dictionary) -> bool:
	if is_host():
		return _host_message(me, type, payload)
	if ctrl == null:
		last_error = "the run has not arrived from the host yet"
		return false
	transport.send(host_id, type, payload)
	return true


## A member's inbox. `from` is the transport's peer id: everything here except host_changed is
## host-only and ignored from anyone else; payload fields never name the host.
func _member_message(from: String, type: String, payload: Dictionary) -> void:
	if type == "host_changed":
		_consider_host_claim(from)
		return
	if from != host_id:
		return
	match type:
		"run_state":
			var st = payload.get("state", {})
			if typeof(st) == TYPE_DICTIONARY and _is_party_run(st):
				ctrl = RunController.from_state(catalog, st)
				live = bool(payload.get("live", true))
				var ev = payload.get("event", {})
				last_event = (ev as Dictionary).duplicate(true) if typeof(ev) == TYPE_DICTIONARY else {}
				if ctrl.phase() != "map":
					vote_info = {}
				if ctrl.phase() != "fight":
					fight_info = {}
					pause_info = {}
				changed.emit(str(payload.get("reason", "state")))
		"ticket":
			_accept_ticket(payload)
		"notice":
			notice.emit(str(payload.get("text", "")))
		"run_end":
			_accept_run_end(payload)
		"error":
			last_error = str(payload.get("text", ""))
			notice.emit("Not accepted: %s" % last_error)
			changed.emit("refused")
		"vote_open":
			var opts = payload.get("options", [])
			var voters = payload.get("voters", [])
			vote_info = {"open": true, "event": bool(payload.get("event", false)), "options": opts if typeof(opts) == TYPE_ARRAY else [],
				"voters": voters if typeof(voters) == TYPE_ARRAY else [], "captain": str(payload.get("captain", "")), "votes": {},
				"until": clock + clampf(float(payload.get("seconds", 10.0)), 0.0, 120.0)}
			changed.emit("vote")
		"vote_update":
			var vs = payload.get("votes", {})
			if not vote_info.is_empty() and typeof(vs) == TYPE_DICTIONARY:
				vote_info["votes"] = (vs as Dictionary).duplicate()
				changed.emit("vote")
		"vote_result":
			vote_info = {}
			changed.emit("vote")
		"fight_start":
			fight_info = {"encounter": str(payload.get("encounter", "")), "name": str(payload.get("name", "")),
				"rule_tags": payload.get("rule_tags", []) if typeof(payload.get("rule_tags", [])) == TYPE_ARRAY else []}
			changed.emit("fight_start")
		"paused":
			var b = payload.get("budget", {})
			pause_info = {"paused": true, "by": str(payload.get("by", "")), "until": clock + clampf(float(payload.get("seconds", 0.0)), 0.0, 120.0),
				"budget": (b as Dictionary).duplicate() if typeof(b) == TYPE_DICTIONARY else {}}
			notice.emit("Ref timeout called by %s (%d s)." % [name_of(str(payload.get("by", "?"))), int(payload.get("seconds", 0))])
			changed.emit("paused")
		"resumed":
			var b2 = payload.get("budget", {})
			pause_info = {"paused": false, "budget": (b2 as Dictionary).duplicate() if typeof(b2) == TYPE_DICTIONARY else pause_info.get("budget", {})}
			notice.emit("Fight resumed.")
			changed.emit("resumed")
		_:
			pass


## True if `st` is this party's run (run id + seed). The host's first state names the run.
func _is_party_run(st: Dictionary) -> bool:
	var rid := str(st.get("run_id", ""))
	if rid == "":
		return false
	if _run_id == "":
		_run_id = rid
		_run_seed = int(st.get("seed", 0))
		return true
	return rid == _run_id and int(st.get("seed", 0)) == _run_seed


## A node-boundary checkpoint from the host: kept (and saved as this member's party replica)
## only if it is intact, belongs to this party's run, is not older than the one held, and its
## state follows from its own decision log. A finished run's slot is cleared instead.
func _accept_ticket(t: Dictionary) -> void:
	if not RunStore.ticket_valid(t):
		return
	var st: Dictionary = t["state"]
	if not _is_party_run(st) or str(t.get("run_id", "")) != _run_id:
		notice.emit("Ignored a checkpoint for another run.")
		return
	if not ticket.is_empty() and int(t.get("log_size", 0)) < int(ticket.get("log_size", 0)):
		return
	var v := RunController.verify_from(catalog, _verified, st)
	if not bool(v["ok"]):
		notice.emit("Ignored the host's checkpoint: %s." % str(v["error"]))
		return
	ticket = t
	_verified = v["ctrl"]
	if store:
		if (v["ctrl"] as RunController).is_over():
			store.clear(profile_id, RunStore.slot_for(st))
		else:
			store.save(st, profile_id, RunStore.slot_for(st))
			store.save_party_seat(profile_id, RunStore.slot_for(st), me)


## The host's final result: credited only when it is this party's run and follows from its own
## decision log — and then from the rebuilt run, never from the numbers in the message.
func _accept_run_end(payload: Dictionary) -> void:
	var st = payload.get("state", {})
	if typeof(st) != TYPE_DICTIONARY or not _is_party_run(st):
		return
	var v := RunController.verify_from(catalog, _verified, st)
	var rebuilt: RunController = v["ctrl"]
	if not bool(v["ok"]) or rebuilt == null or not rebuilt.is_over():
		var why := str(v["error"]) if str(v["error"]) != "" else "the run is not over"
		notice.emit("The host's final result does not match the run (%s); it was not credited." % why)
		return
	var final: Dictionary = rebuilt.state
	# fights are in the log (their time is a floor); menu time is not, so keep the host's if larger
	var el := maxf(float(final.get("elapsed", 0.0)), float((st as Dictionary).get("elapsed", 0.0)))
	final["elapsed"] = el
	(final["result"] as Dictionary)["elapsed"] = el
	ctrl = RunController.from_state(catalog, final)
	if store:
		store.clear(profile_id, RunStore.slot_for(final))
	_credit_self(final)


func _credit_self(st: Dictionary) -> void:
	if _credited or profile.is_empty():
		return
	_credited = true
	var rep := CampaignProgression.finish_run(catalog, st, me, profile)
	CampaignProgression.grant_achievements(rep, profile)
	run_finished.emit(rep)


# =============================================================================================
# Membership: disconnect, rejoin, host departure
# =============================================================================================

func _on_peer_left(peer: String, _reason: String) -> void:
	if is_host():
		if ctrl == null:
			return
		var p := ctrl.player(peer)
		if p.is_empty():
			return
		p["connected"] = false
		p["bot"] = true
		if vote:
			vote.voters.erase(peer)
			vote.votes.erase(peer)
		transport.send("", "notice", {"text": "%s disconnected; a bot takes their fighter until they return." % p.get("name", peer)})
		notice.emit("%s disconnected." % p.get("name", peer))
		_after_change("disconnect")
	elif peer == host_id:
		# the successor's claim overtook this departure: follow it now instead of waiting
		if _host_claim != "" and _host_claim == _expected_successor(peer):
			_follow_host(_host_claim)
			return
		waiting_host = true
		host_lost_at = clock
		notice.emit("The host left. Waiting %d s for them to return..." % int(coop_rules().get("host_wait", 60.0)))


func _on_peer_joined(peer: String) -> void:
	if not is_host() and peer == host_id:
		_host_claim = ""        # the host is here: an early claim is void
		if waiting_host:
			waiting_host = false
			notice.emit("The host is back.")
			transport.send(host_id, "hello", {"player": me})


## The member the election rule makes host once `departed` is gone: the first connected member
## in Captain order (CAMPAIGN.md §11), from this member's replica checkpoint.
func _expected_successor(departed: String) -> String:
	var st: Dictionary = ticket.get("state", {}) if not ticket.is_empty() else (ctrl.state if ctrl else {})
	if st.is_empty():
		return ""
	var alive := [me]
	alive.append_array(transport.peers())
	for pid in _captain_order(st):
		if alive.has(pid) and str(pid) != departed:
			return str(pid)
	return ""


## A member claims to host the run now (host_changed). Accepted only from the successor the
## election rule picks after the current host, and only once that host is gone from this
## member's view (a claim that arrives first is held until then). Anything else is ignored.
func _consider_host_claim(from: String) -> void:
	if from == host_id:
		return
	if from != _expected_successor(host_id):
		notice.emit("Ignored a host change claimed by %s (not the party's next host)." % from)
		return
	if transport.peers().has(host_id):
		_host_claim = from
		return
	_follow_host(from)


func _follow_host(new_host: String) -> void:
	host_id = new_host
	waiting_host = false
	_host_claim = ""
	notice.emit("%s is now hosting the run." % new_host)
	transport.send(new_host, "hello", {"player": me})


## Rejoin after a disconnect: ask the host to hand our fighter back at the next node boundary.
func rejoin() -> void:
	if not is_host():
		transport.send(host_id, "rejoin", {"player": me})


func _elect_new_host() -> void:
	waiting_host = false
	if ticket.is_empty() or not RunStore.ticket_valid(ticket):
		suspended = true
		notice.emit("The host left and no valid checkpoint is available. The run stays suspended in the host's save.")
		return
	var st: Dictionary = ticket["state"]
	var next := _expected_successor(host_id)
	if transport.peers().is_empty():
		suspended = true
		notice.emit("Everyone left. The run is suspended; any member can resume it later from their party save.")
		return
	var old_host := host_id
	host_id = next
	if next == me:
		ctrl = RunController.from_state(catalog, st.duplicate(true))
		var op := ctrl.player(old_host)
		if not op.is_empty():
			op["connected"] = false
			op["bot"] = true
		for p in ctrl.players():
			if str(p["id"]) != me and not transport.peers().has(str(p["id"])):
				p["connected"] = false
				p["bot"] = true
		_init_budgets()
		vote = null
		event_vote = null
		_fight_announced = ""
		transport.send("", "host_changed", {"host": me})
		notice.emit("You are now hosting the run (resumed from the last node).")
		_after_change("host_migrated")
	else:
		notice.emit("%s takes over as host." % next)


## Members in Captain order: the run's current Captain first, then the party order.
func _captain_order(st: Dictionary) -> Array:
	var ids := RunState.player_ids(st)
	var tmp := RunController.from_state(catalog, st)
	var cap := tmp.captain()
	var out := []
	var start := maxi(0, ids.find(cap))
	for i in ids.size():
		out.append(ids[(start + i) % ids.size()])
	return out
