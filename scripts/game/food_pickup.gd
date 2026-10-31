extends Area3D
## Cosmetic food presentation and scent highlights only. FoodRun owns possession and collision travel.
const RoachScale := preload("res://scripts/game/roach_scale.gd")
const Catalog := preload("res://scripts/game/food_catalog.gd")
const SURFACE := preload("res://assets/shaders/food_surface.gdshader")
@export_range(0, 3) var food_kind := 0
var _visual: Node3D
var _ring: MeshInstance3D

func _ready() -> void:
	scale = Vector3.ONE * RoachScale.GEOMETRY
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false
	for child: Node in get_children():
		if child is MeshInstance3D or child is CollisionShape3D:
			child.queue_free()
	_visual = Node3D.new()
	add_child(_visual)
	_build_food()
	_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.66
	ring_mesh.outer_radius = 0.69
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 8
	_ring.mesh = ring_mesh
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = Color(0.95, 0.75, 0.35)
	_ring.material_override = ring_material
	_ring.position.y = -float(Catalog.info(food_kind)["radius"]) / RoachScale.GEOMETRY + 0.02
	add_child(_ring)
	set_hint(false, false)

func set_hint(focused: bool, scent: bool) -> void:
	if _ring == null: return
	_ring.visible = focused or scent
	(_ring.material_override as StandardMaterial3D).no_depth_test = scent

func present(target: Vector3, angles: Vector3, carried: bool, delta: float) -> void:
	# Smoothing belongs to visuals; host gameplay always uses its own position.
	global_position = global_position.lerp(target, 1.0 - exp(-24.0 * delta))
	_visual.rotation = angles
	_ring.visible = _ring.visible and not carried

func _material(color: Color, roughness: float = 0.65, grain: float = 0.18) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SURFACE
	material.set_shader_parameter("tint", color)
	material.set_shader_parameter("roughness", roughness)
	material.set_shader_parameter("grain", grain)
	return material

func _mesh(mesh: Mesh, material: Material, at: Vector3 = Vector3.ZERO, size: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.scale = size
	_visual.add_child(instance)
	return instance

func _build_food() -> void:
	var color: Color = Catalog.info(food_kind)["color"]
	match food_kind:
		0:
			var cube := BoxMesh.new()
			cube.size = Vector3(0.5, 0.48, 0.5)
			_mesh(cube, _material(color, 0.88, 0.35))
			var crystal := SphereMesh.new()
			crystal.radius = 0.035
			crystal.height = 0.06
			crystal.radial_segments = 6
			crystal.rings = 3
			var crystal_material := _material(Color(1.0, 0.98, 0.9), 0.28)
			for index: int in 12:
				_mesh(crystal, crystal_material, Vector3(sin(index * 13.3) * 0.2, 0.24, cos(index * 8.1) * 0.2))
		1:
			var pea := SphereMesh.new()
			pea.radius = 0.32
			pea.height = 0.62
			pea.radial_segments = 28
			pea.rings = 16
			_mesh(pea, _material(color, 0.43, 0.13))
			_mesh(pea, _material(color.darkened(0.25)), Vector3(0.0, 0.30, 0.0), Vector3(0.18, 0.045, 0.18))
		2:
			var wedge := PrismMesh.new()
			wedge.size = Vector3(0.95, 0.56, 0.75)
			_mesh(wedge, _material(color, 0.56, 0.07))
			var hole := SphereMesh.new()
			hole.radius = 0.10
			hole.height = 0.2
			hole.radial_segments = 16
			hole.rings = 8
			var hole_material := _material(Color(0.48, 0.23, 0.035), 0.9)
			for index: int in 4:
				_mesh(hole, hole_material, Vector3(-0.23 + index * 0.15, -0.15 + (index % 2) * 0.12, 0.376), Vector3(0.7, 0.7, 0.08))
		3:
			var dough := TorusMesh.new()
			dough.inner_radius = 0.24
			dough.outer_radius = 0.72
			dough.rings = 40
			dough.ring_segments = 16
			_mesh(dough, _material(Color(0.66, 0.32, 0.09), 0.73, 0.23))
			_mesh(dough, _material(color, 0.28, 0.035), Vector3(0.0, 0.105, 0.0), Vector3(0.98, 0.58, 0.98))
			var sprinkle := CapsuleMesh.new()
			sprinkle.radius = 0.017
			sprinkle.height = 0.09
			sprinkle.radial_segments = 6
			sprinkle.rings = 2
			for index: int in 24:
				var angle := float(index) * TAU / 24.0
				var radius := 0.45 + sin(index * 4.5) * 0.09
				var icing_color := Color(0.94, 0.76, 0.28) if index % 2 == 0 else Color(0.88, 0.77, 0.68)
				var instance := _mesh(sprinkle, _material(icing_color), Vector3(cos(angle) * radius, 0.235, sin(angle) * radius))
				instance.rotation = Vector3(PI * 0.5, angle * 2.7, 0.0)
