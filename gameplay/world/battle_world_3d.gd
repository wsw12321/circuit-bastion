class_name BastionBattleWorld3D
extends Node3D

## 3D runtime spatial layer for Circuit Bastion.
## Simulation dictionaries remain the deterministic save/replay contract. This
## node owns the live Path3D, CharacterBody3D actors and Area3D contacts.

signal deployment_snapped(module_id: String, grid_position: Vector2i, world_position: Vector3)
signal deployment_rejected(kind: String, grid_position: Vector2i, reason: String)
signal enemy_hit(enemy_id: String, module_id: String, damage: int)
signal enemy_breached(enemy_id: String, damage: int)

const ENEMY_ACTOR_SCRIPT := preload("res://gameplay/world/enemy_actor_3d.gd")
const MODULE_AREA_SCRIPT := preload("res://gameplay/world/module_area_3d.gd")
const CAMERA_SCRIPT := preload("res://godot/battle_camera_3d.gd")
const GRID_COLUMNS := 8
const GRID_ROWS := 6
const CELL_SIZE := 2.0
const BOARD_ORIGIN := Vector3(-8.0, 0.52, -6.0)
const ENEMY_COLLISION_LAYER := 2
const MODULE_COLLISION_LAYER := 4

var simulation: RefCounted
var camera
var route_path: Path3D
var route_curve: Curve3D
var enemy_container: Node3D
var module_container: Node3D
var core_hit_area: Area3D
var enemy_bodies: Dictionary = {}
var module_areas: Dictionary = {}
var _hit_cooldowns: Dictionary = {}
var _breach_seen: Dictionary = {}
var _collision_queries: Dictionary = {}
var _collision_shapes: Dictionary = {}
var _ready_nodes := false
var _visual_phase := 0.0
var _signal_route_points: Array[Vector3] = []
var _energy_route_points: Array[Vector3] = []
var _signal_packet: MeshInstance3D
var _energy_packet: MeshInstance3D
var _entry_portal: MeshInstance3D

func _ready() -> void:
	_ensure_world_nodes()
	set_process(true)

func _process(delta: float) -> void:
	# A pair of low-poly packets makes the authored route feel live even when
	# the deterministic simulation is paused. They are purely presentational.
	_visual_phase = fmod(_visual_phase + maxf(delta, 0.0), TAU)
	if _signal_packet != null and _signal_route_points.size() > 1:
		_signal_packet.position = _sample_route(_signal_route_points, fmod(_visual_phase * 0.11, 1.0)) + Vector3(0.0, 0.16, 0.0)
		_signal_packet.scale = Vector3.ONE * (0.88 + sin(_visual_phase * 3.0) * 0.12)
	if _energy_packet != null and _energy_route_points.size() > 1:
		_energy_packet.position = _sample_route(_energy_route_points, fmod(_visual_phase * 0.075 + 0.35, 1.0)) + Vector3(0.0, 0.13, 0.0)
		_energy_packet.scale = Vector3.ONE * (0.90 + sin(_visual_phase * 2.6 + 0.9) * 0.10)
	if _entry_portal != null:
		_entry_portal.rotation.y = _visual_phase * 0.32

func setup(value: RefCounted) -> void:
	simulation = value
	_ensure_world_nodes()

func _ensure_world_nodes() -> void:
	if _ready_nodes:
		return
	enemy_container = Node3D.new()
	enemy_container.name = "EnemyActors3D"
	add_child(enemy_container)
	module_container = Node3D.new()
	module_container.name = "ModuleAreas3D"
	add_child(module_container)
	route_path = Path3D.new()
	route_path.name = "EnemyRoute3D"
	route_curve = Curve3D.new()
	route_curve.bake_interval = 0.1
	for point in [
		cell_to_world(Vector2i(0, 3)),
		cell_to_world(Vector2i(2, 3)),
		cell_to_world(Vector2i(3, 2)),
		cell_to_world(Vector2i(5, 3)),
		cell_to_world(Vector2i(7, 3)),
	]:
		route_curve.add_point(point)
	route_path.curve = route_curve
	add_child(route_path)
	_create_environment()
	_create_ground()
	_create_route_visuals()
	_create_camera()
	_create_core_area()
	_ready_nodes = true

