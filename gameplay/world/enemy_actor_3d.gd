class_name BastionEnemyActor3D
extends CharacterBody3D

## Physics-backed 3D enemy actor with distinct silhouettes and readable combat feedback.
## The deterministic simulation owns target_progress. This node presents that
## state with smooth movement, hover motion, a health bar and hit flash.

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
var health := 100.0
var max_health := 100.0
var path_curve: Curve3D
var initialized := false
var _visual_kind := ""
var _visual_root: Node3D
var _body_material: StandardMaterial3D
var _eye_material: StandardMaterial3D
var _health_fill: MeshInstance3D
var _hit_flash := 0.0
var _phase := 0.0

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
	_visual_root = Node3D.new()
	_visual_root.name = "EnemyVisual"
	add_child(_visual_root)
	_create_shadow()

func configure(state: Dictionary, curve: Curve3D) -> void:
	enemy_id = str(state.get("id", enemy_id))
	var next_kind := str(state.get("kind", kind))
	if next_kind != _visual_kind:
		kind = next_kind
		_build_visuals()
	target_progress = float(state.get("progress", target_progress))
	damage = maxi(1, int(state.get("damage", damage)))
	speed = float(state.get("speed", speed))
	health = float(state.get("health", state.get("hp", health)))
	max_health = maxf(1.0, float(state.get("max_health", state.get("health_max", max_health))))
	path_curve = curve
	if not initialized:
		path_progress = target_progress
		global_position = _sample_path(path_progress)
		initialized = true
	_update_health_bar()

func _build_visuals() -> void:
	if _visual_root == null:
		return
	for child in _visual_root.get_children():
		child.queue_free()
	_visual_kind = kind
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = _tint()
	_body_material.emission_enabled = true
	_body_material.emission = _tint() * 0.18
	_body_material.emission_energy_multiplier = 0.9
	_eye_material = StandardMaterial3D.new()
	_eye_material.albedo_color = Color("#fff3cc")
	_eye_material.emission_enabled = true
	_eye_material.emission = _tint()
	_eye_material.emission_energy_multiplier = 3.0

	var body := MeshInstance3D.new()
	body.name = "EnemyBody"
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.30 if kind == "scout" else 0.46
	body_mesh.bottom_radius = 0.48 if kind != "boss" else 0.62
	body_mesh.height = 0.70 if kind != "boss" else 0.95
	body_mesh.radial_segments = 10 if kind == "scout" else 14
	body.mesh = body_mesh
	body.position.y = 0.04
	body.material_override = _body_material
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_visual_root.add_child(body)

	var core := MeshInstance3D.new()
	core.name = "EnemyCore"
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.22 if kind != "boss" else 0.30
	core_mesh.height = core_mesh.radius * 2.0
	core_mesh.radial_segments = 12
	core_mesh.rings = 6
	core.mesh = core_mesh
	core.position = Vector3(0.0, 0.12 if kind != "boss" else 0.24, 0.38 if kind == "scout" else 0.32)
	core.material_override = _eye_material
	_visual_root.add_child(core)

	if kind == "scout":
		_add_fin(Vector3(-0.55, 0.08, 0.0), -22.0)
		_add_fin(Vector3(0.55, 0.08, 0.0), 22.0)
		_add_fin(Vector3(0.0, 0.16, -0.52), 0.0)
	elif kind == "bruiser" or kind == "tank":
		_add_armor(Vector3(0.0, 0.28, 0.0), Vector3(0.72, 0.16, 0.72))
		_add_fin(Vector3(-0.50, 0.04, 0.0), -90.0)
		_add_fin(Vector3(0.50, 0.04, 0.0), 90.0)
	elif kind == "boss":
		for side in range(4):
			_add_fin(Vector3(0.0, 0.14, 0.0), float(side) * 90.0, 0.72)
		var crown := MeshInstance3D.new()
		crown.name = "BossCrown"
		var crown_mesh := CylinderMesh.new()
		crown_mesh.top_radius = 0.12
		crown_mesh.bottom_radius = 0.38
		crown_mesh.height = 0.42
		crown.mesh = crown_mesh
		crown.position.y = 0.58
		crown.material_override = _eye_material
		_visual_root.add_child(crown)
	else:
		_add_fin(Vector3(0.0, 0.14, -0.52), 0.0)

	_create_health_bar()
	_create_kind_light()

