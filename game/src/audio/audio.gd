extends Node
## Autoload "Audio": buses (Master+limiter, Music, SFX, Voice, UI, Ambience plus owned sub-buses
## Impacts/Movement/Zones -> SFX, Creatures/Dialogue -> Voice, Crowd -> Ambience), the sound bank
## (assets/audio/bank.json, built by tools/audio/build.js), pooled 2D/3D players with priorities and
## variation rules, music with crossfades, bar-synced jumps, stingers and intensity/variant layers,
## the announcer/coach queue (recorded speech or babble + subtitles; v0.9.17 commentary engine:
## CommentaryDirector decides what to say, CommentarySelector picks fresh lines against the persistent
## CommentaryHistory, the queue expires stale calls — docs/audio/COMMENTARY.md), crowd heat and
## arena/hub ambience.
## Contract (docs/ARCHITECTURE.md): sfx(id, pos?, vol_db, pitch), music(track, fade), announce(line_id)
## + `subtitle` signal. Integration helpers: attach_match(sim, player_index) / on_sim_event(ev).
## Invariants: headless/server/lab processes never load or play audio (every call is a safe no-op
## except subtitles); a missing id logs once and never crashes; nothing here changes gameplay.

signal subtitle(speaker: String, text: String, seconds: float)
signal line_started(line_id: String)
signal line_finished(line_id: String)
## v0.9.17 commentary log (audit tool and tests): {kind: request|queued|started|finished|dropped|
## expired|interrupted|invalidated, id, ...}. Emitted only while something is connected.
signal commentary_event(ev: Dictionary)

const BANK_PATH := "res://assets/audio/bank.json"
const BUSES := ["Music", "SFX", "Voice", "UI", "Ambience"]
const SUB_BUSES := {"Impacts": ["SFX", 0.0], "Movement": ["SFX", -4.0], "Zones": ["SFX", -8.0], "Creatures": ["Voice", -3.0], "Dialogue": ["Voice", -2.0], "Crowd": ["Ambience", 0.0], "Radio": ["Music", 0.0]}
const POOL_2D := 24
const POOL_3D := 32
const DUCK_RECOVER := 6.0            ## dB per second
const REDUCED_TRIGGERS := ["ko", "round_start", "juice", "win", "draw", "boss_intro", "boss_phase2", "intro", "time", "stoppage",
	"decision", "career_intro", "career_result"]
const PRIORITY_INTERRUPT := 90       ## interrupts anything at or below its own priority
const PRIORITY_QUEUE_MIN := 25        ## below this a line is only spoken when the booth is free
const QUEUE_MAX := 3
const LINE_GAP_LOW := 1.1            ## seconds of breathing room before a low-priority line
const LINE_GAP_MEDIUM := 0.3
const INTERRUPT_FADE := 0.12         ## an interrupted recording fades instead of clicking off
const SPEECH_DB := -2.0
## When a request finds no line of its own: accurate stand-ins only ([trigger, extra ctx]).
const REQUEST_FALLBACK := {
	"career_intro": [["intro", {}]],
	"career_result": [["win", {}]],
	"decision": [["time", {"kind": "decision"}]],
	"ability_hit": [["ability", {}]],
	"element": [["element_color", {}]],
	"fighter_color": [["color", {}]],
	"matchup_color": [["color", {}]],
	"element_color": [["color", {}]],
	"taunt_punished": [["taunt", {"kind": "punished"}]],
	"hurt": [["low_health", {}]],
}

var enabled := false                  ## false when headless / dedicated server / lab worker
var bank := {}                        ## parsed bank.json
var bank_loaded := false
var crowd_heat := 0.0                 ## 0..1 crossfades murmur/excited/roar
var announcer_mode := "full"          ## full | reduced | off (Settings gameplay.announcer)
## Active announcer line pack ("" = the standard bank). Set per match from the profile option
## `announcer_pack` (the Cannery's Barnaby desk turns on Vintage Bellows) or ctx.announcer_pack.
## Pack lines (announcer entries with "pack") are preferred for every trigger they cover.
var announcer_pack := ""
var _pack_lines := {}                    ## id -> entry (lines that belong to a pack)
var _pack_by_trigger := {}               ## pack -> {trigger -> [ids]}
var subtitles_on := true

var _sfx_entries := {}               ## id -> resolved entry (aliases merged)
var _streams := {}                   ## res path -> AudioStream
var _loop_stream_paths := {}          ## paths whose replacement bank entries request looping
var _missing := {}                   ## logged-once ids
var _voices2d: Array = []            ## Array[Dictionary] {player, id, priority, started, loop, handle}
var _voices3d: Array = []
var _next_handle := 1
var _last_variant := {}              ## id -> last variant index
var _last_play := {}                 ## id -> time of last play (cooldowns)
var _rng := RandomNumberGenerator.new()
var _duck := {}                      ## bus -> current duck dB (negative)
var _duck_target := {}               ## bus -> target duck dB
var _impact_duck_until := 0.0

# music
var _music_slots: Array = []          ## two slot dictionaries {track, entry, base, layers:{id:{player,target,current}}, vol, target, fade_rate, bus}
var _music_cur := -1
var _music_sting: AudioStreamPlayer
var _music_pending_jump := -1.0        ## seconds position to seek to on the next bar line
var _music_pending_stop := false
var _music_pitch := 1.0
var _jukebox_context := ""
var _jukebox_default := ""
var _jukebox_opts := {}
var _music_duck := 0.0

# announcer
var _lines := {}                      ## id -> line dict
var _lines_by_trigger := {}           ## trigger -> Array of ids
var _babble: Babble
var _speech := preload("res://src/audio/speech_library.gd").new()
var _speech_player: AudioStreamPlayer
var _speech_player_b: AudioStreamPlayer   ## the other half of the interrupt crossfade
var _speech_clips: Array = []
var _ann_current := {}                ## {id, priority, until, speaker, follow, trigger}
var _ann_queue: Array = []            ## waiting lines, best first (QUEUE_MAX), each with expires/not_before/tag
var _ann_last_end := -100.0           ## when the booth last finished a line (breathing room)
var _ann_speakers: Array = []         ## the last few speakers (voice balance)
var _ann_seed := 0
var _history: CommentaryHistory = null
var _history_in_memory := false
var _selector: CommentarySelector = null
var _director: CommentaryDirector = null   ## present between begin_match and end_match
var _booth_ctx := {}                  ## standing facts every request is matched against (booth_context)
var _ann_last_trigger_time := {}      ## reduced mode frequency limiting
var _ann_conversation_groups := {}    ## conversation id -> ordered Array[Dictionary]
var _ann_conversation_queue: Array = []
var _ann_active_conversation := ""
var _ann_vars := {}                   ## default {p}/{o} substitutions for the match

# crowd / ambience
var _crowd_players: Array = []        ## 3 loop players
var _ambience: AudioStreamPlayer
var _ambience_next: AudioStreamPlayer
var _ambience_id := ""
var _ambience_fade: Tween
var _ambience_fade_in: Tween
var _arena_id := ""

# match context
var _match := {}                      ## begin_match context
var _bridge: Node = null
var _timers: Array = []               ## [{at, call}] delayed sfx (stormfront strike)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	var headless := DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server") or args.has("--server") or args.has("--lab-worker")
	enabled = not headless
	_rng.seed = 0x5EED
	_ensure_buses()
	for k in ["audio.master", "audio.music", "audio.sfx", "audio.voice", "audio.ui", "audio.ambience"]:
		Settings.apply(k)
	_read_settings()
	Settings.changed.connect(_on_setting_changed)
	# dedicated-server packages are exported without audio assets and never play sound
	if not OS.has_feature("dedicated_server"):
		load_bank()
	_load_lines()
	if Content.has_signal("reloaded"):
		Content.reloaded.connect(_load_lines)
	if enabled:
		_build_pools()
		_babble = Babble.new()
		_babble.name = "Babble"
		add_child(_babble)
		_babble.finished.connect(_on_babble_finished)
		for sp in bank.get("voices", {}):
			_babble.add_voice(str(sp), bank["voices"][sp])
		_speech_player = _make_2d("Dialogue")
		_speech_player.name = "RecordedSpeech"
		_speech_player.volume_db = SPEECH_DB
		_speech_player.finished.connect(_advance_speech.bind(_speech_player))
		_speech_player_b = _make_2d("Dialogue")
		_speech_player_b.name = "RecordedSpeechB"
		_speech_player_b.volume_db = SPEECH_DB
		_speech_player_b.finished.connect(_advance_speech.bind(_speech_player_b))
		_music_sting = AudioStreamPlayer.new()
		_music_sting.bus = "Music"
		_music_sting.name = "Sting"
		add_child(_music_sting)
		_ambience = _make_2d("Ambience")
		_ambience_next = _make_2d("Ambience")
		call_deferred("_warm_streams")


func _read_settings() -> void:
	announcer_mode = str(Settings.get_value("gameplay.announcer"))
	subtitles_on = bool(Settings.get_value("access.subtitles"))


func _on_setting_changed(key: String, _v) -> void:
	if key == "audio.jukebox" and _jukebox_context != "":
		var options := _jukebox_opts.duplicate()
		options["restart"] = true
		music(_jukebox_default, 0.5, options)
	if key == "gameplay.announcer" or key == "access.subtitles":
		_read_settings()


# ---------------------------------------------------------------------------------------
# Buses
# ---------------------------------------------------------------------------------------

func _ensure_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")
	for sb in SUB_BUSES:
		var spec: Array = SUB_BUSES[sb]
		if AudioServer.get_bus_index(sb) < 0:
			AudioServer.add_bus()
			var i2 := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i2, sb)
			AudioServer.set_bus_send(i2, str(spec[0]))
			AudioServer.set_bus_volume_db(i2, float(spec[1]))
		_duck[sb] = 0.0
		_duck_target[sb] = 0.0
	var master := AudioServer.get_bus_index("Master")
	var has_limiter := false
	for i in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter:
			has_limiter = true
	if not has_limiter:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -1.0
		lim.pre_gain_db = 0.0
		AudioServer.add_bus_effect(master, lim)
	# Crowd reverb (arena character) and the diegetic radio filter are owned here
	var crowd := AudioServer.get_bus_index("Crowd")
	if crowd >= 0 and AudioServer.get_bus_effect_count(crowd) == 0:
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.7
		rv.damping = 0.5
		rv.wet = 0.25
		rv.dry = 0.9
		AudioServer.add_bus_effect(crowd, rv)
	var radio := AudioServer.get_bus_index("Radio")
	if radio >= 0 and AudioServer.get_bus_effect_count(radio) == 0:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 4000.0
		AudioServer.add_bus_effect(radio, lp)
		var eq := AudioEffectLowShelfFilter.new()
		eq.cutoff_hz = 200.0
		eq.gain = 0.0
		AudioServer.add_bus_effect(radio, eq)


func _bus_base_db(bus: String) -> float:
	return float(SUB_BUSES[bus][1]) if SUB_BUSES.has(bus) else 0.0


# ---------------------------------------------------------------------------------------
# Bank
# ---------------------------------------------------------------------------------------

