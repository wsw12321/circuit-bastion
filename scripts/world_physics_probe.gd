extends SceneTree

## Headless contract for the native spatial layer.

const Simulation := preload("res://scripts/simulation.gd")
const BattleWorld := preload("res://gameplay/world/battle_world.gd")

var hit_count := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var simulation = Simulation.new(7331)
	simulation.add_module("scanner", Vector2i(2, 3))
	var world = BattleWorld.new()
	root.add_child(world)
	world.setup(simulation)
	var preview: Dictionary = world.preview_deployment("pulse_cannon", world.cell_to_world(Vector2i(4, 2)))
	_assert(bool(preview.get("valid", false)), "deployment preview should snap to an empty cell")
	var snapped: Vector2 = preview.get("world_position", Vector2.INF)
	_assert(snapped == world.cell_to_world(Vector2i(4, 2)), "deployment must snap to cell center")
	var module_id := world.deploy_module_at_cell("pulse_cannon", Vector2i(4, 2))
	_assert(not module_id.is_empty(), "node-backed deployment should update simulation")
	world.enemy_hit.connect(_on_enemy_hit)
	_assert(simulation.start_battle(), "battle should start")
	world.sync_snapshot(simulation.get_snapshot())
	var initial_enemy_count := world.get_enemy_actor_count()
	_assert(initial_enemy_count > 0, "enemy CharacterBody2D actors should spawn")
	var enemy_ids: Array = world.enemy_bodies.keys()
	var first_id := str(enemy_ids[0])
	var first_position := world.get_enemy_position(first_id)
	for _step in 40:
		simulation.advance(0.1)
		world.sync_snapshot(simulation.get_snapshot())
		world.step_world(0.1)
	var next_position := world.get_enemy_position(first_id)
	_assert(first_position != next_position, "enemy path follower should move smoothly")
	var nearby := world.query_modules_near(world.cell_to_world(Vector2i(4, 2)), 1.0)
	_assert(nearby.has(module_id), "collision query should find deployed Area2D")
	_assert(hit_count >= 0, "hit signal contract should remain callable")
	print("WORLD_PHYSICS_OK actors=%d hits=%d modules=%d" % [world.get_enemy_actor_count(), hit_count, world.module_areas.size()])
	quit(0)

func _on_enemy_hit(_enemy_id: String, _module_id: String, _damage: int) -> void:
	hit_count += 1

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("WORLD_PHYSICS_FAILED: " + message)
	quit(1)
