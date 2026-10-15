extends Screen
## AI Lab screen (App screen "lab"): configure and launch training, watch live progress and
## learning curves, pause/resume/cancel/resume-after-crash, browse checkpoints and evaluation
## reports, manage the policy library (rename, export, import with validation errors, delete,
## evaluate, fight, spectate) and imitation recording / datasets.
## All work happens in worker processes (LabManager); this screen only reads small files on a
## timer, so it never stalls. Fully operable with a controller (D-pad/stick + A/B, LB/RB switch
## tabs) and with mouse/keyboard (PageUp/PageDown switch tabs).
## Plain Godot controls styled minimally (LabUi) so the shared UI theme can be adopted later.

const TAB_NAMES: PackedStringArray = ["Train", "Runs", "Policies", "Recording"]
const APPROACHES: PackedStringArray = ["es", "bc", "bc_es"]
const APPROACH_NAMES: PackedStringArray = ["Evolution strategies (reward)", "Behaviour cloning (imitation)", "Clone, then evolve (BC → ES)"]
const NET_SIZES := [[16], [32, 32], [64, 64], [96, 96]]
const NET_NAMES: PackedStringArray = ["Tiny 16 (fastest)", "Small 32×32 (default for ES)", "Medium 64×64 (default for imitation)", "Large 96×96 (slow)"]

## Opened from the AI Lab terminal in the Cannery's Boiler Room (params.from_hub): leaving walks
## back there instead of the main menu (kept across the Lab's own fight/spectate round trips).
static var return_to_hub := false

var _tab := 0
var _tab_buttons: Array[Button] = []
var _panels: Array[Control] = []
var _status: Label
var _timer: Timer
var _tick := 0
var _chart_sig := ""                      ## run dir + metrics size of the curve on screen
var _job_dir := ""                        ## run whose job is cached in _job (a job never changes)
var _job := {}
var _ckpt_files := ""                     ## run dir + checkpoint file names behind _ckpt_rows
var _ckpt_rows := PackedStringArray()     ## checkpoint rows on screen

# ---- train ----
var _creatures: Array = []
var _fighter: OptionButton
var _approach: OptionButton
var _objective: OptionButton
var _weights_grid: GridContainer
var _weight_boxes := {}
var _scenario: OptionButton
var _opp_checks := {}
var _round_time: HBoxContainer
var _spawn: OptionButton
var _seed := 1
var _seed_label: Label
var _dataset: OptionButton
var _dataset_paths: Array = []
var _init_policy: OptionButton
var _init_paths: Array = []
var _net: OptionButton
var _lim_minutes: HBoxContainer
var _lim_steps: HBoxContainer
var _lim_episodes: HBoxContainer
var _workers: HBoxContainer
var _worlds: HBoxContainer
var _cpu: HBoxContainer
var _low_prio: CheckBox
var _es_pairs: HBoxContainer
var _es_sigma: HBoxContainer
var _es_lr: HBoxContainer
var _es_eps: HBoxContainer
var _bc_epochs: HBoxContainer
var _run_name: LineEdit
var _start_btn: Button
var _train_help: RichTextLabel

# ---- runs ----
var _runs_list: ItemList
var _runs: Array = []
var _run_dir := ""
var _run_info: RichTextLabel
var _chart: LabChart
var _ckpts: ItemList
var _report: RichTextLabel
var _btn_pause: Button
var _btn_resume: Button
var _btn_cancel: Button
var _btn_continue: Button
var _btn_snapshot: Button
var _btn_delete_run: Button
var _delete_run_armed := ""

# ---- policies ----
var _pol_list: ItemList
var _pols: Array = []
var _pol_info: RichTextLabel
var _rename_edit: LineEdit
var _export_edit: LineEdit
var _import_edit: LineEdit
var _import_pick: OptionButton
var _import_files: Array = []
var _player_creature: OptionButton
var _spectate_opp: OptionButton
var _spectate_keys: Array = []
var _delete_pol_armed := ""

# ---- recording ----
var _rec_toggle: CheckBox
var _rec_fighter: Label
var _ds_list: ItemList
var _dss: Array = []
var _ds_rename: LineEdit
var _teacher: OptionButton
var _teacher_opp: OptionButton
var _teacher_eps: HBoxContainer
var _delete_ds_armed := ""


func on_enter(p: Dictionary) -> void:
	return_to_hub = bool(p.get("from_hub", false))
	# the shared UiTheme is applied by Screen; this screen only adds an opaque backdrop
	var bg := ColorRect.new()
	bg.color = UiTheme.BG_DEEP
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var frame := build_frame("Train real fighters", "AI Lab", std_prompts([{"actions": ["ui_tab_prev", "ui_tab_next"], "text": "Switch tab"}]))
	(frame["header"] as VBoxContainer).add_child(LabUi.label("Policies learn on this PC in background worker processes — the game stays responsive while they train.", "BodyMuted"))
	var col: VBoxContainer = frame["body"]
	var tabs := UiTheme.hbox(UiTheme.GAP_S)
	col.add_child(tabs)
	for i in TAB_NAMES.size():
		var b := LabUi.button(TAB_NAMES[i], _select_tab.bind(i), 230, "TabButton")
		tabs.add_child(b)
		_tab_buttons.append(b)
	var body := Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	_panels.append(_build_train())
	_panels.append(_build_runs())
	_panels.append(_build_policies())
	_panels.append(_build_recording())
	for pnl in _panels:
		pnl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		body.add_child(pnl)
	_status = LabUi.label("", "CaptionStrong", UiTheme.WARNING)
	col.add_child(_status)
	_timer = Timer.new()
	_timer.wait_time = 0.5
	_timer.autostart = true
	_timer.timeout.connect(_on_timer)
	add_child(_timer)
	_select_tab(int(p.get("tab", 0)))
	_refresh_runs()
	_refresh_policies()
	_refresh_datasets()


func default_focus() -> Control:
	return _tab_buttons[_tab] if not _tab_buttons.is_empty() else null


func on_back() -> bool:
	_go_back()
	return true


func _go_back() -> void:
	if return_to_hub and App.has_screen("hub"):
		return_to_hub = false
		App.goto("hub", {"spot": "boiler_room", "from": "lab"})
		return
	for s in ["main_menu", "title"]:
		if App.has_screen(s):
			App.goto(s)
			return
	_set_status("No menu to return to in this build.")


func _set_status(t: String) -> void:
	_status.text = t
	Log.i("lab", t)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or App.top_screen() != self:
		return
	var step := 0
	# UiNav's tab actions: LB/RB, Q/E, PageUp/PageDown
	if event.is_action_pressed("ui_tab_prev"):
		step = -1
	elif event.is_action_pressed("ui_tab_next"):
		step = 1
	if step != 0:
		get_viewport().set_input_as_handled()
		_select_tab(posmod(_tab + step, TAB_NAMES.size()))
		_tab_buttons[_tab].grab_focus()
		return
	super._unhandled_input(event)


func _select_tab(i: int) -> void:
	_tab = clampi(i, 0, _panels.size() - 1)
	for k in _panels.size():
		_panels[k].visible = k == _tab
		_tab_buttons[k].theme_type_variation = "TabButtonActive" if k == _tab else "TabButton"
	# keep controller focus on something visible (e.g. after Start switches to Runs)
	var fo := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if fo == null or not fo.is_visible_in_tree():
		_tab_buttons[_tab].grab_focus.call_deferred()
	match _tab:
		1:
			_refresh_runs()
		2:
			_refresh_policies()
		3:
			_refresh_datasets()


func _scroll_col() -> Array:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	sc.add_child(v)
	return [sc, v]


# =====================================================================================
# Train tab
# =====================================================================================

