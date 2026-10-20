extends Node
## Commentary audit (v0.9.17, docs/audio/COMMENTARY.md): records what the announcer ACTUALLY plays
## (line id, trigger, speaker, text, start/finish, cut-offs) next to the simulation events it should
## describe, so the baseline and revised commentary can be compared on the same material:
##   1. a scripted, reproducible event sequence fed straight to Audio.on_sim_event: a standard duel
##      (Stoke vs Dredge) and a 10-point / referee bout (Varga vs Knell), each with its own health curve
##      through Audio.on_match_tick;
##   2. consecutive ordinary presented bouts (bots, App.start_match, real time) from a fixed card with
##      rematches, plus Career bouts built by CareerController/CareerFight (Cage Rules preset).
## Runs headless at real time (NO --fixed-fps: the announcer's clock is wall time). One process = one
## "session"; a second process with the same --user-root continues the card (--start-bout), which is
## how a game restart is measured. Writes one JSON log (tools/audio/commentary_report.js reads it).
##
##   godot --headless --path game -- --bench commentary --out <json> [--label baseline]
##         [--sequence 1|0] [--start-bout 0] [--bouts 6] [--user-root <dir>]
## Works on builds without the v0.9.17 commentary log: only the long-standing line_started /
## line_finished / subtitle signals are required; Audio.commentary_event is recorded when present.

const CARD := [
	{"a": "f_stoke", "b": "f_dredge", "kind": "duel"},
	{"a": "f_stoke", "b": "f_dredge", "kind": "duel"},       # rematch
	{"a": "f_gusto", "b": "f_jitters", "kind": "duel"},
	{"a": "f_varga", "b": "f_knell", "kind": "career"},      # Career bout (Cage Rules preset)
	{"a": "f_slurry", "b": "f_dozer", "kind": "duel"},
	{"a": "f_stoke", "b": "f_dredge", "kind": "duel"},       # third meeting
	{"a": "f_jitters", "b": "f_gusto", "kind": "duel"},      # reversed rematch
	{"a": "f_knell", "b": "f_stoke", "kind": "duel"},
	{"a": "f_varga", "b": "f_dozer", "kind": "career"},
	{"a": "f_dredge", "b": "f_slurry", "kind": "duel"},
	{"a": "f_gusto", "b": "f_jitters", "kind": "duel"},
	{"a": "f_varga", "b": "f_knell", "kind": "career"},      # career rematch
]
const NAMES := {"f_stoke": "Stoke", "f_dredge": "Dredge", "f_gusto": "Gusto", "f_dozer": "Dozer", "f_slurry": "Slurry",
	"f_jitters": "Jitters", "f_varga": "Varga", "f_knell": "Knell"}
const EVENT_TYPES := ["hit", "knockdown", "getup", "ko", "downed", "parry", "dodge", "guard_break", "juice", "juice_end", "ability",
	"reaction", "ringout", "slam", "throw", "grab", "taunt", "round_intro", "round_start", "round_end", "timeout", "match_end",
	"sudden_death", "judges_decision", "round_scored", "ref_count", "ref_wave_up", "ref_stoppage", "counter", "burst"]

var args: PackedStringArray
var out_path := ""
var label := "run"
var log_lines: Array = []
var log_events: Array = []
var log_segments: Array = []
var log_commentary: Array = []
var _segment := ""
var _seg_t0 := 0
var _current := {}          ## the line being spoken {id, i (index in log_lines)}
var _match_scene: Node = null
var _event_cursor := 0
var _finished := false
var _result := {}
var _subtitle := ""


