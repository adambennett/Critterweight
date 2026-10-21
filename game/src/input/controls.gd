extends Node
## Autoload "Controls": gameplay/UI input actions, default and user bindings, rebinding,
## controller dead zones/sensitivity/vibration, last-used device tracking (for button prompts)
## and conversion of device input into the simulation's FighterInput.
##
## Bindings are persisted by Settings as {action: [event dicts]} (see event_to_dict()).

signal device_changed(kind: String)        ## "keyboard" | "gamepad"
signal bindings_changed()
signal joy_connection(device: int, connected: bool)

const GAME_ACTIONS := ["move_left", "move_right", "move_up", "move_down", "light", "heavy", "guard",
	"dodge", "grab", "ability1", "ability2", "juice", "taunt", "target", "tag", "cam_left", "cam_right",
	"pause", "scoreboard", "interact", "mma_lh", "mma_rh", "mma_ll", "mma_rl", "mma_mod1", "mma_mod2", "mma_mod3", "mma_guard", "mma_dodge", "mma_grab", "mma_stance", "mma_check", "mma_ability1", "mma_ability2", "mma_juice", "mma_target", "mma_taunt", "mma_tag"]
const ACTION_LABELS := {
	"mma_lh": "Cage Rules: Left hand",
	"mma_rh": "Cage Rules: Right hand",
	"mma_ll": "Cage Rules: Left leg",
	"mma_rl": "Cage Rules: Right leg",
	"mma_mod1": "Cage Rules: Hooks / body kicks (hold)",
	"mma_mod2": "Cage Rules: Straights / head kicks (hold)",
	"mma_mod3": "Cage Rules: Overhands / low kicks (hold)",
	"mma_guard": "Cage Rules: Guard",
	"mma_target": "Cage Rules: Switch target",
	"mma_taunt": "Cage Rules: Touch gloves / cheer",
	"mma_tag": "Cage Rules: Tag partner",
	"mma_dodge": "Cage Rules: Slip / dash",
	"mma_grab": "Cage Rules: Takedown / throw",
	"mma_stance": "Cage Rules: Switch stance",
	"mma_check": "Cage Rules: Check low kicks (hold)",
	"mma_ability1": "Cage Rules: Cut the Angle",
	"mma_ability2": "Cage Rules: Second Wind",
	"mma_juice": "Cage Rules: Championship Rounds",

	"move_left": "Move left", "move_right": "Move right", "move_up": "Move forward", "move_down": "Move back",
	# v0.9.18: the four move inputs carry the equipped moves in Movesets (the default) and the
	# Classic actions in Classic (docs/design/MOVESET_COMBAT.md §2.1)
	"light": "Move 1 (Light in Classic)", "heavy": "Move 2 (Heavy in Classic)", "guard": "Guard (tap to parry)",
	"dodge": "Dodge", "grab": "Grapple (Grab in Classic)", "ability1": "Move 3 (Ability 1 in Classic)", "ability2": "Move 4 (Ability 2 in Classic)",
	"juice": "Ultimate (JUICE)", "taunt": "Taunt / cheer", "target": "Switch target", "tag": "Tag partner", "cam_left": "Camera left",
	"cam_right": "Camera right", "pause": "Pause menu", "scoreboard": "Scoreboard", "interact": "Interact",
}
## The Classic names of the actions whose label follows the combat style (Classic matches, the
## Classic half of the Controls reference).
const CLASSIC_LABELS := {"light": "Light attack", "heavy": "Heavy attack (hold to charge)", "grab": "Grab / throw",
	"ability1": "Ability 1", "ability2": "Ability 2", "juice": "JUICE (ultimate)"}