func _build_train() -> Control:
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	var sv := _scroll_col()
	var form: VBoxContainer = sv[1]
	(sv[0] as Control).size_flags_stretch_ratio = 1.6
	root.add_child(sv[0])
	form.add_child(LabUi.header("What to train"))
	_creatures = Content.playable_creatures()
	var names := []
	for cid in _creatures:
		var c := Content.creature(str(cid))
		names.append("%s (%s)" % [c.display_name if c else str(cid), str(cid)])
	_fighter = LabUi.option(names)
	_fighter.item_selected.connect(func(_i: int) -> void: _refresh_train_lists())
	LabUi.row(form, "Fighter", _fighter, "Policies are trained per fighter.")
	_approach = LabUi.option(Array(APPROACH_NAMES))
	_approach.item_selected.connect(func(_i: int) -> void: _update_train_help())
	LabUi.row(form, "Approach", _approach)
	var obj_names := []
	for pid in LabRewards.preset_ids():
		obj_names.append(str(LabRewards.PRESETS[pid]["name"]))
	_objective = LabUi.option(obj_names)
	_objective.item_selected.connect(func(_i: int) -> void: _load_preset_weights())
	LabUi.row(form, "Objective / style", _objective)
	var wtoggle := CheckButton.new()
	wtoggle.text = "Edit reward weights"
	wtoggle.focus_mode = Control.FOCUS_ALL
	form.add_child(wtoggle)
	_weights_grid = GridContainer.new()
	_weights_grid.columns = 2
	_weights_grid.visible = false
	form.add_child(_weights_grid)
	wtoggle.toggled.connect(func(on: bool) -> void: _weights_grid.visible = on)
	for t in LabRewards.TERMS:
		var l := LabUi.label(str(t).replace("_", " "))
		l.custom_minimum_size = Vector2(220, 0)
		_weights_grid.add_child(l)
		var sb := LabUi.slider(-20.0, 20.0, 0.05, 0.0, "%.2f")
		_weights_grid.add_child(sb)
		_weight_boxes[t] = sb
	form.add_child(LabUi.header("Against whom"))
	var scn_names := []
	for sid in LabScenarios.preset_ids():
		scn_names.append(str(LabScenarios.PRESETS[sid]["name"]))
	_scenario = LabUi.option(scn_names)
	_scenario.item_selected.connect(func(_i: int) -> void: _load_scenario())
	LabUi.row(form, "Scenario", _scenario)
	var opp_box := GridContainer.new()
	opp_box.columns = 2
	for kind in LabOpponents.BASELINES:
		var cb := CheckBox.new()
		cb.text = LabOpponents.display_name(kind)
		cb.focus_mode = Control.FOCUS_ALL
		opp_box.add_child(cb)
		_opp_checks[kind] = cb
	LabUi.row(form, "Training opponents", opp_box, "Episodes cycle through the checked opponents.")
	_round_time = LabUi.slider(4.0, 99.0, 1.0, 8.0, "%d s")
	LabUi.row(form, "Round length", _round_time)
	_spawn = LabUi.option(["Random positions", "Standard corners"])
	LabUi.row(form, "Starting positions", _spawn)
	var seed_row := HBoxContainer.new()
	_seed_label = LabUi.label("1")
	_seed_label.custom_minimum_size = Vector2(110, 0)
	seed_row.add_child(LabUi.button("−", func() -> void: _set_seed(_seed - 1), 50))
	seed_row.add_child(_seed_label)
	seed_row.add_child(LabUi.button("+", func() -> void: _set_seed(_seed + 1), 50))
	seed_row.add_child(LabUi.button("Random", func() -> void: _set_seed(randi_range(1, 99999)), 120))
	LabUi.row(form, "Seed", seed_row, "Same seed + same settings = the same run (fixed-step workers).")
	form.add_child(LabUi.header("Model and data"))
	_net = LabUi.option(Array(NET_NAMES), 1)
	LabUi.row(form, "Network size", _net)
	_dataset = LabUi.option([])
	LabUi.row(form, "Imitation dataset", _dataset, "Recorded matches (Recording tab) used by behaviour cloning.")
	_init_policy = LabUi.option([])
	LabUi.row(form, "Start from policy", _init_policy, "BC → ES starts evolution from a cloned policy; ES can also continue any saved policy.")
	form.add_child(LabUi.header("Limits and resources"))
	_lim_minutes = LabUi.slider(1.0, 480.0, 1.0, 20.0, "%d min")
	LabUi.row(form, "Time limit", _lim_minutes)
	_lim_steps = LabUi.slider(1.0, 500.0, 1.0, 40.0, "%d")
	LabUi.row(form, "Max ES generations", _lim_steps)
	_lim_episodes = LabUi.slider(0.0, 200000.0, 100.0, 0.0, "%d")
	LabUi.row(form, "Max episodes (0 = no limit)", _lim_episodes)
	var cpus := OS.get_processor_count()
	_workers = LabUi.slider(1.0, float(maxi(1, cpus - 1)), 1.0, float(clampi(cpus / 2 - 1, 1, 3)), "%d")
	LabUi.row(form, "Worker processes", _workers, "Each worker uses about one CPU core. Total speed scales with workers.")
	_worlds = LabUi.slider(1.0, 4.0, 1.0, 2.0, "%d")
	LabUi.row(form, "Matches per worker", _worlds)
	_cpu = LabUi.slider(25.0, 100.0, 5.0, 100.0, "%d %%")
	LabUi.row(form, "CPU share per worker", _cpu, "Below 100% the workers pause between frames to leave CPU for other programs.")
	_low_prio = CheckBox.new()
	_low_prio.text = "Run workers at low priority"
	_low_prio.button_pressed = true
	_low_prio.focus_mode = Control.FOCUS_ALL
	form.add_child(_low_prio)
	form.add_child(LabUi.header("Advanced"))
	_es_pairs = LabUi.slider(2.0, 64.0, 1.0, 12.0, "%d")
	LabUi.row(form, "ES: mirrored pairs", _es_pairs, "Population = 2 × pairs candidates per generation.")
	_es_sigma = LabUi.slider(0.005, 0.3, 0.005, 0.05, "%.3f")
	LabUi.row(form, "ES: noise σ", _es_sigma)
	_es_lr = LabUi.slider(0.001, 0.1, 0.001, 0.02, "%.3f")
	LabUi.row(form, "ES: learning rate", _es_lr)
	_es_eps = LabUi.slider(1.0, 8.0, 1.0, 1.0, "%d")
	LabUi.row(form, "ES: episodes per candidate", _es_eps)
	_bc_epochs = LabUi.slider(5.0, 300.0, 5.0, 60.0, "%d")
	LabUi.row(form, "BC: max epochs", _bc_epochs)
	_run_name = LineEdit.new()
	_run_name.placeholder_text = "optional name for the trained policy"
	_run_name.max_length = 64
	LabUi.row(form, "Name", _run_name)
	_start_btn = LabUi.button("START TRAINING", _start_training, 360, "PrimaryButton")
	form.add_child(_start_btn)
	# help column
	var help_panel := LabUi.panel_box()
	help_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(help_panel)
	_train_help = LabUi.rich()
	help_panel.add_child(_train_help)
	_load_preset_weights()
	_load_scenario()
	_refresh_train_lists()
	_update_train_help()
	return root


func _set_seed(v: int) -> void:
	_seed = clampi(v, 1, 99999999)
	_seed_label.text = str(_seed)


func _creature_id() -> String:
	return str(_creatures[_fighter.selected]) if not _creatures.is_empty() and _fighter.selected >= 0 else "dev_biped"


func _load_preset_weights() -> void:
	var pid: String = LabRewards.preset_ids()[_objective.selected]
	var w := LabRewards.weights_for(pid)
	for t in _weight_boxes:
		LabUi.slider_of(_weight_boxes[t]).value = float(w.get(t, 0.0))
	_update_train_help()


