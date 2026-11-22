extends Node3D
class_name Battlefield3D

## Native Godot 4 spatial battlefield.
## The deterministic simulator still owns game state; this node only renders
## that state with engine-native 3D nodes and owns camera gestures.

signal camera_changed(yaw: float, pitch: float, zoom: float)

const GRID_COLUMNS := 8
const GRID_ROWS := 6
const CELL_SIZE := 1.6
const BOARD_ORIGIN := Vector3(-5.6, 0.0, -4.0)
const ROUTE_CELLS := [Vector2i(0, 3), Vector2i(3, 2), Vector2i(5, 3), Vector2i(7, 3)]
const CAMERA_TARGET := Vector3(0.0, 0.0, 0.0)
const CAMERA_MIN_ZOOM := 8.0
const CAMERA_MAX_ZOOM := 22.0
const CAMERA_DEFAULT_ZOOM := 14.0
const CAMERA_MIN_PITCH := deg_to_rad(30.0)
const CAMERA_MAX_PITCH := deg_to_rad(68.0)

var simulation: Object
var snapshot: Dictionary = {}
var camera: Camera3D
var environment_node: WorldEnvironment
var grid_root: Node3D
var route_root: Node3D
var module_root: Node3D
var enemy_root: Node3D
var camera_yaw := deg_to_rad(45.0)
var camera_pitch := deg_to_rad(50.0)
var camera_zoom := CAMERA_DEFAULT_ZOOM
var dragging := false
var last_pointer := Vector2.ZERO
var touches: Dictionary = {}
var touch_last: Dictionary = {}
var touch_previous_distance := -1.0
var touch_previous_angle := 0.0
var module_nodes: Dictionary = {}
var enemy_nodes: Dictionary = {}
var module_materials: Dictionary = {}
var enemy_material: StandardMaterial3D
var route_material: StandardMaterial3D
var core_material: StandardMaterial3D
var ground_material: StandardMaterial3D
var board_ready := false

func _ready() -> void:
	_build_spatial_scene()
	_apply_camera_transform()
	set_process(true)
	set_process_input(true)

func setup(value: Object) -> void:
	simulation = value
	if not board_ready:
		_build_spatial_scene()
	if simulation != null and simulation.has_method("get_snapshot"):
		sync_snapshot(simulation.get_snapshot())

func _build_spatial_scene() -> void:
	if board_ready:
		return
	board_ready = true
	grid_root = Node3D.new()
	grid_root.name = "Grid"
	add_child(grid_root)
	route_root = Node3D.new()
	route_root.name = "Routes"
	add_child(route_root)
	module_root = Node3D.new()
	module_root.name = "Modules"
	add_child(module_root)
	enemy_root = Node3D.new()
	enemy_root.name = "Enemies"
	add_child(enemy_root)

	environment_node = WorldEnvironment.new()
	environment_node.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#071017")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#7aa7b8")
	environment.ambient_light_energy = 0.72
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.rotation_degrees = Vector3(-54.0, -28.0, 0.0)
	sun.light_color = Color("#d8efff")
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	add_child(sun)

	var fill := OmniLight3D.new()
	fill.name = "CoreFill"
	fill.position = Vector3(0.0, 4.0, 0.0)
	fill.light_color = Color("#42c7ee")
	fill.light_energy = 1.4
	fill.omni_range = 12.0
	add_child(fill)

	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = camera_zoom
	camera.current = true
	camera.far = 80.0
	add_child(camera)

	ground_material = _material(Color("#0a2029"), 0.94, 0.08)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(15.6, 11.6)
	ground.mesh = ground_mesh
	ground.material_override = ground_material
	ground.position = Vector3(0.0, -0.08, 0.0)
	add_child(ground)

	_build_grid()
	_build_routes()
	_build_core_marker()
	_apply_camera_transform()

