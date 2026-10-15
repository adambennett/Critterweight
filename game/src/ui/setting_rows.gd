class_name SettingRows
extends RefCounted
## Builds the widget for any Settings.SCHEMA key and wires it to the Settings autoload:
##  bool -> ToggleRow, enum -> OptionRow, int/float -> SliderRow (or a number field for wide int
##  ranges such as ports), string -> TextFieldRow. Values apply immediately (sliders persist when the
##  user stops adjusting). Keys flagged "rollback" (window mode, resolution, display) go through
##  Settings.apply_display_tentative + a 15 s Keep/Revert countdown. Keys flagged "restart" show a
##  "Restart required" badge and toast. X / Delete on a row restores that option's default.
## Rows refresh themselves when Settings.changed fires (e.g. a quality preset rewrites other keys).

const ROLLBACK_SECONDS := 15.0

## Display strings for enum values (key-specific formatting is in value_label()).
const VALUE_LABELS := {
	"windowed": "Windowed", "borderless": "Borderless window", "fullscreen": "Fullscreen", "native": "Native",
	"off": "Off", "on": "On", "adaptive": "Adaptive", "bilinear": "Bilinear", "fsr1": "AMD FSR 1.0", "fsr2": "AMD FSR 2.2",
	"deck": "Steam Deck", "low": "Low", "medium": "Medium", "high": "High", "ultra": "Ultra", "custom": "Custom",
	"fxaa": "FXAA", "msaa2": "MSAA 2x", "msaa4": "MSAA 4x", "taa": "TAA",
	"auto": "Automatic", "xbox": "Xbox", "playstation": "PlayStation", "keyboard": "Keyboard & mouse",
	"small": "Small", "large": "Large", "huge": "Huge", "full": "Full", "reduced": "Reduced",
	"normal": "Normal", "standard": "Standard", "deuteranopia": "Deuteranopia", "protanopia": "Protanopia",
	"tritanopia": "Tritanopia", "sparring": "Sparring", "amateur": "Amateur", "pro": "Pro", "title_shot": "Title Shot",
	"ask": "Ask every time", "never": "Never", "debug": "Debug (verbose)", "info": "Normal", "warn": "Warnings only",
	"error": "Errors only", "Default": "System default",
}

## Help for schema entries whose "help" is empty.
const FALLBACK_HELP := {
	"audio.master": "Overall loudness of the game.",
	"audio.music": "Menu and fight music.",
	"audio.voice": "Barnaby the announcer, Granny Haymaker and other voices.",
	"audio.ui": "Menu movement, confirm and back sounds.",
	"input.deadzone": "How far a stick must move before it counts. Raise it if your fighter drifts on its own.",
	"input.sensitivity": "How quickly a stick reaches full speed.",
	"input.invert_camera_x": "Reverses the camera nudge (right stick, or Z and C).",
	"access.subtitle_size": "Size of subtitle text during fights and cutscenes.",
	"gameplay.announcer": "How often Barnaby Bellows calls the action.",
	"network.max_players": "Most players allowed in sessions you host (fighters and spectators).",
	"network.timeout": "How long to wait for an unresponsive server before giving up.",
	"diag.show_fps": "Shows frames per second in the corner of the screen.",
	"diag.show_net": "Shows ping, packet loss and bandwidth during online play.",
}

const PERCENT_OF_ONE := ["display.render_scale", "display.ui_scale", "display.brightness", "input.vibration",
	"access.text_scale", "access.camera_shake", "access.game_speed"]


static func label_for(key: String) -> String:
	return str(Settings.schema(key).get("label", key))


static func help_for(key: String) -> String:
	var s := Settings.schema(key)
	var h := str(s.get("help", ""))
	return h if h != "" else str(FALLBACK_HELP.get(key, ""))


