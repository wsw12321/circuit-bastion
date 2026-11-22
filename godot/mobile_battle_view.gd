extends "res://godot/battle_view.gd"
class_name MobileBattleView

## Touch-first presentation for Android exports.
## The simulation and command signals are inherited from BattleView so the
## mobile target exercises the same deterministic game contract as desktop.

const MOBILE_TOP_BAR_HEIGHT := 64.0
const MOBILE_BOTTOM_BAR_HEIGHT := 104.0
const MOBILE_MARGIN := 14.0

var touch_start := Vector2(-1.0, -1.0)
var touch_positions: Dictionary = {}
var touch_dragged := false
var pinch_distance := -1.0

func _mobile_layout_scale() -> float:
	# With stretch/aspect=expand, a narrow Android window keeps the design
	# height but expands its logical width. Counter-scale touch chrome and text
	# from the actual window size so the small-screen hierarchy stays readable.
	var logical_size := get_viewport_rect().size
	var window_size := Vector2(DisplayServer.window_get_size())
	if logical_size.x <= 0.0 or logical_size.y <= 0.0 or window_size.x <= 0.0 or window_size.y <= 0.0:
		return 1.0
	var stretch_ratio := minf(window_size.x / logical_size.x, window_size.y / logical_size.y)
	return clampf(1.0 / maxf(stretch_ratio, 0.1), 1.0, 1.8)

func _mobile_top_height() -> float:
	return MOBILE_TOP_BAR_HEIGHT * _mobile_layout_scale()

func _mobile_bottom_height() -> float:
	return MOBILE_BOTTOM_BAR_HEIGHT * _mobile_layout_scale()

func _mobile_margin() -> float:
	return MOBILE_MARGIN * _mobile_layout_scale()

func _ready() -> void:
	super._ready()
	# Mobile has a dedicated touch-first bottom bar. The desktop overlay would
	# otherwise duplicate controls and collapse the usable battlefield height.
	if ui_overlay != null:
		ui_overlay.visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()

func _draw() -> void:
	var size := get_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_draw_mobile(size)

