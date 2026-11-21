extends SceneTree

## CI smoke test for the desktop entry point.
## Godot may return exit code 0 after a script-load failure, so this probe
## explicitly checks that the packed scene and composition root instantiate.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("main scene could not be loaded")
		return
	var instance := packed.instantiate()
	if instance == null or instance.get_script() == null:
		_fail("composition root script could not be instantiated")
		return
	root.add_child(instance)
	await process_frame
	if instance.get_child_count() < 1:
		_fail("composition root did not create the BattleView")
		return
	print("GODOT_SMOKE_OK children=%d root_script=%s" % [instance.get_child_count(), instance.get_script().resource_path])
	quit(0)

func _fail(message: String) -> void:
	push_error("GODOT_SMOKE_FAILED: " + message)
	quit(1)
