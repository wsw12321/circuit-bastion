class_name BastionEnemyActor
extends CharacterBody2D

## Physics-backed enemy actor.
## The simulation owns the authoritative progress value. This node smooths the
## presentation toward that value and provides a real collision body for world
## queries and contact checks.

signal reached_core(enemy_id: String)
signal moved(enemy_id: String, progress: float, world_position: Vector2)

const ENEMY_COLLISION_LAYER := 2

var enemy_id := ""
var kind := ""
var target_progress := 0.0
var path_progress := 0.0
var speed := 0.0
var damage := 1
var hit_radius := 14.0
var path_curve: Curve2D
var initialized := false

func _ready() -> void:
	collision_layer = ENEMY_COLLISION_LAYER
	collision_mask = 0
	var shape := CollisionShape2D.new()
	shape.name = "EnemyCollisionShape"
	var circle := CircleShape2D.new()
	circle.radius = hit_radius
	shape.shape = circle
	add_child(shape)
	queue_redraw()

func configure(state: Dictionary, curve: Curve2D) -> void:
	enemy_id = str(state.get("id", enemy_id))
	kind = str(state.get("kind", kind))
	target_progress = float(state.get("progress", target_progress))
	damage = maxi(1, int(state.get("damage", damage)))
	speed = float(state.get("speed", speed))
	path_curve = curve
	if not initialized:
		path_progress = target_progress
		global_position = _sample_path(path_progress)
		initialized = true
	queue_redraw()

func advance(delta: float) -> void:
	if path_curve == null or path_curve.get_baked_length() <= 0.0:
		return
	var safe_delta := maxf(delta, 0.0001)
	var previous := global_position
	var blend := 1.0 - exp(-safe_delta * 12.0)
	path_progress = lerpf(path_progress, target_progress, clampf(blend, 0.0, 1.0))
	var target_position := _sample_path(path_progress)
	velocity = (target_position - global_position) / safe_delta
	move_and_slide()
	if get_slide_collision_count() == 0:
		global_position = global_position.lerp(target_position, clampf(safe_delta * 8.0, 0.0, 1.0))
	if previous.distance_to(global_position) > 0.01:
		moved.emit(enemy_id, path_progress, global_position)
	if path_progress >= 0.995:
		reached_core.emit(enemy_id)
	queue_redraw()

func get_enemy_id() -> String:
	return enemy_id

func get_path_progress() -> float:
	return path_progress

func _sample_path(progress: float) -> Vector2:
	if path_curve == null:
		return global_position
	var length := path_curve.get_baked_length()
	if length <= 0.0:
		return global_position
	return path_curve.sample_baked(clampf(progress, 0.0, 1.0) * length)

func _draw() -> void:
	var tint := Color("#ff6b75")
	if kind == "scout":
		tint = Color("#63d9ff")
	elif kind == "bruiser":
		tint = Color("#ff8f6b")
	elif kind == "boss":
		tint = Color("#ff5f7a")
	draw_circle(Vector2.ZERO, hit_radius, Color(tint, 0.16))
	draw_arc(Vector2.ZERO, hit_radius, 0.0, TAU, 20, tint, 2.0)
