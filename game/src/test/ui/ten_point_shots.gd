extends Node
## Visual evidence runner for 10-point scoring and the referee (windowed, not a test; like
## referee_shots / arena_shots). It plays a REAL local match through App.start_match (bots, the
## real HUD, RefereeView, callouts and the results screen) and saves frames at the moments that
## matter, then quits.
## Run:  godot --path game res://src/test/ui/ten_point_shots.tscn -- --windowed --size 1280x800 --out <dir>
##       (Settings honours "-- --windowed --size WxH"; the engine's own --resolution is overridden by
##       the fullscreen default)
##         [--tag cage] [--rules cage_rules] [--rounds 3] [--round-time 20] [--seed 7] [--arena the_gullet]
##         [--creatures f_stoke,f_dredge] [--player 1] [--knockdown]
##   <out>/<tag>_mid_round.png   6 s into round 1 (HUD without HP bars, round line, cards; the referee)
##   <out>/<tag>_round_card.png  1.2 s after round 1 is scored (the between-rounds scorecard)
##   <out>/<tag>_count.png       a referee count: 2 s in, or 0.8 s after it starts if the fighter rises sooner
##                               (--knockdown forces one in round 2 if none came)
##   <out>/<tag>_decision.png    1 s after the final judges' decision (callout + banner)
##   <out>/<tag>_raise.png       4.8 s after it (the referee raises the winner's arm)
##   <out>/<tag>_results.png     1.5 s into the results screen (method line, ScorecardPanel)
## --player i makes fighter i an idle local player (shows the "stay down" hint while counted).
## --knockdown is scripted evidence only: it knocks fighter 1 down (by fighter 0) once in round 2.
## --tko (scripted evidence) keeps knocking fighter 1 down in round 2 whenever it stands until the
## referee stops it: <tag>_stoppage.png (1.2 s after ref_stoppage, the wave-off), then the T.K.O.
## decision / raise / results shots.

var args: PackedStringArray
var scene: MatchScene = null
var out_dir := "user://"
var tag := "cage"
var _cursor := 0
var _due := {}             ## shot name -> real time (s) it is due
var _taken := {}
var _forced := false
var _next_kd := 0.0
var _results_at := -1.0
var _busy := false


func _arg(flag: String, fallback := "") -> String:
	var i := args.find(flag)
	if i >= 0 and i + 1 < args.size() and not args[i + 1].begins_with("--"):
		return args[i + 1]
	return fallback


func _ready() -> void:
	args = OS.get_cmdline_user_args()
	call_deferred("_start")


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _start() -> void:
	UiNav.ensure()
	out_dir = _arg("--out", "user://")
	DirAccess.make_dir_recursive_absolute(out_dir)
	tag = _arg("--tag", "cage")
	var rules: Dictionary = Content.get_entry("rules", _arg("--rules", "cage_rules")).duplicate(true)
	if _arg("--rounds") != "":
		rules["rounds"] = int(_arg("--rounds"))
	if _arg("--round-time") != "":
		rules["round_time"] = float(_arg("--round-time"))
	var ids := _arg("--creatures", "f_stoke,f_dredge").split(",", false)
	var player := int(_arg("--player", "-1"))
	var fs := []
	for i in 2:
		var c := Content.creature(ids[mini(i, ids.size() - 1)])
		var kind := "player" if i == player else "bot"
		fs.append({"creature": c, "team": i, "kind": kind, "difficulty": "pro" if i == 0 else "regular", "name": c.display_name})
	scene = App.start_match({"arena": _arg("--arena", "the_gullet"), "rules": rules, "seed": int(_arg("--seed", "7")), "fighters": fs})
	print("SHOTS start %s: %s (%s)" % [tag, str(rules.get("id", "?")), ", ".join(ids)])


func _process(_dt: float) -> void:
	if _busy:
		return
	var now := _now()
	if scene != null and is_instance_valid(scene) and scene.sim != null:
		var sim := scene.sim
		var mm := sim.mode
		for ev in sim.events_since(_cursor):
			_cursor = int(ev["seq"])
			match str(ev["type"]):
				"round_scored":
					if int(ev.get("round", 0)) == 1:
						_want("round_card", now + 1.2)
				"ref_stoppage":
					_want("stoppage", now + 1.2)
				"judges_decision":
					if int(ev.get("winner", -1)) >= 0 or mm.winner_team == -1:
						_want("decision", now + 1.0)
						_want("raise", now + 4.8)
		if mm != null:
			if mm.phase == MatchMode.Phase.FIGHT and mm.round_index == 0 and mm.phase_time >= 6.0:
				_want("mid_round", now)
			var rv = mm.view_state().get("referee", {})
			if typeof(rv) == TYPE_DICTIONARY and (rv as Dictionary).has("count"):
				var n := int(((rv as Dictionary)["count"] as Dictionary).get("n", 0))
				if n >= 2 and _due.has("count") and not _taken.has("count"):
					_due["count"] = now
				_want("count", now + 0.8)
			if args.has("--knockdown") and not _forced and not _taken.has("count") and mm.phase == MatchMode.Phase.FIGHT \
					and mm.round_index == 1 and mm.phase_time >= 3.0 and not sim.fighters[1].is_down():
				_forced = true
				sim.fighters[1].knock_down("poise", sim.fighters[0])
				print("SHOTS scripted knockdown at %.1f s" % sim.time)
			if args.has("--tko") and mm.phase == MatchMode.Phase.FIGHT and mm.round_index == 1 and mm.phase_time >= 2.0 \
					and sim.fighters[1].state in [Fighter.State.NEUTRAL, Fighter.State.GUARD] and now >= _next_kd:
				_next_kd = now + 0.6
				sim.fighters[1].knock_down("poise", sim.fighters[0])
				print("SHOTS scripted knockdown at %.1f s" % sim.time)
		if str(_arg("--rules", "cage_rules")) == "duel" and _taken.has("mid_round"):
			get_tree().quit(0)
			return
	var top := App.top_screen()
	if top != null and top.screen_name == "results" and _results_at < 0.0:
		_results_at = now
		_want("results", now + 1.5)
	for k in _due.keys():
		if not _taken.has(k) and now >= float(_due[k]):
			_taken[k] = true
			_shoot(k)
			return


func _want(shot: String, at: float) -> void:
	if not _due.has(shot) and not _taken.has(shot):
		_due[shot] = at


func _shoot(shot: String) -> void:
	_busy = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join("%s_%s.png" % [tag, shot])
	img.save_png(path)
	print("SHOT ", path, " ", img.get_size())
	_busy = false
	if shot == "results":
		get_tree().quit(0)
