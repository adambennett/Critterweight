class_name BookieFlow
extends CampaignFlow
## CampaignFlow for The Bookie's Table: when the player has taken over, decisions use the very
## same campaign screens (map, reward, event, shop, rest); whenever control should go back to
## the table (a fight is next, the run ended, or the player hands back), it returns to the
## Bookie screen and releases the table's loop. Runs at the table are not autosaved (the table
## is a session); they are credited by the table to the "bookie" record board.
## Screens follow CampaignFlow.current_screen (a pending pick first — e.g. Train at a rest).
## Every presented fight re-applies the table's speed (SimSpeed: k x physics ticks at the fixed
## 1/120 s step): a finished MatchScene resets Engine.time_scale on its way out.

var table: BookieTable
var watching := true             ## fights presented (true) or fast-forwarded headless (false)
var log_lines: Array = []        ## newest first: what happened at the table (for the live view)
var _scene: MatchScene = null
var _fight_done := false
var _fight_result := {}


static func for_table(t: BookieTable) -> BookieFlow:
	var f := BookieFlow.new()
	f.table = t
	f.catalog = t.catalog
	f.ctrl = t.ctrl
	f.store = RunStore.new()
	t.decision_needed.connect(f._on_decision_needed)
	t.run_over.connect(f._on_run_over)
	t.fight_started.connect(f._on_fight_started)
	t.changed.connect(f._on_changed)
	t.fight_runner = f.run_fight
	t.set_meta("bookie_flow", f)     # the table keeps its flow alive (Callables do not)
	return f


func note(line: String) -> void:
	log_lines.push_front(line)
	while log_lines.size() > 40:
		log_lines.pop_back()


func _on_run_over(summary: Dictionary) -> void:
	var rep: Dictionary = summary.get("report", {})
	note("RUN %d: %s in Act %d (%s) · +%d Clout" % [table.runs_completed, "TITLE WON" if bool(summary.get("victory", false)) else "knocked out",
		int(summary.get("act", 1)), CampaignUI.fmt_time(float(summary.get("elapsed", 0.0))), int(rep.get("clout", 0))])
	if not table.profile.is_empty():
		Profiles.save()


func _on_fight_started(info: Dictionary) -> void:
	note("Fight: %s" % str(info.get("name", info.get("encounter", ""))))


func _on_changed(what: String) -> void:
	if what != "phase" or table.transitions.is_empty():
		return
	var tr: Dictionary = table.transitions.back()
	match str(tr.get("to", "")):
		"reward":
			if str(tr.get("from", "")) == "fight":
				var lf := table.ctrl.last_fight()
				note("  won in %s" % CampaignUI.fmt_time(float(lf.get("time", 0.0))))
		"event":
			note("Event: %s" % str(table.ctrl.event_view("p0").get("title", "")))
		"shop":
			note("Shop: Needles' pop-up stall")
		"rest":
			note("Rest stop")
		"victory":
			note("THE TITLE IS WON!")
		"defeat":
			note("Knocked out.")


## The table's fight runner: a presented match (App.start_match) while watching, otherwise the
## headless fast-forward runner. Pause freezes the match (sim + its physics space).
func run_fight(t: BookieTable, config: Dictionary) -> Dictionary:
	if not watching:
		return await HeadlessFightRunner.run(t, config, 420.0, t._is_paused, t.is_stopping)
	_fight_done = false
	_fight_result = {}
	MatchFlow.last_config = {}     # no "Restart fight" into an unrelated earlier match
	# the previous presented fight's MatchScene reset Engine.time_scale when it ended/left the
	# tree (physics ticks stayed at k x): restore the table's speed and the fixed sim step
	SimSpeed.set_scale(t.speed)
	_scene = App.start_match(config, _on_presented_finished)
	App.push("bookie", {"overlay": true})
	var space := _scene.get_world_3d().space if _scene.get_world_3d() else RID()
	var frozen := false
	while not _fight_done:
		var hold := t.paused
		if hold != frozen:
			if space.is_valid():
				PhysicsServer3D.space_set_active(space, not hold)
			if is_instance_valid(_scene) and _scene.sim:
				_scene.sim.paused = hold
			frozen = hold
		await t.get_tree().process_frame
	if frozen and space.is_valid():
		PhysicsServer3D.space_set_active(space, true)
	App.set_scene(null)
	_scene = null
	App.goto("bookie", {})
	return _fight_result


func _on_presented_finished(result: Dictionary) -> void:
	_fight_result = result
	_fight_done = true


## Ends a presented fight early (STOP at the table): the fight counts as lost.
func abort_fight() -> void:
	if _scene != null and not _fight_done:
		_fight_result = {"campaign": {"won": false, "time": 0.0, "players": {}, "error": "stopped at the table"}}
		_fight_done = true


func is_bookie() -> bool:
	return true


func _on_decision_needed(_kind: String) -> void:
	show_current()


func save(_st = null) -> void:
	pass


func show_current() -> void:
	ctrl = table.ctrl
	if table.unattended:
		return_to_table()
		return
	ctrl.advance_if_done()
	var screen := current_screen()
	if screen == "run_map" and ctrl.phase() != "map":
		screen = ""          # this player's part of the node is done: the table moves on
	match screen:
		"", "fight", "summary":
			return_to_table()
		_:
			App.goto(screen, {"flow": self})


## Back to the Bookie screen; the table continues (fight next, or Teddy decides again).
func return_to_table() -> void:
	var top := App.top_screen()
	if top == null or top.screen_name != "bookie":
		App.goto("bookie", {})
	table.player_decided()


func launch_fight() -> void:
	return_to_table()


## "Suspend" at the table means: hand the decisions back to Teddy.
func suspend() -> void:
	table.hand_back()
	return_to_table()


func abandon() -> void:
	ctrl.abandon()
	return_to_table()


func finish() -> void:
	return_to_table()
