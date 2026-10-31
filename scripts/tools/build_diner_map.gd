extends SceneTree
## Offline authoring tool. Saves editable geometry; the game never runs this builder.
## Rebuild only when you own scenes/game/maps/diner_kitchen.tscn.
const OUTPUT := "res://scenes/game/maps/diner_kitchen.tscn"
const Detail := preload("res://scripts/tools/diner_detail_geometry.gd")
const Layout := preload("res://scripts/game/diner_layout.gd")
const LayoutBaker := preload("res://scripts/tools/diner_layout_baker.gd")
var _map: Node3D
var _materials: Dictionary[String, Material] = {}
var _box_meshes: Dictionary[String, ArrayMesh] = {}
var _placing_clutter := false

func _initialize() -> void:
	_build.call_deferred()

func _build() -> void:
	_map = Node3D.new()
	_map.name = "DinerKitchen"
	root.add_child(_map)
	_materials["tile"] = _pbr("brown_floor_tiles", 1.7, true, 0.75)
	_materials["wall"] = _pbr("long_white_tiles", 2.0, true, 0.6)
	_materials["steel"] = _metal(Color("a5aaa9"), 0.30)
	_materials["darksteel"] = _metal(Color("646c6b"), 0.44)
	_materials["cream"] = _solid(Color("c6bba0"), 0.1, 0.6)
	_materials["red"] = _solid(Color("6f2421"), 0.15, 0.48)
	_materials["rubber"] = _solid(Color("171c19"), 0.0, 0.86)
	_materials["wood"] = _pbr("kitchen_wood", 0.9, false, 0.22)
	_materials["cardboard"] = _surface(Color("8d7050"), Color("8d7050"), 0.3, 0.93, false, false)
	_materials["paper"] = _solid(Color("e0d8bd"), 0.0, 0.9)
	_materials["grime"] = _solid(Color("332820"), 0.0, 0.94)
	_materials["ceramic"] = _solid(Color("dbd6b9"), 0.0, 0.25)
	_materials["water"] = _solid(Color("233d36"), 0.32, 0.12)
	_materials["amber"] = _glow(Color("ffad51"), 2.5)
	_materials["mint"] = _glow(Color("75d5b6"), 2.0)
	_materials["white"] = _glow(Color("d6e0cf"), 1.5)
	_architecture()
	_prep_line()
	_dish_pit()
	_counter()
	_dressing()
	_lighting()
	_cart()
	_close_details()
	LayoutBaker.new().bake(_map, Layout.SCALE)
	_clutter()
	preload("res://scripts/tools/diner_makeover.gd").new().apply(_map)
	var packed := PackedScene.new()
	var error := packed.pack(_map)
	if error == OK:
		error = ResourceSaver.save(packed, OUTPUT)
	print("DINER BUILD: %s" % ("PASS" if error == OK else error_string(error)))
	_map.queue_free()
	quit(0 if error == OK else 1)

func _adopt(node: Node, parent: Node, node_name: String) -> void:
	node.name = node_name
	parent.add_child(node, true)
	node.owner = _map

func _group(node_name: String, at: Vector3 = Vector3.ZERO) -> Node3D:
	var node := Node3D.new()
	_adopt(node, _map, node_name)
	node.position = at
	return node

