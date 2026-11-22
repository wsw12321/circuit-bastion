class_name CircuitSimulation
extends RefCounted

const ContentCatalogScript = preload("res://scripts/content_catalog.gd")

const Replay = preload("res://scripts/replay.gd")

## Deterministic, UI-independent simulation for the Circuit Bastion vertical slice.
## All combat advances in fixed 100 ms steps so a replay is reproducible from
## the same seed and command sequence.

const FIXED_STEP := 0.1
const WAVE_COUNT := 10
const MAX_EVENT_LOG := 512

signal event_recorded(event: Dictionary)
signal event_emitted(event: Dictionary)
signal state_changed(snapshot: Dictionary)

var seed_value := 1337
var rng_state := 1338
var tick_count := 0
var elapsed := 0.0
var accumulator := 0.0
var speed := 1.0
var paused := true
var running := false
var finished := false
var victory := false
var current_wave := 0
var base_integrity := 100
var charge := 120
var modules: Dictionary = {}
var connections: Array = []
var enemies: Dictionary = {}
var event_log: Array = []
var event_sequence := 0
var next_module_id := 1
var next_enemy_id := 1
var catalog: RefCounted
var replay: RefCounted

const ENEMY_ARCHETYPES := [
	{"kind": "scout", "label": "侦察蜂", "hp": 34, "speed": 0.12, "damage": 1, "tags": ["light"]},
	{"kind": "bruiser", "label": "破城兽", "hp": 90, "speed": 0.045, "damage": 3, "tags": ["armored"]},
	{"kind": "splitter", "label": "裂变体", "hp": 52, "speed": 0.07, "damage": 2, "tags": ["swarm"]},
	{"kind": "jammer", "label": "干扰体", "hp": 64, "speed": 0.06, "damage": 2, "tags": ["signal"]},
	{"kind": "leech", "label": "虹吸虫", "hp": 42, "speed": 0.09, "damage": 2, "tags": ["drain"]},
	{"kind": "phase", "label": "相位影", "hp": 74, "speed": 0.08, "damage": 2, "tags": ["phase"]},
]

const MODULE_ARCHETYPES := {
	"scanner": {"label": "扫描器", "power": 1, "damage": 0, "cooldown": 0.0, "range": 0.45, "heat": 1},
	"pulse_cannon": {"label": "脉冲炮", "power": 3, "damage": 18, "cooldown": 0.8, "range": 0.5, "heat": 5},
	"railgun": {"label": "轨道炮", "power": 6, "damage": 42, "cooldown": 1.8, "range": 0.85, "heat": 11},
	"router": {"label": "路由器", "power": 2, "damage": 0, "cooldown": 0.0, "range": 0.0, "heat": 1},
	"capacitor": {"label": "电容", "power": -2, "damage": 0, "cooldown": 0.0, "range": 0.0, "heat": -2},
	"heat_sink": {"label": "散热器", "power": 1, "damage": 0, "cooldown": 0.0, "range": 0.0, "heat": -5},
	"slow_field": {"label": "减速场", "power": 4, "damage": 4, "cooldown": 1.2, "range": 0.3, "heat": 7},
	"repair_arm": {"label": "维修臂", "power": 3, "damage": 0, "cooldown": 2.0, "range": 0.0, "heat": 4},
}

func _init(initial_seed: int = 1337) -> void:
	catalog = ContentCatalogScript.new()
	reset(initial_seed)

func reset(new_seed: int = 1337) -> void:
	seed_value = new_seed
	rng_state = abs(new_seed) + 1
	tick_count = 0
	elapsed = 0.0
	accumulator = 0.0
	speed = 1.0
	paused = true
	running = false
	finished = false
	victory = false
	current_wave = 0
	base_integrity = 100
	charge = 120
	modules.clear()
	connections.clear()
	enemies.clear()
	event_log.clear()
	event_sequence = 0
	next_module_id = 1
	next_enemy_id = 1
	replay = Replay.new(seed_value)
	_emit_event("system", "core", "", "模拟已重置", {"seed": seed_value})

func set_speed(multiplier: float) -> void:
	var chosen := 1.0
	for option in [1.0, 2.0, 4.0]:
		if absf(float(option) - multiplier) < absf(chosen - multiplier):
			chosen = float(option)
	speed = chosen
	_record_command("set_speed", {"speed": speed})
	_emit_event("control", "core", "", "速度设为 %.0fx" % speed)

func set_paused(value: bool) -> void:
	paused = value
	_record_command("set_paused", {"paused": paused})
	_emit_event("control", "core", "", "战斗%s" % ("暂停" if paused else "继续"))