func _create_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "BattleEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#050b12")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#77a9bd")
	environment.ambient_light_energy = 0.48
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.18
	environment.glow_enabled = true
	environment.glow_intensity = 0.7
	environment.glow_bloom = 0.14
	environment.fog_enabled = true
	environment.fog_light_color = Color("#102834")
	environment.fog_density = 0.008
	environment.fog_height = 0.0
	environment.fog_height_density = 0.025
	world_environment.environment = environment
	add_child(world_environment)

func _create_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(GRID_COLUMNS * CELL_SIZE + 2.0, 0.5, GRID_ROWS * CELL_SIZE + 2.0)
	shape.shape = box
	shape.position.y = -0.05
	ground.add_child(shape)
	var deck := MeshInstance3D.new()
	deck.name = "ArenaDeck"
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = box.size
	deck.mesh = deck_mesh
	deck.position.y = -0.05
	deck.material_override = _material(Color("#0b1c27"), Color("#07131b"), 0.18)
	deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	ground.add_child(deck)
	add_child(ground)

	var tile_material_a := _material(Color("#12313d"), Color("#06131b"), 0.06)
	var tile_material_b := _material(Color("#102834"), Color("#071721"), 0.08)
	for row in GRID_ROWS:
		for column in GRID_COLUMNS:
			var tile := MeshInstance3D.new()
			tile.name = "Tile_%d_%d" % [column, row]
			var tile_mesh := BoxMesh.new()
			tile_mesh.size = Vector3(CELL_SIZE - 0.08, 0.12, CELL_SIZE - 0.08)
			tile.mesh = tile_mesh
			tile.position = cell_to_world(Vector2i(column, row)) + Vector3(0.0, -0.17, 0.0)
			tile.material_override = tile_material_a if (column + row) % 2 == 0 else tile_material_b
			tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(tile)

	var border_material := _material(Color("#1a5361"), Color("#0a2832"), 0.24)
	for x in range(GRID_COLUMNS + 1):
		_add_box("BorderX_%d" % x, Vector3(0.06, 0.18, GRID_ROWS * CELL_SIZE + 0.5), Vector3(BOARD_ORIGIN.x + float(x) * CELL_SIZE, 0.16, 0.0), border_material)
	for z in range(GRID_ROWS + 1):
		_add_box("BorderZ_%d" % z, Vector3(GRID_COLUMNS * CELL_SIZE + 0.5, 0.18, 0.06), Vector3(0.0, 0.16, BOARD_ORIGIN.z + float(z) * CELL_SIZE), border_material)