static func value_label(key: String, v) -> String:
	var s := Settings.schema(key)
	if s.has("opt_labels"):
		var opts: Array = s.get("opts", [])
		var i := opts.find(v)
		if i < 0:
			for j in opts.size():
				if str(opts[j]) == str(v):
					i = j
		var lbls: Array = s["opt_labels"]
		if i >= 0 and i < lbls.size():
			return str(lbls[i])
	match key:
		"display.frame_limit":
			return "Unlimited" if int(v) == 0 else "%d fps" % int(v)
		"display.screen":
			var idx := int(v)
			if DisplayServer.get_name() != "headless" and idx < DisplayServer.get_screen_count():
				var sz := DisplayServer.screen_get_size(idx)
				return "Display %d  (%d × %d)" % [idx + 1, sz.x, sz.y]
			return "Display %d" % (idx + 1)
		"display.resolution":
			var r := str(v)
			if "x" in r:
				var parts := r.split("x")
				return "%s × %s" % [parts[0], parts[1]]
	var sv := str(v)
	if VALUE_LABELS.has(sv):
		return str(VALUE_LABELS[sv])
	return sv.capitalize()


static func default_label(key: String) -> String:
	var s := Settings.schema(key)
	var d = s.get("def")
	match str(s.get("t", "")):
		"bool":
			return "On" if bool(d) else "Off"
		"int", "float":
			return _number_text(key, float(d))
		"string":
			return "(empty)" if str(d) == "" else str(d)
	return value_label(key, d)


static func _number_text(key: String, v: float) -> String:
	var s := Settings.schema(key)
	if key.begins_with("audio."):
		return "%d%%" % roundi(v)
	if PERCENT_OF_ONE.has(key):
		if key == "access.camera_shake" and is_zero_approx(v):
			return "Off"
		return "%d%%" % roundi(v * 100.0)
	if key == "network.timeout":
		return "%d s" % roundi(v)
	if key == "input.deadzone":
		return "%.2f" % v
	if str(s.get("t", "")) == "int":
		return "%d" % roundi(v)
	return "%.2f" % v


## Builds and wires the row for `key`. `host` (the settings screen) is used for dialogs/toasts.
static func make(key: String) -> UiRow:
	var s := Settings.schema(key)
	var label := label_for(key)
	var t := str(s.get("t", ""))
	var row: UiRow
	var v = Settings.get_value(key)
	match t:
		"bool":
			var tr := ToggleRow.new(label)
			tr.setup(bool(v))
			tr.value_changed.connect(func(nv) -> void: _commit(key, nv, tr))
			row = tr
		"enum":
			var opts := Settings.options(key)
			var lbls: Array[String] = []
			for o in opts:
				lbls.append(value_label(key, o))
			var orow := OptionRow.new(label)
			orow.setup(opts, lbls, v)
			orow.value_changed.connect(func(nv) -> void: _commit(key, nv, orow))
			row = orow
		"int", "float":
			var mn := float(s.get("min", 0.0))
			var mx := float(s.get("max", 1.0))
			var st := float(s.get("step", 1.0 if t == "int" else 0.05))
			if t == "int" and (mx - mn) / maxf(st, 1.0) > 200.0:
				var nf := TextFieldRow.new(label)
				nf.setup(str(int(v)), 5)
				nf.numeric = true
				nf.min_number = int(mn)
				nf.max_number = int(mx)
				nf.value_changed.connect(func(nv) -> void: _commit(key, int(str(nv)), nf))
				row = nf
			else:
				var fmt := SliderRow.Fmt.INT
				if key.begins_with("audio."):
					fmt = SliderRow.Fmt.PERCENT
				elif PERCENT_OF_ONE.has(key):
					fmt = SliderRow.Fmt.PERCENT_OF_ONE
				elif key == "network.timeout":
					fmt = SliderRow.Fmt.SECONDS
				elif t == "float":
					fmt = SliderRow.Fmt.DECIMAL2
				var sr := SliderRow.new(label)
				sr.setup(mn, mx, st, float(v), fmt)
				if key == "access.camera_shake":
					sr.zero_text = "Off"
				if key.begins_with("audio."):
					sr.zero_text = "Muted"
				# apply live while adjusting; persist when the user stops
				sr.value_changed.connect(func(nv) -> void: Settings.set_value(key, int(nv) if t == "int" else nv, true, false))
				sr.committed.connect(func(nv: float) -> void: _commit(key, int(nv) if t == "int" else nv, sr))
				row = sr
		"string":
			var fr := TextFieldRow.new(label)
			fr.setup(str(v), int(s.get("max_len", 32)), key.contains("password"))
			fr.value_changed.connect(func(nv) -> void: _commit(key, nv, fr))
			row = fr
		_:
			row = UiRow.new(label)
	row.key = key
	row.set_help(label, help_for(key), _extra_for(key))
	if bool(s.get("restart", false)):
		row.set_badge("Restart required", "Warning")
	row.on_extra = func() -> void: restore_default(key, row)
	return row


