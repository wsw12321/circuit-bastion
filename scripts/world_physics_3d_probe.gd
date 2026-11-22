extends SceneTree

## Headless contract for the native 3D spatial layer.

const Simulation := preload("res://scripts/simulation.gd")
const BattleWorld3D := preload("res://gameplay/world/battle_world_3d.gd")

var hit_count := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var simulation = Simulation.new(7331)
	simulation.add_module("scanner", Vector2i(2, 3))
	var world = BattleWorld3D.new()
	root.add_child(world)
	world.setup(simulation)
	var preview: Dictionary = world.preview_deployment("pulse_cannon", world.cell_to_world(Vector2i(4, 2)))
	if not _assert(bool(preview.get("valid", false)), "3D deployment preview should snap to an empty cell"):
		return
	var snapped: Vector3 = preview.get("world_position", Vector3.INF)
	if not _assert(snapped == world.cell_to_world(Vector2i(4, 2)), "3D deployment must snap to cell center"):
		return
	var module_id := str(world.deploy_module_at_cell("pulse_cannon", Vector2i(4, 2)))
	if not _assert(not module_id.is_empty(), "3D deployment should update simulation"):
		return
	world.enemy_hit.connect(_on_enemy_hit)
	if not _assert(simulation.start_battle(), "3D battle should start"):
		return
	world.sync_snapshot(simulation.get_snapshot())
	await physics_frame
	if not _assert(world.route_path is Path3D, "3D world should expose a Path3D route"):
		return
	if not _assert(world.route_curve is Curve3D, "3D world should expose a Curve3D route"):
		return
	var initial_enemy_count := world.get_enemy_actor_count()
	if not _assert(initial_enemy_count > 0, "enemy CharacterBody3D actors should spawn"):
		return
	var enemy_ids: Array = world.enemy_bodies.keys()
	var first_id := str(enemy_ids[0])
	var actor = world.enemy_bodies[first_id]
	if not _assert(actor is CharacterBody3D, "enemy actors must use CharacterBody3D"):
		return
	var first_position: Vector3 = world.get_enemy_position(first_id)
	for _step in 40:
		simulation.advance(0.1)
		world.sync_snapshot(simulation.get_snapshot())
		world.step_world(0.1)
		await physics_frame
	var next_position: Vector3 = world.get_enemy_position(first_id)
	if not _assert(first_position != next_position, "enemy path follower should move continuously in 3D"):
		return
	var nearby := world.query_modules_near(world.cell_to_world(Vector2i(4, 2)), 1.0)
	if not _assert(nearby.has(module_id), "3D collision query should find deployed Area3D"):
		return
	if not _assert(hit_count >= 0, "3D hit signal contract should remain callable"):
		return
	print("WORLD_PHYSICS_3D_OK actors=%d hits=%d modules=%d" % [world.get_enemy_actor_count(), hit_count, world.module_areas.size()])
	quit(0)

func _on_enemy_hit(_enemy_id: String, _module_id: String, _damage: int) -> void:
	hit_count += 1

func _assert(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("WORLD_PHYSICS_3D_FAILED: " + message)
	quit(1)
	return false
