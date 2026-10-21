class_name FighterPreview
extends SubViewportContainer
## The same segmented model renderer used in fights, isolated from gameplay physics.
var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var model: CreatureView
var yaw := 0.4
var pitch := 0.15
var distance := 4.0
var target := Vector3(0, 0.8, 0)
var creature_id := ""

func _init() -> void:
	stretch = true
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(440, 260)
	set_meta("owns_sticks", true)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	resized.connect(queue_redraw)

func _draw() -> void:
	if has_focus():
		draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), UiTheme.GOLD, false, 4)

func _ready() -> void:
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = UiTheme.BG_DEEP
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8795b0")
	env.ambient_light_energy = 0.8
	environment.environment = env
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42, -35, 0)
	light.light_energy = 2.5
	world.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 140, 0)
	fill.light_color = UiTheme.RIM
	fill.light_energy = 1.3
	world.add_child(fill)
	camera = Camera3D.new()
	camera.fov = 40
	world.add_child(camera)
	camera.current = true
	var pedestal := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 2.0
	mesh.bottom_radius = 2.0
	mesh.height = 0.12
	pedestal.mesh = mesh
	pedestal.position.y = -0.08
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("282c35")
	pedestal.material_override = mat
	world.add_child(pedestal)

func show_fighter(c: CreatureDef) -> void:
	creature_id = c.id
	if model:
		world.remove_child(model)
		model.queue_free()
	model = CreatureView.new()
	world.add_child(model)
	model.setup(c, Elements.color(c.element))
	var transforms: Array[Transform3D] = []
	var height := 1.0
	var extent := 1.0
	var lift := Vector3.UP * CreatureView.rest_sink(c.body)    # feet on the pedestal, not in it
	for segment in c.body.segments:
		transforms.append(Transform3D(Basis.IDENTITY, segment.pivot + lift))
		height = maxf(height, segment.pivot.y)
		extent = maxf(extent, segment.pivot.length())
	model.snap_transforms(transforms)
	model.render(1.0)      # once: a skin swap (CreatureView.reload_model) re-poses from these transforms
	target = Vector3(0, height * 0.5, 0)
	distance = maxf(4.2, extent * 2.5)
	yaw = 0.4
	pitch = 0.15

func _process(dt: float) -> void:
	if camera == null or not is_visible_in_tree():
		return
	if has_focus():
		for device in Input.get_connected_joypads():
			var x := Input.get_joy_axis(device, JOY_AXIS_RIGHT_X)
			var y := Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y)
			if absf(x) > 0.2:
				yaw -= x * dt * 2
			if absf(y) > 0.2:
				pitch += y * dt
			var zoom := Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT) - Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT)
			if absf(zoom) > 0.2:
				distance += zoom * dt * 4
	pitch = clampf(pitch, -0.25, 1.2)
	distance = clampf(distance, 2, 15)
	camera.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(target, Vector3.UP)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		grab_focus()
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance -= 0.3
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance += 0.3
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		yaw -= event.relative.x * 0.008
		pitch += event.relative.y * 0.005
	elif event is InputEventJoypadMotion:
		accept_event()
