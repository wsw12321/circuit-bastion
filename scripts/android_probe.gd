extends SceneTree

## Headless contract check for the Android export preset and touch view.

const MOBILE_VIEW_SCRIPT := preload("res://godot/mobile_battle_view.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var preset_file := FileAccess.open("res://export_presets.cfg", FileAccess.READ)
	if preset_file == null:
		_fail("export_presets.cfg could not be opened")
		return
	var preset_text := preset_file.get_as_text()
	for required in [
		"[preset.2]",
		'name="Android"',
		'platform="Android"',
		'architectures/arm64-v8a=true',
		'package/unique_name="com.circuitbastion.game"',
	]:
		if not preset_text.contains(required):
			_fail("missing Android preset field: " + required)
			return
	var view = MOBILE_VIEW_SCRIPT.new()
	if view == null or not view.has_method("_cell_at_mobile"):
		_fail("mobile BattleView could not be instantiated")
		return
	print("ANDROID_SMOKE_OK preset=Android arm64=enabled touch=screen")
	quit(0)

func _fail(message: String) -> void:
	push_error("ANDROID_SMOKE_FAILED: " + message)
	quit(1)
