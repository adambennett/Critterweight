extends Node
## Autoload "Audio": buses (Master+limiter, Music, SFX, Voice, UI, Ambience plus owned sub-buses
## Impacts/Movement/Zones -> SFX, Creatures/Dialogue -> Voice, Crowd -> Ambience), the sound bank
## (assets/audio/bank.json, built by tools/audio/build.js), pooled 2D/3D players with priorities and
## variation rules, music with crossfades, bar-synced jumps, stingers and intensity/variant layers,
## the announcer/coach queue (babble + subtitles), crowd heat and arena/hub ambience.
## Contract (docs/ARCHITECTURE.md): sfx(id, pos?, vol_db, pitch), music(track, fade), announce(line_id)
## + `subtitle` signal. Integration helpers: attach_match(sim, player_index) / on_sim_event(ev).
## Invariants: headless/server/lab processes never load or play audio (every call is a safe no-op
## except subtitles); a missing id logs once and never crashes; nothing here changes gameplay.

signal subtitle(speaker: String, text: String, seconds: float)
signal line_started(line_id: String)
signal line_finished(line_id: String)

const BANK_PATH := "res://assets/audio/bank.json"
const BUSES := ["Music", "SFX", "Voice", "UI", "Ambience"]
const SUB_BUSES := {"Impacts": ["SFX", 0.0], "Movement": ["SFX", -4.0], "Zones": ["SFX", -8.0], "Creatures": ["Voice", -3.0], "Dialogue": ["Voice", -2.0], "Crowd": ["Ambience", 0.0], "Radio": ["Music", 0.0]}
const POOL_2D := 24
const POOL_3D := 32
const DUCK_RECOVER := 6.0            ## dB per second
const REDUCED_TRIGGERS := ["ko", "round_start", "juice", "win", "draw", "boss_intro", "boss_phase2", "intro", "time"]
const PRIORITY_INTERRUPT := 90
const PRIORITY_QUEUE := 70

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
var _music_duck := 0.0

# announcer
var _lines := {}                      ## id -> line dict
var _lines_by_trigger := {}           ## trigger -> Array of ids
var _babble: Babble
var _ann_current := {}                ## {id, priority, until, speaker}
var _ann_pending := {}                ## one queued line
var _ann_used := {}                   ## ids used in this match
var _ann_rotation := {}               ## trigger -> int
var _ann_seed := 0
var _ann_last_trigger_time := {}      ## reduced mode frequency limiting
var _ann_vars := {}                   ## default {p}/{o} substitutions for the match

# crowd / ambience
var _crowd_players: Array = []        ## 3 loop players
var _ambience: AudioStreamPlayer
var _ambience_next: AudioStreamPlayer
var _ambience_id := ""
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
	var sfx: Dictionary = bank.get("sfx", {})
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
	if not enabled or not bank_loaded:
		return
	var entries: Dictionary = bank.get("music", {})
	if track == "":
		stop_music(fade)
		return
	if not entries.has(track):
		_warn_missing("music:" + track)
		return
	if _music_cur >= 0 and str(_music_slots[_music_cur]["track"]) == track and is_music_playing():
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
		(slot["base"] as Node).queue_free()
		slot["base"] = null
	for lid in slot["layers"]:
		(slot["layers"][lid]["player"] as Node).queue_free()
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
# Announcer and coach
# ---------------------------------------------------------------------------------------

func _load_lines() -> void:
	_lines.clear()
	_lines_by_trigger.clear()
	_pack_lines.clear()
	_pack_by_trigger.clear()
	for id in Content.ids("announcer"):
		var e := Content.get_entry("announcer", id)
		if str(e.get("text", "")) == "":
			continue
		var pk := str(e.get("pack", ""))
		if pk != "":
			_pack_lines[id] = e
			if not _pack_by_trigger.has(pk):
				_pack_by_trigger[pk] = {}
			var pt := str(e.get("trigger", ""))
			if not (_pack_by_trigger[pk] as Dictionary).has(pt):
				_pack_by_trigger[pk][pt] = []
			_pack_by_trigger[pk][pt].append(id)
			continue
		_lines[id] = e
		var trig := str(e.get("trigger", ""))
		if not _lines_by_trigger.has(trig):
			_lines_by_trigger[trig] = []
		_lines_by_trigger[trig].append(id)


## The standard bank's line ids (pack lines: pack_line_ids).
func line_ids() -> Array:
	var out: Array = _lines.keys()
	out.sort()
	return out


