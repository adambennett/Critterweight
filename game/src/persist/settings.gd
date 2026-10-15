extends Node
## Autoload "Settings": every player-facing option is declared once in SCHEMA (type, default,
## range/options, label, help text, restart flag) and persisted through Saves. UI screens are
## generated from the schema, so there are no decorative options: each key has an apply path.
## Display changes support tentative apply + confirm/rollback (UI-04).

signal changed(key: String, value)

const FILE := "settings.json"
const VERSION := 1

## t: bool | int | float | enum | string | dict ; cat: settings tab ; hidden: not shown in menus
const SCHEMA := [
	{"key": "display.window_mode", "cat": "display", "t": "enum", "def": "fullscreen", "opts": ["windowed", "borderless", "fullscreen"], "label": "Window mode", "help": "Windowed, borderless window or exclusive fullscreen.", "rollback": true},
	{"key": "display.resolution", "cat": "display", "t": "enum", "def": "native", "opts_fn": "resolutions", "label": "Resolution", "help": "Window size in windowed mode; output size in fullscreen.", "rollback": true},
	{"key": "display.screen", "cat": "display", "t": "enum", "def": 0, "opts_fn": "screens", "label": "Display", "help": "Which monitor the game uses.", "rollback": true},
	{"key": "display.vsync", "cat": "display", "t": "enum", "def": "on", "opts": ["off", "on", "adaptive"], "label": "VSync", "help": "Synchronize frames to the display to prevent tearing."},
	{"key": "display.frame_limit", "cat": "display", "t": "enum", "def": 0, "opts": [0, 30, 60, 90, 120, 144, 165, 240], "label": "Frame limit", "help": "Maximum frames per second (0 = unlimited)."},
	{"key": "display.render_scale", "cat": "display", "t": "float", "def": 1.0, "min": 0.5, "max": 1.0, "step": 0.05, "label": "Render scale", "help": "3D resolution relative to the window. Lower is faster; the HUD stays sharp."},
	{"key": "display.upscaler", "cat": "display", "t": "enum", "def": "fsr1", "opts": ["bilinear", "fsr1", "fsr2"], "label": "Upscaler", "help": "How a reduced render scale is upscaled."},
	{"key": "display.ui_scale", "cat": "display", "t": "float", "def": 1.0, "min": 0.75, "max": 1.5, "step": 0.05, "label": "UI scale", "help": "Size of menus and HUD."},
	{"key": "display.brightness", "cat": "display", "t": "float", "def": 1.0, "min": 0.6, "max": 1.4, "step": 0.05, "label": "Brightness", "help": "Overall scene brightness."},
	{"key": "graphics.preset", "cat": "graphics", "t": "enum", "def": "high", "opts": ["deck", "low", "medium", "high", "ultra", "custom"], "label": "Quality preset", "help": "Sets the options below. Deck targets 1280x800 at 60 fps."},
	{"key": "graphics.shadows", "cat": "graphics", "t": "enum", "def": 2, "opts": [0, 1, 2, 3], "opt_labels": ["Off", "Low", "Medium", "High"], "label": "Shadows", "help": "Shadow quality and soft-shadow filtering."},
	{"key": "graphics.ao", "cat": "graphics", "t": "enum", "def": 2, "opts": [0, 1, 2], "opt_labels": ["Off", "Low", "High"], "label": "Ambient occlusion", "help": "Screen-space ambient occlusion (contact shading)."},
	{"key": "graphics.effects", "cat": "graphics", "t": "enum", "def": 2, "opts": [0, 1, 2], "opt_labels": ["Low", "Medium", "High"], "label": "Effects", "help": "Particles, glow and fog. Combat cues stay readable on Low."},
	{"key": "graphics.antialiasing", "cat": "graphics", "t": "enum", "def": "msaa2", "opts": ["off", "fxaa", "msaa2", "msaa4", "taa"], "label": "Anti-aliasing", "help": "Edge smoothing."},
	{"key": "graphics.crowd", "cat": "graphics", "t": "enum", "def": 2, "opts": [0, 1, 2], "opt_labels": ["Sparse", "Normal", "Packed"], "label": "Crowd density", "help": "Number of animated spectators."},
	{"key": "audio.master", "cat": "audio", "t": "int", "def": 80, "min": 0, "max": 100, "step": 5, "label": "Master volume", "help": ""},
	{"key": "audio.music", "cat": "audio", "t": "int", "def": 65, "min": 0, "max": 100, "step": 5, "label": "Music", "help": ""},
	{"key": "audio.sfx", "cat": "audio", "t": "int", "def": 85, "min": 0, "max": 100, "step": 5, "label": "Effects", "help": "Impacts, abilities, creatures."},
	{"key": "audio.voice", "cat": "audio", "t": "int", "def": 85, "min": 0, "max": 100, "step": 5, "label": "Announcer & voices", "help": ""},
	{"key": "audio.ui", "cat": "audio", "t": "int", "def": 70, "min": 0, "max": 100, "step": 5, "label": "Interface", "help": ""},
	{"key": "audio.ambience", "cat": "audio", "t": "int", "def": 70, "min": 0, "max": 100, "step": 5, "label": "Crowd & ambience", "help": ""},
	{"key": "audio.mute_in_background", "cat": "audio", "t": "bool", "def": true, "label": "Mute when unfocused", "help": "Silence the game when another window is active."},
	{"key": "audio.device", "cat": "audio", "t": "enum", "def": "Default", "opts_fn": "audio_devices", "label": "Output device", "help": "Audio output device."},
	{"key": "input.deadzone", "cat": "input", "t": "float", "def": 0.2, "min": 0.05, "max": 0.5, "step": 0.01, "label": "Stick dead zone", "help": ""},
	{"key": "input.sensitivity", "cat": "input", "t": "float", "def": 1.0, "min": 0.5, "max": 1.5, "step": 0.05, "label": "Stick sensitivity", "help": ""},
	{"key": "input.invert_camera_x", "cat": "input", "t": "bool", "def": false, "label": "Invert camera nudge", "help": ""},
	{"key": "input.vibration", "cat": "input", "t": "float", "def": 1.0, "min": 0.0, "max": 1.0, "step": 0.1, "label": "Vibration", "help": "Controller rumble strength."},
	{"key": "input.prompts", "cat": "input", "t": "enum", "def": "auto", "opts": ["auto", "xbox", "playstation", "keyboard"], "label": "Button prompts", "help": "Which button names the game shows. Auto follows the last device used."},
	{"key": "input.guard_toggle", "cat": "input", "t": "bool", "def": false, "label": "Guard: toggle instead of hold", "help": "Press once to raise your guard, again to drop it."},
	{"key": "input.bindings", "cat": "input", "t": "dict", "def": {}, "hidden": true, "label": "Bindings", "help": ""},
	{"key": "access.text_scale", "cat": "accessibility", "t": "float", "def": 1.0, "min": 0.8, "max": 1.6, "step": 0.1, "label": "Text size", "help": "Scales menu and HUD text."},
	{"key": "access.subtitles", "cat": "accessibility", "t": "bool", "def": true, "label": "Subtitles", "help": "Show announcer, coach and character lines as text."},
	{"key": "access.subtitle_size", "cat": "accessibility", "t": "enum", "def": "medium", "opts": ["small", "medium", "large", "huge"], "label": "Subtitle size", "help": ""},
	{"key": "access.camera_shake", "cat": "accessibility", "t": "float", "def": 1.0, "min": 0.0, "max": 1.0, "step": 0.1, "label": "Camera shake", "help": "0 disables shake entirely."},
	{"key": "access.reduce_flashing", "cat": "accessibility", "t": "bool", "def": false, "label": "Reduce flashing", "help": "Softens hit flashes, strobes and bright bursts."},
	{"key": "access.reduce_motion", "cat": "accessibility", "t": "bool", "def": false, "label": "Reduce motion", "help": "Calmer camera, no slow-motion, fewer screen-space effects."},
	{"key": "access.gore", "cat": "accessibility", "t": "enum", "def": "full", "opts": ["full", "reduced", "off"], "label": "Cartoon gore", "help": "Full: bruises and a silly detached piece on KO. Reduced: bruises only. Off: neither (text and stars still show every hit and KO)."},
	{"key": "access.target_assist", "cat": "accessibility", "t": "enum", "def": "normal", "opts": ["low", "normal", "high"], "label": "Aim assist", "help": "How strongly attacks snap toward your target."},
	{"key": "access.colorblind", "cat": "accessibility", "t": "enum", "def": "standard", "opts": ["standard", "deuteranopia", "protanopia", "tritanopia"], "label": "Team colours", "help": "Alternative team palettes. Shapes and labels are always shown too."},
	{"key": "access.game_speed", "cat": "accessibility", "t": "float", "def": 1.0, "min": 0.6, "max": 1.0, "step": 0.05, "label": "Game speed (offline)", "help": "Slows offline matches for more reaction time. Runs at reduced speed are marked as custom for records."},
	{"key": "gameplay.difficulty", "cat": "gameplay", "t": "enum", "def": "amateur", "opts": ["sparring", "amateur", "pro", "title_shot"], "label": "Default difficulty", "help": "Starting difficulty for campaigns and quick fights."},
	{"key": "gameplay.tutorial_prompts", "cat": "gameplay", "t": "bool", "def": true, "label": "Control hints", "help": "Show button hints during fights."},
	{"key": "gameplay.pause_on_focus_loss", "cat": "gameplay", "t": "bool", "def": true, "label": "Pause when unfocused", "help": "Offline matches pause when the window loses focus."},
	{"key": "gameplay.announcer", "cat": "gameplay", "t": "enum", "def": "full", "opts": ["full", "reduced", "off"], "label": "Announcer chatter", "help": ""},
	{"key": "gameplay.damage_numbers", "cat": "gameplay", "t": "bool", "def": false, "label": "Damage numbers", "help": "Show floating damage numbers."},
	{"key": "network.player_name", "cat": "network", "t": "string", "def": "Rookie", "max_len": 20, "label": "Player name", "help": "Shown to other players."},
	{"key": "network.port", "cat": "network", "t": "int", "def": 7777, "min": 1024, "max": 65535, "step": 1, "label": "Host port", "help": "UDP port used when you host. Forward it on your router for internet play."},
	{"key": "network.max_players", "cat": "network", "t": "int", "def": 4, "min": 2, "max": 8, "step": 1, "label": "Max players (hosting)", "help": ""},
	{"key": "network.password", "cat": "network", "t": "string", "def": "", "max_len": 32, "label": "Session password", "help": "Players must enter it to join your session. Empty = open."},
	{"key": "network.lan_discovery", "cat": "network", "t": "bool", "def": true, "label": "LAN discovery", "help": "Announce/see sessions on the local network."},
	{"key": "network.interp", "cat": "network", "t": "enum", "def": "auto", "opts": ["auto", "low", "high"], "label": "Network smoothing", "help": "Low = less delay but more jitter on bad connections."},
	{"key": "network.send_rate", "cat": "network", "t": "int", "def": 30, "min": 20, "max": 60, "step": 10, "label": "Update rate (hosting)", "help": "Snapshots per second sent to each player when you host. Lower saves upload; 30 is the tested default. The simulation itself always runs at 120 Hz."},
	{"key": "network.party_relay", "cat": "network", "t": "bool", "def": true, "label": "Co-op relay (hosting)", "help": "Lets players in your session message each other through you (co-op runs). Off: they can only talk to you."},
	{"key": "network.timeout", "cat": "network", "t": "int", "def": 10, "min": 5, "max": 60, "step": 1, "label": "Connection timeout (s)", "help": ""},
	{"key": "diag.show_fps", "cat": "diagnostics", "t": "bool", "def": false, "label": "Show FPS", "help": ""},
	{"key": "diag.show_net", "cat": "diagnostics", "t": "bool", "def": false, "label": "Show network stats", "help": ""},
	{"key": "diag.log_level", "cat": "diagnostics", "t": "enum", "def": "info", "opts": ["debug", "info", "warn", "error"], "label": "Log detail", "help": "Logs are in the user data folder (logs/)."},
]