func run(a: PackedStringArray) -> void:
	args = a
	out_path = _arg("--out", "user://commentary_audit.json")
	label = _arg("--label", "run")
	Audio.line_started.connect(_on_line_started)
	Audio.line_finished.connect(_on_line_finished)
	Audio.subtitle.connect(_on_subtitle)
	if Audio.has_signal("commentary_event"):
		Audio.connect("commentary_event", _on_commentary_event)
	# the default announcer setting, subtitles on (what a fresh profile hears)
	Settings.set_value("gameplay.announcer", "full", true, false)
	Settings.set_value("access.subtitles", true, true, false)
	var t_start := Time.get_ticks_msec()
	if _arg("--sequence", "1") == "1":
		await _run_sequence("sequence_duel", _duel_script(), ["f_stoke", "f_dredge"], {})
		await _run_sequence("sequence_ten_point", _ten_point_script(), ["f_varga", "f_knell"], {"ten_point": true})
	var start := int(_arg("--start-bout", "0"))
	var count := int(_arg("--bouts", str(CARD.size())))
	for k in range(start, mini(start + count, CARD.size())):
		await _run_bout(k)
	_write({"wall_seconds": (Time.get_ticks_msec() - t_start) / 1000.0})
	get_tree().quit(0)


func _arg(flag: String, fallback: String) -> String:
	var i := args.find(flag)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback


func _now() -> float:
	return (Time.get_ticks_msec() - _seg_t0) / 1000.0


func _begin_segment(name_: String, info: Dictionary) -> void:
	_segment = name_
	_seg_t0 = Time.get_ticks_msec()
	var s := info.duplicate()
	s["segment"] = name_
	log_segments.append(s)
	print("AUDIT segment %s %s" % [name_, JSON.stringify(info)])


# ---- recording --------------------------------------------------------------------------------

func _on_line_started(id: String) -> void:
	var l: Dictionary = Audio.line(id)
	if not _current.is_empty():
		var prev: Dictionary = log_lines[int(_current["i"])]
		if not prev.has("end"):
			prev["end"] = _now()
			prev["cut_by"] = id
	var entry := {"segment": _segment, "t": _now(), "id": id, "trigger": str(l.get("trigger", "say" if id.begins_with("say:") else "")),
		"speaker": str(l.get("speaker", "")), "text": str(l.get("text", "")), "when": l.get("when", {}),
		"priority": int(l.get("priority", 0)), "said": _subtitle}
	_subtitle = ""
	log_lines.append(entry)
	_current = {"id": id, "i": log_lines.size() - 1}


## The spoken text with names/numbers filled in (emitted right before line_started).
func _on_subtitle(_speaker: String, text: String, _seconds: float) -> void:
	_subtitle = text


func _on_line_finished(id: String) -> void:
	if _current.is_empty() or str(_current["id"]) != id:
		return
	var e: Dictionary = log_lines[int(_current["i"])]
	if not e.has("end"):
		e["end"] = _now()
	_current = {}


func _on_commentary_event(ev: Dictionary) -> void:
	var e := ev.duplicate()
	e["segment"] = _segment
	e["t"] = _now()
	log_commentary.append(e)


func _record_event(ev: Dictionary, sim_time: float, health: Array) -> void:
	var type := str(ev.get("type", ""))
	if not EVENT_TYPES.has(type):
		return
	if type == "hit" and float(ev.get("damage", 0.0)) <= 0.0 and not bool(ev.get("blocked", false)):
		return
	var e := {"segment": _segment, "t": _now(), "sim_t": sim_time, "type": type}
	for k in ["fighter", "target", "damage", "slot", "move", "blocked", "parried", "counter", "reason", "by", "winner", "method",
			"round", "id", "reaction", "kind", "n", "attacker", "launch"]:
		if ev.has(k):
			var v = ev[k]
			e[k] = v if typeof(v) in [TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_BOOL] else str(v)
	e["health"] = health.duplicate()
	log_events.append(e)


# ---- 1. the scripted sequences ----------------------------------------------------------------

