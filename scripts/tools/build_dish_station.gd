extends SceneTree
## Offline static art authoring. The hood, controls and spray stay separate for
## future interaction work; this pass adds no water, damage or appliance logic.
const Detail := preload("res://scripts/tools/diner_detail_geometry.gd")
const SCENE := "res://scenes/game/props/commercial_dish_station.tscn"
var station: Node3D
var materials: Dictionary = {}

func _initialize() -> void: build.call_deferred()
func build() -> void:
	station = Node3D.new()
	station.name = "CommercialDishStation"
	root.add_child(station)
	var steel := ShaderMaterial.new()
	steel.shader = load("res://assets/shaders/diner_brushed_metal.gdshader")
	steel.set_shader_parameter("tint", Color(0.62, 0.65, 0.64))
	steel.set_shader_parameter("base_roughness", 0.36)
	materials.steel = steel
	materials.dark = material(Color(0.055, 0.065, 0.063), 0.62, 0.35)
	materials.rubber = material(Color(0.023, 0.028, 0.026), 0.89)
	materials.plastic = material(Color(0.16, 0.24, 0.22), 0.73)
	materials.cream = material(Color(0.76, 0.73, 0.60), 0.68)
	materials.ceramic = material(Color(0.86, 0.84, 0.76), 0.22)
	materials.red = material(Color(0.42, 0.065, 0.04), 0.57)
	materials.blue = material(Color(0.04, 0.16, 0.27), 0.6)
	materials.soap = material(Color(0.62, 0.68, 0.52), 0.48)
	var sink := group(station, "SinkCounter")
	# Worktop at the existing 1.08m height. Open bowl voids, not painted holes.
	for segment: Vector2 in [Vector2(-2.20, -1.09), Vector2(-0.43, -0.34), Vector2(0.32, 0.48)]:
		box(sink, "Deck", Vector3((segment.x + segment.y) / 2, 1.055, 0), Vector3(segment.y - segment.x, 0.05, 0.95), "steel")
	for z: float in [-0.40, 0.40]:
		box(sink, "RimRail", Vector3(-0.385, 1.055, z), Vector3(1.59, 0.05, 0.15), "steel")
	box(sink, "RolledFront", Vector3(-0.86, 1.035, 0.47), Vector3(2.68, 0.075, 0.025), "steel")
	box(sink, "Splashback", Vector3(-0.86, 1.22, -0.472), Vector3(2.68, 0.30, 0.024), "steel")
	pipe(sink, "SplashCap", [Vector3(-2.19, 1.377, -0.47), Vector3(0.46, 1.377, -0.47)], 0.014, "steel")
	for x: float in [-2.06, -0.10]:
		for z: float in [-0.36, 0.36]: leg(sink, Vector3(x, 0, z), 1.02)
	pipe(sink, "RearBrace", [Vector3(-2.06, 0.25, -0.36), Vector3(-0.10, 0.25, -0.36)], 0.018, "steel")
	for x: float in [-0.76, -0.01]: basin(sink, x)
	for index: int in 12:
		pipe(sink, "DirtyDrainRib", [Vector3(-2.11 + index * 0.077, 1.084, -0.34), Vector3(-2.11 + index * 0.077, 1.084, 0.34)], 0.0035, "steel")
	faucet(group(station, "RinseFaucet"), -0.76)
	faucet(group(station, "RinseTap"), -0.01, false)
	washer()
	var clean := group(station, "CleanDrainboard")
	box(clean, "Deck", Vector3(1.79, 1.055, 0), Vector3(0.86, 0.05, 0.95), "steel")
	box(clean, "Backsplash", Vector3(1.79, 1.20, -0.47), Vector3(0.86, 0.24, 0.024), "steel")
	for z: float in [-0.36, 0.36]: leg(clean, Vector3(2.10, 0, z), 1.02)
	for index: int in 10:
		pipe(clean, "DrainRib", [Vector3(1.43 + index * 0.077, 1.084, -0.35), Vector3(1.43 + index * 0.077, 1.084, 0.35)], 0.0035, "steel")
	rack(group(station, "CleanDishRack"), Vector3(1.78, 1.094, 0), true)
	rack(group(station, "DirtyDishRack"), Vector3(-1.67, 1.094, 0.02), false)
	wall_shelf()
	# The machine is raised, with bottles against the sink's rear rather than across
	# the low passage. Hoses are solid where a bug can actually reach them.
	var plumbing := group(station, "ServicePlumbing")
	pipe(plumbing, "WasteManifold", [Vector3(-0.76, 0.56, -0.36), Vector3(1.16, 0.56, -0.36), Vector3(1.16, 0.25, -0.52)], 0.021, "dark", true)
	pipe(plumbing, "FillHose", [Vector3(0.96, 0.42, -0.45), Vector3(0.96, 0.27, -0.49), Vector3(0.50, 0.22, -0.49), Vector3(0.38, 0.55, -0.49)], 0.012, "rubber", true)
	bottle(plumbing, Vector3(-1.72, 0.001, -0.27), "soap")
	bottle(plumbing, Vector3(-1.46, 0.001, -0.27), "blue")
	# Short return ties the wash line into the existing perpendicular dish table.
	var link := group(station, "ReturnTable")
	box(link, "Top", Vector3(2.85, 1.055, 0), Vector3(1.26, 0.05, 0.95), "steel")
	for z: float in [-0.36, 0.36]: leg(link, Vector3(3.32, 0, z), 1.02)
	pipe(link, "RearLip", [Vector3(2.22, 1.10, -0.47), Vector3(3.48, 1.10, -0.47)], 0.016, "steel")
	for assembly: Node3D in station.get_children(): batch(assembly)
	var drain := group(station, "DrainEntrance")
	drain.position = Vector3(-0.76, 0.785, -0.08)
	var control := Marker3D.new()
	add(drain, control, "Control")
	control.position.y = 0.015
	var arrival := Marker3D.new()
	add(drain, arrival, "Arrival")
	arrival.position = Vector3(0, 0.002, 0.085)
	arrival.rotation.y = PI
	# Keep the production marker scene intact; its script sizes named meshes.
	var climbs := group(station, "ClimbPoints")
	for entry: Array in [["DirtyDrainboard", -2.10, "Dirty drainboard"], ["SinkRim", -0.385, "Sink rim"], ["CleanReturn", 3.12, "Clean dish return"]]:
		var spot: Node3D = load("res://scenes/game/props/roach_climb_spot.tscn").instantiate()
		spot.height = 1.08
		spot.destination_name = entry[2]
		spot.position = Vector3(entry[1], 0, 0.55)
		add(climbs, spot, entry[0])
	var packed := PackedScene.new()
	var error := packed.pack(station)
	if error == OK: error = ResourceSaver.save(packed, SCENE)
	print("DISH STATION BUILD: ", "PASS" if error == OK else error_string(error))
	station.free()
	quit(0 if error == OK else 1)