func _load_scenario() -> void:
	var sid: String = LabScenarios.preset_ids()[_scenario.selected]
	var scn: Dictionary = LabScenarios.PRESETS[sid]
	for k in _opp_checks:
		(_opp_checks[k] as CheckBox).button_pressed = (scn["opponents"] as Array).has(k)
	LabUi.slider_of(_round_time).value = float(scn["round_time"])
	_spawn.select(0 if str(scn.get("spawn", "random")) == "random" else 1)
	_update_train_help()


func _refresh_train_lists() -> void:
	var cid := _creature_id()
	_dataset.clear()
	_dataset_paths.clear()
	for d: Dictionary in PolicyDataset.list(cid):
		_dataset.add_item("%s — %d samples (%s)" % [str(d["name"]), int(d["samples"]), str(d["source"])])
		_dataset_paths.append(str(d["path"]))
	if _dataset_paths.is_empty():
		_dataset.add_item("(no datasets for this fighter yet — see Recording)")
		_dataset_paths.append("")
	_init_policy.clear()
	_init_paths.clear()
	_init_policy.add_item("(none — start from a random network)")
	_init_paths.append("")
	for s: Dictionary in PolicyLibrary.list(cid):
		if bool(s.get("valid", false)):
			_init_policy.add_item("%s [%s]" % [str(s["name"]), str(s.get("approach", ""))])
			_init_paths.append(str(s.get("id", "")))


func _update_train_help() -> void:
	if _train_help == null:
		return
	var ap: String = APPROACHES[_approach.selected]
	var pid: String = LabRewards.preset_ids()[_objective.selected]
	var sid: String = LabScenarios.preset_ids()[_scenario.selected]
	var t := "[b]%s[/b]\n" % APPROACH_NAMES[_approach.selected]
	match ap:
		"es":
			t += "Learns from the reward alone: each generation tries mirrored random variations of the network in real matches and moves toward the ones that scored better. Needs no recordings. Strength grows with training time.\n\n"
		"bc":
			t += "Copies a recorded playstyle (yours or a bot's): supervised learning on (observation, action) pairs. Whole recorded episodes are held out for validation (early stopping) and for the reported test accuracy, so it needs at least %d recorded episodes (rounds). Fast; quality depends on how much and how consistent the recorded play is.\n\n" % LabBC.MIN_EPISODES
		"bc_es":
			t += "Starts from a cloned policy (pick it under 'Start from policy') and improves it with evolution strategies on the chosen objective.\n\n"
	t += "[b]Objective:[/b] %s\n%s\n\n" % [str(LabRewards.PRESETS[pid]["name"]), str(LabRewards.PRESETS[pid]["help"])]
	t += "[b]Scenario:[/b] %s\n%s\n\n" % [str(LabScenarios.PRESETS[sid]["name"]), str(LabScenarios.PRESETS[sid]["help"])]
	t += "[b]Evaluation[/b] is separate from training: fixed baseline opponents, held-out seeds and the standard corner spawns (jittered, so no episode repeats); reports show mean ± std, 95% intervals and paired comparisons on the same episodes.\n\n"
	t += "[b]Speed[/b]: one worker simulates roughly 8–16 seconds of fighting per second, depending on the PC and what else is running; add workers for more. The game stays responsive — training runs in background processes and can be paused, cancelled or resumed after a crash.\n\n"
	t += "[color=#a8a0b0]Learning is real but not magic: short runs learn simple habits (approach, hit, guard). Beating strong players needs long training and is not guaranteed.[/color]"
	_train_help.text = t


func _start_training() -> void:
	var ap: String = APPROACHES[_approach.selected]
	var cid := _creature_id()
	var opps := []
	for k in _opp_checks:
		if (_opp_checks[k] as CheckBox).button_pressed:
			opps.append(k)
	if opps.is_empty():
		_set_status("Pick at least one training opponent.")
		return
	var weights := {}
	for t in _weight_boxes:
		weights[t] = LabUi.slider_of(_weight_boxes[t]).value
	var hidden: Array = NET_SIZES[_net.selected]
	var job := {"kind": "bc" if ap == "bc" else "es", "name": _run_name.text.strip_edges(), "creature": cid, "seed": _seed,
		"objective": {"preset": LabRewards.preset_ids()[_objective.selected], "weights": weights},
		"scenario": {"preset": LabScenarios.preset_ids()[_scenario.selected], "opponents": opps,
			"round_time": LabUi.slider_of(_round_time).value, "spawn": "random" if _spawn.selected == 0 else "standard"},
		"eval": {"opponents": opps},
		"model": {"hidden": hidden},
		"es": {"pairs": int(LabUi.slider_of(_es_pairs).value), "sigma": LabUi.slider_of(_es_sigma).value,
			"lr": LabUi.slider_of(_es_lr).value, "episodes_per_candidate": int(LabUi.slider_of(_es_eps).value)},
		"bc": {"datasets": [], "epochs": int(LabUi.slider_of(_bc_epochs).value)},
		"limits": {"max_wall_s": LabUi.slider_of(_lim_minutes).value * 60.0, "max_generations": int(LabUi.slider_of(_lim_steps).value),
			"max_epochs": int(LabUi.slider_of(_bc_epochs).value),
			"max_episodes": int(LabUi.slider_of(_lim_episodes).value), "workers": int(LabUi.slider_of(_workers).value),
			"worlds": int(LabUi.slider_of(_worlds).value), "cpu_share": LabUi.slider_of(_cpu).value / 100.0, "low_priority": _low_prio.button_pressed}}
	if ap == "bc":
		var dp: String = _dataset_paths[_dataset.selected] if _dataset.selected >= 0 else ""
		if dp == "":
			_set_status("Behaviour cloning needs a dataset: record some matches first (Recording tab).")
			return
		job["bc"]["datasets"] = [dp]
		job["model"]["hidden"] = hidden if _net.selected != 1 else [64, 64]
	if ap == "bc_es" or (_init_policy.selected > 0):
		var pid: String = _init_paths[_init_policy.selected] if _init_policy.selected >= 0 else ""
		if ap == "bc_es" and pid == "":
			_set_status("BC → ES needs a starting policy (train a behaviour-cloning policy first).")
			return
		if pid != "" and ap != "bc":
			var pol := PolicyLibrary.get_policy(pid)
			if pol == null:
				_set_status("Starting policy unavailable: " + PolicyLibrary.last_error(pid))
				return
			job["model"]["init_policy"] = pid
	var r := LabManager.create_run(job)
	if not r["ok"]:
		_set_status("Cannot start: " + "; ".join(r["errors"]))
		return
	var pid2 := LabManager.start(str(r["run_dir"]))
	if pid2 <= 0:
		_set_status("Could not launch a worker process.")
		return
	_set_status("Training started (%s). Follow it on the Runs tab." % str(r["run_id"]))
	_run_dir = str(r["run_dir"])
	_select_tab(1)
	_refresh_runs()


# =====================================================================================
# Runs tab
# =====================================================================================