func _solid(color: Color, metal: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metal
	material.roughness = roughness
	return material

func _pbr(asset: String, repeat_meters: float, world_space: bool, normal_strength: float) -> StandardMaterial3D:
	var material := _solid(Color.WHITE, 0.0, 1.0)
	var folder := "res://assets/textures/diner/"
	material.albedo_texture = load(folder + asset + "_diff_2k.jpg")
	material.normal_enabled = true
	material.normal_texture = load(folder + asset + "_nor_gl_2k.jpg")
	material.normal_scale = normal_strength
	material.roughness_texture = load(folder + asset + "_rough_2k.jpg")
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.uv1_triplanar = true
	material.uv1_world_triplanar = world_space
	if asset == "long_white_tiles":
		material.uv1_triplanar = false
		material.uv1_world_triplanar = false
	material.uv1_scale = Vector3.ONE / repeat_meters
	return material

func _metal(tint: Color, roughness: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/shaders/diner_brushed_metal.gdshader")
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("base_roughness", roughness)
	return material

func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var material := _solid(color, 0.0, 0.35)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material

func _surface(a: Color, b: Color, tiles: float, roughness: float, wall: bool = false, tiled: bool = true) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/shaders/diner_surface.gdshader")
	material.set_shader_parameter("base_color", a)
	material.set_shader_parameter("alternate_color", b)
	material.set_shader_parameter("tile_size", tiles)
	material.set_shader_parameter("surface_roughness", roughness)
	material.set_shader_parameter("wall", wall)
	material.set_shader_parameter("tiled", tiled)
	return material

func _box(parent: Node3D, node_name: String, at: Vector3, size: Vector3, material: String, collision: bool = true) -> Node3D:
	var body: Node3D = StaticBody3D.new() if collision else Node3D.new()
	_adopt(body, parent, node_name)
	body.position = at
	if collision:
		body.add_to_group("diner_static", true)
		if _placing_clutter:
			body.add_to_group("diner_clutter", true)
	var mesh := MeshInstance3D.new()
	var key := str(size) + ("wall" if material == "wall" else "")
	if not _box_meshes.has(key):
		_box_meshes[key] = Detail.bevel_box(size, 0.012, material == "wall")
	mesh.mesh = _box_meshes[key]
	mesh.material_override = _materials[material]
	_adopt(mesh, body, "Mesh")
	if collision:
		var shape := CollisionShape3D.new()
		var bounds := BoxShape3D.new()
		bounds.size = size
		shape.shape = bounds
		_adopt(shape, body, "Collision")
	return body

func _cylinder(parent: Node3D, node_name: String, at: Vector3, radius: float, height: float, material: String) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = 24
	mesh.mesh = cylinder
	mesh.material_override = _materials[material]
	_adopt(mesh, parent, node_name)
	mesh.position = at
	return mesh

func _label(parent: Node3D, node_name: String, words: String, at: Vector3, font_size: int, pixel: float, color: Color) -> Label3D:
	var label := Label3D.new()
	_adopt(label, parent, node_name)
	label.position = at
	label.text = words
	label.font_size = font_size
	label.pixel_size = pixel
	label.modulate = color
	label.outline_size = 0
	return label

func _ramp(parent: Node3D, node_name: String, start: Vector3, end: Vector3, width: float, material: String = "wood") -> void:
	var horizontal := Vector2(end.x - start.x, end.z - start.z).length()
	var length := start.distance_to(end)
	var slope := atan2(end.y - start.y, horizontal)
	var ramp := _box(parent, node_name, (start + end) * 0.5 - Vector3.UP * 0.045, Vector3(width, 0.09, length + 0.12), material)
	ramp.rotation = Vector3(slope, atan2(start.x - end.x, start.z - end.z), 0.0)
	# Low side edges make the route readable without blocking the roach's capsule.
	for side: float in [-1.0, 1.0]:
		_box(ramp, "Edge", Vector3(side * (width * 0.5 - 0.012), 0.051, 0), Vector3(0.024, 0.012, length), "steel" if material == "steel" else "wood", false)

func _architecture() -> void:
	var room := _group("Room")
	_box(room, "Floor", Vector3(0, -0.3, 0), Vector3(36, 0.6, 30), "tile")
	_box(room, "NorthWall", Vector3(0, 3.6, -15), Vector3(36.5, 7.2, 0.4), "wall")
	_box(room, "SouthWall", Vector3(0, 3.6, 15), Vector3(36.5, 7.2, 0.4), "wall")
	_box(room, "WestWall", Vector3(-18, 3.6, 0), Vector3(0.4, 7.2, 30), "wall")
	_box(room, "EastWall", Vector3(18, 3.6, 0), Vector3(0.4, 7.2, 30), "wall")
	_box(room, "Ceiling", Vector3(0, 7.3, 0), Vector3(36, 0.2, 30), "cream")
	for z: float in [-14.76, 14.76]:
		_box(room, "RedTileBand", Vector3(0, 2.9, z), Vector3(35.5, 0.3, 0.04), "red", false)
		_box(room, "Skirting", Vector3(0, 0.16, z), Vector3(35.5, 0.32, 0.06), "darksteel", false)
	for x: float in [-17.76, 17.76]:
		_box(room, "RedTileBand", Vector3(x, 2.9, 0), Vector3(0.04, 0.3, 29.5), "red", false)
		_box(room, "Skirting", Vector3(x, 0.16, 0), Vector3(0.06, 0.32, 29.5), "darksteel", false)
	# The customer side is a visual slice, contained by the same solid perimeter.
	for x: float in [-8, 0, 8]:
		_box(room, "NightWindow", Vector3(x, 4.2, 14.72), Vector3(6.6, 3.2, 0.06), "rubber", false)
		for side: float in [-3.35, 3.35]:
			_box(room, "WindowFrame", Vector3(x + side, 4.2, 14.64), Vector3(0.12, 3.4, 0.12), "steel", false)
		_box(room, "WindowMullion", Vector3(x, 4.2, 14.61), Vector3(0.08, 3.3, 0.14), "steel", false)
		_box(room, "NeonReflection", Vector3(x, 5.45, 14.59), Vector3(6.4, 0.045, 0.05), "mint", false)
	var sign := _label(room, "DinerSign", "NIGHT OWL\nD I N E R", Vector3(0, 4.3, 14.5), 96, 0.018, Color("86dfc4"))
	sign.rotation.y = PI
	var closed := _label(room, "Closed", "SORRY, WE'RE CLOSED", Vector3(-8, 3.65, 14.5), 40, 0.018, Color("ffba72"))
	closed.rotation.y = PI
	_box(room, "ServiceDoor", Vector3(13.8, 2.5, -14.7), Vector3(3.4, 5, 0.12), "darksteel", false)
	_box(room, "DoorWindow", Vector3(13.8, 3.5, -14.6), Vector3(1.4, 1.5, 0.1), "rubber", false)
	_box(room, "DoorKickplate", Vector3(13.8, 0.6, -14.6), Vector3(3.1, 1.0, 0.12), "steel", false)
	_label(room, "ExitSign", "EXIT", Vector3(13.8, 5.5, -14.55), 48, 0.014, Color("87cfaa"))

func _table(parent: Node3D, at: Vector3, size: Vector2, node_name: String, surface: String = "steel") -> Node3D:
	var table := Node3D.new()
	_adopt(table, parent, node_name)
	table.position = at
	_box(table, "Worktop", Vector3(0, 2.32, 0), Vector3(size.x, 0.16, size.y), surface)
	_box(table, "Apron", Vector3(0, 2.05, 0), Vector3(size.x - 0.1, 0.38, size.y - 0.1), "darksteel")
	for x: float in [-size.x * 0.5 + 0.18, size.x * 0.5 - 0.18]:
		for z: float in [-size.y * 0.5 + 0.18, size.y * 0.5 - 0.18]:
			_box(table, "Leg", Vector3(x, 1.0, z), Vector3(0.14, 2.0, 0.14), "steel")
			_cylinder(table, "AdjustableFoot", Vector3(x, 0.055, z), 0.087, 0.11, "rubber")
			_cylinder(table, "FootCollar", Vector3(x, 0.14, z), 0.077, 0.055, "steel")
	return table

func _prep_line() -> void:
	var prep := _group("PrepLine")
	_table(prep, Vector3(1, 0, -6), Vector2(10, 3), "PrepIsland")
	_ramp(prep, "PrepBoardRamp", Vector3(-6, 0.001, -3.1), Vector3(-6, 2.4, -8.6), 2.0)
	_box(prep, "BoardLanding", Vector3(-4.5, 2.34, -9.4), Vector3(5, 0.12, 1.6), "wood")
	_box(prep, "BoardBridge", Vector3(-3, 2.34, -8.25), Vector3(2, 0.12, 1.5), "wood")
	_box(prep, "CartLanding", Vector3(7.5, 2.32, -5.4), Vector3(3.0, 0.16, 1.8), "steel")
	_box(prep, "ChoppingBoard", Vector3(0.1, 2.43, -6), Vector3(2.6, 0.06, 1.7), "wood", false)
	_box(prep, "KnifeBlade", Vector3(-0.5, 2.49, -6.3), Vector3(1.3, 0.04, 0.24), "steel", false).rotation.y = 0.4
	_box(prep, "KnifeHandle", Vector3(-1.35, 2.50, -6.65), Vector3(0.7, 0.11, 0.23), "rubber", false).rotation.y = 0.4
	for x: float in [-11, -6, -1, 4]:
		var appliance := _box(prep, "CookLine", Vector3(x, 1.2, -12.8), Vector3(4.6, 2.4, 3.2), "steel")
		_box(appliance, "FrontPanel", Vector3(0, 0, 1.63), Vector3(4.3, 1.7, 0.06), "darksteel", false)
		for dial: float in [-1.5, -0.5, 0.5, 1.5]:
			_cylinder(appliance, "Dial", Vector3(dial, 0.8, 1.72), 0.11, 0.1, "rubber").rotation.x = PI * 0.5
		for burner: float in [-1, 1]:
			_cylinder(prep, "Burner", Vector3(x + burner, 2.44, -12.6), 0.52, 0.07, "rubber")
	_box(prep, "ExtractorHood", Vector3(-3.5, 5.2, -12.6), Vector3(20, 1.1, 3.9), "steel", false)
	for i: int in 18:
		_box(prep, "HoodVent", Vector3(-12 + i, 4.63, -12.6), Vector3(0.06, 0.04, 3.2), "rubber", false)
	_box(prep, "OrderRail", Vector3(1, 4.3, -6), Vector3(9, 0.08, 0.09), "steel", false)
	for i: int in 6:
		var ticket := _box(prep, "OrderTicket", Vector3(-2.5 + i * 1.25, 4.05, -5.96), Vector3(0.24, 0.36, 0.001), "paper", false)
		ticket.rotation.z = sin(i * 4.3) * 0.06
		_label(ticket, "Print", "NIGHT OWL\nCHECK %03d\n\n1  COFFEE\n1  CHERRY PIE\n\nTOTAL  8.50" % (184 + i), Vector3(0, 0, 0.002), 24, 0.0007, Color("353127"))
	_label(prep, "PrepSign", "01  /  HOT LINE", Vector3(-2, 3.6, -14.6), 48, 0.015, Color("393e32"))
	for x: float in [-2, 2, 5]:
		_cylinder(prep, "HeatShade", Vector3(x, 5, -6), 0.52, 0.30, "red")
		_cylinder(prep, "HeatBulb", Vector3(x, 4.83, -6), 0.35, 0.03, "amber")
		_box(prep, "HeatCord", Vector3(x, 6.1, -6), Vector3(0.035, 2.2, 0.035), "rubber", false)

func _dish_pit() -> void:
	var dish := _group("DishPit")
	_table(dish, Vector3(13.4, 0, 5.7), Vector2(6.4, 3), "DishTable")
	var sinks := _table(dish, Vector3(15.7, 0, -3.4), Vector2(3.5, 9), "SinkLine")
	sinks.get_node("Worktop").free()
	sinks.get_node("Apron").free()
	for side: float in [-1.0, 1.0]:
		_box(sinks, "DrainBoard", Vector3(side * 1.10, 2.32, 0), Vector3(1.3, 0.16, 9), "steel")
	for span: Vector2 in [Vector2(-4.5, -2.425), Vector2(-1.775, 1.575), Vector2(2.225, 4.5)]:
		_box(sinks, "SinkBridge", Vector3(0, 2.32, (span.x + span.y) * 0.5), Vector3(0.9, 0.16, span.y - span.x), "steel")
	for z: float in [-5.5, -1.5]:
		_box(dish, "BasinBottom", Vector3(15.7, 2.025, z), Vector3(0.9, 0.05, 0.65), "steel")
		for side: float in [-1.0, 1.0]:
			_box(dish, "BasinWall", Vector3(15.7 + side * 0.44, 2.21, z), Vector3(0.02, 0.38, 0.65), "steel")
			_box(dish, "BasinWall", Vector3(15.7, 2.21, z + side * 0.315), Vector3(0.9, 0.38, 0.02), "steel")
		_cylinder(dish, "SinkDrain", Vector3(15.7, 2.052, z), 0.045, 0.003, "rubber")
		_cylinder(dish, "TapBase", Vector3(16.3, 2.412, z), 0.05, 0.025, "steel")
		var neck: Array[Vector3] = [Vector3(16.3, 2.43, z), Vector3(16.3, 2.67, z)]
		for i: int in 17:
			var angle := PI * i / 16
			neck.append(Vector3(16.18 + 0.12 * cos(angle), 2.67 + 0.12 * sin(angle), z))
		neck.append(Vector3(16.06, 2.63, z))
		_pipe(dish, "GooseneckTap", neck, 0.016)
		_cylinder(dish, "TapAerator", Vector3(16.06, 2.635, z), 0.021, 0.025, "steel")
		_box(dish, "TapLever", Vector3(16.34, 2.47, z + 0.05), Vector3(0.02, 0.018, 0.13), "steel", false)
	_ramp(dish, "DishTrayRamp", Vector3(13.2, 0.001, 12.9), Vector3(13.2, 2.4, 7.1), 2.2, "steel")
	for point: Vector3 in [Vector3(12, 2.4, 5.3), Vector3(14.8, 2.4, 6.1), Vector3(16, 2.4, 4.7)]:
		for layer: int in 5:
			_mesh(dish, "Plate", point + Vector3.UP * (0.003 + layer * 0.017), _plate_mesh(), "ceramic")
	_box(dish, "BusTub", Vector3(13.6, 0.42, 2), Vector3(2.4, 0.84, 1.5), "darksteel")
	_box(dish, "FallenTray", Vector3(10.5, 0.03, 10), Vector3(3.4, 0.06, 2), "steel").rotation.y = -0.35
	_puddle(dish, Vector3(15, 0.0004, 10.4))
	var sign := _label(dish, "DishSign", "02  /  DISH PIT", Vector3(17.65, 4.5, 3), 48, 0.015, Color("393e32"))
	sign.rotation.y = -PI * 0.5
	_box(dish, "WetFloorSign", Vector3(10.8, 0.7, 11.2), Vector3(0.75, 1.4, 0.08), "wood").rotation.x = -0.18
	_label(dish, "Caution", "CAUTION\nWET FLOOR", Vector3(10.8, 0.8, 11.3), 24, 0.009, Color("201f14"))

func _counter() -> void:
	var counter := _group("CounterAndNest")
	# The nest is open at the front; the low side passages reconnect to the aisle.
	_box(counter, "CounterTop", Vector3(-11.3, 3.22, 0), Vector3(7.5, 0.18, 9), "cream")
	_box(counter, "CounterBack", Vector3(-15, 1.6, 0), Vector3(0.24, 3.2, 9), "red")
	for z: float in [-3.3, 3.3]:
		# Preserve the insect-sized 4 cm clearance after compacting the fixtures.
		_box(counter, "LowPassageRoof", Vector3(-11, 0.04 / Layout.SCALE + 0.055, z), Vector3(7.5, 0.11, 2.2), "red")
		_box(counter, "CabinetUpper", Vector3(-11, 1.62, z), Vector3(7.3, 3.02, 2.0), "cream")
		_box(counter, "DrawerPull", Vector3(-7.3, 2.52, z), Vector3(0.16, 0.07, 0.7), "steel", false)
	_box(counter, "LooseBaseboard", Vector3(-7.7, 0.25, -2.3), Vector3(0.12, 0.5, 1.2), "wood").rotation.y = -0.4
	_label(counter, "NestSign", "03  /  UNDER THE COUNTER", Vector3(-11.1, 2.6, 4.55), 40, 0.014, Color("eadcc0"))
	for x: float in [-12.7, -10, -7.3]:
		_box(counter, "ServingCounter", Vector3(x, 2.4, 11), Vector3(2.6, 0.18, 2.2), "cream")
		_box(counter, "CounterCabinet", Vector3(x, 1.15, 11.3), Vector3(2.5, 2.3, 1.5), "red")
		_cylinder(counter, "StoolBase", Vector3(x, 0.08, 13.2), 0.65, 0.16, "steel")
		_cylinder(counter, "StoolPost", Vector3(x, 0.9, 13.2), 0.12, 1.7, "steel")
		_cylinder(counter, "StoolSeat", Vector3(x, 1.8, 13.2), 0.67, 0.25, "red")
	# Open shelving provides cover without enclosing food in unreachable geometry.
	for y: float in [1.2, 2.6, 4.0]:
		_box(counter, "PantryShelf", Vector3(-16.8, y, -9), Vector3(1.6, 0.12, 6), "steel")
	for z: float in [-11.8, -6.2]:
		_box(counter, "ShelfUpright", Vector3(-16.2, 2, z), Vector3(0.12, 4, 0.12), "steel")
	for i: int in 5:
		_cylinder(counter, "SupplyTin", Vector3(-16.7, 1.72, -11 + i), 0.32, 0.9, "cream")

func _dressing() -> void:
	var props := _group("AfterHoursDetails")
	_box(props, "RubberMat", Vector3(3, 0.018, -9.5), Vector3(8, 0.035, 1.5), "rubber", false)
	for i: int in 24:
		_box(props, "MatRib", Vector3(-0.8 + i * 0.33, 0.04, -9.5), Vector3(0.035, 0.02, 1.4), "darksteel", false)
	for point: Vector3 in [Vector3(-3.5, 0, 7), Vector3(1, 0, 10), Vector3(-12, 0, -8)]:
		var crate := _box(props, "DeliveryBox", point + Vector3.UP * 0.55, Vector3(1.7, 1.1, 1.5), "cardboard")
		_box(crate, "PackingTape", Vector3(0, 0.56, 0), Vector3(0.25, 0.012, 1.5), "cream", false)
		_label(crate, "BoxPrint", "NIGHT OWL\nDRY GOODS", Vector3(0, 0, 0.76), 24, 0.014, Color("30291c"))
	for i: int in 22:
		var p := Vector3(sin(i * 3.14 + 0.8) * 6 + 1, 0.002, cos(i * 2.3) * 10)
		_box(props, "Crumb", p, Vector3(0.003 + (i % 3) * 0.002, 0.003, 0.006), "wood", false).rotation.y = i * 0.83
	_box(props, "MenuBoard", Vector3(5, 4, 14.55), Vector3(3.2, 2, 0.12), "rubber", false)
	var menu := _label(props, "Menu", "TONIGHT'S SPECIAL\nCOFFEE  /  PIE\nOPEN LATE. VERY LATE.", Vector3(5, 4, 14.45), 26, 0.018, Color("d9cdb2"))
	menu.rotation.y = PI
	_box(props, "WallClock", Vector3(-8, 4.2, -14.65), Vector3(1.2, 1.2, 0.12), "cream", false)
	_box(props, "ClockHand", Vector3(-8, 4.37, -14.56), Vector3(0.035, 0.4, 0.03), "rubber", false)
	_box(props, "ClockHand", Vector3(-7.84, 4.2, -14.55), Vector3(0.35, 0.035, 0.03), "rubber", false)

func _light(parent: Node3D, at: Vector3, color: Color, energy: float, reach: float, shadows: bool = false) -> void:
	var light := OmniLight3D.new()
	_adopt(light, parent, "PracticalLight")
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = 1.4
	light.shadow_enabled = shadows
	light.shadow_bias = 0.035

func _lighting() -> void:
	var lighting := _group("Lighting")
	var world := WorldEnvironment.new()
	_adopt(world, lighting, "WorldEnvironment")
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("101b22")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c2c9d0")
	environment.ambient_light_energy = 0.32
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.ssao_enabled = true
	environment.ssao_radius = 0.22
	environment.ssao_intensity = 1.4
	environment.ssil_enabled = true
	environment.ssil_intensity = 0.75
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("344b52")
	sky_material.sky_horizon_color = Color("a9b2a0")
	sky_material.ground_horizon_color = Color("757767")
	sky_material.ground_bottom_color = Color("303831")
	sky.sky_material = sky_material
	environment.sky = sky
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.glow_enabled = true
	world.environment = environment
	var reflection := ReflectionProbe.new()
	_adopt(reflection, lighting, "KitchenReflection")
	reflection.position = Vector3(0, 2.8, 0)
	reflection.size = Vector3(35.5, 7.0, 29.5)
	reflection.interior = true
	reflection.box_projection = true
	reflection.max_distance = 40
	reflection.intensity = 0.85
	for at: Vector3 in [Vector3(-8, 6.6, -7), Vector3(6, 6.6, -9), Vector3(11, 6.6, 5), Vector3(-5, 6.6, 7), Vector3(14, 6.6, -4), Vector3(-12, 6.6, 0)]:
		_box(lighting, "FluorescentHousing", at, Vector3(4.2, 0.12, 0.7), "darksteel", false)
		for z: float in [-0.2, 0.2]:
			_box(lighting, "FluorescentTube", at + Vector3(0, -0.08, z), Vector3(3.8, 0.065, 0.075), "white", false)
		_light(lighting, at - Vector3.UP * 0.5, Color("f0ede2"), 4.0, 15, true)
	_light(lighting, Vector3(1, 4.5, -6), Color("ffb465"), 2.2, 7)
	_light(lighting, Vector3(0, 4, 12.5), Color("7abdb4"), 2.0, 12)
	_light(lighting, Vector3(-8, 3.7, 12.8), Color("e59559"), 1.4, 8)

func _cart() -> void:
	var cart := AnimatableBody3D.new()
	cart.position = Vector3(9, 0, -3)
	cart.sync_to_physics = false
	_adopt(cart, _map, "ServingCart")
	cart.set_script(load("res://scripts/game/serving_cart.gd"))
	# Collision shapes belong directly to the moving body; never nest static bodies.
	_cart_box(cart, "Deck", Vector3(0, 2.32, 0), Vector3(2.4, 0.16, 3), "steel")
	_cart_box(cart, "Shelf", Vector3(0, 0.8, 0), Vector3(2.3, 0.12, 2.9), "darksteel")
	for x: float in [-1.05, 1.05]:
		for z: float in [-1.35, 1.35]:
			_cart_box(cart, "Upright", Vector3(x, 1.3, z), Vector3(0.1, 2.0, 0.1), "steel")
			_cylinder(cart, "Wheel", Vector3(x, 0.24, z), 0.24, 0.16, "rubber").rotation.z = PI * 0.5
	_cart_box(cart, "PushHandle", Vector3(0, 2.9, 1.42), Vector3(2.3, 0.09, 0.09), "steel")
	var ramp_start := Vector3(-4.8, 0.001, 0)
	var ramp_end := Vector3(-1.15, 2.4, 0)
	var ramp_rotation := Vector3(0, 0, atan2(2.399, 3.65))
	_cart_box(cart, "LoadingRamp", (ramp_start + ramp_end) * 0.5 - Vector3.UP * 0.045, Vector3(ramp_start.distance_to(ramp_end) + 0.12, 0.09, 1.8), "wood", ramp_rotation)
	var label := _label(cart, "Prompt", "SERVING CART", Vector3(0, 3.55, 0), 32, 0.013, Color("f4d19a"))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var handle := Marker3D.new()
	_adopt(handle, cart, "Handle")
	handle.position = Vector3(0, 0, 2.25)
	for z: float in [-3, 5.7]:
		_box(_map, "CartDockMark", Vector3(9, 0.013, z), Vector3(2.8, 0.025, 3.4), "rubber", false)

func _cart_box(cart: AnimatableBody3D, node_name: String, at: Vector3, size: Vector3, material: String, angles: Vector3 = Vector3.ZERO) -> void:
	var visual := _box(cart, node_name, at, size, material, false)
	visual.rotation = angles
	var shape := CollisionShape3D.new()
	var bounds := BoxShape3D.new()
	bounds.size = size
	shape.shape = bounds
	_adopt(shape, cart, node_name + "Collision")
	shape.position = at
	shape.rotation = angles

func _mesh(parent: Node3D, node_name: String, at: Vector3, geometry: Mesh, material: String) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	_adopt(mesh, parent, node_name)
	mesh.mesh = geometry
	mesh.material_override = _materials[material]
	mesh.position = at
	return mesh

func _plate_mesh() -> ArrayMesh:
	return Detail.lathe([
		Vector2(0.001, 0.005), Vector2(0.07, 0.005), Vector2(0.075, 0),
		Vector2(0.09, 0), Vector2(0.093, 0.008), Vector2(0.146, 0.022),
		Vector2(0.16, 0.025), Vector2(0.16, 0.031), Vector2(0.15, 0.033),
		Vector2(0.10, 0.015), Vector2(0.075, 0.012), Vector2(0.001, 0.012)])

func _puddle(parent: Node3D, at: Vector3) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment: int in 64:
		for corner: int in 3:
			var angle := TAU * (segment + maxi(corner - 1, 0)) / 64.0
			var radius := 0.72 + sin(angle * 3.0 + 0.5) * 0.12 + sin(angle * 7.0) * 0.035
			surface.set_normal(Vector3.UP)
			surface.set_color(Color(1, 1, 1, 0.85 if corner == 0 else 0.0))
			surface.set_uv(Vector2.ZERO)
			surface.add_vertex(Vector3.ZERO if corner == 0 else Vector3(cos(angle) * radius, 0, sin(angle) * radius * 0.67))
	var wet := (_materials["tile"] as StandardMaterial3D).duplicate() as StandardMaterial3D
	wet.roughness_texture = null
	wet.roughness = 0.08
	wet.normal_scale = 0.08
	wet.albedo_color = Color(0.72, 0.72, 0.72, 1.0)
	wet.vertex_color_use_as_albedo = true
	wet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mesh := _mesh(parent, "WetFloorFilm", at, surface.commit(), "tile")
	mesh.material_override = wet
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _pipe(parent: Node3D, node_name: String, points: Array[Vector3], radius: float, material: String = "steel") -> void:
	_mesh(parent, node_name, Vector3.ZERO, Detail.pipe(points, radius), material)

func _close_details() -> void:
	var details := _group("RoachEyeDetails")
	# Flat drains keep the established floor routes traversable. Slots are inset
	# visually; tiny dressing does not create snagging collision edges.
	for point: Vector3 in [Vector3(10, 0, 8.7), Vector3(15.4, 0, -0.4), Vector3(-3.8, 0, -10.1)]:
		var drain := _box(details, "FloorDrain", point + Vector3.UP * 0.0004, Vector3(0.23, 0.0008, 0.23), "steel", false)
		for i: int in 9:
			_box(drain, "DrainSlot", Vector3(-0.088 + i * 0.022, 0.0005, 0), Vector3(0.009, 0.0003, 0.17), "rubber", false)
		for x: float in [-0.099, 0.099]:
			for z: float in [-0.099, 0.099]:
				_cylinder(drain, "ScrewHead", Vector3(x, 0.0008, z), 0.0035, 0.001, "darksteel")
	# Drain plumbing: real curved elbows, union nuts and wall escutcheons.
	for z: float in [-5.5, -1.5]:
		var points: Array[Vector3] = [Vector3(15.7, 2.15, z), Vector3(15.7, 0.74, z)]
		for i: int in 13:
			var angle := PI * i / 12
			points.append(Vector3(15.7 + 0.22 * (1.0 - cos(angle)), 0.74 - 0.22 * sin(angle), z))
		points.append(Vector3(16.14, 1.04, z))
		for i: int in 9:
			var angle := PI * 0.5 * i / 8
			points.append(Vector3(16.32 - 0.18 * cos(angle), 1.04 + 0.18 * sin(angle), z))
		points.append(Vector3(17.72, 1.22, z))
		_pipe(details, "SinkWastePipe", points, 0.034)
		for y: float in [0.91, 1.9]:
			_cylinder(details, "UnionNut", Vector3(15.7, y, z), 0.047, 0.07, "steel")
		_cylinder(details, "WallEscutcheon", Vector3(17.69, 1.22, z), 0.085, 0.018, "steel").rotation.z = PI * 0.5
	# Cabinet seams and kick scuffs convey assembled panels rather than one cube.
	var counter: Node3D = _map.get_node("CounterAndNest")
	for z: float in [-3.3, 3.3]:
		for y: float in [0.16, 1.15, 2.18]:
			_box(counter, "CabinetSeam", Vector3(-7.342, y, z), Vector3(0.002, 0.008, 1.92), "grime", false)
		for offset: float in [-0.92, 0.92]:
			_box(counter, "CabinetSeam", Vector3(-7.342, 1.64, z + offset), Vector3(0.002, 2.94, 0.005), "grime", false)
	# Small hardware along the folded worktop edge is visible from ground level.
	for x: float in [-3.7, -1.4, 1, 3.4, 5.7]:
		for z: float in [-7.51, -4.49]:
			_cylinder(details, "WorktopRivet", Vector3(x, 2.29, z), 0.012, 0.005, "steel").rotation.x = PI * 0.5
	# Rolled ceramic cup with an actual opening and curved handle.
	var mug := _mesh(details, "CoffeeMug", Vector3(1.7, 2.401, -5.6), Detail.lathe([
		Vector2(0.001, 0), Vector2(0.04, 0), Vector2(0.046, 0.008),
		Vector2(0.052, 0.108), Vector2(0.05, 0.114), Vector2(0.045, 0.112),
		Vector2(0.041, 0.018), Vector2(0.001, 0.018)]), "ceramic")
	var handle: Array[Vector3] = []
	for i: int in 17:
		var angle := -PI * 0.5 + PI * i / 16
		handle.append(Vector3(0.047 + 0.035 * cos(angle), 0.06 + 0.033 * sin(angle), 0))
	_pipe(mug, "Handle", handle, 0.007, "ceramic")
	_cylinder(mug, "ColdCoffee", Vector3(0, 0.083, 0), 0.044, 0.001, "grime")
	# Crushed crumbs are batched: they remain inert dressing, distinct from the
	# finite, host-owned pickup nodes. Scatter follows work areas and wall edges.
	var rng := RandomNumberGenerator.new()
	rng.seed = 91047
	var crumbs := MultiMeshInstance3D.new()
	_adopt(crumbs, details, "ScatteredDebris")
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.mesh = Detail.bevel_box(Vector3.ONE, 0.2)
	batch.instance_count = 240
	crumbs.multimesh = batch
	var crumb_material := _solid(Color("b69a6c"), 0.0, 0.95)
	crumb_material.vertex_color_use_as_albedo = true
	crumbs.material_override = crumb_material
	for i: int in batch.instance_count:
		var at := Vector3(rng.randf_range(-5, 6), 0, rng.randf_range(-10.5, -4)) if i < 160 else Vector3(rng.randf_range(-14, -7), 0, rng.randf_range(-4, 4))
		var size := Vector3(rng.randf_range(0.001, 0.006), rng.randf_range(0.0005, 0.002), rng.randf_range(0.002, 0.008))
		at.y = size.y * 0.5 + 0.0001
		batch.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(size), at))
		batch.set_instance_color(i, Color.WHITE * rng.randf_range(0.5, 1.0))
	# Caster forks, axle caps and rubber tread ground the moving cart visually.
	var cart: Node3D = _map.get_node("ServingCart")
	for x: float in [-1.05, 1.05]:
		for z: float in [-1.35, 1.35]:
			for side: float in [-1.0, 1.0]:
				_box(cart, "CasterFork", Vector3(x + side * 0.10, 0.32, z), Vector3(0.028, 0.29, 0.18), "steel", false)
				_cylinder(cart, "AxleCap", Vector3(x + side * 0.12, 0.24, z), 0.045, 0.014, "steel").rotation.z = PI * 0.5
			_cylinder(cart, "SwivelBearing", Vector3(x, 0.51, z), 0.13, 0.05, "steel")

