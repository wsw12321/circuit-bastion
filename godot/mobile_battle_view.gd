extends "res://godot/battle_view.gd"
class_name MobileBattleView

## Touch-first presentation for Android exports.
## The simulation and command signals are inherited from BattleView so the
## mobile target exercises the same deterministic game contract as desktop.

const MOBILE_TOP_BAR_HEIGHT := 64.0
const MOBILE_BOTTOM_BAR_HEIGHT := 104.0
const MOBILE_MARGIN := 14.0

var touch_start := Vector2(-1.0, -1.0)

func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()

func _draw() -> void:
	var size := get_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_draw_mobile(size)

func _draw_mobile(size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#071017", 0.58))
	_draw_mobile_top_bar(size)
	var metrics := _mobile_grid(size)
	var board: Rect2 = metrics["board"]
	var origin: Vector2 = metrics["origin"]
	var cell_size: float = metrics["cell_size"]
	# Keep silhouettes, labels, and health bars legible across narrow phones.
	character_scale = clampf(cell_size / 56.0, 0.62, 1.0)
	draw_rect(board, Color("#091923", 0.48), true)
	draw_rect(board, Color("#1c3c4b"), false, 1.0)
	draw_rect(Rect2(board.position + Vector2(7, 7), board.size - Vector2(14, 14)), Color("#112b36"), false, 1.0)
	draw_string(ThemeDB.fallback_font, board.position + Vector2(14, 25), "SECTOR 07 / TOUCH GRID", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#d7e8ed"))
	draw_string(ThemeDB.fallback_font, board.position + Vector2(board.size.x - 142, 25), "TICK %06d" % int(snapshot.get("tick", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#6f929f"))
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
	draw_string(ThemeDB.fallback_font, board.position + Vector2(14, board.size.y - 13), "点按格子选择模块 · 路由 %s" % (route_focus if route_focus != "" else "SIGNAL"), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#7697a4"))
	_draw_mobile_bottom_bar(size)

func _draw_mobile_top_bar(size: Vector2) -> void:
	draw_rect(Rect2(0, 0, size.x, MOBILE_TOP_BAR_HEIGHT), Color("#0b1822"), true)
	draw_line(Vector2(0, MOBILE_TOP_BAR_HEIGHT - 1), Vector2(size.x, MOBILE_TOP_BAR_HEIGHT - 1), Color("#1d3b4b"), 1.0)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(MOBILE_MARGIN, 23), "CIRCUIT BASTION", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#e9f4f7"))
	var status := "暂停" if paused else "运行中"
	var status_color := Color("#ffca62") if paused else Color("#68e3bf")
	draw_circle(Vector2(MOBILE_MARGIN + 4, 45), 4.0, status_color)
	draw_string(font, Vector2(MOBILE_MARGIN + 14, 49), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, status_color)
	draw_string(font, Vector2(size.x - 160, 23), "WAVE %02d" % int(snapshot.get("wave", 1)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#9fb8c1"))
	draw_string(font, Vector2(size.x - 160, 46), "CORE %02d%%" % int(snapshot.get("integrity", 100)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#68e3bf"))
	draw_string(font, Vector2(size.x - 78, 46), "%03d C" % int(snapshot.get("charge", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#ffca62"))

func _draw_mobile_bottom_bar(size: Vector2) -> void:
	var y := size.y - MOBILE_BOTTOM_BAR_HEIGHT
	draw_rect(Rect2(0, y, size.x, MOBILE_BOTTOM_BAR_HEIGHT), Color("#0b1822"), true)
	draw_line(Vector2(0, y), Vector2(size.x, y), Color("#1d3b4b"), 1.0)
	var rects := _mobile_action_rects(size)
	var labels := ["暂停" if not paused else "继续", "%d×" % speed, "回放", "商店"]
	var colors := [Color("#ffca62"), Color("#72d7ff"), Color("#b690ff"), Color("#68e3bf")]
	for index in rects.size():
		var active := (index == 0 and paused) or (index == 1 and speed > 1)
		_draw_mobile_button(rects[index], labels[index], colors[index], active)
	draw_string(ThemeDB.fallback_font, Vector2(MOBILE_MARGIN, y + 88), "双指旋转/缩放 · 单指点选/拖动", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#60818c"))

func _draw_mobile_button(rect: Rect2, label: String, color: Color, active: bool) -> void:
	draw_rect(rect, Color(color, 0.22 if active else 0.10), true)
	draw_rect(rect, color, false, 1.0)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(0, 29), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 13, color)

func _mobile_action_rects(size: Vector2) -> Array:
	var gap := 8.0
	var width := (size.x - MOBILE_MARGIN * 2.0 - gap * 3.0) / 4.0
	var y := size.y - MOBILE_BOTTOM_BAR_HEIGHT + 14.0
	var rects: Array = []
	for index in 4:
		rects.append(Rect2(MOBILE_MARGIN + index * (width + gap), y, width, 44.0))
	return rects

func _mobile_grid(size: Vector2) -> Dictionary:
	var board := Rect2(
		MOBILE_MARGIN,
		MOBILE_TOP_BAR_HEIGHT + 8.0,
		maxf(120.0, size.x - MOBILE_MARGIN * 2.0),
		maxf(120.0, size.y - MOBILE_TOP_BAR_HEIGHT - MOBILE_BOTTOM_BAR_HEIGHT - 20.0)
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
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_cancel_interaction("已取消部署")
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


func _cell_at_mobile(position: Vector2) -> Vector2i:
	var metrics := _mobile_grid(get_rect().size)
	var cell_size: float = metrics["cell_size"]
	if cell_size <= 0.0:
		return Vector2i(-1, -1)
	var origin: Vector2 = metrics["origin"]
	var local := (position - origin) / cell_size
	var cell := Vector2i(floor(local.x), floor(local.y))
	if cell.x < 0 or cell.y < 0 or cell.x >= GRID_COLUMNS or cell.y >= GRID_ROWS:
		return Vector2i(-1, -1)
	return cell
