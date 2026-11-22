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
const GRID_COLUMNS := 8
const GRID_ROWS := 6
const ENTRY_CELL := Vector2i(0, 3)
const CORE_CELL := Vector2i(7, 3)
const BENCH_LIMIT := 8
const SHOP_SIZE := 4
const SHOP_REFRESH_COST := 8

const MODULE_COSTS := {
	"scanner": 16,
	"pulse_cannon": 28,
	"railgun": 48,
	"router": 20,
	"capacitor": 22,
	"heat_sink": 18,
	"slow_field": 34,
	"repair_arm": 32,
}

const UPGRADE_BRANCHES := {
	"overclock": {"label": "超频", "description": "伤害与功率提升，热量增加", "cost": 24},
	"stabilizer": {"label": "稳压", "description": "冷却与热量控制提升", "cost": 22},
	"automation": {"label": "自动化", "description": "射程与规则响应提升", "cost": 30},
}

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
var scrap := 0
var modules: Dictionary = {}
var connections: Array = []
var enemies: Dictionary = {}
var event_log: Array = []
var event_sequence := 0
var next_module_id := 1
var next_enemy_id := 1
var catalog: RefCounted
var replay: RefCounted
var bench: Array = []
var shop_inventory: Array = []
var shop_rotation := 0
var shop_refreshes := 0
var wave_reward := 0
var phase := "build"
var last_failure_reason := ""

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
	scrap = 0
	modules.clear()
	connections.clear()
	enemies.clear()
	event_log.clear()
	event_sequence = 0
	next_module_id = 1
	next_enemy_id = 1
	bench.clear()
	shop_rotation = 0
	shop_refreshes = 0
	wave_reward = 0
	phase = "build"
	last_failure_reason = ""
	replay = Replay.new(seed_value)
	_refresh_shop_inventory(false)
	_emit_event("system", "core", "", "模拟已重置", {"seed": seed_value})

func set_speed(multiplier: float) -> void:
	var chosen := 1.0
	for option in [1.0, 2.0, 4.0]:
		if absf(float(option) - multiplier) < absf(chosen - multiplier):
			chosen = float(option)
	speed = chosen
	_record_command("set_speed", {"speed": speed})
	_emit_event("control", "core", "", "速度设为 %.0fx" % speed)

func module_cost(module_kind: String) -> int:
	return int(MODULE_COSTS.get(module_kind, 0))

func module_spec(module_kind: String) -> Dictionary:
	var spec: Dictionary = catalog.module_spec(module_kind)
	if spec.is_empty():
		spec = MODULE_ARCHETYPES.get(module_kind, {}).duplicate(true)
	return spec

func is_cell_in_bounds(grid_position: Vector2i) -> bool:
	return grid_position.x >= 0 and grid_position.x < GRID_COLUMNS and grid_position.y >= 0 and grid_position.y < GRID_ROWS

func is_cell_reserved(grid_position: Vector2i) -> bool:
	return grid_position == ENTRY_CELL or grid_position == CORE_CELL

func occupied_module_at(grid_position: Vector2i, ignore_module_id := "") -> String:
	var module_ids: Array = modules.keys()
	module_ids.sort()
	for module_id in module_ids:
		if str(module_id) == ignore_module_id:
			continue
		var module: Dictionary = modules[module_id]
		var grid: Dictionary = module.get("grid", {})
		if Vector2i(int(grid.get("x", -1)), int(grid.get("y", -1))) == grid_position:
			return str(module_id)
	return ""

func preview_placement(module_kind: String, grid_position: Vector2i, rotation := 0, ignore_module_id := "") -> Dictionary:
	var spec := module_spec(module_kind)
	var reason := ""
	if spec.is_empty():
		reason = "未知模块"
	elif not is_cell_in_bounds(grid_position):
		reason = "超出棋盘"
	elif is_cell_reserved(grid_position):
		reason = "核心通道不可占用"
	elif occupied_module_at(grid_position, ignore_module_id) != "":
		reason = "格点已被占用"
	var cost := module_cost(module_kind)
	if reason.is_empty() and ignore_module_id.is_empty() and charge < cost:
		reason = "电荷不足"
	return {
		"valid": reason.is_empty(), "kind": module_kind,
		"grid": {"x": grid_position.x, "y": grid_position.y},
		"rotation": posmod(rotation, 4), "cost": cost,
		"reason": reason, "occupied_by": occupied_module_at(grid_position, ignore_module_id),
	}

func preview_build(module_kind: String, grid_position: Vector2i, rotation := 0) -> Dictionary:
	return preview_placement(module_kind, grid_position, rotation)

