extends Node
## Autoload "Audio": bus layout (Master with limiter, Music, SFX, Voice, UI, Ambience) and the
## playback API used by views/UI. Content and synthesis pipeline: tools/audio (see AUDIO_DIRECTION).
## Contract: sfx(id, pos?, vol_db, pitch), music(track, fade), announce(line_id) -> subtitles signal.

signal subtitle(speaker: String, text: String, seconds: float)

const BUSES := ["Music", "SFX", "Voice", "UI", "Ambience"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	for k in ["audio.master", "audio.music", "audio.sfx", "audio.voice", "audio.ui", "audio.ambience"]:
		Settings.apply(k)


func _ensure_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")
	var master := AudioServer.get_bus_index("Master")
	var has_limiter := false
	for i in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter:
			has_limiter = true
	if not has_limiter:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.5
		AudioServer.add_bus_effect(master, lim)


func sfx(_id: String, _pos = null, _vol_db := 0.0, _pitch := 1.0) -> void:
	pass


func music(_track: String, _fade := 1.0) -> void:
	pass


func announce(_line_id: String, _vars := {}) -> void:
	pass