func line(id: String) -> Dictionary:
	return _lines.get(id, _pack_lines.get(id, {}))


## Line packs installed (ids), e.g. ["vintage_bellows"].
func line_packs() -> Array:
	var out: Array = _pack_by_trigger.keys()
	out.sort()
	return out


func pack_line_ids(pack: String) -> Array:
	var out: Array = []
	for t in _pack_by_trigger.get(pack, {}):
		out.append_array(_pack_by_trigger[pack][t])
	out.sort()
	return out


## Selects the active line pack ("" or an unknown pack = the standard bank).
func set_announcer_pack(pack: String) -> void:
	announcer_pack = pack if _pack_by_trigger.has(pack) else ""


func _substitute(text: String, vars: Dictionary) -> String:
	var out := text
	var merged := _ann_vars.duplicate()
	for k in vars:
		merged[k] = vars[k]
	for k in merged:
		out = out.replace("{%s}" % k, str(merged[k]))
	return out


## Speaks a line from the bank by id (announcer or coach). Returns false if dropped.
func announce(line_id: String, vars := {}) -> bool:
	var l: Dictionary = _lines.get(line_id, _pack_lines.get(line_id, {}))
	if l.is_empty():
		_warn_missing("line:" + line_id)
		return false
	return _say_line(line_id, str(l.get("speaker", "barnaby")), str(l["text"]), int(l.get("priority", 50)), vars, str(l.get("mood", "")), str(l.get("trigger", "")))


## Speaks arbitrary text (coach prompts, mod lines). Returns false if dropped.
func say(speaker: String, text: String, priority := 50, vars := {}, mood := "") -> bool:
	return _say_line("say:%d" % hash(text), speaker, text, priority, vars, mood, "say")


func stop_announcer() -> void:
	_ann_current = {}
	_ann_pending = {}
	if _babble:
		_babble.stop()
	_music_lead_mute(false)
	_duck_target["Crowd"] = 0.0


func announcer_busy() -> bool:
	return not _ann_current.is_empty()


func _say_line(id: String, speaker: String, text: String, priority: int, vars: Dictionary, mood: String, trigger: String) -> bool:
	if announcer_mode == "off" and speaker == "barnaby":
		return false
	var reduced := announcer_mode == "reduced"
	if reduced and speaker == "barnaby" and trigger != "say" and not REDUCED_TRIGGERS.has(trigger):
		return false
	var now := _now()
	if reduced and trigger != "say":
		if now - float(_ann_last_trigger_time.get(trigger, -100.0)) < 8.0:
			return false
		_ann_last_trigger_time[trigger] = now
	var entry := {"id": id, "speaker": speaker, "text": _substitute(text, vars), "priority": priority, "mood": mood, "vars": vars}
	if not _ann_current.is_empty():
		if priority >= PRIORITY_INTERRUPT and priority >= int(_ann_current["priority"]):
			_start_line(entry)
			return true
		if priority >= PRIORITY_QUEUE:
			if _ann_pending.is_empty() or priority >= int(_ann_pending["priority"]):
				_ann_pending = entry
			return true
		return false
	_start_line(entry)
	return true


func _start_line(entry: Dictionary) -> void:
	var text: String = entry["text"]
	var speaker: String = entry["speaker"]
	var seconds := 0.0
	var reduced := announcer_mode == "reduced"
	if enabled and _babble and _babble.has_voice(speaker):
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
	_ann_current = {"id": entry["id"], "priority": entry["priority"], "until": _now() + seconds + 0.15, "speaker": speaker}
	_ann_used[entry["id"]] = true
	if subtitles_on:
		subtitle.emit(speaker, text, seconds + 0.6)
	line_started.emit(str(entry["id"]))
	_music_lead_mute(true)
	_duck_target["Crowd"] = -3.0


func _on_babble_finished(_id: String) -> void:
	_finish_line()


func _finish_line() -> void:
	if _ann_current.is_empty():
		return
	var id := str(_ann_current["id"])
	_ann_current = {}
	line_finished.emit(id)
	if not _ann_pending.is_empty():
		var nxt := _ann_pending
		_ann_pending = {}
		_start_line(nxt)
	else:
		_music_lead_mute(false)
		_duck_target["Crowd"] = 0.0


## Picks and speaks a line for a trigger ("ko", "big_hit", ...). ctx keys are matched against each
## line's `when` (string equality or membership when the ctx value is an Array); the most specific
## matching lines win, rotate by seed and are not repeated within a match. Returns the id or "".
func announce_trigger(trigger: String, ctx := {}, vars := {}) -> String:
	var id := pick_line(trigger, ctx)
	if id == "":
		return ""
	return id if announce(id, vars) else ""


