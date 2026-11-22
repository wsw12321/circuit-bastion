extends SceneTree

const JSON_FILES := [
    {"path": "res://content_modules.json", "key": "modules", "minimum": 8},
    {"path": "res://content_enemies.json", "key": "enemies", "minimum": 7},
    {"path": "res://content_waves.json", "key": "waves", "minimum": 10},
]
const REQUIRED_FILES := [
    "res://project.godot",
    "res://export_presets.cfg",
    "res://scenes/main.tscn",
    "res://scripts/game_root.gd",
    "res://scripts/simulation.gd",
    "res://godot/battle_view.gd",
    "res://godot/mobile_battle_view.gd",
]

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    for path in REQUIRED_FILES:
        if not FileAccess.file_exists(path):
            _fail("missing resource: " + path)
            return
    for item in JSON_FILES:
        var file := FileAccess.open(str(item["path"]), FileAccess.READ)
        if file == null:
            _fail("could not open " + str(item["path"]))
            return
        var parsed = JSON.parse_string(file.get_as_text())
        if not (parsed is Dictionary):
            _fail("invalid JSON object: " + str(item["path"]))
            return
        var values = parsed.get(str(item["key"]), [])
        if not (values is Array) or values.size() < int(item["minimum"]):
            _fail("unexpected content in " + str(item["path"]))
            return
    var rules_file := FileAccess.open("res://content_rules.json", FileAccess.READ)
    if rules_file == null:
        _fail("could not open rules content")
        return
    var rules = JSON.parse_string(rules_file.get_as_text())
    for key in ["triggers", "conditions", "actions"]:
        if not (rules is Dictionary) or not (rules.get(key, []) is Array) or rules.get(key, []).is_empty():
            _fail("rules content missing " + key)
            return
    var presets_file := FileAccess.open("res://export_presets.cfg", FileAccess.READ)
    if presets_file == null:
        _fail("could not open export presets")
        return
    var presets := presets_file.get_as_text()
    for required in [
        "[preset.0]", 'name="Linux/X11"', 'export_path="dist/godot/circuit-bastion-linux-x86_64"',
        "[preset.1]", 'name="Windows Desktop"', 'export_path="dist/godot/circuit-bastion-windows-x86_64.exe"',
        "[preset.2]", 'name="Android"', 'architectures/arm64-v8a=true',
    ]:
        if not presets.contains(required):
            _fail("export preset contract missing " + required)
            return
    print("RESOURCE_OK files=%d json=%d presets=linux/windows/android-arm64" % [REQUIRED_FILES.size(), JSON_FILES.size() + 1])
    quit(0)

func _fail(message: String) -> void:
    push_error("RESOURCE_FAILED: " + message)
    quit(1)
