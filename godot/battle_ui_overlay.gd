extends Control
class_name BattleUIOverlay

const UI_THEME := preload("res://godot/ui_theme.tres")

var battle_view: Control
var pause_button: Button
var speed_button: Button
var replay_button: Button
var retry_button: Button
var refresh_button: Button
var sell_button: Button
var shop_buttons: Array[Button] = []
var bench_buttons: Array[Button] = []
var branch_buttons: Array[Button] = []
var inspector_card: Panel
var inspector_title: Label
var inspector_meta: Label
var inspector_telemetry: Label
var ghost_panel: Panel
var ghost_label: Label
var tooltip_panel: Panel
var tooltip_label: Label
var last_size := Vector2(-1.0, -1.0)
var last_selected := ""

func attach(view: Control) -> void:
	battle_view = view
	theme = UI_THEME
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_controls()
	_layout_controls()
	_sync_controls()
	set_process(true)


func _build_controls() -> void:
	pause_button = _make_button("暂停", "切换战斗暂停状态", _on_pause_pressed)
	speed_button = _make_button("1×", "切换 1× / 2× / 4× 模拟速度", _on_speed_pressed)
	replay_button = _make_button("事件回放", "导出当前确定性事件轨迹", _on_replay_pressed)
	retry_button = _make_button("重试", "保留当前种子重新开始", _on_retry_pressed)
	refresh_button = _make_button("刷新", "轮转备战商店", _on_refresh_pressed)
	sell_button = _make_button("出售", "出售当前选中的模块", _on_sell_pressed)
	sell_button.add_theme_color_override("font_color", Color("#ff9aa1"))
	
	for index in range(3):
		var shop_button := _make_button("模块", "购买并部署该模块", _on_shop_pressed.bind(index))
		shop_buttons.append(shop_button)
		var bench_button := _make_button("备战", "从备战栏选择模块并部署", _on_bench_pressed.bind(index))
		bench_buttons.append(bench_button)
	
	for branch in ["overclock", "fortify", "logic"]:
		var branch_button := _make_button(branch.to_upper(), "编译台升级分支 · " + branch, _on_branch_pressed.bind(branch))
		branch_buttons.append(branch_button)
	
	inspector_card = Panel.new()
	inspector_card.theme = UI_THEME
	inspector_card.add_theme_stylebox_override("panel", UI_THEME.get_stylebox("panel", "Card"))
	inspector_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(inspector_card)
	inspector_title = _make_label(inspector_card, "脉冲炮", 15, Color("#f2d18a"))
	inspector_meta = _make_label(inspector_card, "执行模块 · Tier 02", 10, Color("#86a5af"))
	inspector_telemetry = _make_label(inspector_card, "功率 4.2 kW · 延迟 80 ms", 10, Color("#a8c0c8"))
	inspector_title.position = Vector2(52, 12)
	inspector_meta.position = Vector2(52, 35)
	inspector_telemetry.position = Vector2(52, 54)
	sell_button.reparent(inspector_card)
	sell_button.position = Vector2(232, 11)
	sell_button.size = Vector2(70, 28)
	
	ghost_panel = Panel.new()
	ghost_panel.theme = UI_THEME
	ghost_panel.add_theme_stylebox_override("panel", UI_THEME.get_stylebox("panel", "Ghost"))
	ghost_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost_label = _make_label(ghost_panel, "可部署", 11, Color("#9af0d3"))
	ghost_label.position = Vector2(12, 9)
	add_child(ghost_panel)
	
	tooltip_panel = Panel.new()
	tooltip_panel.theme = UI_THEME
	tooltip_panel.add_theme_stylebox_override("panel", UI_THEME.get_stylebox("panel", "Tooltip"))
	tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_label = _make_label(tooltip_panel, "", 11, Color("#d8eef3"))
	tooltip_label.position = Vector2(12, 8)
	add_child(tooltip_panel)
	tooltip_panel.visible = false