func _add_fin(position: Vector3, rotation: float, length := 0.48) -> void:
	var fin := MeshInstance3D.new()
	fin.name = "SilhouetteFin"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12, 0.12, length)
	fin.mesh = mesh
	fin.position = position
	fin.rotation_degrees.y = rotation
	fin.material_override = _body_material
	_visual_root.add_child(fin)

func _add_armor(position: Vector3, size: Vector3) -> void:
	var armor := MeshInstance3D.new()
	armor.name = "ArmorPlate"
	var mesh := BoxMesh.new()
	mesh.size = size
	armor.mesh = mesh
	armor.position = position
	armor.material_override = _body_material
	_visual_root.add_child(armor)

func _create_shadow() -> void:
	var shadow := MeshInstance3D.new()
	shadow.name = "EnemyShadow"
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = 0.52
	shadow_mesh.bottom_radius = 0.58
	shadow_mesh.height = 0.025
	shadow.mesh = shadow_mesh
	shadow.position.y = 0.03
	var shadow_material := StandardMaterial3D.new()
	shadow_material.albedo_color = Color("#02070a")
	shadow_material.emission_enabled = true
	shadow_material.emission = Color("#02070a")
	shadow.material_override = shadow_material
	add_child(shadow)

func _create_health_bar() -> void:
	var back := MeshInstance3D.new()
	back.name = "HealthBarBack"
	var back_mesh := BoxMesh.new()
	back_mesh.size = Vector3(0.92, 0.075, 0.045)
	back.mesh = back_mesh
	back.position = Vector3(0.0, 0.88, 0.0)
	back.material_override = _flat_material(Color("#081116"), Color("#081116"))
	_visual_root.add_child(back)
	_health_fill = MeshInstance3D.new()
	_health_fill.name = "HealthBarFill"
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(0.88, 0.052, 0.055)
	_health_fill.mesh = fill_mesh
	_health_fill.position = Vector3(-0.44, 0.88, -0.03)
	_health_fill.material_override = _flat_material(_tint(), _tint() * 0.8)
	_visual_root.add_child(_health_fill)

func _create_kind_light() -> void:
	var light := OmniLight3D.new()
	light.name = "EnemyGlow"
	light.position = Vector3(0.0, 0.24, 0.0)
	light.omni_range = 2.5 if kind != "boss" else 4.0
	light.light_color = _tint()
	light.light_energy = 0.35 if kind != "boss" else 0.8
	_visual_root.add_child(light)

func _flat_material(color: Color, emission: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = 1.1
	return material

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

func _process(delta: float) -> void:
	_phase = fmod(_phase + delta * (2.5 + speed * 0.04), TAU)
	_hit_flash = maxf(0.0, _hit_flash - delta * 4.5)
	if _visual_root == null:
		return
	var bob := sin(_phase) * 0.035
	_visual_root.position.y = bob
	_visual_root.rotation.y = sin(_phase * 0.4) * 0.04
	if _body_material != null:
		_body_material.emission_energy_multiplier = 1.5 if _hit_flash > 0.0 else 0.9

func flash_hit() -> void:
	_hit_flash = 1.0
	if _eye_material != null:
		_eye_material.emission_energy_multiplier = 5.0

func _update_health_bar() -> void:
	if _health_fill == null:
		return
	var ratio := clampf(health / max_health, 0.0, 1.0)
	_health_fill.scale.x = maxf(0.02, ratio)
	_health_fill.position.x = -0.44 * (1.0 - ratio)

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
	if kind == "bruiser" or kind == "tank":
		return Color("#ff9a67")
	if kind == "boss":
		return Color("#ff4f78")
	if kind == "jammer":
		return Color("#c58bff")
	if kind == "carrier":
		return Color("#f0c86b")
	return Color("#ff6b75")