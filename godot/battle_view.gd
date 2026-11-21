extends Control
class_name BattleView

## Presentation layer for the Circuit Bastion vertical slice.
## The view accepts plain Dictionaries so it can run with the deterministic
## simulator or with the built-in preview state while the project boots.

signal module_selected(module_id: String)
signal cell_selected(cell: Vector2i)
signal command_requested(command: String)
signal event_selected(event_index: int)

const GRID_COLUMNS := 8
const GRID_ROWS := 6
const TOP_BAR_HEIGHT := 72.0
const MARGIN := 28.0
const RIGHT_PANEL_WIDTH := 326.0
const BOTTOM_BAR_HEIGHT := 84.0

var simulation: Object
var snapshot: Dictionary = {}
var selected_module_id := "pulse_cannon"
var selected_cell := Vector2i(4, 3)
var highlighted_event := -1
var route_focus := ""
var speed := 1
var paused := false
var phase := 0.0
var hover_cell := Vector2i(-1, -1)

var modules: Array = [
	{"id": "scanner", "name": "探针", "cell": Vector2i(1, 1), "color": Color("#5ed6ff"), "load": 0.22},
	{"id": "router", "name": "路由器", "cell": Vector2i(3, 2), "color": Color("#b690ff"), "load": 0.48},
	{"id": "pulse_cannon", "name": "脉冲炮", "cell": Vector2i(5, 3), "color": Color("#ffca62"), "load": 0.73},
	{"id": "cooler", "name": "散热器", "cell": Vector2i(6, 1), "color": Color("#68e3bf"), "load": 0.31},
	{"id": "battery", "name": "电池", "cell": Vector2i(2, 4), "color": Color("#82aaff"), "load": 0.18},
]

var events: Array = [
	{"time": "00:18.420", "type": "SIGNAL", "text": "脉冲炮 → 路由器", "color": Color("#72d7ff")},
	{"time": "00:17.900", "type": "HIT", "text": "脉冲炮 命中裂隙虫", "color": Color("#ffca62")},
	{"time": "00:16.740", "type": "RULE", "text": "过滤器 放行目标", "color": Color("#b690ff")},
	{"time": "00:15.120", "type": "POWER", "text": "电池输出 4.2 kW", "color": Color("#68e3bf")},
]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	phase = fmod(phase + delta * (0.8 if not paused else 0.16), TAU)
	if simulation != null and simulation.has_method("get_snapshot"):
		set_snapshot(simulation.get_snapshot())
	queue_redraw()


func set_simulation(value: Object) -> void:
	simulation = value
	queue_redraw()


func set_snapshot(value: Dictionary) -> void:
	snapshot = value.duplicate(true)
	if snapshot.has("paused"):
		paused = bool(snapshot.paused)
	if snapshot.has("speed"):
		speed = int(snapshot.speed)
	if snapshot.has("modules") and snapshot.modules is Array:
		modules = snapshot.modules
	if snapshot.has("events") and snapshot.events is Array:
		events = snapshot.events
	queue_redraw()

func highlight_event(event: Dictionary) -> void:
	route_focus = str(event.get("type", event.get("kind", ""))).to_upper()
	queue_redraw()


func _draw() -> void:
	var size := get_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Color("#071017"))
	_draw_top_bar(size)
	_draw_battlefield(size)
	_draw_right_panel(size)
	_draw_bottom_bar(size)


