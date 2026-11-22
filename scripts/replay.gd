class_name BastionReplay
extends RefCounted

## Versioned, JSON-safe input trace for deterministic battle replays.
## The simulation remains the source of truth. This object records the seed
## and player commands so a replay can be rebuilt after a content update.

const FORMAT_VERSION := 1

var seed_value: int = 0
var commands: Array = []

func _init(initial_seed: int = 0) -> void:
	seed_value = initial_seed

func record(tick: int, command: String, payload: Dictionary = {}) -> void:
	commands.append({
		"tick": tick,
		"command": command,
		"payload": payload.duplicate(true),
	})

func to_dict() -> Dictionary:
	return {
		"format": FORMAT_VERSION,
		"seed": seed_value,
		"commands": commands.duplicate(true),
	}

func encode() -> String:
	return JSON.stringify(to_dict())

static func decode(encoded: String) -> RefCounted:
	var parsed = JSON.parse_string(encoded)
	if not parsed is Dictionary:
		return null
	if int(parsed.get("format", 0)) != FORMAT_VERSION:
		return null
	var replay = load("res://scripts/replay.gd").new(int(parsed.get("seed", 0)))
	if parsed.get("commands", []) is Array:
		replay.commands = parsed.commands.duplicate(true)
	return replay