## [t, event, info] rows; health rows are {"t": s, "health": [a, b]} and drive on_match_tick.
func _duel_script() -> Array:
	var s: Array = []
	var hit := func(t: float, f: int, tg: int, dmg: float, slot := "l1", extra := {}) -> void:
		var ev := {"type": "hit", "fighter": f, "target": tg, "damage": dmg, "slot": slot, "move": slot, "quality": 0.6}
		ev.merge(extra, true)
		s.append([t, ev, {}])
	s.append([0.2, {"type": "round_intro", "round": 1}, {}])
	s.append([3.0, {"type": "round_start", "round": 1}, {"final_round": false}])
	hit.call(5.0, 0, 1, 4.0, "l1")
	hit.call(5.4, 0, 1, 4.5, "l2")
	hit.call(5.8, 0, 1, 6.0, "l3")
	hit.call(9.0, 1, 0, 0.0, "l1", {"blocked": true})
	s.append([10.5, {"type": "parry", "fighter": 0, "attacker": 1}, {}])
	hit.call(11.0, 0, 1, 12.0, "heavy", {"counter": true})
	s.append([15.0, {"type": "dodge", "fighter": 1}, {}])
	s.append([17.0, {"type": "ability", "fighter": 1, "slot": "ability1", "id": "tide_spit"}, {}])
	hit.call(17.6, 1, 0, 6.0, "ability1", {"element": "brine"})
	hit.call(21.0, 1, 0, 16.0, "heavy_charged", {"move": "heavy_charged", "launch": 2.0})
	s.append([21.1, {"type": "knockdown", "fighter": 0, "reason": "hit", "by": 1}, {}])
	s.append([23.5, {"type": "getup", "fighter": 0}, {}])
	s.append([27.0, {"type": "ability", "fighter": 0, "slot": "ability1", "id": "steam_vent"}, {}])
	hit.call(27.5, 0, 1, 6.0, "ability1", {"element": "scorch"})
	s.append([28.0, {"type": "reaction", "fighter": 1, "reaction": "flare_up", "name": "Flare-Up", "a": "scorch", "b": "brine"}, {}])
	hit.call(31.0, 0, 1, 5.0, "l1")
	hit.call(31.4, 0, 1, 5.0, "l2")
	hit.call(31.8, 0, 1, 7.0, "l3")
	hit.call(32.3, 0, 1, 11.0, "finisher")
	s.append([36.0, {"type": "guard_break", "fighter": 1}, {}])
	s.append([40.0, {"type": "juice", "fighter": 0, "id": "meltdown"}, {}])
	hit.call(41.0, 0, 1, 14.0, "heavy")
	s.append([47.0, {"type": "taunt", "fighter": 1}, {}])
	hit.call(52.0, 1, 0, 9.0, "heavy")
	s.append([60.0, {"type": "throw", "fighter": 1, "victim": 0, "kind": "forward"}, {}])
	s.append([60.3, {"type": "knockdown", "fighter": 0, "reason": "throw", "by": 1}, {}])
	s.append([62.5, {"type": "getup", "fighter": 0}, {}])
	hit.call(70.0, 0, 1, 18.0, "heavy_charged", {"move": "heavy_charged"})
	s.append([70.1, {"type": "ko", "fighter": 1, "by": 0}, {}])
	s.append([70.2, {"type": "round_end", "winner": 0, "round": 1}, {}])
	s.append([74.0, {"type": "round_intro", "round": 2}, {}])
	s.append([77.0, {"type": "round_start", "round": 2}, {"final_round": false}])
	hit.call(80.0, 1, 0, 7.0, "l1")
	hit.call(84.0, 0, 1, 5.0, "l1")
	s.append([88.0, {"type": "ringout", "fighter": 1}, {}])
	s.append([92.0, {"type": "ability", "fighter": 1, "slot": "ability2", "id": "anchor_drop"}, {}])
	hit.call(96.0, 1, 0, 13.0, "heavy", {"counter": true})
	s.append([100.0, {"type": "slam", "fighter": 0, "speed": 6.0}, {}])
	hit.call(108.0, 0, 1, 10.0, "heavy")
	hit.call(118.0, 1, 0, 20.0, "heavy_charged", {"move": "heavy_charged"})
	s.append([118.1, {"type": "ko", "fighter": 0, "by": 1}, {}])
	s.append([118.2, {"type": "round_end", "winner": 1, "round": 2}, {}])
	s.append([122.0, {"type": "round_intro", "round": 3}, {}])
	s.append([125.0, {"type": "round_start", "round": 3}, {"final_round": true}])
	hit.call(128.0, 0, 1, 6.0, "l1")
	hit.call(135.0, 1, 0, 6.0, "l2")
	s.append([140.0, {"type": "juice", "fighter": 1, "id": "high_tide"}, {}])
	hit.call(140.6, 1, 0, 10.0, "juice", {"element": "brine"})
	s.append([141.0, {"type": "knockdown", "fighter": 0, "reason": "poise", "by": 1}, {}])
	s.append([143.0, {"type": "getup", "fighter": 0}, {}])
	hit.call(150.0, 0, 1, 8.0, "heavy")
	hit.call(158.0, 0, 1, 15.0, "heavy")
	s.append([158.1, {"type": "ko", "fighter": 1, "by": 0}, {}])
	s.append([158.2, {"type": "round_end", "winner": 0, "round": 3}, {}])
	s.append([158.3, {"type": "match_end", "winner": 0}, {}])
	# health: [stoke, dredge] fractions over time (low-health watcher)
	for row in [[0, 1, 1], [12, 1, 0.8], [22, 0.75, 0.8], [33, 0.75, 0.55], [42, 0.75, 0.42], [53, 0.66, 0.42], [61, 0.58, 0.42],
			[70, 0.58, 0.0], [77, 1, 1], [81, 0.94, 1], [85, 0.94, 0.95], [97, 0.82, 0.95], [109, 0.82, 0.86], [114, 0.18, 0.86],
			[118, 0.0, 0.86], [125, 1, 1], [129, 1, 0.95], [136, 0.95, 0.95], [141, 0.85, 0.95], [151, 0.85, 0.15], [158, 0.85, 0.0], [162, 0.85, 0.0]]:
		s.append({"t": float(row[0]), "health": [float(row[1]), float(row[2])]})
	return s