func build_module(module_kind: String, grid_position: Vector2i, rotation := 0) -> String:
	if running and not paused and phase == "combat":
		last_failure_reason = "战斗运行中，请先暂停"
		_emit_event("warning", "core", "", "无法部署：战斗运行中，请先暂停")
		return ""
	var preview := preview_placement(module_kind, grid_position, rotation)
	if not bool(preview.valid):
		last_failure_reason = str(preview.reason)
		_emit_event("warning", "core", "", "无法部署%s" % preview.reason, preview)
		return ""
	charge -= int(preview.cost)
	var module_id := add_module(module_kind, grid_position, rotation)
	if module_id.is_empty():
		charge += int(preview.cost)
		return ""
	_record_command("build_module", {"kind": module_kind, "x": grid_position.x, "y": grid_position.y, "rotation": posmod(rotation, 4)})
	_emit_event("build", module_id, "core", "部署完成，消耗 %d 电荷" % int(preview.cost), {"cost": preview.cost})
	return module_id

func move_module(module_id: String, grid_position: Vector2i) -> bool:
	if not modules.has(module_id):
		last_failure_reason = "模块不存在"
		return false
	var module: Dictionary = modules[module_id]
	var preview := preview_placement(str(module.kind), grid_position, int(module.get("rotation", 0)), module_id)
	if not bool(preview.valid):
		last_failure_reason = str(preview.reason)
		_emit_event("warning", module_id, "core", "无法移动：%s" % preview.reason, preview)
		return false
	var previous: Dictionary = module.get("grid", {}).duplicate(true)
	module.grid = {"x": grid_position.x, "y": grid_position.y}
	_record_command("move_module", {"module": module_id, "x": grid_position.x, "y": grid_position.y})
	_emit_event("build", module_id, "core", "%s 移至 [%d,%d]" % [module.label, grid_position.x, grid_position.y], {"from": previous, "to": module.grid})
	return true

func rotate_module(module_id: String, quarter_turns := 1) -> bool:
	if not modules.has(module_id):
		return false
	var module: Dictionary = modules[module_id]
	module.rotation = posmod(int(module.get("rotation", 0)) + quarter_turns, 4)
	_record_command("rotate_module", {"module": module_id, "rotation": module.rotation})
	_emit_event("build", module_id, "core", "%s 旋转至 %d°" % [module.label, int(module.rotation) * 90], {"rotation": module.rotation})
	return true

func set_module_rotation(module_id: String, rotation: int) -> bool:
	if not modules.has(module_id):
		return false
	var module: Dictionary = modules[module_id]
	var target := posmod(rotation, 4)
	var delta := posmod(target - int(module.get("rotation", 0)), 4)
	if delta == 0:
		return true
	return rotate_module(module_id, delta)

func sell_module(module_id: String) -> int:
	if not modules.has(module_id):
		return 0
	var module: Dictionary = modules[module_id]
	var base_cost := module_cost(str(module.kind))
	var level := maxi(1, int(module.get("level", 1)))
	var refund := maxi(1, int(round(float(base_cost * level) * 0.6)))
	for connection in connections.duplicate(true):
		if connection.from == module_id or connection.to == module_id:
			connections.erase(connection)
	modules.erase(module_id)
	charge += refund
	_record_command("sell_module", {"module": module_id, "refund": refund})
	_emit_event("build", module_id, "core", "%s 已回收，返还 %d 电荷" % [module.label, refund], {"refund": refund})
	return refund

func upgrade_options(module_id: String) -> Array:
	if not modules.has(module_id):
		return []
	var module: Dictionary = modules[module_id]
	var level := int(module.get("level", 1))
	var selected: Dictionary = module.get("upgrades", {})
	var options: Array = []
	for branch in ["overclock", "stabilizer", "automation"]:
		var branch_spec: Dictionary = UPGRADE_BRANCHES[branch]
		var rank := int(selected.get(branch, 0))
		options.append({"branch": branch, "label": branch_spec.label, "description": branch_spec.description, "rank": rank, "next_rank": rank + 1, "cost": int(branch_spec.cost) * (level + rank)})
	return options