func _clutter() -> void:
	# These placements are in final metres, after the original fixture bake.
	# Reserve x=1.75..4.75, z=-2.05..3.35 for the cart and its shorter ramp.
	_placing_clutter = true
	_materials["crateplastic"] = _solid(Color("394b40"), 0, 0.7)
	_materials["binplastic"] = _solid(Color("475152"), 0, 0.64)
	_materials["yellowplastic"] = _solid(Color("a99346"), 0, 0.72)
	var clutter := _group("ServiceClutter")
	# The central rack creates a low roach route and an obstacle for humans.
	var rack := Node3D.new()
	_adopt(rack, clutter, "ServiceRack")
	rack.position = Vector3(-0.9, 0, 2.35)
	for y: float in [0.05, 0.62, 1.22]:
		_box(rack, "Shelf", Vector3(0, y, 0), Vector3(2.1, 0.02, 0.75), "steel")
	for x: float in [-1.0, 1.0]:
		for z: float in [-0.32, 0.32]:
			_box(rack, "Post", Vector3(x, 0.67, z), Vector3(0.032, 1.34, 0.032), "steel")
			_cylinder(rack, "Foot", Vector3(x, 0.015, z), 0.027, 0.03, "rubber")
	for x: float in [-0.65, 0, 0.65]:
		_delivery_box(rack, Vector3(x, 0.635, 0), Vector3(0.48, 0.32, 0.48))
		for level: int in 4:
			_mesh(rack, "CleanPlate", Vector3(x, 1.232 + level * 0.018, 0), _plate_mesh(), "ceramic")
	for point: Vector3 in [Vector3(-2.92, 0, 1.0), Vector3(-2.84, 0, 1.66), Vector3(-1.2, 0, -2.65), Vector3(3.25, 0, 4.4), Vector3(4.15, 0, -5.35)]:
		_crate(clutter, point)
	_crate(clutter, Vector3(-2.92, 0.36, 1.0))
	_crate(clutter, Vector3(3.25, 0.36, 4.4))
	_crate(clutter, Vector3(0.6, 0, -0.65))
	_delivery_box(clutter, Vector3(0.55, 0, 0.6), Vector3(0.46, 0.32, 0.4))
	_delivery_box(clutter, Vector3(0.55, 0.32, 0.6), Vector3(0.4, 0.26, 0.36))
	_bin(clutter, "MopPail", Vector3(1.45, 0, 1.02), 0.23, 0.46, "yellowplastic")
	# A secondary service table breaks up the south aisle and reconnects to
	# the rack through its open underside; cans above remain static obstacles.
	_box(clutter, "ServiceTableTop", Vector3(-0.55, 0.87, 4.4), Vector3(1.2, 0.04, 0.65), "steel")
	for x: float in [-1.1, 0]:
		for z: float in [4.12, 4.68]:
			_box(clutter, "ServiceTableLeg", Vector3(x, 0.43, z), Vector3(0.035, 0.86, 0.035), "steel")
	for x: float in [-0.85, -0.55, -0.25]:
		_bin(clutter, "ServiceTin", Vector3(x, 0.89, 4.4), 0.08, 0.2, "cream")
	for row: Dictionary in [
		{"at": Vector3(-2.0, 0, 0.95), "size": Vector3(0.6, 0.38, 0.42)},
		{"at": Vector3(-2.0, 0.38, 0.95), "size": Vector3(0.48, 0.29, 0.38)},
		{"at": Vector3(3.45, 0, -5.95), "size": Vector3(0.62, 0.52, 0.52)},
		{"at": Vector3(3.45, 0.52, -5.95), "size": Vector3(0.56, 0.42, 0.48)},
		{"at": Vector3(-6.9, 0, 3.1), "size": Vector3(0.66, 0.46, 0.45)},
		{"at": Vector3(-6.6, 0, -2.9), "size": Vector3(0.6, 0.55, 0.5)}]:
		_delivery_box(clutter, row["at"], row["size"])
	_bin(clutter, "FlourPail", Vector3(-1, 0, -1.15), 0.22, 0.4, "cream")
	_bin(clutter, "WasteBin", Vector3(0.5, 0, 4.7), 0.28, 0.82, "binplastic")
	_bin(clutter, "DishPail", Vector3(6.65, 0, 1.08), 0.24, 0.62, "yellowplastic")
	_bin(clutter, "SupplyPail", Vector3(-6.9, 0, -1.1), 0.23, 0.42, "cream")
	var fridge := _box(clutter, "ReachInFridge", Vector3(5.25, 1.025, -5.87), Vector3(1.2, 2.05, 0.82), "steel")
	for x: float in [-0.292, 0.292]:
		_box(fridge, "DoorSeal", Vector3(x, 0.03, 0.416), Vector3(0.575, 1.86, 0.015), "rubber", false)
		_box(fridge, "Door", Vector3(x, 0.03, 0.431), Vector3(0.56, 1.83, 0.025), "steel", false)
		_box(fridge, "Pull", Vector3(x - signf(x) * 0.22, 0.10, 0.48), Vector3(0.025, 0.38, 0.035), "darksteel", false)
	for i: int in 12:
		_box(fridge, "CompressorVent", Vector3(-0.5 + i * 0.09, -0.935, 0.425), Vector3(0.045, 0.055, 0.008), "rubber", false)
	# Low pans and tubs obstruct the floor while leaving routes around them.
	_tray(clutter, Vector3(-3.0, 0, 0.58), Vector2(0.48, 0.30), 0.045, "steel")
	_tray(clutter, Vector3(-0.35, 0, -2.62), Vector2(0.65, 0.48), 0.23, "binplastic")
	_tray(clutter, Vector3(5.2, 0, 4.35), Vector2(0.48, 0.34), 0.055, "steel")
	# Wire dish racks, tins and condiment bottles break up the worktop runs.
	for x: float in [-0.85, -0.6, -0.35]:
		_bin(clutter, "PrepTin", Vector3(x, Layout.WORKTOP_HEIGHT, -2.95), 0.055, 0.14, "steel")
	for x: float in [0.5, 0.67, 0.84]:
		var bottle := _mesh(clutter, "SqueezeBottle", Vector3(x, Layout.WORKTOP_HEIGHT, -2.88), Detail.lathe([
			Vector2(0.001, 0), Vector2(0.035, 0), Vector2(0.036, 0.15),
			Vector2(0.025, 0.17), Vector2(0.012, 0.18), Vector2(0.004, 0.22), Vector2(0.001, 0.22)]), "yellowplastic" if x < 0.6 else "red")
		var body := StaticBody3D.new()
		_adopt(body, bottle, "CollisionBody")
		body.add_to_group("diner_static", true)
		body.add_to_group("diner_clutter", true)
		var shape := CollisionShape3D.new()
		_adopt(shape, body, "Collision")
		var cylinder := CylinderShape3D.new()
		cylinder.radius = 0.036
		cylinder.height = 0.22
		shape.shape = cylinder
		shape.position.y = 0.11
	var wire_rack := Node3D.new()
	_adopt(wire_rack, clutter, "DishDryingRack")
	wire_rack.position = Vector3(6.58, Layout.WORKTOP_HEIGHT, 2.45)
	for i: int in 9:
		_pipe(wire_rack, "Wire", [Vector3(-0.30 + i * 0.075, 0.02, -0.21), Vector3(-0.30 + i * 0.075, 0.02, 0.21)], 0.004)
	for z: float in [-0.21, 0.21]:
		_pipe(wire_rack, "Rail", [Vector3(-0.32, 0.02, z), Vector3(0.32, 0.02, z)], 0.006)
	for i: int in 5:
		var plate := _mesh(wire_rack, "StandingPlate", Vector3(-0.22 + i * 0.11, 0.15, 0), _plate_mesh(), "ceramic")
		plate.rotation.z = PI * 0.42
	_box(wire_rack, "RackClearance", Vector3(0, 0.12, 0), Vector3(0.65, 0.22, 0.36), "steel").get_node("Mesh").visible = false
	_placing_clutter = false