static func _extra_for(key: String) -> String:
	var s := Settings.schema(key)
	var parts: PackedStringArray = PackedStringArray()
	parts.append("Default: %s" % default_label(key))
	if bool(s.get("rollback", false)):
		parts.append("You get %d seconds to keep or revert this change." % int(ROLLBACK_SECONDS))
	if bool(s.get("restart", false)):
		parts.append("Takes effect after restarting the game.")
	parts.append("X / Delete: restore the default.")
	return "\n".join(parts)


## Applies + persists a value chosen in the UI (with display rollback / restart notices).
static func _commit(key: String, v, row: UiRow) -> void:
	var s := Settings.schema(key)
	if bool(s.get("rollback", false)):
		_apply_display(key, v, row)
		return
	var stored = Settings.set_value(key, v)
	refresh_row(row, stored)
	if bool(s.get("restart", false)):
		UiNav.toast("%s changes after a restart." % label_for(key), "info")


static func _apply_display(key: String, v, row: UiRow) -> void:
	var prev := Settings.apply_display_tentative({key: v})
	App.push("dialog", {"title": "Keep these display settings?",
		"body": "%s: %s.\nReverting automatically in {s} seconds." % [label_for(key), value_label(key, Settings.get_value(key))],
		"buttons": [{"label": "Keep", "id": "keep", "default": true}, {"label": "Revert", "id": "revert", "cancel": true}],
		"countdown": ROLLBACK_SECONDS, "timeout_choice": "revert", "kind": "warning",
		"callback": func(id: String) -> void:
			if id == "keep":
				Settings.confirm_display()
				UiNav.toast("Display settings kept.", "success")
			else:
				Settings.revert_display(prev)
				UiNav.toast("Display settings reverted.", "info")
			if is_instance_valid(row):
				refresh_row(row, Settings.get_value(key))})


## X / Delete on a row.
static func restore_default(key: String, row: UiRow) -> void:
	var s := Settings.schema(key)
	var d = Settings.get_value(key) if s.is_empty() else s["def"]
	if str(Settings.get_value(key)) == str(d):
		Audio.sfx("ui_error")
		UiNav.toast("%s is already at its default." % label_for(key), "info", 2.0)
		return
	Audio.sfx("ui_accept")
	_commit(key, d, row)


## Shows `v` in the row without emitting change signals.
static func refresh_row(row: UiRow, v) -> void:
	if not is_instance_valid(row):
		return
	if row is ToggleRow:
		(row as ToggleRow).set_value(bool(v))
	elif row is OptionRow:
		(row as OptionRow).set_value(v)
	elif row is SliderRow:
		(row as SliderRow).set_value(float(v))
	elif row is TextFieldRow:
		(row as TextFieldRow).set_value(str(v))


## Human summary of the current value (tests, help panel).
static func value_text(row: UiRow) -> String:
	if row is ToggleRow:
		return (row as ToggleRow).value_text()
	if row is OptionRow:
		return (row as OptionRow).value_text()
	if row is SliderRow:
		return (row as SliderRow).value_text()
	if row is TextFieldRow:
		return (row as TextFieldRow).value_text()
	return ""
