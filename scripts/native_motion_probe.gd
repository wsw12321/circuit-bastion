extends SceneTree

## Headless contract for the native Godot world.
##
## The deterministic simulation owns command state. This probe confirms that
## deployment and movement do not read the event log, while the Godot world
## still provides native nodes, collision shapes, and smooth body movement.

const CircuitSimulation = preload("res://scripts/simulation.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not _check_command_state():
		return

	var world := Node2D.new()
	world.name = "NativeMotionWorld"
	root.add_child(world)

	var wall := StaticBody2D.new()
	wall.name = "CollisionWall"
	var wall_shape := CollisionShape2D.new()
	wall_shape.name = "CollisionShape2D"
	var wall_rect := RectangleShape2D.new()
	wall_rect.size = Vector2(20.0, 160.0)
	wall_shape.shape = wall_rect
	wall.add_child(wall_shape)
	wall.position = Vector2(80.0, 0.0)
	world.add_child(wall)

	var blocker := CharacterBody2D.new()
	blocker.name = "CollisionActor"
	blocker.position = Vector2(-80.0, 0.0)
	var blocker_shape := CollisionShape2D.new()
	blocker_shape.name = "CollisionShape2D"
	var blocker_circle := CircleShape2D.new()
	blocker_circle.radius = 8.0
	blocker_shape.shape = blocker_circle
	blocker.add_child(blocker_shape)
	world.add_child(blocker)

	var mover := CharacterBody2D.new()
	mover.name = "SmoothActor"
	mover.position = Vector2(-140.0, 80.0)
	var mover_shape := CollisionShape2D.new()
	mover_shape.name = "CollisionShape2D"
	var mover_circle := CircleShape2D.new()
	mover_circle.radius = 6.0
	mover_shape.shape = mover_circle
	mover.add_child(mover_shape)
	world.add_child(mover)

	var deployed_module := Node2D.new()
	deployed_module.name = "DeployedModule"
	deployed_module.set_meta("deployed", true)
	var module_body := StaticBody2D.new()
	module_body.name = "CollisionBody"
	var module_shape := CollisionShape2D.new()
	module_shape.name = "CollisionShape2D"
	var module_rect := RectangleShape2D.new()
	module_rect.size = Vector2(16.0, 16.0)
	module_shape.shape = module_rect
	module_body.add_child(module_shape)
	deployed_module.add_child(module_body)
	deployed_module.position = Vector2(0.0, 160.0)
	world.add_child(deployed_module)

	await process_frame

	var collision = blocker.move_and_collide(Vector2(220.0, 0.0))
	if not _expect(collision != null, "CharacterBody2D did not collide with StaticBody2D"):
		return
	if not _expect(collision.get_collider() == wall, "collision collider was not the native wall"):
		return
	if not _expect(blocker.global_position.x < wall.global_position.x - 5.0, "collision actor crossed the wall"):
		return

	var previous := mover.global_position
	var target := Vector2(-40.0, 80.0)
	for _step in range(10):
		var desired := previous.move_toward(target, 10.0)
		var displacement := desired - previous
		var smooth_collision = mover.move_and_collide(displacement)
		if not _expect(smooth_collision == null, "smooth actor encountered an unexpected obstacle"):
			return
		var actual_step := mover.global_position.distance_to(previous)
		if not _expect(actual_step <= 10.01, "smooth actor moved farther than one fixed substep"):
			return
		previous = mover.global_position
	if not _expect(previous.distance_to(target) <= 0.05, "smooth actor did not reach its target"):
		return

	if not _expect(bool(deployed_module.get_meta("deployed", false)), "deployment node metadata was not retained"):
		return
	if not _expect(deployed_module.get_node_or_null("CollisionBody/CollisionShape2D") != null, "deployment collision shape is missing"):
		return

	print("NATIVE_MOTION_OK command_state=true nodes=CharacterBody2D+StaticBody2D collision=true smooth=true deployment=true")
	world.queue_free()
	quit(0)

func _check_command_state() -> bool:
	var simulation = CircuitSimulation.new(8128)
	simulation.event_log.clear()
	var module_id := str(simulation.build_module("pulse_cannon", Vector2i(2, 2)))
	if not _expect(not module_id.is_empty(), "simulation build command did not deploy a module"):
		return false
	simulation.event_log.clear()
	if not _expect(simulation.move_module(module_id, Vector2i(3, 2)), "simulation move command failed after event log reset"):
		return false
	var module_state: Dictionary = simulation.modules.get(module_id, {})
	var grid: Dictionary = module_state.get("grid", {})
	return _expect(int(grid.get("x", -1)) == 3 and int(grid.get("y", -1)) == 2, "module movement was not command-state driven")

func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false

func _fail(message: String) -> void:
	push_error("NATIVE_MOTION_FAILED: " + message)
	quit(1)
