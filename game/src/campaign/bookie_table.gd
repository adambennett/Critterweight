class_name BookieTable
extends Node
## The Bookie's Table (MODES.md §1, CAMPAIGN.md §12): a full fight card where AI ("Teddy's
## dice") pilots every fight while the player chooses fighter, route, rewards, shop and rest —
## or, unattended, Teddy makes those choices too (CampaignAutoPilot heuristic) and the table
## keeps going, optionally starting the next card when one ends.
## Controls: pause()/resume() (also freezes a fight in progress), set_speed(1..4; tests use
## more: the simulation step never changes, only how many steps run per second), take_over()
## (decisions wait for the player from the next decision point on) and hand_back().
## Presentation is pluggable: `fight_runner` (async Callable(table, match_config) -> result)
## defaults to a headless fight; the Bookie screen plugs in a presented match and its camera.
## Records go to their own board ("bookie") with Clout at 50% (CampaignProgression).

signal changed(what: String)
signal decision_needed(kind: String)
signal decision_made()
signal fight_started(info: Dictionary)
signal run_over(summary: Dictionary)
signal stopped()                      ## the play() loop has ended

var catalog: CampaignCatalog
var ctrl: RunController
var profile: Dictionary = {}          ## credited at the end of each run (Profiles.current at runtime)
var unattended := true
var paused := false
var speed := 1.0
var camera := "broadcast"             ## presented fights: broadcast | director | free (BookieFlow.apply_camera)
var fighter_tier := "contender"       ## Teddy's dice
var think_delay := 0.6                ## seconds between automatic decisions (0 = instant)
var keep_going := false               ## unattended: deal a new card after each run
var max_runs := 0                     ## with keep_going: stop after this many runs (0 = no limit)
var fight_runner: Callable = Callable()
var base_cfg := {}
var runs_completed := 0
var transitions: Array = []           ## [{from, to, what}] (diagnostics, unattended tests)
var results: Array = []               ## summaries of finished runs
var running := false
var waiting_for_player := false       ## attended: the table waits for the player's decision
var in_fight := false
var current_fight := {}               ## {encounter, name} of the fight being played
var _stop := false
var _decided := false


func setup(cat: CampaignCatalog, cfg: Dictionary, prof: Dictionary = {}) -> void:
	catalog = cat
	profile = prof
	base_cfg = cfg.duplicate(true)
	base_cfg["mode"] = "bookie"
	_new_card(int(cfg.get("seed", 0)))


func _new_card(seed_value: int) -> void:
	var cfg := base_cfg.duplicate(true)
	cfg["seed"] = seed_value
	cfg["run_id"] = "bookie_%d_%d" % [runs_completed, Time.get_ticks_usec()]
	ctrl = RunController.start_run(catalog, cfg)
	changed.emit("new_card")


## Deals a fresh card with the same settings (e.g. after a run ended and the loop stopped).
func deal(seed_value := 0) -> void:
	paused = false
	waiting_for_player = false
	_decided = false
	_new_card(seed_value)


const CAMERAS := ["broadcast", "director", "free"]
const CAMERA_LABELS := {"broadcast": "Broadcast", "director": "Director", "free": "Free"}


func set_camera(c: String) -> void:
	camera = c if c in CAMERAS else "broadcast"
	changed.emit("camera")


func set_speed(k: float) -> void:
	speed = clampf(k, 0.25, 64.0)
	if running:
		SimSpeed.set_scale(speed)
	changed.emit("speed")


func pause() -> void:
	paused = true
	changed.emit("paused")


func resume() -> void:
	paused = false
	changed.emit("resumed")


func take_over() -> void:
	unattended = false
	changed.emit("take_over")


func hand_back() -> void:
	unattended = true
	changed.emit("hand_back")
	_release()


## Ends the loop at the next decision point (or after the fight in progress).
func stop() -> void:
	_stop = true
	_release()


func is_stopping() -> bool:
	return _stop


## Called by the UI after the player made a decision through ctrl (attended mode). Safe to call
## at any time — also synchronously from a decision_needed handler (no lost wake-up).
func player_decided() -> void:
	_release()


func _release() -> void:
	_decided = true
	decision_made.emit()


func _is_paused() -> bool:
	return paused


## Main loop. Returns when stopped, or when the run ends and keep_going is off (or max_runs).
func play() -> void:
	running = true
	_stop = false
	SimSpeed.set_scale(speed)
	var guard := 0
	while not _stop and guard < 100000:
		guard += 1
		if paused:
			await get_tree().process_frame
			continue
		var before := ctrl.phase()
		match before:
			"victory", "defeat":
				_finish_run()
				if not keep_going or (max_runs > 0 and runs_completed >= max_runs):
					break
				_new_card(RunRng.derive(int(ctrl.state.get("seed", 1)), "next/%d" % runs_completed))
				continue
			"fight":
				var built := ctrl.match_config({"bot_tier_players": fighter_tier, "player_kinds": {"p0": "bot"}})
				current_fight = {"encounter": ctrl.current_plan().get("encounter", ""), "name": ctrl.current_plan().get("name", "")}
				if not (built["errors"] as PackedStringArray).is_empty() or (built["config"] as Dictionary).is_empty():
					# content missing: the card cannot go on; the fight counts as lost
					push_warning("bookie fight could not be built: %s" % "; ".join(built["errors"]))
					ctrl.complete_fight({"campaign": {"won": false, "time": 0.0, "players": {}, "error": "; ".join(built["errors"])}})
				else:
					in_fight = true
					fight_started.emit(current_fight)
					var res: Dictionary = {}
					if fight_runner.is_valid():
						res = await fight_runner.call(self, built["config"])
					else:
						res = await HeadlessFightRunner.run(self, built["config"], 420.0, _is_paused, is_stopping)
					in_fight = false
					ctrl.complete_fight(res)
			_:
				if unattended:
					if think_delay > 0.0:
						# real-time pause between Teddy's decisions; pause/stop/take-over cut it short
						var until := Time.get_ticks_msec() + int(think_delay * 1000.0)
						while Time.get_ticks_msec() < until and not _stop and not paused and unattended:
							await get_tree().process_frame
					if _stop or paused or not unattended:
						continue
					if before == "map":
						ctrl.choose_node(CampaignAutoPilot.choose_route(ctrl, "p0"), "p0")
					elif not CampaignAutoPilot.settle(ctrl, ["p0"]):
						await get_tree().process_frame
				else:
					_decided = false
					waiting_for_player = true
					decision_needed.emit(before)
					if not _decided:
						await decision_made
					waiting_for_player = false
		if ctrl.phase() != before:
			transitions.append({"from": before, "to": ctrl.phase(), "node": str(ctrl.state.get("position", ""))})
			changed.emit("phase")
	running = false
	SimSpeed.restore()
	stopped.emit()


func _finish_run() -> void:
	runs_completed += 1
	var summary := ctrl.summary()
	summary["run_id"] = str(ctrl.state.get("run_id", ""))
	if not profile.is_empty():
		summary["report"] = CampaignProgression.finish_run(catalog, ctrl.state, "p0", profile)
	results.append(summary)
	run_over.emit(summary)