func _ten_point_script() -> Array:
	var s: Array = []
	var hit := func(t: float, f: int, tg: int, dmg: float, slot := "l1", extra := {}) -> void:
		var ev := {"type": "hit", "fighter": f, "target": tg, "damage": dmg, "slot": slot, "move": slot, "quality": 0.6}
		ev.merge(extra, true)
		s.append([t, ev, {}])
	s.append([0.2, {"type": "round_intro", "round": 1}, {}])
	s.append([3.0, {"type": "round_start", "round": 1}, {"final_round": false}])
	hit.call(5.0, 0, 1, 5.0, "rh_straight")
	hit.call(7.0, 1, 0, 6.0, "l1")
	hit.call(11.0, 0, 1, 12.0, "rl_hkick", {"counter": true})
	s.append([11.1, {"type": "knockdown", "fighter": 1, "reason": "hit", "by": 0}, {"referee": true}])
	for c in 4:
		s.append([12.0 + c, {"type": "ref_count", "fighter": 1, "n": c + 1}, {}])
	s.append([15.5, {"type": "ref_wave_up", "fighter": 1}, {}])
	s.append([15.6, {"type": "getup", "fighter": 1}, {}])
	s.append([20.0, {"type": "ability", "fighter": 1, "slot": "ability1", "id": "ghost_light"}, {}])
	hit.call(21.0, 1, 0, 9.0, "ability1", {"element": "spectral"})
	s.append([24.0, {"type": "parry", "fighter": 0, "attacker": 1}, {}])
	hit.call(30.0, 0, 1, 7.0, "lh_hook")
	s.append([33.0, {"type": "timeout"}, {"ten_point": true}])
	s.append([33.1, {"type": "round_scored", "round": 1}, {}])
	s.append([33.2, {"type": "round_end", "winner": 0, "round": 1}, {}])
	s.append([37.0, {"type": "round_intro", "round": 2}, {}])
	s.append([40.0, {"type": "round_start", "round": 2}, {"final_round": false}])
	s.append([43.0, {"type": "juice", "fighter": 1, "id": "last_bell"}, {}])
	hit.call(43.5, 1, 0, 6.0, "juice", {"element": "spectral"})
	hit.call(44.0, 1, 0, 6.0, "juice", {"element": "spectral"})
	s.append([48.0, {"type": "ability", "fighter": 0, "slot": "ability1", "id": "cut_the_angle"}, {}])
	hit.call(48.5, 0, 1, 11.0, "rh_uppercut")
	s.append([48.6, {"type": "knockdown", "fighter": 1, "reason": "hit", "by": 0}, {"referee": true}])
	for c2 in 3:
		s.append([49.5 + c2, {"type": "ref_count", "fighter": 1, "n": c2 + 1}, {}])
	s.append([52.0, {"type": "getup", "fighter": 1}, {}])
	hit.call(60.0, 0, 1, 13.0, "rh_overhand")
	s.append([60.1, {"type": "knockdown", "fighter": 1, "reason": "hit", "by": 0}, {"referee": true}])
	s.append([61.0, {"type": "ref_count", "fighter": 1, "n": 1}, {}])
	s.append([62.0, {"type": "ref_stoppage", "fighter": 1, "by": 0}, {}])
	s.append([62.1, {"type": "round_end", "winner": 0, "round": 2}, {}])
	s.append([64.0, {"type": "judges_decision", "winner": 0, "method": "TKO"}, {"ten_point": true, "sudden_death_follows": false}])
	s.append([68.0, {"type": "match_end", "winner": 0}, {}])
	for row in [[0, 1, 1], [6, 1, 0.95], [8, 0.95, 0.95], [12, 0.95, 0.85], [22, 0.87, 0.85], [31, 0.87, 0.79], [40, 1, 1], [45, 0.9, 1],
			[49, 0.9, 0.9], [61, 0.9, 0.78], [68, 0.9, 0.78]]:
		s.append({"t": float(row[0]), "health": [float(row[1]), float(row[2])]})
	return s


