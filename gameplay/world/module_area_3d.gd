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
var _core_material: StandardMaterial3D
var _collision_body: StaticBody3D
var _visual_root: Node3D
var _health_fill: MeshInstance3D
var _core_light: OmniLight3D
var _ornament_root: Node3D
var _status_material: StandardMaterial3D
var _pulse := 0.0
var _visual_kind := ""
var _rotation_index := 0

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
	_visual_root = Node3D.new()
	_visual_root.name = "ModuleVisual"
	add_child(_visual_root)

func configure(state: Dictionary, world_position: Vector3) -> void:
	if _collision_body != null:
		_collision_body.collision_layer = MODULE_COLLISION_LAYER
		_collision_body.collision_mask = ENEMY_COLLISION_LAYER
	module_id = str(state.get("id", module_id))
	var next_kind := str(state.get("kind", kind))
	if next_kind != _visual_kind:
		kind = next_kind
		_build_visuals()
	global_position = world_position
	_rotation_index = posmod(int(state.get("rotation", _rotation_index)), 4)
	if _visual_root != null:
		_visual_root.rotation.y = float(_rotation_index) * PI * 0.5
	var grid: Dictionary = state.get("grid", {})
	grid_position = Vector2i(int(grid.get("x", grid_position.x)), int(grid.get("y", grid_position.y)))
	var level := maxi(1, int(state.get("level", 1)))
	var next_max_health := 100 + (level - 1) * 20
	if not _configured:
		max_health = next_max_health
		health = int(state.get("health", max_health))
		_configured = true
	elif max_health != next_max_health:
		var ratio := float(health) / float(maxi(1, max_health))
		max_health = next_max_health
		health = maxi(1, int(round(ratio * float(max_health))))
	if state.has("health"):
		health = clampi(int(state.get("health", health)), 0, max_health)
	_update_health_bar()

func _build_visuals() -> void:
	if _visual_root == null:
		return
	for child in _visual_root.get_children():
		child.queue_free()
	_visual_kind = kind
	var tint := _tint()
	_mesh_material = StandardMaterial3D.new()
	_mesh_material.albedo_color = tint
	_mesh_material.roughness = 0.38
	_mesh_material.metallic = 0.32
	_mesh_material.emission_enabled = true
	_mesh_material.emission = tint * 0.16
	_mesh_material.emission_energy_multiplier = 1.0
	_core_material = StandardMaterial3D.new()
	_core_material.albedo_color = Color("#fff0b8")
	_core_material.roughness = 0.22
	_core_material.metallic = 0.12
	_core_material.emission_enabled = true
	_core_material.emission = tint
	_core_material.emission_energy_multiplier = 2.4
	_status_material = _flat_material(tint, tint)

	var base := MeshInstance3D.new()
	base.name = "ModuleBase"
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.60
	base_mesh.bottom_radius = 0.70
	base_mesh.height = 0.22
	base_mesh.radial_segments = 18
	base.mesh = base_mesh
	base.position.y = -0.30
	base.material_override = _mesh_material
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_visual_root.add_child(base)

	var deck := MeshInstance3D.new()
	deck.name = "ModuleDeck"
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(0.86, 0.10, 0.86)
	deck.mesh = deck_mesh
	deck.position.y = -0.14
	deck.material_override = _mesh_material
	_visual_root.add_child(deck)

	var core := MeshInstance3D.new()
	core.name = "ModuleCore"
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.26 if kind != "pulse_cannon" else 0.30
	core_mesh.height = core_mesh.radius * 2.0
	core_mesh.radial_segments = 14
	core_mesh.rings = 8
	core.mesh = core_mesh
	core.position.y = 0.20
	core.scale = Vector3(1.0, 1.15, 1.0)
	core.material_override = _core_material
	_visual_root.add_child(core)

	_ornament_root = Node3D.new()
	_ornament_root.name = "ModuleOrnaments"
	_visual_root.add_child(_ornament_root)
	_add_kind_geometry(tint)

	var stem := MeshInstance3D.new()
	stem.name = "ModuleStem"
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.10
	stem_mesh.bottom_radius = 0.16
	stem_mesh.height = 0.46
	stem.mesh = stem_mesh
	stem.position.y = -0.02
	stem.material_override = _mesh_material
	_visual_root.add_child(stem)

	for side in range(4):
		var port := MeshInstance3D.new()
		port.name = "Port_%d" % side
		var port_mesh := BoxMesh.new()
		port_mesh.size = Vector3(0.12, 0.10, 0.30)
		port.mesh = port_mesh
		var angle := float(side) * PI * 0.5
		port.position = Vector3(sin(angle) * 0.50, -0.10, cos(angle) * 0.50)
		port.rotation.y = angle
		port.material_override = _core_material
		_visual_root.add_child(port)

	for side in range(4):
		var corner := MeshInstance3D.new()
		corner.name = "StatusCorner_%d" % side
		var corner_mesh := BoxMesh.new()
		corner_mesh.size = Vector3(0.08, 0.06, 0.26)
		corner.mesh = corner_mesh
		var angle := float(side) * PI * 0.5 + PI * 0.25
		corner.position = Vector3(sin(angle) * 0.68, -0.20, cos(angle) * 0.68)
		corner.rotation.y = angle
		corner.material_override = _core_material
		_visual_root.add_child(corner)

	_create_health_bar()
	_core_light = OmniLight3D.new()
	_core_light.name = "ModuleGlow"
	_core_light.position = Vector3(0.0, 0.20, 0.0)
	_core_light.omni_range = 2.6
	_core_light.light_color = tint
	_core_light.light_energy = 0.7
	_visual_root.add_child(_core_light)

