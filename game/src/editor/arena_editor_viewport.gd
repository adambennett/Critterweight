class_name ArenaEditorViewport
extends SubViewportContainer
## The arena editor's 3D view: an ArenaView (editor mode, own World3D) with an orbit camera,
## the placement cursor, a translucent ghost of the armed palette item, the selection outline,
## validation pins and a floor grid. Pointer input is converted to floor coordinates and emitted;
## all editing decisions are made by ArenaEditorScreen. Purely visual.

signal pointer_moved(world: Vector3)
signal pointer_pressed(world: Vector3, button: int, shift: bool, alt: bool)
signal pointer_released(world: Vector3, button: int)

const GRID_SHADER := "shader_type spatial;\nrender_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;\nuniform vec4 col : source_color = vec4(1.0, 1.0, 1.0, 1.0);\nuniform float minor = 0.5;\nvarying vec3 w;\nvoid vertex() { w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }\nvoid fragment() {\n\tvec2 p = w.xz;\n\tvec2 f1 = abs(fract(p / minor + 0.5) - 0.5) * minor;\n\tvec2 f2 = abs(fract(p + 0.5) - 0.5);\n\tfloat l1 = 1.0 - smoothstep(0.0, 0.012, min(f1.x, f1.y));\n\tfloat l2 = 1.0 - smoothstep(0.0, 0.02, min(f2.x, f2.y));\n\tALBEDO = col.rgb;\n\tALPHA = max(l1 * 0.12, l2 * 0.3) * col.a;\n}\n"

var sv: SubViewport
var root: Node3D
var view: ArenaView
var cam: Camera3D
var arena: ArenaDef
var focus := Vector3.ZERO
var yaw := deg_to_rad(28.0)
var pitch := deg_to_rad(54.0)
var dist := 17.0
var _focus_target := Vector3.ZERO
var cursor: Node3D
var ghost: Node3D
var _ghost_key := ""
var _ghost_ring: MeshInstance3D
var selection: Node3D
var pins: Node3D
var grid: MeshInstance3D
var _orbit_drag := false
var _pan_drag := false
var _rmb_moved := 0.0
var _last_mouse := Vector2.ZERO
var mouse_inside := false
var hover_world := Vector3.ZERO


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	sv = SubViewport.new()
	sv.own_world_3d = true
	sv.msaa_3d = Viewport.MSAA_2X
	sv.handle_input_locally = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	root = Node3D.new()
	root.name = "EditorWorld"
	sv.add_child(root)
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.05
	cam.far = 400.0
	root.add_child(cam)
	cam.current = true
	_build_cursor()
	pins = Node3D.new()
	root.add_child(pins)
	mouse_entered.connect(func(): mouse_inside = true)
	mouse_exited.connect(func(): mouse_inside = false)


func show_arena(a: ArenaDef) -> void:
	arena = a
	if view and is_instance_valid(view):
		view.queue_free()
	view = ArenaView.new()
	view.set_editor_mode(true)
	root.add_child(view)
	view.build(a)
	view.set_crowd_energy(0.15)
	if grid and is_instance_valid(grid):
		grid.queue_free()
	var ext := a.extent().grow(1.0)
	grid = MeshInstance3D.new()
	grid.mesh = ArenaMeshKit.floor_quad(ext.size)
	var gm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GRID_SHADER
	gm.shader = sh
	gm.set_shader_parameter("col", Color(0.95, 0.97, 1.0, 0.9))
	gm.render_priority = 3
	grid.material_override = gm
	grid.position = Vector3(ext.get_center().x, 0.02, ext.get_center().y)
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(grid)


func show_layout(a: ArenaDef) -> void:
	arena = a
	if view:
		view.rebuild_layout(a)


func set_grid_visible(on: bool) -> void:
	if grid:
		grid.visible = on


# =====================================================================================
# Camera
# =====================================================================================

func _process(dt: float) -> void:
	focus = focus.lerp(_focus_target, clampf(dt * 10.0, 0.0, 1.0))
	pitch = clampf(pitch, deg_to_rad(18.0), deg_to_rad(88.0))
	dist = clampf(dist, 4.0, 40.0)
	var off := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)) * dist
	cam.position = focus + off
	cam.look_at(focus, Vector3.UP)
	if cursor and cursor.visible:
		var ring: Node3D = cursor.get_node("Ring")
		ring.rotation.y += dt * 1.6
		ring.scale = Vector3.ONE * (1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.06)


func set_focus(p: Vector3, instant := false) -> void:
	_focus_target = Vector3(p.x, 0.0, p.z)
	if instant:
		focus = _focus_target


func orbit(dyaw: float, dpitch: float) -> void:
	yaw += dyaw
	pitch += dpitch


func zoom(factor: float) -> void:
	dist *= factor


