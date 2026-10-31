extends SceneTree
const Detail := preload("res://scripts/tools/diner_detail_geometry.gd")
var pipe_root: Node3D
var iron: StandardMaterial3D
func _initialize() -> void: build.call_deferred()
func build() -> void:
	pipe_root = Node3D.new()
	pipe_root.name = "ExteriorDrainPipe"
	root.add_child(pipe_root)
	iron = StandardMaterial3D.new()
	iron.albedo_color = Color(0.14, 0.17, 0.16)
	iron.roughness = 0.72
	iron.metallic = 0.65
	var mouth := add_mesh("OpenMouth", Detail.lathe([Vector2(0.056, -0.12), Vector2(0.070, -0.12), Vector2(0.070, 0.09), Vector2(0.056, 0.09), Vector2(0.056, -0.12)]), Vector3(0, 0.075, 0))
	mouth.rotation.x = PI / 2
	collide(mouth)
	var rear := add_mesh("ElbowAndStack", Detail.pipe([Vector3(0, 0.075, -0.14), Vector3(0, 0.075, -0.22), Vector3(0, 0.10, -0.27), Vector3(0, 0.16, -0.29), Vector3(0, 0.68, -0.29), Vector3(0, 0.73, -0.34), Vector3(0, 0.73, -0.44)], 0.070), Vector3.ZERO)
	collide(rear)
	for y: float in [0.27, 0.56]:
		var band := add_mesh("PipeClamp", Detail.lathe([Vector2(0.070, -0.015), Vector2(0.078, -0.015), Vector2(0.078, 0.015), Vector2(0.070, 0.015), Vector2(0.070, -0.015)]), Vector3(0, y, -0.29))
		collide(band)
		var plate := add_mesh("WallPlate", Detail.bevel_box(Vector3(0.22, 0.07, 0.014), 0.006), Vector3(0, y, -0.40))
		for x: float in [-0.085, 0.085]:
			var bolt := CylinderMesh.new()
			bolt.top_radius = 0.011
			bolt.bottom_radius = 0.011
			bolt.height = 0.009
			bolt.radial_segments = 6
			var screw := add_mesh("ClampBolt", bolt, Vector3(x, y, -0.387))
			screw.rotation.x = PI / 2
	var control := Marker3D.new()
	add(control, "Control")
	control.position = Vector3(0, 0.027, 0.10)
	var arrival := Marker3D.new()
	add(arrival, "Arrival")
	arrival.position = Vector3(0, 0.002, 0.18)
	arrival.rotation.y = PI
	var packed := PackedScene.new()
	var error := packed.pack(pipe_root)
	if error == OK: error = ResourceSaver.save(packed, "res://scenes/game/props/exterior_drain_pipe.tscn")
	print("DRAIN PIPE BUILD: ", "PASS" if error == OK else error_string(error))
	pipe_root.free()
	quit(0 if error == OK else 1)
func add(node: Node, label: String) -> void:
	node.name = label
	pipe_root.add_child(node, true)
	node.owner = pipe_root
func add_mesh(label: String, mesh: Mesh, at: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	add(node, label)
	node.mesh = mesh
	node.material_override = iron
	node.position = at
	return node
func collide(mesh: MeshInstance3D) -> void:
	var body := StaticBody3D.new()
	add(body, str(mesh.name) + "Body")
	body.transform = mesh.transform
	body.add_to_group("diner_static", true)
	var shape := CollisionShape3D.new()
	shape.shape = mesh.mesh.create_trimesh_shape()
	body.add_child(shape)
	shape.owner = pipe_root
