class_name CampaignFlow
extends RefCounted
## Glue between a run (RunController, or a CoopSession for parties) and the game shell: which
## screen shows which phase, launching presented matches through App.start_match, autosaving at
## every committed transition, play-time tracking, custom-run marking and end-of-run credit to
## the active profile. Every campaign screen receives the flow as params["flow"]; there is no
## global campaign state.
##   map -> run_map · fight -> App.start_match -> (result) · event -> event · shop -> shop ·
##   rest -> rest · reward -> reward · victory/defeat -> run_summary
## Invariants:
##   * A pending pick of this player always comes first in any phase but a fight (Train at a
##     rest, an event's pick, a consumable's pick in a shop): current_screen() never sends a
##     screen back to itself once its own step is done, so screens never bounce.
##   * Play time = time in menus + each fight's simulated time, counted once: the wall clock is
##     stopped while a presented fight runs (the fight adds its own time when it is applied).
##   * "Custom" is re-checked before every fight and when a card is run back; a run that became
##     custom stays custom (RunController.mark_custom).
##   * A new run never silently replaces a suspended one: callers ask (menu, hub), and whatever
##     is still in the slot is credited as abandoned before the new run is saved. A run saved by
##     a newer game version is never touched at all (the menus refuse to deal over it).

const REASON_GAME_SPEED := "reduced game speed"
const REASON_STAND_INS := "development stand-in creatures"
## Custom reasons that can change while a run goes on (re-checked before fights and on "Run it
## back"); any other reason (a test build, custom rules) is fixed when the card is dealt.
const LIVE_REASONS := [REASON_GAME_SPEED, REASON_STAND_INS]

var catalog: CampaignCatalog
var ctrl: RunController
var coop: CoopSession = null
var store: RunStore
var me := "p0"
var report: Dictionary = {}
var notices: Array = []
var intro_seen := {}             ## act -> true once its intro card was shown this session
var _last_ms := 0                ## wall clock of the last time tick; 0 while a presented fight runs


## Developer switches (the campaign's development stand-ins) stay hidden in normal play. They show
## with --dev or --campaign-stand-ins on the command line or Settings > Diagnostics > Developer
## tools. (Screens may still be opened with params.stand_ins by tests and tools.)
static var force_dev_tools := false      ## tests


static func dev_tools() -> bool:
	if force_dev_tools:
		return true
	var a := OS.get_cmdline_user_args()
	return a.has("--dev") or a.has("--campaign-stand-ins") or Settings.get_value("diag.dev_tools") == true


static func make_catalog(stand_ins: bool) -> CampaignCatalog:
	return CampaignCatalog.new(Content, "dev_biped" if stand_ins else "")


## Reasons a run started now would be "custom" (no records/ladder; still stats/history).
static func custom_reasons(stand_ins: bool, extra: Array = []) -> Array:
	var out := extra.duplicate()
	if Settings.get_value("access.game_speed") != null and float(Settings.get_value("access.game_speed")) < 0.999:
		if not out.has(REASON_GAME_SPEED):
			out.append(REASON_GAME_SPEED)
	if stand_ins and not out.has(REASON_STAND_INS):
		out.append(REASON_STAND_INS)
	return out


static func start(cat: CampaignCatalog, cfg: Dictionary) -> CampaignFlow:
	var c: Dictionary = cfg.duplicate(true)
	if str(c.get("mode", "campaign")) != "bookie":
		# a Dose this profile has not unlocked (or one on Sparring) is never started
		c["dose"] = CampaignProgression.clamp_dose(cat, Profiles.current, str(c.get("variant", "off_the_street")),
			str(c.get("difficulty", "amateur")), int(c.get("dose", 0)))
	# the menus ask before replacing a suspended run; anything still in the slot is credited as
	# abandoned here rather than overwritten
	abandon_suspended(cat, RunStore.slot_for(c))
	var f := CampaignFlow.new()
	f.catalog = cat
	f.store = RunStore.new()
	f.ctrl = RunController.start_run(cat, c)
	f._hook()
	f.save()
	return f


static func resume(cat: CampaignCatalog, st: Dictionary) -> CampaignFlow:
	var f := CampaignFlow.new()
	f.catalog = cat
	f.store = RunStore.new()
	f.ctrl = RunController.from_state(cat, st)
	f._hook()
	return f


func _hook() -> void:
	ctrl.autosave = save
	_last_ms = maxi(1, Time.get_ticks_msec())


# =============================================================================================
# Suspended runs of the active profile (one slot per variant)
# =============================================================================================

static func profile_key() -> String:
	return Profiles.id() if Profiles.id() != "" else "default"


## The run suspended in `slot` of the active profile ({} if the slot is free):
## {slot, ok, error, newer, summary} like RunStore.list rows. `newer`: saved by a newer game
## version — it is never replaced, moved or deleted (a new run cannot take that slot).
static func suspended_run(cat: CampaignCatalog, slot: String) -> Dictionary:
	var res := RunStore.new().load_slot(profile_key(), slot, cat)
	if not bool(res.get("exists", false)):
		return {}
	return {"slot": slot, "ok": bool(res["ok"]), "error": str(res["error"]), "newer": bool(res.get("newer", false)),
		"summary": RunStore.summarize(res.get("state", {}))}