const PRESETS := {
	"deck": {"graphics.shadows": 1, "graphics.ao": 0, "graphics.effects": 1, "graphics.antialiasing": "fxaa", "graphics.crowd": 0, "display.render_scale": 1.0},
	"low": {"graphics.shadows": 1, "graphics.ao": 0, "graphics.effects": 0, "graphics.antialiasing": "fxaa", "graphics.crowd": 0, "display.render_scale": 0.85},
	"medium": {"graphics.shadows": 2, "graphics.ao": 1, "graphics.effects": 1, "graphics.antialiasing": "msaa2", "graphics.crowd": 1, "display.render_scale": 1.0},
	"high": {"graphics.shadows": 2, "graphics.ao": 2, "graphics.effects": 2, "graphics.antialiasing": "msaa2", "graphics.crowd": 2, "display.render_scale": 1.0},
	"ultra": {"graphics.shadows": 3, "graphics.ao": 2, "graphics.effects": 2, "graphics.antialiasing": "msaa4", "graphics.crowd": 2, "display.render_scale": 1.0},
}

var values := {}
var _schema := {}
var _headless := false
var load_error := ""


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	for s in SCHEMA:
		_schema[s["key"]] = s
		values[s["key"]] = _copy(s["def"])
	load_settings()
	apply_all()
	get_window().focus_entered.connect(_on_focus.bind(true))
	get_window().focus_exited.connect(_on_focus.bind(false))


