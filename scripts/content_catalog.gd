class_name ContentCatalog
extends RefCounted

## Data-driven content registry. JSON stays human-editable and deterministic.
## The simulation keeps its built-in archetypes as a compatibility fallback.

const MODULES_PATH := "res://content_modules.json"
const ENEMIES_PATH := "res://content_enemies.json"
const WAVES_PATH := "res://content_waves.json"
const RULES_PATH := "res://content_rules.json"

var modules: Dictionary = {}
var enemies: Dictionary = {}
var waves: Dictionary = {}
var rules: Dictionary = {}

func _init() -> void:
	modules = _index(_load_array(MODULES_PATH, "modules"), "kind")
	enemies = _index(_load_array(ENEMIES_PATH, "enemies"), "kind")
	for wave in _load_array(WAVES_PATH, "waves"):
		waves[int(wave.get("wave", 0))] = wave
	var rule_data := _load_object(RULES_PATH)
	if rule_data:
		rules = rule_data

func module_spec(kind: String) -> Dictionary:
	return modules.get(kind, {}).duplicate(true)

func enemy_spec(kind: String) -> Dictionary:
	return enemies.get(kind, {}).duplicate(true)

func wave_spec(wave: int) -> Dictionary:
	return waves.get(wave, {}).duplicate(true)

func enemy_pool(wave: int) -> Array:
	var spec := wave_spec(wave)
	return spec.get("pool", []).duplicate()

func content_signature() -> String:
	var payload := {"modules": modules, "enemies": enemies, "waves": waves, "rules": rules}
	return str(JSON.stringify(payload).hash())

func _index(items: Array, key: String) -> Dictionary:
	var result := {}
	for item in items:
		if item is Dictionary and item.has(key):
			result[str(item[key])] = item
	return result

func _load_array(path: String, key: String) -> Array:
	var data := _load_object(path)
	if data.has(key) and data[key] is Array:
		return data[key]
	return []

func _load_object(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