func _draw_mobile(size: Vector2) -> void:
	var scale := _mobile_layout_scale()
	var margin := _mobile_margin()
	draw_rect(Rect2(Vector2.ZERO, size), Color("#071017", 0.18 if use_3d_battlefield else 0.58))
	_draw_mobile_top_bar(size)
	var metrics := _mobile_grid(size)
	var board: Rect2 = metrics["board"]
	var origin: Vector2 = metrics["origin"]
	var cell_size: float = metrics["cell_size"]
	# Keep silhouettes, labels, and health bars legible across narrow phones.
	character_scale = clampf(cell_size / 56.0, 0.62, 1.0)
	var battlefield_alpha := 0.10 if use_3d_battlefield else 0.48
	draw_rect(board, Color("#091923", battlefield_alpha), true)
	draw_rect(board, Color("#1c3c4b", 0.72 if use_3d_battlefield else 1.0), false, 1.0)
	if not use_3d_battlefield:
		draw_rect(Rect2(board.position + Vector2(7, 7), board.size - Vector2(14, 14)), Color("#112b36"), false, 1.0)
	draw_string(ThemeDB.fallback_font, board.position + Vector2(14.0 * scale, 25.0 * scale), "SECTOR 07 / TOUCH GRID", HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(12, int(round(12.0 * scale))), Color("#d7e8ed"))
	draw_string(ThemeDB.fallback_font, board.position + Vector2(board.size.x - 142.0 * scale, 25.0 * scale), "TICK %06d" % int(snapshot.get("tick", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(10, int(round(10.0 * scale))), Color("#6f929f"))
	if use_3d_battlefield:
		_draw_3d_overlay(board)
	if not use_3d_battlefield:
		for row in GRID_ROWS:
			for column in GRID_COLUMNS:
				var cell := Vector2i(column, row)
				var rect := Rect2(origin + Vector2(column, row) * cell_size + Vector2(2, 2), Vector2(cell_size - 4, cell_size - 4))
				var fill := Color("#173745") if cell == hover_cell else Color("#0d222c")
				draw_rect(rect, fill, true)
				draw_rect(rect, Color("#1b3b48"), false, 1.0)
		_draw_routes(origin, cell_size)
		_draw_board_markers(origin, cell_size)
	if not use_3d_battlefield:
		_draw_modules(origin, cell_size)
		_draw_enemies(origin, cell_size)
	var board_hint := "点按 3D 模块部署 · 双指旋转/缩放" if use_3d_battlefield else "点按格子选择模块 · 路由 %s" % (route_focus if route_focus != "" else "SIGNAL")
	draw_string(ThemeDB.fallback_font, board.position + Vector2(14.0 * scale, board.size.y - 13.0 * scale), board_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(10, int(round(10.0 * scale))), Color("#7697a4"))
	_draw_mobile_bottom_bar(size)

func _draw_mobile_top_bar(size: Vector2) -> void:
	var scale := _mobile_layout_scale()
	var top_height := _mobile_top_height()
	var margin := _mobile_margin()
	draw_rect(Rect2(0, 0, size.x, top_height), Color("#0b1822"), true)
	draw_line(Vector2(0, top_height - 1), Vector2(size.x, top_height - 1), Color("#1d3b4b"), 1.0)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(margin, 23.0 * scale), "CIRCUIT BASTION", HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(15, int(round(15.0 * scale))), Color("#e9f4f7"))
	var status := "暂停" if paused else "运行中"
	var status_color := Color("#ffca62") if paused else Color("#68e3bf")
	draw_circle(Vector2(margin + 4.0 * scale, 45.0 * scale), 4.0 * scale, status_color)
	draw_string(font, Vector2(margin + 14.0 * scale, 49.0 * scale), status, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(11, int(round(11.0 * scale))), status_color)
	draw_string(font, Vector2(size.x - 160.0 * scale, 23.0 * scale), "WAVE %02d" % int(snapshot.get("wave", 1)), HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(11, int(round(11.0 * scale))), Color("#9fb8c1"))
	draw_string(font, Vector2(size.x - 160.0 * scale, 46.0 * scale), "CORE %02d%%" % int(snapshot.get("integrity", 100)), HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(10, int(round(10.0 * scale))), Color("#68e3bf"))
	draw_string(font, Vector2(size.x - 78.0 * scale, 46.0 * scale), "%03d C" % int(snapshot.get("charge", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(10, int(round(10.0 * scale))), Color("#ffca62"))

func _draw_mobile_bottom_bar(size: Vector2) -> void:
	var scale := _mobile_layout_scale()
	var margin := _mobile_margin()
	var bottom_height := _mobile_bottom_height()
	var y := size.y - bottom_height
	draw_rect(Rect2(0, y, size.x, bottom_height), Color("#0b1822"), true)
	draw_line(Vector2(0, y), Vector2(size.x, y), Color("#1d3b4b"), 1.0)
	var rects := _mobile_action_rects(size)
	var labels := ["暂停" if not paused else "继续", "%d×" % speed, "回放", "商店"]
	var colors := [Color("#ffca62"), Color("#72d7ff"), Color("#b690ff"), Color("#68e3bf")]
	for index in rects.size():
		var active := (index == 0 and paused) or (index == 1 and speed > 1)
		_draw_mobile_button(rects[index], labels[index], colors[index], active)
	draw_string(ThemeDB.fallback_font, Vector2(margin, y + 88.0 * scale), "双指旋转/缩放 · 单指点选/拖动", HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(9, int(round(9.0 * scale))), Color("#60818c"))

func _draw_mobile_button(rect: Rect2, label: String, color: Color, active: bool) -> void:
	var scale := _mobile_layout_scale()
	draw_rect(rect, Color(color, 0.22 if active else 0.10), true)
	draw_rect(rect, color, false, 1.0)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(0, 29.0 * scale), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, maxi(13, int(round(13.0 * scale))), color)

func _mobile_action_rects(size: Vector2) -> Array:
	var scale := _mobile_layout_scale()
	var margin := _mobile_margin()
	var gap := 8.0 * scale
	var width := (size.x - margin * 2.0 - gap * 3.0) / 4.0
	var y := size.y - _mobile_bottom_height() + 14.0 * scale
	var rects: Array = []
	for index in 4:
		rects.append(Rect2(margin + index * (width + gap), y, width, 44.0 * scale))
	return rects

func _mobile_grid(size: Vector2) -> Dictionary:
	var margin := _mobile_margin()
	var top_height := _mobile_top_height()
	var bottom_height := _mobile_bottom_height()
	var board := Rect2(
		margin,
		top_height + 8.0 * _mobile_layout_scale(),
		maxf(120.0, size.x - margin * 2.0),
		maxf(120.0, size.y - top_height - bottom_height - 20.0 * _mobile_layout_scale())
	)
	var cell_size := minf((board.size.x - 24.0) / float(GRID_COLUMNS), (board.size.y - 46.0) / float(GRID_ROWS))
	var grid_size := Vector2(cell_size * GRID_COLUMNS, cell_size * GRID_ROWS)
	var origin := board.position + Vector2((board.size.x - grid_size.x) * 0.5, 34.0)
	return {"board": board, "cell_size": cell_size, "origin": origin}

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		active_touch_ids[event.index] = event.position if event.pressed else active_touch_ids.get(event.index, Vector2.ZERO)
		_forward_camera_input(event)
		if event.pressed:
			if active_touch_ids.size() > 1:
				touch_gesture_active = true
				touch_pointer_id = -1
				dragging_module_id = ""
				drag_origin_cell = Vector2i(-1, -1)
				preview_cell = Vector2i(-1, -1)
				queue_redraw()
				return
			touch_pointer_id = event.index
			touch_start = event.position
			hover_cell = _cell_at_mobile(event.position)
			_mobile_pointer_press(event.position)
		else:
			active_touch_ids.erase(event.index)
			if touch_gesture_active:
				if active_touch_ids.is_empty():
					touch_gesture_active = false
				touch_pointer_id = -1
				queue_redraw()
				return
			if touch_pointer_id == event.index:
				_mobile_pointer_release(event.position)
				touch_pointer_id = -1
	elif event is InputEventScreenDrag:
		if touch_gesture_active:
			_forward_camera_input(event)
			return
		if _forward_camera_input(event):
			return
		if event.index == touch_pointer_id:
			hover_cell = _cell_at_mobile(event.position)
			preview_cell = hover_cell
			preview_valid = _cell_is_valid(preview_cell, dragging_module_id)
			queue_redraw()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_mobile_pointer_press(event.position)
			else:
				_mobile_pointer_release(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Keep the desktop and touch-first views in sync: the orbit camera
			# needs the release event to clear its right-button drag latch.
			if event.pressed:
				_cancel_interaction("已取消部署")
			_forward_camera_input(event)
		elif event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_forward_camera_input(event)
	elif event is InputEventMouseMotion:
		if _forward_camera_input(event):
			return
		hover_cell = _cell_at_mobile(event.position)
		if build_mode or not dragging_module_id.is_empty():
			preview_cell = hover_cell
			preview_valid = _cell_is_valid(preview_cell, dragging_module_id)
		queue_redraw()


func _mobile_pointer_press(position: Vector2) -> void:
	var size := get_rect().size
	var rects := _mobile_action_rects(size)
	for index in rects.size():
		if rects[index].has_point(position):
			_mobile_action(index)
			return
	var cell := _cell_at_mobile(position)
	if cell.x < 0:
		return
	selected_cell = cell
	hover_cell = cell
	preview_cell = cell
	preview_valid = _cell_is_valid(cell, dragging_module_id)
	if build_mode:
		queue_redraw()
		return
	var module_id := _module_at_cell(cell)
	if not module_id.is_empty():
		selected_module_id = module_id
		module_selected.emit(selected_module_id)
		dragging_module_id = module_id
		drag_origin_cell = cell
		preview_valid = true
	cell_selected.emit(cell)
	queue_redraw()


func _mobile_pointer_release(position: Vector2) -> void:
	var size := get_rect().size
	for rect in _mobile_action_rects(size):
		if rect.has_point(position):
			return
	var cell := _cell_at_mobile(position)
	if cell.x < 0:
		dragging_module_id = ""
		drag_origin_cell = Vector2i(-1, -1)
		preview_cell = Vector2i(-1, -1)
		queue_redraw()
		return
	hover_cell = cell
	preview_cell = cell
	if build_mode:
		preview_valid = _cell_is_valid(cell)
		if preview_valid:
			command_requested.emit("build:%s:%d:%d:%d" % [build_kind, cell.x, cell.y, build_rotation])
			build_mode = false
			feedback_message = "已部署 %s · 等待连接" % build_kind
			feedback_tone = "ok"
			_trigger_screen_feedback(0.12, 0.10)
		else:
			feedback_message = "位置冲突 · 请选择空闲网格"
			feedback_tone = "warn"
			_trigger_screen_feedback(0.34, 0.24)
		queue_redraw()
		return
	if not dragging_module_id.is_empty():
		if cell != drag_origin_cell and _cell_is_valid(cell, dragging_module_id):
			command_requested.emit("move:%s:%d:%d" % [dragging_module_id, cell.x, cell.y])
			feedback_message = "移动 %s → [%d,%d]" % [dragging_module_id, cell.x, cell.y]
			feedback_tone = "ok"
			_trigger_screen_feedback(0.12, 0.10)
		elif cell != drag_origin_cell:
			feedback_message = "移动被阻止 · 目标网格不可用"
			feedback_tone = "warn"
			_trigger_screen_feedback(0.34, 0.24)
		dragging_module_id = ""
		drag_origin_cell = Vector2i(-1, -1)
		preview_valid = _cell_is_valid(cell)
		queue_redraw()


func _mobile_action(index: int) -> void:
	match index:
		0:
			paused = not paused
			command_requested.emit("pause" if paused else "resume")
		1:
			speed = 1 if speed >= 4 else speed * 2
			command_requested.emit("speed:%d" % speed)
		2:
			command_requested.emit("replay")
		3:
			var items := _display_shop_items()
			if not items.is_empty():
				build_kind = str(items[0].get("kind", "pulse_cannon"))
				build_mode = true
				preview_cell = Vector2i(-1, -1)
				feedback_message = "部署 %s · 点按格子确认" % str(items[0].get("name", build_kind))
				feedback_tone = "info"
				command_requested.emit("shop:buy:0")
				command_requested.emit("shop:select:0:%s" % build_kind)
	queue_redraw()


func _rotate_battle_camera(delta: Vector2) -> void:
	# Keep the Android contract explicit while sharing the desktop orbit implementation.
	super._rotate_battle_camera(delta)


func _zoom_battle_camera(delta: float) -> void:
	# Pinch and wheel zoom use the same clamped camera target on every platform.
	super._zoom_battle_camera(delta)


func _cell_at_mobile(position: Vector2) -> Vector2i:
	var metrics := _mobile_grid(get_rect().size)
	var board: Rect2 = metrics["board"]
	if use_3d_battlefield:
		return _cell_at_3d(position, board)
	var cell_size: float = metrics["cell_size"]
	if cell_size <= 0.0:
		return Vector2i(-1, -1)
	var origin: Vector2 = metrics["origin"]
	var local := (position - origin) / cell_size
	var cell := Vector2i(floor(local.x), floor(local.y))
	if cell.x < 0 or cell.y < 0 or cell.x >= GRID_COLUMNS or cell.y >= GRID_ROWS:
		return Vector2i(-1, -1)
	return cell
