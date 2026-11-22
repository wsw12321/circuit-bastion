extends Control
class_name BattleView

## Presentation layer for the Circuit Bastion vertical slice.
## The view accepts plain Dictionaries so it can run with the deterministic
## simulator or with the built-in preview state while the project boots.

signal module_selected(module_id: String)
signal cell_selected(cell: Vector2i)
signal command_requested(command: String)
signal event_selected(event_index: int)
signal interaction_feedback(message: String, tone: String)

const GRID_COLUMNS := 8
const GRID_ROWS := 6
const TOP_BAR_HEIGHT := 72.0
const MARGIN := 28.0
const RIGHT_PANEL_WIDTH := 326.0
const BOTTOM_BAR_HEIGHT := 84.0
const CHARACTER_ART := preload("res://godot/character_art.gd")
const UI_OVERLAY_SCRIPT := preload("res://godot/battle_ui_overlay.gd")

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
var last_tick := -1
var route_flash := 0.0
var route_flash_color := Color("#72d7ff")
var build_mode := false
var build_kind := "pulse_cannon"
var build_rotation := 0
var dragging_module_id := ""
var drag_origin_cell := Vector2i(-1, -1)
var preview_cell := Vector2i(-1, -1)
var preview_valid := false
var shop_revision := 1
var shop_inventory: Array = []
var bench_items: Array = []
var selected_upgrade_branch := "overclock"
var feedback_message := "就绪 · 点击商店模块开始部署"
var feedback_tone := "info"
var touch_pointer_id := -1
var enemy_hp_cache: Dictionary = {}
var enemy_last_state: Dictionary = {}
var enemy_hit_flash: Dictionary = {}
var enemy_death_effects: Array = []
var art_tick := -1
var character_scale := 1.0
var fx_items: Array = []
@export_enum("cyan", "amber", "violet", "mono") var effect_theme_id := "cyan"
@export var low_performance_effects := false
@export_range(0, 2, 1) var effect_quality := 2
var effect_colors: Dictionary = {}
var screen_feedback_time := 0.0
var screen_feedback_strength := 0.0
var wave_rhythm_phase := 0.0
var seen_event_keys: Dictionary = {}
var wave_banner_time := 0.0
var wave_banner_text := ""
var wave_banner_color := Color("#b690ff")
var result_transition_time := 0.0
var previous_finished := false
var previous_victory := false
var ui_overlay: Node
@export var use_3d_battlefield := true

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
	_configure_effects()
	if ui_overlay == null:
		ui_overlay = UI_OVERLAY_SCRIPT.new()
		add_child(ui_overlay)
		ui_overlay.call("attach", self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	grab_focus()
	set_process(true)
	queue_redraw()


func _configure_effects() -> void:
	var configured_theme := str(ProjectSettings.get_setting("circuit_bastion/effect_theme", effect_theme_id))
	if configured_theme in ["cyan", "amber", "violet", "mono"]:
		effect_theme_id = configured_theme
	low_performance_effects = bool(ProjectSettings.get_setting("circuit_bastion/low_performance_effects", low_performance_effects))
	if OS.has_feature("mobile") or low_performance_effects:
		effect_quality = mini(effect_quality, 1)
	match effect_theme_id:
		"amber":
			effect_colors = {
				"signal": Color("#ffcf70"), "energy": Color("#ffe29a"), "hazard": Color("#ff806e"),
				"hit": Color("#fff4c2"), "overheat": Color("#ff9b5c"), "breach": Color("#ff5c67"),
				"success": Color("#96f0c3"), "banner": Color("#ffd166")
			}
		"violet":
			effect_colors = {
				"signal": Color("#75d9ff"), "energy": Color("#bda4ff"), "hazard": Color("#ff83b7"),
				"hit": Color("#f6e8ff"), "overheat": Color("#ff9bd0"), "breach": Color("#ff668d"),
				"success": Color("#83f1d6"), "banner": Color("#c4a7ff")
			}
		"mono":
			effect_colors = {
				"signal": Color("#d6e3e8"), "energy": Color("#b9c7cc"), "hazard": Color("#8f9ca1"),
				"hit": Color("#ffffff"), "overheat": Color("#d4d4d4"), "breach": Color("#aeb8bc"),
				"success": Color("#e4eef1"), "banner": Color("#d6e3e8")
			}
		_:
			effect_colors = {
				"signal": Color("#42c7ee"), "energy": Color("#ffca62"), "hazard": Color("#ff6b75"),
				"hit": Color("#fff2c4"), "overheat": Color("#ff8a5b"), "breach": Color("#ff6b75"),
				"success": Color("#68e3bf"), "banner": Color("#b690ff")
			}

func set_effect_theme(theme_id: String) -> void:
	effect_theme_id = theme_id
	_configure_effects()
	queue_redraw()

func set_effect_quality(quality: int) -> void:
	effect_quality = clampi(quality, 0, 2)
	queue_redraw()

func _effect_color(role: String, fallback: Color) -> Color:
	var value = effect_colors.get(role, fallback)
	return value if value is Color else fallback

func _process(delta: float) -> void:
	phase = fmod(phase + delta * (0.8 if not paused else 0.16), TAU)
	route_flash = maxf(0.0, route_flash - delta * 1.7)
	_update_fx(delta)
	for enemy_id in enemy_hit_flash.keys():
		var remaining := float(enemy_hit_flash[enemy_id]) - delta * 4.2
		if remaining <= 0.0:
			enemy_hit_flash.erase(enemy_id)
		else:
			enemy_hit_flash[enemy_id] = remaining
	for index in range(enemy_death_effects.size() - 1, -1, -1):
		var effect: Dictionary = enemy_death_effects[index]
		effect["ttl"] = float(effect.get("ttl", 0.0)) - delta
		if float(effect.get("ttl", 0.0)) <= 0.0:
			enemy_death_effects.remove_at(index)
	if simulation != null and simulation.has_method("get_snapshot"):
		set_snapshot(simulation.get_snapshot())
	queue_redraw()


func _is_compact(size: Vector2) -> bool:
	return size.x < 980.0 or size.x < size.y * 0.9


func _bottom_bar_height(size: Vector2) -> float:
	return 190.0 if _is_compact(size) else BOTTOM_BAR_HEIGHT


func set_simulation(value: Object) -> void:
	simulation = value
	queue_redraw()


func set_snapshot(value: Dictionary) -> void:
	snapshot = value.duplicate(true)
	var tick := int(snapshot.get("tick", 0))
	_sync_enemy_art(tick)
	if last_tick >= 0 and tick != last_tick:
		route_flash = 1.0
		route_flash_color = Color("#ffca62") if tick % 3 == 0 else Color("#72d7ff")
	last_tick = tick
	if snapshot.has("paused"):
		paused = bool(snapshot.paused)
	if snapshot.has("speed"):
		speed = int(snapshot.speed)
	if snapshot.has("modules") and snapshot.modules is Array:
		modules = snapshot.modules
	if snapshot.has("events") and snapshot.events is Array:
		events = snapshot.events
	if snapshot.has("shop_revision"):
		shop_revision = int(snapshot.get("shop_revision", shop_revision))
	elif snapshot.has("shop_refreshes"):
		shop_revision = int(snapshot.get("shop_refreshes", 0)) + 1
	if snapshot.has("phase"):
		feedback_message = str(snapshot.get("phase", feedback_message))
	if snapshot.has("shop") and snapshot.shop is Array:
		shop_inventory = snapshot.shop.duplicate(true)
	if snapshot.has("bench") and snapshot.bench is Array:
		bench_items = snapshot.bench.duplicate(true)
	_consume_new_events()
	var finished_now := bool(snapshot.get("finished", false))
	var victory_now := bool(snapshot.get("victory", false))
	if finished_now and not previous_finished:
		result_transition_time = 0.0
		_start_result_transition("victory" if victory_now else "defeat")
	previous_finished = finished_now
	previous_victory = victory_now
	queue_redraw()

func highlight_event(event: Dictionary) -> void:
	var kind := str(event.get("type", event.get("kind", ""))).to_upper()
	if kind in ["ACTION", "HIT", "ENEMY_DESTROYED", "SIGNAL", "CONNECTION", "RULE"]:
		route_focus = "SIGNAL"
	elif kind in ["BREACH", "OVERHEAT", "DISCONNECT"]:
		route_focus = "BREACH"
	elif kind in ["POWER", "ENERGY", "CONTROL"]:
		route_focus = "POWER"
	else:
		route_focus = kind
	queue_redraw()


func _draw() -> void:
	var size := get_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Color("#071017", 0.16 if use_3d_battlefield else 1.0))
	_draw_top_bar(size)
	if use_3d_battlefield:
		_draw_battlefield_frame(size)
	else:
		_draw_battlefield(size)
	_draw_right_panel(size)
	_draw_bottom_bar(size)
	_draw_result_banner(size)
	_draw_fx_overlay(size)