## What the style-dependent actions do in each style (Controls reference and rebinding help).
const ACTION_HELP := {
	"light": "Movesets: the move in slot 1 of your loadout (the basic strike in every recommended loadout). Classic: Light attack; press again to chain.",
	"heavy": "Movesets: the move in slot 2 of your loadout; hold it if the move charges or keeps going. Classic: Heavy attack, hold to charge; Light, Light, Heavy is the finisher.",
	"ability1": "Movesets: the move in slot 3 of your loadout. Classic: your fighter's first ability.",
	"ability2": "Movesets: the move in slot 4 of your loadout. Classic: your fighter's second ability.",
	"grab": "Grapple beats guard and counters: grab, then push a direction and press again to throw. Also picks up the ball, revives and interacts. (Grab in Classic.)",
	"juice": "Your fighter's Ultimate, its JUICE: press at full Hype.",
	"guard": "Hold to block the front; tap just as a hit lands to parry.",
}
## Actions that are held (vs pressed) for the hold/toggle accessibility option.
const TOGGLEABLE := ["guard"]

var last_device := "keyboard"
var deadzone := 0.2
var sensitivity := 1.0
var invert_camera_x := false
var vibration := 1.0
var guard_toggle := false
var prompt_style := "auto"          ## auto | xbox | playstation | keyboard
var _guard_toggled := false
var _mma_view_used := false
var _defaults := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_defaults = _default_bindings()
	apply_bindings(_defaults)
	Input.joy_connection_changed.connect(_on_joy_connection)


func _default_bindings() -> Dictionary:
	return {
		"move_left": [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)],
		"move_right": [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)],
		"move_up": [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)],
		"move_down": [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)],
		"mma_lh": [_key(KEY_U), _joy(JOY_BUTTON_X)],
		"mma_rh": [_key(KEY_I), _joy(JOY_BUTTON_Y)],
		"mma_ll": [_key(KEY_J), _joy(JOY_BUTTON_A)],
		"mma_rl": [_key(KEY_K), _joy(JOY_BUTTON_B)],
		"mma_mod1": [_key(KEY_Q), _joy(JOY_BUTTON_LEFT_SHOULDER)],
		"mma_mod2": [_key(KEY_E), _joy(JOY_BUTTON_RIGHT_SHOULDER)],
		"mma_mod3": [_key(KEY_R), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)],
		"mma_guard": [_key(KEY_L), _key(KEY_SEMICOLON), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)],
		"mma_dodge": [_key(KEY_SHIFT), _joy(JOY_BUTTON_RIGHT_STICK)],
		"mma_grab": [_key(KEY_SPACE), _joy(JOY_BUTTON_LEFT_STICK)],
		"mma_stance": [_key(KEY_X), _joy(JOY_BUTTON_DPAD_LEFT)],
		"mma_check": [_key(KEY_O), _joy(JOY_BUTTON_DPAD_DOWN)],
		"mma_ability1": [_key(KEY_F1), _joy(JOY_BUTTON_DPAD_UP)],
		"mma_ability2": [_key(KEY_F2), _joy(JOY_BUTTON_DPAD_RIGHT)],
		"mma_juice": [_key(KEY_V), _joy(JOY_BUTTON_BACK)],
		"mma_target": [_key(KEY_TAB)],
		"mma_taunt": [_key(KEY_T)],
		"mma_tag": [_key(KEY_G)],
		"light": [_key(KEY_J), _mouse(MOUSE_BUTTON_LEFT), _joy(JOY_BUTTON_X)],
		"heavy": [_key(KEY_K), _mouse(MOUSE_BUTTON_RIGHT), _joy(JOY_BUTTON_Y)],
		"guard": [_key(KEY_SHIFT), _key(KEY_L), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)],
		"dodge": [_key(KEY_SPACE), _joy(JOY_BUTTON_A)],
		"grab": [_key(KEY_F), _mouse(MOUSE_BUTTON_MIDDLE), _joy(JOY_BUTTON_B)],
		"ability1": [_key(KEY_Q), _joy(JOY_BUTTON_LEFT_SHOULDER)],
		"ability2": [_key(KEY_E), _joy(JOY_BUTTON_RIGHT_SHOULDER)],
		"juice": [_key(KEY_R), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)],
		"taunt": [_key(KEY_T), _joy(JOY_BUTTON_DPAD_UP)],
		"target": [_key(KEY_TAB), _joy(JOY_BUTTON_RIGHT_STICK)],
		"tag": [_key(KEY_G), _joy(JOY_BUTTON_DPAD_DOWN)],
		"cam_left": [_key(KEY_Z), _axis(JOY_AXIS_RIGHT_X, -1.0)],
		"cam_right": [_key(KEY_C), _axis(JOY_AXIS_RIGHT_X, 1.0)],
		"pause": [_key(KEY_ESCAPE), _joy(JOY_BUTTON_START)],
		"scoreboard": [_key(KEY_BACKSLASH), _joy(JOY_BUTTON_BACK)],
		"interact": [_key(KEY_ENTER), _joy(JOY_BUTTON_A)],
	}


