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
var route_path: Path3D
var route_curve: Curve3D
var enemy_container: Node3D
var module_container: Node3D
var core_hit_area: Area3D
var enemy_bodies: Dictionary = {}
var module_areas: Dictionary = {}
var _hit_cooldowns: Dictionary = {}
var _breach_seen: Dictionary = {}
var _ready_nodes := false

func _ready() -> void:
	_ensure_world_nodes()

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
	_create_ground()
	_create_camera()
	_create_core_area()
	_ready_nodes = true

func _create_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(GRID_COLUMNS * CELL_SIZE, 0.2, GRID_ROWS * CELL_SIZE)
	shape.shape = box
	shape.position.y = -0.1
	ground.add_child(shape)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#102a35")
	material.emission_enabled = true
	material.emission = Color("#06131a")
	mesh_instance.material_override = material
	ground.add_child(mesh_instance)
	add_child(ground)

func _create_camera() -> void:
	var camera = get_node_or_null("Camera3D")
	if camera == null:
		camera = CAMERA_SCRIPT.new()
		camera.name = "BattleCamera3D"
		add_child(camera)
	camera.target = Vector3(0.0, 0.0, 0.0)
	camera.zoom_distance = 18.0
	camera.target_zoom_distance = 18.0
	camera.current = true

	var directional = get_node_or_null("BattleLight3D")
	if directional == null:
		for child in get_children():
			if child is DirectionalLight3D:
				directional = child
				break
	if directional == null:
		directional = DirectionalLight3D.new()
		directional.name = "BattleLight3D"
		add_child(directional)
	directional.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	directional.light_energy = 1.1

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

func cell_to_world(grid_position: Vector2i) -> Vector3:
	return BOARD_ORIGIN + Vector3((float(grid_position.x) + 0.5) * CELL_SIZE, 0.0, (float(grid_position.y) + 0.5) * CELL_SIZE)

func world_to_cell(world_position: Vector3) -> Vector2i:
	var local := (world_position - BOARD_ORIGIN) / CELL_SIZE
	return Vector2i(floor(local.x), floor(local.z))

func snap_to_grid(world_position: Vector3) -> Dictionary:
	var grid_position := world_to_cell(world_position)
	var clamped := Vector2i(clampi(grid_position.x, 0, GRID_COLUMNS - 1), clampi(grid_position.y, 0, GRID_ROWS - 1))
	return {"grid": clamped, "world_position": cell_to_world(clamped), "distance": world_position.distance_to(cell_to_world(clamped))}

func preview_deployment(module_kind: String, world_position: Vector3, rotation := 0) -> Dictionary:
	if simulation == null:
		return {"valid": false, "reason": "simulation_unavailable"}
	var snap := snap_to_grid(world_position)
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
		return false
	var state: Dictionary = simulation.modules[module_id]
	var preview: Dictionary = simulation.preview_placement(str(state.get("kind", "")), grid_position, int(state.get("rotation", 0)), module_id)
	if not bool(preview.get("valid", false)):
		return false
	var moved: bool = bool(simulation.move_module(module_id, grid_position))
	if moved:
		sync_snapshot(simulation.get_snapshot())
		deployment_snapped.emit(module_id, grid_position, cell_to_world(grid_position))
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
			stale_enemy.queue_free()
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
		if is_instance_valid(area) and area.global_position.distance_to(world_position) <= radius + area.contact_radius:
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
			var query_shape := SphereShape3D.new()
			query_shape.radius = actor.hit_radius
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = query_shape
			query.transform = Transform3D(Basis.IDENTITY, actor.global_position)
			query.collision_mask = MODULE_COLLISION_LAYER
			query.collide_with_areas = true
			for hit in get_world_3d().direct_space_state.intersect_shape(query, 16):
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
	_hit_cooldowns[key] = 0.35
	enemy_hit.emit(enemy_id, module_id, damage)

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