func _add_kind_geometry(tint: Color) -> void:
	## Give each module a silhouette that communicates its role at a glance.
	## These are intentionally low-poly primitives so the Android GL renderer
	## does not need texture imports or shader variants.
	if _ornament_root == null:
		return
	match kind:
		"scanner":
			var dish := MeshInstance3D.new()
			dish.name = "ScannerDish"
			var dish_mesh := CylinderMesh.new()
			dish_mesh.top_radius = 0.34
			dish_mesh.bottom_radius = 0.12
			dish_mesh.height = 0.10
			dish_mesh.radial_segments = 12
			dish.mesh = dish_mesh
			dish.position = Vector3(0.0, 0.45, 0.0)
			dish.rotation_degrees.x = -18.0
			dish.material_override = _core_material
			_ornament_root.add_child(dish)
			_add_pole(Vector3(0.0, 0.34, 0.0), 0.32, _mesh_material)
			_add_arc_ring("ScannerRing", 0.55, 0.43, 0.07, _status_material)
		"router":
			_add_hub_arms(tint)
			_add_arc_ring("RouterRing", 0.62, 0.55, 0.055, _core_material)
		"pulse_cannon", "railgun":
			var barrel := MeshInstance3D.new()
			barrel.name = "CannonBarrel"
			var barrel_mesh := BoxMesh.new()
			barrel_mesh.size = Vector3(0.18, 0.18, 0.82)
			barrel.mesh = barrel_mesh
			barrel.position = Vector3(0.0, 0.18, 0.42)
			barrel.material_override = _mesh_material
			_ornament_root.add_child(barrel)
			var muzzle := MeshInstance3D.new()
			muzzle.name = "CannonMuzzle"
			var muzzle_mesh := CylinderMesh.new()
			muzzle_mesh.top_radius = 0.18
			muzzle_mesh.bottom_radius = 0.22
			muzzle_mesh.height = 0.10
			muzzle_mesh.radial_segments = 10
			muzzle.mesh = muzzle_mesh
			muzzle.position = Vector3(0.0, 0.18, 0.84)
			muzzle.rotation_degrees.x = 90.0
			muzzle.material_override = _core_material
			_ornament_root.add_child(muzzle)
			_add_arc_ring("CannonRing", 0.48, 0.40, 0.07, _status_material)
		"heat_sink", "repair_arm":
			for index in range(3):
				var fin := MeshInstance3D.new()
				fin.name = "CoolingFin_%d" % index
				var fin_mesh := BoxMesh.new()
				fin_mesh.size = Vector3(0.10, 0.46, 0.62)
				fin.mesh = fin_mesh
				fin.position = Vector3(-0.26 + float(index) * 0.26, 0.12, 0.0)
				fin.material_override = _mesh_material
				_ornament_root.add_child(fin)
			_add_arc_ring("HeatRing", 0.68, 0.58, 0.055, _status_material)
		"capacitor", "battery":
			for index in range(2):
				var cell := MeshInstance3D.new()
				cell.name = "CapacitorCell_%d" % index
				var cell_mesh := CylinderMesh.new()
				cell_mesh.top_radius = 0.14
				cell_mesh.bottom_radius = 0.17
				cell_mesh.height = 0.54
				cell_mesh.radial_segments = 10
				cell.mesh = cell_mesh
				cell.position = Vector3(-0.20 + float(index) * 0.40, 0.08, 0.0)
				cell.material_override = _mesh_material
				_ornament_root.add_child(cell)
			_add_arc_ring("ChargeRing", 0.62, 0.54, 0.05, _core_material)
		"slow_field":
			_add_arc_ring("FieldRing", 0.72, 0.62, 0.06, _core_material)
			_add_arc_ring("FieldRingInner", 0.48, 0.40, 0.04, _status_material)
		_:
			_add_pole(Vector3(0.0, 0.32, 0.0), 0.28, _mesh_material)

