class_name BastionBattleCamera3D
extends Camera3D

## Orbit camera with smoothed yaw, pitch, and zoom controls.

@export var target := Vector3(0.0, 0.0, 0.0)
@export_range(4.0, 24.0, 0.1) var zoom_distance := 12.0
@export_range(-1.3, -0.15, 0.01) var pitch := -0.72
@export_range(-3.14, 3.14, 0.01) var yaw := 0.35

var target_zoom_distance := 12.0
var target_pitch := -0.72
var target_yaw := 0.35
var smoothing := 12.0

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

func rotate_orbit(delta: Vector2) -> void:
	target_yaw = wrapf(target_yaw + delta.x * 0.01, -PI, PI)
	target_pitch = clampf(target_pitch + delta.y * 0.01, -1.3, -0.15)

func zoom_by(delta: float) -> void:
	target_zoom_distance = clampf(target_zoom_distance + delta, 4.0, 24.0)

func get_orbit_yaw() -> float:
	return target_yaw

func get_orbit_pitch() -> float:
	return target_pitch

func get_zoom_distance() -> float:
	return target_zoom_distance

func _apply_transform() -> void:
	var horizontal := cos(pitch) * zoom_distance
	# Negative pitch angles represent an elevated orbit around the target.
	position = target + Vector3(sin(yaw) * horizontal, -sin(pitch) * zoom_distance, cos(yaw) * horizontal)
	look_at(target, Vector3.UP)