static func _copy(v):
	return v.duplicate(true) if typeof(v) in [TYPE_DICTIONARY, TYPE_ARRAY] else v


func schema(key: String) -> Dictionary:
	return _schema.get(key, {})


func keys_in(cat: String) -> Array:
	var out := []
	for s in SCHEMA:
		if s["cat"] == cat and not s.get("hidden", false):
			out.append(s["key"])
	return out


func get_value(key: String):
	return values.get(key, _schema.get(key, {}).get("def"))


func options(key: String) -> Array:
	var s: Dictionary = _schema.get(key, {})
	if s.has("opts"):
		return s["opts"]
	match str(s.get("opts_fn", "")):
		"resolutions":
			var out := ["native"]
			for r in ["1280x720", "1280x800", "1366x768", "1600x900", "1920x1080", "2560x1440", "3840x2160"]:
				out.append(r)
			return out
		"screens":
			var n := 1 if _headless else DisplayServer.get_screen_count()
			return range(n)
		"audio_devices":
			return Array(AudioServer.get_output_device_list())
	return []


## Validates and stores a value; returns the value actually stored (clamped/coerced).
func set_value(key: String, v, apply_now := true, persist := true):
	var s: Dictionary = _schema.get(key, {})
	if s.is_empty():
		Log.w("settings", "unknown setting %s" % key)
		return null
	var coerced = _coerce(s, v)
	values[key] = coerced
	if key == "graphics.preset" and PRESETS.has(coerced):
		for k in PRESETS[coerced]:
			values[k] = PRESETS[coerced][k]
			if apply_now:
				apply(k)
			changed.emit(k, values[k])
	elif key.begins_with("graphics.") or key == "display.render_scale":
		if key != "graphics.preset" and values["graphics.preset"] != "custom" and PRESETS.has(values["graphics.preset"]) and PRESETS[values["graphics.preset"]].get(key) != coerced:
			values["graphics.preset"] = "custom"
			changed.emit("graphics.preset", "custom")
	if apply_now:
		apply(key)
	changed.emit(key, coerced)
	if persist:
		save_settings()
	return coerced