func load_bank() -> bool:
	bank_loaded = false
	_sfx_entries.clear()
	if not FileAccess.file_exists(BANK_PATH):
		Log.e("audio", "bank missing: %s (run `node tools/audio/build.js`)" % BANK_PATH)
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(BANK_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		Log.e("audio", "bank.json is not valid JSON")
		return false
	bank = parsed
	_streams.clear()
	_loop_stream_paths.clear()
	var sfx: Dictionary = bank.get("sfx", {})
	for id in sfx:
		var entry: Dictionary = _resolve_entry(sfx, str(id), 0)
		if bool(entry.get("loop", false)):
			for file in entry.get("files", []): _loop_stream_paths[str(file)] = true
	for id in bank.get("music", {}):
		var entry: Dictionary = bank["music"][id]
		if entry.get("loop") != null: _loop_stream_paths[str(entry.get("file", ""))] = true
	for id in sfx:
		_sfx_entries[id] = _resolve_entry(sfx, str(id), 0)
	bank_loaded = true
	Log.i("audio", "bank loaded: %d sfx ids, %d music tracks, %d voices" % [_sfx_entries.size(), bank.get("music", {}).size(), bank.get("voices", {}).size()])
	return true


func _resolve_entry(sfx: Dictionary, id: String, depth: int) -> Dictionary:
	var e: Dictionary = sfx.get(id, {})
	if e.has("alias") and depth < 4:
		var base := _resolve_entry(sfx, str(e["alias"]), depth + 1)
		var merged := base.duplicate()
		for k in e:
			if k != "alias":
				merged[k] = e[k]
		return merged
	return e


func has_sfx(id: String) -> bool:
	return _sfx_entries.has(id)


func sfx_ids() -> Array:
	var out: Array = _sfx_entries.keys()
	out.sort()
	return out


func music_ids() -> Array:
	var out: Array = bank.get("music", {}).keys()
	out.sort()
	return out


func _stream(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	if not ResourceLoader.exists(path):
		return null
	var s = load(path)
	if s is AudioStream:
		if _loop_stream_paths.has(path):
			if s is AudioStreamMP3: (s as AudioStreamMP3).loop = true
			elif s is AudioStreamOggVorbis: (s as AudioStreamOggVorbis).loop = true
		_streams[path] = s
		return s
	return null


func _warm_streams() -> void:
	# preload SFX streams in chunks so the title screen never waits on disk
	var paths: Array = []
	for id in _sfx_entries:
		for f in _sfx_entries[id].get("files", []):
			paths.append(str(f))
	var i := 0
	while i < paths.size():
		var stop := mini(paths.size(), i + 48)
		while i < stop:
			_stream(str(paths[i]))
			i += 1
		await get_tree().process_frame


# ---------------------------------------------------------------------------------------
# Pools and one-shots
# ---------------------------------------------------------------------------------------

func _make_2d(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func _build_pools() -> void:
	for i in POOL_2D:
		var p := _make_2d("SFX")
		p.name = "Sfx2D_%d" % i
		_voices2d.append({"player": p, "id": "", "priority": 0, "started": 0.0, "loop": false, "handle": 0, "fade": 0.0, "fade_target": 0.0, "base_db": 0.0})
	for i in POOL_3D:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "SFX"
		p3.name = "Sfx3D_%d" % i
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.unit_size = 7.0
		p3.max_distance = 60.0
		p3.panning_strength = 1.2
		add_child(p3)
		_voices3d.append({"player": p3, "id": "", "priority": 0, "started": 0.0, "loop": false, "handle": 0, "fade": 0.0, "fade_target": 0.0, "base_db": 0.0})


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _warn_missing(id: String) -> void:
	if not _missing.has(id):
		_missing[id] = true
		Log.w("audio", "unknown sound id '%s'" % id)


## Plays a one-shot (or starts a loop entry). pos: Vector3 for 3D, null for 2D. Returns a voice
## handle (>0) or -1. vol_db/pitch are offsets on top of the bank entry and its random variation.
func sfx(id: String, pos = null, vol_db := 0.0, pitch := 1.0) -> int:
	if not enabled or not bank_loaded:
		return -1
	var e: Dictionary = _sfx_entries.get(id, {})
	if e.is_empty():
		_warn_missing(id)
		return -1
	var now := _now()
	var cd := float(e.get("cooldown", 0.0))
	if cd > 0.0 and now - float(_last_play.get(id, -100.0)) < cd:
		return -1
	var files: Array = e.get("files", [])
	if files.is_empty():
		_warn_missing(id)
		return -1
	var vi := 0
	if files.size() > 1:
		vi = _rng.randi_range(0, files.size() - 2)
		if vi >= int(_last_variant.get(id, -1)):
			vi += 1
	_last_variant[id] = vi
	var stream := _stream(str(files[vi]))
	if stream == null:
		_warn_missing(id)
		return -1
	var spatial := bool(e.get("spatial", true)) and pos is Vector3
	var priority := int(e.get("priority", 50))
	var v := _alloc_voice(spatial, id, priority, int(e.get("max_voices", 4)))
	if v.is_empty():
		return -1
	var pr: Array = e.get("pitch", [1.0, 1.0])
	var player: Node = v["player"]
	var base_db := float(e.get("gain", 0.0)) + vol_db + _rng.randf_range(-1.0, 1.0)
	if spatial:
		var p3 := player as AudioStreamPlayer3D
		p3.global_position = pos
		p3.stream = stream
		p3.bus = str(e.get("bus", "SFX"))
		p3.volume_db = base_db
		p3.pitch_scale = pitch * _rng.randf_range(float(pr[0]), float(pr[1]))
		p3.play()
	else:
		var p2 := player as AudioStreamPlayer
		p2.stream = stream
		p2.bus = str(e.get("bus", "SFX"))
		p2.volume_db = base_db
		p2.pitch_scale = pitch * _rng.randf_range(float(pr[0]), float(pr[1]))
		p2.play()
	v["id"] = id
	v["priority"] = priority
	v["started"] = now
	v["loop"] = bool(e.get("loop", false))
	v["handle"] = _next_handle
	v["fade"] = 0.0
	v["fade_target"] = 0.0
	v["base_db"] = base_db
	_next_handle += 1
	_last_play[id] = now
	if str(e.get("bus", "")) == "Impacts" and priority >= 80:
		_impact_duck_until = now + 0.15
	return v["handle"]


## Starts a looping entry (zone, drag, charge, hover...). Returns a handle for stop_loop/set_loop_pos.
func sfx_loop(id: String, pos = null, vol_db := 0.0) -> int:
	return sfx(id, pos, vol_db, 1.0)


func stop_loop(handle: int, fade := 0.25) -> void:
	var v := _voice_by_handle(handle)
	if v.is_empty():
		return
	if fade <= 0.0:
		_stop_voice(v)
	else:
		v["fade_target"] = -60.0
		v["fade"] = 60.0 / fade


func set_loop_pos(handle: int, pos: Vector3) -> void:
	var v := _voice_by_handle(handle)
	if not v.is_empty() and v["player"] is AudioStreamPlayer3D:
		(v["player"] as AudioStreamPlayer3D).global_position = pos


func set_loop_volume(handle: int, vol_db: float, fade := 0.2) -> void:
	var v := _voice_by_handle(handle)
	if v.is_empty():
		return
	v["fade_target"] = vol_db
	v["fade"] = maxf(1.0, absf(vol_db - _voice_offset(v)) / maxf(0.01, fade))


func is_playing(handle: int) -> bool:
	var v := _voice_by_handle(handle)
	return not v.is_empty()


func stop_all_sfx(fade := 0.1) -> void:
	for v in _voices2d + _voices3d:
		if v["handle"] > 0:
			if fade <= 0.0:
				_stop_voice(v)
			else:
				v["fade_target"] = -60.0
				v["fade"] = 60.0 / fade


func _voice_by_handle(handle: int) -> Dictionary:
	if handle <= 0:
		return {}
	for v in _voices2d:
		if v["handle"] == handle and _playing(v):
			return v
	for v in _voices3d:
		if v["handle"] == handle and _playing(v):
			return v
	return {}


func _playing(v: Dictionary) -> bool:
	return bool((v["player"] as Node).get("playing"))


func _voice_offset(v: Dictionary) -> float:
	return float((v["player"] as Node).get("volume_db")) - float(v["base_db"])


func _stop_voice(v: Dictionary) -> void:
	(v["player"] as Node).call("stop")
	v["handle"] = 0
	v["id"] = ""
	v["loop"] = false


func _alloc_voice(spatial: bool, id: String, priority: int, max_same: int) -> Dictionary:
	var pool: Array = _voices3d if spatial else _voices2d
	var same := 0
	var oldest_same: Dictionary = {}
	var free: Dictionary = {}
	var steal: Dictionary = {}
	for v in pool:
		if not _playing(v):
			if free.is_empty():
				free = v
			continue
		if v["id"] == id:
			same += 1
			if oldest_same.is_empty() or float(v["started"]) < float(oldest_same["started"]):
				oldest_same = v
		if int(v["priority"]) <= priority and not bool(v["loop"]):
			if steal.is_empty() or int(v["priority"]) < int(steal["priority"]) or (int(v["priority"]) == int(steal["priority"]) and float(v["started"]) < float(steal["started"])):
				steal = v
	if same >= max_same and not oldest_same.is_empty():
		_stop_voice(oldest_same)
		return oldest_same
	if not free.is_empty():
		return free
	if not steal.is_empty():
		_stop_voice(steal)
		return steal
	return {}


# ---------------------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------------------

func ui(id: String, vol_db := 0.0, pitch := 1.0) -> int:
	return sfx(id, null, vol_db, pitch)


## Coin ping repeated n times (capped at 5), rising in pitch.
func scrip(n: int) -> void:
	var count := clampi(n, 1, 5)
	for i in count:
		_timers.append({"at": _now() + 0.07 * i, "id": "ui_scrip", "pos": null, "vol": 0.0, "pitch": 1.0 + 0.06 * i})


# ---------------------------------------------------------------------------------------
# Music
# ---------------------------------------------------------------------------------------

func _slot_new() -> Dictionary:
	return {"track": "", "entry": {}, "base": null, "layers": {}, "vol": -80.0, "target": -80.0, "rate": 40.0, "bus": "Music", "gain": 0.0}


func music_track() -> String:
	return str(_music_slots[_music_cur]["track"]) if _music_cur >= 0 else ""


func is_music_playing() -> bool:
	return _music_cur >= 0 and _music_slots[_music_cur]["base"] != null and (_music_slots[_music_cur]["base"] as AudioStreamPlayer).playing


## Plays a track from the bank with a crossfade. opts: {layers: {id: bool}, seed: int,
## intensity: float, section: String (start section), pitch: float, diegetic: bool}
func music(track: String, fade := 1.0, opts := {}) -> void:
	if track != "" and not bool(opts.get("jukebox_resolved", false)):
		var context := str(opts.get("context", Jukebox.context_for(track)))
		var current := music_track() if context == _jukebox_context else ""
		_jukebox_context = context
		_jukebox_default = track
		_jukebox_opts = opts.duplicate()
		track = Jukebox.choose(context, track, current)
	if not enabled or not bank_loaded:
		return
	var entries: Dictionary = bank.get("music", {})
	if track == "":
		stop_music(fade)
		return
	if not entries.has(track):
		_warn_missing("music:" + track)
		return
	if _music_cur >= 0 and str(_music_slots[_music_cur]["track"]) == track and is_music_playing() and not bool(opts.get("restart", false)):
		_apply_music_opts(_music_slots[_music_cur], opts)
		return
	var entry: Dictionary = entries[track]
	var base_stream := _stream(str(entry["file"]))
	if base_stream == null:
		_warn_missing("music:" + track)
		return
	if _music_slots.is_empty():
		_music_slots = [_slot_new(), _slot_new()]
	var next_i := 1 - _music_cur if _music_cur >= 0 else 0
	var slot: Dictionary = _music_slots[next_i]
	_free_slot(slot)
	var diegetic := bool(opts.get("diegetic", entry.get("tags", []).has("diegetic")))
	slot["bus"] = "Radio" if diegetic else "Music"
	slot["track"] = track
	slot["entry"] = entry
	slot["gain"] = float(entry.get("gain", 0.0))
	var pitch := float(opts.get("pitch", 1.0))
	var base := AudioStreamPlayer.new()
	base.stream = base_stream
	if not bool(opts.get("jukebox_preview", false)) and _jukebox_context != "" and str(Jukebox.config(_jukebox_context)["mode"]) != "game":
		base.stream = base_stream.duplicate()
		if base.stream is AudioStreamWAV:
			(base.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
		elif base.stream is AudioStreamOggVorbis:
			(base.stream as AudioStreamOggVorbis).loop = false
		elif base.stream is AudioStreamMP3:
			(base.stream as AudioStreamMP3).loop = false
		base.finished.connect(_playlist_finished.bind(track))
	base.bus = slot["bus"]
	base.pitch_scale = pitch
	base.name = "Music_" + track
	add_child(base)
	slot["base"] = base
	var layers := {}
	for L in entry.get("layers", []):
		var ls := _stream(str(L["file"]))
		if ls == null:
			continue
		var lp := AudioStreamPlayer.new()
		lp.stream = ls
		lp.bus = slot["bus"]
		lp.pitch_scale = pitch
		lp.name = "Music_%s_%s" % [track, L["id"]]
		add_child(lp)
		layers[str(L["id"])] = {"player": lp, "def": L, "current": float(L.get("default_db", 0.0)), "target": float(L.get("default_db", 0.0))}
	slot["layers"] = layers
	_apply_music_opts(slot, opts)
	# start everything in the same frame so stems stay sample-aligned
	var from := 0.0
	var section := str(opts.get("section", ""))
	if section != "":
		from = _section_start_seconds(entry, section)
	base.volume_db = -80.0
	base.play(from)
	for lid in layers:
		var l: Dictionary = layers[lid]
		(l["player"] as AudioStreamPlayer).volume_db = -80.0
		(l["player"] as AudioStreamPlayer).play(from)
	slot["vol"] = -80.0 if _music_cur >= 0 else -12.0
	slot["target"] = 0.0
	slot["rate"] = 80.0 / maxf(0.05, fade)
	if _music_cur >= 0:
		var old: Dictionary = _music_slots[_music_cur]
		old["target"] = -80.0
		old["rate"] = 80.0 / maxf(0.05, fade)
	_music_cur = next_i
	_music_pending_jump = -1.0
	_music_pending_stop = false


## Plays a Jukebox preview immediately, replacing any current track or preview.
func preview_music(track: String) -> void:
	if not enabled or not bank_loaded:
		return
	var entries: Dictionary = bank.get("music", {})
	if not entries.has(track) or bool(entries[track].get("stinger", false)):
		return
	if _music_slots.is_empty():
		_music_slots = [_slot_new(), _slot_new()]
	for slot in _music_slots:
		_free_slot(slot)
	_music_cur = -1
	_music_pending_jump = -1.0
	_music_pending_stop = false
	music(track, 0.08, {"jukebox_resolved": true, "jukebox_preview": true, "restart": true})


func _apply_music_opts(slot: Dictionary, opts: Dictionary) -> void:
	var layers: Dictionary = slot["layers"]
	if opts.has("seed"):
		# per-match variation: enable one percussion variant (or none) and nudge the pitch a hair
		var r := RandomNumberGenerator.new()
		r.seed = int(opts["seed"])
		var variants: Array = []
		for lid in layers:
			if str(layers[lid]["def"].get("kind", "")) == "variant":
				variants.append(lid)
		var pick := r.randi_range(-1, variants.size() - 1)
		for i in variants.size():
			layers[variants[i]]["target"] = 0.0 if i == pick else -80.0
			layers[variants[i]]["current"] = layers[variants[i]]["target"]
	if opts.has("layers"):
		var want: Dictionary = opts["layers"]
		for lid in want:
			if layers.has(lid):
				layers[lid]["target"] = 0.0 if bool(want[lid]) else -80.0
	if opts.has("intensity"):
		music_intensity(float(opts["intensity"]))


## Lead/intensity layers fade in with v (0..1); 0 = muted.
func music_intensity(v: float) -> void:
	if _music_cur < 0:
		return
	var layers: Dictionary = _music_slots[_music_cur]["layers"]
	for lid in layers:
		if str(layers[lid]["def"].get("kind", "")) == "intensity":
			layers[lid]["target"] = -80.0 if v <= 0.01 else lerpf(-24.0, 0.0, clampf(v, 0.0, 1.0))


func music_layer(id: String, on: bool, _fade := 1.0) -> void:
	if _music_cur < 0:
		return
	var layers: Dictionary = _music_slots[_music_cur]["layers"]
	if layers.has(id):
		layers[id]["target"] = 0.0 if on else -80.0


## Mutes lead-type layers (used while the announcer babbles).
func _music_lead_mute(mute: bool) -> void:
	_music_duck = -6.0 if mute else 0.0


func music_bar_seconds() -> float:
	if _music_cur < 0:
		return 0.0
	return float(_music_slots[_music_cur]["entry"].get("bar_seconds", 0.0)) / maxf(0.01, _music_pitch)


func music_position() -> float:
	if not is_music_playing():
		return 0.0
	return (_music_slots[_music_cur]["base"] as AudioStreamPlayer).get_playback_position()


## Bar (1-based) and beat phase (0..1 within the bar) of the current track.
func music_bar() -> Dictionary:
	var bs := music_bar_seconds()
	if bs <= 0.0:
		return {"bar": 0, "phase": 0.0}
	var p := music_position()
	return {"bar": int(floor(p / bs)) + 1, "phase": fmod(p, bs) / bs}


func _section_start_seconds(entry: Dictionary, section: String) -> float:
	for s in entry.get("sections", []):
		if str(s["id"]) == section:
			return (float(s["start_bar"]) - 1.0) * float(entry["bar_seconds"])
	return 0.0


## Jumps to the nearest bar of `section` on the next bar line (e.g. combat B after JUICE).
func music_jump(section: String) -> void:
	if not is_music_playing():
		return
	var entry: Dictionary = _music_slots[_music_cur]["entry"]
	var start := _section_start_seconds(entry, section)
	var bars := 0
	for s in entry.get("sections", []):
		if str(s["id"]) == section:
			bars = int(s["bars"])
	if bars <= 0:
		return
	var bs := float(entry["bar_seconds"])
	var bar_now := music_bar()
	# jump to the same bar offset inside the section so the phrase stays coherent
	var offset := (int(bar_now["bar"]) - 1) % bars
	_music_pending_jump = start + float(offset) * bs


## Stops the music (next beat, short fade) and plays a one-shot sting (victory / defeat).
func sting(track: String) -> void:
	if not enabled or not bank_loaded:
		return
	var entries: Dictionary = bank.get("music", {})
	if not entries.has(track):
		_warn_missing("music:" + track)
		return
	var s := _stream(str(entries[track]["file"]))
	if s == null:
		return
	stop_music(0.1)
	_music_sting.stream = s
	_music_sting.volume_db = float(entries[track].get("gain", 0.0))
	_music_sting.play()


func stop_music(fade := 1.0) -> void:
	if _music_cur < 0:
		return
	var slot: Dictionary = _music_slots[_music_cur]
	slot["target"] = -80.0
	slot["rate"] = 80.0 / maxf(0.05, fade)
	_music_cur = -1


func _free_slot(slot: Dictionary) -> void:
	if slot["base"] != null:
		var base := slot["base"] as AudioStreamPlayer
		base.stop()
		base.queue_free()
		slot["base"] = null
	for lid in slot["layers"]:
		var player := slot["layers"][lid]["player"] as AudioStreamPlayer
		player.stop()
		player.queue_free()
	slot["layers"] = {}
	slot["track"] = ""


func _tick_music(dt: float) -> void:
	for si in _music_slots.size():
		var slot: Dictionary = _music_slots[si]
		if slot["base"] == null:
			continue
		var vol := float(slot["vol"])
		var target := float(slot["target"])
		vol = move_toward(vol, target, float(slot["rate"]) * dt)
		slot["vol"] = vol
		var base_db := vol + float(slot["gain"]) + _music_duck
		(slot["base"] as AudioStreamPlayer).volume_db = base_db
		var layers: Dictionary = slot["layers"]
		for lid in layers:
			var l: Dictionary = layers[lid]
			var cur := move_toward(float(l["current"]), float(l["target"]), 40.0 * dt)
			l["current"] = cur
			var lead_duck := _music_duck * 1.5 if str(l["def"].get("kind", "")) in ["lead", "intensity", "phase"] else _music_duck
			(l["player"] as AudioStreamPlayer).volume_db = base_db - _music_duck + lead_duck + cur
		if vol <= -79.0 and target <= -79.0 and si != _music_cur:
			_free_slot(slot)
	if _music_pending_jump >= 0.0 and is_music_playing():
		var bar := music_bar()
		var bs := music_bar_seconds()
		if float(bar["phase"]) * bs < dt * 1.5 or float(bar["phase"]) > 0.985:
			var slot2: Dictionary = _music_slots[_music_cur]
			(slot2["base"] as AudioStreamPlayer).seek(_music_pending_jump)
			for lid2 in slot2["layers"]:
				var lp: AudioStreamPlayer = slot2["layers"][lid2]["player"]
				if int(slot2["layers"][lid2]["def"].get("loop_bars", 0)) >= int(slot2["entry"].get("bars", 0)):
					lp.seek(_music_pending_jump)
			_music_pending_jump = -1.0


# ---------------------------------------------------------------------------------------
# Announcer and coach (v0.9.17: docs/audio/COMMENTARY.md)
# ---------------------------------------------------------------------------------------
# Lines come from content (announcer/*.json): {id, speaker, trigger, when, priority, text} plus the
# v0.9.17 metadata {families, energy, situation, also}. `also` lists further triggers a line is
# accurate for. Selection (CommentarySelector) scores every line whose `when` matches against the
# persistent CommentaryHistory. The queue holds up to QUEUE_MAX waiting lines, best first; each one
# expires (a late call is worse than none) and a result call (KO, stoppage, decision, match end)
# invalidates everything less urgent that was waiting. During a match CommentaryDirector decides
# what to talk about; announce()/announce_trigger()/say() stay the API for menus, the hub, the
# tutorial and the modes.

func _load_lines() -> void:
	_lines.clear()
	_lines_by_trigger.clear()
	_pack_lines.clear()
	_pack_by_trigger.clear()
	_ann_conversation_groups.clear()
	for id in Content.ids("announcer"):
		var e := Content.get_entry("announcer", id)
		if str(e.get("text", "")) == "" or e.has("retired"):
			continue     # retired: asserts something the game does not have (docs/audio/COMMENTARY.md §5)
		var pk := str(e.get("pack", ""))
		var triggers: Array = [str(e.get("trigger", ""))]
		for extra in e.get("also", []):
			if not triggers.has(str(extra)):
				triggers.append(str(extra))
		if pk != "":
			_pack_lines[id] = e
			if not _pack_by_trigger.has(pk):
				_pack_by_trigger[pk] = {}
			for pt in triggers:
				if not (_pack_by_trigger[pk] as Dictionary).has(pt):
					_pack_by_trigger[pk][pt] = []
				_pack_by_trigger[pk][pt].append(id)
			continue
		_lines[id] = e
		for trig in triggers:
			if not _lines_by_trigger.has(trig):
				_lines_by_trigger[trig] = []
			_lines_by_trigger[trig].append(id)
		var conversation_id := str(e.get("conversation_id", ""))
		if conversation_id != "":
			var group: Array = _ann_conversation_groups.get(conversation_id, [])
			group.append(e)
			_ann_conversation_groups[conversation_id] = group
	for conversation_id in _ann_conversation_groups:
		var group: Array = _ann_conversation_groups[conversation_id]
		group.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("conversation_turn", 0)) < int(b.get("conversation_turn", 0))
		)
		_ann_conversation_groups[conversation_id] = group


## The standard bank's line ids (pack lines: pack_line_ids).
func line_ids() -> Array:
	var out: Array = _lines.keys()
	out.sort()
	return out


func line(id: String) -> Dictionary:
	return _lines.get(id, _pack_lines.get(id, {}))


## Standard-bank ids registered for a trigger (its own lines and the ones listing it in `also`).
func trigger_line_ids(trigger: String) -> Array:
	return (_lines_by_trigger.get(trigger, []) as Array).duplicate()


## Line packs installed (ids), e.g. ["vintage_bellows"].
func line_packs() -> Array:
	var out: Array = _pack_by_trigger.keys()
	out.sort()
	return out


func pack_line_ids(pack: String) -> Array:
	var out: Array = []
	for t in _pack_by_trigger.get(pack, {}):
		for id in _pack_by_trigger[pack][t]:
			if not out.has(id):
				out.append(id)
	out.sort()
	return out


## Selects the active line pack ("" or an unknown pack = the standard bank).
func set_announcer_pack(pack: String) -> void:
	announcer_pack = pack if _pack_by_trigger.has(pack) else ""


## The commentary memory (persistent across matches and restarts; see CommentaryHistory).
func commentary_history() -> CommentaryHistory:
	_ensure_commentary()
	return _history


func _ensure_commentary() -> void:
	if _history == null:
		_history = CommentaryHistory.open_default() if not _history_in_memory else CommentaryHistory.new()
		_selector = CommentarySelector.new(_history)
		_selector.seed_match(_ann_seed)


## Tests and tools: keep the history in memory (no file) from now on, starting empty.
func use_memory_history() -> void:
	_history_in_memory = true
	_history = CommentaryHistory.new()
	_selector = CommentarySelector.new(_history)
	_selector.seed_match(_ann_seed)


func _substitute(text: String, vars: Dictionary) -> String:
	var out := text
	var merged := _ann_vars.duplicate()
	for k in vars:
		merged[k] = vars[k]
	for k in merged:
		out = out.replace("{%s}" % k, str(merged[k]))
	return out


## Speaks a line from the bank by id (announcer or coach). Returns false if dropped.
## opts: {ttl, tag, priority (overrides the line's), follow (a request spoken after it)}.
func announce(line_id: String, vars := {}, opts := {}) -> bool:
	var l: Dictionary = _lines.get(line_id, _pack_lines.get(line_id, {}))
	if l.is_empty():
		_warn_missing("line:" + line_id)
		return false
	var priority := int(opts.get("priority", l.get("priority", 50)))
	return _say_line(line_id, str(l.get("speaker", "barnaby")), str(l["text"]), priority, vars, str(l.get("mood", "")), str(l.get("trigger", "")), opts)


## Speaks arbitrary text (coach prompts, mod lines). Returns false if dropped.
func say(speaker: String, text: String, priority := 50, vars := {}, mood := "") -> bool:
	return _say_line("say:%d" % hash(text), speaker, text, priority, vars, mood, "say", {})


## Recorded duration for world bubbles and scripted dialogue pacing; zero for unrecorded text.
func speech_seconds(speaker: String, text: String, vars := {}) -> float:
	var merged := _ann_vars.duplicate()
	merged.merge(vars, true)
	var recording := _speech.resolve("", speaker, text, _substitute(text, vars), merged, _match)
	return float(recording.get("seconds", 0.0))


func stop_announcer() -> void:
	_stop_speech()
	_ann_current = {}
	_ann_queue.clear()
	_ann_last_end = -100.0      # an explicit silence: the next line may start at once
	_ann_conversation_queue.clear()
	_ann_active_conversation = ""
	if _babble:
		_babble.stop()
	_music_lead_mute(false)
	_duck_target["Crowd"] = 0.0


func announcer_busy() -> bool:
	return not _ann_current.is_empty()


## The waiting lines, best first (inspection/tests): [{id, priority, expires, tag, ...}].
func announcer_queue() -> Array:
	return _ann_queue


static func default_ttl(priority: int) -> float:
	if priority >= 90:
		return 5.0
	if priority >= 70:
		return 3.0
	if priority >= 50:
		return 2.0
	return 1.5


func _say_line(id: String, speaker: String, text: String, priority: int, vars: Dictionary, mood: String, trigger: String, opts := {}) -> bool:
	var is_announcer := speaker in ["barnaby", "kendall"]
	if announcer_mode == "off" and is_announcer:
		_log_commentary("dropped", {"id": id, "why": "off"})
		return false
	var reduced := announcer_mode == "reduced"
	if reduced and is_announcer and trigger != "say" and not REDUCED_TRIGGERS.has(trigger) and not REDUCED_TRIGGERS.has(str(opts.get("request", ""))):
		_log_commentary("dropped", {"id": id, "why": "reduced"})
		return false
	var now := _now()
	if reduced and trigger != "say":
		if now - float(_ann_last_trigger_time.get(trigger, -100.0)) < 8.0:
			_log_commentary("dropped", {"id": id, "why": "reduced_rate"})
			return false
		_ann_last_trigger_time[trigger] = now
	if priority >= 100:
		invalidate_queued(100)     # a result call: everything less urgent that was waiting is stale
	var ttl := float(opts.get("ttl", default_ttl(priority)))
	var entry := {"id": id, "speaker": speaker, "text": _substitute(text, vars), "priority": priority, "mood": mood, "vars": vars, "source": text,
		"expires": now + ttl, "tag": str(opts.get("tag", "")), "queued_at": now, "trigger": trigger, "follow": opts.get("follow", {})}
	if _ann_current.is_empty():
		# breathing room: low-priority talk waits a beat after the last line
		var gap := LINE_GAP_LOW if priority < 50 else (LINE_GAP_MEDIUM if priority < 80 else 0.0)
		if bool(opts.get("turn", false)):
			gap = 0.0       # the next turn of an exchange keeps the exchange's own timing
		if now - _ann_last_end >= gap:
			_start_line(entry)
			return true
		entry["not_before"] = _ann_last_end + gap
		return _enqueue(entry)
	var cur_p := int(_ann_current["priority"])
	if (priority >= PRIORITY_INTERRUPT and priority >= cur_p) or (priority >= 80 and cur_p <= 40):
		_log_commentary("interrupted", {"id": str(_ann_current["id"]), "by": id})
		_start_line(entry)
		return true
	if priority >= PRIORITY_QUEUE_MIN:
		return _enqueue(entry)
	_log_commentary("dropped", {"id": id, "why": "busy"})
	return false


func _enqueue(entry: Dictionary) -> bool:
	_ann_queue.append(entry)
	_ann_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["priority"]) != int(b["priority"]):
			return int(a["priority"]) > int(b["priority"])
		return float(a["queued_at"]) < float(b["queued_at"]))
	while _ann_queue.size() > QUEUE_MAX:
		var gone: Dictionary = _ann_queue.pop_back()
		_log_commentary("dropped", {"id": str(gone["id"]), "why": "queue_full"})
		if gone == entry:
			return false
	_log_commentary("queued", {"id": str(entry["id"]), "priority": int(entry["priority"]), "ttl": float(entry["expires"]) - _now()})
	return true