## Abandons the run suspended in `slot` of the active profile: it is credited as an abandoned
## defeat (history and attempts; CampaignProgression.finish_run, idempotent per run) and its
## slot is cleared. A save that cannot be loaded is moved aside, never deleted; one saved by a
## newer game version is left exactly as it is. Returns the credit report ({} when the slot was
## free, unreadable or newer).
static func abandon_suspended(cat: CampaignCatalog, slot: String) -> Dictionary:
	var rs := RunStore.new()
	var key := profile_key()
	var res := rs.load_slot(key, slot, cat)
	if not bool(res.get("exists", false)) or bool(res.get("newer", false)):
		return {}
	if not bool(res["ok"]):
		rs.quarantine(key, slot)
		return {}
	var c := RunController.from_state(cat, res["state"])
	c.abandon()
	var rep := CampaignProgression.finish_run(cat, c.state, local_player_id(c.state), Profiles.current)
	Profiles.save()
	rs.clear(key, slot)
	return rep


## The player of a run that belongs to the active profile (party saves hold every member).
static func local_player_id(st: Dictionary) -> String:
	var pid := Profiles.id()
	for p in st.get("players", []):
		if pid != "" and str(p.get("profile_id", "")) == pid:
			return str(p.get("id", "p0"))
	var ids := RunState.player_ids(st)
	return str(ids[0]) if not ids.is_empty() else "p0"


## One line describing a suspended run (RunStore.summarize) for confirmations.
static func describe_suspended(cat: CampaignCatalog, s: Dictionary) -> String:
	if s.is_empty():
		return "an unreadable save"
	var names := []
	for fid in s.get("fighters", []):
		names.append(CampaignUI.fighter_name(cat, str(fid)))
	var dose := int(s.get("dose", 0))
	return "%s · Act %d · %s · %s%s" % [str(s.get("variant", "")).replace("_", " ").capitalize(), int(s.get("act", 1)),
		", ".join(names), str(cat.difficulty(str(s.get("difficulty", ""))).get("name", s.get("difficulty", ""))),
		(" · Dose %d" % dose) if dose > 0 else ""]


# =============================================================================================
# The running card
# =============================================================================================

## True for The Bookie's Table (screens adapt labels: "hand back" instead of "suspend").
func is_bookie() -> bool:
	return false


## True for an online party run (CoopFlow): decisions travel to the party's host and the screens
## refresh when the shared run changes, not right after a button press.
func is_party() -> bool:
	return false


## Party runs: one status line for the screens (who is deciding what, the vote, the Captain).
func party_text() -> String:
	return ""


## Party runs: the route / group-event vote on screen ({} = none; CoopSession.vote_view).
func vote_view() -> Dictionary:
	return {}


## Party runs: the latest event outcome at this node (CoopSession.last_event; {} = none).
func party_event() -> Dictionary:
	return {}


## The player read an event's outcome (CONTINUE).
func ack_event() -> void:
	pass


# ---------------------------------------------------------------------------------------------
# This player's decisions. Screens call these; a solo run applies them at once (false + the reason
# in error_text() when refused). CoopFlow sends them to the party's host instead.
# ---------------------------------------------------------------------------------------------

func error_text() -> String:
	return ctrl.last_error


func do_claim(rid: String, choice: String) -> bool:
	return ctrl.claim(me, rid, choice)


func do_reroll(rid: String) -> bool:
	return ctrl.reroll(me, rid)


func do_event(choice: String) -> bool:
	return ctrl.choose_event(me, choice)


func do_shop_buy(slot: String) -> bool:
	return ctrl.shop_buy(me, slot)


func do_shop_service() -> bool:
	return ctrl.shop_service(me)


func do_shop_sell(item: String) -> bool:
	return ctrl.shop_sell(me, item)


func do_shop_leave() -> bool:
	return ctrl.shop_leave(me)


func do_rest(option: String) -> bool:
	return ctrl.rest_choose(me, option)


func do_consume(item: String) -> bool:
	return ctrl.use_consumable(me, item)


func profile_id() -> String:
	return profile_key()


## Whether this flow's catalog fills missing creatures with development stand-ins.
func uses_stand_ins() -> bool:
	return catalog != null and catalog.resolver.stand_in != ""


func save(_st = null) -> void:
	_tick_time()
	if ctrl.is_over():
		return
	var err := store.save(ctrl.state, profile_id())
	if err != OK:
		notices.append("Could not save the run (%s)." % error_string(err))


func _tick_time() -> void:
	if _last_ms <= 0:
		return      # a presented fight is running: it adds its own (simulated) time
	var now := maxi(1, Time.get_ticks_msec())
	ctrl.add_time((now - _last_ms) / 1000.0)
	_last_ms = now