func _build_runs() -> Control:
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(520, 0)
	root.add_child(left)
	left.add_child(LabUi.header("Training runs"))
	_runs_list = ItemList.new()
	_runs_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_runs_list.focus_mode = Control.FOCUS_ALL
	_runs_list.item_selected.connect(func(i: int) -> void:
		_run_dir = str((_runs[i] as Dictionary)["dir"]) if i < _runs.size() else ""
		_delete_run_armed = ""
		_refresh_run_detail(true))
	left.add_child(_runs_list)
	var ctrl := GridContainer.new()
	ctrl.columns = 2
	left.add_child(ctrl)
	_btn_pause = LabUi.button("Pause", func() -> void: _control("pause"))
	_btn_resume = LabUi.button("Resume", func() -> void: _control("run"))
	_btn_cancel = LabUi.button("Cancel", func() -> void: _control("cancel"))
	_btn_continue = LabUi.button("Continue run", _continue_run)
	_btn_continue.tooltip_text = "Resume a stopped, cancelled or crashed run from its newest checkpoint."
	_btn_snapshot = LabUi.button("Save snapshot", func() -> void:
		if _run_dir != "":
			LabManager.request_snapshot(_run_dir)
			_set_status("Snapshot requested — it appears in Policies in a moment."))
	_btn_snapshot.tooltip_text = "Save the current best network of a running job as a policy."
	_btn_delete_run = LabUi.button("Delete run", _delete_run)
	for b: Button in [_btn_pause, _btn_resume, _btn_cancel, _btn_continue, _btn_snapshot, _btn_delete_run]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ctrl.add_child(b)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	var top := HBoxContainer.new()
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top.size_flags_stretch_ratio = 1.2
	right.add_child(top)
	var info_panel := LabUi.panel_box()
	info_panel.custom_minimum_size = Vector2(460, 0)
	top.add_child(info_panel)
	_run_info = LabUi.rich()
	info_panel.add_child(_run_info)
	_chart = LabChart.new()
	_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top.add_child(_chart)
	var bottom := HBoxContainer.new()
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(bottom)
	var ck_box := VBoxContainer.new()
	ck_box.custom_minimum_size = Vector2(320, 0)
	bottom.add_child(ck_box)
	ck_box.add_child(LabUi.header("Checkpoints"))
	_ckpts = ItemList.new()
	_ckpts.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ckpts.focus_mode = Control.FOCUS_ALL
	ck_box.add_child(_ckpts)
	var rep_panel := LabUi.panel_box()
	rep_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(rep_panel)
	_report = LabUi.rich()
	rep_panel.add_child(_report)
	return root


func _control(desired: String) -> void:
	if _run_dir == "":
		return
	LabManager.control(_run_dir, desired)
	_set_status({"pause": "Pausing…", "run": "Resuming…", "cancel": "Cancelling (the last checkpoint is kept)…"}.get(desired, desired))


func _continue_run() -> void:
	if _run_dir == "" or not LabManager.can_resume(_run_dir):
		_set_status("This run cannot be resumed (it is running or already completed).")
		return
	var pid := LabManager.start(_run_dir)
	_set_status("Resumed from the latest checkpoint (worker pid %d)." % pid if pid > 0 else "Could not launch a worker.")


func _delete_run() -> void:
	if _run_dir == "":
		return
	if LabManager.is_alive(_run_dir):
		_set_status("Cancel the run before deleting it.")
		return
	if _delete_run_armed != _run_dir:
		_delete_run_armed = _run_dir
		_set_status("Press 'Delete run' again to permanently delete this run folder.")
		return
	LabManager.delete_run(_run_dir)
	_delete_run_armed = ""
	_run_dir = ""
	_set_status("Run deleted.")
	_refresh_runs()


## "Mad Scientist": a trained policy beat its baseline in a held-out evaluation (ES/BC→ES: the
## trained network vs its starting network on the same test episodes, paired 95% interval above
## zero; evaluation runs: the same vs a random network; BC: test-episode accuracy clearly above
## the majority-class baseline). Reports written before the paired test fall back to their own
## criteria.
static func beats_baseline(rep: Dictionary) -> bool:
	if rep.has("initial") and rep.has("trained"):
		if typeof(rep.get("paired")) == TYPE_DICTIONARY:
			var p: Dictionary = rep["paired"]
			return bool(p.get("significant", false)) and float(p.get("mean", 0.0)) > 0.0 and not bool(rep.get("selected_initial", false))
		return float((rep["trained"] as Dictionary)["reward"]["mean"]) > float((rep["initial"] as Dictionary)["reward"]["mean"]) \
			and float(rep.get("welch_t", 0.0)) >= 2.0
	if rep.has("target") and rep.has("compare"):
		if typeof(rep.get("paired_compare")) == TYPE_DICTIONARY:
			var pc: Dictionary = rep["paired_compare"]
			return bool(pc.get("significant", false)) and float(pc.get("mean", 0.0)) > 0.0
		var t: Array = (rep["target"] as Dictionary)["reward"]["ci95"]
		var c: Array = (rep["compare"] as Dictionary)["reward"]["ci95"]
		return t.size() == 2 and c.size() == 2 and float(t[0]) > float(c[1])
	if rep.has("test") and rep.has("majority_baseline"):
		return float((rep["test"] as Dictionary).get("acc_joint", 0.0)) > float((rep["majority_baseline"] as Dictionary).get("acc_joint", 1.0)) + 0.05
	if rep.has("final_val") and rep.has("majority_baseline"):
		return float((rep["final_val"] as Dictionary).get("acc_joint", 0.0)) > float((rep["majority_baseline"] as Dictionary).get("acc_joint", 1.0)) + 0.05
	return false


func _check_achievement(rep: Dictionary) -> void:
	if rep.is_empty() or Platform.is_unlocked("ach_mad_scientist"):
		return
	if beats_baseline(rep):
		Platform.unlock_achievement("ach_mad_scientist")


func _refresh_runs() -> void:
	if _runs_list == null:
		return
	_runs = LabManager.list_runs()
	_runs_list.clear()
	var sel := -1
	for i in _runs.size():
		var r: Dictionary = _runs[i]
		if str(r["state"]) == "completed":
			_check_achievement(LabManager.report(str(r["dir"])))
		var nm := str(r["name"]) if str(r["name"]) != "" else str(r["run_id"])
		_runs_list.add_item("[%s] %s · %s · %s · %d ep" % [str(r["state"]).to_upper(), nm, str(r["kind"]).to_upper(), str(r["creature"]), int(r["episodes"])])
		if str(r["dir"]) == _run_dir:
			sel = i
	if sel < 0 and not _runs.is_empty() and _run_dir == "":
		sel = 0
		_run_dir = str((_runs[0] as Dictionary)["dir"])
	if sel >= 0:
		_runs_list.select(sel)
	_refresh_run_detail(true)