func _delivery_box(parent: Node3D, at: Vector3, size: Vector3) -> void:
	var carton := _box(parent, "DeliveryCarton", at + Vector3.UP * size.y * 0.5, size, "cardboard")
	_box(carton, "Tape", Vector3(0, size.y * 0.5 + 0.0006, 0), Vector3(0.055, 0.001, size.z), "paper", false)
	_box(carton, "FoldSeam", Vector3(0, size.y * 0.5 + 0.0012, 0), Vector3(0.002, 0.0005, size.z), "grime", false)
	_label(carton, "Stamp", "NIGHT OWL\nDRY GOODS\nKEEP DRY", Vector3(0, 0, size.z * 0.5 + 0.001), 24, 0.0015, Color("30291c"))

func _crate(parent: Node3D, at: Vector3) -> void:
	var crate := Node3D.new()
	_adopt(crate, parent, "MilkCrate")
	crate.position = at
	_box(crate, "Base", Vector3(0, 0.05, 0), Vector3(0.54, 0.02, 0.42), "crateplastic")
	for x: float in [-0.255, 0.255]:
		for z: float in [-0.195, 0.195]:
			_box(crate, "Corner", Vector3(x, 0.18, z), Vector3(0.03, 0.36, 0.03), "crateplastic")
	for y: float in [0.09, 0.22, 0.345]:
		for z: float in [-0.20, 0.20]:
			_box(crate, "Rib", Vector3(0, y, z), Vector3(0.54, 0.024, 0.018), "crateplastic")
		for x: float in [-0.26, 0.26]:
			_box(crate, "Rib", Vector3(x, y, 0), Vector3(0.018, 0.024, 0.42), "crateplastic")
	for x: float in [-0.16, -0.08, 0, 0.08, 0.16]:
		for z: float in [-0.20, 0.20]:
			_box(crate, "Slat", Vector3(x, 0.22, z), Vector3(0.013, 0.25, 0.015), "crateplastic")

