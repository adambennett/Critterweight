extends SceneTree
## Windowed audio showcase / runtime verification (plays real audio on the machine):
##   godot --path game -s res://src/test/audio/audio_showcase.gd [-- --quick]
## Plays the menu track, crossfades to combat A with the intensity layer, fires a scripted fight
## (hits, parry, knockdown, reaction, JUICE with the combat-B half-time jump, KO + victory sting),
## announcer lines with subtitles, crowd heat and ambience, then prints a log (music position
## advancing, voices used, babble frames) and quits. Exit code 0 = every stage ran as expected.
## (A `-s` script compiles before autoloads exist, so the Audio singleton is fetched by path.)

var _a: Node
var _t := 0.0
var _stage := 0
var _subs := 0
var _plan: Array = []
var _zone := -1


func _initialize() -> void:
	_a = root.get_node("Audio")
	var quick := OS.get_cmdline_user_args().has("--quick")
	var s := 0.35 if quick else 1.0
	_a.connect("subtitle", func(speaker: String, text: String, seconds: float): _subs += 1; print("  [%s] %s (%.1fs)" % [speaker, text, seconds]))
	_plan = [
		[0.0, func(): _say("menu music + harbour ambience"); _a.ambience("amb_menu"); _a.music("fight_night_poster", 0.5); _a.ui("ui_accept")],
		[3.0 * s, func(): _say("idle quip"); _a.announce_trigger("idle")],
		[6.0 * s, func(): _say("combat A crossfade (seed variant layer) + arena + crowd"); _a.attach_match_dummy(); _a.music("combat_a", 1.5, {"seed": 42, "intensity": 0.0}); _a.set_arena("the_gullet"); _a.sfx("ui_round_card")],
		[8.0 * s, func(): _a.on_sim_event({"type": "round_intro", "round": 1})],
		[10.0 * s, func(): _a.on_sim_event({"type": "round_start", "round": 1})],
		[12.0 * s, func(): _say("light string on Dredge (chitin layer, scorch)"); for i in 3: _hit(0, 1, 5.0 + i, "l%d" % (i + 1), "scorch")],
		[13.5 * s, func(): _say("heavy counter + wall slam"); _hit(1, 0, 16.0, "heavy", "", true); _a.on_sim_event({"type": "slam", "fighter": 0, "speed": 6.0, "pos": Vector3(2, 0.5, 0)})],
		[15.0 * s, func(): _say("parry"); _a.on_sim_event({"type": "parry", "fighter": 0, "attacker": 1, "pos": Vector3.ZERO})],
		[16.5 * s, func(): _say("intensity layer in (fighter < 50% HP)"); _a.music_intensity(1.0); _a.on_match_tick([0.18, 0.6], 60.0, 0.25)],
		[18.0 * s, func(): _say("reaction: Short-Out"); _a.on_sim_event({"type": "reaction", "fighter": 1, "reaction": "short_out", "name": "Short-Out", "a": "static", "b": "brine", "pos": Vector3(1, 0, 0)})],
		[20.0 * s, func(): _say("knockdown + zone loop"); _a.on_sim_event({"type": "knockdown", "fighter": 1, "reason": "poise"}); _zone = _a.sfx_loop("zone_scorch", Vector3(1, 0, 1))],
		[23.0 * s, func(): _say("combat B + JUICE (jumps to the half-time B section on the next bar)"); _a.music("combat_b", 1.0, {"seed": 7}); _a.stop_loop(_zone, 0.5)],
		[25.0 * s, func(): _a.on_sim_event({"type": "juice", "fighter": 0, "id": "meltdown"})],
		[29.0 * s, func(): _say("boss track, phase 2 layer + Snappington gavel"); _a.music("boss", 1.0, {"layers": {"p2": true, "snappington": true}})],
		[33.0 * s, func(): _say("KO + victory sting + crowd"); _a.on_sim_event({"type": "ko", "fighter": 1}); _a.on_sim_event({"type": "match_end", "winner": 0})],
		[36.0 * s, func(): _say("coach line (Granny, pleased)"); _a.announce("coach_tut_04_success")],
		[39.0 * s, func(): _say("hub radio in the Juice Bar"); _a.end_match(); _a.music("cannery_radio", 1.0); _a.set_room("juice_bar")],
		[42.0 * s, func(): _a.set_room("dock")],
		[45.0 * s, func(): _finish()],
	]


var _started := false


func _start_check() -> bool:
	# autoload _ready() runs after a -s script's _initialize(), so check on the first tick
	print("AUDIO SHOWCASE: enabled=%s bank=%s sfx ids=%d music=%d" % [_a.enabled, _a.bank_loaded, _a.sfx_ids().size(), _a.music_ids().size()])
	if not _a.enabled or not _a.bank_loaded:
		print("Audio is disabled in this process (headless?) or the bank is missing - run without --headless after `node tools/audio/build.js`")
		quit(2)
		return false
	return true


func _say(what: String) -> void:
	print("%6.2fs %s" % [_t, what])


func _hit(a: int, b: int, dmg: float, slot: String, el: String, counter := false) -> void:
	_a.on_sim_event({"type": "hit", "fighter": a, "target": b, "damage": dmg, "point": Vector3(0, 1, 0), "normal": Vector3.UP, "blocked": false, "parried": false, "counter": counter, "part": "head", "element": el, "quality": 0.8, "move": slot, "slot": slot, "knockdown": false, "otg": false}, Vector3.ZERO, {"time": _t})


func _process(delta: float) -> bool:
	if not _started:
		_started = true
		if not _start_check():
			return true
	_t += delta
	while _stage < _plan.size() and _t >= float(_plan[_stage][0]):
		(_plan[_stage][1] as Callable).call()
		_stage += 1
	return false


func _finish() -> void:
	var pos := float(_a.music_position())
	var active := 0
	var voices: Array = _a._voices2d + _a._voices3d
	for v in voices:
		if int(v["handle"]) > 0:
			active += 1
	var missing: Dictionary = _a._missing
	var handles := int(_a._next_handle) - 1
	print("---- showcase summary ----")
	print("music track: %s position %.1f s (bar %s)" % [_a.music_track(), pos, str(_a.music_bar())])
	print("subtitles shown: %d" % _subs)
	print("voices still active: %d, total handles issued: %d" % [active, handles])
	print("missing ids logged: %d %s" % [missing.size(), str(missing.keys())])
	# quick mode compresses time so queued lines (win/coach) are superseded by design; 5 spoken lines is the floor
	var ok: bool = str(_a.music_track()) == "cannery_radio" and pos > 1.0 and _subs >= 5 and missing.is_empty() and handles > 20
	print("RESULT: %s" % ("OK" if ok else "FAIL"))
	quit(0 if ok else 1)