func _run_sequence(name_: String, script: Array, creatures: Array, opts: Dictionary) -> void:
	var fighters: Array = []
	for i in creatures.size():
		fighters.append({"index": i, "creature": creatures[i], "name": NAMES.get(creatures[i], creatures[i]), "team": i})
	Audio.begin_match({"player_index": 0, "fighters": fighters, "arena": "the_gullet", "arena_name": "The Gullet", "seed": 1701,
		"context": "versus"})
	_begin_segment(name_, {"kind": "sequence", "creatures": creatures, "ten_point": bool(opts.get("ten_point", false))})
	var rows: Array = []
	var health_rows: Array = []
	for r in script:
		if r is Dictionary:
			health_rows.append(r)
		else:
			rows.append(r)
	rows.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	var end_t := float(rows.back()[0]) + 8.0
	var ri := 0
	var tick_t := 0.0
	var health: Array = [1.0, 1.0]
	while _now() < end_t:
		var now := _now()
		while ri < rows.size() and float(rows[ri][0]) <= now:
			var ev: Dictionary = (rows[ri][1] as Dictionary).duplicate()
			var info: Dictionary = (rows[ri][2] as Dictionary).duplicate()
			info["health"] = health.duplicate()
			info["time"] = now
			if bool(opts.get("ten_point", false)) and str(ev["type"]) in ["timeout", "judges_decision"]:
				info["ten_point"] = true
			if bool(opts.get("ten_point", false)) and str(ev["type"]) == "knockdown":
				info["referee"] = true
			_record_event(ev, now, health)
			Audio.on_sim_event(ev, Vector3.ZERO, info)
			ri += 1
		while now >= tick_t:
			for hr in health_rows:
				if float(hr["t"]) <= tick_t:
					health = (hr["health"] as Array).duplicate()
			# the timer warning: the last 10 s of a 99 s round are not part of these scripts
			Audio.on_match_tick(health, 50.0, 0.25)
			tick_t += 0.25
		await get_tree().process_frame
	Audio.end_match()
	_flush_current()


# ---- 2. presented bouts -----------------------------------------------------------------------