func upgrade_module(module_id: String, branch: String) -> bool:
	if not modules.has(module_id) or not UPGRADE_BRANCHES.has(branch):
		return false
	var module: Dictionary = modules[module_id]
	var upgrades: Dictionary = module.get("upgrades", {})
	var rank := int(upgrades.get(branch, 0))
	if rank >= 3:
		last_failure_reason = "该分支已满级"
		return false
	var cost := int(UPGRADE_BRANCHES[branch].cost) * (int(module.get("level", 1)) + rank)
	if charge < cost:
		last_failure_reason = "电荷不足"
		_emit_event("warning", module_id, "core", "升级失败：电荷不足", {"cost": cost})
		return false
	charge -= cost
	upgrades[branch] = rank + 1
	module.upgrades = upgrades
	module.level = int(module.get("level", 1)) + 1
	match branch:
		"overclock":
			module.damage = int(module.damage) + 8
			module.power = int(module.power) + 1
			module.heat_limit = maxi(40, int(module.heat_limit) - 3)
		"stabilizer":
			module.cooldown = maxf(0.2, float(module.cooldown) * 0.88)
			module.heat = maxi(0, int(module.heat) - 2)
		"automation":
			module.range = minf(1.0, float(module.range) + 0.08)
			module.rule_slots = int(module.get("rule_slots", 2)) + 1
	_record_command("upgrade_module", {"module": module_id, "branch": branch, "cost": cost, "rank": rank + 1})
	_emit_event("upgrade", module_id, "core", "%s 编译台升级：%s %d" % [module.label, UPGRADE_BRANCHES[branch].label, rank + 1], {"branch": branch, "rank": rank + 1, "cost": cost})
	return true

func set_paused(value: bool) -> void:
	paused = value
	_record_command("set_paused", {"paused": paused})
	_emit_event("control", "core", "", "战斗%s" % ("暂停" if paused else "继续"))

func toggle_pause() -> void:
	set_paused(not paused)