func _refresh_run_detail(full: bool) -> void:
	if _run_info == null:
		return
	if _run_dir == "":
		_run_info.text = "No runs yet. Configure one on the Train tab."
		_chart.set_series([])
		_chart_sig = ""
		_report.text = ""
		_ckpts.clear()
		_ckpt_rows = PackedStringArray()
		_ckpt_files = ""
		return
	if _job_dir != _run_dir:
		_job_dir = _run_dir
		_job = LabManager.job_of(_run_dir)
	var job := _job
	var pr := LabManager.progress(_run_dir)
	var st := LabManager.status(_run_dir)
	var rs := LabManager.run_state(_run_dir, st, pr)
	var state := str(rs["state"])
	var kind := str(job.get("kind", ""))
	var t := "[b]%s[/b]  [color=%s]%s[/color]\n" % [LabUi.esc(job.get("name", "")) if str(job.get("name", "")) != "" else LabUi.esc(job.get("id", "")), LabUi.state_color(state), state.to_upper()]
	t += "%s · %s · seed %d\n" % [LabUi.esc(LabJob.KIND_NAMES.get(kind, kind)), LabUi.esc(job.get("creature", "")), int(job.get("seed", 0))]
	if kind in ["es", "bc"]:
		t += "Objective: %s · scenario: %s\n" % [str((job.get("objective", {}) as Dictionary).get("preset", "")), str((job.get("scenario", {}) as Dictionary).get("preset", ""))]
	if not pr.is_empty():
		var lim: Dictionary = pr.get("limits", {})
		t += "\nStep: %s\n" % str(pr.get("step", pr.get("phase", "")))
		if pr.has("generation"):
			t += "Generation: %d / %d\n" % [int(pr["generation"]), int(lim.get("max_generations", 0))]
		if pr.has("epoch"):
			t += "Epoch: %d / %d   (current epoch %d%%)\n" % [int(pr["epoch"]), int(lim.get("max_epochs", 0)), int(100.0 * float(pr.get("epoch_progress", 0.0)))]
		t += "Episodes: %d   (batch %d / %d)\n" % [int(pr.get("episodes", 0)), int(pr.get("batch_done", 0)), int(pr.get("batch_size", 0))]
		t += "Elapsed: %s of %s\n" % [LabUi.fmt_time(float(pr.get("elapsed_s", 0.0))), LabUi.fmt_time(float(pr.get("max_wall_s", 0.0)))]
		t += "Simulated: %s (%.1fx real time) · %.0f episodes/hour\n" % [LabUi.fmt_time(float(pr.get("sim_s", 0.0))), float(pr.get("sim_speed", 0.0)), float(pr.get("eps_per_hour", 0.0))]
		t += "Workers: %d (%d helpers alive) · coordinator CPU %.0f%% · memory %.0f MB\n" % [int(pr.get("workers", 1)), int(pr.get("helpers_alive", 0)), 100.0 * float(pr.get("util", 0.0)), float(pr.get("mem_mb", 0.0))]
		for k in ["fitness_mean", "fitness_max", "eval_reward", "best_eval_reward", "train_loss", "val_loss", "val_acc_joint", "best_val_loss"]:
			if pr.has(k):
				t += "%s: %.3f\n" % [str(k).replace("_", " "), float(pr[k])]
	var silent := float(rs["silent_s"])
	if silent > 0.0 and state in ["running", "paused", "starting"]:
		t += "\n[i]No report for %d s: the worker process is alive but waiting for CPU (a low-priority worker yields to other programs on a busy PC).[/i]\n" % int(silent)
	if str(st.get("message", "")) != "":
		t += "\n[i]%s[/i]\n" % LabUi.esc(st["message"])
	if _run_info.text != t:   # re-laying out rich text is the expensive part: only on change
		_run_info.text = t
	_btn_pause.disabled = state != "running"
	_btn_resume.disabled = state != "paused"
	_btn_cancel.disabled = not (state in ["running", "paused", "starting"])
	_btn_continue.disabled = not LabManager.resumable(rs)
	_btn_snapshot.disabled = not (state in ["running", "paused"]) or not (kind in ["es", "bc"])
	if not full and _tick % 4 != 0:
		return
	_update_chart(kind)
	var ck_dir := _run_dir.path_join("checkpoints")
	var files := _run_dir + "|" + (",".join(DirAccess.get_files_at(ck_dir)) if DirAccess.dir_exists_absolute(ck_dir) else "")
	if files != _ckpt_files:   # checkpoints are new files: re-list only when the names change
		_ckpt_files = files
		var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
		var rows := PackedStringArray()
		for ck: Dictionary in LabManager.checkpoints(_run_dir):
			rows.append("#%d  %s  (%d KB)" % [int(ck["n"]), Time.get_datetime_string_from_unix_time(int(ck["time"]) + bias, true), int(ck["size_kb"])])
		if rows != _ckpt_rows:
			_ckpt_rows = rows
			_ckpts.clear()
			for row in rows:
				_ckpts.add_item(row)
	var rep := LabManager.report(_run_dir)
	var rep_text := _report_text(rep)
	if _report.text != rep_text:
		_report.text = rep_text
	_check_achievement(rep)


func _update_chart(kind: String) -> void:
	# the learning curve only changes when metrics.jsonl grows: parse it only then
	var fa := FileAccess.open(_run_dir.path_join("metrics.jsonl"), FileAccess.READ)
	var sig := "%s|%d" % [_run_dir, fa.get_length() if fa != null else -1]
	fa = null
	if sig == _chart_sig:
		return
	_chart_sig = sig
	var lines := LabManager.metrics(_run_dir)
	if kind == "bc":
		var tl := []
		var vl := []
		var acc := []
		for l: Dictionary in lines:
			if l.has("train_loss"):
				tl.append([float(l["epoch"]), float(l["train_loss"])])
			if l.has("val_loss"):
				vl.append([float(l["epoch"]), float(l["val_loss"])])
			if l.has("val_acc_joint"):
				acc.append([float(l["epoch"]), float(l["val_acc_joint"])])
		_chart.x_label = "epoch"
		_chart.y_label = "loss / accuracy"
		_chart.set_series([{"name": "train loss", "points": tl, "color": Color(1.0, 0.65, 0.3)},
			{"name": "validation loss", "points": vl, "color": Color(0.45, 0.8, 1.0), "dots": true, "shape": "square"},
			{"name": "val. accuracy", "points": acc, "color": Color(0.6, 1.0, 0.55), "dots": true, "shape": "diamond"}])
	else:
		var fit := []
		var ev := []
		for l: Dictionary in lines:
			if l.has("fit_mean"):
				fit.append([float(l["gen"]), float(l["fit_mean"])])
			if l.has("eval_reward"):
				ev.append([float(l["gen"]), float(l["eval_reward"])])
		_chart.x_label = "generation"
		_chart.y_label = "episode reward"
		_chart.set_series([{"name": "population (training)", "points": fit, "color": Color(1.0, 0.65, 0.3)},
			{"name": "policy (validation)", "points": ev, "color": Color(0.45, 0.8, 1.0), "dots": true, "shape": "square"}])


func _report_text(rep: Dictionary) -> String:
	if rep.is_empty():
		return "[color=#a8a0b0]The evaluation report appears here when the run completes.[/color]"
	var t := "[b]Evaluation report[/b] (%s)\n" % str(rep.get("kind", ""))
	if rep.has("error"):
		t += "[color=#ff8a7a]%s[/color]\n" % LabUi.esc(rep["error"])
	if rep.has("initial") and rep.has("trained"):
		t += "Held-out test episodes — starting policy vs trained policy:\n"
		t += "  start:   %s\n  trained: %s\n" % [LabEval.one_line(rep["initial"]), LabEval.one_line(rep["trained"])]
		if typeof(rep.get("paired")) == TYPE_DICTIONARY:
			t += "  trained − start: %s\n" % LabEval.paired_line(rep["paired"])
		else:
			t += "  Welch t = %.2f\n" % float(rep.get("welch_t", 0.0))
		if bool(rep.get("selected_initial", false)):
			t += "  [color=#f0d070]No trained network beat the starting network on validation: the saved policy is the starting network.[/color]\n"
		t += _per_opponent(rep["trained"])
	if rep.has("test") and rep.has("split"):
		var sp: Dictionary = rep["split"]
		t += "Split by whole episodes: %d train / %d validation (early stopping) / %d test%s\n" % [int(sp.get("train_episodes", 0)),
			int(sp.get("val_episodes", 0)), int(sp.get("test_episodes", 0)),
			(" · %d duplicate episode copies ignored" % int(sp.get("duplicate_episodes", 0))) if int(sp.get("duplicate_episodes", 0)) > 0 else ""]
		var te: Dictionary = rep["test"]
		var bt: Dictionary = rep.get("majority_baseline", {})
		t += "Test-episode accuracy vs the recorded actions: move %.0f%%, button %.0f%%, both %.0f%%\n" % [100.0 * float(te.get("acc_move", 0)), 100.0 * float(te.get("acc_button", 0)), 100.0 * float(te.get("acc_joint", 0))]
		t += "Majority-class baseline (test episodes): move %.0f%%, button %.0f%%\n" % [100.0 * float(bt.get("acc_move", 0)), 100.0 * float(bt.get("acc_button", 0))]
	elif rep.has("final_val"):
		var v: Dictionary = rep["final_val"]
		var b: Dictionary = rep.get("majority_baseline", {})
		t += "Validation accuracy (the early-stopping split) vs the recorded actions: move %.0f%%, button %.0f%%, both %.0f%%\n" % [100.0 * float(v.get("acc_move", 0)), 100.0 * float(v.get("acc_button", 0)), 100.0 * float(v.get("acc_joint", 0))]
		t += "Majority-class baseline: move %.0f%%, button %.0f%%\n" % [100.0 * float(b.get("acc_move", 0)), 100.0 * float(b.get("acc_button", 0))]
	if rep.has("final_val") or rep.has("test"):
		if rep.has("tvd_move"):
			t += "Action-distribution distance to the teacher (0 = identical): move %.3f, button %.3f\n" % [float(rep["tvd_move"]), float(rep["tvd_button"])]
		if rep.has("clone_rollouts"):
			t += "Clone in matches: %s\n" % LabEval.one_line(rep["clone_rollouts"])
		if rep.has("teacher_rollouts"):
			t += "Teacher, same episodes: %s\n" % LabEval.one_line(rep["teacher_rollouts"])
		if typeof(rep.get("paired_teacher")) == TYPE_DICTIONARY:
			t += "Clone − teacher: %s\n" % LabEval.paired_line(rep["paired_teacher"])
	if rep.has("target"):
		t += "%s\n" % LabEval.one_line(rep["target"])
		if not bool(rep.get("complete", true)):
			t += "[color=#f0d070]Stopped early (%s): %d of %d planned episodes per policy.[/color]\n" % [LabUi.esc(rep.get("stop_reason", "")), int(rep.get("played_episodes", 0)), int(rep.get("planned_episodes", 0))]
		t += _per_opponent(rep["target"])
		if rep.has("compare"):
			t += "Comparison (%s): %s\n" % [LabUi.esc(rep.get("compare_label", "")), LabEval.one_line(rep["compare"])]
			if typeof(rep.get("paired_compare")) == TYPE_DICTIONARY:
				t += "  policy − comparison: %s\n" % LabEval.paired_line(rep["paired_compare"])
	if rep.has("samples") and rep.has("dataset"):
		t += "Recorded %d samples into %s\n" % [int(rep["samples"]), LabUi.esc(str(rep["dataset"]).get_file())]
	if str(rep.get("policy_id", "")) != "":
		t += "\nSaved policy: [b]%s[/b]" % LabUi.esc(rep["policy_id"])
	return t