func _create_route_visuals() -> void:
	var route_material := _material(Color("#176277"), Color("#28c6dc"), 1.5)
	var route_glow_material := _material(Color("#0e3140"), Color("#25bcd2"), 0.8)
	_signal_route_points = [
		cell_to_world(Vector2i(0, 3)) + Vector3(0.0, -0.22, 0.0),
		cell_to_world(Vector2i(2, 3)) + Vector3(0.0, -0.22, 0.0),
		cell_to_world(Vector2i(3, 2)) + Vector3(0.0, -0.22, 0.0),
		cell_to_world(Vector2i(5, 3)) + Vector3(0.0, -0.22, 0.0),
		cell_to_world(Vector2i(7, 3)) + Vector3(0.0, -0.22, 0.0),
	]
	_energy_route_points = [
		cell_to_world(Vector2i(2, 4)) + Vector3(0.0, -0.18, 0.0),
		cell_to_world(Vector2i(3, 4)) + Vector3(0.0, -0.18, 0.0),
		cell_to_world(Vector2i(5, 3)) + Vector3(0.0, -0.18, 0.0),
	]
	for index in range(_signal_route_points.size() - 1):
		_add_segment("RouteGlow_%d" % index, _signal_route_points[index], _signal_route_points[index + 1], 0.28, route_glow_material)
		_add_segment("RouteRail_%d" % index, _signal_route_points[index] + Vector3(0.0, 0.08, 0.0), _signal_route_points[index + 1] + Vector3(0.0, 0.08, 0.0), 0.07, route_material)
	for index in range(_signal_route_points.size()):
		var beacon := MeshInstance3D.new()
		beacon.name = "RouteBeacon_%d" % index
		var beacon_mesh := CylinderMesh.new()
		beacon_mesh.top_radius = 0.16
		beacon_mesh.bottom_radius = 0.20
		beacon_mesh.height = 0.28
		beacon.mesh = beacon_mesh
		beacon.position = _signal_route_points[index] + Vector3(0.0, 0.14, 0.0)
		beacon.material_override = route_material
		add_child(beacon)
	_signal_packet = _create_route_packet("SignalPacket", Color("#9ff5ff"))
	_energy_packet = _create_route_packet("EnergyPacket", Color("#fff0ad"))

	# The entry reads as a portal rather than an unadorned spawn square.
	_entry_portal = MeshInstance3D.new()
	_entry_portal.name = "EntryPortal"
	var portal_mesh := TorusMesh.new()
	portal_mesh.inner_radius = 0.48
	portal_mesh.outer_radius = 0.56
	portal_mesh.rings = 14
	portal_mesh.ring_segments = 6
	_entry_portal.mesh = portal_mesh
	_entry_portal.position = _signal_route_points[0] + Vector3(0.0, 0.20, 0.0)
	_entry_portal.rotation_degrees.x = 90.0
	_entry_portal.material_override = _material(Color("#4a1f32"), Color("#ff6b75"), 1.3)
	add_child(_entry_portal)

func _create_camera() -> void:
	camera = get_node_or_null("Camera3D")
	if camera == null:
		for child in get_children():
			if child is Camera3D:
				camera = child as Camera3D
				break
	if camera == null or not camera.has_method("rotate_orbit"):
			camera = CAMERA_SCRIPT.new()
			camera.name = "BattleCamera3D"
			add_child(camera)
	camera.set("target", Vector3(0.0, 0.28, 0.0))
	camera.set("zoom_distance", 18.0)
	camera.set("target_zoom_distance", 18.0)
	camera.set("pitch", -0.78)
	camera.set("target_pitch", -0.78)
	camera.set("yaw", 0.32)
	camera.set("target_yaw", 0.32)
	camera.current = true

	var key_light: DirectionalLight3D = get_node_or_null("KeyLight")
	if key_light == null:
		key_light = get_node_or_null("BattleKeyLight3D")
	if key_light == null:
		key_light = DirectionalLight3D.new()
		key_light.name = "BattleKeyLight3D"
		add_child(key_light)
	key_light.rotation_degrees = Vector3(-55.0, -28.0, 0.0)
	key_light.light_color = Color("#b9e5ff")
	key_light.light_energy = 1.35
	key_light.shadow_enabled = true
	key_light.directional_shadow_max_distance = 40.0

	var rim_light: DirectionalLight3D = get_node_or_null("BattleRimLight3D")
	if rim_light == null:
		rim_light = DirectionalLight3D.new()
		rim_light.name = "BattleRimLight3D"
		add_child(rim_light)
	rim_light.rotation_degrees = Vector3(-28.0, 148.0, 0.0)
	rim_light.light_color = Color("#5b7dff")
	rim_light.light_energy = 0.34
	rim_light.shadow_enabled = false

	var fill: OmniLight3D = get_node_or_null("FillLight")
	if fill == null:
		fill = get_node_or_null("BattleFillLight3D")
	if fill == null:
		fill = OmniLight3D.new()
		fill.name = "BattleFillLight3D"
		add_child(fill)
	fill.position = Vector3(0.0, 6.0, 3.0)
	fill.omni_range = 30.0
	fill.light_color = Color("#4b8fa9")
	fill.light_energy = 1.1