func toggle_pause() -> void:
	set_paused(not paused)

func add_module(module_kind: String, grid_position := Vector2i.ZERO) -> String:
	var catalog_spec: Dictionary = catalog.module_spec(module_kind)
	var fallback_spec: Dictionary = MODULE_ARCHETYPES.get(module_kind, {})
	var spec: Dictionary = catalog_spec if not catalog_spec.is_empty() else fallback_spec.duplicate(true)
	if spec.is_empty():
		return ""
	var module_id := "M%02d" % next_module_id
	next_module_id += 1
	modules[module_id] = {
		"id": module_id, "kind": module_kind, "label": spec.label,
		"grid": {"x": grid_position.x, "y": grid_position.y},
		"power": int(spec.power), "damage": int(spec.damage),
		"cooldown": float(spec.cooldown), "cooldown_left": 0.0,
		"range": float(spec.range), "heat": 0, "heat_limit": 100,
		"rules": [], "firmware": "standard", "disabled": false,
	}
	_record_command("add_module", {"kind": module_kind, "x": grid_position.x, "y": grid_position.y})
	_emit_event("module", module_id, "", "部署 %s" % spec.label, {"kind": module_kind})
	return module_id

func connect_modules(from_id: String, to_id: String, connection_kind := "signal") -> bool:
	if not modules.has(from_id) or not modules.has(to_id) or from_id == to_id:
		return false
	if connection_kind not in ["power", "signal", "heat"]:
		return false
	for connection in connections:
		if connection.from == from_id and connection.to == to_id and connection.kind == connection_kind:
			return false
	connections.append({"from": from_id, "to": to_id, "kind": connection_kind, "latency": 0.1})
	_record_command("connect_modules", {"from": from_id, "to": to_id, "kind": connection_kind})
	_emit_event("connection", from_id, to_id, "建立%s线路" % connection_kind, {"kind": connection_kind})
	return true

func add_rule(module_id: String, trigger: String, condition: String, action: String, priority := 0) -> bool:
	if not modules.has(module_id):
		return false
	var rule := {"trigger": trigger, "condition": condition, "action": action, "priority": priority}
	modules[module_id].rules.append(rule)
	_record_command("add_rule", {"module": module_id, "trigger": trigger, "condition": condition, "action": action, "priority": priority})
	_emit_event("rule", module_id, "", "写入规则 %s → %s" % [trigger, action], rule)
	return true

func start_battle() -> bool:
	if modules.is_empty():
		_emit_event("warning", "core", "", "没有可运行模块")
		return false
	running = true
	paused = false
	finished = false
	victory = false
	current_wave = 1
	_record_command("start_battle")
	_spawn_wave(current_wave)
	_emit_event("wave", "core", "", "第 1 波开始", {"wave": current_wave})
	return true

## Compatibility name used by the composition root and older prototype code.
func start_wave() -> bool:
	return start_battle()

func advance(delta_seconds: float) -> void:
	if not running or paused or finished:
		return
	accumulator += maxf(delta_seconds, 0.0) * speed
	while accumulator >= FIXED_STEP:
		accumulator -= FIXED_STEP
		_step_fixed()
	state_changed.emit(get_snapshot())

func step_once() -> void:
	if running and not finished:
		_step_fixed()
		state_changed.emit(get_snapshot())

func _step_fixed() -> void:
	tick_count += 1
	elapsed = float(tick_count) * FIXED_STEP
	_update_modules()
	_update_enemies()
	if running and enemies.is_empty() and not finished:
		_finish_wave()

func _update_modules() -> void:
	var module_ids: Array = modules.keys()
	module_ids.sort()
	for module_id in module_ids:
		var module: Dictionary = modules[module_id]
		if module.disabled:
			continue
		module.cooldown_left = maxf(0.0, float(module.cooldown_left) - FIXED_STEP)
		if module.kind == "heat_sink":
			module.heat = maxi(0, int(module.heat) - 1)
		if module.kind == "repair_arm":
			if module.cooldown_left <= 0.0 and base_integrity < 100:
				base_integrity = mini(100, base_integrity + 2)
				module.cooldown_left = module.cooldown
				_emit_event("action", module_id, "core", "维修臂修复核心", {"integrity": base_integrity})
			continue
		if int(module.damage) <= 0 or module.cooldown_left > 0.0:
			continue
		var target_id := _find_target(module)
		if target_id == "" or not _rule_allows_attack(module, enemies[target_id]):
			continue
		var target: Dictionary = enemies[target_id]
		var damage := int(module.damage)
		if module.kind == "slow_field":
			target.speed_multiplier = 0.6
		else:
			target.hp = maxi(0, int(target.hp) - damage)
		module.heat = mini(int(module.heat_limit), int(module.heat) + int(module.get("heat", 0)))
		module.cooldown_left = float(module.cooldown)
		_emit_event("action", module_id, target_id, "%s 命中 %s" % [module.label, target.label], {"damage": damage, "hp": target.hp})
		if int(target.hp) <= 0:
			enemies.erase(target_id)
			charge += 4
			_emit_event("enemy_destroyed", module_id, target_id, "%s 已清除" % target.label, {"reward": 4})