func basin(parent: Node3D, x: float) -> void:
	var bowl := group(parent, "Basin")
	box(bowl, "Bottom", Vector3(x, 0.775, 0), Vector3(0.66, 0.02, 0.65), "steel")
	for sign: float in [-1, 1]:
		box(bowl, "Side", Vector3(x + sign * 0.327, 0.93, 0), Vector3(0.014, 0.29, 0.65), "steel")
		box(bowl, "End", Vector3(x, 0.93, sign * 0.318), Vector3(0.66, 0.29, 0.014), "steel")
		pipe(bowl, "RolledRim", [Vector3(x - 0.32, 1.079, sign * 0.32), Vector3(x + 0.32, 1.079, sign * 0.32)], 0.007, "steel")
	if x < -0.5:
		# An open dark throat and displaced strainer distinguish the usable drain.
		cylinder(bowl, "OpenDrain", Vector3(x, 0.790, -0.08), 0.048, 0.002, "rubber")
		visual(bowl, "DrainLip", Detail.lathe([Vector2(0.042, 0), Vector2(0.051, 0), Vector2(0.051, 0.006), Vector2(0.042, 0.006), Vector2(0.042, 0)]), Vector3(x, 0.789, -0.08), "steel")
		var cap := cylinder(bowl, "LooseStrainer", Vector3(x + 0.115, 0.803, -0.08), 0.040, 0.005, "steel")
		cap.rotation.z = -0.30
	else:
		cylinder(bowl, "DrainFlange", Vector3(x, 0.790, -0.08), 0.050, 0.004, "dark")
	if x >= -0.5:
		cylinder(bowl, "DrainCentre", Vector3(x, 0.793, -0.08), 0.038, 0.004, "steel")
		for index: int in 12:
			var a := TAU * index / 12
			cylinder(bowl, "StrainerHole", Vector3(x + cos(a) * 0.024, 0.7955, -0.08 + sin(a) * 0.024), 0.004, 0.001, "rubber")
	pipe(bowl, "WasteTail", [Vector3(x, 0.76, -0.08), Vector3(x, 0.48, -0.08)], 0.024, "dark", true)
	var trap: Array[Vector3] = []
	for index: int in 17:
		var a := PI * index / 16
		trap.append(Vector3(x, 0.48 - sin(a) * 0.09, -0.17 + cos(a) * 0.09))
	trap.append(Vector3(x, 0.56, -0.26))
	trap.append(Vector3(x, 0.56, -0.36))
	pipe(bowl, "PTrap", trap, 0.024, "dark", true)
	for y: float in [0.57, 0.73]: cylinder(bowl, "SlipNut", Vector3(x, y, -0.08), 0.032, 0.028, "steel")

