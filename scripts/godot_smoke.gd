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
	var battle_view_loaded := false
	var battle_view_node: Node = null
	var overlay_loaded := false
	var battle_world_loaded := false
	var camera_contract_loaded := false
	var runtime_camera: Node = null
	for child: Node in instance.get_children():
		if child.get_script() != null and child.get_script().resource_path == "res://godot/battle_view.gd":
			battle_view_loaded = true
			battle_view_node = child
			for nested: Node in child.get_children():
				if nested.get_script() != null and nested.get_script().resource_path == "res://godot/battle_ui_overlay.gd":
					overlay_loaded = true
		if child.get_script() != null and child.get_script().resource_path == "res://gameplay/world/battle_world_3d.gd":
			battle_world_loaded = true
			var camera := child.get_node_or_null("BattleCamera3D")
			runtime_camera = camera if camera != null else child.get_node_or_null("Camera3D")
			if camera != null and camera.has_method("rotate_orbit") and camera.has_method("zoom_by") and camera.has_method("get_orbit_yaw") and camera.has_method("get_zoom_distance"):
				camera_contract_loaded = true
	if not battle_view_loaded:
		_fail("BattleView script could not be instantiated")
		return
	if not overlay_loaded:
		_fail("BattleUIOverlay script could not be instantiated")
		return
	if not battle_world_loaded:
		_fail("3D runtime world script could not be instantiated")
		return
	if not camera_contract_loaded:
		_fail("3D runtime camera orbit/zoom contract is missing")
		return
	if battle_view_node == null or not battle_view_node.has_method("set_battle_world") or not battle_view_node.has_method("_rotate_battle_camera") or not battle_view_node.has_method("_zoom_battle_camera"):
		_fail("BattleView camera input wiring is missing")
		return
	var battle_view_source_file := FileAccess.open("res://godot/battle_view.gd", FileAccess.READ)
	if battle_view_source_file == null:
		_fail("BattleView source could not be opened")
		return
	var battle_view_source := battle_view_source_file.get_as_text()
	if not battle_view_source.contains("MOUSE_BUTTON_MASK_LEFT"):
		_fail("desktop left-drag camera contract is missing")
		return
	if not battle_view_source.contains("if event.button_index == MOUSE_BUTTON_RIGHT:"):
		_fail("desktop right-button release camera contract is missing")
		return
	if runtime_camera == null or battle_view_node == null:
		_fail("desktop camera input test could not find runtime nodes")
		return
	var right_press := InputEventMouseButton.new()
	right_press.button_index = MOUSE_BUTTON_RIGHT
	right_press.pressed = true
	battle_view_node.call("_gui_input", right_press)
	var orbit_before: float = runtime_camera.get_orbit_yaw()
	var orbit_motion := InputEventMouseMotion.new()
	orbit_motion.relative = Vector2(18.0, 0.0)
	orbit_motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	battle_view_node.call("_gui_input", orbit_motion)
	if is_equal_approx(orbit_before, float(runtime_camera.get_orbit_yaw())):
		_fail("desktop right-button orbit motion was not forwarded")
		return
	var right_release := InputEventMouseButton.new()
	right_release.button_index = MOUSE_BUTTON_RIGHT
	right_release.pressed = false
	battle_view_node.call("_gui_input", right_release)
	var orbit_after_release: float = runtime_camera.get_orbit_yaw()
	battle_view_node.call("_gui_input", orbit_motion)
	if not is_equal_approx(orbit_after_release, float(runtime_camera.get_orbit_yaw())):
		_fail("desktop right-button release did not stop orbit motion")
		return
	var child_count := instance.get_child_count()
	instance.free()
	print("GODOT_SMOKE_OK children=%d root_script=res://scripts/game_root.gd battle_view=true overlay=true world_3d=true camera_orbit_zoom=true camera_input=true left_drag=true" % child_count)
	quit(0)

func _fail(message: String) -> void:
	push_error("GODOT_SMOKE_FAILED: " + message)
	quit(1)