## Drops waiting lines that are stale now: everything below `below` priority (a result call), or
## only those carrying `tag` (a new round makes the last round's calls stale).
func invalidate_queued(below: int, tag := "") -> void:
	var keep: Array = []
	for e in _ann_queue:
		if int(e["priority"]) < below and (tag == "" or str(e["tag"]) == tag):
			_log_commentary("invalidated", {"id": str(e["id"])})
		else:
			keep.append(e)
	_ann_queue = keep


## The next waiting line that is still fresh, or {} (expired ones are dropped and logged).
func _next_queued(now: float) -> Dictionary:
	while not _ann_queue.is_empty():
		var e: Dictionary = _ann_queue[0]
		if now > float(e["expires"]):
			_ann_queue.pop_front()
			_log_commentary("expired", {"id": str(e["id"]), "waited": now - float(e["queued_at"])})
			continue
		if now < float(e.get("not_before", 0.0)):
			return {}
		_ann_queue.pop_front()
		return e
	return {}


func _start_line(entry: Dictionary) -> void:
	if int(entry.get("priority", 0)) >= PRIORITY_INTERRUPT:
		_ann_conversation_queue.clear()
		_ann_active_conversation = ""
	var text: String = entry["text"]
	var speaker: String = entry["speaker"]
	_stop_speech(true)
	if _babble:
		_babble.stop()
	var merged := _ann_vars.duplicate()
	merged.merge(entry["vars"], true)
	var recording := _speech.resolve(str(entry["id"]), speaker, str(entry.get("source", text)), text, merged, _match)
	var seconds := float(recording.get("seconds", 0.0))
	var reduced := announcer_mode == "reduced"
	if enabled and not recording.is_empty():
		_speech_clips = recording["clips"].duplicate()
		_play_speech_clip()
	elif enabled and _babble and _babble.has_voice(speaker):
		var names: Array = []
		for k in ["p", "o"]:
			var v = entry["vars"].get(k, _ann_vars.get(k, ""))
			if str(v) != "":
				names.append(str(v))
		for nm in _match.get("names", []):
			names.append(str(nm))
		seconds = _babble.speak(str(entry["id"]), speaker, text, _ann_seed + hash(str(entry["id"])), reduced and speaker == "barnaby", names, str(entry["mood"]))
	if seconds <= 0.0:
		seconds = clampf(float(text.length()) * 0.055, 1.2, 4.0)
	_ann_current = {"id": entry["id"], "priority": entry["priority"], "until": _now() + seconds + 0.15, "speaker": speaker,
		"recorded": not recording.is_empty(), "follow": entry.get("follow", {}), "trigger": str(entry.get("trigger", "")),
		"follow_id": str(line(str(entry["id"])).get("follow_id", "")), "vars": entry.get("vars", {})}
	var fams: Array = line(str(entry["id"])).get("families", [])
	if speaker in ["barnaby", "kendall"]:
		_ensure_commentary()
		_history.note_play(str(entry["id"]), fams)
		_ann_speakers.append(speaker)
		if _ann_speakers.size() > 4:
			_ann_speakers.pop_front()
	if _director:
		_director.note_line_started(_director.t)
	if subtitles_on:
		subtitle.emit(speaker, text, seconds + 0.6)
	_log_commentary("started", {"id": str(entry["id"]), "speaker": speaker, "seconds": seconds, "priority": int(entry["priority"]),
		"waited": _now() - float(entry.get("queued_at", _now())), "said": text})
	line_started.emit(str(entry["id"]))
	_music_lead_mute(true)
	_duck_target["Crowd"] = -3.0