func _per_opponent(s: Dictionary) -> String:
	var t := ""
	for o: Dictionary in s.get("per_opponent", []):
		var dd: Dictionary = o["damage_dealt"]
		var dt: Dictionary = o["damage_taken"]
		t += "  vs %s: win %.0f%% (n=%d) · damage dealt %.1f ± %.1f · taken %.1f ± %.1f\n" % [LabUi.esc(o["name"]), 100.0 * float(o["win_rate"]), int(o["n"]),
			float(dd["mean"]), float(dd["std"]), float(dt["mean"]), float(dt["std"])]
	return t


func _on_timer() -> void:
	_tick += 1
	if not is_visible_in_tree():
		return
	if _tab == 1:
		_refresh_run_detail(false)
		if _tick % 6 == 0:
			var keep := _run_dir
			_runs = LabManager.list_runs()
			for i in _runs.size():
				var r: Dictionary = _runs[i]
				var nm := str(r["name"]) if str(r["name"]) != "" else str(r["run_id"])
				var text := "[%s] %s · %s · %s · %d ep" % [str(r["state"]).to_upper(), nm, str(r["kind"]).to_upper(), str(r["creature"]), int(r["episodes"])]
				if i < _runs_list.item_count:
					_runs_list.set_item_text(i, text)
				else:
					_runs_list.add_item(text)
			_run_dir = keep


# =====================================================================================
# Policies tab
# =====================================================================================

func _build_policies() -> Control:
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(520, 0)
	root.add_child(left)
	left.add_child(LabUi.header("Policy library"))
	_pol_list = ItemList.new()
	_pol_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pol_list.focus_mode = Control.FOCUS_ALL
	_pol_list.item_selected.connect(func(_i: int) -> void:
		_delete_pol_armed = ""
		_show_policy())
	left.add_child(_pol_list)
	# the action column scrolls (follow_focus) so it fits Steam Deck heights
	var sv := _scroll_col()
	root.add_child(sv[0])
	var right: VBoxContainer = sv[1]
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var info_panel := LabUi.panel_box()
	info_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_panel.custom_minimum_size = Vector2(0, 300)
	right.add_child(info_panel)
	_pol_info = LabUi.rich()
	info_panel.add_child(_pol_info)
	var play := HBoxContainer.new()
	play.add_theme_constant_override("separation", 8)
	right.add_child(play)
	_player_creature = LabUi.option([])
	var you := LabUi.caption("You play:")
	you.custom_minimum_size = Vector2(140, 0)
	play.add_child(you)
	play.add_child(_player_creature)
	play.add_child(LabUi.button("FIGHT THIS BOT", _fight, 260))
	var spec := HBoxContainer.new()
	spec.add_theme_constant_override("separation", 8)
	right.add_child(spec)
	_spectate_opp = LabUi.option([])
	var vs := LabUi.caption("Opponent:")
	vs.custom_minimum_size = Vector2(140, 0)
	spec.add_child(vs)
	spec.add_child(_spectate_opp)
	spec.add_child(LabUi.button("SPECTATE THIS BOT", _spectate, 260))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	right.add_child(actions)
	actions.add_child(LabUi.button("Evaluate vs baselines", _evaluate_policy))
	actions.add_child(LabUi.button("Delete", _delete_policy))
	actions.add_child(LabUi.button("Open policy folder", func() -> void: OS.shell_open("file://" + PolicyLibrary.user_dir())))
	_rename_edit = LineEdit.new()
	_rename_edit.max_length = 64
	_rename_edit.placeholder_text = "new name"
	var rn := HBoxContainer.new()
	rn.add_child(_rename_edit)
	_rename_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rn.add_child(LabUi.button("Rename", _rename_policy, 160))
	LabUi.row(right, "Rename", rn)
	_export_edit = LineEdit.new()
	var ex := HBoxContainer.new()
	ex.add_child(_export_edit)
	_export_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ex.add_child(LabUi.button("Export", _export_policy, 160))
	LabUi.row(right, "Export to file", ex, "Writes a .policy.json file (pure data: safe to share).")
	_import_pick = LabUi.option([])
	_import_pick.item_selected.connect(func(i: int) -> void:
		if i < _import_files.size():
			_import_edit.text = str(_import_files[i]))
	LabUi.row(right, "Files in import folder", _import_pick, "Put .policy.json files into the 'import' folder inside the policy folder.")
	_import_edit = LineEdit.new()
	_import_edit.placeholder_text = "path to a .policy.json file"
	var im := HBoxContainer.new()
	im.add_child(_import_edit)
	_import_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	im.add_child(LabUi.button("Import", _import_policy, 160))
	LabUi.row(right, "Import file", im)
	return root


func _refresh_policies() -> void:
	if _pol_list == null:
		return
	var keep := _selected_policy_id()
	_pols = PolicyLibrary.list()
	_pol_list.clear()
	var sel := -1
	for i in _pols.size():
		var s: Dictionary = _pols[i]
		var mark := "" if bool(s.get("valid", false)) else "  [INVALID]"
		_pol_list.add_item("%s · %s · %s · v%d%s" % [str(s.get("name", "")), str(s.get("creature", "")), str(s.get("approach", "")).to_upper(), int(s.get("version", 1)), mark])
		if str(s.get("id", "")) == keep:
			sel = i
	if sel < 0 and not _pols.is_empty():
		sel = 0
	if sel >= 0:
		_pol_list.select(sel)
	_player_creature.clear()
	for cid in Content.playable_creatures():
		_player_creature.add_item(str(cid))
	_spectate_opp.clear()
	_spectate_keys.clear()
	for k in ["bot_rookie", "bot_regular", "bot_pro", "bot_champion", "jabber", "idle"]:
		_spectate_opp.add_item(LabOpponents.display_name(k))
		_spectate_keys.append(k)
	for s: Dictionary in _pols:
		if bool(s.get("valid", false)):
			_spectate_opp.add_item("Policy: " + str(s["name"]))
			_spectate_keys.append("policy:" + str(s["id"]))
	_import_pick.clear()
	_import_files.clear()
	var imp_dir := PolicyLibrary.user_dir().path_join("import")
	LabIO.ensure_dir(imp_dir)
	for fn in DirAccess.get_files_at(imp_dir):
		if str(fn).ends_with(".json"):
			_import_pick.add_item(str(fn))
			_import_files.append(imp_dir.path_join(str(fn)))
	if _import_files.is_empty():
		_import_pick.add_item("(empty)")
	_show_policy()


