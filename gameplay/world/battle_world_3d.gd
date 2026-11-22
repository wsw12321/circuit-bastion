class_name BastionBattleWorld3D
extends Node3D

## Minimal 3D spatial layer for the Godot battlefield.
## The deterministic simulation remains the source of truth. This node owns
## presentation paths, physics-backed actors, module areas, and contact queries.

signal enemy_hit(enemy_id: String, module_id: String, damage: int)
signal enemy_breached(enemy_id: String, damage: int)

const ENEMY_ACTOR_SCRIPT := preload("res://gameplay/world/enemy_actor_3d.gd")
const MODULE_AREA_SCRIPT := preload("res://gameplay/world/module_area_3d.gd")

const GRID_COLUMNS := 8
const GRID_ROWS := 6
const CELL_SIZE := 1.2
const BOARD_ORIGIN := Vector2(-4.8, -3.6)
const ENEMY_COLLISION_LAYER := 2
const MODULE_COLLISION_LAYER := 4

var simulation: RefCounted
var route_path: Path3D
var route_curve: Curve3D
var enemy_container: Node3D
var module_container: Node3D
var enemy_bodies: Dictionary = {}
var module_areas: Dictionary = {}
var _hit_cooldowns: Dictionary = {}
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
	var floor_body := StaticBody3D.new()
	floor_body.name = "BattlefieldFloor"
	floor_body.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(GRID_COLUMNS * CELL_SIZE + 2.0, 0.2, GRID_ROWS * CELL_SIZE + 2.0)
	floor_shape.shape = floor_box
	floor_shape.position.y = -0.2
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	_ready_nodes = true

func cell_to_world(grid_position: Vector2i) -> Vector3:
	return Vector3(
		BOARD_ORIGIN.x + (float(grid_position.x) + 0.5) * CELL_SIZE,
		0.0,
		BOARD_ORIGIN.y + (float(grid_position.y) + 0.5) * CELL_SIZE
	)

func sync_snapshot(snapshot: Dictionary) -> void:
	_ensure_world_nodes()
	var modules_state := _state_map(snapshot.get("modules", {}))
	var enemies_state := _state_map(snapshot.get("enemies", {}))
	for module_id in module_areas.keys().duplicate():
		if not modules_state.has(module_id):
			var stale_module: Node = module_areas[module_id]
			module_areas.erase(module_id)
			stale_module.queue_free()
	for enemy_id in enemy_bodies.keys().duplicate():
		if not enemies_state.has(enemy_id):
			var stale_enemy: Node = enemy_bodies[enemy_id]
			enemy_bodies.erase(enemy_id)
			stale_enemy.queue_free()
	for module_id in modules_state.keys():
		var module_state: Dictionary = modules_state[module_id]
		var module_area: BastionModuleArea3D = module_areas.get(module_id)
		if module_area == null or not is_instance_valid(module_area):
			module_area = MODULE_AREA_SCRIPT.new()
			module_area.name = "ModuleArea3D_%s" % module_id
			module_container.add_child(module_area)
			module_areas[module_id] = module_area
		module_area.configure(module_state, cell_to_world(_state_grid(module_state)))
	for enemy_id in enemies_state.keys():
		var enemy_state: Dictionary = enemies_state[enemy_id]
		var actor: BastionEnemyActor3D = enemy_bodies.get(enemy_id)
		if actor == null or not is_instance_valid(actor):
			actor = ENEMY_ACTOR_SCRIPT.new()
			actor.name = "EnemyActor3D_%s" % enemy_id
			enemy_container.add_child(actor)
			enemy_bodies[enemy_id] = actor
		actor.configure(enemy_state, route_curve)

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
	for module_id in module_areas.keys():
		var area: BastionModuleArea3D = module_areas[module_id]
		if is_instance_valid(area) and area.global_position.distance_to(world_position) <= radius + area.contact_radius:
			result.append(str(module_id))
	return result

func get_enemy_actor_count() -> int:
	return enemy_bodies.size()

func get_enemy_position(enemy_id: String) -> Vector3:
	var actor: BastionEnemyActor3D = enemy_bodies.get(enemy_id)
	return actor.global_position if actor != null and is_instance_valid(actor) else Vector3.INF

func _query_collisions() -> void:
	var touched: Dictionary = {}
	for enemy_id in enemy_bodies.keys():
		var actor: BastionEnemyActor3D = enemy_bodies[enemy_id]
		if not is_instance_valid(actor):
			continue
		for module_id in module_areas.keys():
			var module_area: BastionModuleArea3D = module_areas[module_id]
			if is_instance_valid(module_area) and actor.global_position.distance_to(module_area.global_position) <= module_area.contact_radius + actor.hit_radius:
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
	if float(_hit_cooldowns.get(key, 0.0)) > 0.0:
		return
	var module_area: BastionModuleArea3D = module_areas.get(module_id)
	if module_area == null or not is_instance_valid(module_area):
		return
	var enemy_state: Dictionary = _state_map(simulation.get_snapshot().get("enemies", {})).get(enemy_id, {})
	var damage := maxi(1, int(enemy_state.get("damage", 1)))
	module_area.receive_hit(enemy_id, damage)
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
	for enemy_id in enemy_bodies.keys():
		var actor: BastionEnemyActor3D = enemy_bodies[enemy_id]
		if not is_instance_valid(actor) or actor.get_path_progress() < 0.995:
			continue
		enemy_breached.emit(str(enemy_id), 1)

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