## crossfade = true: the outgoing recording fades for INTERRUPT_FADE instead of clicking off.
func _stop_speech(crossfade := false) -> void:
	_speech_clips.clear()
	if _speech_player == null:
		return
	if crossfade and _speech_player.playing and enabled:
		var old := _speech_player
		_speech_player = _speech_player_b
		_speech_player_b = old
		var tw := create_tween()
		tw.tween_property(old, "volume_db", -40.0, INTERRUPT_FADE)
		tw.tween_callback(func() -> void:
			old.stop()
			old.stream = null
			old.volume_db = SPEECH_DB)
	else:
		_speech_player.stop()
		_speech_player.stream = null


func _play_speech_clip() -> void:
	if _speech_player == null or _speech_clips.is_empty():
		return
	var path := str(_speech_clips.pop_front())
	_speech_player.stream = _stream(path)
	_speech_player.pitch_scale = 1.0
	_speech_player.volume_db = SPEECH_DB
	_speech_player.play()


func _advance_speech(player: AudioStreamPlayer = null) -> void:
	if player != null and player != _speech_player:
		return      # the faded-out recording of an interrupted line
	if _speech_clips.is_empty():
		_finish_line()
	else:
		_play_speech_clip()


func _on_babble_finished(_id: String) -> void:
	_finish_line()


