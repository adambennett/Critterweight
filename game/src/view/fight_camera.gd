class_name FightCamera
extends Camera3D
## Broadcast-style fight camera. Frames every active fighter from an elevated 3/4 side view,
## prefers the side perpendicular to the player's engagement line (never flips abruptly),
## accepts a manual yaw nudge (right stick / Z,C), and applies trauma-based shake scaled by the
## accessibility "camera shake" setting. Modes: fight, follow (hub), spectate (auto director),
## free (spectator free cam).

enum Mode { FIGHT, FOLLOW, SPECTATE, FREE }

var mode := Mode.FIGHT
var points_provider: Callable          ## () -> Array[Vector3] of interesting positions
var focus_provider: Callable           ## () -> [Vector3 focus, Vector3 target or null]
var yaw := 0.0
var manual_yaw := 0.0
var dist := 7.0
var height := 3.2
var center := Vector3.ZERO
var shake_scale := 1.0
var _trauma := 0.0
var _rng := RandomNumberGenerator.new()
var arena_radius := 5.0
var free_pos := Vector3(0, 4, 9)
var free_yaw := 0.0
var free_pitch := -0.3


func _ready() -> void:
	fov = 50.0
	near = 0.05
	far = 200.0
	current = true


func add_trauma(t: float) -> void:
	_trauma = clampf(_trauma + t, 0.0, 1.0)


func snap() -> void:
	_update(1.0, true)


func _process(dt: float) -> void:
	_update(dt, false)


func _update(dt: float, instant: bool) -> void:
	if mode == Mode.FREE:
		_free_cam(dt)
		return
	var pts: Array = points_provider.call() if points_provider.is_valid() else []
	if pts.is_empty():
		return
	var c := Vector3.ZERO
	for p: Vector3 in pts:
		c += p
	c /= pts.size()
	var spread := 0.0
	for p: Vector3 in pts:
		spread = maxf(spread, Vector2(p.x - c.x, p.z - c.z).length())
	var desired_yaw := yaw
	if focus_provider.is_valid():
		var fp: Array = focus_provider.call()
		if fp.size() >= 2 and fp[1] != null:
			var line: Vector3 = fp[1] - fp[0]
			line.y = 0.0
			if line.length() > 0.3:
				var perp := atan2(line.z, -line.x)
				var alt := MathX.wrap_angle(perp + PI)
				desired_yaw = perp if absf(MathX.wrap_angle(perp - yaw)) < absf(MathX.wrap_angle(alt - yaw)) else alt
		if mode == Mode.FOLLOW and fp.size() >= 1:
			c = fp[0]
			spread = 0.0
	var input_yaw := 0.0
	if mode != Mode.SPECTATE:
		input_yaw = Controls.camera_axis()
	manual_yaw = clampf(manual_yaw + input_yaw * dt * 2.2, -1.2, 1.2) if mode == Mode.FIGHT else manual_yaw + input_yaw * dt * 2.2
	if absf(input_yaw) < 0.01 and mode == Mode.FIGHT:
		manual_yaw = move_toward(manual_yaw, 0.0, dt * 0.4)
	var k := 1.0 if instant else MathX.damp_factor(0.6, dt)
	yaw = lerp_angle(yaw, desired_yaw, k * (0.6 if mode == Mode.FIGHT else 1.0))
	var want_dist := clampf(4.8 + spread * 1.35, 5.2, 14.0)
	if mode == Mode.FOLLOW:
		want_dist = 5.5
	var kd := 1.0 if instant else MathX.damp_factor(0.35, dt)
	dist = lerpf(dist, want_dist, kd)
	# a crowd (5+ fighters) gets a steeper, more top-down angle: from the low duel angle the near cage rail
	# and posts cut across the fighters in front, and the plate rows cover the bottom of the screen
	var crowd := clampf((float(pts.size()) - 3.0) / 4.0, 0.0, 1.0) if mode == Mode.FIGHT else 0.0
	height = lerpf(height, 1.8 + dist * (0.3 + 0.16 * crowd), kd)
	center = center.lerp(c, 1.0 if instant else MathX.damp_factor(0.12, dt))
	var cam_yaw := yaw + manual_yaw
	var offset := Vector3(sin(cam_yaw), 0.0, cos(cam_yaw)) * dist + Vector3.UP * height
	var look := center + Vector3.UP * 0.9
	var pos := center + offset
	# keep the camera out of the far crowd geometry
	var hz := Vector2(pos.x, pos.z)
	var lim := arena_radius + 7.5
	if hz.length() > lim:
		hz = hz.normalized() * lim
		pos = Vector3(hz.x, pos.y, hz.y)
	_trauma = maxf(0.0, _trauma - dt * 1.6)
	var sh := _trauma * _trauma * shake_scale
	if sh > 0.0:
		pos += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * sh * 0.25
	global_position = pos
	look_at(look, Vector3.UP)
	if sh > 0.0:
		rotate_object_local(Vector3.FORWARD, _rng.randf_range(-1, 1) * sh * 0.05)


func _free_cam(dt: float) -> void:
	var mv := Controls.move_vector()
	free_yaw -= Controls.camera_axis() * dt * 1.8
	var basis_y := Basis(Vector3.UP, free_yaw)
	free_pos += basis_y * Vector3(mv.x, 0, -mv.y) * dt * 6.0
	if Input.is_action_pressed("guard"):
		free_pos.y -= dt * 3.0
	if Input.is_action_pressed("dodge"):
		free_pos.y += dt * 3.0
	free_pos.y = clampf(free_pos.y, 0.5, 14.0)
	global_transform = Transform3D(basis_y * Basis(Vector3.RIGHT, free_pitch), free_pos)


## Ground-plane basis used to convert the movement stick into a world direction.
func input_basis() -> Basis:
	return Basis(Vector3.UP, atan2(global_basis.z.x, global_basis.z.z))