func _coerce(s: Dictionary, v):
	match str(s["t"]):
		"bool":
			return bool(v)
		"int":
			return clampi(int(v), int(s.get("min", -2147483648)), int(s.get("max", 2147483647)))
		"float":
			var f := clampf(float(v), float(s.get("min", -1e9)), float(s.get("max", 1e9)))
			if s.has("step"):
				f = snappedf(f, float(s["step"]))
			return f
		"enum":
			var opts := options(s["key"])
			for o in opts:
				if str(o) == str(v):
					return o
			return s["def"] if opts.has(s["def"]) or not s.has("opts") else (opts[0] if not opts.is_empty() else s["def"])
		"string":
			var t := str(v).strip_edges().substr(0, int(s.get("max_len", 64)))
			return t
		"dict":
			return v if typeof(v) == TYPE_DICTIONARY else {}
	return v


func reset(cat := "") -> void:
	for s in SCHEMA:
		if cat == "" or s["cat"] == cat:
			values[s["key"]] = _copy(s["def"])
	if cat == "" or cat == "input":
		values["input.bindings"] = {}
	apply_all()
	for s in SCHEMA:
		if cat == "" or s["cat"] == cat:
			changed.emit(s["key"], values[s["key"]])
	save_settings()


func load_settings() -> void:
	var r := Saves.read_json(Paths.file("profiles", FILE), "settings", VERSION)
	if r["ok"]:
		var d: Dictionary = r["data"]
		for k in d:
			if _schema.has(k):
				values[k] = _coerce(_schema[k], d[k])
	elif r["exists"]:
		load_error = "Settings could not be read (%s). Defaults are in use; the damaged file was kept." % r["error"]
		Log.w("settings", load_error)