func _selected_policy_id() -> String:
	if _pol_list == null or _pol_list.get_selected_items().is_empty():
		return ""
	var i := _pol_list.get_selected_items()[0]
	return str((_pols[i] as Dictionary).get("id", "")) if i < _pols.size() else ""


func _show_policy() -> void:
	var id := _selected_policy_id()
	if id == "":
		_pol_info.text = "No policies yet. Train one, or import a .policy.json file."
		return
	var s: Dictionary = {}
	for x: Dictionary in _pols:
		if str(x.get("id", "")) == id:
			s = x
	# policy files come from mods, imports and the player: every field is escaped for BBCode
	if not bool(s.get("valid", false)):
		_pol_info.text = "[b]%s[/b]\n[color=#ff8a7a]This file cannot be used:[/color]\n%s" % [LabUi.esc(id), LabUi.esc(s.get("error", ""))]
		if str(s.get("source", "")) == "user":
			_pol_info.text += "\n\n[color=#a8a0b0]You can delete it, or rename the file to keep it aside.[/color]"
			_rename_edit.text = id
		return
	var p := PolicyLibrary.get_policy(id)
	if p == null:
		_pol_info.text = LabUi.esc(PolicyLibrary.last_error(id))
		return
	var tr := p.training
	var t := "[b]%s[/b]   v%d   (%s)\n" % [LabUi.esc(p.name), p.version, LabUi.esc(p.source)]
	t += "id: %s\nfighter: %s · approach: %s · decisions: %s at %d Hz\n" % [LabUi.esc(p.id), LabUi.esc(p.creature), LabUi.esc(tr.get("approach", "?")), LabUi.esc(p.act_mode), p.decision_hz]
	t += "network: MLP %s %s, %d parameters · obs %s / act %s\n" % [LabUi.esc(str(Array(p.net.hidden))), LabUi.esc(p.net.activation), p.param_count(), PolicyObs.VERSION, PolicyActions.VERSION]
	t += "created %s · updated %s\n" % [LabUi.esc(p.created), LabUi.esc(p.updated)]
	if p.description != "":
		t += "[i]%s[/i]\n" % LabUi.esc(p.description)
	if str(tr.get("approach", "")) == "bc" and tr.has("samples"):
		t += "trained on %d recorded decisions (%s), %d epochs · %d test matches · %s wall time\n" % [int(tr["samples"]),
			LabUi.esc(", ".join(PackedStringArray(tr.get("datasets", [])))), int(tr.get("epochs", 0)), int(tr.get("episodes", 0)), LabUi.fmt_time(float(tr.get("wall_time_s", 0.0)))]
	elif tr.has("episodes"):
		t += "trained on %d episodes, %.0f s simulated, %s wall time\n" % [int(tr["episodes"]), float(tr.get("sim_seconds", 0.0)), LabUi.fmt_time(float(tr.get("wall_time_s", 0.0)))]
	if typeof(tr.get("objective")) == TYPE_DICTIONARY:
		t += "objective: %s\n" % LabUi.esc((tr["objective"] as Dictionary).get("preset", ""))
	if typeof(tr.get("test_eval")) == TYPE_DICTIONARY:
		var te: Dictionary = tr["test_eval"]
		t += "\n[b]Held-out test evaluation[/b]\n  before training: %s\n  after training:  %s\n" % [LabEval.one_line(te.get("initial", {})), LabEval.one_line(te.get("trained", {}))]
		if typeof(te.get("paired")) == TYPE_DICTIONARY:
			t += "  difference: %s\n" % LabEval.paired_line(te["paired"])
	if typeof(tr.get("test_accuracy")) == TYPE_DICTIONARY:
		var ta: Dictionary = tr["test_accuracy"]
		t += "\n[b]Imitation accuracy on held-out test episodes[/b] move %.0f%% · button %.0f%% · both %.0f%%\n" % [100.0 * float(ta.get("move", 0)), 100.0 * float(ta.get("button", 0)), 100.0 * float(ta.get("joint", 0))]
	elif typeof(tr.get("val_accuracy")) == TYPE_DICTIONARY:
		var va: Dictionary = tr["val_accuracy"]
		t += "\n[b]Imitation accuracy on the validation episodes[/b] (also used for early stopping) move %.0f%% · button %.0f%% · both %.0f%%\n" % [100.0 * float(va.get("move", 0)), 100.0 * float(va.get("button", 0)), 100.0 * float(va.get("joint", 0))]
	for w in PolicyLibrary.warnings_for(p):
		t += "\n[color=#f0d070]%s[/color]" % LabUi.esc(w)
	if p.source != "user":
		t += "\n[color=#a8a0b0]Built-in policy: read-only (export it to make an editable copy).[/color]"
	_pol_info.text = t
	_rename_edit.text = p.name
	_export_edit.text = PolicyLibrary.user_dir().path_join("exports").path_join(PolicyLibrary.file_stem(p.name if p.name != "" else p.id) + PolicyIO.EXT)


func _rename_policy() -> void:
	var id := _selected_policy_id()
	if id == "":
		return
	var invalid := PolicyLibrary.get_policy(id) == null
	var err := PolicyLibrary.rename(id, _rename_edit.text)
	if err == OK:
		_set_status("Renamed the file (it still cannot be used)." if invalid else "Renamed.")
	elif PolicyLibrary.is_builtin(id):
		_set_status("Built-in policies are read-only.")
	else:
		_set_status("Rename failed: %s" % error_string(err))
	_refresh_policies()


func _export_policy() -> void:
	var id := _selected_policy_id()
	var path := _export_edit.text.strip_edges()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := PolicyLibrary.export_to(id, path)
	_set_status("Exported to %s" % path if err == OK else "Export failed: %s" % error_string(err))


func _import_policy() -> void:
	var r := PolicyLibrary.import_from(_import_edit.text)
	if r["ok"]:
		var w := "; ".join(r["warnings"])
		_set_status("Imported as %s%s" % [str(r["id"]), (" — " + w) if w != "" else ""])
	else:
		_set_status("Import refused: " + "; ".join(r["errors"]))
		_pol_info.text = "[b]Import refused[/b]\n[color=#ff8a7a]%s[/color]" % LabUi.esc("\n".join(r["errors"]))
		return
	_refresh_policies()


func _delete_policy() -> void:
	var id := _selected_policy_id()
	if id == "":
		return
	if PolicyLibrary.is_builtin(id):
		_set_status("Built-in policies cannot be deleted.")
		return
	if _delete_pol_armed != id:
		_delete_pol_armed = id
		_set_status("Press Delete again to permanently delete this policy.")
		return
	var err := PolicyLibrary.delete(id)
	_delete_pol_armed = ""
	_set_status("Deleted." if err == OK else "Delete failed: %s" % error_string(err))
	_refresh_policies()


func _evaluate_policy() -> void:
	var id := _selected_policy_id()
	if id == "":
		return
	var r := LabManager.evaluate_policy(id, ["idle", "jabber", "bot_rookie", "bot_regular", "bot_pro"], 6, int(LabUi.slider_of(_workers).value))
	if r["ok"]:
		_run_dir = str(r["run_dir"])
		_set_status("Evaluation started — see the Runs tab.")
		_select_tab(1)
	else:
		_set_status("Cannot evaluate: " + "; ".join(r["errors"]))