func _finish_line() -> void:
	if _ann_current.is_empty():
		return
	var id := str(_ann_current["id"])
	var follow: Dictionary = _ann_current.get("follow", {})
	var follow_id := str(_ann_current.get("follow_id", ""))
	var follow_vars: Dictionary = _ann_current.get("vars", {})
	_stop_speech()
	_ann_current = {}
	_ann_last_end = _now()
	if _director:
		_director.note_line_finished(_director.t)
	_log_commentary("finished", {"id": id})
	line_finished.emit(id)
	if follow_id != "" and announcer_mode == "full" and not line(follow_id).is_empty():
		# the answer to this line (Barnaby asks, Kendall answers): spoken right after, never late
		announce(follow_id, follow_vars, {"priority": 45, "ttl": 2.5, "tag": "follow", "turn": true})
	elif not follow.is_empty() and _director != null and announcer_mode == "full":
		var r := follow.duplicate()
		r["ctx"] = (r.get("ctx", {}) as Dictionary)
		r["priority"] = int(CommentaryDirector.CLASS_PRIORITY.get(str(r.get("class", "color")), 15))
		r["after"] = id
		_do_request(r)
	if not _ann_current.is_empty():
		return
	var nxt := _next_queued(_now())
	if not nxt.is_empty():
		_ann_conversation_queue.clear()
		_ann_active_conversation = ""
		_start_line(nxt)
	elif not _ann_conversation_queue.is_empty() and _ann_active_conversation != "":
		var conversation_id := _ann_active_conversation
		get_tree().create_timer(0.45).timeout.connect(_continue_color_conversation.bind(conversation_id), CONNECT_ONE_SHOT)
	elif _ann_queue.is_empty():
		_ann_active_conversation = ""
		_music_lead_mute(false)
		_duck_target["Crowd"] = 0.0


func _continue_color_conversation(conversation_id: String) -> void:
	if _ann_active_conversation != conversation_id or not _ann_current.is_empty():
		return
	if _ann_conversation_queue.is_empty():
		_ann_active_conversation = ""
		_music_lead_mute(false)
		_duck_target["Crowd"] = 0.0
		return
	var next_line: Dictionary = _ann_conversation_queue.pop_front()
	if not announce(str(next_line.get("id", "")), {}, {"turn": true}):
		_ann_conversation_queue.clear()
		_ann_active_conversation = ""


## Picks and speaks a line for a trigger ("ko", "big_hit", ...). ctx keys are matched against each
## line's `when` (string equality, or membership when either side is an Array); among the matching
## lines CommentarySelector prefers specific, fresh lines from fresh joke families. Returns the id or "".
func announce_trigger(trigger: String, ctx := {}, vars := {}) -> String:
	var id := pick_line(trigger, ctx)
	if id == "":
		return ""
	return id if announce(id, vars, {"request": trigger}) else ""


## A director request {trigger, ctx, vars, class, priority, ttl, tag, energy, speaker_pref, follow}.
## Returns the line id spoken or queued ("" when nothing fits or it was dropped).
func _do_request(r: Dictionary) -> String:
	var trigger := str(r.get("trigger", ""))
	# the match's standing facts (venue, officials, scoring, body plans) under the request's own
	var ctx: Dictionary = _booth_ctx.duplicate()
	ctx.merge(r.get("ctx", {}), true)
	var priority := int(r.get("priority", CommentaryDirector.CLASS_PRIORITY.get(str(r.get("class", "low")), 40)))
	if priority >= 100 and str(r.get("tag", "")) in ["result", "final"]:
		invalidate_queued(100)
	elif trigger == "round_start":
		invalidate_queued(100, "round")
	if trigger == "color_conversation":
		var conv := _announce_color_conversation()
		_log_commentary("request", {"trigger": trigger, "class": str(r.get("class", "")), "picked": conv})
		return conv
	var pref := str(r.get("speaker_pref", ""))
	if pref == "" and int(priority) < 50 and _ann_speakers.size() >= 2 and _ann_speakers[-1] == _ann_speakers[-2]:
		pref = "kendall" if _ann_speakers[-1] == "barnaby" else "barnaby"
	var id := pick_line(trigger, ctx, {"speaker_pref": pref, "energy": str(r.get("energy", ""))})
	for fb in REQUEST_FALLBACK.get(trigger, []):
		if id != "":
			break
		id = pick_line(str(fb[0]), (fb[1] as Dictionary).merged(ctx, false), {"speaker_pref": pref})
	_log_commentary("request", {"trigger": trigger, "class": str(r.get("class", "")), "picked": id, "ctx": ctx,
		"score": _selector.last_breakdown.duplicate() if _selector else {}})
	if id == "":
		return ""
	var opts := {"ttl": float(r.get("ttl", default_ttl(priority))), "tag": str(r.get("tag", "")), "priority": priority, "request": trigger}
	if r.has("follow"):
		opts["follow"] = r["follow"]
	return id if announce(id, r.get("vars", {}), opts) else ""


## Low-priority color commentary (tests and the menu path; matches use the director's pacing).
func announce_color_commentary(force_conversation := false) -> String:
	if announcer_mode != "full" or not _ann_current.is_empty() or not _ann_queue.is_empty():
		return ""
	if force_conversation:
		var conversation_line := _announce_color_conversation()
		if conversation_line != "":
			return conversation_line
	var context := _color_context()
	var trigger := "color"
	var roll := _rng.randi_range(0, 99)
	if roll >= 90:
		trigger = "matchup_color"
	elif roll >= 66:
		trigger = "fighter_color"
	var id := pick_line(trigger, context)
	if id == "" and trigger != "color":
		id = pick_line("color", context)
	return id if id != "" and announce(id) else ""


func _announce_color_conversation() -> String:
	_ensure_commentary()
	var candidates: Array = []
	for id in _lines_by_trigger.get("color_conversation_start", []):
		if _history.matches_since(str(id)) > 3:
			candidates.append(id)
	if candidates.is_empty():
		return ""
	candidates.sort()
	var first_id := str(candidates[_rng.randi_range(0, candidates.size() - 1)])
	var first: Dictionary = _lines.get(first_id, {})
	var conversation_id := str(first.get("conversation_id", ""))
	var group: Array = _ann_conversation_groups.get(conversation_id, [])
	if conversation_id == "" or group.size() < 2:
		return ""
	_ann_conversation_queue.clear()
	for i in range(1, group.size()):
		_ann_conversation_queue.append(group[i])
	_ann_active_conversation = conversation_id
	if announce(first_id):
		return first_id
	_ann_conversation_queue.clear()
	_ann_active_conversation = ""
	return ""


func _color_context() -> Dictionary:
	var context := {"creature": [], "element": [], "matchup": []}
	var fighters: Array = _match.get("fighters", [])
	for fighter in fighters:
		var creature_id := str(fighter.get("creature", ""))
		if creature_id == "":
			continue
		if not context["creature"].has(creature_id):
			context["creature"].append(creature_id)
		var definition: Dictionary = Content.creature_entry(creature_id)
		var element := str(definition.get("element", ""))
		if element != "" and not context["element"].has(element):
			context["element"].append(element)
	for i in range(fighters.size()):
		for j in range(i + 1, fighters.size()):
			if int(fighters[i].get("team", -1)) == int(fighters[j].get("team", -1)):
				continue
			var a := str(fighters[i].get("creature", ""))
			var b := str(fighters[j].get("creature", ""))
			if a == "" or b == "":
				continue
			var pair: Array = [a, b]
			pair.sort()
			var matchup := str(pair[0]) + "|" + str(pair[1])
			if not context["matchup"].has(matchup):
				context["matchup"].append(matchup)
	return context


## The best line for a trigger in this context (CommentarySelector), or "". An active line pack
## (Vintage Bellows) answers first for the triggers it covers.
func pick_line(trigger: String, ctx := {}, opts := {}) -> String:
	_ensure_commentary()
	if not _booth_ctx.is_empty():
		var full := _booth_ctx.duplicate()
		full.merge(ctx, true)
		ctx = full
	if announcer_pack != "":
		var pack_ids: Array = (_pack_by_trigger.get(announcer_pack, {}) as Dictionary).get(trigger, [])
		var pid := _selector.pick(pack_ids, _pack_lines, ctx, opts)
		if pid != "":
			return pid
	return _selector.pick(_lines_by_trigger.get(trigger, []), _lines, ctx, opts)


static func _matches(ctx_value, want) -> bool:
	return CommentarySelector.matches(ctx_value, want)


func _log_commentary(kind: String, data: Dictionary) -> void:
	if commentary_event.get_connections().is_empty():
		return
	var d := data.duplicate()
	d["kind"] = kind
	d["now"] = _now()
	d["match_t"] = _director.t if _director else 0.0
	commentary_event.emit(d)


# ---------------------------------------------------------------------------------------
# Crowd and ambience
# ---------------------------------------------------------------------------------------