func _draw_top_bar(size: Vector2) -> void:
	draw_rect(Rect2(0, 0, size.x, TOP_BAR_HEIGHT), Color("#0b1822"))
	draw_line(Vector2(0, TOP_BAR_HEIGHT - 1), Vector2(size.x, TOP_BAR_HEIGHT - 1), Color("#1d3b4b"), 1.0)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(MARGIN, 31), "CIRCUIT BASTION", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#e9f4f7"))
	draw_string(font, Vector2(MARGIN, 53), "DETERMINISTIC DEFENSE SYSTEM // LOCAL BUILD", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#6a8a98"))
	var status := "战斗已暂停" if paused else "战斗运行中"
	var status_color := Color("#ffca62") if paused else Color("#68e3bf")
	draw_circle(Vector2(size.x - 326, 30), 5.0, status_color)
	draw_string(font, Vector2(size.x - 310, 35), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, status_color)
	draw_string(font, Vector2(size.x - 310, 54), "WAVE %02d / 10" % int(snapshot.get("wave", 3)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#9fb8c1"))
	draw_string(font, Vector2(size.x - 130, 35), "电荷  %03d" % int(snapshot.get("charge", 128)), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ffca62"))
	draw_string(font, Vector2(size.x - 130, 54), "核心  %02d%%" % int(snapshot.get("integrity", 86)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#68e3bf"))


func _draw_battlefield(size: Vector2) -> void:
	var area_width := size.x - RIGHT_PANEL_WIDTH - MARGIN * 3.0
	var board := Rect2(MARGIN, TOP_BAR_HEIGHT + 20.0, area_width, size.y - TOP_BAR_HEIGHT - BOTTOM_BAR_HEIGHT - 40.0)
	draw_rect(board, Color("#091923"), true)
	draw_rect(board, Color("#1c3c4b"), false, 1.0)
	var cell_size: float = minf((board.size.x - 40.0) / float(GRID_COLUMNS), (board.size.y - 72.0) / float(GRID_ROWS))
	var grid_size := Vector2(cell_size * GRID_COLUMNS, cell_size * GRID_ROWS)
	var origin := board.position + Vector2((board.size.x - grid_size.x) * 0.5, 44.0)
	_draw_board_header(board)
	_draw_routes(origin, cell_size)
	for row in GRID_ROWS:
		for column in GRID_COLUMNS:
			var cell := Vector2i(column, row)
			var rect := Rect2(origin + Vector2(column, row) * cell_size + Vector2(3, 3), Vector2(cell_size - 6, cell_size - 6))
			var fill := Color("#0d222c") if cell != hover_cell else Color("#173745")
			draw_rect(rect, fill, true)
			draw_rect(rect, Color("#1b3b48"), false, 1.0)
	_draw_modules(origin, cell_size)
	_draw_enemies(origin, cell_size)
	_draw_path_legend(board)


func _draw_board_header(board: Rect2) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, board.position + Vector2(18, 26), "SECTOR 07 / FOUNDRY RING", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#d7e8ed"))
	draw_string(font, board.position + Vector2(board.size.x - 184, 26), "SIM TICK  %06d" % int(snapshot.get("tick", 1842)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#6f929f"))


func _draw_routes(origin: Vector2, cell_size: float) -> void:
	var signal_points := PackedVector2Array([
		_cell_center(origin, cell_size, Vector2i(0, 3)),
		_cell_center(origin, cell_size, Vector2i(3, 2)),
		_cell_center(origin, cell_size, Vector2i(5, 3)),
		_cell_center(origin, cell_size, Vector2i(7, 3)),
	])
	var energy_points := PackedVector2Array([
		_cell_center(origin, cell_size, Vector2i(2, 4)),
		_cell_center(origin, cell_size, Vector2i(3, 4)),
		_cell_center(origin, cell_size, Vector2i(5, 3)),
	])
	var hazard_points := PackedVector2Array([
		_cell_center(origin, cell_size, Vector2i(6, 1)),
		_cell_center(origin, cell_size, Vector2i(6, 3)),
		_cell_center(origin, cell_size, Vector2i(6, 5)),
	])
	_draw_polyline(signal_points, Color("#42c7ee"), 6.0 if route_focus in ["SIGNAL", "CONNECTION", "ACTION"] else 4.0)
	_draw_polyline(energy_points, Color("#ffca62"), 5.0 if route_focus in ["POWER", "ENERGY"] else 3.0)
	_draw_polyline(hazard_points, Color("#ff6b75"), 5.0 if route_focus in ["BREACH", "DAMAGE"] else 2.0)
	if highlighted_event == 0 or highlighted_event == 1:
		_draw_polyline(signal_points, Color("#d9fbff"), 6.0)
	for point in signal_points:
		draw_circle(point, 3.0 + sin(phase + point.x * 0.02) * 1.0, Color("#a7f0ff"))


func _draw_polyline(points: PackedVector2Array, color: Color, width: float) -> void:
	for index in range(points.size() - 1):
		draw_line(points[index], points[index + 1], color.darkened(0.42), width + 5.0)
		draw_line(points[index], points[index + 1], color, width)


func _draw_modules(origin: Vector2, cell_size: float) -> void:
	var font := ThemeDB.fallback_font
	for module in modules:
		var cell: Vector2i = module.get("cell", Vector2i.ZERO)
		var center := _cell_center(origin, cell_size, cell)
		var raw_color = module.get("color", Color("#72d7ff"))
		var color: Color = raw_color if raw_color is Color else Color(str(raw_color))
		var selected: bool = str(module.get("id", "")) == selected_module_id
		var radius := cell_size * 0.30
		if selected:
			draw_circle(center, radius + 7.0, Color(color, 0.10))
			draw_arc(center, radius + 7.0, phase, phase + 4.3, 24, Color(color, 0.7), 2.0)
		draw_circle(center, radius, Color("#102834"))
		draw_circle(center, radius, color, false, 3.0)
		draw_line(center - Vector2(radius * 0.58, 0), center + Vector2(radius * 0.58, 0), color, 2.0)
		draw_line(center - Vector2(0, radius * 0.58), center + Vector2(0, radius * 0.58), color, 2.0)
		draw_string(font, center + Vector2(-radius, radius + 18), str(module.get("name", "模块")), HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 11, Color("#c5dbe2"))
		var load: float = float(module.get("load", 0.2))
		var bar := Rect2(center + Vector2(-radius, radius + 25), Vector2(radius * 2.0, 4))
		draw_rect(bar, Color("#18313c"), true)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clamp(load, 0.0, 1.0), bar.size.y)), color, true)


func _draw_enemies(origin: Vector2, cell_size: float) -> void:
	var font := ThemeDB.fallback_font
	var enemy_list: Array = []
	var enemy_state: Dictionary = snapshot.get("enemies", {})
	if not enemy_state.is_empty():
		for enemy_id in enemy_state.keys():
			var enemy: Dictionary = enemy_state[enemy_id]
			var progress: float = clampf(float(enemy.get("progress", 0.0)), 0.0, 0.99)
			enemy_list.append({
				"cell": Vector2i(int(progress * 7.0), 3),
				"hp": float(enemy.get("hp", 1.0)) / maxf(1.0, float(enemy.get("max_hp", 1.0))),
				"label": str(enemy.get("label", "目标")),
			})
	else:
		enemy_list = [
			{"cell": Vector2i(0, 3), "hp": 0.72, "label": "裂隙虫"},
			{"cell": Vector2i(1, 3), "hp": 0.46, "label": "裂隙虫"},
			{"cell": Vector2i(2, 3), "hp": 0.88, "label": "侦察蜂"},
		]
	for enemy in enemy_list:
		var center := _cell_center(origin, cell_size, enemy.cell) + Vector2(0, -cell_size * 0.25)
		draw_circle(center, 9.0, Color("#ff6b75"))
		draw_circle(center, 13.0 + sin(phase * 1.4 + center.x) * 2.0, Color("#ff6b75", 0.12), false, 2.0)
		var hp_rect := Rect2(center + Vector2(-17, 15), Vector2(34, 4))
		draw_rect(hp_rect, Color("#311d27"), true)
		draw_rect(Rect2(hp_rect.position, Vector2(hp_rect.size.x * enemy.hp, hp_rect.size.y)), Color("#ff6b75"), true)
		draw_string(font, center + Vector2(-25, -18), enemy.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#a8c0c8"))


func _draw_path_legend(board: Rect2) -> void:
	var y := board.position.y + board.size.y - 22.0
	var font := ThemeDB.fallback_font
	_draw_legend_item(board.position.x + 18, y, Color("#42c7ee"), "信号线")
	_draw_legend_item(board.position.x + 104, y, Color("#ffca62"), "能源线")
	_draw_legend_item(board.position.x + 190, y, Color("#ff6b75"), "过热线")
	draw_string(font, Vector2(board.position.x + board.size.x - 170, y + 4), "点击事件追踪传播路径", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#7697a4"))


func _draw_legend_item(x: float, y: float, color: Color, label: String) -> void:
	var font := ThemeDB.fallback_font
	draw_line(Vector2(x, y), Vector2(x + 22, y), color, 3.0)
	draw_string(font, Vector2(x + 29, y + 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#92adb6"))


func _draw_right_panel(size: Vector2) -> void:
	var x := size.x - RIGHT_PANEL_WIDTH - MARGIN
	var top := TOP_BAR_HEIGHT + 20.0
	var panel := Rect2(x, top, RIGHT_PANEL_WIDTH, size.y - TOP_BAR_HEIGHT - BOTTOM_BAR_HEIGHT - 40.0)
	draw_rect(panel, Color("#0b1a23"), true)
	draw_rect(panel, Color("#1d3b4b"), false, 1.0)
	var font := ThemeDB.fallback_font
	draw_string(font, panel.position + Vector2(18, 28), "系统检查", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#d7e8ed"))
	draw_string(font, panel.position + Vector2(18, 50), "SELECTED MODULE / PORTS / RULES", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#64848e"))
	var selected_name := "脉冲炮"
	for module in modules:
		if module.get("id", "") == selected_module_id:
			selected_name = str(module.get("name", selected_name))
	var card := Rect2(panel.position + Vector2(16, 68), Vector2(panel.size.x - 32, 82))
	draw_rect(card, Color("#112833"), true)
	draw_rect(card, Color("#345567"), false, 1.0)
	draw_circle(card.position + Vector2(28, 40), 15.0, Color("#ffca62", 0.18))
	draw_circle(card.position + Vector2(28, 40), 11.0, Color("#ffca62"), false, 2.0)
	draw_string(font, card.position + Vector2(56, 32), selected_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#f2d18a"))
	draw_string(font, card.position + Vector2(56, 53), "执行模块 · Tier 02", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#86a5af"))
	draw_string(font, card.position + Vector2(56, 70), "功率  4.2 kW     延迟  80 ms", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#a8c0c8"))
	draw_string(font, panel.position + Vector2(18, 182), "端口", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#8eb0bb"))
	_draw_port(panel.position + Vector2(18, 202), "IN / SIGNAL", Color("#42c7ee"), "路由器 · 12 events/s")
	_draw_port(panel.position + Vector2(18, 232), "OUT / TARGET", Color("#ffca62"), "输出节点 · 1.0×")
	draw_string(font, panel.position + Vector2(18, 284), "规则槽  2 / 3", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#8eb0bb"))
	_draw_rule(panel.position + Vector2(18, 300), "目标类型 == 裂隙虫", "脉冲伤害 +24", Color("#b690ff"))
	_draw_rule(panel.position + Vector2(18, 343), "若线路拥塞 > 60%", "切换为低功率", Color("#ffca62"))
	_draw_event_log(panel)


func _draw_port(position: Vector2, label: String, color: Color, value: String) -> void:
	var font := ThemeDB.fallback_font
	draw_circle(position + Vector2(5, 7), 5.0, color)
	draw_string(font, position + Vector2(18, 11), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)
	draw_string(font, position + Vector2(120, 11), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#a2bac2"))


func _draw_rule(position: Vector2, condition: String, action: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var rect := Rect2(position, Vector2(RIGHT_PANEL_WIDTH - 36, 34))
	draw_rect(rect, Color("#0e222d"), true)
	draw_rect(rect, Color("#264653"), false, 1.0)
	draw_string(font, position + Vector2(10, 14), condition, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#d2e2e6"))
	draw_string(font, position + Vector2(10, 27), "→ " + action, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, color)


func _draw_event_log(panel: Rect2) -> void:
	var font := ThemeDB.fallback_font
	var y := panel.position.y + panel.size.y - 192.0
	draw_string(font, Vector2(panel.position.x + 18, y), "事件追踪", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#8eb0bb"))
	draw_string(font, Vector2(panel.position.x + panel.size.x - 100, y), "%02d EVENTS" % events.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#60818c"))
	for index in range(min(events.size(), 4)):
		var event: Dictionary = events[index]
		var row := Rect2(Vector2(panel.position.x + 14, y + 12 + index * 34), Vector2(panel.size.x - 28, 28))
		if index == highlighted_event:
			draw_rect(row, Color("#17333f"), true)
		var raw_color = event.get("color", Color("#72d7ff"))
		var event_color: Color = raw_color if raw_color is Color else Color(str(raw_color))
		draw_circle(row.position + Vector2(10, 14), 3.0, event_color)
		draw_string(font, row.position + Vector2(20, 12), str(event.get("time", "00:00.000")), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#62818d"))
		draw_string(font, row.position + Vector2(82, 12), str(event.get("type", "EVENT")), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, event_color)
		draw_string(font, row.position + Vector2(20, 24), str(event.get("text", "未知事件")), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#d3e2e5"))


func _draw_bottom_bar(size: Vector2) -> void:
	var y := size.y - BOTTOM_BAR_HEIGHT
	draw_rect(Rect2(0, y, size.x, BOTTOM_BAR_HEIGHT), Color("#0b1822"), true)
	draw_line(Vector2(0, y), Vector2(size.x, y), Color("#1d3b4b"), 1.0)
	_draw_button(Rect2(MARGIN, y + 20, 118, 38), "暂停" if not paused else "继续", "pause", Color("#ffca62"))
	_draw_button(Rect2(MARGIN + 128, y + 20, 80, 38), "%d×" % speed, "speed", Color("#72d7ff"))
	_draw_button(Rect2(MARGIN + 218, y + 20, 118, 38), "事件回放", "replay", Color("#b690ff"))
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 290, y + 43), "确定性种子  CB-07-1842", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#6b8d98"))


func _draw_button(rect: Rect2, label: String, command: String, color: Color) -> void:
	var active := (command == "pause" and paused) or (command == "speed" and speed > 1)
	draw_rect(rect, Color(color, 0.18 if active else 0.08), true)
	draw_rect(rect, color, false, 1.0)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(0, 24), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 12, color)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hover_cell = _cell_at(event.position)
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_click(event.position)


func _handle_click(position: Vector2) -> void:
	var size := get_rect().size
	var bottom_y := size.y - BOTTOM_BAR_HEIGHT
	if position.y >= bottom_y:
		if Rect2(MARGIN, bottom_y + 20, 118, 38).has_point(position):
			paused = not paused
			command_requested.emit("pause" if paused else "resume")
		elif Rect2(MARGIN + 128, bottom_y + 20, 80, 38).has_point(position):
			speed = 1 if speed >= 4 else speed * 2
			command_requested.emit("speed:%d" % speed)
		elif Rect2(MARGIN + 218, bottom_y + 20, 118, 38).has_point(position):
			command_requested.emit("replay")
		queue_redraw()
		return
	var event_index := _event_at(position, size)
	if event_index >= 0:
		highlighted_event = event_index
		event_selected.emit(event_index)
		queue_redraw()
		return
	var cell := _cell_at(position)
	if cell.x >= 0:
		selected_cell = cell
		for module in modules:
			if module.get("cell", Vector2i(-1, -1)) == cell:
				selected_module_id = str(module.get("id", selected_module_id))
				module_selected.emit(selected_module_id)
		cell_selected.emit(cell)
		queue_redraw()


func _cell_at(position: Vector2) -> Vector2i:
	var size := get_rect().size
	var area_width := size.x - RIGHT_PANEL_WIDTH - MARGIN * 3.0
	var board := Rect2(MARGIN, TOP_BAR_HEIGHT + 20.0, area_width, size.y - TOP_BAR_HEIGHT - BOTTOM_BAR_HEIGHT - 40.0)
	var cell_size: float = minf((board.size.x - 40.0) / float(GRID_COLUMNS), (board.size.y - 72.0) / float(GRID_ROWS))
	var grid_size := Vector2(cell_size * GRID_COLUMNS, cell_size * GRID_ROWS)
	var origin := board.position + Vector2((board.size.x - grid_size.x) * 0.5, 44.0)
	var local: Vector2 = (position - origin) / cell_size
	var cell := Vector2i(floor(local.x), floor(local.y))
	if cell.x < 0 or cell.y < 0 or cell.x >= GRID_COLUMNS or cell.y >= GRID_ROWS:
		return Vector2i(-1, -1)
	return cell


func _event_at(position: Vector2, size: Vector2) -> int:
	var panel_x := size.x - RIGHT_PANEL_WIDTH - MARGIN
	var panel_top := TOP_BAR_HEIGHT + 20.0
	var panel := Rect2(panel_x, panel_top, RIGHT_PANEL_WIDTH, size.y - TOP_BAR_HEIGHT - BOTTOM_BAR_HEIGHT - 40.0)
	var y := panel.position.y + panel.size.y - 192.0
	for index in range(min(events.size(), 4)):
		var row := Rect2(panel.position.x + 14, y + 12 + index * 34, panel.size.x - 28, 28)
		if row.has_point(position):
			return index
	return -1


func _cell_center(origin: Vector2, cell_size: float, cell: Vector2i) -> Vector2:
	return origin + (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size
