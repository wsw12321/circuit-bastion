extends SceneTree

## Headless contract for the minimal 3D battlefield slice.
## Android export verification runs the same scene and collision contract.

const Simulation := preload("res://scripts/simulation.gd")
const BattlefieldScene := preload("res://godot/scenes/battle_3d.tscn")

var hit_count := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := BattlefieldScene
	if not _assert(packed != null, "3D battlefield scene could not be loaded"):
		return
	var instance := packed.instantiate()
	if not _assert(instance is Node3D, "3D battlefield root must be Node3D"):
		return
	root.add_child(instance)
	await process_frame
	var world = instance
	var camera = instance.get_node_or_null("Camera3D")
	if not _assert(camera != null and camera.has_method("rotate_orbit"), "orbit camera must be present"):
		return
	if not _assert(float(camera.global_position.y) > float(camera.target.y), "orbit camera must remain above the battlefield"):
		return
	var yaw_before: float = camera.get_orbit_yaw()
	camera.rotate_orbit(Vector2(18.0, -8.0))
	if not _assert(not is_equal_approx(yaw_before, camera.get_orbit_yaw()), "camera rotation should update yaw"):
		return
	var zoom_before: float = camera.get_zoom_distance()
	camera.zoom_by(-3.0)
	if not _assert(camera.get_zoom_distance() < zoom_before, "camera zoom should reduce distance"):
		return
	if not _assert(camera.global_position.y > 0.0, "camera should remain above the battlefield"):
		return

	var simulation = Simulation.new(7331)
	var module_id: String = simulation.add_module("scanner", Vector2i(0, 3))
	if not _assert(simulation.start_battle(), "3D simulation should start"):
		return
	world.setup(simulation)
	world.sync_snapshot(simulation.get_snapshot())
	world.enemy_hit.connect(_on_enemy_hit)
	if not _assert(world.get_enemy_actor_count() > 0, "3D enemy actors should spawn"):
		return
	var enemy_id := str(world.enemy_bodies.keys()[0])
	var actor = world.enemy_bodies[enemy_id]
	var module_area = world.module_areas[module_id]
	if not _assert(actor.collision_layer == 2 and actor.collision_mask == 4, "3D enemy collision contract is invalid"):
		return
	if not _assert(module_area.collision_layer == 4 and module_area.collision_mask == 2, "3D module collision contract is invalid"):
		return
	if not _assert(world.query_modules_near(world.cell_to_world(Vector2i(0, 3)), 0.1).has(module_id), "3D module proximity query should resolve"):
		return

	var initial_position: Vector3 = world.get_enemy_position(enemy_id)
	var moved := false
	for _step in 40:
		simulation.advance(0.1)
		world.sync_snapshot(simulation.get_snapshot())
		world.step_world(0.1)
		var current_position: Vector3 = world.get_enemy_position(enemy_id)
		if current_position != Vector3.INF and initial_position.distance_to(current_position) > 0.01:
			moved = true
	if not _assert(moved, "3D enemy path follower should move smoothly"):
		return
	if not _assert(hit_count >= 1, "3D collision query should emit a hit"):
		return
	var actor_count: int = world.get_enemy_actor_count()
	instance.free()
	print("WORLD_3D_OK camera=orbit-zoom actors=%d hits=%d" % [actor_count, hit_count])
	quit(0)

func _on_enemy_hit(_enemy_id: String, _module_id: String, _damage: int) -> void:
	hit_count += 1

func _assert(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("WORLD_3D_FAILED: " + message)
	quit(1)
	return false
