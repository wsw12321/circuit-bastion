extends SceneTree

## Headless contract for the native Godot 4 spatial battlefield.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("main scene could not be loaded")
		return
	var instance := packed.instantiate()
	root.add_child(instance)
	await process_frame
	var battlefield := instance.get_node_or_null("Battlefield3D")
	if battlefield == null or not battlefield is Node3D:
		_fail("Battlefield3D Node3D is missing")
		return
	var camera := battlefield.get_node_or_null("Camera3D")
	var environment := battlefield.get_node_or_null("WorldEnvironment")
	var ground := battlefield.get_node_or_null("Ground")
	if camera == null or not camera is Camera3D:
		_fail("Camera3D is missing")
		return
	if environment == null or not environment is WorldEnvironment:
		_fail("WorldEnvironment is missing")
		return
	if ground == null or not ground is MeshInstance3D:
		_fail("ground MeshInstance3D is missing")
		return
	if not battlefield.has_method("get_camera_state"):
		_fail("camera gesture API is missing")
		return
	print("GODOT_3D_SMOKE_OK node3d=true camera3d=true environment=true mesh=true gestures=true")
	instance.queue_free()
	quit(0)

func _fail(message: String) -> void:
	push_error("GODOT_3D_SMOKE_FAILED: " + message)
	quit(1)