func _draw_battlefield_frame(size: Vector2) -> void:
	var panel_reserve := 0.0 if _is_compact(size) else RIGHT_PANEL_WIDTH + MARGIN * 3.0
	var area_width := maxf(180.0, size.x - panel_reserve)
	var board := Rect2(MARGIN, TOP_BAR_HEIGHT + 20.0, area_width, size.y - TOP_BAR_HEIGHT - _bottom_bar_height(size) - 40.0)
	draw_rect(board, Color("#091923", 0.16), true)
	draw_rect(board, Color("#1c3c4b", 0.72), false, 1.0)
	draw_string(ThemeDB.fallback_font, board.position + Vector2(18, 26), "SECTOR 07 / 3D BATTLEFIELD", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#d7e8ed"))
	draw_string(ThemeDB.fallback_font, board.position + Vector2(board.size.x - 164, 26), "CAMERA 45°", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#72d7ff"))
	draw_string(ThemeDB.fallback_font, board.position + Vector2(18, board.size.y - 18), "拖动旋转 · 滚轮/双指缩放", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#6f929f"))


func _draw_top_bar(size: Vector2) -> void:
	draw_rect(Rect2(0, 0, size.x, TOP_BAR_HEIGHT), Color("#0b1822"))
	draw_line(Vector2(0, TOP_BAR_HEIGHT - 1), Vector2(size.x, TOP_BAR_HEIGHT - 1), Color("#1d3b4b"), 1.0)
	var font := ThemeDB.fallback_font
	if _is_compact(size):
		draw_string(font, Vector2(MARGIN, 28), "CIRCUIT BASTION", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#e9f4f7"))
		draw_string(font, Vector2(MARGIN, 50), "WAVE %02d · %s" % [int(snapshot.get("wave", 1)), "暂停" if paused else "运行"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#8daab4"))
		draw_string(font, Vector2(size.x - 118, 28), "C %03d" % int(snapshot.get("charge", 128)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ffca62"))
		draw_string(font, Vector2(size.x - 118, 50), "CORE %02d%%" % int(snapshot.get("integrity", 86)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#68e3bf"))
		return
	draw_string(font, Vector2(MARGIN, 31), "CIRCUIT BASTION", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#e9f4f7"))
	draw_string(font, Vector2(MARGIN, 53), "DETERMINISTIC DEFENSE SYSTEM // LOCAL BUILD", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#6a8a98"))
	var status := "战斗已暂停" if paused else "战斗运行中"
	var status_color := Color("#ffca62") if paused else Color("#68e3bf")
	draw_circle(Vector2(size.x - 326, 30), 5.0, status_color)
	draw_string(font, Vector2(size.x - 310, 35), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, status_color)
	draw_string(font, Vector2(size.x - 310, 54), "WAVE %02d / 10" % int(snapshot.get("wave", 3)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#9fb8c1"))
	draw_string(font, Vector2(size.x - 198, 54), str(snapshot.get("phase", "combat")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#72d7ff"))
	draw_string(font, Vector2(size.x - 130, 35), "电荷  %03d" % int(snapshot.get("charge", 128)), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ffca62"))
	draw_string(font, Vector2(size.x - 130, 54), "核心  %02d%%" % int(snapshot.get("integrity", 86)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#68e3bf"))
	var wave_progress := clampf(float(snapshot.get("wave", 1)) / 10.0, 0.0, 1.0)
	draw_rect(Rect2(MARGIN, TOP_BAR_HEIGHT - 5, 240, 2), Color("#15303b"), true)
	draw_rect(Rect2(MARGIN, TOP_BAR_HEIGHT - 5, 240 * wave_progress, 2), Color("#42c7ee"), true)
	draw_string(font, Vector2(MARGIN + 255, TOP_BAR_HEIGHT - 1), "LIVE TELEMETRY", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#47717d"))


func _draw_battlefield(size: Vector2) -> void:
	var panel_reserve := 0.0 if _is_compact(size) else RIGHT_PANEL_WIDTH + MARGIN * 3.0
	var area_width := maxf(180.0, size.x - panel_reserve)
	var board := Rect2(MARGIN, TOP_BAR_HEIGHT + 20.0, area_width, size.y - TOP_BAR_HEIGHT - _bottom_bar_height(size) - 40.0)
	draw_rect(board, Color("#091923"), true)
	draw_rect(board, Color("#1c3c4b"), false, 1.0)
	draw_rect(Rect2(board.position + Vector2(8, 8), board.size - Vector2(16, 16)), Color("#112b36"), false, 1.0)
	var cell_size: float = maxf(18.0, minf((board.size.x - 40.0) / float(GRID_COLUMNS), (board.size.y - 72.0) / float(GRID_ROWS)))
	var grid_size := Vector2(cell_size * GRID_COLUMNS, cell_size * GRID_ROWS)
	var origin := board.position + Vector2((board.size.x - grid_size.x) * 0.5, 44.0)
	_draw_board_header(board)
	_draw_routes(origin, cell_size)
	for row in GRID_ROWS:
		for column in GRID_COLUMNS:
			var cell := Vector2i(column, row)
			var rect := Rect2(origin + Vector2(column, row) * cell_size + Vector2(3, 3), Vector2(cell_size - 6, cell_size - 6))
			var fill := Color("#0d222c") if cell != hover_cell else Color("#173745")
			if (build_mode or not dragging_module_id.is_empty()) and cell == preview_cell:
				fill = Color("#173e38") if preview_valid else Color("#40222b")
			draw_rect(rect, fill, true)
			draw_rect(rect, Color("#1b3b48"), false, 1.0)
	_draw_board_markers(origin, cell_size)
	_draw_modules(origin, cell_size)
	_draw_build_preview(origin, cell_size)
	_draw_enemies(origin, cell_size)
	_draw_route_fx(origin, cell_size)
	_draw_path_legend(board)


func _draw_board_header(board: Rect2) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, board.position + Vector2(18, 26), "SECTOR 07 / FOUNDRY RING", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#d7e8ed"))
	draw_string(font, board.position + Vector2(board.size.x - 184, 26), "SIM TICK  %06d" % int(snapshot.get("tick", 1842)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#6f929f"))
	draw_string(font, board.position + Vector2(18, board.size.y - 42), "ROUTE INTEGRITY  /  96%", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#4d8290"))
	draw_string(font, board.position + Vector2(board.size.x - 134, board.size.y - 42), "BANDWIDTH 64%", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#4d8290"))


func _draw_board_markers(origin: Vector2, cell_size: float) -> void:
	var font := ThemeDB.fallback_font
	var spawn := _cell_center(origin, cell_size, Vector2i(0, 3))
	var core := _cell_center(origin, cell_size, Vector2i(7, 3))
	draw_circle(spawn, cell_size * 0.22, Color("#ff6b75", 0.08))
	draw_arc(spawn, cell_size * 0.27, phase, phase + 4.6, 24, Color("#ff6b75", 0.8), 2.0)
	draw_circle(core, cell_size * 0.25, Color("#68e3bf", 0.08))
	draw_arc(core, cell_size * 0.30, -phase, -phase + 4.6, 24, Color("#68e3bf", 0.8), 2.0)
	draw_string(font, spawn + Vector2(-20, cell_size * 0.46), "ENTRY", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("#9a5f6b"))
	draw_string(font, core + Vector2(-18, cell_size * 0.48), "CORE", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("#5a9d8b"))


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
	var signal_color := _effect_color("signal", Color("#42c7ee"))
	var energy_color := _effect_color("energy", Color("#ffca62"))
	var hazard_color := _effect_color("hazard", Color("#ff6b75"))
	_draw_polyline(signal_points, signal_color, 6.0 if route_focus in ["SIGNAL", "CONNECTION", "ACTION"] else 4.0)
	_draw_polyline(energy_points, energy_color, 5.0 if route_focus in ["POWER", "ENERGY"] else 3.0)
	_draw_polyline(hazard_points, hazard_color, 5.0 if route_focus in ["BREACH", "DAMAGE"] else 2.0)
	if highlighted_event == 0 or highlighted_event == 1:
		_draw_polyline(signal_points, Color("#d9fbff"), 6.0)
	for point in signal_points:
		draw_circle(point, 3.0 + sin(phase + point.x * 0.02) * 1.0, Color(signal_color, 0.78))
	var packet_t := fmod(phase * 0.18, 1.0)
	var trail_count := 3
	if effect_quality == 1:
		trail_count = 2
	elif effect_quality == 0:
		trail_count = 1
	for trail in range(trail_count):
		var trail_progress := fmod(packet_t - float(trail) * 0.035 + 1.0, 1.0)
		_draw_packet(signal_points, trail_progress, Color(route_flash_color, 0.35 - float(trail) * 0.09), maxf(1.5, 3.5 - float(trail) * 0.6))
	_draw_packet(signal_points, packet_t, route_flash_color, 5.0 + route_flash * 5.0)
	_draw_packet(energy_points, fmod(packet_t + 0.35, 1.0), energy_color, 3.0 if effect_quality > 0 else 2.0)
	if route_flash > 0.0:
		draw_circle(_cell_center(origin, cell_size, Vector2i(5, 3)), cell_size * (0.36 + route_flash * 0.12), Color(route_flash_color, route_flash * 0.10), false, 2.0)


func _draw_polyline(points: PackedVector2Array, color: Color, width: float) -> void:
	for index in range(points.size() - 1):
		draw_line(points[index], points[index + 1], color.darkened(0.42), width + 5.0)
		draw_line(points[index], points[index + 1], color, width)


func _draw_packet(points: PackedVector2Array, progress: float, color: Color, radius: float) -> void:
	if points.size() < 2:
		return
	var segment_count := points.size() - 1
	var scaled := progress * float(segment_count)
	var segment := clampi(int(floor(scaled)), 0, segment_count - 1)
	var local_t := scaled - float(segment)
	var position := points[segment].lerp(points[segment + 1], local_t)
	draw_circle(position, radius + 5.0, Color(color, 0.08), true)
	draw_circle(position, radius, color, true)


func _draw_modules(origin: Vector2, cell_size: float) -> void:
	var font := ThemeDB.fallback_font
	for module in modules:
		var cell: Vector2i = _module_cell(module)
		var center := _cell_center(origin, cell_size, cell)
		var raw_color = module.get("color", Color("#72d7ff"))
		var color: Color = raw_color if raw_color is Color else Color(str(raw_color))
		var selected: bool = str(module.get("id", "")) == selected_module_id
		var disabled := bool(module.get("disabled", false))
		var radius := cell_size * 0.30
		if disabled:
			draw_circle(center, radius + 9.0, Color("#ff6b75", 0.10), true)
			draw_arc(center, radius + 8.0, phase, phase + TAU * 0.86, 24, Color("#ff6b75", 0.85), 2.0)
		if selected:
			draw_circle(center, radius + 7.0, Color(color, 0.10))
			draw_arc(center, radius + 7.0, phase, phase + 4.3, 24, Color(color, 0.7), 2.0)
			draw_arc(center, radius + 12.0, -phase * 0.6, -phase * 0.6 + 3.7, 18, Color(color, 0.25), 1.0)
		draw_circle(center, radius, Color("#102834"))
		draw_circle(center, radius, color, false, 3.0)
		draw_line(center - Vector2(radius * 0.58, 0), center + Vector2(radius * 0.58, 0), color, 2.0)
		draw_line(center - Vector2(0, radius * 0.58), center + Vector2(0, radius * 0.58), color, 2.0)
		for socket_index in range(4):
			var socket_angle := float(socket_index) * TAU / 4.0 + PI / 4.0
			var socket := center + Vector2(cos(socket_angle), sin(socket_angle)) * (radius + 2.0)
			draw_circle(socket, 3.0, Color("#071017"), true)
			draw_circle(socket, 2.0, color, true)
		draw_string(font, center + Vector2(-radius, radius + 18), str(module.get("name", module.get("label", "模块"))), HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 11, Color("#c5dbe2"))
		var load: float = float(module.get("load", 0.2))
		var bar := Rect2(center + Vector2(-radius, radius + 25), Vector2(radius * 2.0, 4))
		draw_rect(bar, Color("#18313c"), true)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clamp(load, 0.0, 1.0), bar.size.y)), color, true)


func _draw_build_preview(origin: Vector2, cell_size: float) -> void:
	var cell := preview_cell if preview_cell.x >= 0 else hover_cell
	if not build_mode and dragging_module_id.is_empty():
		return
	if cell.x < 0:
		return
	var center := _cell_center(origin, cell_size, cell)
	var color := Color("#68e3bf") if preview_valid else Color("#ff6b75")
	var radius := cell_size * 0.30
	draw_circle(center, radius + 10.0, Color(color, 0.10), true)
	draw_arc(center, radius + 8.0, -phase, -phase + TAU, 28, color, 2.0)
	draw_circle(center, radius, Color(color, 0.10), true)
	draw_circle(center, radius, color, false, 2.0)
	for socket_index in range(4):
		var socket_angle := float(socket_index) * TAU / 4.0 + PI / 4.0 + float(build_rotation) * PI / 2.0
		var socket := center + Vector2(cos(socket_angle), sin(socket_angle)) * (radius + 2.0)
		draw_circle(socket, 3.0, color, true)
	var label := "可部署" if preview_valid else "位置冲突"
	draw_string(ThemeDB.fallback_font, center + Vector2(-34, radius + 25), label, HORIZONTAL_ALIGNMENT_CENTER, 68, 10, color)


func _draw_enemies(origin: Vector2, cell_size: float) -> void:
	var font := ThemeDB.fallback_font
	var enemy_list: Array = []
	var enemy_state: Dictionary = snapshot.get("enemies", {})
	if not enemy_state.is_empty():
		for enemy_id in enemy_state.keys():
			var enemy: Dictionary = enemy_state[enemy_id]
			var progress: float = clampf(float(enemy.get("progress", 0.0)), 0.0, 0.99)
			var label := str(enemy.get("label", "目标"))
			var kind := str(enemy.get("kind", _infer_enemy_kind(label)))
			enemy_list.append({
				"id": str(enemy_id),
				"cell": Vector2i(int(progress * 7.0), 3),
				"progress": progress,
				"hp": float(enemy.get("hp", 1.0)),
				"max_hp": maxf(1.0, float(enemy.get("max_hp", 1.0))),
				"label": label,
				"kind": kind,
			})
	else:
		enemy_list = [
			{"id": "preview_scout", "cell": Vector2i(0, 3), "progress": 0.03, "hp": 25.0, "max_hp": 34.0, "label": "侦察蜂", "kind": "scout"},
			{"id": "preview_bruiser", "cell": Vector2i(1, 3), "progress": 0.17, "hp": 64.0, "max_hp": 90.0, "label": "破城兽", "kind": "bruiser"},
			{"id": "preview_phase", "cell": Vector2i(2, 3), "progress": 0.29, "hp": 55.0, "max_hp": 74.0, "label": "相位影", "kind": "phase"},
			{"id": "preview_jammer", "cell": Vector2i(3, 3), "progress": 0.41, "hp": 48.0, "max_hp": 64.0, "label": "干扰体", "kind": "jammer"},
			{"id": "preview_leech", "cell": Vector2i(4, 3), "progress": 0.54, "hp": 28.0, "max_hp": 42.0, "label": "虹吸虫", "kind": "leech"},
			{"id": "preview_splitter", "cell": Vector2i(5, 3), "progress": 0.66, "hp": 40.0, "max_hp": 52.0, "label": "裂变体", "kind": "splitter"},
			{"id": "preview_boss", "cell": Vector2i(6, 3), "progress": 0.78, "hp": 410.0, "max_hp": 520.0, "label": "熔断主宰", "kind": "boss"},
		]
	enemy_list.sort_custom(_sort_enemy_draw_order)
	for effect in enemy_death_effects:
		var death_progress := clampf(float(effect.get("progress", 0.0)), 0.0, 0.99)
		var death_center := _cell_center(origin, cell_size, Vector2i(int(death_progress * 7.0), 3)) + Vector2(0, -cell_size * 0.25)
		var death_kind := str(effect.get("kind", "scout"))
		var death_size := cell_size * (0.47 if death_kind == "boss" else 0.31) * character_scale
		var max_ttl := maxf(0.01, float(effect.get("max_ttl", 1.0)))
		var intensity := clampf(float(effect.get("ttl", 0.0)) / max_ttl, 0.0, 1.0)
		CHARACTER_ART.draw_death_burst(self, death_center, death_size, death_kind, phase, intensity)
		draw_string(font, death_center + Vector2(-death_size, death_size * 0.98), str(effect.get("label", "目标")) + " · OFFLINE", HORIZONTAL_ALIGNMENT_LEFT, death_size * 2.0, 8, Color(1.0, 0.83, 0.68, intensity))
	for enemy in enemy_list:
		var kind := str(enemy.get("kind", "scout"))
		var center := _cell_center(origin, cell_size, enemy.get("cell", Vector2i.ZERO)) + Vector2(0, -cell_size * 0.25)
		var serial := str(enemy.get("id", "0")).replace("E", "")
		var lane := 0.0 if not serial.is_valid_int() else float((int(serial) % 3) - 1) * cell_size * 0.11
		center += Vector2(0, lane)
		var is_boss := kind == "boss"
		var art_size := cell_size * (0.47 if is_boss else 0.31) * character_scale
		var hit_intensity := float(enemy_hit_flash.get(str(enemy.get("id", "")), 0.0))
		var art_color := CHARACTER_ART.palette(kind)
		CHARACTER_ART.draw_ground_layer(self, center, art_size, kind, phase)
		if is_boss:
			var boss_pulse := 0.22 + 0.10 * (0.5 + 0.5 * sin(phase * 1.4))
			draw_arc(center, art_size * 1.34, phase * 0.55, phase * 0.55 + 4.9, 32, Color(art_color, boss_pulse), 2.0)
			draw_line(center + Vector2(-art_size * 0.78, art_size * 0.94), center + Vector2(-art_size * 0.58, art_size * 0.94), Color("#ffca62", 0.68), 2.0)
			draw_line(center + Vector2(art_size * 0.58, art_size * 0.94), center + Vector2(art_size * 0.78, art_size * 0.94), Color("#ffca62", 0.68), 2.0)
		elif hit_intensity > 0.0:
			draw_arc(center, art_size * 0.92, -phase, -phase + 4.1, 22, Color(art_color, 0.26 * hit_intensity), 1.5)
		var animation_state := _enemy_animation_state(enemy, hit_intensity)
		CHARACTER_ART.draw_enemy(self, center, art_size, kind, animation_state, phase, hit_intensity)
		var hp_ratio := clampf(float(enemy.get("hp", 1.0)) / maxf(1.0, float(enemy.get("max_hp", 1.0))), 0.0, 1.0)
		var width_scale := maxf(0.78, character_scale)
		var bar_width := (58.0 if is_boss else 34.0) * width_scale
		var hp_rect := Rect2(center + Vector2(-bar_width * 0.5, art_size * 0.72), Vector2(bar_width, 4.0 * width_scale))
		draw_rect(hp_rect, Color("#311d27"), true)
		draw_rect(Rect2(hp_rect.position, Vector2(hp_rect.size.x * hp_ratio, hp_rect.size.y)), art_color, true)
		var label_size := maxi(8, int(round((10 if is_boss else 9) * character_scale)))
		draw_string(font, center + Vector2(-bar_width * 0.5, -art_size * 0.78), str(enemy.get("label", "目标")), HORIZONTAL_ALIGNMENT_LEFT, bar_width, label_size, Color("#e6f2f4") if is_boss else Color("#a8c0c8"))
		if is_boss:
			draw_string(font, center + Vector2(-bar_width * 0.5, art_size * 0.96), "BOSS  %02d%%" % int(hp_ratio * 100.0), HORIZONTAL_ALIGNMENT_LEFT, bar_width, maxi(8, label_size - 1), Color("#ffca62"))

func _sort_enemy_draw_order(left: Dictionary, right: Dictionary) -> bool:
	var left_progress := float(left.get("progress", 0.0))
	var right_progress := float(right.get("progress", 0.0))
	if is_equal_approx(left_progress, right_progress):
		return str(left.get("kind", "")) == "boss"
	return left_progress < right_progress


func _enemy_animation_state(enemy: Dictionary, hit_intensity: float) -> String:
	if hit_intensity > 0.0:
		return "hit"
	if paused:
		return "idle"
	var kind := str(enemy.get("kind", "scout"))
	var serial_text := str(enemy.get("id", "0")).replace("E", "")
	var serial := float(int(serial_text)) if serial_text.is_valid_int() else 0.0
	var progress := float(enemy.get("progress", 0.0))
	var cycle := phase * (0.95 if kind == "boss" else 1.15) + serial * 0.77 + progress * 4.0
	var attack_threshold := 0.80 if kind == "boss" else 0.92
	if sin(cycle) > attack_threshold:
		return "attack"
	return "move" if absf(cos(cycle * 1.7)) > 0.18 else "idle"

func _infer_enemy_kind(label: String) -> String:
	var labels := {
		"侦察蜂": "scout",
		"破城兽": "bruiser",
		"裂变体": "splitter",
		"干扰体": "jammer",
		"虹吸虫": "leech",
		"相位影": "phase",
		"熔断主宰": "boss",
	}
	return str(labels.get(label, "scout"))

func _sync_enemy_art(tick: int) -> void:
	if art_tick == tick:
		return
	art_tick = tick
	var current: Dictionary = snapshot.get("enemies", {})
	for enemy_id in current.keys():
		var enemy: Dictionary = current[enemy_id]
		var hp := float(enemy.get("hp", 1.0))
		if enemy_hp_cache.has(enemy_id) and hp < float(enemy_hp_cache[enemy_id]):
			enemy_hit_flash[enemy_id] = 1.0
		enemy_hp_cache[enemy_id] = hp
		enemy_last_state[enemy_id] = enemy.duplicate(true)
	var missing_ids: Array = []
	for enemy_id in enemy_last_state.keys():
		if not current.has(enemy_id):
			missing_ids.append(enemy_id)
	for enemy_id in missing_ids:
		var previous: Dictionary = enemy_last_state[enemy_id]
		var previous_label := str(previous.get("label", "目标"))
		enemy_death_effects.append({
			"progress": clampf(float(previous.get("progress", 0.0)), 0.0, 0.99),
			"kind": str(previous.get("kind", _infer_enemy_kind(previous_label))),
			"label": previous_label,
			"ttl": 1.0,
			"max_ttl": 1.0,
		})
		enemy_last_state.erase(enemy_id)
		enemy_hp_cache.erase(enemy_id)
		enemy_hit_flash.erase(enemy_id)


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
	if _is_compact(size):
		_draw_compact_panel(size)
		return
	var x := size.x - RIGHT_PANEL_WIDTH - MARGIN
	var top := TOP_BAR_HEIGHT + 20.0
	var panel := Rect2(x, top, RIGHT_PANEL_WIDTH, maxf(220.0, size.y - TOP_BAR_HEIGHT - _bottom_bar_height(size) - 40.0))
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
	var sell_rect := Rect2(card.position + Vector2(card.size.x - 74, 12), Vector2(58, 24))
	draw_rect(sell_rect, Color("#ff6b75", 0.12), true)
	draw_rect(sell_rect, Color("#ff6b75", 0.55), false, 1.0)
	draw_string(font, sell_rect.position + Vector2(0, 16), "出售", HORIZONTAL_ALIGNMENT_CENTER, sell_rect.size.x, 10, Color("#ff9aa1"))
	draw_string(font, panel.position + Vector2(18, 182), "端口", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#8eb0bb"))
	_draw_port(panel.position + Vector2(18, 202), "IN / SIGNAL", Color("#42c7ee"), "路由器 · 12 events/s")
	_draw_port(panel.position + Vector2(18, 232), "OUT / TARGET", Color("#ffca62"), "输出节点 · 1.0×")
	draw_string(font, panel.position + Vector2(18, 284), "规则槽  2 / 3", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#8eb0bb"))
	_draw_rule(panel.position + Vector2(18, 300), "目标类型 == 裂隙虫", "脉冲伤害 +24", Color("#b690ff"))
	_draw_rule(panel.position + Vector2(18, 343), "若线路拥塞 > 60%", "切换为低功率", Color("#ffca62"))
	draw_string(font, panel.position + Vector2(18, 405), "实时遥测", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#8eb0bb"))
	_draw_meter(panel.position + Vector2(18, 421), "核心完整度", float(snapshot.get("integrity", 86)) / 100.0, Color("#68e3bf"), "%02d%%" % int(snapshot.get("integrity", 86)))
	_draw_meter(panel.position + Vector2(18, 448), "电荷储备", float(snapshot.get("charge", 128)) / 200.0, Color("#ffca62"), "%03d" % int(snapshot.get("charge", 128)))
	_draw_meter(panel.position + Vector2(18, 475), "线路带宽", 0.64, Color("#72d7ff"), "64%")
	_draw_meter(panel.position + Vector2(18, 502), "热交换", 0.31, Color("#ff6b75"), "31°")
	_draw_upgrade_branches(panel)
	_draw_event_log(panel)


func _draw_compact_panel(size: Vector2) -> void:
	var rect := Rect2(MARGIN, size.y - _bottom_bar_height(size) - 86.0, size.x - MARGIN * 2.0, 62.0)
	draw_rect(rect, Color("#0b1a23", 0.94), true)
	draw_rect(rect, Color("#1d3b4b"), false, 1.0)
	var selected_name := "模块"
	for module in modules:
		if str(module.get("id", "")) == selected_module_id:
			selected_name = str(module.get("name", selected_name))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(12, 21), "选中  " + selected_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#f2d18a"))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(12, 42), "长按详情 · 拖拽移动 · R 旋转 · 点击出售", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#8daab4"))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(rect.size.x - 88, 21), "诊断 %02d" % int(snapshot.get("diagnostics", {}).get("warning_count", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#ffca62"))


func _draw_upgrade_branches(panel: Rect2) -> void:
	var font := ThemeDB.fallback_font
	var y := panel.position.y + 530.0
	draw_string(font, Vector2(panel.position.x + 18, y), "编译台升级分支", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#8eb0bb"))
	var branches := [
		{"id": "overclock", "label": "超频", "cost": "40 C", "color": Color("#ffca62")},
		{"id": "fortify", "label": "固件", "cost": "36 C", "color": Color("#68e3bf")},
		{"id": "logic", "label": "逻辑", "cost": "28 C", "color": Color("#b690ff")},
	]
	for index in range(branches.size()):
		var branch: Dictionary = branches[index]
		var rect := Rect2(panel.position + Vector2(14 + index * 98, y + 10), Vector2(90, 34))
		var active := str(branch.id) == selected_upgrade_branch
		draw_rect(rect, Color(branch.color, 0.18 if active else 0.07), true)
		draw_rect(rect, branch.color if active else Color("#264653"), false, 1.0)
		draw_string(font, rect.position + Vector2(8, 15), str(branch.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, branch.color)
		draw_string(font, rect.position + Vector2(8, 28), str(branch.cost), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#a8c0c8"))


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


func _draw_meter(position: Vector2, label: String, value: float, color: Color, value_text: String) -> void:
	var font := ThemeDB.fallback_font
	var clamped := clampf(value, 0.0, 1.0)
	draw_string(font, position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#a9c1c8"))
	draw_string(font, position + Vector2(RIGHT_PANEL_WIDTH - 72, 0), value_text, HORIZONTAL_ALIGNMENT_RIGHT, 54, 9, color)
	var track := Rect2(position + Vector2(0, 7), Vector2(RIGHT_PANEL_WIDTH - 36, 4))
	draw_rect(track, Color("#17313b"), true)
	draw_rect(Rect2(track.position, Vector2(track.size.x * clamped, track.size.y)), color, true)


func _draw_event_log(panel: Rect2) -> void:
	var font := ThemeDB.fallback_font
	var y := panel.position.y + panel.size.y - 112.0
	draw_string(font, Vector2(panel.position.x + 18, y), "事件追踪", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#8eb0bb"))
	draw_string(font, Vector2(panel.position.x + panel.size.x - 100, y), "%02d EVENTS" % events.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#60818c"))
	for index in range(min(events.size(), 3)):
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
	var bottom_height := _bottom_bar_height(size)
	var y := size.y - bottom_height
	draw_rect(Rect2(0, y, size.x, bottom_height), Color("#0b1822"), true)
	draw_line(Vector2(0, y), Vector2(size.x, y), Color("#1d3b4b"), 1.0)
	_draw_button(Rect2(MARGIN, y + 20, 118, 38), "暂停" if not paused else "继续", "pause", Color("#ffca62"))
	_draw_button(Rect2(MARGIN + 128, y + 20, 80, 38), "%d×" % speed, "speed", Color("#72d7ff"))
	_draw_button(Rect2(MARGIN + 218, y + 20, 118, 38), "事件回放", "replay", Color("#b690ff"))
	if bool(snapshot.get("finished", false)):
		_draw_button(Rect2(MARGIN + 346, y + 20, 44, 38), "重试", "retry", Color("#ff6b75"))
	_draw_shop_slots(y)
	_draw_bench_strip(y)
	var status_color := Color("#68e3bf") if feedback_tone == "ok" else Color("#ffca62") if feedback_tone == "warn" else Color("#6b8d98")
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 440, y + 25), feedback_message, HORIZONTAL_ALIGNMENT_LEFT, 420, 10, status_color)
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 290, y + 43), "确定性种子  CB-07-1842", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#6b8d98"))


func _draw_result_banner(size: Vector2) -> void:
	if not bool(snapshot.get("finished", false)):
		return
	var victory_state := bool(snapshot.get("victory", false))
	var color := Color("#68e3bf") if victory_state else Color("#ff6b75")
	var width := minf(520.0, size.x * 0.52)
	var rect := Rect2(Vector2((size.x - width) * 0.5, TOP_BAR_HEIGHT + 42.0), Vector2(width, 56.0))
	draw_rect(rect, Color("#0b1822", 0.94), true)
	draw_rect(rect, color, false, 1.0)
	var title := "堡垒完成 · 10 波已守住" if victory_state else "核心失守 · 需要重新编译"
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(18, 24), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, color)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(18, 43), "点击底部「重试」保留确定性种子，重新测试你的线路", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#b4cbd2"))


func _draw_shop_slots(y: float) -> void:
	var font := ThemeDB.fallback_font
	if _is_compact(get_rect().size):
		var size := get_rect().size
		var start_x := 16.0
		var refresh_width := 60.0
		var gap := 4.0
		var item_width := maxf(70.0, (size.x - start_x * 2.0 - refresh_width - gap * 3.0) / 3.0)
		draw_string(font, Vector2(start_x, y + 54), "备战商店 / R%02d" % shop_revision, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#60818c"))
		var shop := _display_shop_items()
		for index in range(shop.size()):
			var item: Dictionary = shop[index]
			var rect := Rect2(start_x + index * (item_width + gap), y + 66, item_width, 48)
			draw_rect(rect, Color("#0e222d"), true)
			draw_rect(rect, Color(item.color, 0.55), false, 1.0)
			draw_string(font, rect.position + Vector2(7, 18), item.name, HORIZONTAL_ALIGNMENT_LEFT, item_width - 12, 10, Color("#d8e7ea"))
			draw_string(font, rect.position + Vector2(7, 34), item.cost, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, item.color)
		var refresh_rect := Rect2(size.x - start_x - refresh_width, y + 66, refresh_width, 48)
		draw_rect(refresh_rect, Color("#0e222d"), true)
		draw_rect(refresh_rect, Color("#72d7ff", 0.65), false, 1.0)
		draw_string(font, refresh_rect.position + Vector2(0, 21), "刷新", HORIZONTAL_ALIGNMENT_CENTER, refresh_width, 10, Color("#72d7ff"))
		return
	draw_string(font, Vector2(390, y + 19), "备战商店  /  R%02d" % shop_revision, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#60818c"))
	var shop := _display_shop_items()
	for index in range(shop.size()):
		var item: Dictionary = shop[index]
		var rect := Rect2(390 + index * 108, y + 25, 98, 45)
		draw_rect(rect, Color("#0e222d"), true)
		draw_rect(rect, Color(item.color, 0.55), false, 1.0)
		draw_circle(rect.position + Vector2(15, 16), 5.0, item.color)
		draw_string(font, rect.position + Vector2(27, 18), item.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#d8e7ea"))
		draw_string(font, rect.position + Vector2(27, 33), item.type, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("#72919b"))
		draw_string(font, rect.position + Vector2(64, 33), item.cost, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, item.color)
	var refresh := Rect2(714, y + 25, 72, 45)
	draw_rect(refresh, Color("#0e222d"), true)
	draw_rect(refresh, Color("#72d7ff", 0.65), false, 1.0)
	draw_string(font, refresh.position + Vector2(0, 19), "刷新", HORIZONTAL_ALIGNMENT_CENTER, refresh.size.x, 10, Color("#72d7ff"))
	draw_string(font, refresh.position + Vector2(0, 34), "8 C", HORIZONTAL_ALIGNMENT_CENTER, refresh.size.x, 8, Color("#7697a4"))


func _display_shop_items() -> Array:
	if shop_inventory.is_empty():
		return [
			{"name": "滤波器", "type": "逻辑", "cost": "18 C", "kind": "slow_field", "color": Color("#b690ff")},
			{"name": "缓存", "type": "中继", "cost": "24 C", "kind": "router", "color": Color("#72d7ff")},
			{"name": "维修臂", "type": "执行", "cost": "32 C", "kind": "repair_arm", "color": Color("#68e3bf")},
		]
	var result: Array = []
	var palette := [Color("#b690ff"), Color("#72d7ff"), Color("#68e3bf"), Color("#ffca62")]
	for index in range(mini(3, shop_inventory.size())):
		var item: Dictionary = shop_inventory[index]
		result.append({
			"name": str(item.get("label", item.get("kind", "模块"))),
			"type": str(item.get("role", "模块")),
			"cost": "%d C" % int(item.get("cost", 0)),
			"kind": str(item.get("kind", "pulse_cannon")),
			"color": palette[index % palette.size()],
		})
	return result


func _draw_bench_strip(y: float) -> void:
	var font := ThemeDB.fallback_font
	if _is_compact(get_rect().size):
		draw_string(font, Vector2(16, y + 135), "备战栏  %02d / 08" % bench_items.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#60818c"))
		for index in range(mini(3, bench_items.size())):
			var item: Dictionary = bench_items[index]
			var rect := Rect2(120 + index * 88, y + 122, 82, 38)
			draw_rect(rect, Color("#0e222d"), true)
			draw_rect(rect, Color("#68e3bf"), false, 1.0)
			draw_string(font, rect.position + Vector2(5, 16), str(item.get("label", item.get("kind", "模块"))), HORIZONTAL_ALIGNMENT_LEFT, 72, 9, Color("#d8e7ea"))
			draw_string(font, rect.position + Vector2(5, 30), "点击部署", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("#68e3bf"))
		return
	var x := 800.0
	draw_string(font, Vector2(x, y + 19), "备战栏  %02d / 08" % bench_items.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#60818c"))
	for index in range(mini(3, bench_items.size())):
		var item: Dictionary = bench_items[index]
		var rect := Rect2(x + index * 72, y + 25, 64, 45)
		var active := build_mode and build_kind == str(item.get("kind", ""))
		draw_rect(rect, Color("#162d35") if active else Color("#0e222d"), true)
		draw_rect(rect, Color("#68e3bf") if active else Color("#264653"), false, 1.0)
		draw_string(font, rect.position + Vector2(5, 19), str(item.get("label", item.get("kind", "模块"))), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 10, 9, Color("#d8e7ea"))
		draw_string(font, rect.position + Vector2(5, 34), "点击部署", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("#68e3bf"))


func _draw_button(rect: Rect2, label: String, command: String, color: Color) -> void:
	var active := (command == "pause" and paused) or (command == "speed" and speed > 1)
	draw_rect(rect, Color(color, 0.18 if active else 0.08), true)
	draw_rect(rect, color, false, 1.0)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(0, 24), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 12, color)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hover_cell = _cell_at(event.position)
		if build_mode or not dragging_module_id.is_empty():
			preview_cell = hover_cell
			preview_valid = _cell_is_valid(preview_cell, dragging_module_id)
		queue_redraw()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pointer_press(event.position)
			else:
				_pointer_release(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_cancel_interaction("已取消部署")
	elif event is InputEventScreenTouch:
		if event.pressed:
			touch_pointer_id = event.index
			_pointer_press(event.position)
		else:
			if touch_pointer_id == event.index:
				_pointer_release(event.position)
				touch_pointer_id = -1
	elif event is InputEventScreenDrag and event.index == touch_pointer_id:
		hover_cell = _cell_at(event.position)
		preview_cell = hover_cell
		preview_valid = _cell_is_valid(preview_cell, dragging_module_id)
		queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)


func _pointer_press(position: Vector2) -> void:
	var size := get_rect().size
	var bottom_y := size.y - _bottom_bar_height(size)
	if position.y >= bottom_y:
		if _is_compact(size):
			if Rect2(MARGIN, bottom_y + 20, 118, 38).has_point(position):
				paused = not paused
				command_requested.emit("pause" if paused else "resume")
			elif Rect2(MARGIN + 128, bottom_y + 20, 80, 38).has_point(position):
				speed = 1 if speed >= 4 else speed * 2
				command_requested.emit("speed:%d" % speed)
			elif Rect2(MARGIN + 218, bottom_y + 20, 118, 38).has_point(position):
				command_requested.emit("replay")
			elif Rect2(size.x - 76, bottom_y + 66, 60, 48).has_point(position):
				shop_revision += 1
				command_requested.emit("shop:refresh:%d" % shop_revision)
			else:
				var gap := 4.0
				var item_width := maxf(70.0, (size.x - 32.0 - 60.0 - gap * 3.0) / 3.0)
				for index in range(3):
					var shop_rect := Rect2(16.0 + index * (item_width + gap), bottom_y + 66, item_width, 48)
					if shop_rect.has_point(position):
						var display_items := _display_shop_items()
						if index < display_items.size():
							build_kind = str(display_items[index].get("kind", "pulse_cannon"))
							build_mode = true
							command_requested.emit("shop:buy:%d" % index)
							command_requested.emit("shop:select:%d:%s" % [index, build_kind])
						break
				for index in range(mini(3, bench_items.size())):
					var bench_rect := Rect2(120 + index * 88, bottom_y + 122, 82, 38)
					if bench_rect.has_point(position):
						build_kind = str(bench_items[index].get("kind", "pulse_cannon"))
						build_mode = true
						command_requested.emit("bench:select:%d" % index)
						break
			queue_redraw()
			return
		if Rect2(MARGIN, bottom_y + 20, 118, 38).has_point(position):
			paused = not paused
			command_requested.emit("pause" if paused else "resume")
		elif Rect2(MARGIN + 128, bottom_y + 20, 80, 38).has_point(position):
			speed = 1 if speed >= 4 else speed * 2
			command_requested.emit("speed:%d" % speed)
		elif Rect2(MARGIN + 218, bottom_y + 20, 118, 38).has_point(position):
			command_requested.emit("replay")
		elif Rect2(MARGIN + 346, bottom_y + 20, 44, 38).has_point(position) and bool(snapshot.get("finished", false)):
			command_requested.emit("retry")
			feedback_message = "正在重启模拟 · 固定种子保持不变"
			feedback_tone = "ok"
		elif Rect2(714, bottom_y + 25, 72, 45).has_point(position):
			shop_revision += 1
			feedback_message = "商店刷新 · 轮次 R%02d" % shop_revision
			feedback_tone = "ok"
			command_requested.emit("shop:refresh:%d" % shop_revision)
		elif position.x >= 800 and position.x < 1016 and not bench_items.is_empty():
			var bench_slot := clampi(int((position.x - 800.0) / 72.0), 0, bench_items.size() - 1)
			var bench_item: Dictionary = bench_items[bench_slot]
			build_kind = str(bench_item.get("kind", "pulse_cannon"))
			build_mode = true
			preview_cell = hover_cell
			preview_valid = _cell_is_valid(preview_cell)
			feedback_message = "备战栏 · 部署 %s" % str(bench_item.get("label", build_kind))
			feedback_tone = "info"
			command_requested.emit("bench:select:%d" % bench_slot)
		elif position.x >= 390 and position.x < 714:
			var slot := clampi(int((position.x - 390.0) / 108.0), 0, 2)
			var display_items := _display_shop_items()
			build_kind = str(display_items[slot].get("kind", "pulse_cannon")) if slot < display_items.size() else "pulse_cannon"
			build_mode = true
			preview_cell = hover_cell
			preview_valid = _cell_is_valid(preview_cell)
			feedback_message = "部署 %s · 点击网格确认 · R 旋转" % str(display_items[slot].get("name", build_kind)) if slot < display_items.size() else "部署模块 · 点击网格确认 · R 旋转"
			feedback_tone = "info"
			command_requested.emit("shop:buy:%d" % slot)
			command_requested.emit("shop:select:%d:%s" % [slot, build_kind])
		queue_redraw()
		return
	if _panel_sell_rect(size).has_point(position):
		if not selected_module_id.is_empty():
			command_requested.emit("sell:%s" % selected_module_id)
			feedback_message = "已提交出售 · %s" % selected_module_id
			feedback_tone = "warn"
		queue_redraw()
		return
	var branch := _upgrade_branch_at(position, size)
	if not branch.is_empty():
		selected_upgrade_branch = branch
		feedback_message = "编译台 · %s 分支已选中" % branch
		feedback_tone = "ok"
		command_requested.emit("upgrade:%s" % branch)
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
		hover_cell = cell
		preview_cell = cell
		if build_mode:
			preview_valid = _cell_is_valid(cell)
			if preview_valid:
				command_requested.emit("build:%s:%d:%d:%d" % [build_kind, cell.x, cell.y, build_rotation])
				feedback_message = "已部署 %s · 等待连接" % build_kind
				feedback_tone = "ok"
				build_mode = false
			else:
				feedback_message = "位置冲突 · 请选择空闲网格"
				feedback_tone = "warn"
			queue_redraw()
			return
		selected_cell = cell
		var module_id := _module_at_cell(cell)
		if not module_id.is_empty():
			selected_module_id = module_id
			module_selected.emit(selected_module_id)
			dragging_module_id = module_id
			drag_origin_cell = cell
			preview_valid = true
		cell_selected.emit(cell)
		queue_redraw()


func _pointer_release(position: Vector2) -> void:
	if dragging_module_id.is_empty():
		return
	var target := _cell_at(position)
	if target.x >= 0 and target != drag_origin_cell and _cell_is_valid(target, dragging_module_id):
		command_requested.emit("move:%s:%d:%d" % [dragging_module_id, target.x, target.y])
		feedback_message = "移动 %s → [%d,%d]" % [dragging_module_id, target.x, target.y]
		feedback_tone = "ok"
	elif target != drag_origin_cell:
		feedback_message = "移动被阻止 · 目标网格不可用"
		feedback_tone = "warn"
	dragging_module_id = ""
	drag_origin_cell = Vector2i(-1, -1)
	preview_cell = target
	preview_valid = _cell_is_valid(target)
	queue_redraw()


func _cancel_interaction(message: String) -> void:
	build_mode = false
	dragging_module_id = ""
	drag_origin_cell = Vector2i(-1, -1)
	preview_cell = Vector2i(-1, -1)
	feedback_message = message
	feedback_tone = "info"
	queue_redraw()


func _handle_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_ESCAPE:
			_cancel_interaction("已取消部署")
		KEY_R:
			build_rotation = (build_rotation + 1) % 4
			if not selected_module_id.is_empty():
				command_requested.emit("rotate:%s:%d" % [selected_module_id, build_rotation])
			feedback_message = "端口旋转 · %d°" % (build_rotation * 90)
			feedback_tone = "ok"
			queue_redraw()
		KEY_B:
			build_mode = not build_mode
			feedback_message = "建造模式已开启" if build_mode else "建造模式已关闭"
			feedback_tone = "info"
			queue_redraw()
		KEY_DELETE, KEY_BACKSPACE:
			if not selected_module_id.is_empty():
				command_requested.emit("sell:%s" % selected_module_id)
				feedback_message = "已提交出售 · %s" % selected_module_id
				feedback_tone = "warn"
				queue_redraw()


func _panel_sell_rect(size: Vector2) -> Rect2:
	if _is_compact(size):
		return Rect2()
	var panel_x := size.x - RIGHT_PANEL_WIDTH - MARGIN
	var panel_top := TOP_BAR_HEIGHT + 20.0
	return Rect2(panel_x + 16 + RIGHT_PANEL_WIDTH - 32 - 74, panel_top + 68 + 12, 58, 24)


func _upgrade_branch_at(position: Vector2, size: Vector2) -> String:
	if _is_compact(size):
		return ""
	var panel_x := size.x - RIGHT_PANEL_WIDTH - MARGIN
	var panel_top := TOP_BAR_HEIGHT + 20.0
	var y := panel_top + 530.0 + 10.0
	var ids := ["overclock", "fortify", "logic"]
	for index in range(ids.size()):
		var rect := Rect2(panel_x + 14 + index * 98, y, 90, 34)
		if rect.has_point(position):
			return ids[index]
	return ""


func _module_at_cell(cell: Vector2i) -> String:
	for module in modules:
		if _module_cell(module) == cell:
			return str(module.get("id", ""))
	return ""


func _module_cell(module: Dictionary) -> Vector2i:
	var value = module.get("cell", null)
	if value is Vector2i:
		return value
	var grid = module.get("grid", {})
	if grid is Dictionary:
		return Vector2i(int(grid.get("x", -1)), int(grid.get("y", -1)))
	return Vector2i(-1, -1)


func _cell_is_valid(cell: Vector2i, moving_id: String = "") -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= GRID_COLUMNS or cell.y >= GRID_ROWS:
		return false
	if (cell == Vector2i(0, 3) or cell == Vector2i(7, 3)) and moving_id.is_empty():
		return false
	for module in modules:
		var id := str(module.get("id", ""))
		if id != moving_id and _module_cell(module) == cell:
			return false
	return true


func _cell_at(position: Vector2) -> Vector2i:
	var size := get_rect().size
	var panel_reserve := 0.0 if _is_compact(size) else RIGHT_PANEL_WIDTH + MARGIN * 3.0
	var area_width := maxf(180.0, size.x - panel_reserve)
	var board := Rect2(MARGIN, TOP_BAR_HEIGHT + 20.0, area_width, size.y - TOP_BAR_HEIGHT - _bottom_bar_height(size) - 40.0)
	var cell_size: float = maxf(18.0, minf((board.size.x - 40.0) / float(GRID_COLUMNS), (board.size.y - 72.0) / float(GRID_ROWS)))
	var grid_size := Vector2(cell_size * GRID_COLUMNS, cell_size * GRID_ROWS)
	var origin := board.position + Vector2((board.size.x - grid_size.x) * 0.5, 44.0)
	var local: Vector2 = (position - origin) / cell_size
	var cell := Vector2i(floor(local.x), floor(local.y))
	if cell.x < 0 or cell.y < 0 or cell.x >= GRID_COLUMNS or cell.y >= GRID_ROWS:
		return Vector2i(-1, -1)
	return cell


func _event_at(position: Vector2, size: Vector2) -> int:
	if _is_compact(size):
		return -1
	var panel_x := size.x - RIGHT_PANEL_WIDTH - MARGIN
	var panel_top := TOP_BAR_HEIGHT + 20.0
	var panel := Rect2(panel_x, panel_top, RIGHT_PANEL_WIDTH, maxf(220.0, size.y - TOP_BAR_HEIGHT - _bottom_bar_height(size) - 40.0))
	var y := panel.position.y + panel.size.y - 112.0
	for index in range(min(events.size(), 3)):
		var row := Rect2(panel.position.x + 14, y + 12 + index * 34, panel.size.x - 28, 28)
		if row.has_point(position):
			return index
	return -1



func _consume_new_events() -> void:
	for event_value in events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value
		var key := "%s|%s|%s|%s" % [
			str(event.get("sequence", "")),
			str(event.get("time", "")),
			str(event.get("type", event.get("kind", ""))),
			str(event.get("text", event.get("message", ""))),
		]
		if seen_event_keys.has(key):
			continue
		seen_event_keys[key] = true
		_consume_event(event)
	if seen_event_keys.size() > 512:
		seen_event_keys.clear()

func _consume_event(event: Dictionary) -> void:
	var kind := str(event.get("kind", event.get("type", ""))).to_lower()
	var message := str(event.get("text", event.get("message", "")))
	var payload_value = event.get("payload", {})
	var payload: Dictionary = payload_value if payload_value is Dictionary else {}
	match kind:
		"action":
			if message.find("命中") >= 0:
				route_flash = 1.0
				route_flash_color = _effect_color("hit", Color("#ffca62"))
				_spawn_fx("attack", event, _effect_color("hit", Color("#ffca62")), 0.78)
				_spawn_fx("hit", event, _effect_color("hit", Color("#fff2c4")), 0.52)
				_trigger_screen_feedback(0.30, 0.22)
		"enemy_destroyed":
			_spawn_fx("hit", event, _effect_color("success", Color("#68e3bf")), 0.60)
			_trigger_screen_feedback(0.38, 0.25)
		"breach":
			route_flash = 1.0
			route_flash_color = _effect_color("breach", Color("#ff6b75"))
			_spawn_fx("breach", event, _effect_color("breach", Color("#ff6b75")), 0.86)
			_trigger_screen_feedback(0.95, 0.70)
		"overheat":
			_spawn_fx("overheat", event, _effect_color("overheat", Color("#ff8a5b")), 0.95)
			_trigger_screen_feedback(0.55, 0.42)
		"disconnect":
			_spawn_fx("disconnect", event, _effect_color("breach", Color("#ff6b75")), 0.88)
			_trigger_screen_feedback(0.65, 0.46)
		"reconnect":
			_spawn_fx("reconnect", event, _effect_color("success", Color("#68e3bf")), 0.70)
			_trigger_screen_feedback(0.22, 0.20)
		"wave":
			var wave := int(payload.get("wave", snapshot.get("wave", 1)))
			_start_wave_banner("WAVE %02d  INCOMING" % wave, _effect_color("banner", Color("#b690ff")))
			_trigger_screen_feedback(0.34 + minf(float(wave), 10.0) * 0.025, 0.42)
		"victory":
			_start_wave_banner("SYSTEM VICTORY", _effect_color("success", Color("#68e3bf")))
			_start_result_transition("victory")
			_trigger_screen_feedback(0.75, 0.90)
		"defeat":
			_start_wave_banner("CORE BREACHED", _effect_color("breach", Color("#ff6b75")))
			_start_result_transition("defeat")
			_trigger_screen_feedback(0.95, 1.0)
		_:
			if message.find("过热") >= 0:
				_spawn_fx("overheat", event, _effect_color("overheat", Color("#ff8a5b")), 0.95)
				_trigger_screen_feedback(0.45, 0.35)

func _spawn_fx(kind: String, event: Dictionary, color: Color, duration: float) -> void:
	var payload_value = event.get("payload", {})
	var payload: Dictionary = payload_value if payload_value is Dictionary else {}
	fx_items.append({
		"kind": kind,
		"age": 0.0,
		"duration": duration,
		"color": color,
		"source": str(event.get("source", "")),
		"target": str(event.get("target", "")),
		"progress": clampf(float(payload.get("progress", 0.62)), 0.0, 1.0),
	})

func _update_fx(delta: float) -> void:
	for index in range(fx_items.size() - 1, -1, -1):
		var fx: Dictionary = fx_items[index]
		fx.age = float(fx.get("age", 0.0)) + delta
		if float(fx.age) > float(fx.get("duration", 0.5)):
			fx_items.remove_at(index)
		else:
			fx_items[index] = fx
	wave_banner_time = maxf(0.0, wave_banner_time - delta)
	screen_feedback_time = maxf(0.0, screen_feedback_time - delta)
	screen_feedback_strength = maxf(0.0, screen_feedback_strength - delta * 1.8)
	wave_rhythm_phase = fmod(wave_rhythm_phase + delta * (1.4 if wave_banner_time > 0.0 else 0.7), TAU)
	result_transition_time += delta

func _trigger_screen_feedback(strength: float, duration: float = 0.3) -> void:
	screen_feedback_strength = maxf(screen_feedback_strength, clampf(strength, 0.0, 1.0))
	screen_feedback_time = maxf(screen_feedback_time, maxf(0.05, duration))

func _start_wave_banner(text: String, color: Color) -> void:
	wave_banner_text = text
	wave_banner_color = color
	wave_banner_time = 2.2

func _start_result_transition(result: String) -> void:
	result_transition_time = 0.0
	if result == "victory":
		wave_banner_text = "SYSTEM VICTORY"
		wave_banner_color = Color("#68e3bf")
	else:
		wave_banner_text = "CORE BREACHED"
		wave_banner_color = Color("#ff6b75")
	wave_banner_time = 3.0


func _signal_route(origin: Vector2, cell_size: float) -> PackedVector2Array:
	return PackedVector2Array([
		_cell_center(origin, cell_size, Vector2i(0, 3)),
		_cell_center(origin, cell_size, Vector2i(3, 2)),
		_cell_center(origin, cell_size, Vector2i(5, 3)),
		_cell_center(origin, cell_size, Vector2i(7, 3)),
	])

func _route_position(points: PackedVector2Array, progress: float) -> Vector2:
	if points.size() < 2:
		return Vector2.ZERO
	var scaled := clampf(progress, 0.0, 0.999) * float(points.size() - 1)
	var segment := clampi(int(floor(scaled)), 0, points.size() - 2)
	return points[segment].lerp(points[segment + 1], scaled - float(segment))

func _cell_for_token(token: String) -> Vector2i:
	var normalized := token.to_lower()
	for module in modules:
		if str(module.get("id", "")).to_lower() == normalized or str(module.get("kind", "")).to_lower() == normalized:
			return _module_cell(module)
	if normalized.find("scanner") >= 0:
		return Vector2i(1, 1)
	if normalized.find("router") >= 0:
		return Vector2i(3, 2)
	if normalized.find("cool") >= 0 or normalized.find("heat") >= 0:
		return Vector2i(6, 1)
	if normalized.find("battery") >= 0 or normalized.find("capac") >= 0:
		return Vector2i(2, 4)
	return Vector2i(5, 3)

func _draw_route_fx(origin: Vector2, cell_size: float) -> void:
	var points := _signal_route(origin, cell_size)
	for fx_value in fx_items:
		var fx: Dictionary = fx_value
		var kind := str(fx.get("kind", ""))
		var color: Color = fx.get("color", Color("#72d7ff"))
		var age := float(fx.get("age", 0.0))
		var duration := maxf(0.01, float(fx.get("duration", 0.5)))
		var progress := clampf(float(fx.get("progress", 0.62)), 0.0, 1.0)
		var fade := 1.0 - clampf(age / duration, 0.0, 1.0)
		var center := _route_position(points, progress)
		if kind in ["attack", "hit"]:
			if kind == "attack":
				var source := _cell_center(origin, cell_size, _cell_for_token(str(fx.get("source", "pulse_cannon"))))
				var head := source.lerp(center, clampf(age / duration, 0.0, 1.0))
				var tail := source.lerp(center, maxf(0.0, age / duration - 0.24))
				draw_line(tail, head, Color(color, fade * 0.34), 9.0)
				draw_line(tail, head, Color("#fff5d6", fade * 0.92), 2.0)
				draw_circle(head, 9.0 + 3.0 * fade, Color(color, fade * 0.16), true)
				draw_circle(head, 4.0 + 2.0 * fade, Color("#fff5d6", fade), true)
			else:
				var radius := 12.0 + (1.0 - fade) * 34.0
				draw_circle(center, radius, Color(color, fade * 0.10), true)
				draw_arc(center, radius, -phase, -phase + TAU * 0.88, 28, Color(color, fade), 3.0)
				var spark_count := 6
				if effect_quality == 1:
					spark_count = 4
				elif effect_quality == 0:
					spark_count = 0
				for spark in range(spark_count):
					var angle := phase + float(spark) * TAU / float(maxi(1, spark_count))
					var inner := center + Vector2(cos(angle), sin(angle)) * radius * 0.42
					var outer := center + Vector2(cos(angle), sin(angle)) * (radius + 8.0) * 0.68
					draw_line(inner, outer, Color(color, fade), 2.0)
		elif kind in ["overheat", "reconnect"]:
			var module_center := _cell_center(origin, cell_size, _cell_for_token(str(fx.get("source", "pulse_cannon"))))
			var radius := 18.0 + sin(phase * 2.0) * 3.0
			draw_circle(module_center, radius + 8.0, Color(color, fade * 0.10), true)
			draw_arc(module_center, radius, phase, phase + TAU * 0.86, 28, Color(color, fade), 3.0)
			draw_circle(module_center, 5.0 + fade * 4.0, Color(color, fade), true)
		elif kind == "disconnect":
			var module_center := _cell_center(origin, cell_size, _cell_for_token(str(fx.get("source", "pulse_cannon"))))
			var size := 18.0 + (1.0 - fade) * 8.0
			draw_line(module_center - Vector2(size, size), module_center + Vector2(size, size), Color(color, fade), 3.0)
			draw_line(module_center + Vector2(size, -size), module_center - Vector2(size, -size), Color(color, fade), 3.0)
			draw_arc(module_center, size + 5.0, phase, phase + TAU * 0.75, 20, Color(color, fade * 0.7), 2.0)
		elif kind == "breach":
			var core := _cell_center(origin, cell_size, Vector2i(7, 3))
			var radius := 12.0 + (1.0 - fade) * cell_size * 0.72
			draw_circle(core, radius, Color(color, fade * 0.12), true)
			draw_arc(core, radius, -phase, -phase + TAU * 0.9, 32, Color(color, fade), 4.0)
			draw_line(core - Vector2(radius, 0), core + Vector2(radius, 0), Color(color, fade * 0.6), 2.0)

func _draw_fx_overlay(size: Vector2) -> void:
	if screen_feedback_time > 0.0 and not bool(snapshot.get("finished", false)):
		var feedback_fade := clampf(screen_feedback_strength * (screen_feedback_time / 0.7), 0.0, 1.0)
		var feedback_color := _effect_color("breach", Color("#ff6b75")) if screen_feedback_strength > 0.7 else _effect_color("hit", Color("#ffca62"))
		var edge := 4.0 + 5.0 * feedback_fade
		draw_rect(Rect2(0, 0, size.x, edge), Color(feedback_color, feedback_fade * 0.28), true)
		draw_rect(Rect2(0, size.y - edge, size.x, edge), Color(feedback_color, feedback_fade * 0.28), true)
		draw_rect(Rect2(0, 0, edge, size.y), Color(feedback_color, feedback_fade * 0.18), true)
		draw_rect(Rect2(size.x - edge, 0, edge, size.y), Color(feedback_color, feedback_fade * 0.18), true)
	if wave_banner_time > 0.0 and not wave_banner_text.is_empty():
		var rhythm_alpha := 0.78 + sin(wave_rhythm_phase) * 0.12
		var fade := clampf(wave_banner_time / 0.34, 0.0, 1.0) * rhythm_alpha
		var banner := Rect2(Vector2(0, TOP_BAR_HEIGHT + 4.0), Vector2(size.x, 54.0))
		draw_rect(banner, Color("#0b202a", 0.92 * fade), true)
		draw_line(banner.position + Vector2(0, banner.size.y), banner.position + Vector2(banner.size.x, banner.size.y), Color(wave_banner_color, 0.8 * fade), 2.0)
		draw_string(ThemeDB.fallback_font, banner.position + Vector2(0, 24), wave_banner_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color(wave_banner_color, fade))
		draw_string(ThemeDB.fallback_font, banner.position + Vector2(0, 43), "DETERMINISTIC EVENT BROADCAST", HORIZONTAL_ALIGNMENT_CENTER, size.x, 9, Color("#9fb8c1", fade))
	if bool(snapshot.get("finished", false)):
		var victory_state := bool(snapshot.get("victory", false))
		var color := _effect_color("success", Color("#68e3bf")) if victory_state else _effect_color("breach", Color("#ff6b75"))
		var fade_result := clampf(0.30 + result_transition_time * 0.18, 0.0, 0.74)
		draw_rect(Rect2(Vector2.ZERO, size), Color("#071017", fade_result), true)
		var title := "SYSTEM VICTORY" if victory_state else "CORE BREACHED"
		draw_string(ThemeDB.fallback_font, Vector2(0, size.y * 0.52), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 32, color)
		draw_string(ThemeDB.fallback_font, Vector2(0, size.y * 0.52 + 30), "点击底部「重试」重新编译防线", HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, Color("#c6dbe1", minf(1.0, fade_result + 0.2)))

func _cell_center(origin: Vector2, cell_size: float, cell: Vector2i) -> Vector2:
	return origin + (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size
