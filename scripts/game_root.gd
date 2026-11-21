extends Node
## Thin composition root for the desktop vertical slice.
## It wires the deterministic simulation to the hand-drawn BattleView and keeps
## presentation free from game-state mutation.

const SIMULATION_SCRIPT := preload("res://scripts/simulation.gd")
const BATTLE_VIEW_SCRIPT := preload("res://godot/battle_view.gd")

var simulation: RefCounted
var view: Control
var view_events: Array[Dictionary] = []

func _ready() -> void:
	simulation = SIMULATION_SCRIPT.new(2048)
	view = BATTLE_VIEW_SCRIPT.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
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
	match command:
		"pause", "resume":
			simulation.toggle_pause()
		"replay":
			view_events.push_front({"time": "REPLAY", "type": "SYSTEM", "text": "事件回放已锁定当前确定性记录", "color": Color("#b690ff")})
	var parts := command.split(":")
	if parts.size() == 2 and parts[0] == "speed":
		simulation.set_speed(int(parts[1]))
	_push_snapshot()

func _push_snapshot() -> void:
	if not is_instance_valid(view) or not is_instance_valid(simulation):
		return
	var state: Dictionary = simulation.snapshot()
	state = simulation.get_snapshot()
	state["events"] = view_events
	state["modules"] = _view_modules()
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
	return [
		{"id": "scanner", "name": "扫描器", "cell": Vector2i(1, 1), "color": Color("#5ed6ff"), "load": 0.22},
		{"id": "router", "name": "路由器", "cell": Vector2i(3, 2), "color": Color("#b690ff"), "load": 0.48},
		{"id": "pulse_cannon", "name": "脉冲炮", "cell": Vector2i(5, 3), "color": Color("#ffca62"), "load": 0.73},
		{"id": "cooler", "name": "散热器", "cell": Vector2i(6, 1), "color": Color("#68e3bf"), "load": 0.31},
		{"id": "battery", "name": "电容", "cell": Vector2i(2, 4), "color": Color("#82aaff"), "load": 0.18},
	]