func faucet(parent: Node3D, x: float, spray: bool = true) -> void:
	for side: float in [-1, 1]:
		cylinder(parent, "MixerFoot", Vector3(x + side * 0.115, 1.09, -0.39), 0.035, 0.025, "steel")
		cylinder(parent, "Valve", Vector3(x + side * 0.115, 1.13, -0.39), 0.024, 0.055, "steel")
		pipe(parent, "ValveHandle", [Vector3(x + side * 0.115, 1.165, -0.39), Vector3(x + side * 0.18, 1.165, -0.34)], 0.012, "blue" if side > 0 else "red")
	pipe(parent, "Mixer", [Vector3(x - 0.115, 1.12, -0.39), Vector3(x + 0.115, 1.12, -0.39)], 0.022, "steel")
	var arc: Array[Vector3] = [Vector3(x, 1.12, -0.39), Vector3(x, 1.35, -0.39)]
	for index: int in 25:
		var a := PI * index / 24
		arc.append(Vector3(x, 1.35 + sin(a) * 0.15, -0.24 - cos(a) * 0.15))
	arc.append(Vector3(x, 1.31, -0.09))
	pipe(parent, "Spout", arc, 0.017, "steel")
	cylinder(parent, "Aerator", Vector3(x, 1.31, -0.09), 0.024, 0.036, "dark")
	if not spray: return
	pipe(parent, "Riser", [Vector3(x, 1.12, -0.43), Vector3(x, 1.77, -0.43)], 0.016, "steel")
	pipe(parent, "WallBrace", [Vector3(x, 1.62, -0.43), Vector3(x, 1.62, -0.57)], 0.012, "steel")
	var hose: Array[Vector3] = []
	for index: int in 45:
		var a := PI * index / 44
		hose.append(Vector3(x, 1.77 + sin(a) * 0.24, -0.21 - cos(a) * 0.22))
	hose.append(Vector3(x, 1.55, 0.01))
	pipe(parent, "FlexibleHose", hose, 0.013, "rubber")
	var spring: Array[Vector3] = []
	for index: int in 361:
		var t := index / 360.0
		var a := t * PI
		var center := Vector3(x, 1.77 + sin(a) * 0.24, -0.21 - cos(a) * 0.22)
		var normal := Vector3(0, sin(a), -cos(a))
		spring.append(center + Vector3.RIGHT * cos(t * TAU * 22) * 0.024 + normal * sin(t * TAU * 22) * 0.024)
	pipe(parent, "SpringGuard", spring, 0.003, "steel")
	cylinder(parent, "SprayGrip", Vector3(x, 1.49, 0.01), 0.024, 0.14, "rubber")
	box(parent, "Trigger", Vector3(x, 1.48, 0.035), Vector3(0.016, 0.095, 0.010), "steel", false)
	cylinder(parent, "SprayRose", Vector3(x, 1.40, 0.01), 0.035, 0.035, "steel")
	cylinder(parent, "SprayFace", Vector3(x, 1.381, 0.01), 0.029, 0.002, "dark")