func handle_camera_input(event: InputEvent) -> bool:
	if camera == null or not is_instance_valid(camera):
		return false
	return camera.handle_input(event)

func reset_camera_view() -> void:
	if camera != null and is_instance_valid(camera):
		camera.reset_view()

func _create_core_area() -> void:
	core_hit_area = Area3D.new()
	core_hit_area.name = "CoreHitArea3D"
	core_hit_area.collision_layer = 8
	core_hit_area.collision_mask = ENEMY_COLLISION_LAYER
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = CELL_SIZE * 0.38
	shape.shape = sphere
	core_hit_area.position = cell_to_world(Vector2i(7, 3))
	core_hit_area.add_child(shape)
	add_child(core_hit_area)

	var pedestal := MeshInstance3D.new()
	pedestal.name = "CorePedestal"
	var pedestal_mesh := CylinderMesh.new()
	pedestal_mesh.top_radius = 0.82
	pedestal_mesh.bottom_radius = 1.02
	pedestal_mesh.height = 0.38
	pedestal.mesh = pedestal_mesh
	pedestal.position = core_hit_area.position + Vector3(0.0, -0.23, 0.0)
	pedestal.material_override = _material(Color("#183a42"), Color("#0d6a79"), 0.45)
	add_child(pedestal)

	var core := MeshInstance3D.new()
	core.name = "CoreCrystal"
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.62
	core_mesh.height = 1.32
	core_mesh.radial_segments = 20
	core_mesh.rings = 10
	core.mesh = core_mesh
	core.position = core_hit_area.position + Vector3(0.0, 0.62, 0.0)
	core.scale = Vector3(0.78, 1.15, 0.78)
	core.material_override = _material(Color("#69e9d1"), Color("#36e8d2"), 2.4)
	add_child(core)

	var core_light := OmniLight3D.new()
	core_light.name = "CoreLight"
	core_light.position = core.position + Vector3(0.0, 0.2, 0.0)
	core_light.omni_range = 7.0
	core_light.light_color = Color("#43e5d0")
	core_light.light_energy = 2.2
	add_child(core_light)

	for side in range(4):
		var marker := MeshInstance3D.new()
		marker.name = "CoreMarker_%d" % side
		var marker_mesh := BoxMesh.new()
		marker_mesh.size = Vector3(0.08, 0.16, 0.75)
		marker.mesh = marker_mesh
		marker.position = core_hit_area.position + Vector3(0.0, 0.02, 0.0)
		marker.rotation_degrees.y = float(side) * 90.0
		marker.material_override = _material(Color("#3adbc9"), Color("#37d9d0"), 1.8)
		add_child(marker)

