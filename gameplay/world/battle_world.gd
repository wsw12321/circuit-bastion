class_name BastionBattleWorld
extends Node2D

## Runtime spatial layer for Circuit Bastion.
## Simulation dictionaries remain the deterministic save/replay contract, while
## this node owns live paths, colliders, snapping and contact queries.

signal deployment_snapped(module_id: String, grid_position: Vector2i, world_position: Vector2)
signal deployment_rejected(kind: String, grid_position: Vector2i, reason: String)
signal enemy_hit(enemy_id: String, module_id: String, damage: int)
signal enemy_breached(enemy_id: String, damage: int)

const ENEMY_ACTOR_SCRIPT := preload("res://gameplay/world/enemy_actor.gd")
const MODULE_AREA_SCRIPT := preload("res://gameplay/world/module_area.gd")

const GRID_COLUMNS := 8
const GRID_ROWS := 6
const CELL_SIZE := 96.0
const BOARD_ORIGIN := Vector2(80.0, 120.0)
const ENEMY_COLLISION_LAYER := 2
const MODULE_COLLISION_LAYER := 4

var simulation: RefCounted
var route_path: Path2D
var route_curve: Curve2D
var enemy_container: Node2D
var module_container: Node2D
var core_hit_area: Area2D
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
	enemy_container = Node2D.new()
	enemy_container.name = "EnemyActors"
	add_child(enemy_container)
	module_container = Node2D.new()
	module_container.name = "ModuleAreas"
	add_child(module_container)
	route_path = Path2D.new()
	route_path.name = "EnemyRoute"
	route_curve = Curve2D.new()
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
	core_hit_area = Area2D.new()
	core_hit_area.name = "CoreHitArea"
	core_hit_area.collision_layer = 8
	core_hit_area.collision_mask = ENEMY_COLLISION_LAYER
	core_hit_area.monitoring = true
	var core_shape := CollisionShape2D.new()
	var core_circle := CircleShape2D.new()
	core_circle.radius = CELL_SIZE * 0.38
	core_shape.shape = core_circle
	core_hit_area.position = cell_to_world(Vector2i(7, 3))
	core_hit_area.add_child(core_shape)
	add_child(core_hit_area)
	_ready_nodes = true

func cell_to_world(grid_position: Vector2i) -> Vector2:
	return BOARD_ORIGIN + (Vector2(grid_position) + Vector2(0.5, 0.5)) * CELL_SIZE

func world_to_cell(world_position: Vector2) -> Vector2i:
	var local := (world_position - BOARD_ORIGIN) / CELL_SIZE
	return Vector2i(floor(local.x), floor(local.y))

func snap_to_grid(world_position: Vector2) -> Dictionary:
	var grid_position := world_to_cell(world_position)
	var clamped := Vector2i(
		clampi(grid_position.x, 0, GRID_COLUMNS - 1),
		clampi(grid_position.y, 0, GRID_ROWS - 1)
	)
	return {
		"grid": clamped,
		"world_position": cell_to_world(clamped),
		"distance": world_position.distance_to(cell_to_world(clamped)),
	}

func preview_deployment(module_kind: String, world_position: Vector2, rotation := 0) -> Dictionary:
	if simulation == null:
		return {"valid": false, "reason": "simulation_unavailable"}
	var snap := snap_to_grid(world_position)
	var preview: Dictionary = simulation.preview_placement(module_kind, snap.grid, rotation)
	preview["world_position"] = snap.world_position
	preview["snap_distance"] = snap.distance
	return preview

func deploy_module_at_cell(module_kind: String, grid_position: Vector2i, rotation := 0) -> String:
	return deploy_module(module_kind, cell_to_world(grid_position), rotation)

func deploy_module(module_kind: String, world_position: Vector2, rotation := 0) -> String:
	var preview := preview_deployment(module_kind, world_position, rotation)
	var grid_position: Vector2i = preview.grid
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
	if simulation == null:
		return false
	var preview: Dictionary = simulation.preview_placement(
		str(simulation.modules.get(module_id, {}).get("kind", "")),
		grid_position,
		int(simulation.modules.get(module_id, {}).get("rotation", 0)),
		module_id
	)
	if not bool(preview.get("valid", false)):
		deployment_rejected.emit(str(simulation.modules.get(module_id, {}).get("kind", "")), grid_position, str(preview.get("reason", "invalid")))
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
		var module_area: Area2D = module_areas.get(module_id)
		if module_area == null or not is_instance_valid(module_area):
			module_area = MODULE_AREA_SCRIPT.new()
			module_area.name = "ModuleArea_%s" % module_id
			module_container.add_child(module_area)
			module_areas[module_id] = module_area
		module_area.configure(module_state, cell_to_world(_state_grid(module_state)))
	for enemy_id in enemies_state.keys():
		var enemy_state: Dictionary = enemies_state[enemy_id]
		var actor: CharacterBody2D = enemy_bodies.get(enemy_id)
		if actor == null or not is_instance_valid(actor):
			actor = ENEMY_ACTOR_SCRIPT.new()
			actor.name = "EnemyActor_%s" % enemy_id
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

func query_modules_near(world_position: Vector2, radius: float) -> Array:
	var result: Array = []
	for module_id in module_areas.keys():
		var area: Area2D = module_areas[module_id]
		if is_instance_valid(area) and area.global_position.distance_to(world_position) <= radius + area.contact_radius:
			result.append(str(module_id))
	return result

func get_enemy_actor_count() -> int:
	return enemy_bodies.size()

func get_enemy_position(enemy_id: String) -> Vector2:
	var actor: CharacterBody2D = enemy_bodies.get(enemy_id)
	return actor.global_position if actor != null and is_instance_valid(actor) else Vector2.INF

func _query_collisions() -> void:
	var touched: Dictionary = {}
	for module_id in module_areas.keys():
		var module_area: Area2D = module_areas[module_id]
		if not is_instance_valid(module_area):
			continue
		for body in module_area.get_overlapping_bodies():
			if body is CharacterBody2D and body.has_method("get_enemy_id"):
				touched["%s:%s" % [body.get_enemy_id(), module_id]] = body.get_enemy_id()
	for enemy_id in enemy_bodies.keys():
		var actor: CharacterBody2D = enemy_bodies[enemy_id]
		if not is_instance_valid(actor):
			continue
		var actor_position: Vector2 = actor.global_position
		for module_id in module_areas.keys():
			var module_area: Area2D = module_areas[module_id]
			if is_instance_valid(module_area) and actor_position.distance_to(module_area.global_position) <= module_area.contact_radius + 14.0:
				touched["%s:%s" % [enemy_id, module_id]] = enemy_id
		if is_inside_tree():
			var query_shape := CircleShape2D.new()
			query_shape.radius = 14.0
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = query_shape
			query.transform = Transform2D(0.0, actor_position)
			query.collision_mask = MODULE_COLLISION_LAYER
			query.collide_with_areas = true
			var results := get_world_2d().direct_space_state.intersect_shape(query, 16)
			for hit in results:
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
	var module_area: Area2D = module_areas.get(module_id)
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
		var actor: CharacterBody2D = enemy_bodies[enemy_id]
		if not is_instance_valid(actor) or actor.get_path_progress() < 0.995:
			continue
		if _breach_seen.has(enemy_id):
			continue
		_breach_seen[enemy_id] = true
		var enemy_state: Dictionary = _state_map(simulation.get_snapshot().get("enemies", {})).get(enemy_id, {})
		enemy_breached.emit(enemy_id, maxi(1, int(enemy_state.get("damage", 1))))

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