func washer() -> void:
	var body := group(station, "DishwasherBase")
	box(body, "LowerCabinet", Vector3(0.92, 0.635, 0), Vector3(0.84, 0.87, 0.86), "steel")
	for x: float in [0.60, 1.24]:
		for z: float in [-0.31, 0.31]: leg(body, Vector3(x, 0, z), 0.19)
	box(body, "ServicePanel", Vector3(0.92, 0.66, 0.436), Vector3(0.74, 0.66, 0.013), "steel", false)
	for index: int in 7:
		box(body, "VentSlot", Vector3(0.92, 0.29 + index * 0.020, 0.444), Vector3(0.43, 0.006, 0.001), "dark", false)
	for x: float in [0.59, 1.25]:
		for y: float in [0.38, 0.91]:
			var screw := cylinder(body, "PanelScrew", Vector3(x, y, 0.446), 0.006, 0.003, "dark")
			screw.rotation.x = PI / 2
	var hood := group(station, "DishwasherHood")
	box(hood, "WashChamber", Vector3(0.92, 1.35, 0), Vector3(0.82, 0.55, 0.86), "steel")
	box(hood, "DoorSeal", Vector3(0.92, 1.078, 0), Vector3(0.85, 0.018, 0.89), "dark", false)
	box(hood, "FoldedLid", Vector3(0.92, 1.64, 0), Vector3(0.88, 0.035, 0.92), "steel")
	for x: float in [0.46, 1.38]:
		pipe(hood, "LiftArm", [Vector3(x, 1.11, -0.22), Vector3(x, 1.38, 0.22), Vector3(x, 1.38, 0.57)], 0.021, "steel")
	pipe(hood, "LiftHandle", [Vector3(0.46, 1.38, 0.57), Vector3(1.38, 1.38, 0.57)], 0.023, "dark")
	var controls := group(station, "DishwasherControls")
	box(controls, "ControlFascia", Vector3(0.92, 1.55, 0.445), Vector3(0.72, 0.10, 0.018), "dark", false)
	box(controls, "TemperatureWindow", Vector3(0.74, 1.55, 0.456), Vector3(0.19, 0.054, 0.004), "rubber", false)
	for x: float in [1.01, 1.14]:
		var button := cylinder(controls, "PushButton", Vector3(x, 1.55, 0.46), 0.020, 0.010, "plastic" if x < 1.1 else "red")
		button.rotation.x = PI / 2
	box(controls, "MakerPlate", Vector3(0.92, 0.88, 0.445), Vector3(0.15, 0.052, 0.003), "dark", false)

