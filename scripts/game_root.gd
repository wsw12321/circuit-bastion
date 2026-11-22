extends Node
## Thin composition root for the desktop vertical slice.
## It wires the deterministic simulation to the hand-drawn BattleView and keeps
## presentation free from game-state mutation.

const SIMULATION_SCRIPT := preload("res://scripts/simulation.gd")
const BATTLE_VIEW_SCRIPT := preload("res://godot/battle_view.gd")

var simulation: RefCounted
var view: Control
var view_events: Array[Dictionary] = []
var pending_build_kind := ""
var pending_bench_index := -1

func _ready() -> void:
	simulation = SIMULATION_SCRIPT.new(2048)
	view = BATTLE_VIEW_SCRIPT.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	view.set_simulation(simulation)
	simulation.event_recorded.connect(_on_event_recorded)
	simulation.state_changed.connect(_on_state_changed)
	view.command_requested.connect(_on_command_requested)
	view.event_selected.connect(_on_event_selected)
	_seed_modules()
	simulation.start_battle()
	_push_snapshot()

func _process(delta: float) -> void:
	simulation.advance(delta)
	_push_snapshot()

func _on_event_recorded(event: Dictionary) -> void:
	var kind := str(event.get("kind", "event"))
	var palette := {
		"action": Color("#ffca62"),
		"enemy_destroyed": Color("#68e3bf"),
		"breach": Color("#ff6b75"),
		"wave": Color("#b690ff"),
		"control": Color("#b690ff"),
	}
	view_events.push_front({
		"time": "%02d:%02d.%03d" % [int(event.get("tick", 0)) / 600, (int(event.get("tick", 0)) / 10) % 60, int(event.get("tick", 0)) * 100 % 1000],
		"type": kind.to_upper(),
		"text": str(event.get("message", "")),
		"color": palette.get(kind, Color("#72d7ff")),
	})
	if view_events.size() > 24:
		view_events.pop_back()
	_push_snapshot()

func _on_state_changed(_state: Dictionary) -> void:
	_push_snapshot()

func _on_event_selected(event_index: int) -> void:
	if event_index >= 0 and event_index < view_events.size():
		view.highlight_event(view_events[event_index])

func _on_command_requested(command: String) -> void:
	var parts := command.split(":")
	if command == "pause" or command == "resume":
		simulation.set_paused(command == "pause")
	elif command == "replay":
		view_events.push_front({"time": "REPLAY", "type": "SYSTEM", "text": "事件回放已锁定当前确定性记录", "color": Color("#b690ff")})
	elif parts.size() == 2 and parts[0] == "speed":
		simulation.set_speed(int(parts[1]))
	elif parts.size() >= 5 and parts[0] == "build":
		var build_kind := str(parts[1])
		var build_cell := Vector2i(int(parts[2]), int(parts[3]))
		var build_rotation := int(parts[4])
		var build_id := ""
		var bench_items: Array = simulation.get_bench()
		for bench_index in range(bench_items.size() - 1, -1, -1):
			if str(bench_items[bench_index].get("kind", "")) == build_kind:
				build_id = str(simulation.deploy_bench_item(bench_index, build_cell, build_rotation))
				break
		if build_id.is_empty():
			build_id = str(simulation.build_module(build_kind, build_cell, build_rotation))
		pending_build_kind = "" if not build_id.is_empty() else pending_build_kind
	elif parts.size() >= 4 and parts[0] == "move":
		simulation.move_module(str(parts[1]), Vector2i(int(parts[2]), int(parts[3])))
	elif parts.size() >= 3 and parts[0] == "rotate":
		if simulation.has_method("set_module_rotation"):
			simulation.set_module_rotation(str(parts[1]), int(parts[2]))
		else:
			simulation.rotate_module(str(parts[1]), int(parts[2]))
	elif parts.size() == 2 and parts[0] == "sell":
		simulation.sell_module(str(parts[1]))
	elif parts.size() >= 2 and parts[0] == "shop":
		if parts[1] == "buy" and parts.size() >= 3:
			simulation.buy_shop_slot(int(parts[2]))
		elif parts[1] == "refresh":
			simulation.refresh_shop()
		elif parts[1] == "select":
			pending_build_kind = str(parts[3]) if parts.size() >= 4 else ""
			if parts.size() >= 3:
				var slot: int = int(parts[2])
				view_events.push_front({"time": "SHOP", "type": "PREP", "text": "选择 %s · 点击网格部署" % pending_build_kind, "color": Color("#b690ff")})
	elif parts.size() >= 2 and parts[0] == "bench":
		if parts[1] == "deploy" and parts.size() >= 6:
			simulation.deploy_bench_item(int(parts[2]), Vector2i(int(parts[3]), int(parts[4])), int(parts[5]))
		elif parts[1] == "discard" and parts.size() >= 3:
			simulation.discard_bench_item(int(parts[2]))
	elif parts.size() == 2 and parts[0] == "upgrade":
		var branch: String = str({"fortify": "stabilizer", "logic": "automation"}.get(parts[1], parts[1]))
		var selected: String = _selected_module_id()
		if not selected.is_empty():
			simulation.upgrade_module(selected, str(branch))
	elif command == "retry":
		simulation.retry_battle()
	_push_snapshot()