func save_settings() -> void:
	var err := Saves.write_json(Paths.file("profiles", FILE), "settings", VERSION, values)
	if err != OK:
		Log.e("settings", "save failed: %s" % error_string(err))


func apply_all() -> void:
	for s in SCHEMA:
		apply(s["key"])


func apply(key: String) -> void:
	var v = values.get(key)
	match key:
		"display.window_mode", "display.resolution", "display.screen":
			_apply_window()
		"display.vsync":
			if not _headless:
				DisplayServer.window_set_vsync_mode({"off": DisplayServer.VSYNC_DISABLED, "on": DisplayServer.VSYNC_ENABLED, "adaptive": DisplayServer.VSYNC_ADAPTIVE}.get(v, DisplayServer.VSYNC_ENABLED))
		"display.frame_limit":
			Engine.max_fps = int(v)
		"display.render_scale", "display.upscaler":
			var vp := get_tree().root
			vp.scaling_3d_scale = float(values["display.render_scale"])
			vp.scaling_3d_mode = {"bilinear": Viewport.SCALING_3D_MODE_BILINEAR, "fsr1": Viewport.SCALING_3D_MODE_FSR, "fsr2": Viewport.SCALING_3D_MODE_FSR2}.get(values["display.upscaler"], Viewport.SCALING_3D_MODE_FSR)
		"display.ui_scale", "access.text_scale":
			get_tree().root.content_scale_factor = float(values["display.ui_scale"]) * lerpf(1.0, float(values["access.text_scale"]), 0.6)
		"graphics.antialiasing":
			var vp2 := get_tree().root
			vp2.msaa_3d = {"msaa2": Viewport.MSAA_2X, "msaa4": Viewport.MSAA_4X}.get(v, Viewport.MSAA_DISABLED)
			vp2.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if v == "fxaa" else Viewport.SCREEN_SPACE_AA_DISABLED
			vp2.use_taa = v == "taa"
		"graphics.shadows":
			var q := int(v)
			RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][q])
			RenderingServer.positional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][q])
			RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096, 8192][q], true)
		"audio.master", "audio.music", "audio.sfx", "audio.voice", "audio.ui", "audio.ambience":
			_apply_bus(key)
		"audio.device":
			if not _headless and AudioServer.get_output_device_list().has(str(v)):
				AudioServer.output_device = str(v)
		"input.deadzone":
			Controls.deadzone = float(v)
		"input.sensitivity":
			Controls.sensitivity = float(v)
		"input.invert_camera_x":
			Controls.invert_camera_x = bool(v)
		"input.vibration":
			Controls.vibration = float(v)
		"input.prompts":
			Controls.prompt_style = str(v)
		"input.guard_toggle":
			Controls.guard_toggle = bool(v)
		"input.bindings":
			var b: Dictionary = v
			# an empty map means "defaults" (fresh install or reset), so re-apply them explicitly
			Controls.apply_bindings(b if not b.is_empty() else Controls.default_bindings())
		"diag.log_level":
			Log.level = ["debug", "info", "warn", "error"].find(str(v))