func _run_bout(k: int) -> void:
	var b: Dictionary = CARD[k]
	var cfg := {}
	var info := {"kind": str(b["kind"]), "bout": k, "a": str(b["a"]), "b": str(b["b"])}
	if str(b["kind"]) == "career":
		cfg = _career_config(k, str(b["a"]), str(b["b"]))
		if cfg.is_empty():
			info["error"] = "career bout could not be built"
			log_segments.append(info)
			return
		info["rules"] = str((cfg["rules"] as Dictionary).get("id", ""))
	else:
		cfg = {"arena": "the_gullet", "rules": "duel", "seed": 5100 + k, "no_record": true,
			"fighters": [
				{"creature": str(b["a"]), "team": 0, "kind": "bot", "difficulty": "pro", "name": NAMES.get(b["a"], b["a"])},
				{"creature": str(b["b"]), "team": 1, "kind": "bot", "difficulty": "pro", "name": NAMES.get(b["b"], b["b"])}]}
		info["rules"] = "duel"
	_begin_segment("bout_%02d" % k, info)
	_finished = false
	_result = {}
	_match_scene = App.start_match(cfg, _on_bout_finished)
	_event_cursor = 0
	var started := Time.get_ticks_msec()
	var cap_ms := 9 * 60 * 1000
	while not _finished and Time.get_ticks_msec() - started < cap_ms:
		await get_tree().physics_frame
		_pull_events()
	_pull_events()
	var result := _result
	var seg: Dictionary = log_segments.back()
	seg["duration"] = _now()
	seg["timed_out"] = not _finished
	seg["winner_team"] = int(result.get("winner_team", -2))
	var sc: Dictionary = result.get("scoring", {})
	if not sc.is_empty():
		seg["method"] = str(sc.get("method", ""))
	seg["rounds"] = int(result.get("rounds", 0))
	# the app's own teardown (results screen skipped): free the scene, end the match audio
	App.set_scene(null)
	_match_scene = null
	await get_tree().create_timer(1.5).timeout     # trailing lines (win call) finish or are cut
	_flush_current()


func _on_bout_finished(r: Dictionary) -> void:
	_result = r
	_finished = true


func _pull_events() -> void:
	if _match_scene == null or not is_instance_valid(_match_scene):
		return
	var sim: MatchSim = _match_scene.get("sim")
	if sim == null:
		return
	var health: Array = []
	for f in sim.fighters:
		health.append(snappedf(f.health_frac(), 0.01))
	for ev in sim.events_since(_event_cursor):
		_event_cursor = int(ev["seq"])
		_record_event(ev, sim.time, health)


func _career_config(k: int, mine: String, theirs: String) -> Dictionary:
	var cat := CampaignCatalog.new(Content)
	var r := CareerController.create(cat, {"name": "Rookie", "nick": "", "fighter": mine, "difficulty": "normal", "seed": 7700 + k,
		"created_at": 1}, null, "audit", 1)
	if not bool(r["ok"]):
		return {}
	var ctrl: CareerController = r["ctrl"]
	var offers: Array = ctrl.state["offers"]
	if offers.is_empty():
		return {}
	var o: Dictionary = offers[0]
	var opp: Dictionary = o.get("opp", {})
	opp["fighter"] = theirs
	opp["name"] = NAMES.get(theirs, theirs)
	o["opp"] = opp
	if not ctrl.accept(str(o["id"])):
		return {}
	ctrl.state["booked"]["weeks_left"] = 0
	var built := ctrl.fight_config({"player_kind": "bot", "player_bot_tier": "pro"})
	if not (built["errors"] as PackedStringArray).is_empty():
		return {}
	return built["config"]


func _flush_current() -> void:
	if not _current.is_empty():
		var e: Dictionary = log_lines[int(_current["i"])]
		if not e.has("end"):
			e["end"] = _now()
			e["open_at_segment_end"] = true
		_current = {}


func _write(extra: Dictionary) -> void:
	var data := {"label": label, "build": BuildInfo.label(), "date": Time.get_datetime_string_from_system(),
		"start_bout": int(_arg("--start-bout", "0")), "segments": log_segments, "lines": log_lines, "events": log_events,
		"commentary": log_commentary, "has_commentary_log": Audio.has_signal("commentary_event")}
	data.merge(extra, true)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))
		f.close()
	print("AUDIT wrote %s: %d lines, %d events, %d segments" % [out_path, log_lines.size(), log_events.size(), log_segments.size()])