func crowd_start() -> void:
	if not enabled or not _crowd_players.is_empty():
		return
	for id in ["crowd_murmur", "crowd_excited", "crowd_roar"]:
		var e: Dictionary = _sfx_entries.get(id, {})
		var files: Array = e.get("files", [])
		var p := _make_2d("Crowd")
		p.name = "Crowd_" + id
		if not files.is_empty():
			p.stream = _stream(str(files[0]))
		p.volume_db = -80.0
		_crowd_players.append({"player": p, "gain": float(e.get("gain", 0.0))})
	for c in _crowd_players:
		if (c["player"] as AudioStreamPlayer).stream:
			(c["player"] as AudioStreamPlayer).play()


func crowd_stop(fade := 1.0) -> void:
	for c in _crowd_players:
		var p: AudioStreamPlayer = c["player"]
		var tw := create_tween()
		tw.tween_property(p, "volume_db", -80.0, fade)
		tw.tween_callback(p.queue_free)
	_crowd_players.clear()


## One-shot crowd reaction ("crowd_ooh", "crowd_aww", "crowd_boo", "crowd_gasp", "crowd_laugh", "crowd_cheer", "crowd_can_shower").
func crowd(id: String, vol_db := 0.0) -> int:
	return sfx(id, null, vol_db, 1.0)


func _tick_crowd(dt: float) -> void:
	if _crowd_players.is_empty():
		return
	crowd_heat = clampf(crowd_heat - 0.05 * dt, 0.0, 1.0)
	var h := crowd_heat
	var w := [clampf(1.0 - h * 1.6, 0.0, 1.0), clampf(1.0 - absf(h - 0.5) * 2.2, 0.0, 1.0), clampf((h - 0.45) * 1.9, 0.0, 1.0)]
	for i in 3:
		var c: Dictionary = _crowd_players[i]
		var target := float(c["gain"]) + (linear_to_db(maxf(0.001, float(w[i]))) if float(w[i]) > 0.001 else -80.0)
		var p: AudioStreamPlayer = c["player"]
		p.volume_db = move_toward(p.volume_db, maxf(target, -80.0), 30.0 * dt)


func add_heat(v: float) -> void:
	crowd_heat = clampf(crowd_heat + v, 0.0, 1.0)


## Ambience bed by id ("amb_gullet", "amb_hub_main", ...). "" stops it.
func ambience(id: String, fade := 1.5) -> void:
	if not enabled:
		return
	if id == _ambience_id:
		return
	_ambience_id = id
	# Rapid room changes must not leave older fades writing to a reused player.
	if _ambience_fade:
		_ambience_fade.kill()
	if _ambience_fade_in:
		_ambience_fade_in.kill()
	_ambience_next.stop()
	_ambience_fade = create_tween()
	_ambience_fade.tween_property(_ambience, "volume_db", -80.0, fade)
	_ambience_fade.tween_callback(_ambience.stop)
	var e: Dictionary = _sfx_entries.get(id, {})
	var files: Array = e.get("files", [])
	if id == "" or files.is_empty():
		if id != "":
			_warn_missing(id)
		return
	var s := _stream(str(files[0]))
	if s == null:
		return
	var tmp := _ambience
	_ambience = _ambience_next
	_ambience_next = tmp
	_ambience.stream = s
	_ambience.volume_db = -80.0
	_ambience.play()
	_ambience_fade_in = create_tween()
	_ambience_fade_in.tween_property(_ambience, "volume_db", float(e.get("gain", 0.0)), fade)


## Arena: ambience + crowd reverb character. `base` is the arena's base (gullet/drydock/crusher/
## rooftop, which user layouts keep whatever they are named); without one the id is matched.
func set_arena(arena_id: String, base := "") -> void:
	_arena_id = arena_id
	var key := "gullet"
	if base == "rooftop_canvas":
		key = "rooftop"
	elif base in ["gullet", "drydock", "crusher", "rooftop"]:
		key = base
	else:
		for k in ["drydock", "crusher", "rooftop"]:
			if arena_id.contains(k):
				key = k
	ambience("amb_" + key)
	if not enabled:
		return
	var crowd_bus := AudioServer.get_bus_index("Crowd")
	if crowd_bus < 0 or AudioServer.get_bus_effect_count(crowd_bus) == 0:
		return
	var rv := AudioServer.get_bus_effect(crowd_bus, 0) as AudioEffectReverb
	if rv == null:
		return
	var preset: Array = {"gullet": [0.75, 0.45, 0.3, 40.0], "drydock": [0.4, 0.7, 0.08, 20.0], "crusher": [0.55, 0.5, 0.22, 60.0], "rooftop": [0.2, 0.8, 0.04, 10.0]}[key]
	rv.room_size = float(preset[0])
	rv.damping = float(preset[1])
	rv.wet = float(preset[2])
	rv.predelay_msec = float(preset[3])


## Hub rooms: ambience bed and the diegetic radio filter (brighter in the Juice Bar, bass-heavy at the dock).
func set_room(room: String) -> void:
	var amb := {"main": "amb_hub_main", "juice_bar": "amb_hub_juice_bar", "dock": "amb_hub_dock", "office": "amb_hub_office", "boiler": "amb_hub_boiler", "locker": "amb_hub_locker", "booth": "amb_hub_booth", "med_bay": "amb_hub_locker", "roof": "amb_rooftop"}
	ambience(str(amb.get(room, "amb_hub_main")))
	if not enabled:
		return
	var radio := AudioServer.get_bus_index("Radio")
	if radio < 0 or AudioServer.get_bus_effect_count(radio) < 2:
		return
	var lp := AudioServer.get_bus_effect(radio, 0) as AudioEffectLowPassFilter
	var ls := AudioServer.get_bus_effect(radio, 1) as AudioEffectLowShelfFilter
	var presets := {"juice_bar": [9000.0, 0.0, 0.0], "dock": [3500.0, 5.0, -1.0], "main": [2600.0, 0.0, -3.0]}
	var p: Array = presets.get(room, [1400.0, -2.0, -6.0])
	if lp:
		lp.cutoff_hz = float(p[0])
	if ls:
		ls.gain = float(p[1])
	AudioServer.set_bus_volume_db(radio, float(p[2]))


# ---------------------------------------------------------------------------------------
# Match integration
# ---------------------------------------------------------------------------------------

## ctx: {player_index: int, fighters: [{index, creature, name, team}], arena: String, seed: int,
##       context: "campaign"|"coop"|"versus", round_time: float}
func begin_match(ctx: Dictionary) -> void:
	stop_announcer()  # a menu quip must never block the walk-in line
	_match = ctx.duplicate(true)
	_ann_seed = int(ctx.get("seed", 0))
	_ann_vars = {}
	_ann_speakers.clear()
	_ann_last_end = -100.0
	_ensure_commentary()
	_history.begin_match()
	_selector.seed_match(_ann_seed)
	# the profile's announcer line pack (Vintage Bellows from the Cannery) unless the caller names one
	var pf: Dictionary = Profiles.current if typeof(Profiles.current) == TYPE_DICTIONARY else {}
	set_announcer_pack(str(ctx.get("announcer_pack", pf.get("announcer_pack", ""))))
	var names: Array = []
	var pi := int(ctx.get("player_index", 0))
	for f in ctx.get("fighters", []):
		names.append(str(f.get("name", "")))
		if int(f.get("index", -1)) == pi:
			_ann_vars["p"] = str(f.get("name", "you"))
		elif not _ann_vars.has("o"):
			_ann_vars["o"] = str(f.get("name", "them"))
	_ann_vars["a"] = str(ctx.get("arena_name", ctx.get("arena", "")))
	_match["names"] = names
	_match["state"] = _default_state()
	# the director: enrich the fighters with their element for element/matchup talk
	var dfs: Array = []
	for f in ctx.get("fighters", []):
		var fd: Dictionary = (f as Dictionary).duplicate()
		var entry: Dictionary = Content.creature_entry(str(fd.get("creature", "")))
		fd["element"] = str(entry.get("element", ""))
		fd["plan"] = str(creature_audio(str(fd.get("creature", ""))).get("plan", "biped"))
		fd["height"] = float((entry.get("body", {}) as Dictionary).get("height", 1.0)) if typeof(entry.get("body", {})) == TYPE_DICTIONARY else 1.0
		fd["speed"] = float((entry.get("stats", {}) as Dictionary).get("walk_speed", 3.0)) if typeof(entry.get("stats", {})) == TYPE_DICTIONARY else 3.0
		dfs.append(fd)
	_booth_ctx = booth_context(ctx, dfs)
	_director = CommentaryDirector.new()
	_director.begin({"fighters": dfs, "player_index": pi, "context": str(ctx.get("context", "versus")), "seed": _ann_seed,
		"career": ctx.get("career", {}), "ten_point": bool(ctx.get("ten_point", false)), "referee": bool(ctx.get("referee", false)),
		"rounds": int(ctx.get("rounds", 1))})
	crowd_heat = 0.15
	if enabled:
		crowd_start()
		set_arena(str(ctx.get("arena", "")), str(ctx.get("arena_base", "")))


## The standing facts of a match that lines can be gated on (docs/audio/COMMENTARY.md §5):
## venue (gullet | crusher | drydock | rooftop), outdoor, fence (a cage), open_edges (ring-outs),
## night, hazards, props, referee, scoring (ten_point | hp), context, format, objective,
## special_rules, hands (every fighter has hands), size_gap, quick, rounds_multi.
static func booth_context(ctx: Dictionary, fighters: Array) -> Dictionary:
	var base := str(ctx.get("arena_base", "")).to_lower()
	var aid := str(ctx.get("arena", "")).to_lower()
	var venue := "gullet"
	for v in ["crusher", "drydock", "rooftop"]:
		if base.contains(v) or aid.contains(v):
			venue = v
	var out := {"venue": venue, "outdoor": venue != "gullet", "fence": venue == "gullet", "open_edges": venue == "rooftop",
		"night": venue == "rooftop", "hazards": bool(ctx.get("hazards", venue != "gullet")), "props": bool(ctx.get("props", false)),
		"referee": bool(ctx.get("referee", false)), "scoring": "ten_point" if bool(ctx.get("ten_point", false)) else "hp",
		"context": str(ctx.get("context", "versus")), "format": str(ctx.get("format", "duel")),
		"objective": str(ctx.get("mode", "")) in ["chumball", "spotlight_hog"],
		"special_rules": str(ctx.get("mode", "standard")) not in ["standard", ""] or bool(ctx.get("custom", false)),
		"rounds_multi": int(ctx.get("rounds", 1)) > 1}
	var hands := true
	var lo := INF
	var hi := 0.0
	var quick := false
	for f in fighters:
		if str(f.get("plan", "biped")) != "biped":
			hands = false
		var h := float(f.get("height", 1.0))
		lo = minf(lo, h)
		hi = maxf(hi, h)
		quick = quick or float(f.get("speed", 0.0)) >= 3.8
	out["hands"] = hands and not fighters.is_empty()
	out["size_gap"] = lo < INF and hi > lo * 1.35
	out["quick"] = quick
	return out