func _make_button(label: String, tip: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.theme = UI_THEME
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.tooltip_text = tip
	button.pressed.connect(callback)
	button.mouse_entered.connect(_show_tooltip.bind(tip))
	button.mouse_exited.connect(_hide_tooltip)
	add_child(button)
	return button


func _make_label(parent: Control, value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _view_value(property: String, fallback: Variant) -> Variant:
	if battle_view == null or not is_instance_valid(battle_view):
		return fallback
	var value = battle_view.get(property)
	return fallback if value == null else value


func _is_compact(size: Vector2) -> bool:
	return size.x < 980.0 or size.x < size.y * 0.9


func _layout_controls() -> void:
	if battle_view == null:
		return
	var size := get_rect().size
	if size.x < 10.0 or size.y < 10.0:
		return
	if size == last_size:
		return
	last_size = size
	var compact := _is_compact(size)
	var bottom_height := 190.0 if compact else 84.0
	var bottom_y := size.y - bottom_height
	var margin := 28.0
	
	_place(pause_button, Vector2(margin, bottom_y + 20), Vector2(118, 38), true)
	_place(speed_button, Vector2(margin + 128, bottom_y + 20), Vector2(80, 38), true)
	_place(replay_button, Vector2(margin + 218, bottom_y + 20), Vector2(118, 38), true)
	_place(retry_button, Vector2(margin + 346, bottom_y + 20), Vector2(44, 38), bool(_view_value("snapshot", {}).get("finished", false)))
	
	if compact:
		var gap := 4.0
		var item_width := maxf(70.0, (size.x - 32.0 - 60.0 - gap * 3.0) / 3.0)
		for index in range(3):
			_place(shop_buttons[index], Vector2(16 + index * (item_width + gap), bottom_y + 66), Vector2(item_width, 48), true)
			_place(bench_buttons[index], Vector2(120 + index * 88, bottom_y + 122), Vector2(82, 38), index < _bench_items().size())
		_place(refresh_button, Vector2(size.x - 76, bottom_y + 66), Vector2(60, 48), true)
	else:
		for index in range(3):
			_place(shop_buttons[index], Vector2(390 + index * 108, bottom_y + 25), Vector2(98, 45), true)
			_place(bench_buttons[index], Vector2(800 + index * 72, bottom_y + 25), Vector2(64, 45), index < _bench_items().size())
		_place(refresh_button, Vector2(714, bottom_y + 25), Vector2(72, 45), true)
	
	var panel_rect := Rect2(size.x - 326.0 - margin, 72.0 + 20.0, 326.0, maxf(220.0, size.y - 72.0 - bottom_height - 40.0))
	inspector_card.visible = not compact
	inspector_card.position = panel_rect.position + Vector2(16, 68)
	inspector_card.size = Vector2(panel_rect.size.x - 32, 82)
	for index in range(branch_buttons.size()):
		var branch := branch_buttons[index]
		_place(branch, panel_rect.position + Vector2(14 + index * 98, 530), Vector2(90, 34), not compact)
	
	var board_reserve := 0.0 if compact else 326.0 + margin * 3.0
	var board := Rect2(margin, 72.0 + 20.0, maxf(180.0, size.x - board_reserve), size.y - 72.0 - bottom_height - 40.0)
	ghost_panel.position = board.position + Vector2(18, 42)
	ghost_panel.size = Vector2(minf(280.0, board.size.x - 36.0), 36)
	ghost_panel.visible = bool(_view_value("build_mode", false)) or not str(_view_value("dragging_module_id", "")).is_empty()


func _place(button: Control, position: Vector2, size: Vector2, visible: bool) -> void:
	button.position = position
	button.size = size
	button.visible = visible


func _process(_delta: float) -> void:
	_layout_controls()
	_sync_controls()


func _sync_controls() -> void:
	if battle_view == null:
		return
	var snapshot := _view_value("snapshot", {}) as Dictionary
	var paused := bool(_view_value("paused", false))
	var speed := int(_view_value("speed", 1))
	pause_button.text = "继续" if paused else "暂停"
	speed_button.text = "%d×" % speed
	retry_button.visible = bool(snapshot.get("finished", false)) and not _is_compact(get_rect().size)
	
	var selected_id := str(_view_value("selected_module_id", ""))
	var selected_name := "模块"
	var selected_load := 0.0
	var modules := _view_value("modules", []) as Array
	for module in modules:
		if str(module.get("id", "")) == selected_id:
			selected_name = str(module.get("name", module.get("label", selected_name)))
			selected_load = float(module.get("load", 0.0))
			break
	if selected_id != last_selected:
		last_selected = selected_id
		if not selected_id.is_empty():
			_show_tooltip("已选中 · %s · 长按查看详情" % selected_name)
	inspector_title.text = selected_name
	inspector_meta.text = "执行模块 · 负载 %02d%%" % int(selected_load * 100.0)
	inspector_telemetry.text = "功率 %0.1f kW · 线路带宽 64%%" % (4.2 + selected_load * 2.0)
	
	var shop := _shop_items()
	for index in range(shop_buttons.size()):
		var button := shop_buttons[index]
		if index < shop.size():
			var item: Dictionary = shop[index]
			button.text = "%s\n%s" % [str(item.get("name", "模块")), str(item.get("cost", "0 C"))]
			button.disabled = false
			button.tooltip_text = "购买 %s · %s" % [str(item.get("name", "模块")), str(item.get("cost", "0 C"))]
		else:
			button.text = "空槽"
			button.disabled = true
	var bench := _bench_items()
	for index in range(bench_buttons.size()):
		if index < bench.size():
			var item: Dictionary = bench[index]
			bench_buttons[index].text = "%s\n部署" % str(item.get("label", item.get("kind", "模块")))
			bench_buttons[index].disabled = false
		else:
			bench_buttons[index].text = "空备战"
			bench_buttons[index].disabled = true
	var build_mode := bool(_view_value("build_mode", false))
	ghost_panel.visible = build_mode or not str(_view_value("dragging_module_id", "")).is_empty()
	if ghost_panel.visible:
		var kind := str(_view_value("build_kind", "模块"))
		var valid := bool(_view_value("preview_valid", false))
		ghost_label.text = "部署 %s · %s · R 旋转" % [kind, "可部署" if valid else "位置冲突"]
		ghost_label.add_theme_color_override("font_color", Color("#9af0d3") if valid else Color("#ff9aa1"))
	
	var finished := bool(snapshot.get("finished", false))
	if finished:
		tooltip_panel.visible = false


func _shop_items() -> Array:
	if battle_view != null and battle_view.has_method("_display_shop_items"):
		var result: Variant = battle_view.call("_display_shop_items")
		if result is Array:
			return result
	return []


func _bench_items() -> Array:
	var value := _view_value("bench_items", [])
	return value as Array if value is Array else []


func _emit_command(command: String) -> void:
	if battle_view == null:
		return
	battle_view.emit_signal("command_requested", command)
	_pulse(pause_button if command in ["pause", "resume"] else speed_button)
	

func _pulse(control: Control) -> void:
	if control == null:
		return
	control.scale = Vector2(0.96, 0.96)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, 0.22)


func _on_pause_pressed() -> void:
	var paused := bool(_view_value("paused", false))
	_emit_command("resume" if paused else "pause")


func _on_speed_pressed() -> void:
	var speed := int(_view_value("speed", 1))
	var next_speed := 1 if speed >= 4 else speed * 2
	_emit_command("speed:%d" % next_speed)


func _on_replay_pressed() -> void:
	_emit_command("replay")


func _on_retry_pressed() -> void:
	_emit_command("retry")


func _on_refresh_pressed() -> void:
	var revision := int(_view_value("shop_revision", 1)) + 1
	battle_view.set("shop_revision", revision)
	battle_view.set("feedback_message", "商店刷新 · 轮次 R%02d" % revision)
	_emit_command("shop:refresh:%d" % revision)


func _on_shop_pressed(index: int) -> void:
	var shop := _shop_items()
	if index >= shop.size():
		return
	var item: Dictionary = shop[index]
	var kind := str(item.get("kind", "pulse_cannon"))
	battle_view.set("build_kind", kind)
	battle_view.set("build_mode", true)
	battle_view.set("feedback_message", "部署 %s · 点击网格确认 · R 旋转" % str(item.get("name", kind)))
	_emit_command("shop:buy:%d" % index)
	battle_view.emit_signal("command_requested", "shop:select:%d:%s" % [index, kind])


func _on_bench_pressed(index: int) -> void:
	var bench := _bench_items()
	if index >= bench.size():
		return
	var item: Dictionary = bench[index]
	var kind := str(item.get("kind", "pulse_cannon"))
	battle_view.set("build_kind", kind)
	battle_view.set("build_mode", true)
	battle_view.set("feedback_message", "备战栏 · 部署 %s" % str(item.get("label", kind)))
	_emit_command("bench:select:%d" % index)


func _on_sell_pressed() -> void:
	var selected := str(_view_value("selected_module_id", ""))
	if selected.is_empty():
		_show_tooltip("先在战场选择一个模块")
		return
	_emit_command("sell:%s" % selected)


func _on_branch_pressed(branch: String) -> void:
	battle_view.set("selected_upgrade_branch", branch)
	_emit_command("upgrade:%s" % branch)


func _show_tooltip(message: String) -> void:
	if tooltip_panel == null or message.is_empty():
		return
	tooltip_label.text = message
	tooltip_panel.size = Vector2(minf(320.0, maxf(180.0, message.length() * 9.0)), 34)
	var mouse := get_local_mouse_position()
	tooltip_panel.position = Vector2(clampf(mouse.x + 14.0, 8.0, maxf(8.0, get_rect().size.x - tooltip_panel.size.x - 8.0)), clampf(mouse.y + 12.0, 8.0, maxf(8.0, get_rect().size.y - tooltip_panel.size.y - 8.0)))
	tooltip_panel.visible = true


func _hide_tooltip() -> void:
	if tooltip_panel != null and not bool(_view_value("build_mode", false)):
		tooltip_panel.visible = false
