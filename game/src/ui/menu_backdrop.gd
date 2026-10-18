class_name MenuBackdrop
extends Node3D
## Animated 3D background for the title and main menus: The Gullet under arena lights, an orbiting
## camera that keeps the cage right of centre (menus sit on the left), and two coloured spotlights
## (night-rim cyan, circuit gold) sweeping the mat. Installed as App's current scene by
## MenuBackdrop.ensure(); App.start_match() replaces it. Skipped in headless runs.
## Reduced motion slows the orbit to a crawl and stops the sweeps.

var arena_view: ArenaView
var cam: Camera3D
var _t := 0.0
var _sweeps: Array[SpotLight3D] = []
var _sweep_targets: Array[Vector3] = []


static func ensure() -> void:
	Audio.silence_environment()
	if DisplayServer.get_name() == "headless":
		return
	var s = App.current_scene
	if s != null and is_instance_valid(s) and s is MenuBackdrop:
		return
	App.set_scene(MenuBackdrop.new())


func _ready() -> void:
	name = "MenuBackdrop"
	var def: ArenaDef = Content.arena("the_gullet")
	if def == null:
		def = ArenaDef.from_dict({"id": "menu", "name": "The Gullet", "base": "octagon", "radius": 5.0, "theme": "can"})
	arena_view = ArenaView.new()
	add_child(arena_view)
	arena_view.build(def)
	arena_view.apply_quality(Settings.quality())
	arena_view.set_crowd_energy(0.35)
	cam = Camera3D.new()
	cam.fov = 46.0
	cam.near = 0.1
	cam.far = 200.0
	add_child(cam)
	cam.current = true
	var colors := [UiTheme.RIM, UiTheme.GOLD]
	for i in 2:
		var s := SpotLight3D.new()
		s.light_color = colors[i]
		s.light_energy = 9.0
		s.spot_range = 22.0
		s.spot_angle = 16.0
		s.spot_angle_attenuation = 0.5
		s.shadow_enabled = false
		add_child(s)
		_sweeps.append(s)
		_sweep_targets.append(Vector3.ZERO)
	_t = 7.0
	_update()


func _process(dt: float) -> void:
	_t += dt * (0.15 if UiTheme.reduce_motion() else 1.0)
	_update()


func _update() -> void:
	var a := _t * 0.045
	var r := 10.8
	var pos := Vector3(sin(a) * r, 3.4 + sin(_t * 0.13) * 0.35, cos(a) * r)
	var center := Vector3(0, 0.9, 0)
	var fwd := (center - pos).normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	cam.position = pos
	cam.look_at(center - right * 2.7, Vector3.UP)
	for i in _sweeps.size():
		var phase := _t * (0.33 if i == 0 else 0.27) + PI * i
		if UiTheme.reduce_motion():
			phase = PI * i + 0.6
		var target := Vector3(cos(phase) * 3.2, 0.0, sin(phase * 1.3) * 3.2)
		var origin := Vector3(cos(phase * 0.5 + i * 2.0) * 6.5, 9.0, sin(phase * 0.5 + i * 2.0) * 6.5)
		_sweeps[i].position = origin
		_sweeps[i].look_at(target, Vector3.UP)
