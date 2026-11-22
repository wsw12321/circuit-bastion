class_name BastionModuleArea3D
extends Area3D

## Deployable module collider for the 3D world.
## Area3D overlap detection is used for contacts while the deterministic
## simulation remains the authority for health and combat outcomes.

signal hit_received(module_id: String, attacker_id: String, damage: int, remaining_health: int)

const MODULE_COLLISION_LAYER := 4
const ENEMY_COLLISION_LAYER := 2

var module_id := ""
var kind := ""
var grid_position := Vector2i(-1, -1)
var max_health := 100
var health := 100
var contact_radius := 0.62
var _configured := false
var _mesh_material: StandardMaterial3D
var _collision_body: StaticBody3D

func _ready() -> void:
	collision_layer = MODULE_COLLISION_LAYER
	collision_mask = ENEMY_COLLISION_LAYER
	monitoring = true
	monitorable = true
	var shape := CollisionShape3D.new()
	shape.name = "ModuleCollisionShape"
	var sphere := SphereShape3D.new()
	sphere.radius = contact_radius
	shape.shape = sphere
	add_child(shape)
	var blocker := StaticBody3D.new()
	blocker.name = "ModuleCollisionBody"
	blocker.collision_layer = MODULE_COLLISION_LAYER
	blocker.collision_mask = ENEMY_COLLISION_LAYER
	_collision_body = blocker
	var blocker_shape := CollisionShape3D.new()
	var blocker_sphere := SphereShape3D.new()
	blocker_sphere.radius = contact_radius
	blocker_shape.shape = blocker_sphere
	blocker.add_child(blocker_shape)
	add_child(blocker)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "ModuleMesh"
	var mesh := CylinderMesh.new()
	mesh.top_radius = contact_radius * 0.82
	mesh.bottom_radius = contact_radius
	mesh.height = 0.18
	mesh.radial_segments = 16
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = _tint()
	material.emission_enabled = true
	material.emission = material.albedo_color * 0.16
	_mesh_material = material
	mesh_instance.material_override = material
	add_child(mesh_instance)

func configure(state: Dictionary, world_position: Vector3) -> void:
	if _collision_body != null:
		_collision_body.collision_layer = MODULE_COLLISION_LAYER
		_collision_body.collision_mask = ENEMY_COLLISION_LAYER
	module_id = str(state.get("id", module_id))
	kind = str(state.get("kind", kind))
	if _mesh_material != null:
		_mesh_material.albedo_color = _tint()
		_mesh_material.emission = _mesh_material.albedo_color * 0.16
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

func receive_hit(attacker_id: String, damage: int) -> void:
	var applied := maxi(0, damage)
	if applied == 0 or health <= 0:
		return
	health = maxi(0, health - applied)
	if health <= 0 and _collision_body != null:
		_collision_body.collision_layer = 0
		_collision_body.collision_mask = 0
	hit_received.emit(module_id, attacker_id, applied, health)

func is_destroyed() -> bool:
	return health <= 0

func get_health_ratio() -> float:
	return float(health) / float(maxi(1, max_health))

func get_module_id() -> String:
	return module_id

func _tint() -> Color:
	if kind == "pulse_cannon":
		return Color("#ffca62")
	if kind == "router":
		return Color("#b690ff")
	if kind == "heat_sink":
		return Color("#68e3bf")
	return Color("#72d7ff")