func rack(parent: Node3D, at: Vector3, loaded: bool) -> void:
	for x: float in [-0.30, 0.30]: box(parent, "Side", at + Vector3(x, 0.065, 0), Vector3(0.018, 0.13, 0.60), "plastic")
	for z: float in [-0.30, 0.30]: box(parent, "End", at + Vector3(0, 0.065, z), Vector3(0.60, 0.13, 0.018), "plastic")
	for index: int in 12:
		box(parent, "GridX", at + Vector3(-0.275 + index * 0.05, 0.009, 0), Vector3(0.009, 0.018, 0.58), "plastic", false)
		box(parent, "GridZ", at + Vector3(0, 0.009, -0.275 + index * 0.05), Vector3(0.58, 0.018, 0.009), "plastic", false)
	box(parent, "RackFloor", at + Vector3(0, 0.002, 0), Vector3(0.60, 0.003, 0.60), "plastic", true, false)
	for row: int in 8:
		for z: float in [-0.19, 0.19]: pipe(parent, "PlatePeg", [at + Vector3(-0.24 + row * 0.068, 0.02, z), at + Vector3(-0.24 + row * 0.068, 0.17, z)], 0.007, "plastic")
	if loaded:
		for index: int in 5:
			var plate := visual(parent, "CleanPlate", Detail.lathe([Vector2(0, 0.004), Vector2(0.07, 0.004), Vector2(0.10, 0.012), Vector2(0.13, 0.029), Vector2(0.136, 0.027), Vector2(0.134, 0.020), Vector2(0.10, 0.003), Vector2(0.07, -0.004), Vector2(0, -0.004)]), at + Vector3(-0.19 + index * 0.068, 0.15, 0), "ceramic")
			plate.rotation.z = PI / 2 - 0.08
			mesh_collision(parent, plate)
	else:
		for index: int in 3:
			var mug := visual(parent, "Mug", Detail.lathe([Vector2(0.032, 0), Vector2(0.043, 0.095), Vector2(0.037, 0.095), Vector2(0.026, 0.01)]), at + Vector3(-0.16 + index * 0.15, 0.025, -0.08), "ceramic")
			mesh_collision(parent, mug)
			pipe(parent, "MugHandle", [mug.position + Vector3(0.036, 0.08, 0), mug.position + Vector3(0.065, 0.07, 0), mug.position + Vector3(0.065, 0.03, 0), mug.position + Vector3(0.033, 0.02, 0)], 0.007, "ceramic")

func wall_shelf() -> void:
	var shelf := group(station, "DryingShelf")
	box(shelf, "Shelf", Vector3(-1.63, 1.76, -0.45), Vector3(1.08, 0.025, 0.25), "steel")
	box(shelf, "TowelShelf", Vector3(-0.10, 1.76, -0.45), Vector3(0.58, 0.025, 0.25), "steel")
	for x: float in [-1.94, -1.20, -0.20]:
		pipe(shelf, "WallBracket", [Vector3(x, 1.48, -0.56), Vector3(x, 1.73, -0.34), Vector3(x, 1.73, -0.56)], 0.014, "steel")
	for index: int in 3:
		box(shelf, "NestedTray", Vector3(-1.7, 1.79 + index * 0.014, -0.45), Vector3(0.47, 0.014, 0.23), "steel", false)
	for x: float in [-1.35, -1.15]: bottle(shelf, Vector3(x, 1.777, -0.45), "soap")
	var towel := box(shelf, "FoldedTowel", Vector3(-0.10, 1.796, -0.43), Vector3(0.26, 0.05, 0.19), "cream", false)
	for index: int in 4: box(shelf, "TowelFold", Vector3(-0.10, 1.78 + index * 0.012, -0.332), Vector3(0.24, 0.002, 0.003), "dark", false)

func bottle(parent: Node3D, at: Vector3, colour: String) -> void:
	box(parent, "DetergentBottle", at + Vector3.UP * 0.10, Vector3(0.10, 0.20, 0.09), colour, true)
	cylinder(parent, "BottleCap", at + Vector3.UP * 0.211, 0.022, 0.025, "cream")
	box(parent, "BottleLabel", at + Vector3(0, 0.115, 0.047), Vector3(0.076, 0.086, 0.001), "cream", false)