func pick_line(trigger: String, ctx := {}) -> String:
	if announcer_pack != "":
		var pack_ids: Array = (_pack_by_trigger.get(announcer_pack, {}) as Dictionary).get(trigger, [])
		var pid := _pick_from(pack_ids, _pack_lines, trigger, ctx)
		if pid != "":
			return pid
	return _pick_from(_lines_by_trigger.get(trigger, []), _lines, trigger, ctx)


## The most specific line of `ids` (entries in `table`) matching ctx, rotating through equals.
func _pick_from(ids: Array, table: Dictionary, trigger: String, ctx: Dictionary) -> String:
	if ids.is_empty():
		return ""
	var best: Array = []
	var best_spec := -1
	for id in ids:
		var l: Dictionary = table[id]
		var when: Dictionary = l.get("when", {})
		var ok := true
		for k in when:
			if not ctx.has(k) or not _matches(ctx[k], when[k]):
				ok = false
				break
		if not ok:
			continue
		var spec := when.size()
		if spec > best_spec:
			best_spec = spec
			best = [id]
		elif spec == best_spec:
			best.append(id)
	if best.is_empty():
		return ""
	var fresh: Array = []
	for id in best:
		if not _ann_used.has(id):
			fresh.append(id)
	var pool: Array = fresh if not fresh.is_empty() else best
	pool.sort()
	var rot := int(_ann_rotation.get(trigger, _ann_seed))
	_ann_rotation[trigger] = rot + 1
	return str(pool[posmod(rot, pool.size())])


static func _matches(ctx_value, want) -> bool:
	if typeof(ctx_value) == TYPE_ARRAY:
		for v in ctx_value:
			if _matches(v, want):
				return true
		return false
	var numeric := typeof(want) == TYPE_FLOAT or typeof(want) == TYPE_INT
	if numeric and (typeof(ctx_value) == TYPE_FLOAT or typeof(ctx_value) == TYPE_INT):
		return is_equal_approx(float(ctx_value), float(want))  # JSON numbers parse as floats
	return str(ctx_value) == str(want)


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
	var tw := create_tween()
	tw.tween_property(_ambience, "volume_db", -80.0, fade)
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
	var tw2 := create_tween()
	tw2.tween_property(_ambience, "volume_db", float(e.get("gain", 0.0)), fade)