func pan(screen_delta: Vector2) -> void:
	var right := cam.global_basis.x
	right.y = 0.0
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	var k := dist * 0.0016
	_focus_target += (-right.normalized() * screen_delta.x + fwd.normalized() * screen_delta.y) * k
	_clamp_focus()


func _clamp_focus() -> void:
	if arena:
		var ext := arena.extent().grow(3.0)
		_focus_target.x = clampf(_focus_target.x, ext.position.x, ext.end.x)
		_focus_target.z = clampf(_focus_target.z, ext.position.y, ext.end.y)


func reset_camera() -> void:
	yaw = deg_to_rad(28.0)
	pitch = deg_to_rad(54.0)
	dist = 17.0 if arena == null else maxf(arena.extent().size.x, arena.extent().size.y) * 1.25 + 3.0
	set_focus(Vector3.ZERO)


## Camera-relative ground axes (for stick movement): [right, forward] as XZ unit vectors.
func ground_axes() -> Array:
	var right := cam.global_basis.x
	right.y = 0.0
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	return [right.normalized(), fwd.normalized()]


# =====================================================================================
# Picking
# =====================================================================================

func floor_point(screen_pos: Vector2) -> Vector3:
	var o := cam.project_ray_origin(screen_pos)
	var d := cam.project_ray_normal(screen_pos)
	if absf(d.y) < 1e-4:
		return Vector3(o.x, 0.0, o.z)
	var t := -o.y / d.y
	if t < 0.0:
		t = 200.0
	var p := o + d * t
	return Vector3(p.x, 0.0, p.z)


func screen_point(world: Vector3) -> Vector2:
	return cam.unproject_position(world)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _orbit_drag:
			orbit(-mm.relative.x * 0.006, mm.relative.y * 0.005)
			_rmb_moved += mm.relative.length()
		elif _pan_drag:
			pan(mm.relative)
		hover_world = floor_point(mm.position)
		pointer_moved.emit(hover_world)
		accept_event()
	elif ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					zoom(0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					zoom(1.1)
			MOUSE_BUTTON_RIGHT:
				_orbit_drag = mb.pressed
				if mb.pressed:
					_rmb_moved = 0.0
				elif _rmb_moved < 6.0:
					pointer_pressed.emit(floor_point(mb.position), MOUSE_BUTTON_RIGHT, mb.shift_pressed, mb.alt_pressed)
			MOUSE_BUTTON_MIDDLE:
				_pan_drag = mb.pressed
			MOUSE_BUTTON_LEFT:
				grab_focus()
				hover_world = floor_point(mb.position)
				if mb.pressed:
					pointer_pressed.emit(hover_world, MOUSE_BUTTON_LEFT, mb.shift_pressed, mb.alt_pressed)
				else:
					pointer_released.emit(hover_world, MOUSE_BUTTON_LEFT)
		accept_event()


# =====================================================================================
# Cursor, ghost, selection, pins
# =====================================================================================

func _build_cursor() -> void:
	cursor = Node3D.new()
	cursor.name = "Cursor"
	root.add_child(cursor)
	var ring := Node3D.new()
	ring.name = "Ring"
	cursor.add_child(ring)
	var tm := TorusMesh.new()
	tm.inner_radius = 0.28
	tm.outer_radius = 0.36
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color("#C9A227")
	m.no_depth_test = true
	m.render_priority = 4
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.material_override = m
	mi.scale = Vector3(1, 0.25, 1)
	mi.position.y = 0.04
	ring.add_child(mi)
	for k in 4:
		var tick := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.2, 0.02, 0.04)
		tick.mesh = bm
		tick.material_override = m
		tick.position = Vector3(cos(k * PI * 0.5) * 0.5, 0.04, sin(k * PI * 0.5) * 0.5)
		tick.rotation.y = -k * PI * 0.5
		ring.add_child(tick)


func set_cursor(p: Vector3, on := true) -> void:
	cursor.visible = on
	cursor.position = Vector3(p.x, 0.0, p.z)


