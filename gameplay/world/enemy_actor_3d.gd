class_name BastionEnemyActor3D
extends CharacterBody3D

## Physics-backed 3D enemy actor.
## The deterministic simulation owns target_progress. This node only smooths the
## presentation toward that target and lets Godot resolve spatial contacts.

signal reached_core(enemy_id: String)
signal moved(enemy_id: String, progress: float, world_position: Vector3)

const ENEMY_COLLISION_LAYER := 2
const MODULE_COLLISION_LAYER := 4

var enemy_id := ""
var kind := ""
var target_progress := 0.0
var path_progress := 0.0
var speed := 0.0
var damage := 1
var hit_radius := 0.42
var path_curve: Curve3D
var initialized := false

func _ready() -> void:
	collision_layer = ENEMY_COLLISION_LAYER
	collision_mask = MODULE_COLLISION_LAYER
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	var shape := CollisionShape3D.new()
	shape.name = "EnemyCollisionShape"
	var sphere := SphereShape3D.new()
	sphere.radius = hit_radius
	shape.shape = sphere
	add_child(shape)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "EnemyMesh"
	var mesh := SphereMesh.new()
	mesh.radius = hit_radius
	mesh.height = hit_radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = _tint()
	material.emission_enabled = true
	material.emission = material.albedo_color * 0.22
	mesh_instance.material_override = material
	add_child(mesh_instance)

func configure(state: Dictionary, curve: Curve3D) -> void:
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

func advance(delta: float) -> void:
	if path_curve == null or path_curve.get_baked_length() <= 0.0:
		return
	var safe_delta := maxf(delta, 0.0001)
	var previous := global_position
	var blend := 1.0 - exp(-safe_delta * 12.0)
	path_progress = lerpf(path_progress, target_progress, clampf(blend, 0.0, 1.0))
	var target_position := _sample_path(path_progress)
	velocity = (target_position - global_position) / safe_delta
	velocity.y = 0.0
	move_and_slide()
	if get_slide_collision_count() == 0:
		global_position = global_position.lerp(target_position, clampf(safe_delta * 8.0, 0.0, 1.0))
	if previous.distance_to(global_position) > 0.001:
		moved.emit(enemy_id, path_progress, global_position)
	if path_progress >= 0.995:
		reached_core.emit(enemy_id)

func get_enemy_id() -> String:
	return enemy_id

func get_path_progress() -> float:
	return path_progress

func _sample_path(progress: float) -> Vector3:
	if path_curve == null:
		return global_position
	var length := path_curve.get_baked_length()
	if length <= 0.0:
		return global_position
	return path_curve.sample_baked(clampf(progress, 0.0, 1.0) * length)

func _tint() -> Color:
	if kind == "scout":
		return Color("#63d9ff")
	if kind == "bruiser":
		return Color("#ff8f6b")
	if kind == "boss":
		return Color("#ff5f7a")
	return Color("#ff6b75")
