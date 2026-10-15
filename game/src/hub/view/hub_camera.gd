class_name HubCamera
extends Camera3D
## The hub's follow camera: an elevated 3/4 view that trails your fighter, with per-space pitch
## and distance (HubLayout.SPACES[*].cam; tighter in small rooms), yaw on the right stick / Z,C
## (full turn, kept between spaces), smooth follow, snap after teleports, light trauma shake.
## Walls between the camera and the fighter are dithered away by hub_surface (HubView sets the
## cylinder), so the camera never has to fight the level.

var target := Vector3.ZERO
var yaw := 0.0                 ## 0 = camera south of the target looking north
var pitch_deg := 54.0
var distance := 10.5
var shake_scale := 1.0
var _focus := Vector3.ZERO
var _pitch := 54.0
var _dist := 10.5
var _trauma := 0.0
var _rng := RandomNumberGenerator.new()
var _zoom := 1.0
var _ease_to := INF            ## preferred yaw of the space just entered (eased in once; the stick cancels it)
var _input_yaw := 0.0
## While a board is open your fighter is framed beside it: x = sideways, y = toward the camera, in
## fractions of the camera distance (HubScene sets it from the board's alignment).
var frame_shift := Vector2.ZERO
var _shift := Vector2.ZERO
var _hold_input := false       ## the camera turns itself into a new space while you walk: keep your heading
var pitch_lock := 0.0          ## QA captures (--hub-pitch <deg>): one fixed pitch in every space


func _ready() -> void:
	fov = 48.0
	near = 0.1
	far = 220.0
	current = true


func set_space(space_id: String) -> void:
	var s := HubLayout.space(space_id)
	var cam: Array = s.get("cam", [54.0, 10.5])
	pitch_deg = pitch_lock if pitch_lock > 0.0 else float(cam[0])
	distance = float(cam[1])
	var want := deg_to_rad(float(cam[2]) if cam.size() > 2 else 0.0)
	if absf(wrapf(want - yaw, -PI, PI)) > 0.05:
		_ease_to = want


func add_trauma(t: float) -> void:
	_trauma = clampf(_trauma + t, 0.0, 1.0)


func snap() -> void:
	if _ease_to != INF:
		yaw = _ease_to
		_ease_to = INF
	_focus = target
	_pitch = pitch_deg
	_dist = distance
	_input_yaw = yaw
	_hold_input = false
	_place(0.0)


func _process(dt: float) -> void:
	var axis := Controls.camera_axis()
	if App.top_screen() == null:
		yaw = wrapf(yaw + axis * dt * 2.0, -PI, PI)
		if absf(axis) > 0.01:
			_ease_to = INF
			_hold_input = false
	if _ease_to != INF:
		yaw = lerp_angle(yaw, _ease_to, MathX.damp_factor(0.35, dt))
		if absf(wrapf(_ease_to - yaw, -PI, PI)) < 0.01:
			yaw = _ease_to
			_ease_to = INF
	_focus = _focus.lerp(target, MathX.damp_factor(0.1, dt))
	_shift = _shift.lerp(frame_shift, MathX.damp_factor(0.25, dt))
	_pitch = lerpf(_pitch, pitch_deg, MathX.damp_factor(0.35, dt))
	_dist = lerpf(_dist, distance * _zoom, MathX.damp_factor(0.35, dt))
	_place(dt)


func _place(dt: float) -> void:
	var p := deg_to_rad(_pitch)
	var off := Vector3(sin(yaw) * cos(p), sin(p), cos(yaw) * cos(p)) * _dist
	var look := _focus + Vector3.UP * 0.8
	if _shift != Vector2.ZERO:
		look += (Vector3(cos(yaw), 0.0, -sin(yaw)) * _shift.x + Vector3(sin(yaw), 0.0, cos(yaw)) * _shift.y) * _dist
	var pos := look + off
	_trauma = maxf(0.0, _trauma - dt * 1.6)
	var sh := _trauma * _trauma * shake_scale
	if sh > 0.0:
		pos += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * sh * 0.2
	global_position = pos
	look_at(look, Vector3.UP)


## Ground-plane basis that turns the movement stick into a world direction. While the camera eases
## itself into a new space's view (the Loading Dock looks west) and you keep walking, the old basis
## is held until you let go of the stick, so you keep going where you were going.
func input_basis() -> Basis:
	var walking := Controls.move_vector().length() > 0.2
	if _ease_to != INF and walking:
		_hold_input = true
	elif not walking:
		_hold_input = false
	if not _hold_input:
		_input_yaw = yaw
	return Basis(Vector3.UP, _input_yaw)