## Arena: ambience + crowd reverb character. `base` is the arena's base (gullet/drydock/crusher/
## rooftop, which user layouts keep whatever they are named); without one the id is matched.
func set_arena(arena_id: String, base := "") -> void:
	_arena_id = arena_id
	var key := "gullet"
	if base in ["gullet", "drydock", "crusher", "rooftop"]:
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
	_ann_used.clear()
	_ann_rotation.clear()
	_ann_seed = int(ctx.get("seed", 0))
	_ann_vars = {}
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
	crowd_heat = 0.15
	if enabled:
		crowd_start()
		set_arena(str(ctx.get("arena", "")), str(ctx.get("arena_base", "")))


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
	if content_entry.has("audio") and typeof(content_entry["audio"]) == TYPE_DICTIONARY:
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
	var t := float(info.get("time", st.get("time", 0.0)))
	var play := func(id: String, p = null, vol: float = 0.0, pitch: float = 1.0) -> void:
		sfx(id, p if p != null else pos, vol, pitch)
		acts.append(id)
	var say_t := func(trigger: String, ctx: Dictionary = {}) -> void:
		var id := announce_trigger(trigger, ctx)
		if id != "":
			acts.append("line:" + id)
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
				# announcer
				if not bool(st.get("first_hit", false)) and dmg > 0.5:
					st["first_hit"] = true
					var c1 := _who(fi, ti)
					if heavy:
						c1["kind"] = "heavy"
					say_t.call("first_hit", c1)
				elif dmg >= 10.0:
					var kinds: Array = []
					if bool(ev.get("counter", false)):
						kinds.append("counter")
					if dmg >= 15.0:
						kinds.append("big_damage")
					if str(ev.get("move", "")).contains("charged") or slot == "charged":
						kinds.append("charged")
					if float(ev.get("launch", 0.0)) > 0.0:
						kinds.append("launcher")
					var c2 := _who(fi, ti)
					c2["kind"] = kinds
					say_t.call("big_hit", c2)
				# combo counting per attacker
				var combo: Dictionary = st["combo"]
				var cc: Dictionary = combo.get(fi, {"n": 0, "t": -10.0})
				if t - float(cc["t"]) < 1.1 and dmg > 0.5:
					cc["n"] = int(cc["n"]) + 1
				elif dmg > 0.5:
					cc["n"] = 1
				cc["t"] = t
				combo[fi] = cc
				var n := int(cc["n"])
				if slot == "finisher":
					var c3 := _who(fi, ti)
					c3["kind"] = "finisher"
					say_t.call("combo", c3)
				elif n == 3 or n == 4 or n == 6:
					var c4 := _who(fi, ti)
					c4["kind"] = "three" if n == 3 else ("four_plus" if n == 4 else "six_plus")
					say_t.call("combo", c4)
		"glance":
			play.call("glance")
		"parry":
			play.call("parry")
			st["parries"] = int(st.get("parries", 0)) + 1
			var attacker := int(ev.get("attacker", -1))
			var cp := _who(fi, attacker)
			var kinds2: Array = []
			if str(st["last_slot"].get(fi, "")) == "heavy":
				kinds2.append("heavy")
			if int(st["parries"]) == 3:
				kinds2.append("third")
			cp["kind"] = kinds2
			say_t.call("parry", cp)
		"knockdown":
			play.call("knockdown")
			_voice(fi, "hurt", pos)
			st["knockdowns"] = int(st.get("knockdowns", 0)) + 1
			add_heat(0.12)
			var reason := str(ev.get("reason", "hit"))
			var att := int(st["last_attacker"].get(fi, -1))
			var ck := _who(att, fi)
			var kinds3: Array = []
			if reason == "poise":
				kinds3.append("poise")
			elif reason == "throw":
				kinds3.append("throw")
			elif reason == "trip":
				kinds3.append("trip")
			if int(st["knockdowns"]) == 3:
				kinds3.append("third")
			ck["kind"] = kinds3
			say_t.call("knockdown", ck)
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
			_voice(fi, "ko", pos)
			add_heat(0.4)
			crowd("crowd_cheer")
			var att2 := int(st["last_attacker"].get(fi, -1))
			var slot2 := str(st["last_slot"].get(fi, ""))
			var ck2 := _who(att2, fi)
			var kinds4: Array = []
			if slot2 == "heavy" or slot2 == "finisher":
				kinds4.append("heavy")
			elif slot2 == "throw" or slot2 == "slam":
				kinds4.append("throw")
			elif slot2 == "zone" or slot2 == "reaction":
				kinds4.append("zone")
			if str(ev.get("by", "")) == "juice" or bool(info.get("attacker_juiced", false)):
				kinds4.append("juice")
			if t - float(st.get("round_started_at", 0.0)) < 30.0:
				kinds4.append("fast")
			if str(Settings.get_value("access.gore")) == "full":
				kinds4.append("piece")
			ck2["kind"] = kinds4
			if type == "ko":
				say_t.call("ko", ck2)
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
			say_t.call("juice", {"creature": _fighter_creature(fi)})
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
			var ct := {"creature": _fighter_creature(fi)}
			var hp: Array = info.get("health", [])
			if fi >= 0 and fi < hp.size() and float(hp[fi]) < 0.2:
				ct["kind"] = "low"
			say_t.call("taunt", ct)
		"move_start":
			var ms := str(ev.get("slot", ""))
			if ms in ["heavy", "finisher"]:
				play.call("whoosh_heavy")
				_voice(fi, "grunt", pos)
			elif ms in ["l1", "l2", "l3", "dash_attack"]:
				play.call("whoosh_light")
			elif ms == "taunt":
				pass
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
			say_t.call("reaction", {"reaction": rid})
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
			var att3 := int(st["last_attacker"].get(fi, -1))
			var cs := _who(att3, fi)
			cs["kind"] = "wall"
			say_t.call("big_hit", cs)
		"ringout":
			play.call("whoosh_heavy")
			crowd("crowd_laugh")
			var cr := _who(-1, fi)
			if _is_player(fi):
				cr["who"] = "player"
			say_t.call("ringout", cr)
		"reflect":
			play.call("proj_reflect")
		"round_intro":
			var rnd := int(ev.get("round", 1))
			st["round"] = rnd
			play.call("ui_round_card", null)
			if rnd == 1:
				# the opponent gets the walk-in line (one line fits the intro window)
				for f in _match.get("fighters", []):
					if not _is_player(int(f.get("index", -1))):
						var cid := str(f.get("creature", ""))
						if cid.begins_with("b_"):
							say_t.call("boss_intro", {"boss": cid})
						else:
							say_t.call("intro", {"creature": cid})
						break
		"round_start":
			play.call("ui_fight", null)
			play.call("ann_bell", null)
			st["round_started_at"] = t
			st["first_hit"] = false
			var rnd2 := int(ev.get("round", 1))
			var cr2 := {}
			if rnd2 >= 2:
				cr2["round"] = "2plus"
			if bool(info.get("final_round", false)):
				cr2["round"] = "final"
			if str(_match.get("context", "")) == "campaign":
				cr2["context"] = "campaign"
			announce_trigger("round_start", cr2, {"n": rnd2})
			acts.append("line:round_start")
		"round_end":
			play.call("ann_bell_triple", null)
			crowd("crowd_cheer")
		"timeout":
			play.call("ann_bell", null)
			say_t.call("time", {"kind": "decision"})
		"match_end":
			var w := int(ev.get("winner", -1))
			var my_team := -99
			var winner_creature := ""
			for f in _match.get("fighters", []):
				if _is_player(int(f.get("index", -1))):
					my_team = int(f.get("team", -99))
				if int(f.get("team", -98)) == w and winner_creature == "":
					winner_creature = str(f.get("creature", ""))
			if w < 0:
				say_t.call("draw", {})
				sting("defeat")
			elif w == my_team:
				sting("victory")
				crowd("crowd_cheer")
				crowd("crowd_can_shower")
				say_t.call("win", {"creature": winner_creature})
			else:
				sting("defeat")
				crowd("crowd_aww")
				say_t.call("win", {"creature": winner_creature})
		"respawn", "revived":
			play.call("blink_up")
		"elimination":
			pass
		"round_reset", "match_start", "effect_end":
			pass
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