## Shows a translucent preview of `def` placed as `item` (rebuilt only when the type changes).
func set_ghost(def: Dictionary, item: Dictionary, valid: bool) -> void:
	var key := "%s|%s" % [str(def.get("id", "")), str(item.get("team", -1))]
	if key != _ghost_key or ghost == null:
		clear_ghost()
		_ghost_key = key
		ghost = Node3D.new()
		root.add_child(ghost)
		var vis := ArenaPropVisuals.build(def, item, {"index": 0, "editor": true})
		vis.name = "Vis"
		ghost.add_child(vis)
		ArenaView._set_transparency(vis, 0.45)
		_ghost_ring = MeshInstance3D.new()
		_ghost_ring.mesh = ArenaMeshKit.floor_disc(1.0, 32)
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.no_depth_test = true
		_ghost_ring.material_override = rm
		ghost.add_child(_ghost_ring)
	var vis2: Node3D = ghost.get_node("Vis")
	if str(def.get("body", "none")) != "none":
		vis2.transform = ArenaBuilder.prop_body_transform(item, def)
	else:
		var pos: Vector3 = item["pos"]
		vis2.transform = Transform3D(Basis(Vector3.UP, float(item.get("yaw", 0.0))), pos)
	var s := ArenaCatalog.footprint_size(item, def)
	var pos2: Vector3 = item["pos"]
	_ghost_ring.position = Vector3(pos2.x, 0.03, pos2.z)
	var r := maxf(0.35, s.length() * 0.5)
	_ghost_ring.scale = Vector3(r, 1, r)
	(_ghost_ring.material_override as StandardMaterial3D).albedo_color = Color(0.55, 0.85, 0.3, 0.18) if valid else Color(1.0, 0.3, 0.3, 0.3)


func clear_ghost() -> void:
	if ghost and is_instance_valid(ghost):
		ghost.queue_free()
	ghost = null
	_ghost_key = ""


## Gold outline around the selected item's footprint, with a facing arrow.
func set_selection(item: Dictionary, def: Dictionary) -> void:
	clear_selection()
	if item.is_empty():
		return
	selection = Node3D.new()
	root.add_child(selection)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("#FFD24A")
	mat.no_depth_test = true
	mat.render_priority = 5
	var poly := PackedVector2Array()
	if bool(def.get("is_marker", false)) or ArenaCatalog.footprint_shape(def) != "box":
		var c: Vector3 = item["pos"]
		var r := 0.6 if bool(def.get("is_marker", false)) else ArenaCatalog.footprint_size(item, def).x * 0.5 + 0.12
		for k in 24:
			var a := TAU * k / 24.0
			poly.append(Vector2(c.x + cos(a) * r, c.z + sin(a) * r))
	else:
		var s := ArenaCatalog.footprint_size(item, def) + Vector2(0.24, 0.24)
		for l in [Vector2(-s.x, -s.y), Vector2(s.x, -s.y), Vector2(s.x, s.y), Vector2(-s.x, s.y)]:
			poly.append(ArenaCatalog.to_world(item, l * 0.5))
	var band := MeshInstance3D.new()
	band.mesh = ArenaMeshKit.outline_band(poly, 0.0, 0.07, 0.05)
	band.material_override = mat
	selection.add_child(band)
	if item.has("pos2"):
		var c2: Vector3 = item["pos2"]
		var ring := MeshInstance3D.new()
		var poly2 := PackedVector2Array()
		for k2 in 24:
			var a2 := TAU * k2 / 24.0
			poly2.append(Vector2(c2.x + cos(a2) * 0.62, c2.z + sin(a2) * 0.62))
		ring.mesh = ArenaMeshKit.outline_band(poly2, 0.0, 0.06, 0.05)
		ring.material_override = mat
		selection.add_child(ring)
	var arrow := MeshInstance3D.new()
	arrow.mesh = ArenaMeshKit.cylinder(0.0, 0.16, 0.36, 3, 0.0)
	arrow.material_override = mat
	var p: Vector3 = item["pos"]
	var yaw2 := float(item.get("yaw", 0.0))
	var fwd := Vector3(sin(yaw2), 0, cos(yaw2))
	var reach := ArenaCatalog.footprint_size(item, def).y * 0.5 + 0.45 if not bool(def.get("is_marker", false)) else 0.95
	arrow.position = p + fwd * reach + Vector3(0, 0.06, 0)
	arrow.rotation = Vector3(PI * 0.5, yaw2, 0)
	arrow.scale = Vector3(1, 1, 0.3)
	selection.add_child(arrow)


func clear_selection() -> void:
	if selection and is_instance_valid(selection):
		selection.queue_free()
	selection = null


## Red pins at error positions (warnings amber).
func set_pins(issues: Array) -> void:
	for c in pins.get_children():
		c.queue_free()
	for it in issues:
		var p: Vector3 = it.get("pos", Vector3.ZERO)
		if p == Vector3.ZERO and str(it.get("ref", {}).get("kind", "")) == "layout":
			continue
		var l := Label3D.new()
		l.text = "!"
		l.font_size = 72
		l.pixel_size = 0.006
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.outline_size = 14
		l.modulate = Color("#FF5A5A") if str(it.get("severity", "")) == "error" else Color("#FFC43D")
		l.outline_modulate = Color(0.08, 0.03, 0.03)
		l.font = load("res://assets/fonts/BarlowCondensed-900.woff2")
		l.position = p + Vector3(0, 1.9, 0)
		pins.add_child(l)