static func _key(code: int) -> Dictionary:
	return {"type": "key", "code": code}


static func _mouse(b: int) -> Dictionary:
	return {"type": "mouse", "button": b}


static func _joy(b: int) -> Dictionary:
	return {"type": "joy_button", "button": b}


static func _axis(a: int, dir: float) -> Dictionary:
	return {"type": "joy_axis", "axis": a, "dir": dir}


static func dict_to_event(d: Dictionary) -> InputEvent:
	match str(d.get("type", "")):
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(d.get("code", 0))
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = int(d.get("button", 1))
			return m
		"joy_button":
			var j := InputEventJoypadButton.new()
			j.button_index = int(d.get("button", 0))
			j.device = -1
			return j
		"joy_axis":
			var a := InputEventJoypadMotion.new()
			a.axis = int(d.get("axis", 0))
			a.axis_value = float(d.get("dir", 1.0))
			a.device = -1
			return a
	return null


static func event_to_dict(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		var code := (ev as InputEventKey).physical_keycode
		if code == 0:
			code = (ev as InputEventKey).keycode
		return _key(code)
	if ev is InputEventMouseButton:
		return _mouse((ev as InputEventMouseButton).button_index)
	if ev is InputEventJoypadButton:
		return _joy((ev as InputEventJoypadButton).button_index)
	if ev is InputEventJoypadMotion:
		var jm := ev as InputEventJoypadMotion
		return _axis(jm.axis, signf(jm.axis_value))
	return {}


func current_bindings() -> Dictionary:
	var out := {}
	for a in GAME_ACTIONS:
		var arr := []
		for ev in InputMap.action_get_events(a):
			var d := event_to_dict(ev)
			if not d.is_empty():
				arr.append(d)
		out[a] = arr
	return out


func default_bindings() -> Dictionary:
	return _defaults.duplicate(true)


func apply_bindings(b: Dictionary) -> void:
	for a in GAME_ACTIONS:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.25)
		InputMap.action_erase_events(a)
		var list: Array = b.get(a, _defaults.get(a, []))
		for d in list:
			var ev := dict_to_event(d)
			if ev:
				InputMap.action_add_event(a, ev)
	# Controller navigation for every UI (Godot's ui_* defaults cover D-pad; add stick + A/B).
	_ensure_ui(&"ui_accept", [_joy(JOY_BUTTON_A)])
	_ensure_ui(&"ui_cancel", [_joy(JOY_BUTTON_B)])
	_ensure_ui(&"ui_left", [_axis(JOY_AXIS_LEFT_X, -1.0)])
	_ensure_ui(&"ui_right", [_axis(JOY_AXIS_LEFT_X, 1.0)])
	_ensure_ui(&"ui_up", [_axis(JOY_AXIS_LEFT_Y, -1.0)])
	_ensure_ui(&"ui_down", [_axis(JOY_AXIS_LEFT_Y, 1.0)])
	bindings_changed.emit()


