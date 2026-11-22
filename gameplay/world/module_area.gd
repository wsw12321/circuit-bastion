class_name BastionModuleArea
extends Area2D

## Deployable module collider.
## The module remains a spatial Area2D even when the deterministic simulation
## is paused, so deployment previews and contact queries share one geometry.

signal hit_received(module_id: String, attacker_id: String, damage: int, remaining_health: int)

const MODULE_COLLISION_LAYER := 4
const ENEMY_COLLISION_LAYER := 2

var module_id := ""
var kind := ""
var grid_position := Vector2i(-1, -1)
var max_health := 100
var health := 100
var contact_radius := 34.0
var _configured := false

func _ready() -> void:
	collision_layer = MODULE_COLLISION_LAYER
	collision_mask = ENEMY_COLLISION_LAYER
	monitoring = true
	monitorable = true
	var shape := CollisionShape2D.new()
	shape.name = "ModuleCollisionShape"
	var circle := CircleShape2D.new()
	circle.radius = contact_radius
	shape.shape = circle
	add_child(shape)
	queue_redraw()

func configure(state: Dictionary, world_position: Vector2) -> void:
	module_id = str(state.get("id", module_id))
	kind = str(state.get("kind", kind))
	var grid: Dictionary = state.get("grid", {})
	grid_position = Vector2i(int(grid.get("x", grid_position.x)), int(grid.get("y", grid_position.y)))
	global_position = world_position
	var level := maxi(1, int(state.get("level", 1)))
	var next_max_health := 100 + (level - 1) * 20
	if not _configured:
		max_health = next_max_health
		health = max_health
		_configured = true
	elif max_health != next_max_health:
		var ratio := float(health) / float(maxi(1, max_health))
		max_health = next_max_health
		health = maxi(1, int(round(ratio * float(max_health))))
	queue_redraw()

func receive_hit(attacker_id: String, damage: int) -> void:
	var applied := maxi(0, damage)
	if applied == 0 or health <= 0:
		return
	health = maxi(0, health - applied)
	hit_received.emit(module_id, attacker_id, applied, health)
	queue_redraw()

func is_destroyed() -> bool:
	return health <= 0

func get_health_ratio() -> float:
	return float(health) / float(maxi(1, max_health))

func _draw() -> void:
	var tint := Color("#72d7ff")
	if kind == "pulse_cannon":
		tint = Color("#ffca62")
	elif kind == "router":
		tint = Color("#b690ff")
	elif kind == "heat_sink":
		tint = Color("#68e3bf")
	if is_destroyed():
		tint = Color("#ff6b75")
	draw_circle(Vector2.ZERO, contact_radius, Color(tint, 0.08))
	draw_arc(Vector2.ZERO, contact_radius, 0.0, TAU, 24, Color(tint, 0.72), 2.0)
