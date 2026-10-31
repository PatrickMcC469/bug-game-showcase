extends SceneTree
## Offline deterministic Godot mesh authoring. New scenes use metres, a
## floor-contact origin and no scripts, labels, particles or gameplay state.
const Definition := preload("res://scripts/game/food_definition.gd")
const Surface := preload("res://assets/shaders/food_variety_surface.gdshader")
var _root: Node3D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for directory: String in ["res://scenes/game/food", "res://assets/food"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	_build("spicy_pepper", "Spicy pepper", Definition.Effect.SPICY, "Faster movement while carried, with gradual health loss.")
	_build("fermented_fruit", "Fermented grape", Definition.Effect.TIPSY, "Tipsy movement and sideways wobble while carried.")
	_build("frozen_food", "Frozen blueberry", Definition.Effect.COLD, "Cold builds while carried; holding too long briefly freezes the bug.")
	_build("french_fry", "French fry", Definition.Effect.GREASE, "Leaves short-lived grease slicks that can trip the exterminator.")
	var viewer := Node3D.new()
	viewer.name = "FoodVarietyShowcase"
	viewer.set_script(load("res://scripts/game/food_variety_showcase.gd"))
	var scene := PackedScene.new()
	assert(scene.pack(viewer) == OK)
	assert(ResourceSaver.save(scene, "res://scenes/game/food_variety_showcase.tscn") == OK)
	viewer.free()
	print("FOOD VARIETY BUILD: PASS")
	quit()

func _build(id: String, title: String, effect: int, description: String) -> void:
	_root = Node3D.new()
	_root.name = id.to_pascal_case()
	_root.set_meta("food_id", id)
	match id:
		"spicy_pepper": _pepper()
		"fermented_fruit": _grape()
		"frozen_food": _frozen()
		"french_fry": _fry()
	var bounds := _bounds()
	for child: Node3D in _root.get_children(): child.position.y -= bounds.position.y
	bounds = _bounds()
	_root.set_meta("dimensions_m", bounds.size)
	var anchor := Marker3D.new()
	_add(anchor, "CarryAnchor")
	anchor.position = bounds.get_center()
	var scene := PackedScene.new()
	assert(scene.pack(_root) == OK)
	var path := "res://scenes/game/food/" + id + ".tscn"
	assert(ResourceSaver.save(scene, path) == OK)
	var food := Definition.new()
	food.food_id = StringName(id)
	food.display_name = title
	food.model_scene = load(path)
	food.effect = effect
	food.effect_description = description
	assert(food.validate().is_empty())
	assert(ResourceSaver.save(food, "res://assets/food/" + id + ".tres") == OK)
	_root.free()

func _material(base: Color, accent: Color, roughness: float, kind: int = 0) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = Surface
	material.set_shader_parameter("base_color", base)
	material.set_shader_parameter("accent_color", accent)
	material.set_shader_parameter("surface_roughness", roughness)
	material.set_shader_parameter("surface_kind", kind)
	return material

func _add(node: Node3D, title: String) -> void:
	node.name = title
	_root.add_child(node, true)
	node.owner = _root

func _mesh(title: String, mesh: Mesh, material: Material, at := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	_add(node, title)
	return node

func _sphere(title: String, radius: float, proportions: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2
	sphere.radial_segments = 24
	sphere.rings = 12
	var node := _mesh(title, sphere, material, at)
	node.scale = proportions
	return node

func _skin(point: Callable, rows: int = 40, sides: int = 40) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in rows:
		for j: int in sides:
			var uv := [Vector2(float(i)/rows, float(j)/sides), Vector2(float(i+1)/rows, float(j)/sides), Vector2(float(i+1)/rows, float(j+1)/sides), Vector2(float(i)/rows, float(j+1)/sides)]
			for index: int in [0, 1, 2, 0, 2, 3]:
				surface.set_uv(uv[index])
				surface.add_vertex(point.call(uv[index].x, uv[index].y * TAU))
	surface.index()
	surface.generate_normals()
	return surface.commit()

func _pepper() -> void:
	var skin := _skin(func(t: float, a: float) -> Vector3:
		var radius := 0.0052 * pow(1.0 - t, 0.65) * (0.82 + 0.18 * sin(t * PI))
		radius *= 1.0 + 0.05 * sin(a * 5 + t * 6)
		return Vector3(0.005 * t * t + cos(a) * radius, 0.006 + 0.001 * sin(t * PI) + sin(a) * radius, -0.022 + 0.044 * t))
	_mesh("PepperSkin", skin, _material(Color("b91f10"), Color("5d1209"), 0.30))
	var green := _material(Color("3d5521"), Color("18280f"), 0.65)
	_sphere("Calyx", 0.0045, Vector3(1, 1, 0.34), Vector3(0, 0.006, -0.022), green)
	var stem := _skin(func(t: float, a: float) -> Vector3:
		var radius := 0.0012 * sin(PI * t)
		return Vector3(cos(a) * radius - t * 0.002, 0.006 + t * 0.004 + sin(a) * radius, -0.022 - t * 0.009), 16, 16)
	_mesh("BentStem", stem, green)

func _grape() -> void:
	var skin := _skin(func(t: float, a: float) -> Vector3:
		var p := t * PI
		var wrinkle := 1.0 + 0.035 * sin(a * 23 + p * 8) * sin(p) + 0.025 * cos(a * 7 - p * 12)
		return Vector3(cos(a) * sin(p) * 0.0105 * wrinkle, cos(p) * 0.010 + 0.010, sin(a) * sin(p) * 0.013 * wrinkle))
	_mesh("WrinkledSkin", skin, _material(Color("3c2445"), Color("5b3e35"), 0.43, 1))
	var pulp := _material(Color("b5aa64"), Color("776b39"), 0.23)
	_sphere("SplitFlesh", 0.004, Vector3(0.16, 0.65, 1.0), Vector3(0.0098, 0.0115, 0.003), pulp)
	_sphere("StemScar", 0.0015, Vector3(1.0, 0.26, 1), Vector3(0, 0.020, 0), _material(Color("534829"), Color("292415"), 0.85))
	var bruise := _material(Color("3c252e"), Color("2b181f"), 0.28)
	_sphere("BruisedFold", 0.0027, Vector3(0.35, 1, 1.5), Vector3(-0.010, 0.009, -0.002), bruise)

func _frozen() -> void:
	var berry := _skin(func(t: float, a: float) -> Vector3:
		var p := t * PI
		var r := 0.0095 * (1.0 + 0.045 * cos(a * 5) * sin(p))
		return Vector3(cos(a) * sin(p) * r, 0.0085 + cos(p) * 0.0085, sin(a) * sin(p) * r))
	_mesh("FrostedBerry", berry, _material(Color("283d67"), Color("9caeb7"), 0.64, 2))
	var frost := _material(Color("b9d7e0"), Color("eff4ee"), 0.52, 2)
	var crystals := SurfaceTool.new()
	crystals.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in 64:
		var y := lerpf(-0.85, 0.94, float(i)/63)
		var a := float(i) * 2.39996323
		var normal := Vector3(sqrt(1-y*y)*cos(a), y, sqrt(1-y*y)*sin(a))
		var center := Vector3(normal.x * 0.00955, 0.0085 + normal.y * 0.00855, normal.z * 0.00955)
		var size := 0.00028 + (sin(i*17.0)*0.5+0.5)*0.00032
		_octahedron(crystals, center, size)
	crystals.generate_normals()
	_mesh("IceCrystals", crystals.commit(), frost)
	var dark := _material(Color("25354c"), Color("667d90"), 0.8)
	_sphere("CrownWell", 0.0027, Vector3(1, 0.2, 1), Vector3(0, 0.0168, 0), dark)
	for i: int in 5:
		var a := TAU * i / 5
		var leaf := _sphere("CrownLobe", 0.0014, Vector3(0.65, 0.3, 1.4), Vector3(cos(a)*0.002, 0.017, sin(a)*0.002), frost)
		leaf.rotation.y = -a + PI/2

func _fry() -> void:
	var potato := _skin(func(t: float, a: float) -> Vector3:
		var tip := 0.72 + 0.28 * pow(sin(PI*t), 0.15)
		var x := signf(cos(a)) * pow(absf(cos(a)), 0.35) * 0.0036 * tip
		var y := signf(sin(a)) * pow(absf(sin(a)), 0.35) * 0.0032 * tip
		return Vector3(x + sin(t*9)*0.00035, y+0.0035+sin(t*PI)*0.00035, -0.024+t*0.048), 36, 32)
	var gold := _material(Color("d79c48"), Color("aa6a2b"), 0.44, 3)
	_mesh("FriedPotato", potato, gold)
	for z: float in [-0.024, 0.024]:
		var end := BoxMesh.new()
		end.size = Vector3(0.0053, 0.0047, 0.00015)
		_mesh("CutEnd", end, _material(Color("b8782b"), Color("84501f"), 0.65, 3), Vector3(sin((z+0.024)/0.048*9)*0.00035, 0.0035, z))
	var salt := SurfaceTool.new()
	salt.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in 20:
		var t := (i+0.5)/20.0
		_octahedron(salt, Vector3(sin(i*13.7)*0.0022, 0.0067+sin(t*PI)*0.00035, -0.022+t*0.044), 0.00016)
	salt.generate_normals()
	_mesh("SaltGrains", salt.commit(), _material(Color("e7dfc7"), Color("cbb991"), 0.42))

func _octahedron(surface: SurfaceTool, at: Vector3, radius: float) -> void:
	var points := [Vector3.UP, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.FORWARD, Vector3.DOWN]
	for face: Array in [[0,2,1],[0,3,2],[0,4,3],[0,1,4],[5,1,2],[5,2,3],[5,3,4],[5,4,1]]:
		for index: int in [face[0], face[2], face[1]]:
			surface.set_uv(Vector2.ZERO)
			surface.add_vertex(at + points[index] * radius)

func _bounds() -> AABB:
	var result := AABB()
	var first := true
	for child: Node in _root.get_children():
		if not child is MeshInstance3D: continue
		var box: AABB = child.transform * child.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result