func _ensure_ui(action: StringName, extra: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for d in extra:
		var ev := dict_to_event(d)
		var found := false
		for existing in InputMap.action_get_events(action):
			if existing.is_match(ev, true):
				found = true
		if not found:
			InputMap.action_add_event(action, ev)


## Replaces the binding of `action` for the device class of `ev`, removing that event from any
## other gameplay action (so one key cannot trigger two actions). Returns the action it was
## taken from ("" if none).
func rebind(action: String, ev: InputEvent) -> String:
	var stolen := ""
	var is_pad := ev is InputEventJoypadButton or ev is InputEventJoypadMotion
	for a in GAME_ACTIONS:
		if a.begins_with("mma_") != action.begins_with("mma_"):
			continue
		for existing in InputMap.action_get_events(a):
			if existing.is_match(ev, true) or (ev is InputEventJoypadMotion and existing is InputEventJoypadMotion and existing.axis == ev.axis and signf(existing.axis_value) == signf(ev.axis_value)):
				InputMap.action_erase_event(a, existing)
				if a != action:
					stolen = a
	for existing in InputMap.action_get_events(action):
		var pad := existing is InputEventJoypadButton or existing is InputEventJoypadMotion
		if pad == is_pad:
			InputMap.action_erase_event(action, existing)
			break
	var clean := dict_to_event(event_to_dict(ev))
	if clean:
		InputMap.action_add_event(action, clean)
	bindings_changed.emit()
	return stolen


func _input(event: InputEvent) -> void:
	var kind := last_device
	if event is InputEventKey or event is InputEventMouseButton:
		kind = "keyboard"
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length() > 3.0:
			kind = "keyboard"
	elif event is InputEventJoypadButton:
		kind = "gamepad"
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		kind = "gamepad"
	if kind != last_device:
		last_device = kind
		device_changed.emit(kind)


func _on_joy_connection(device: int, connected: bool) -> void:
	joy_connection.emit(device, connected)
	if not connected and Input.get_connected_joypads().is_empty() and last_device == "gamepad":
		last_device = "keyboard"
		device_changed.emit("keyboard")


## Raw movement stick (screen space: x right, y up), with radial dead zone and sensitivity.
func move_vector() -> Vector2:
	var v := Vector2(
		Input.get_action_raw_strength("move_right") - Input.get_action_raw_strength("move_left"),
		Input.get_action_raw_strength("move_up") - Input.get_action_raw_strength("move_down"))
	var l := v.length()
	if l < deadzone:
		return Vector2.ZERO
	var scaled := (l - deadzone) / (1.0 - deadzone)
	return v / l * clampf(scaled * sensitivity, 0.0, 1.0)


func camera_axis() -> float:
	var v := Input.get_action_raw_strength("cam_right") - Input.get_action_raw_strength("cam_left")
	if absf(v) < deadzone:
		return 0.0
	return -v if invert_camera_x else v


## Fills a FighterInput from the devices. `cam_basis` turns the stick into a world direction.
func fill(fi: FighterInput, cam_basis: Basis, creature: CreatureDef = null, toward := Vector3.ZERO) -> void:
	if creature and creature.tags.has("martial"):
		fill_martial(fi, cam_basis, toward)
		return
	# Clear guest-only held state when switching a seat or tagging to a normal fighter.
	_mma_view_used = false
	fi.held &= (1 << FighterInput.MMA_LL) - 1
	var mv := move_vector()
	var fwd := -cam_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.FORWARD
	var right := cam_basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 1e-6 else Vector3.RIGHT
	fi.move = fwd * mv.y + right * mv.x
	var map := {"light": FighterInput.LIGHT, "heavy": FighterInput.HEAVY, "guard": FighterInput.GUARD,
		"dodge": FighterInput.DODGE, "grab": FighterInput.GRAB, "ability1": FighterInput.AB1,
		"ability2": FighterInput.AB2, "juice": FighterInput.JUICE, "taunt": FighterInput.TAUNT,
		"target": FighterInput.TARGET, "tag": FighterInput.TAG}
	for a in map:
		var b: int = map[a]
		if Input.is_action_just_pressed(a):
			fi.press(b)
			if a == "guard" and guard_toggle:
				_guard_toggled = not _guard_toggled
		var held := Input.is_action_pressed(a)
		if a == "guard" and guard_toggle:
			held = _guard_toggled
		fi.set_held(b, held)


func rumble(weak: float, strong: float, duration: float) -> void:
	if vibration <= 0.0:
		return
	for d in Input.get_connected_joypads():
		Input.start_joy_vibration(d, clampf(weak * vibration, 0.0, 1.0), clampf(strong * vibration, 0.0, 1.0), duration)


## Short human label for the first binding of an action on the current device class.
func prompt_for(action: String) -> String:
	var want_pad := last_device == "gamepad" if prompt_style == "auto" else prompt_style != "keyboard"
	for ev in InputMap.action_get_events(action):
		var pad := ev is InputEventJoypadButton or ev is InputEventJoypadMotion
		if pad == want_pad:
			return event_label(ev)
	var evs := InputMap.action_get_events(action)
	return event_label(evs[0]) if not evs.is_empty() else "?"


func event_label(ev: InputEvent) -> String:
	var ps := prompt_style == "playstation"
	if ev is InputEventKey:
		var code := (ev as InputEventKey).physical_keycode
		return OS.get_keycode_string(code if code != 0 else (ev as InputEventKey).keycode)
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return "LMB"
			MOUSE_BUTTON_RIGHT: return "RMB"
			MOUSE_BUTTON_MIDDLE: return "MMB"
		return "Mouse%d" % (ev as InputEventMouseButton).button_index
	if ev is InputEventJoypadButton:
		var names_x := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
			JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_BACK: "View",
			JOY_BUTTON_START: "Menu", JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS",
			JOY_BUTTON_DPAD_UP: "D-Up", JOY_BUTTON_DPAD_DOWN: "D-Down", JOY_BUTTON_DPAD_LEFT: "D-Left", JOY_BUTTON_DPAD_RIGHT: "D-Right"}
		var names_p := {JOY_BUTTON_A: "Cross", JOY_BUTTON_B: "Circle", JOY_BUTTON_X: "Square", JOY_BUTTON_Y: "Triangle",
			JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1", JOY_BUTTON_BACK: "Share", JOY_BUTTON_START: "Options",
			JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3"}
		var bi := (ev as InputEventJoypadButton).button_index
		if ps and names_p.has(bi):
			return names_p[bi]
		return names_x.get(bi, "Btn%d" % bi)
	if ev is InputEventJoypadMotion:
		var jm := ev as InputEventJoypadMotion
		match jm.axis:
			JOY_AXIS_TRIGGER_LEFT: return "L2" if ps else "LT"
			JOY_AXIS_TRIGGER_RIGHT: return "R2" if ps else "RT"
			JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y: return "Left Stick"
			JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y: return "Right Stick"
	return "?"

func fill_martial(fi: FighterInput, cam_basis: Basis, toward: Vector3) -> void:
	var mv := move_vector()
	var forward := toward
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = -cam_basis.z
		forward.y = 0.0
	forward = forward.normalized()
	fi.move = forward * mv.y + forward.cross(Vector3.UP) * mv.x
	fi.held = 0
	# View is a release-to-JUICE modifier: chords never also activate the ultimate.
	var chords := {"mma_check": FighterInput.TAG, "mma_stance": FighterInput.TARGET, "mma_ability1": FighterInput.TAUNT}
	var chord_active := {}
	if Input.is_action_pressed("mma_juice"):
		if Input.is_action_pressed("mma_guard"):
			chord_active["mma_guard"] = true
			_mma_view_used = true  # reserved for the Cannery return chord
		for action: String in chords:
			if Input.is_action_pressed(action):
				chord_active[action] = true
				_mma_view_used = true
				if Input.is_action_just_pressed(action) or Input.is_action_just_pressed("mma_juice"):
					fi.press(chords[action])
	for a in MartialControls.MAP:
		var b: int = MartialControls.MAP[a]
		if a == "mma_juice":
			if Input.is_action_just_released(a) and not Input.is_action_pressed(a):
				if not _mma_view_used:
					fi.press(b)
				_mma_view_used = false
			continue
		if chord_active.has(a):
			continue
		if Input.is_action_just_pressed(a):
			fi.press(b)
			if a == "mma_guard" and guard_toggle:
				_guard_toggled = not _guard_toggled
		fi.set_held(b, _guard_toggled if a == "mma_guard" and guard_toggle else Input.is_action_pressed(a))