## Low-health / time watchers (called by the bridge or the lead once per second).
func on_match_tick(health: Array, time_left: float, dt: float) -> void:
	var st := _state()
	st["time"] = float(st.get("time", 0.0)) + dt
	var low: Dictionary = st.get("low", {})
	var pi := int(_match.get("player_index", 0))
	var low_count := 0
	for i in health.size():
		var h := float(health[i])
		if h < 0.2 and h > 0.0:
			low_count += 1
		if h < 0.2 and h > 0.0 and not bool(low.get(i, false)):
			low[i] = true
			var ctx := {}
			if i == pi:
				ctx["who"] = "player"
			else:
				ctx["who"] = "opponent"
			if low_count >= 2:
				ctx["who"] = "both"
			if h < 0.1:
				ctx["kind"] = "ten"
			if str(_match.get("context", "")) == "coop":
				ctx["context"] = "coop"
			announce_trigger("low_health", ctx)
		elif h >= 0.3:
			low[i] = false
	st["low"] = low
	if time_left > 0.0 and time_left <= 10.0 and not bool(st.get("ten_warned", false)):
		st["ten_warned"] = true
		announce_trigger("time", {"kind": "ten_seconds"})
		sfx("ui_timer_tick", null)
	elif time_left > 10.0:
		st["ten_warned"] = false
	_match["state"] = st


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
				var s = load(str(f))
				if not (s is AudioStreamWAV):
					problems.append("%s: %s is not an AudioStreamWAV" % [id, f])
				elif bool(e.get("loop", false)) and (s as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
					problems.append("%s: loop entry imported without a loop" % id)
	for tid in bank.get("music", {}):
		var m: Dictionary = bank["music"][tid]
		var ms = load(str(m["file"])) if ResourceLoader.exists(str(m["file"])) else null
		if not (ms is AudioStreamWAV):
			problems.append("music %s: missing stream" % tid)
		else:
			var w: AudioStreamWAV = ms
			var lp = m.get("loop")
			if lp != null:
				if w.loop_mode != AudioStreamWAV.LOOP_FORWARD or w.loop_begin != int(lp["begin"]) or w.loop_end != int(lp["end"]):
					problems.append("music %s: loop points %d-%d not imported (got mode %d %d-%d)" % [tid, int(lp["begin"]), int(lp["end"]), w.loop_mode, w.loop_begin, w.loop_end])
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
	# announcer timeout safety (babble finished signal is the normal path)
	if not _ann_current.is_empty() and now >= float(_ann_current["until"]) + 0.5:
		_finish_line()
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
