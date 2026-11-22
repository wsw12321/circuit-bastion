extends SceneTree

## Static mobile-platform contract probe.
##
## Android builds need a real Godot preset and mobile-safe project settings even
## when the CI runner only performs the desktop export. This probe intentionally
## reads the project files as text so it catches regressions before a release
## job spends time downloading Android templates and SDK tooling.

const PROJECT_PATH := "res://project.godot"
const PRESETS_PATH := "res://export_presets.cfg"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var project_text := _read_file(PROJECT_PATH)
	var presets_text := _read_file(PRESETS_PATH)
	if project_text.is_empty() or presets_text.is_empty():
		_fail("project or export preset file is missing")
		return
	_assert(project_text.contains("renderer/rendering_method.mobile=\"gl_compatibility\""), "mobile renderer must be configured")
	_assert(project_text.contains("handheld/orientation=1"), "handheld orientation must be configured")
	_assert(project_text.contains("toggle_pause="), "touch-safe pause action must remain available")
	_assert(presets_text.contains("platform=\"Android\""), "Android export preset is missing")
	_assert(presets_text.contains("export_path=\"dist/godot/circuit-bastion-android.apk\""), "Android APK export path is missing")
	_assert(presets_text.contains("package/unique_name=\"com.circuitbastion.game\""), "Android package id is missing")
	_assert(presets_text.contains("architectures/arm64-v8a=true"), "Android arm64 architecture must be enabled")
	print("PLATFORM_OK mobile_renderer=gl_compatibility android_preset=true arm64=true")
	quit(0)

func _read_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""

func _assert(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _fail(message: String) -> void:
	push_error("PLATFORM_ASSERT_FAILED: " + message)
	quit(1)