## Ends the match audio. `owner_sim`: the simulation of the scene that is leaving. A scene swap
## starts the new scene before the old one is freed, so when another scene has already attached
## its own match (hub -> spar, spar -> hub, a rematch, a resumed campaign fight) that newer match
## keeps its bridge, crowd and announcer; only the leaving scene's own audio is ended.
func end_match(owner_sim: Node = null) -> void:
	if owner_sim != null and _bridge != null and is_instance_valid(_bridge):
		var live = _bridge.get("sim")
		if live != null and is_instance_valid(live) and live != owner_sim:
			return
	crowd_stop(1.5)
	stop_announcer()
	_match = {}
	_director = null
	_booth_ctx = {}
	if _history:
		_history.save_file()
	detach_match()


## One-call integration: reads the simulation's events and state every physics tick. Returns the
## bridge node (child of Audio). detach_match() or end_match() removes it.
func attach_match(sim: Node, player_index: int, ctx := {}) -> Node:
	detach_match()
	var c := ctx.duplicate(true)
	c["player_index"] = player_index
	if not c.has("fighters") and sim.get("fighters") != null:
		var fs: Array = []
		for f in sim.get("fighters"):
			fs.append({"index": f.index, "creature": f.creature.id, "name": f.display_name, "team": f.team})
		c["fighters"] = fs
	if not c.has("arena") and sim.get("arena") != null:
		c["arena"] = str(sim.get("arena").id)
		c["arena_name"] = str(sim.get("arena").display_name)
		c["arena_base"] = str(sim.get("arena").base)
	if not c.has("seed"):
		c["seed"] = int(sim.get("seed_value"))
	var rules = sim.get("rules")
	var arena_nodes = sim.get("arena_nodes")
	if typeof(arena_nodes) == TYPE_DICTIONARY:
		c["props"] = not ((arena_nodes as Dictionary).get("props", []) as Array).is_empty()
	var mode = sim.get("mode")
	if mode != null and mode.has_method("id"):
		c["mode"] = str(mode.call("id"))
	if typeof(rules) == TYPE_DICTIONARY:
		c["format"] = str((rules as Dictionary).get("format", "duel"))
		c["rounds"] = int((rules as Dictionary).get("rounds", 1))
		c["ten_point"] = str((rules as Dictionary).get("scoring", "")) == "ten_point"
		c["referee"] = bool((rules as Dictionary).get("referee", false))
	begin_match(c)
	var bridge := AudioMatchBridge.new()
	bridge.name = "MatchBridge"
	add_child(bridge)
	bridge.attach(sim, player_index)
	_bridge = bridge
	return bridge


func detach_match() -> void:
	if _bridge and is_instance_valid(_bridge):
		_bridge.queue_free()
	_bridge = null


## A two-fighter context without a simulation (showcase / UI previews).
func attach_match_dummy() -> void:
	begin_match({"player_index": 0, "fighters": [{"index": 0, "creature": "f_stoke", "name": "STOKE", "team": 0}, {"index": 1, "creature": "f_dredge", "name": "DREDGE", "team": 1}], "arena": "the_gullet", "arena_name": "The Gullet", "seed": 42})


func match_context() -> Dictionary:
	return _match


func creature_audio(creature_id: String) -> Dictionary:
	var c: Dictionary = bank.get("creatures", {}).get(creature_id, {})
	# roster fighters, minions and bosses all carry their own audio block
	var content_entry := {}
	for kind in Content.CREATURE_KINDS:
		content_entry = Content.get_entry(kind, creature_id)
		if not content_entry.is_empty():
			break
	if content_entry.has("audio") and typeof(content_entry["audio"]) == TYPE_DICTIONARY and not content_entry["audio"].is_empty():
		var merged := c.duplicate()
		for k in content_entry["audio"]:
			merged[k] = content_entry["audio"][k]
		return merged
	if c.is_empty():
		return {"voice": "stoke", "material": "flesh", "plan": "biped", "juice": "juice_generic"}
	return c


func _fighter_creature(i: int) -> String:
	for f in _match.get("fighters", []):
		if int(f.get("index", -1)) == i:
			return str(f.get("creature", ""))
	return ""


func _fighter_name(i: int) -> String:
	for f in _match.get("fighters", []):
		if int(f.get("index", -1)) == i:
			return str(f.get("name", ""))
	return ""


## Display name of a team (its fighters' names joined), for {p} in a decision line.
func _team_name(team: int) -> String:
	var names := PackedStringArray()
	for f in _match.get("fighters", []):
		if int(f.get("team", -99)) == team and str(f.get("name", "")) != "":
			names.append(str(f.get("name", "")))
	return " & ".join(names) if not names.is_empty() else str(_ann_vars.get("p", ""))


func _is_player(i: int) -> bool:
	return i == int(_match.get("player_index", -1))


func _who(attacker: int, target: int) -> Dictionary:
	var d := {}
	if _is_player(attacker):
		d["who"] = "player"
	elif _is_player(target):
		d["who"] = "opponent"
	if _is_player(target):
		d["target"] = "player"
	elif target >= 0:
		d["target"] = "opponent"
	return d


func _voice(i: int, type: String, pos = null) -> void:
	var pal := creature_audio(_fighter_creature(i))
	var vid := "voice_%s_%s" % [str(pal.get("voice", "stoke")), type]
	if not _sfx_entries.has(vid):
		vid = "voice_stoke_" + type
	sfx(vid, pos)


## Maps one simulation event (MatchSim.events entries) to sounds and announcer lines. `info` may
## carry {"pos": Vector3 (fighter position), "health": [fracs], "time": seconds, "round": n}.
## Returns the list of actions taken (ids) so tests can assert the mapping without audio hardware.
func on_sim_event(ev: Dictionary, listener_pos := Vector3.ZERO, info := {}) -> Array:
	var acts: Array = []
	var type := str(ev.get("type", ""))
	var fi := int(ev.get("fighter", -1))
	var pos = ev.get("point", ev.get("pos", info.get("pos", null)))
	if pos != null and not (pos is Vector3):
		pos = null
	var st := _state()
	var play := func(id: String, p = null, vol: float = 0.0, pitch: float = 1.0) -> void:
		sfx(id, p if p != null else pos, vol, pitch)
		acts.append(id)
	match type:
		"hit":
			var ti := int(ev.get("target", -1))
			var dmg := float(ev.get("damage", 0.0))
			var slot := str(ev.get("slot", ""))
			var el := str(ev.get("element", ""))
			var q := float(ev.get("quality", 0.5))
			st["last_attacker"][ti] = fi
			st["last_slot"][ti] = slot
			if bool(ev.get("blocked", false)):
				play.call("hit_guard")
			elif bool(ev.get("parried", false)):
				pass
			elif slot == "pummel":
				play.call("pummel")
			elif slot in ["zone", "reaction", "throw", "slam"]:
				if slot == "throw":
					play.call("hit_heavy", pos, -3.0)
			else:
				var heavy := dmg >= 9.0 or slot in ["heavy", "finisher", "dash_attack"]
				if bool(ev.get("otg", false)):
					play.call("hit_otg")
				else:
					play.call("hit_heavy" if heavy else "hit_light", pos, 0.0, 0.92 + 0.16 * q)
				var mat := str(creature_audio(_fighter_creature(ti)).get("material", "flesh"))
				if mat == "chitin":
					play.call("hit_layer_chitin")
				elif mat == "jelly":
					play.call("hit_layer_jelly")
				if el != "" and _sfx_entries.has("el_hit_" + el):
					play.call("el_hit_" + el)
				if bool(ev.get("counter", false)):
					play.call("counter")
				if dmg > 0.5:
					_voice(ti, "hurt", pos)
					add_heat(dmg / 120.0)
				if dmg >= 10.0:
					crowd("crowd_ooh")
		"glance":
			play.call("glance")
		"parry":
			play.call("parry")
		"knockdown":
			play.call("knockdown")
			_voice(fi, "hurt", pos)
			add_heat(0.12)
			if _is_player(fi):
				crowd("crowd_aww")
			else:
				crowd("crowd_ooh")
		"getup":
			play.call("land_soft")
		"ko", "downed":
			play.call("ko")
			if str(Settings.get_value("access.gore")) == "full":
				play.call("ko_piece", pos, 0.0, 1.0)
				info["gore_full"] = true
			_voice(fi, "ko", pos)
			add_heat(0.4)
			crowd("crowd_cheer")
			if type == "downed":
				# a downed fighter (co-op / bonus modes) is not knocked out: no KO call
				return acts
		"guard_break":
			play.call("guard_break")
			_voice(fi, "hurt", pos)
		"burst":
			play.call("burst")
		"juice":
			play.call("juice_pulse")
			var jid := str(creature_audio(_fighter_creature(fi)).get("juice", "juice_generic"))
			play.call(jid if _sfx_entries.has(jid) else "juice_generic")
			_voice(fi, "juice", pos)
			add_heat(0.3)
			crowd("crowd_cheer")
			if music_track() == "combat_b":
				music_jump("B")
		"juice_end":
			play.call("juice_end")
		"grab":
			play.call("grab")
			_voice(fi, "grunt", pos)
		"grab_tech":
			play.call("hit_guard")
		"grab_escape":
			play.call("whoosh_heavy")
		"throw":
			play.call("throw_release")
			_voice(fi, "grunt", pos)
		"dodge":
			play.call("dodge")
		"taunt":
			play.call("taunt_sting")
			_voice(fi, "taunt", pos)
		"move_start":
			var ms := str(ev.get("slot", ""))
			if ms in ["heavy", "finisher"]:
				play.call("whoosh_heavy")
				_voice(fi, "grunt", pos)
			elif ms in ["l1", "l2", "l3", "dash_attack"]:
				play.call("whoosh_light")
		"ability":
			var aid := str(ev.get("id", ""))
			var cand := "ab_" + aid
			var alias_map := {"ab_stoke_the_fire": "ab_stoke_fire", "ab_bulldoze": "ab_bulldoze_start", "ab_spring_pad": "ab_spring_pad_place", "ab_drain_dive": "blink_down"}
			if alias_map.has(cand):
				cand = str(alias_map[cand])
			play.call(cand if _sfx_entries.has(cand) else "ab_generic")
		"effect":
			var et := str(ev.get("effect", ""))
			var el2 := str(ev.get("element", ""))
			match et:
				"projectile":
					play.call("proj_launch_" + el2 if _sfx_entries.has("proj_launch_" + el2) else "whoosh_light")
				"area":
					play.call("proj_hit_" + el2 if _sfx_entries.has("proj_hit_" + el2) else "whoosh_heavy")
				"zone", "prop":
					if _sfx_entries.has("status_" + _zone_status(el2)):
						play.call("status_" + _zone_status(el2), pos, -4.0)
				"leap":
					play.call("leap")
				"dash":
					play.call("dodge")
				"blink":
					play.call("blink_up")
				"pull", "push":
					play.call("whoosh_heavy")
				"heal":
					play.call("pickup_health")
				"cleanse":
					play.call("react_dilute", pos, -6.0)
				"hype":
					play.call("hype_tick")
				"buff", "shield":
					play.call("taunt_sting", pos, -4.0)
		"status":
			var sid := str(ev.get("status", ""))
			if _sfx_entries.has("status_" + sid):
				play.call("status_" + sid)
		"reaction":
			var rid := str(ev.get("reaction", ""))
			if rid == "stormfront":
				play.call("react_stormfront_mark")
				_timers.append({"at": _now() + 0.6, "id": "react_stormfront_strike", "pos": pos, "vol": 0.0, "pitch": 1.0})
			elif _sfx_entries.has("react_" + rid):
				play.call("react_" + rid)
			add_heat(0.1)
			crowd("crowd_ooh")
		"slam":
			var mat2 := "wall_splat_fence"
			if _arena_id.contains("crusher"):
				mat2 = "wall_splat_steel"
			elif _arena_id.contains("drydock"):
				mat2 = "wall_splat_concrete"
			elif _arena_id.contains("rooftop"):
				mat2 = "wall_splat_railing"
			play.call(mat2)
			add_heat(0.1)
		"ringout":
			play.call("whoosh_heavy")
			crowd("crowd_laugh")
		"reflect":
			play.call("proj_reflect")
		"round_intro":
			st["round"] = int(ev.get("round", 1))
			play.call("ui_round_card", null)
		"round_start":
			play.call("ui_fight", null)
			play.call("ann_bell", null)
			st["round_started_at"] = float(info.get("time", st.get("time", 0.0)))
		"round_end":
			play.call("ann_bell_triple", null)
			crowd("crowd_cheer")
		"timeout":
			play.call("ann_bell", null)
		"round_scored":
			play.call("ui_card_flip", null)
		"judges_decision":
			play.call("ann_sting", null)
		"ref_count":
			play.call("ui_timer_tick", null, -4.0)
		"ref_wave_up":
			crowd("crowd_whistle")
		"ref_stoppage":
			# the referee waves it off: the KO bell (the director's stoppage call invalidates any
			# knockdown call still waiting, so it never follows the T.K.O.)
			play.call("ann_bell_triple", null)
			play.call("ko")
			add_heat(0.4)
			crowd("crowd_cheer")
		"match_end":
			var w := int(ev.get("winner", -1))
			var my_team := -99
			for f in _match.get("fighters", []):
				if _is_player(int(f.get("index", -1))):
					my_team = int(f.get("team", -99))
			if w < 0:
				sting("defeat")
			elif w == my_team:
				sting("victory")
				crowd("crowd_cheer")
				crowd("crowd_can_shower")
			else:
				sting("defeat")
				crowd("crowd_aww")
		"respawn", "revived":
			play.call("blink_up")
		"elimination", "round_reset", "match_start", "effect_end":
			pass
	# the booth (CommentaryDirector): what this event means for the commentary
	if _director == null:
		_director = CommentaryDirector.new()
		_director.begin({"fighters": _match.get("fighters", []), "player_index": int(_match.get("player_index", 0)),
			"context": str(_match.get("context", "versus")), "seed": _ann_seed})
	for r in _director.on_event(ev, info):
		var id := _do_request(r)
		if id != "":
			acts.append("line:" + id)
	_match["state"] = st
	return acts