## The screen for the current state: "summary" | "fight" | "reward" | "event" | "shop" | "rest" |
## "run_map". A pending pick of this player comes first in every phase but a fight; once this
## player's part of a shop or rest is done (others may still be deciding), it is the map.
func current_screen() -> String:
	if ctrl.is_over():
		return "summary"
	var ph := ctrl.phase()
	if ph == "fight":
		return "fight"
	if ph != "map" and not ctrl.pending_for(me).is_empty():
		return "reward"
	match ph:
		"event":
			return "event" if ctrl.session().has("event") else "run_map"
		"shop":
			return "run_map" if bool(ctrl.shop_view(me).get("done", true)) else "shop"
		"rest":
			return "run_map" if bool(ctrl.session().get("rest", {}).get(me, {}).get("done", true)) else "rest"
	return "run_map"


## Shows the screen for the current state (or launches the pending fight).
func show_current() -> void:
	ctrl.advance_if_done()      # repairs runs saved mid-transition by older builds
	match current_screen():
		"summary":
			finish()
		"fight":
			launch_fight()
		var screen:
			App.goto(screen, {"flow": self})


func launch_fight() -> void:
	var built := ctrl.match_config({"player_kinds": {me: "player"}, "bot_tier_players": "contender"})
	if not (built["errors"] as PackedStringArray).is_empty() or (built["config"] as Dictionary).is_empty():
		# never strand the player: the map screen explains and offers suspend or forfeit
		App.goto("run_map", {"flow": self, "fight_error": "\n".join(built["errors"])})
		return
	begin_fight()
	SimSpeed.restore()
	# the pause menu's "Restart fight" replays MatchFlow.last_config; a campaign fight must not
	# restart into an unrelated earlier match (quitting keeps the run at this fight instead)
	MatchFlow.last_config = {}
	var scene := App.start_match(built["config"], _on_match_finished)
	# Callables do not retain RefCounted targets. The map screen is freed when the
	# fight starts, so the fight must own its flow until the next decision screen does.
	if scene != null:
		scene.set_meta("campaign_flow", self)


## Right before a presented fight: re-check what makes a run custom (the game speed may have
## been lowered since the last fight), then stop the wall clock — the fight adds its own
## simulated time when it is applied, so it is never counted twice.
func begin_fight() -> void:
	ctrl.mark_custom(custom_reasons(uses_stand_ins()))
	_tick_time()
	_last_ms = 0


func _on_match_finished(result: Dictionary) -> void:
	App.set_scene(null)
	_last_ms = maxi(1, Time.get_ticks_msec())     # menus count again from here
	ctrl.complete_fight(result)
	show_current()


## Gives up a fight that cannot be played (content missing): counts as a lost fight.
func forfeit_fight() -> void:
	if ctrl.phase() == "fight":
		ctrl.complete_fight({"campaign": {"won": false, "time": 0.0, "players": {}, "error": "forfeit"}})
	show_current()


## Route choice from the map screen.
func choose_node(id: String) -> bool:
	var ok := ctrl.choose_node(id, me)
	if ok:
		show_current()
	return ok


func after_decision() -> void:
	show_current()


func suspend() -> void:
	save()
	App.set_scene(null)
	App.goto("campaign_menu")


func abandon() -> void:
	ctrl.abandon()
	finish()


## Credits the finished run to the active profile (idempotent) and shows the results card.
func finish() -> void:
	_tick_time()
	if report.is_empty():
		report = CampaignProgression.finish_run(catalog, ctrl.state, me, Profiles.current)
		Profiles.save()
		CampaignProgression.grant_achievements(report, Profiles.current)
		store.clear(profile_id(), RunStore.slot_for(ctrl.state))
	App.goto("run_summary", {"flow": self})


## A new run with the same settings ("Run it back" keeps the seed; "New card" draws a new one).
## Whether it is custom is decided afresh: live reasons (game speed, stand-ins) are checked now,
## reasons fixed at the original deal (a test build, custom rules) carry over.
func restart(same_seed: bool, dose_delta := 0) -> void:
	var cfg: Dictionary = ctrl.state.get("start_cfg", {}).duplicate(true)
	cfg["seed"] = int(ctrl.state.get("seed", 0)) if same_seed else 0
	cfg["seeded"] = same_seed
	cfg["dose"] = clampi(int(cfg.get("dose", 0)) + dose_delta, 0, 10)
	cfg["created_at"] = int(Time.get_unix_time_from_system())
	cfg.erase("run_id")
	var old_reasons: Array = cfg.get("custom_reasons", [])
	var fixed := []
	for r in old_reasons:
		if not LIVE_REASONS.has(str(r)):
			fixed.append(str(r))
	var reasons := custom_reasons(uses_stand_ins(), fixed)
	cfg["custom_reasons"] = reasons
	cfg["custom"] = not reasons.is_empty() or (bool(cfg.get("custom", false)) and old_reasons.is_empty())
	if str(cfg.get("variant", "")) == "fight_camp":
		for p in cfg.get("players", []):
			p["meta"] = FightCamp.meta_levels(Profiles.current)
	var f := CampaignFlow.start(catalog, cfg)
	f.show_current()