func _bin(parent: Node3D, node_name: String, at: Vector3, radius: float, height: float, material: String) -> void:
	var body := StaticBody3D.new()
	_adopt(body, parent, node_name)
	body.position = at
	body.add_to_group("diner_static", true)
	body.add_to_group("diner_clutter", true)
	_mesh(body, "Shell", Vector3.ZERO, Detail.lathe([
		Vector2(0.001, 0), Vector2(radius * 0.82, 0), Vector2(radius, height * 0.95),
		Vector2(radius * 1.04, height * 0.96), Vector2(radius * 1.04, height),
		Vector2(radius * 0.94, height), Vector2(radius * 0.78, 0.025), Vector2(0.001, 0.025)]), material)
	var collision := CollisionShape3D.new()
	_adopt(collision, body, "Collision")
	var shape := CylinderShape3D.new()
	shape.radius = radius * 1.04
	shape.height = height
	collision.shape = shape
	collision.position.y = height * 0.5
	# A lid makes the simple solid collision agree with the visual volume.
	_cylinder(body, "Lid", Vector3(0, height, 0), radius * 1.04, 0.016, material)
	_box(body, "LidGrip", Vector3(0, height + 0.02, 0), Vector3(radius * 0.6, 0.025, 0.04), material, false)

func _tray(parent: Node3D, at: Vector3, size: Vector2, height: float, material: String) -> void:
	var tray := Node3D.new()
	_adopt(tray, parent, "BusTray")
	tray.position = at
	_box(tray, "Base", Vector3(0, 0.006, 0), Vector3(size.x, 0.012, size.y), material)
	for side: float in [-1.0, 1.0]:
		_box(tray, "Side", Vector3(side * size.x * 0.5, height * 0.5, 0), Vector3(0.008, height, size.y), material)
		_box(tray, "Side", Vector3(0, height * 0.5, side * size.y * 0.5), Vector3(size.x, height, 0.008), material)
