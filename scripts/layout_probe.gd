extends SceneTree

const BattleView = preload("res://godot/battle_view.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var view := BattleView.new()
	root.add_child(view)
	view.set_size(Vector2(390, 844))
	view.set_snapshot({
		"wave": 1, "tick": 0, "paused": true, "speed": 1,
		"integrity": 100, "charge": 120, "phase": "build",
		"modules": [], "events": [], "shop": [], "bench": [],
		"diagnostics": {"warning_count": 0},
	})
	await process_frame
	view.free()
	print("LAYOUT_OK portrait=390x844 compact=true")
	quit(0)