func add_module(module_kind: String, grid_position := Vector2i.ZERO, rotation := 0) -> String:
	var spec := module_spec(module_kind)
	if spec.is_empty():
		return ""
	var module_id := "M%02d" % next_module_id
	next_module_id += 1
	modules[module_id] = {
		"id": module_id, "kind": module_kind, "label": spec.label,
		"grid": {"x": grid_position.x, "y": grid_position.y},
		"rotation": posmod(rotation, 4), "level": 1,
		"power": int(spec.power), "damage": int(spec.damage),
		"cooldown": float(spec.cooldown), "cooldown_left": 0.0,
		"range": float(spec.range), "heat": 0, "heat_limit": 100,
		"rules": [], "rule_slots": 2, "upgrades": {}, "firmware": "standard", "disabled": false,
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

func get_shop_inventory() -> Array:
	return shop_inventory.duplicate(true)

func refresh_shop(force := false) -> bool:
	if not force and charge < SHOP_REFRESH_COST:
		last_failure_reason = "电荷不足"
		_emit_event("warning", "shop", "core", "刷新商店失败：电荷不足", {"cost": SHOP_REFRESH_COST})
		return false
	if not force:
		charge -= SHOP_REFRESH_COST
	_refresh_shop_inventory(true)
	return true

func _refresh_shop_inventory(consume_rotation: bool) -> void:
	if consume_rotation:
		shop_refreshes += 1
	shop_rotation = posmod(shop_rotation + 1, 64)
	var kinds: Array = MODULE_COSTS.keys()
	kinds.sort()
	shop_inventory.clear()
	for index in SHOP_SIZE:
		var kind: String = str(kinds[posmod(shop_rotation + index * 3, kinds.size())])
		var spec := module_spec(kind)
		shop_inventory.append({
			"slot": index, "kind": kind, "label": str(spec.get("label", kind)),
			"cost": module_cost(kind), "stock": 1,
			"role": str(spec.get("role", "module")),
		})
	_emit_event("shop", "shop", "core", "商店库存已编译", {"rotation": shop_rotation, "inventory": shop_inventory})

func buy_shop_slot(slot: int, to_bench := true) -> bool:
	if slot < 0 or slot >= shop_inventory.size():
		return false
	var item: Dictionary = shop_inventory[slot]
	if int(item.get("stock", 0)) <= 0:
		last_failure_reason = "该商品已售罄"
		return false
	var cost := int(item.get("cost", 0))
	if charge < cost:
		last_failure_reason = "电荷不足"
		_emit_event("warning", "shop", "core", "购买失败：电荷不足", {"slot": slot, "cost": cost})
		return false
	if to_bench and bench.size() >= BENCH_LIMIT:
		last_failure_reason = "备战栏已满"
		return false
	charge -= cost
	item.stock = 0
	shop_inventory[slot] = item
	bench.append({"kind": item.kind, "label": item.label, "rotation": 0, "level": 1})
	_record_command("buy_shop_slot", {"slot": slot, "kind": item.kind, "cost": cost})
	_emit_event("shop", "shop", "core", "购入 %s，已加入备战栏" % item.label, {"slot": slot, "cost": cost})
	return true

func get_bench() -> Array:
	return bench.duplicate(true)

func deploy_bench_item(bench_index: int, grid_position: Vector2i, rotation := 0) -> String:
	if bench_index < 0 or bench_index >= bench.size():
		return ""
	var item: Dictionary = bench[bench_index]
	var module_id := build_module(str(item.kind), grid_position, rotation)
	if module_id.is_empty():
		return ""
	bench.remove_at(bench_index)
	_record_command("deploy_bench_item", {"bench_index": bench_index, "module": module_id})
	return module_id

func discard_bench_item(bench_index: int) -> bool:
	if bench_index < 0 or bench_index >= bench.size():
		return false
	var item: Dictionary = bench[bench_index]
	bench.remove_at(bench_index)
	var refund := maxi(1, int(round(float(module_cost(str(item.kind))) * 0.25)))
	charge += refund
	_emit_event("shop", "shop", "core", "弃置 %s，返还 %d 电荷" % [item.label, refund], {"refund": refund})
	return true

func start_battle() -> bool:
	if modules.is_empty():
		_emit_event("warning", "core", "", "没有可运行模块")
		return false
	running = true
	paused = false
	finished = false
	victory = false
	phase = "combat"
	last_failure_reason = ""
	current_wave = 1
	_record_command("start_battle")
	_spawn_wave(current_wave)
	_emit_event("wave", "core", "", "第 1 波开始", {"wave": current_wave})
	return true

func retry_battle() -> bool:
	if modules.is_empty():
		return start_battle()
	enemies.clear()
	connections = connections.duplicate(true)
	base_integrity = 100
	finished = false
	victory = false
	running = true
	paused = false
	phase = "combat"
	current_wave = 1
	tick_count = 0
	elapsed = 0.0
	accumulator = 0.0
	_record_command("retry_battle")
	_spawn_wave(current_wave)
	_emit_event("control", "core", "", "系统已复位，第 1 波重试", {"reason": last_failure_reason})
	return true

func settle_wave() -> Dictionary:
	var settlement := {"wave": current_wave, "reward": wave_reward, "charge": charge, "integrity": base_integrity, "phase": phase}
	_emit_event("settlement", "core", "", "第 %d 波结算：+%d 电荷" % [current_wave, wave_reward], settlement)
	return settlement

func get_diagnostics() -> Dictionary:
	var warnings: Array = []
	var module_ids: Array = modules.keys()
	module_ids.sort()
	for module_id in module_ids:
		var module: Dictionary = modules[module_id]
		var heat_value := int(module.get("heat", 0))
		var heat_limit := maxi(1, int(module.get("heat_limit", 100)))
		if heat_value >= int(float(heat_limit) * 0.8):
			warnings.append({"module": module_id, "severity": "warning", "text": "%s 热量达到 %d%%" % [module.label, int(float(heat_value) / float(heat_limit) * 100.0)]})
		if bool(module.get("disabled", false)):
			warnings.append({"module": module_id, "severity": "critical", "text": "%s 已停机" % module.label})
	for connection in connections:
		if not modules.has(connection.from) or not modules.has(connection.to):
			warnings.append({"module": connection.from, "severity": "critical", "text": "存在悬空线路"})
	return {"warnings": warnings, "warning_count": warnings.size(), "phase": phase, "last_failure": last_failure_reason}

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
	wave_reward = 12 + current_wave * 3
	charge += wave_reward
	scrap += current_wave
	phase = "settlement"
	_emit_event("wave_clear", "core", "", "第 %d 波完成，奖励 %d 电荷" % [current_wave, wave_reward], {"wave": current_wave, "charge": charge, "reward": wave_reward, "scrap": scrap})
	settle_wave()
	if current_wave >= WAVE_COUNT:
		finished = true
		running = false
		phase = "victory" if base_integrity > 0 else "defeat"
		victory = base_integrity > 0
		_emit_event("victory" if victory else "defeat", "core", "", "堡垒完成 10 波")
		return
	current_wave += 1
	phase = "combat"
	_spawn_wave(current_wave)
	_emit_event("wave", "core", "", "第 %d 波开始" % current_wave, {"wave": current_wave})

func get_snapshot() -> Dictionary:
	return {
		"seed": seed_value, "tick": tick_count, "elapsed": elapsed,
		"speed": speed, "paused": paused, "running": running,
		"finished": finished, "victory": victory, "wave": current_wave,
		"integrity": base_integrity, "charge": charge, "scrap": scrap,
		"phase": phase, "wave_reward": wave_reward,
		"bench": bench.duplicate(true), "shop": shop_inventory.duplicate(true),
		"shop_rotation": shop_rotation, "shop_refreshes": shop_refreshes,
		"diagnostics": get_diagnostics(),
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
	scrap = int(snapshot_state.get("scrap", 0))
	phase = str(snapshot_state.get("phase", "build"))
	wave_reward = int(snapshot_state.get("wave_reward", 0))
	bench = snapshot_state.get("bench", []).duplicate(true)
	shop_inventory = snapshot_state.get("shop", []).duplicate(true)
	shop_rotation = int(snapshot_state.get("shop_rotation", 0))
	shop_refreshes = int(snapshot_state.get("shop_refreshes", 0))
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