func _push_snapshot() -> void:
	if not is_instance_valid(view) or not is_instance_valid(simulation):
		return
	var state: Dictionary = simulation.snapshot()
	state = simulation.get_snapshot()
	state["events"] = view_events
	state["modules"] = _view_modules()
	state["shop"] = simulation.get_shop_inventory()
	state["bench"] = simulation.get_bench()
	view.set_snapshot(state)

func _seed_modules() -> void:
	var scanner: String = simulation.add_module("scanner", Vector2i(1, 1))
	var router: String = simulation.add_module("router", Vector2i(3, 2))
	var pulse: String = simulation.add_module("pulse_cannon", Vector2i(5, 3))
	var cooler: String = simulation.add_module("heat_sink", Vector2i(6, 1))
	var battery: String = simulation.add_module("capacitor", Vector2i(2, 4))
	simulation.connect_modules(scanner, router, "signal")
	simulation.connect_modules(router, pulse, "signal")
	simulation.connect_modules(battery, pulse, "power")
	simulation.connect_modules(pulse, cooler, "heat")
	simulation.add_rule(pulse, "target_seen", "always", "fire")

func _view_modules() -> Array:
	var result: Array = []
	var palette := {
		"scanner": Color("#5ed6ff"), "router": Color("#b690ff"), "pulse_cannon": Color("#ffca62"),
		"railgun": Color("#ff9b71"), "heat_sink": Color("#68e3bf"), "capacitor": Color("#82aaff"),
		"slow_field": Color("#dc7dff"), "repair_arm": Color("#8ee7b8"),
	}
	var ids: Array = simulation.modules.keys()
	ids.sort()
	for module_id in ids:
		var module: Dictionary = simulation.modules[module_id]
		var grid: Dictionary = module.get("grid", {})
		var limit := maxi(1, int(module.get("heat_limit", 100)))
		result.append({
			"id": module_id, "name": str(module.get("label", module.get("kind", "模块"))),
			"kind": str(module.get("kind", "module")),
			"cell": Vector2i(int(grid.get("x", 0)), int(grid.get("y", 0))),
			"rotation": int(module.get("rotation", 0)), "level": int(module.get("level", 1)),
			"color": palette.get(str(module.get("kind", "")), Color("#72d7ff")),
			"load": clampf(float(module.get("heat", 0)) / float(limit), 0.0, 1.0),
		})
	return result

func _selected_module_id() -> String:
	if is_instance_valid(view):
		return str(view.get("selected_module_id"))
	return ""
