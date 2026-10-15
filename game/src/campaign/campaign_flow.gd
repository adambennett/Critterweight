class_name CampaignFlow
extends RefCounted
## Glue between a run (RunController, or a CoopSession for parties) and the game shell: which
## screen shows which phase, launching presented matches through App.start_match, autosaving at
## every committed transition, play-time tracking, custom-run marking and end-of-run credit to
## the active profile. Every campaign screen receives the flow as params["flow"]; there is no
## global campaign state.
##   map -> run_map · fight -> App.start_match -> (result) · event -> event · shop -> shop ·
##   rest -> rest · reward -> reward · victory/defeat -> run_summary

var catalog: CampaignCatalog
var ctrl: RunController
var coop: CoopSession = null
var store: RunStore
var me := "p0"
var report: Dictionary = {}
var notices: Array = []
var intro_seen := {}             ## act -> true once its intro card was shown this session
var _last_ms := 0


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
		out.append("reduced game speed")
	if stand_ins:
		out.append("development stand-in creatures")
	return out


static func start(cat: CampaignCatalog, cfg: Dictionary) -> CampaignFlow:
	var f := CampaignFlow.new()
	f.catalog = cat
	f.store = RunStore.new()
	f.ctrl = RunController.start_run(cat, cfg)
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
	_last_ms = Time.get_ticks_msec()


## True for The Bookie's Table (screens adapt labels: "hand back" instead of "suspend").
func is_bookie() -> bool:
	return false


func profile_id() -> String:
	return Profiles.id() if Profiles.id() != "" else "default"


func save(_st = null) -> void:
	_tick_time()
	if ctrl.is_over():
		return
	var err := store.save(ctrl.state, profile_id())
	if err != OK:
		notices.append("Could not save the run (%s)." % error_string(err))


func _tick_time() -> void:
	var now := Time.get_ticks_msec()
	if _last_ms > 0:
		ctrl.add_time((now - _last_ms) / 1000.0)
	_last_ms = now


## Shows the screen for the current phase (or launches the pending fight).
func show_current() -> void:
	match ctrl.phase():
		"map":
			App.goto("run_map", {"flow": self})
		"fight":
			launch_fight()
		"event":
			App.goto("event", {"flow": self})
		"shop":
			App.goto("shop", {"flow": self})
		"rest":
			App.goto("rest", {"flow": self})
		"reward":
			if ctrl.pending_for(me).is_empty():
				App.goto("run_map", {"flow": self})
			else:
				App.goto("reward", {"flow": self})
		"victory", "defeat":
			finish()


func launch_fight() -> void:
	var built := ctrl.match_config({"player_kinds": {me: "player"}, "bot_tier_players": "contender"})
	if not (built["errors"] as PackedStringArray).is_empty() or (built["config"] as Dictionary).is_empty():
		# never strand the player: the map screen explains and offers suspend or forfeit
		App.goto("run_map", {"flow": self, "fight_error": "\n".join(built["errors"])})
		return
	SimSpeed.restore()
	# the pause menu's "Restart fight" replays MatchFlow.last_config; a campaign fight must not
	# restart into an unrelated earlier match (quitting keeps the run at this fight instead)
	MatchFlow.last_config = {}
	App.start_match(built["config"], _on_match_finished)


func _on_match_finished(result: Dictionary) -> void:
	App.set_scene(null)
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
func restart(same_seed: bool, dose_delta := 0) -> void:
	var cfg: Dictionary = ctrl.state.get("start_cfg", {}).duplicate(true)
	cfg["seed"] = int(ctrl.state.get("seed", 0)) if same_seed else 0
	cfg["seeded"] = same_seed
	cfg["dose"] = clampi(int(cfg.get("dose", 0)) + dose_delta, 0, 10)
	cfg["created_at"] = int(Time.get_unix_time_from_system())
	cfg.erase("run_id")
	if str(cfg.get("variant", "")) == "fight_camp":
		for p in cfg.get("players", []):
			p["meta"] = FightCamp.meta_levels(Profiles.current)
	var f := CampaignFlow.start(catalog, cfg)
	f.show_current()