func _apply_bus(key: String) -> void:
	var bus_name: String = {"audio.master": "Master", "audio.music": "Music", "audio.sfx": "SFX", "audio.voice": "Voice", "audio.ui": "UI", "audio.ambience": "Ambience"}[key]
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var pct := float(values[key]) / 100.0
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(pct, 0.0001)) if pct > 0.0 else -80.0)
	AudioServer.set_bus_mute(idx, pct <= 0.0)


func _apply_window() -> void:
	if _headless:
		return
	# explicit command-line window options (captures, tests, Steam launch options) win over
	# settings. The engine consumes its own --resolution/--windowed flags, so the game also
	# accepts them after "--":  -- --windowed [--size 1600x900]
	var cli := OS.get_cmdline_args()
	var user := OS.get_cmdline_user_args()
	var w := get_window()
	if user.has("--windowed"):
		var sz := Vector2i(1600, 900)
		var at := user.find("--size")
		if at >= 0 and at + 1 < user.size() and "x" in user[at + 1]:
			var parts := user[at + 1].split("x")
			sz = Vector2i(int(parts[0]), int(parts[1]))
		w.mode = Window.MODE_WINDOWED
		w.size = sz
		w.move_to_center()
		return
	if cli.has("--resolution") or cli.has("--windowed") or cli.has("-w") or cli.has("--fullscreen") or cli.has("-f"):
		return
	var screen := clampi(int(values["display.screen"]), 0, DisplayServer.get_screen_count() - 1)
	var mode := str(values["display.window_mode"])
	var res := str(values["display.resolution"])
	if w.current_screen != screen:
		w.current_screen = screen
	match mode:
		"fullscreen":
			w.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		"borderless":
			w.mode = Window.MODE_FULLSCREEN
		_:
			w.mode = Window.MODE_WINDOWED
			var size := DisplayServer.screen_get_size(screen)
			if res != "native" and "x" in res:
				var parts := res.split("x")
				size = Vector2i(int(parts[0]), int(parts[1]))
			else:
				size = Vector2i(int(size.x * 0.8), int(size.y * 0.8))
			w.size = size
			var origin := DisplayServer.screen_get_position(screen)
			var ssize := DisplayServer.screen_get_size(screen)
			w.position = origin + (ssize - size) / 2


## Applies display values tentatively; returns the previous values for revert_display().
func apply_display_tentative(changes: Dictionary) -> Dictionary:
	var prev := {}
	for k in changes:
		prev[k] = values.get(k)
		values[k] = _coerce(_schema[k], changes[k])
	_apply_window()
	return prev


func confirm_display() -> void:
	save_settings()
	for k in ["display.window_mode", "display.resolution", "display.screen"]:
		changed.emit(k, values[k])


func revert_display(prev: Dictionary) -> void:
	for k in prev:
		values[k] = prev[k]
	_apply_window()


func quality() -> Dictionary:
	return {"shadows": int(values["graphics.shadows"]), "ao": int(values["graphics.ao"]), "effects": int(values["graphics.effects"]),
		"brightness": float(values["display.brightness"]), "crowd": int(values["graphics.crowd"])}


func _on_focus(focused: bool) -> void:
	if bool(values.get("audio.mute_in_background", true)):
		var idx := AudioServer.get_bus_index("Master")
		AudioServer.set_bus_mute(idx, not focused or float(values["audio.master"]) <= 0.0)
