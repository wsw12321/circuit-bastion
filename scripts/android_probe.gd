extends SceneTree

## Android export contract check against the current touch-capable BattleView.

const GameRoot = preload("res://scripts/game_root.gd")
const MobileBattleView = preload("res://godot/mobile_battle_view.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var preset_file := FileAccess.open("res://export_presets.cfg", FileAccess.READ)
	if preset_file == null:
		_fail("export_presets.cfg could not be opened")
		return
	var preset_text := preset_file.get_as_text()
	for required in [
		"[preset.2]", 'name="Android"', 'platform="Android"',
		"architectures/arm64-v8a=true", 'package/unique_name="com.circuitbastion.game"',
	]:
		if not preset_text.contains(required):
			_fail("missing Android preset field: " + required)
			return
	var sdk_root := OS.get_environment("ANDROID_SDK_ROOT")
	var sdk_probe_enabled := OS.get_environment("CIRCUIT_BASTION_ANDROID_SDK_PROBE") == "1"
	if sdk_probe_enabled:
		if sdk_root.is_empty():
			_fail("ANDROID_SDK_ROOT is not set for the Android SDK probe")
			return
		for required_path in [
			"cmdline-tools", "platform-tools", "platforms/android-34",
			"build-tools/34.0.0", "cmake/3.10.2.4988404", "ndk/23.2.8568313",
		]:
			if not DirAccess.dir_exists_absolute(sdk_root + "/" + required_path):
				_fail("missing Android SDK package: " + required_path)
				return
	var selected_script: Script = GameRoot.select_view_script(true)
	if selected_script == null or selected_script.resource_path != "res://godot/mobile_battle_view.gd":
		_fail("Android runtime must select MobileBattleView")
		return
	var view = selected_script.new()
	if view == null or not view.has_method("_cell_at_mobile"):
		_fail("touch-capable MobileBattleView could not be instantiated")
		return
	print("ANDROID_SMOKE_OK preset=Android arm64=enabled touch=screen")
	quit(0)

func _fail(message: String) -> void:
	push_error("ANDROID_SMOKE_FAILED: " + message)
	quit(1)
