class_name BastionBattleCamera3D
extends Camera3D

## Orbit camera with frame-rate independent smoothing and shared mouse/touch gestures.

signal camera_changed(yaw: float, pitch: float, zoom_distance: float)

@export var target := Vector3(0.0, 0.0, 0.0)
@export_range(4.0, 24.0, 0.1) var zoom_distance := 16.0
@export_range(-1.3, -0.15, 0.01) var pitch := -0.72
@export_range(-3.14, 3.14, 0.01) var yaw := 0.35
@export_range(6.0, 24.0, 0.1) var smoothing := 14.0
@export_range(0.001, 0.03, 0.001) var orbit_sensitivity := 0.008
@export_range(0.1, 3.0, 0.05) var wheel_zoom_step := 1.2
@export_range(0.001, 0.1, 0.001) var pinch_zoom_sensitivity := 0.018

var target_zoom_distance := 16.0
var target_pitch := -0.72
var target_yaw := 0.35
var interaction_enabled := true

var _orbit_dragging := false
var _touch_points: Dictionary = {}
var _pinch_distance := -1.0
var _pinch_center := Vector2.ZERO

func _ready() -> void:
	target_zoom_distance = zoom_distance
	target_pitch = pitch
	target_yaw = yaw
	_apply_transform()

func _process(delta: float) -> void:
	var blend := 1.0 - exp(-maxf(delta, 0.0001) * smoothing)
	zoom_distance = lerpf(zoom_distance, target_zoom_distance, blend)
	pitch = lerpf(pitch, target_pitch, blend)
	yaw = lerp_angle(yaw, target_yaw, blend)
	_apply_transform()

func handle_input(event: InputEvent) -> bool:
	if not interaction_enabled:
		return false
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
			_orbit_dragging = event.pressed
			return true
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(-wheel_zoom_step)
			return true
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(wheel_zoom_step)
			return true
	elif event is InputEventMouseMotion and _orbit_dragging:
		rotate_orbit(event.relative)
		return true
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touch_points[event.index] = event.position
			if _touch_points.size() == 2:
				_begin_pinch()
				return true
			return false
		_touch_points.erase(event.index)
		if _touch_points.size() < 2:
			_end_pinch()
		return _touch_points.size() > 0
	elif event is InputEventScreenDrag:
		if not _touch_points.has(event.index):
			return false
		_touch_points[event.index] = event.position
		if _touch_points.size() < 2:
			return false
		var ids := _touch_points.keys()
		ids.sort()
		var first: Vector2 = _touch_points[ids[0]]
		var second: Vector2 = _touch_points[ids[1]]
		var center := (first + second) * 0.5
		var distance := first.distance_to(second)
		rotate_orbit(center - _pinch_center)
		zoom_by((_pinch_distance - distance) * pinch_zoom_sensitivity)
		_pinch_center = center
		_pinch_distance = distance
		return true
	return false

func rotate_orbit(delta: Vector2) -> void:
	target_yaw = wrapf(target_yaw + delta.x * orbit_sensitivity, -PI, PI)
	target_pitch = clampf(target_pitch + delta.y * orbit_sensitivity, -1.3, -0.15)
	camera_changed.emit(target_yaw, target_pitch, target_zoom_distance)

func zoom_by(delta: float) -> void:
	target_zoom_distance = clampf(target_zoom_distance + delta, 4.0, 24.0)
	camera_changed.emit(target_yaw, target_pitch, target_zoom_distance)

func reset_view() -> void:
	target_zoom_distance = 16.0
	target_pitch = -0.72
	target_yaw = 0.35
	camera_changed.emit(target_yaw, target_pitch, target_zoom_distance)

func get_orbit_yaw() -> float:
	return target_yaw

func get_orbit_pitch() -> float:
	return target_pitch

func get_zoom_distance() -> float:
	return target_zoom_distance

func _begin_pinch() -> void:
	var ids := _touch_points.keys()
	ids.sort()
	var first: Vector2 = _touch_points[ids[0]]
	var second: Vector2 = _touch_points[ids[1]]
	_pinch_center = (first + second) * 0.5
	_pinch_distance = first.distance_to(second)

func _end_pinch() -> void:
	_pinch_distance = -1.0
	_pinch_center = Vector2.ZERO

func _apply_transform() -> void:
	var horizontal := cos(pitch) * zoom_distance
	# Keep the negative public pitch convention while placing the camera above the board.
	position = target + Vector3(sin(yaw) * horizontal, -sin(pitch) * zoom_distance, cos(yaw) * horizontal)
	look_at(target, Vector3.UP)