func _fight() -> void:
	var id := _selected_policy_id()
	var p := PolicyLibrary.get_policy(id)
	if p == null:
		_set_status("Pick a valid policy first.")
		return
	var me := _player_creature.get_item_text(_player_creature.selected) if _player_creature.selected >= 0 else p.creature
	App.start_match({"arena": "the_gullet", "rules": "duel", "fighters": [
		{"creature": me, "team": 0, "kind": "player", "name": "You"},
		{"creature": p.creature, "team": 1, "kind": "policy", "policy_id": p.id, "name": p.name}]}, _back_to_lab)


## Match end -> free the match scene and return to the Policies tab.
static func _back_to_lab(_result: Dictionary) -> void:
	App.set_scene(null)
	App.goto("lab", {"tab": 2, "from_hub": return_to_hub})


func _spectate() -> void:
	var id := _selected_policy_id()
	var p := PolicyLibrary.get_policy(id)
	if p == null:
		_set_status("Pick a valid policy first.")
		return
	var key: String = _spectate_keys[_spectate_opp.selected] if _spectate_opp.selected >= 0 else "bot_regular"
	var opp := {"creature": p.creature, "team": 1, "kind": "bot", "difficulty": "regular", "name": LabOpponents.display_name(key)}
	if key.begins_with("policy:"):
		var q := PolicyLibrary.get_policy(key.substr(7))
		if q != null:
			opp = {"creature": q.creature, "team": 1, "kind": "policy", "policy_id": q.id, "name": q.name}
	elif key.begins_with("bot_"):
		opp["difficulty"] = key.substr(4)
	else:
		opp["kind"] = "script"
		opp["source"] = LabOpponents.create(key, randi(), Content.creature(p.creature))
	App.start_match({"arena": "the_gullet", "rules": {"rounds": 1, "round_time": 60, "mode": "standard"}, "fighters": [
		{"creature": p.creature, "team": 0, "kind": "policy", "policy_id": p.id, "name": p.name}, opp]}, _back_to_lab)


# =====================================================================================
# Recording tab
# =====================================================================================

func _build_recording() -> Control:
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	var sv := _scroll_col()
	(sv[0] as Control).custom_minimum_size = Vector2(700, 0)
	(sv[0] as Control).size_flags_horizontal = Control.SIZE_FILL
	root.add_child(sv[0])
	var left: VBoxContainer = sv[1]
	left.add_child(LabUi.header("Record your play"))
	_rec_toggle = CheckBox.new()
	_rec_toggle.text = "Record my matches for imitation learning"
	_rec_toggle.focus_mode = Control.FOCUS_ALL
	_rec_toggle.button_pressed = LabRecording.is_enabled()
	_rec_toggle.toggled.connect(func(on: bool) -> void:
		LabRecording.set_enabled(on)
		_set_status("Recording %s." % ("ON: your next matches are saved as imitation data" if on else "off")))
	left.add_child(_rec_toggle)
	left.add_child(LabUi.label("Every match you play stores what you saw and did (dataset \"My <fighter> matches\"); play as usual, then train it with Behaviour cloning.", "BodyMuted"))
	left.add_child(LabUi.header("Record a teacher bot"))
	_rec_fighter = LabUi.caption("")
	LabUi.row(left, "Fighter", _rec_fighter, "The fighter selected on the Train tab.")
	_teacher = LabUi.option(["Bot: Rookie", "Bot: Regular", "Bot: Pro", "Bot: Champion", "Scripted jabber", "Scripted turtle"], 1)
	LabUi.row(left, "Teacher", _teacher)
	_teacher_opp = LabUi.option(["Bot: Rookie", "Bot: Regular", "Standing dummy", "Scripted jabber"], 0)
	LabUi.row(left, "Against", _teacher_opp)
	_teacher_eps = LabUi.slider(10.0, 400.0, 10.0, 60.0, "%d matches")
	LabUi.row(left, "Matches", _teacher_eps)
	left.add_child(LabUi.button("RECORD TEACHER DATASET", _record_teacher, 300, "PrimaryButton"))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	right.add_child(LabUi.header("Datasets"))
	_ds_list = ItemList.new()
	_ds_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ds_list.focus_mode = Control.FOCUS_ALL
	right.add_child(_ds_list)
	_ds_rename = LineEdit.new()
	_ds_rename.max_length = 64
	_ds_rename.placeholder_text = "new dataset name"
	var rn := HBoxContainer.new()
	rn.add_child(_ds_rename)
	_ds_rename.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rn.add_child(LabUi.button("Rename", _rename_dataset, 140))
	rn.add_child(LabUi.button("Delete", _delete_dataset, 140))
	right.add_child(rn)
	_ds_list.item_selected.connect(func(i: int) -> void:
		_delete_ds_armed = ""
		if i < _dss.size():
			_ds_rename.text = str((_dss[i] as Dictionary)["name"]))
	return root


func _refresh_datasets() -> void:
	if _ds_list == null:
		return
	_dss = PolicyDataset.list()
	_ds_list.clear()
	for d: Dictionary in _dss:
		var bad := " · %d damaged shard(s)" % (d["errors"] as PackedStringArray).size() if not (d["errors"] as PackedStringArray).is_empty() else ""
		_ds_list.add_item("%s · %s · %d samples in %d sessions · %s%s" % [str(d["name"]), str(d["creature"]), int(d["samples"]), int(d["shards"]), str(d["source"]), bad])
	if _dss.is_empty():
		_ds_list.add_item("(no datasets yet)")
	_rec_toggle.set_pressed_no_signal(LabRecording.is_enabled())
	var c := Content.creature(_creature_id())
	_rec_fighter.text = "%s (%s)" % [c.display_name if c else _creature_id(), _creature_id()]


func _selected_dataset() -> Dictionary:
	if _ds_list.get_selected_items().is_empty():
		return {}
	var i := _ds_list.get_selected_items()[0]
	return _dss[i] if i < _dss.size() else {}


func _rename_dataset() -> void:
	var d := _selected_dataset()
	if d.is_empty():
		return
	var err := PolicyDataset.rename(str(d["id"]), _ds_rename.text)
	_set_status("Dataset renamed." if err == OK else "Rename failed: %s" % error_string(err))
	_refresh_datasets()


func _delete_dataset() -> void:
	var d := _selected_dataset()
	if d.is_empty():
		return
	if _delete_ds_armed != str(d["id"]):
		_delete_ds_armed = str(d["id"])
		_set_status("Press Delete again to permanently delete dataset '%s'." % str(d["name"]))
		return
	var err := PolicyDataset.delete(str(d["id"]))
	_delete_ds_armed = ""
	_set_status("Dataset deleted." if err == OK else "Delete failed: %s" % error_string(err))
	_refresh_datasets()


func _record_teacher() -> void:
	var teachers := ["bot_rookie", "bot_regular", "bot_pro", "bot_champion", "jabber", "turtle"]
	var opps := ["bot_rookie", "bot_regular", "idle", "jabber"]
	var teacher: String = teachers[_teacher.selected]
	var opp: String = opps[_teacher_opp.selected]
	var cid := _creature_id()
	var r := LabManager.create_run({"kind": "record", "name": "Record %s" % LabOpponents.display_name(teacher), "creature": cid,
		"seed": _seed, "scenario": {"preset": "spar_jabber", "opponents": [opp], "round_time": 20.0},
		"record": {"teacher": teacher, "episodes": int(LabUi.slider_of(_teacher_eps).value), "dataset_id": "teacher_%s_vs_%s_%s" % [teacher, opp, cid]},
		"limits": {"workers": int(LabUi.slider_of(_workers).value), "low_priority": _low_prio.button_pressed}})
	if not r["ok"]:
		_set_status("Cannot record: " + "; ".join(r["errors"]))
		return
	LabManager.start(str(r["run_dir"]))
	_run_dir = str(r["run_dir"])
	_set_status("Recording started — see the Runs tab; the dataset appears here when it finishes.")
	_select_tab(1)