func leg(parent: Node3D, at: Vector3, height: float) -> void:
	pipe(parent, "RoundLeg", [at + Vector3.UP * 0.025, at + Vector3.UP * height], 0.025, "steel", true)
	cylinder(parent, "AdjustableFoot", at + Vector3.UP * 0.018, 0.038, 0.025, "rubber")
	cylinder(parent, "FootCollar", at + Vector3.UP * 0.055, 0.030, 0.025, "steel")

func material(colour: Color, roughness: float, metallic: float = 0) -> Material:
	var result := StandardMaterial3D.new()
	result.albedo_color = colour
	result.roughness = roughness
	result.metallic = metallic
	return result
func group(parent: Node3D, label: String) -> Node3D:
	var node := Node3D.new()
	add(parent, node, label)
	return node
func add(parent: Node, node: Node, label: String) -> void:
	node.name = label
	parent.add_child(node, true)
	node.owner = station
func visual(parent: Node3D, label: String, mesh: Mesh, at: Vector3, mat: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	add(parent, node, label)
	node.mesh = mesh
	node.position = at
	node.material_override = materials[mat]
	return node
func box(parent: Node3D, label: String, at: Vector3, size: Vector3, mat: String, solid: bool = true, draw: bool = true) -> Node3D:
	var node := StaticBody3D.new() if solid else Node3D.new()
	add(parent, node, label)
	node.position = at
	if draw: visual(node, "Mesh", Detail.bevel_box(size, minf(0.006, minf(size.x, minf(size.y, size.z)) * 0.22)), Vector3.ZERO, mat)
	if solid:
		node.add_to_group("diner_static", true)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		shape.margin = 0.0001
		collision.shape = shape
		add(node, collision, "Collision")
	return node
func cylinder(parent: Node3D, label: String, at: Vector3, radius: float, height: float, mat: String) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	return visual(parent, label, mesh, at, mat)
func pipe(parent: Node3D, label: String, points: Array[Vector3], radius: float, mat: String, solid: bool = false) -> void:
	visual(parent, label, Detail.pipe(points, radius), Vector3.ZERO, mat)
	if not solid: return
	for index: int in range(points.size() - 1):
		var delta := points[index + 1] - points[index]
		if delta.length() < 0.0001: continue
		var body := StaticBody3D.new()
		add(parent, body, label + "Collision")
		body.add_to_group("diner_static", true)
		body.position = (points[index + 1] + points[index]) * 0.5
		body.quaternion = Quaternion(Vector3.UP, delta.normalized())
		var collision := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = delta.length() + radius * 0.4
		shape.margin = 0.0001
		collision.shape = shape
		add(body, collision, "Shape")
func batch(assembly: Node3D) -> void:
	var surfaces: Dictionary = {}
	var mats: Dictionary = {}
	for node: MeshInstance3D in assembly.find_children("*", "MeshInstance3D", true, false):
		var id := node.material_override.get_instance_id()
		if not surfaces.has(id):
			surfaces[id] = SurfaceTool.new()
			surfaces[id].begin(Mesh.PRIMITIVE_TRIANGLES)
			mats[id] = node.material_override
		surfaces[id].append_from(node.mesh, 0, assembly.global_transform.affine_inverse() * node.global_transform)
		node.free()
	for id: int in surfaces:
		var mesh := MeshInstance3D.new()
		add(assembly, mesh, "Surface")
		mesh.mesh = surfaces[id].commit()
		mesh.material_override = mats[id]

func mesh_collision(parent: Node3D, mesh: MeshInstance3D) -> void:
	var body := StaticBody3D.new()
	add(parent, body, str(mesh.name) + "Collision")
	body.add_to_group("diner_static", true)
	body.transform = mesh.transform
	var collision := CollisionShape3D.new()
	collision.shape = mesh.mesh.create_trimesh_shape()
	add(body, collision, "Shape")