func _find_target(module: Dictionary) -> String:
	var best_id := ""
	var best_progress := 2.0
	var enemy_ids: Array = enemies.keys()
	enemy_ids.sort()
	for enemy_id in enemy_ids:
		var enemy: Dictionary = enemies[enemy_id]
		var distance := absf(float(enemy.progress) - 0.5)
		if distance <= float(module.range) and float(enemy.progress) < best_progress:
			best_progress = float(enemy.progress)
			best_id = enemy_id
	return best_id

func _rule_allows_attack(module: Dictionary, enemy: Dictionary) -> bool:
	if module.rules.is_empty():
		return true
	for rule in module.rules:
		if rule.action not in ["fire", "attack", "slow"]:
			continue
		var condition := str(rule.condition)
		if condition.is_empty() or condition == "always":
			return true
		if condition.begins_with("tag:") and condition.trim_prefix("tag:") in enemy.tags:
			return true
	return false

func _update_enemies() -> void:
	var enemy_ids: Array = enemies.keys()
	enemy_ids.sort()
	for enemy_id in enemy_ids:
		if not enemies.has(enemy_id):
			continue
		var enemy: Dictionary = enemies[enemy_id]
		enemy.progress = float(enemy.progress) + float(enemy.speed) * float(enemy.speed_multiplier) * FIXED_STEP
		if float(enemy.progress) < 1.0:
			continue
		base_integrity = maxi(0, base_integrity - int(enemy.damage))
		enemies.erase(enemy_id)
		_emit_event("breach", enemy_id, "core", "%s 穿过出口" % enemy.label, {"damage": enemy.damage, "integrity": base_integrity})
		if base_integrity <= 0:
			finished = true
			running = false
			_emit_event("defeat", "core", "", "核心已失守")

func _spawn_wave(wave_index: int) -> void:
	var wave_spec: Dictionary = catalog.wave_spec(wave_index)
	var count := int(wave_spec.get("count", 3 + wave_index))
	var pool: Array = wave_spec.get("pool", []).duplicate()
	if pool.is_empty():
		for archetype in ENEMY_ARCHETYPES:
			pool.append(archetype.kind)
	for index in count:
		var kind: String = str(pool[_next_random() % pool.size()])
		var archetype: Dictionary = catalog.enemy_spec(kind)
		if archetype.is_empty():
			for fallback in ENEMY_ARCHETYPES:
				if fallback.kind == kind:
					archetype = fallback.duplicate(true)
					break
		if archetype.is_empty():
			continue
		_spawn_enemy(archetype, wave_index, index)
	if wave_index == WAVE_COUNT:
		var boss: Dictionary = catalog.enemy_spec("boss")
		if boss.is_empty():
			boss = {"kind": "boss", "label": "熔断主宰", "hp": 520, "speed": 0.025, "damage": 12, "tags": ["boss", "armored"]}
		_spawn_enemy(boss, wave_index, count)

func _spawn_enemy(archetype: Dictionary, wave_index: int, ordinal: int) -> void:
	var enemy_id := "E%03d" % next_enemy_id
	next_enemy_id += 1
	var hp := int(archetype.hp) + (wave_index - 1) * 4
	enemies[enemy_id] = {
		"id": enemy_id, "kind": archetype.kind, "label": archetype.label,
		"hp": hp, "max_hp": hp, "speed": float(archetype.speed),
		"speed_multiplier": 1.0, "damage": int(archetype.damage),
		"tags": archetype.tags.duplicate(), "progress": -float(ordinal) * 0.035,
		"wave": wave_index,
	}
	_emit_event("enemy_spawn", "core", enemy_id, "生成 %s" % archetype.label, {"wave": wave_index, "tags": archetype.tags})