func _add_box(node_name: String, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.material_override = material
	add_child(mesh_instance)
	return mesh_instance

func _add_segment(node_name: String, start: Vector3, finish: Vector3, width: float, material: Material) -> MeshInstance3D:
	var segment := MeshInstance3D.new()
	segment.name = node_name
	var mesh := BoxMesh.new()
	var length := start.distance_to(finish)
	mesh.size = Vector3(width, width, length)
	segment.mesh = mesh
	segment.position = start.lerp(finish, 0.5)
	segment.rotation.y = atan2(finish.x - start.x, finish.z - start.z)
	segment.material_override = material
	add_child(segment)
	return segment

func _material(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = 0.42
	material.metallic = 0.26
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = energy
	return material

func _create_route_packet(node_name: String, color: Color) -> MeshInstance3D:
	var packet := MeshInstance3D.new()
	packet.name = node_name
	var mesh := SphereMesh.new()
	mesh.radius = 0.13 if node_name == "SignalPacket" else 0.10
	mesh.height = mesh.radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 6
	packet.mesh = mesh
	packet.material_override = _material(color, color, 2.2)
	add_child(packet)
	return packet

func _sample_route(points: Array[Vector3], progress: float) -> Vector3:
	if points.is_empty():
		return Vector3.ZERO
	if points.size() == 1:
		return points[0]
	var segment_count := points.size() - 1
	var scaled := clampf(progress, 0.0, 0.9999) * float(segment_count)
	var segment := mini(int(floor(scaled)), segment_count - 1)
	return points[segment].lerp(points[segment + 1], scaled - float(segment))

func cell_to_world(grid_position: Vector2i) -> Vector3:
	return BOARD_ORIGIN + Vector3((float(grid_position.x) + 0.5) * CELL_SIZE, 0.0, (float(grid_position.y) + 0.5) * CELL_SIZE)

func world_to_cell(world_position: Vector3) -> Vector2i:
	var local := (world_position - BOARD_ORIGIN) / CELL_SIZE
	return Vector2i(floor(local.x), floor(local.z))

func snap_to_grid(world_position: Vector3) -> Dictionary:
	var grid_position := world_to_cell(world_position)
	var in_bounds := grid_position.x >= 0 and grid_position.x < GRID_COLUMNS and grid_position.y >= 0 and grid_position.y < GRID_ROWS
	var clamped := Vector2i(clampi(grid_position.x, 0, GRID_COLUMNS - 1), clampi(grid_position.y, 0, GRID_ROWS - 1))
	return {"grid": clamped, "in_bounds": in_bounds, "world_position": cell_to_world(clamped), "distance": world_position.distance_to(cell_to_world(clamped))}

func preview_deployment(module_kind: String, world_position: Vector3, rotation := 0) -> Dictionary:
	if simulation == null:
		return {"valid": false, "reason": "simulation_unavailable"}
	var snap := snap_to_grid(world_position)
	if not bool(snap.get("in_bounds", false)):
		return {
			"valid": false,
			"kind": module_kind,
			"grid": {"x": int(snap.grid.x), "y": int(snap.grid.y)},
			"rotation": posmod(rotation, 4),
			"world_position": snap.world_position,
			"snap_distance": snap.distance,
			"reason": "超出棋盘",
		}
	var preview: Dictionary = simulation.preview_placement(module_kind, snap.grid, rotation)
	preview["world_position"] = snap.world_position
	preview["snap_distance"] = snap.distance
	return preview

func deploy_module_at_cell(module_kind: String, grid_position: Vector2i, rotation := 0) -> String:
	return deploy_module(module_kind, cell_to_world(grid_position), rotation)

func deploy_module(module_kind: String, world_position: Vector3, rotation := 0) -> String:
	var preview := preview_deployment(module_kind, world_position, rotation)
	var grid_position: Vector2i = _state_grid(preview)
	if not bool(preview.get("valid", false)):
		deployment_rejected.emit(module_kind, grid_position, str(preview.get("reason", "invalid")))
		return ""
	var module_id := str(simulation.build_module(module_kind, grid_position, rotation))
	if module_id.is_empty():
		deployment_rejected.emit(module_kind, grid_position, str(simulation.last_failure_reason))
		return ""
	sync_snapshot(simulation.get_snapshot())
	deployment_snapped.emit(module_id, grid_position, preview.world_position)
	return module_id

func deploy_bench_item_at_cell(bench_index: int, grid_position: Vector2i, rotation := 0) -> String:
	if simulation == null:
		return ""
	var module_id := str(simulation.deploy_bench_item(bench_index, grid_position, rotation))
	if not module_id.is_empty():
		sync_snapshot(simulation.get_snapshot())
		deployment_snapped.emit(module_id, grid_position, cell_to_world(grid_position))
	return module_id

func move_module_to_cell(module_id: String, grid_position: Vector2i) -> bool:
	if simulation == null or not simulation.modules.has(module_id):
		deployment_rejected.emit(module_id, grid_position, "module_missing")
		return false
	var state: Dictionary = simulation.modules[module_id]
	var preview: Dictionary = simulation.preview_placement(str(state.get("kind", "")), grid_position, int(state.get("rotation", 0)), module_id)
	if not bool(preview.get("valid", false)):
		deployment_rejected.emit(str(state.get("kind", module_id)), grid_position, str(preview.get("reason", "invalid_move")))
		return false
	var moved: bool = bool(simulation.move_module(module_id, grid_position))
	if moved:
		sync_snapshot(simulation.get_snapshot())
		deployment_snapped.emit(module_id, grid_position, cell_to_world(grid_position))
	else:
		deployment_rejected.emit(str(state.get("kind", module_id)), grid_position, "simulation_rejected")
	return moved

func sync_snapshot(snapshot: Dictionary) -> void:
	_ensure_world_nodes()
	var modules_state := _state_map(snapshot.get("modules", {}))
	var enemies_state := _state_map(snapshot.get("enemies", {}))
	for id in module_areas.keys().duplicate():
		if not modules_state.has(id):
			var stale_module: Node = module_areas[id]
			module_areas.erase(id)
			stale_module.queue_free()
	for id in enemy_bodies.keys().duplicate():
		if not enemies_state.has(id):
			var stale_enemy: Node = enemy_bodies[id]
			enemy_bodies.erase(id)
			_collision_queries.erase(id)
			_collision_shapes.erase(id)
			_breach_seen.erase(id)
			stale_enemy.queue_free()
	_prune_contact_state(modules_state, enemies_state)
	for id in modules_state.keys():
		var area = module_areas.get(id)
		if area == null or not is_instance_valid(area):
			area = MODULE_AREA_SCRIPT.new()
			area.name = "ModuleArea3D_%s" % id
			module_container.add_child(area)
			module_areas[id] = area
		area.configure(modules_state[id], cell_to_world(_state_grid(modules_state[id])))
	for id in enemies_state.keys():
		var actor = enemy_bodies.get(id)
		if actor == null or not is_instance_valid(actor):
			actor = ENEMY_ACTOR_SCRIPT.new()
			actor.name = "EnemyActor3D_%s" % id
			enemy_container.add_child(actor)
			enemy_bodies[id] = actor
		actor.configure(enemies_state[id], route_curve)
		_ensure_collision_query(id, actor)

func step_world(delta: float) -> void:
	if not _ready_nodes:
		return
	for actor in enemy_bodies.values():
		if is_instance_valid(actor):
			actor.advance(delta)
	_update_hit_cooldowns(delta)
	_query_collisions()
	_check_breaches()

func query_modules_near(world_position: Vector3, radius: float) -> Array:
	var result: Array = []
	for id in module_areas.keys():
		var area = module_areas[id]
		if is_instance_valid(area) and not area.is_destroyed() and area.global_position.distance_to(world_position) <= radius + area.contact_radius:
			result.append(str(id))
	return result

func get_enemy_actor_count() -> int:
	return enemy_bodies.size()

func get_enemy_position(enemy_id: String) -> Vector3:
	var actor = enemy_bodies.get(enemy_id)
	return actor.global_position if actor != null and is_instance_valid(actor) else Vector3.INF

func _query_collisions() -> void:
	var touched: Dictionary = {}
	for enemy_id in enemy_bodies.keys():
		var actor = enemy_bodies[enemy_id]
		if not is_instance_valid(actor):
			continue
		for module_id in module_areas.keys():
			var area = module_areas[module_id]
			if is_instance_valid(area) and not area.is_destroyed() and actor.global_position.distance_to(area.global_position) <= area.contact_radius + actor.hit_radius:
				touched["%s:%s" % [enemy_id, module_id]] = enemy_id
		if is_inside_tree() and get_world_3d() != null:
			var query := _ensure_collision_query(enemy_id, actor)
			query.transform = Transform3D(Basis.IDENTITY, actor.global_position)
			query.collision_mask = MODULE_COLLISION_LAYER
			query.collide_with_areas = true
			var max_results := maxi(16, module_areas.size() * 2)
			for hit in get_world_3d().direct_space_state.intersect_shape(query, max_results):
				var collider: Object = hit.get("collider")
				if collider != null and collider.has_method("get_module_id"):
					touched["%s:%s" % [enemy_id, collider.get_module_id()]] = enemy_id
	for key in touched.keys():
		var ids := str(key).split(":")
		if ids.size() == 2:
			_register_hit(ids[0], ids[1])

func _register_hit(enemy_id: String, module_id: String) -> void:
	var key := "%s:%s" % [enemy_id, module_id]
	if float(_hit_cooldowns.get(key, 0.0)) > 0.0 or simulation == null:
		return
	var area = module_areas.get(module_id)
	if area == null or not is_instance_valid(area) or area.is_destroyed():
		return
	var enemy_state: Dictionary = _state_map(simulation.get_snapshot().get("enemies", {})).get(enemy_id, {})
	var damage := maxi(1, int(enemy_state.get("damage", 1)))
	area.receive_hit(enemy_id, damage)
	var actor = enemy_bodies.get(enemy_id)
	if actor != null and is_instance_valid(actor) and actor.has_method("flash_hit"):
		actor.flash_hit()
	_hit_cooldowns[key] = 0.35
	enemy_hit.emit(enemy_id, module_id, damage)

func _ensure_collision_query(enemy_id: String, actor: Node) -> PhysicsShapeQueryParameters3D:
	var shape = _collision_shapes.get(enemy_id)
	var radius := maxf(0.01, float(actor.get("hit_radius")))
	if shape == null or not is_equal_approx(float(shape.radius), radius):
		shape = SphereShape3D.new()
		shape.radius = radius
		_collision_shapes[enemy_id] = shape
	var query: PhysicsShapeQueryParameters3D = _collision_queries.get(enemy_id)
	if query == null:
		query = PhysicsShapeQueryParameters3D.new()
		_collision_queries[enemy_id] = query
	query.shape = shape
	return query

func _prune_contact_state(modules_state: Dictionary, enemies_state: Dictionary) -> void:
	for enemy_id in _breach_seen.keys().duplicate():
		if not enemies_state.has(enemy_id):
			_breach_seen.erase(enemy_id)
	for key in _hit_cooldowns.keys().duplicate():
		var ids := str(key).split(":")
		if ids.size() != 2 or not enemies_state.has(ids[0]) or not modules_state.has(ids[1]):
			_hit_cooldowns.erase(key)

func _update_hit_cooldowns(delta: float) -> void:
	for key in _hit_cooldowns.keys().duplicate():
		var remaining := float(_hit_cooldowns[key]) - maxf(delta, 0.0)
		if remaining <= 0.0:
			_hit_cooldowns.erase(key)
		else:
			_hit_cooldowns[key] = remaining

func _check_breaches() -> void:
	if simulation == null:
		return
	for id in enemy_bodies.keys():
		var actor = enemy_bodies[id]
		if not is_instance_valid(actor):
			continue
		var at_core: bool = actor.get_path_progress() >= 0.995
		if core_hit_area != null:
			at_core = at_core and actor.global_position.distance_to(core_hit_area.global_position) <= CELL_SIZE * 0.9
		if not at_core or _breach_seen.has(id):
			continue
		_breach_seen[id] = true
		var state: Dictionary = _state_map(simulation.get_snapshot().get("enemies", {})).get(id, {})
		enemy_breached.emit(str(id), maxi(1, int(state.get("damage", 1))))

func _state_map(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	var result: Dictionary = {}
	if value is Array:
		for item in value:
			if item is Dictionary:
				var item_id := str(item.get("id", ""))
				if not item_id.is_empty():
					result[item_id] = item
	return result

func _state_grid(state: Dictionary) -> Vector2i:
	var grid: Dictionary = state.get("grid", {})
	if grid.is_empty() and state.has("cell"):
		var cell: Vector2i = state.get("cell", Vector2i.ZERO)
		return cell
	return Vector2i(int(grid.get("x", 0)), int(grid.get("y", 0)))