func _add_pole(base: Vector3, height: float, material: Material) -> void:
	var pole := MeshInstance3D.new()
	pole.name = "ModulePole"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.06
	mesh.bottom_radius = 0.10
	mesh.height = height
	mesh.radial_segments = 8
	pole.mesh = mesh
	pole.position = base + Vector3(0.0, height * 0.5, 0.0)
	pole.material_override = material
	_ornament_root.add_child(pole)

func _add_hub_arms(tint: Color) -> void:
	for side in range(4):
		var arm := MeshInstance3D.new()
		arm.name = "RouterArm_%d" % side
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.10, 0.10, 0.62)
		arm.mesh = mesh
		var angle := float(side) * PI * 0.5
		arm.position = Vector3(sin(angle) * 0.28, 0.16, cos(angle) * 0.28)
		arm.rotation.y = angle
		arm.material_override = _mesh_material
		_ornament_root.add_child(arm)
		var node := MeshInstance3D.new()
		node.name = "RouterNode_%d" % side
		var node_mesh := SphereMesh.new()
		node_mesh.radius = 0.10
		node_mesh.height = 0.20
		node.mesh = node_mesh
		node.position = Vector3(sin(angle) * 0.60, 0.18, cos(angle) * 0.60)
		node.material_override = _core_material
		_ornament_root.add_child(node)

func _add_arc_ring(node_name: String, outer_radius: float, inner_radius: float, height: float, material: Material) -> void:
	var ring := MeshInstance3D.new()
	ring.name = node_name
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = outer_radius
	mesh.rings = 12
	mesh.ring_segments = 6
	ring.mesh = mesh
	ring.position.y = height
	ring.material_override = material
	_ornament_root.add_child(ring)

func _create_health_bar() -> void:
	var back := MeshInstance3D.new()
	back.name = "HealthBarBack"
	var back_mesh := BoxMesh.new()
	back_mesh.size = Vector3(0.92, 0.06, 0.045)
	back.mesh = back_mesh
	back.position = Vector3(0.0, 0.70, 0.0)
	back.material_override = _flat_material(Color("#071016"), Color("#071016"))
	_visual_root.add_child(back)
	_health_fill = MeshInstance3D.new()
	_health_fill.name = "HealthBarFill"
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(0.88, 0.042, 0.055)
	_health_fill.mesh = fill_mesh
	_health_fill.position = Vector3(-0.44, 0.70, -0.03)
	_health_fill.material_override = _flat_material(_tint(), _tint())
	_visual_root.add_child(_health_fill)

func _flat_material(color: Color, emission: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.34
	material.metallic = 0.16
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = 1.2
	return material

func _process(delta: float) -> void:
	_pulse = fmod(_pulse + delta * 2.4, TAU)
	if _visual_root == null:
		return
	var breathe := 1.0 + sin(_pulse) * 0.035
	var core := _visual_root.get_node_or_null("ModuleCore")
	if core != null:
		core.scale = Vector3(breathe, 1.15 * breathe, breathe)
	if _core_light != null:
		_core_light.light_energy = 0.62 + (sin(_pulse) + 1.0) * 0.12
	if _ornament_root != null:
		_ornament_root.rotation.y = _pulse * (0.18 if kind in ["router", "slow_field"] else 0.08)
	if _core_material != null and _core_material.emission_energy_multiplier > 2.5:
		_core_material.emission_energy_multiplier = maxf(2.4, _core_material.emission_energy_multiplier - delta * 8.0)

func receive_hit(attacker_id: String, damage: int) -> void:
	var applied := maxi(0, damage)
	if applied == 0 or health <= 0:
		return
	health = maxi(0, health - applied)
	_pulse = 0.0
	if _core_material != null:
		_core_material.emission_energy_multiplier = 5.0
	if health <= 0 and _collision_body != null:
		_collision_body.collision_layer = 0
		_collision_body.collision_mask = 0
	hit_received.emit(module_id, attacker_id, applied, health)
	_update_health_bar()

func is_destroyed() -> bool:
	return health <= 0

func get_health_ratio() -> float:
	return float(health) / float(maxi(1, max_health))

func get_module_id() -> String:
	return module_id

func _update_health_bar() -> void:
	if _health_fill == null:
		return
	var ratio := get_health_ratio()
	_health_fill.scale.x = maxf(0.02, ratio)
	_health_fill.position.x = -0.44 * (1.0 - ratio)

func _tint() -> Color:
	if kind == "pulse_cannon" or kind == "railgun":
		return Color("#ffca62")
	if kind == "router" or kind == "scanner":
		return Color("#b690ff")
	if kind == "heat_sink" or kind == "repair_arm":
		return Color("#68e3bf")
	if kind == "capacitor" or kind == "battery":
		return Color("#82aaff")
	if kind == "slow_field":
		return Color("#dc7dff")
	return Color("#72d7ff")