func _finish_wave() -> void:
	_emit_event("wave_clear", "core", "", "第 %d 波完成" % current_wave, {"wave": current_wave, "charge": charge})
	if current_wave >= WAVE_COUNT:
		finished = true
		running = false
		victory = base_integrity > 0
		_emit_event("victory" if victory else "defeat", "core", "", "堡垒完成 10 波")
		return
	current_wave += 1
	_spawn_wave(current_wave)
	_emit_event("wave", "core", "", "第 %d 波开始" % current_wave, {"wave": current_wave})

func get_snapshot() -> Dictionary:
	return {
		"seed": seed_value, "tick": tick_count, "elapsed": elapsed,
		"speed": speed, "paused": paused, "running": running,
		"finished": finished, "victory": victory, "wave": current_wave,
		"integrity": base_integrity, "charge": charge,
		"content_signature": catalog.content_signature(),
		"modules": modules.duplicate(true), "connections": connections.duplicate(true),
		"enemies": enemies.duplicate(true), "events": event_log.duplicate(true),
	}

## Compatibility name used by the first desktop scene draft.
func snapshot() -> Dictionary:
	return get_snapshot()

func export_replay() -> String:
	return replay.encode() if replay != null else ""

func save_state() -> Dictionary:
	return {
		"version": 1,
		"snapshot": get_snapshot(),
		"runtime": {
			"rng_state": rng_state,
			"accumulator": accumulator,
			"event_sequence": event_sequence,
			"next_module_id": next_module_id,
			"next_enemy_id": next_enemy_id,
		},
		"replay": replay.to_dict() if replay != null else {},
	}

func export_save() -> String:
	return JSON.stringify(save_state())

func import_save(encoded: String) -> bool:
	var parsed = JSON.parse_string(encoded)
	if not parsed is Dictionary:
		return false
	return load_state(parsed)

func load_state(state: Dictionary) -> bool:
	var snapshot_state = state.get("snapshot", {})
	if not snapshot_state is Dictionary:
		return false
	seed_value = int(snapshot_state.get("seed", seed_value))
	tick_count = int(snapshot_state.get("tick", 0))
	elapsed = float(snapshot_state.get("elapsed", 0.0))
	speed = float(snapshot_state.get("speed", 1.0))
	paused = bool(snapshot_state.get("paused", true))
	running = bool(snapshot_state.get("running", false))
	finished = bool(snapshot_state.get("finished", false))
	victory = bool(snapshot_state.get("victory", false))
	current_wave = int(snapshot_state.get("wave", 0))
	base_integrity = int(snapshot_state.get("integrity", 100))
	charge = int(snapshot_state.get("charge", 120))
	modules = snapshot_state.get("modules", {}).duplicate(true)
	connections = snapshot_state.get("connections", []).duplicate(true)
	enemies = snapshot_state.get("enemies", {}).duplicate(true)
	event_log = snapshot_state.get("events", []).duplicate(true)
	var runtime_state = state.get("runtime", {})
	if runtime_state is Dictionary:
		rng_state = int(runtime_state.get("rng_state", rng_state))
		accumulator = float(runtime_state.get("accumulator", 0.0))
		event_sequence = int(runtime_state.get("event_sequence", event_log.size()))
		next_module_id = int(runtime_state.get("next_module_id", modules.size() + 1))
		next_enemy_id = int(runtime_state.get("next_enemy_id", enemies.size() + 1))
	var replay_state = state.get("replay", {})
	replay = Replay.new(seed_value)
	if replay_state is Dictionary:
		replay.commands = replay_state.get("commands", []).duplicate(true)
	return true

func get_event_log(limit := 100) -> Array:
	return event_log.slice(maxi(0, event_log.size() - limit))

func replay_signature() -> String:
	var pieces := [str(seed_value), str(tick_count), str(current_wave), str(base_integrity), str(charge)]
	for event in event_log:
		pieces.append("%s:%s:%s" % [event.sequence, event.kind, event.source])
	return "|".join(pieces)

func _next_random() -> int:
	rng_state = int((rng_state * 1103515245 + 12345) % 2147483647)
	return abs(rng_state)

func _emit_event(kind: String, source: String, target: String, message: String, payload := {}) -> void:
	event_sequence += 1
	var event := {
		"sequence": event_sequence, "tick": tick_count, "time": snappedf(elapsed, 0.001),
		"kind": kind, "source": source, "target": target, "message": message,
		"payload": payload.duplicate(true),
	}
	event_log.append(event)
	if event_log.size() > MAX_EVENT_LOG:
		event_log.pop_front()
	event_recorded.emit(event)
	event_emitted.emit(event)

func _record_command(command: String, payload: Dictionary = {}) -> void:
	if replay != null:
		replay.record(tick_count, command, payload)