func _material(color: Color, roughness := 0.78, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _build_grid() -> void:
	for x in range(GRID_COLUMNS + 1):
		var x_position := BOARD_ORIGIN.x + float(x) * CELL_SIZE - CELL_SIZE * 0.5
		_add_box(grid_root, "GridX%02d" % x, Vector3(x_position, 0.015, 0.0), Vector3(0.025, 0.03, CELL_SIZE * GRID_ROWS), Color("#1d4a58"))
	for z in range(GRID_ROWS + 1):
		var z_position := BOARD_ORIGIN.z + float(z) * CELL_SIZE - CELL_SIZE * 0.5
		_add_box(grid_root, "GridZ%02d" % z, Vector3(0.0, 0.016, z_position), Vector3(CELL_SIZE * GRID_COLUMNS, 0.03, 0.025), Color("#1d4a58"))
	for cell_x in range(GRID_COLUMNS):
		for cell_z in range(GRID_ROWS):
			var cell := Vector2i(cell_x, cell_z)
			var accent := Color("#102f39") if (cell_x + cell_z) % 2 == 0 else Color("#0e2933")
			_add_box(grid_root, "Cell_%d_%d" % [cell_x, cell_z], cell_to_world(cell) + Vector3(0.0, -0.015, 0.0), Vector3(CELL_SIZE - 0.05, 0.02, CELL_SIZE - 0.05), accent)

func _build_routes() -> void:
	route_material = _material(Color("#42c7ee"), 0.45, 0.18)
	for index in range(ROUTE_CELLS.size() - 1):
		var from := cell_to_world(ROUTE_CELLS[index]) + Vector3(0.0, 0.055, 0.0)
		var to := cell_to_world(ROUTE_CELLS[index + 1]) + Vector3(0.0, 0.055, 0.0)
		_add_segment(route_root, "SignalRoute%02d" % index, from, to, 0.12, route_material)
	var energy_material := _material(Color("#ffca62"), 0.5, 0.12)
	_add_segment(route_root, "EnergyRoute", cell_to_world(Vector2i(2, 4)) + Vector3(0.0, 0.08, 0.0), cell_to_world(Vector2i(5, 3)) + Vector3(0.0, 0.08, 0.0), 0.09, energy_material)
	var hazard_material := _material(Color("#ff6b75"), 0.54, 0.08)
	_add_segment(route_root, "HazardRoute", cell_to_world(Vector2i(6, 1)) + Vector3(0.0, 0.1, 0.0), cell_to_world(Vector2i(6, 5)) + Vector3(0.0, 0.1, 0.0), 0.07, hazard_material)

func _build_core_marker() -> void:
	core_material = _material(Color("#68e3bf"), 0.32, 0.2)
	var core := MeshInstance3D.new()
	core.name = "Core"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.46
	mesh.bottom_radius = 0.58
	mesh.height = 0.22
	core.mesh = mesh
	core.material_override = core_material
	core.position = cell_to_world(Vector2i(7, 3)) + Vector3(0.0, 0.14, 0.0)
	add_child(core)
	var beacon := OmniLight3D.new()
	beacon.name = "CoreBeacon"
	beacon.position = core.position + Vector3(0.0, 1.2, 0.0)
	beacon.light_color = Color("#68e3bf")
	beacon.light_energy = 2.0
	beacon.omni_range = 3.5
	add_child(beacon)

func _add_box(parent: Node3D, node_name: String, position: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.material_override = _material(color)
	mesh_instance.position = position
	parent.add_child(mesh_instance)
	return mesh_instance

func _add_segment(parent: Node3D, node_name: String, from: Vector3, to: Vector3, thickness: float, material: StandardMaterial3D) -> void:
	var delta := to - from
	var length := Vector2(delta.x, delta.z).length()
	var segment := MeshInstance3D.new()
	segment.name = node_name
	var box := BoxMesh.new()
	box.size = Vector3(length, thickness, thickness)
	segment.mesh = box
	segment.material_override = material
	segment.position = (from + to) * 0.5
	segment.rotation.y = -atan2(delta.z, delta.x)
	parent.add_child(segment)

func cell_to_world(cell: Vector2i) -> Vector3:
	return BOARD_ORIGIN + Vector3(float(cell.x) * CELL_SIZE, 0.0, float(cell.y) * CELL_SIZE)

func world_to_cell(world_position: Vector3) -> Vector2i:
	var local := world_position - BOARD_ORIGIN
	return Vector2i(clampi(int(floor(local.x / CELL_SIZE + 0.5)), 0, GRID_COLUMNS - 1), clampi(int(floor(local.z / CELL_SIZE + 0.5)), 0, GRID_ROWS - 1))

func sync_snapshot(value: Dictionary) -> void:
	snapshot = value.duplicate(true)
	_sync_modules(snapshot.get("modules", []))
	_sync_enemies(snapshot.get("enemies", {}))

func _sync_modules(items: Array) -> void:
	var alive: Dictionary = {}
	for item in items:
		if not item is Dictionary:
			continue
		var module_id := str(item.get("id", ""))
		if module_id.is_empty():
			continue
		alive[module_id] = true
		var actor: MeshInstance3D = module_nodes.get(module_id)
		if actor == null:
			actor = _create_module_actor(module_id)
			module_nodes[module_id] = actor
		var cell_value = item.get("cell", Vector2i.ZERO)
		var cell: Vector2i = cell_value if cell_value is Vector2i else Vector2i(int(cell_value.get("x", 0)), int(cell_value.get("y", 0)))
		actor.position = cell_to_world(cell) + Vector3(0.0, 0.28, 0.0)
		actor.rotation.y = deg_to_rad(float(item.get("rotation", 0)) * 90.0)
		var color_value = item.get("color", Color("#72d7ff"))
		var color: Color = color_value if color_value is Color else Color(str(color_value))
		var material: StandardMaterial3D = module_materials.get(module_id)
		if material == null:
			material = _material(color, 0.42, 0.12)
			module_materials[module_id] = material
			actor.material_override = material
		material.albedo_color = color if not bool(item.get("disabled", false)) else color.darkened(0.6)
	for module_id in module_nodes.keys().duplicate():
		if not alive.has(module_id):
			module_nodes[module_id].queue_free()
			module_nodes.erase(module_id)

func _create_module_actor(module_id: String) -> MeshInstance3D:
	var actor := MeshInstance3D.new()
	actor.name = "Module_%s" % module_id
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.42
	mesh.bottom_radius = 0.52
	mesh.height = 0.48
	actor.mesh = mesh
	module_root.add_child(actor)
	return actor

func _sync_enemies(value) -> void:
	var items: Array = []
	if value is Dictionary:
		items = value.values()
	elif value is Array:
		items = value
	var alive: Dictionary = {}
	for item in items:
		if not item is Dictionary:
			continue
		var enemy_id := str(item.get("id", ""))
		if enemy_id.is_empty():
			continue
		alive[enemy_id] = true
		var actor: MeshInstance3D = enemy_nodes.get(enemy_id)
		if actor == null:
			actor = _create_enemy_actor(enemy_id)
			enemy_nodes[enemy_id] = actor
		var progress := float(item.get("progress", 0.0))
		actor.position = _route_position(progress) + Vector3(0.0, 0.34, 0.0)
		actor.scale = Vector3.ONE * clampf(0.72 + float(item.get("hp", 1)) / maxf(1.0, float(item.get("max_hp", 1))) * 0.28, 0.6, 1.0)
	for enemy_id in enemy_nodes.keys().duplicate():
		if not alive.has(enemy_id):
			enemy_nodes[enemy_id].queue_free()
			enemy_nodes.erase(enemy_id)

func _create_enemy_actor(enemy_id: String) -> MeshInstance3D:
	var actor := MeshInstance3D.new()
	actor.name = "Enemy_%s" % enemy_id
	var mesh := SphereMesh.new()
	mesh.radius = 0.28
	mesh.height = 0.56
	actor.mesh = mesh
	if enemy_material == null:
		enemy_material = _material(Color("#ff6b75"), 0.44, 0.05)
	actor.material_override = enemy_material
	enemy_root.add_child(actor)
	return actor

func _route_position(progress: float) -> Vector3:
	var clamped := clampf(progress, 0.0, 1.0)
	var segment_count := ROUTE_CELLS.size() - 1
	var scaled := clamped * float(segment_count)
	var index := clampi(int(floor(scaled)), 0, segment_count - 1)
	var local_t := scaled - float(index)
	return cell_to_world(ROUTE_CELLS[index]).lerp(cell_to_world(ROUTE_CELLS[index + 1]), local_t)

func _apply_camera_transform() -> void:
	if camera == null:
		return
	var horizontal := cos(camera_pitch) * camera_zoom
	var position := CAMERA_TARGET + Vector3(sin(camera_yaw) * horizontal, sin(camera_pitch) * camera_zoom, cos(camera_yaw) * horizontal)
	camera.global_position = position
	camera.look_at(CAMERA_TARGET, Vector3.UP)
	camera.size = camera_zoom
	camera_changed.emit(camera_yaw, camera_pitch, camera_zoom)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_set_zoom(camera_zoom - 1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_set_zoom(camera_zoom + 1.0)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			last_pointer = event.position
	elif event is InputEventMouseMotion and dragging:
		var delta: Vector2 = event.position - last_pointer
		last_pointer = event.position
		_rotate_camera(delta)
	elif event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
			touch_last[event.index] = event.position
			if touches.size() == 2:
				var points: Array = touches.values()
				touch_previous_distance = points[0].distance_to(points[1])
				touch_previous_angle = (points[1] - points[0]).angle()
		else:
			touches.erase(event.index)
			touch_last.erase(event.index)
			if touches.size() < 2:
				touch_previous_distance = -1.0
	elif event is InputEventScreenDrag:
		if not touches.has(event.index):
			return
		var previous: Vector2 = touch_last.get(event.index, event.position)
		touch_last[event.index] = event.position
		touches[event.index] = event.position
		if touches.size() == 1:
			_rotate_camera(event.position - previous)
		elif touches.size() >= 2:
			var points: Array = touches.values()
			var distance: float = points[0].distance_to(points[1])
			if touch_previous_distance > 0.0:
				_set_zoom(camera_zoom + (touch_previous_distance - distance) * 0.018)
			touch_previous_distance = distance
			var angle: float = (points[1] - points[0]).angle()
			_rotate_camera(Vector2(rad_to_deg(angle - touch_previous_angle) * 0.55, 0.0))
			touch_previous_angle = angle

func _rotate_camera(delta: Vector2) -> void:
	camera_yaw -= delta.x * 0.008
	camera_pitch = clampf(camera_pitch - delta.y * 0.006, CAMERA_MIN_PITCH, CAMERA_MAX_PITCH)
	_apply_camera_transform()

func _set_zoom(value: float) -> void:
	camera_zoom = clampf(value, CAMERA_MIN_ZOOM, CAMERA_MAX_ZOOM)
	_apply_camera_transform()

func reset_camera() -> void:
	camera_yaw = deg_to_rad(45.0)
	camera_pitch = deg_to_rad(50.0)
	camera_zoom = CAMERA_DEFAULT_ZOOM
	_apply_camera_transform()

func get_camera_state() -> Dictionary:
	return {"yaw": camera_yaw, "pitch": camera_pitch, "zoom": camera_zoom}
