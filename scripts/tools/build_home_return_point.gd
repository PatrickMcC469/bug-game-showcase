extends SceneTree
## Offline authoring: creates a metre-scale shelter with a front and side escape.
var scene: Area3D
func _initialize() -> void:
	call_deferred("build")
func build() -> void:
	scene = Area3D.new()
	scene.name = "HomeReturnPoint"
	scene.set_script(load("res://scripts/game/home_return_point.gd"))
	scene.collision_layer = 0
	scene.collision_mask = 0
	scene.monitoring = false
	scene.monitorable = false
	var trigger := CollisionShape3D.new()
	trigger.name = "ReturnVolume"
	var volume := CylinderShape3D.new()
	volume.radius = 0.09
	volume.height = 0.06
	trigger.shape = volume
	scene.add_child(trigger)
	trigger.owner = scene
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.19, 0.22, 0.19)
	metal.metallic = 0.65
	metal.roughness = 0.72
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.31, 0.23, 0.12)
	paper.roughness = 0.96
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.035, 0.03, 0.021)
	dark.roughness = 1.0
	# A bent, discarded metal cover shelters the delivery floor; open front and
	# both ends remain traversable. No volume grants immunity from weapon damage.
	box("Canopy", Vector3(0.25, 0.004, 0.15), Vector3(0, 0.071, -0.005), metal, true)
	box("RearFold", Vector3(0.25, 0.071, 0.004), Vector3(0, 0.0355, -0.078), metal, true)
	box("DarkBacking", Vector3(0.23, 0.046, 0.001), Vector3(0, 0.027, -0.075), dark, false)
	box("PaperLining", Vector3(0.19, 0.0006, 0.125), Vector3(0, 0.0006, 0.002), paper, false)
	for x: float in [-0.118, 0.118]:
		box("FoldedFoot" + str(x), Vector3(0.004, 0.066, 0.006), Vector3(x, 0.034, -0.048), metal, true)
	for index: int in 7:
		box("WornRib%d" % index, Vector3(0.002, 0.0008, 0.12), Vector3(-0.102 + index * 0.034, 0.0734, -0.005), metal, false)
	var packed := PackedScene.new()
	packed.pack(scene)
	var error := ResourceSaver.save(packed, "res://scenes/game/props/home_return_point.tscn")
	scene.free()
	print("HOME RETURN BUILD: ", error)
	quit(error)
func box(label: String, size: Vector3, at: Vector3, material: Material, solid: bool) -> void:
	var body := Node3D.new() if not solid else StaticBody3D.new()
	body.name = label.validate_node_name()
	body.position = at
	scene.add_child(body)
	body.owner = scene
	var visual := MeshInstance3D.new()
	visual.name = "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = material
	body.add_child(visual)
	visual.owner = scene
	if solid:
		var collision := CollisionShape3D.new()
		collision.name = "Collision"
		var shape := BoxShape3D.new()
		shape.size = size
		shape.margin = 0.0001
		collision.shape = shape
		body.add_child(collision)
		collision.owner = scene