static func _zone_status(element: String) -> String:
	return str({"scorch": "sizzle", "brine": "soaked", "static": "jolted", "sludge": "gunked", "grit": "caked", "gale": "winded"}.get(element, ""))


func _default_state() -> Dictionary:
	return {"first_hit": false, "knockdowns": 0, "parries": 0, "combo": {}, "last_attacker": {}, "last_slot": {}, "round_started_at": 0.0, "low": {}, "round": 1, "time": 0.0}


## Match bookkeeping used by the event mapper; works even when begin_match() was never called.
func _state() -> Dictionary:
	if not _match.has("state"):
		_match["state"] = _default_state()
	return _match["state"]


## The 4 Hz watchers (called by the bridge, or by NetMatchScene for replicated matches): the
## director's low-health / clock / momentum calls and its paced observations and color in lulls.
## info: optional {edge_fighter} (a fighter standing at the cage or roof edge).
func on_match_tick(health: Array, time_left: float, dt: float, info := {}) -> void:
	var st := _state()
	st["time"] = float(st.get("time", 0.0)) + dt
	_match["state"] = st
	if _director == null:
		return
	for r in _director.on_tick(health, time_left, dt, info):
		_do_request(r)


# ---------------------------------------------------------------------------------------
# Validation (used by the headless tests)
# ---------------------------------------------------------------------------------------

## Checks that every bank id resolves to an imported stream. Returns a list of problems.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if not bank_loaded:
		problems.append("bank not loaded")
		return problems
	for id in _sfx_entries:
		var e: Dictionary = _sfx_entries[id]
		var files: Array = e.get("files", [])
		if files.is_empty():
			problems.append("%s: no files" % id)
		for f in files:
			if not ResourceLoader.exists(str(f)):
				problems.append("%s: missing %s" % [id, f])
			else:
				var s := _stream(str(f))
				if not (s is AudioStreamWAV or s is AudioStreamMP3 or s is AudioStreamOggVorbis):
					problems.append("%s: %s is not a supported audio stream" % [id, f])
				elif bool(e.get("loop", false)):
					if s is AudioStreamWAV and (s as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
						problems.append("%s: WAV loop entry imported without a loop" % id)
					elif s is AudioStreamMP3 and not (s as AudioStreamMP3).loop:
						problems.append("%s: MP3 loop entry is not looping" % id)
					elif s is AudioStreamOggVorbis and not (s as AudioStreamOggVorbis).loop:
						problems.append("%s: Ogg loop entry is not looping" % id)
	for tid in bank.get("music", {}):
		var m: Dictionary = bank["music"][tid]
		var ms = _stream(str(m["file"])) if ResourceLoader.exists(str(m["file"])) else null
		if not (ms is AudioStreamWAV or ms is AudioStreamMP3 or ms is AudioStreamOggVorbis):
			problems.append("music %s: missing or unsupported stream" % tid)
		else:
			var lp = m.get("loop")
			if lp is Dictionary and ms is AudioStreamWAV:
				var w: AudioStreamWAV = ms
				if w.loop_mode != AudioStreamWAV.LOOP_FORWARD or w.loop_begin != int(lp["begin"]) or w.loop_end != int(lp["end"]):
					problems.append("music %s: loop points %d-%d not imported (got mode %d %d-%d)" % [tid, int(lp["begin"]), int(lp["end"]), w.loop_mode, w.loop_begin, w.loop_end])
			elif lp != null and ms is AudioStreamMP3 and not (ms as AudioStreamMP3).loop:
				problems.append("music %s: MP3 loop entry is not looping" % tid)
			elif lp != null and ms is AudioStreamOggVorbis and not (ms as AudioStreamOggVorbis).loop:
				problems.append("music %s: Ogg loop entry is not looping" % tid)
		for L in m.get("layers", []):
			if not ResourceLoader.exists(str(L["file"])):
				problems.append("music %s: layer %s missing" % [tid, L["id"]])
	for sp in bank.get("voices", {}):
		for gid in bank["voices"][sp].get("grains", {}):
			var gp := str(bank["voices"][sp]["grains"][gid])
			var gs = load(gp) if ResourceLoader.exists(gp) else null
			if not (gs is AudioStreamWAV) or (gs as AudioStreamWAV).format != AudioStreamWAV.FORMAT_16_BITS:
				problems.append("voice %s grain %s: must be an imported 16-bit PCM stream" % [sp, gid])
	return problems


# ---------------------------------------------------------------------------------------
# Per-frame
# ---------------------------------------------------------------------------------------

func _process(dt: float) -> void:
	if not enabled:
		# keep the announcer queue moving for subtitles even without audio
		if not _ann_current.is_empty() and _now() >= float(_ann_current["until"]):
			_finish_line()
		_pump_queue()
		return
	_tick_music(dt)
	_tick_crowd(dt)
	# delayed one-shots
	var now := _now()
	var i := 0
	while i < _timers.size():
		var tm: Dictionary = _timers[i]
		if now >= float(tm["at"]):
			sfx(str(tm["id"]), tm.get("pos"), float(tm.get("vol", 0.0)), float(tm.get("pitch", 1.0)))
			_timers.remove_at(i)
		else:
			i += 1
	# voice fades
	for v in _voices2d + _voices3d:
		if v["handle"] > 0 and float(v["fade"]) > 0.0 and _playing(v):
			var p: Node = v["player"]
			var cur := float(p.get("volume_db"))
			var target := float(v["base_db"]) + float(v["fade_target"])
			cur = move_toward(cur, target, float(v["fade"]) * dt)
			p.set("volume_db", cur)
			if cur <= -59.0 and float(v["fade_target"]) <= -59.0:
				_stop_voice(v)
			elif absf(cur - target) < 0.01:
				v["fade"] = 0.0
		elif v["handle"] > 0 and not _playing(v):
			v["handle"] = 0
	# A playing recording owns completion: frame delays between phrase clips must not cut it off.
	var speech_playing := _speech_player != null and _speech_player.playing
	if not speech_playing and not _ann_current.is_empty() and now >= float(_ann_current["until"]) + 0.5:
		_finish_line()
	_pump_queue()
	# ducking: impacts duck movement/zones/creatures briefly; dialogue ducks crowd
	var impact_duck := now < _impact_duck_until
	_duck_target["Movement"] = -3.0 if impact_duck else 0.0
	_duck_target["Zones"] = -4.0 if impact_duck else 0.0
	_duck_target["Creatures"] = -2.0 if impact_duck else 0.0
	for b in _duck:
		var cur_d := float(_duck[b])
		var tgt := float(_duck_target[b])
		var rate := 60.0 if tgt < cur_d else DUCK_RECOVER
		cur_d = move_toward(cur_d, tgt, rate * dt)
		if absf(cur_d - float(_duck[b])) > 0.001:
			_duck[b] = cur_d
			var idx := AudioServer.get_bus_index(b)
			if idx >= 0 and str(b) != "Radio":
				AudioServer.set_bus_volume_db(idx, _bus_base_db(str(b)) + cur_d)


## Starts the best waiting line once the booth is free and its breathing room has passed.
func _pump_queue() -> void:
	if not _ann_current.is_empty() or _ann_queue.is_empty():
		return
	var nxt := _next_queued(_now())
	if not nxt.is_empty():
		_start_line(nxt)
	elif _ann_queue.is_empty() and _ann_active_conversation == "":
		_music_lead_mute(false)
		_duck_target["Crowd"] = 0.0


func _playlist_finished(track: String) -> void:
	if track != music_track() or _jukebox_context == "":
		return
	var next := Jukebox.choose(_jukebox_context, _jukebox_default, track, true)
	var options := _jukebox_opts.duplicate()
	options["jukebox_resolved"] = true
	options["restart"] = true
	music(next, 0.6, options)


## Menus have music and UI cues only. End both sides of any in-progress ambience fade.
func silence_environment() -> void:
	crowd_stop(0.0)
	# A previous end_match may already have removed its fading players from the live list.
	# Stop those too, along with any finishing crowd reaction in the SFX pool.
	for child in get_children():
		if child is AudioStreamPlayer and child.bus == "Crowd":
			child.stop()
	if _ambience_fade:
		_ambience_fade.kill()
	if _ambience_fade_in:
		_ambience_fade_in.kill()
	for player in [_ambience, _ambience_next]:
		if is_instance_valid(player):
			player.stop()
	_ambience_id = ""
