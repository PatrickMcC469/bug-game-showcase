extends "res://scripts/tools/diner_makeover.gd"
## Offline art pass. Packed, static set dressing; no runtime spawns or match state.
const GRAPHICS := "res://assets/textures/diner/graphics/"
const SCANS := "res://assets/models/diner/"
var _print_materials: Dictionary[String, StandardMaterial3D] = {}
var _scan_materials: Dictionary[int, Material] = {}
var _random := RandomNumberGenerator.new()

func dress_map(target: Node3D) -> void:
	map = target
	_random.seed = 9426
	_restore_batched_sources()
	_remove("Atmosphere")
	for key: String in ["tile", "wall", "steel", "cream", "red", "wood", "rubber", "cardboard"]:
		materials[key] = _material(key)
	materials["asphalt"] = _scan_material("asphalt_02", 3.0, 0.7)
	materials["pavement"] = _scan_material("concrete_pavement", 2.0, 0.55)
	materials["plaster"] = _scan_material("painted_plaster_wall", 2.0, 0.45)
	materials["brick"] = _scan_material("red_brick", 2.0, 0.65)
	materials["vinyl"] = _scan_material("leather_red_02", 0.75, 0.4, "coll1")
	materials["weathered_green"] = _scan_material("green_metal_rust", 1.4, 0.5)
	materials["paint"] = _solid(Color("324b40"), 0.53)
	materials["brass"] = _solid(Color("b99856"), 0.35)
	materials["brass"].metallic = 0.72
	materials["ceramic"] = _solid(Color("d8d4bb"), 0.22)
	materials["coffee"] = _solid(Color("21130d"), 0.15)
	materials["mustard"] = _solid(Color("ba8e2f"), 0.42)
	materials["ketchup"] = _solid(Color("8c3020"), 0.4)
	materials["paper"] = _solid(Color("d5ccb1"), 0.89)
	materials["darksteel"] = _solid(Color("333b39"), 0.48)
	materials["darksteel"].metallic = 0.65
	materials["steel"] = _brushed_steel()
	var kraft := ShaderMaterial.new()
	kraft.shader = load("res://assets/shaders/diner_kraft.gdshader")
	materials["kraft"] = kraft
	materials["bulb"] = _solid(Color("ffe5bd"), 0.3)
	materials["bulb"].emission_enabled = true
	materials["bulb"].emission = Color("ffc67d")
	materials["bulb"].emission_energy_multiplier = 2.5
	_retouch()
	var atmosphere := _group(map, "Atmosphere")
	var dining := _group(atmosphere, "FrontOfHouse")
	_dining_finish(dining)
	_front_door(dining)
	_coffee_bar(dining)
	_table_settings(dining)
	var kitchen := _group(atmosphere, "KitchenLife")
	_cleaning_corner(kitchen)
	_kitchen_dressing(kitchen)
	var pantry := _group(atmosphere, "StockRoom")
	_pantry_stock(pantry)
	var outside := _group(atmosphere, "ServiceYard")
	_yard(outside)
	_frontage(outside)
	_surface_history(atmosphere)
	_lighting_finish(atmosphere)
	# Bake small manufactured parts per room/material. Imported meshes keep
	# their shared mesh resources and importer-generated LODs.
	for zone: Node3D in [dining, kitchen, pantry, outside]: _batch_details(zone)
	_batch_fixtures(atmosphere)
	preload("res://scripts/tools/diner_surface_cleanup.gd").new().apply(map)
	print("DINER ATMOSPHERE: static dressing packed")

func _scan_material(asset: String, meters: float, strength: float, color_map: String = "diff") -> StandardMaterial3D:
	var result := _solid(Color.WHITE, 1.0)
	var prefix := "res://assets/textures/diner/" + asset
	result.albedo_texture = load(prefix + "_" + color_map + "_2k.jpg")
	result.normal_enabled = true
	result.normal_texture = load(prefix + "_nor_gl_2k.jpg")
	result.normal_scale = strength
	result.roughness_texture = load(prefix + "_rough_2k.jpg")
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	result.uv1_triplanar = true
	result.uv1_scale = Vector3.ONE / meters
	return result

func _brushed_steel() -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = load("res://assets/shaders/diner_brushed_metal.gdshader")
	result.set_shader_parameter("tint", Color("a5aaa9"))
	result.set_shader_parameter("base_roughness", 0.33)
	return result

func _retouch() -> void:
	var outdoors := map.get_node("RestaurantExpansion/Exterior")
	for child: Node in outdoors.get_children():
		if child is not Node3D: continue
		var name := str(child.name)
		var key := ""
		if name.ends_with("Floor") or "Passage" in name or name.ends_with("Ground"): key = "asphalt"
		elif name == "FrontWalk": key = "pavement"
		elif name.begins_with("BoundaryWall"): key = "brick"
		elif name == "Dumpster": key = "weathered_green"
		if not key.is_empty(): _replace_material(child, materials[key])
	var shell := map.get_node("RestaurantExpansion/Shell")
	for child: Node in shell.get_children():
		if str(child.name).begins_with("DiningSide") or str(child.name).ends_with("Ceiling"):
			_replace_material(child, materials["plaster"])
	_replace_material(map.get_node("Room/Ceiling"), materials["plaster"])
	_replace_material(map.get_node("RestaurantExpansion/WalkInPantry/Ceiling"), materials["plaster"])
	for child: Node in map.get_node("RestaurantExpansion/DiningRoom").find_children("*", "MeshInstance3D", true, false):
		var part := str(child.get_parent().name)
		if part in ["Seat", "Back", "WaitingBench", "WaitingBench2"]: child.material_override = materials["vinyl"]
	for child: Node in map.get_node("CounterAndNest").get_children():
		if str(child.name).begins_with("StoolSeat"):
			child.material_override = materials["vinyl"]
			child.mesh = Detail.lathe([Vector2(0, -0.056), Vector2(0.265, -0.056), Vector2(0.295, -0.040), Vector2(0.302, 0.01), Vector2(0.291, 0.046), Vector2(0.255, 0.056), Vector2(0, 0.056)])
		elif str(child.name).begins_with("StoolBase"):
			child.material_override = materials["steel"]
			child.mesh = Detail.lathe([Vector2(0, -0.036), Vector2(0.278, -0.036), Vector2(0.293, -0.021), Vector2(0.273, 0.0), Vector2(0.12, 0.026), Vector2(0.055, 0.036)])
		elif str(child.name).begins_with("StoolPost"): child.material_override = materials["steel"]
		elif str(child.name).begins_with("CounterCabinet"): _replace_material(child, materials["paint"])
	for child: MeshInstance3D in map.find_children("*", "MeshInstance3D", true, false):
		var part := str(child.get_parent().name)
		if part.begins_with("SupplyCarton") or part.begins_with("DeliveryCarton") or part.begins_with("IngredientCarton"):
			if child.name == &"Mesh": child.material_override = materials["kraft"]

func _replace_material(node: Node, material: Material) -> void:
	for child: Node in node.find_children("*", "MeshInstance3D", true, false): child.material_override = material

func _part(parent: Node3D, node_name: String, at: Vector3, geometry: Mesh, material: String) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	_add(part, parent, node_name)
	part.position = at
	part.mesh = geometry
	part.material_override = materials[material]
	return part

func _lathe(parent: Node3D, node_name: String, at: Vector3, profile: Array[Vector2], material: String) -> MeshInstance3D:
	return _part(parent, node_name, at, Detail.lathe(profile, 40), material)

func _pipe(parent: Node3D, node_name: String, points: Array[Vector3], radius: float, material: String = "steel") -> MeshInstance3D:
	return _part(parent, node_name, Vector3.ZERO, Detail.pipe(points, radius, 12), material)

func _sphere(parent: Node3D, node_name: String, at: Vector3, radius: float, material: String) -> MeshInstance3D:
	var geometry := SphereMesh.new()
	geometry.radius = radius
	geometry.height = radius * 2
	geometry.radial_segments = 24
	geometry.rings = 12
	return _part(parent, node_name, at, geometry, material)

func _print(key: String) -> StandardMaterial3D:
	if not _print_materials.has(key):
		var material := _solid(Color.WHITE, 0.81)
		material.albedo_texture = load(GRAPHICS + key + ".png")
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_print_materials[key] = material
	return _print_materials[key]

func _graphic(parent: Node3D, key: String, at: Vector3, size: Vector2, angles: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	_add(mesh, parent, key.to_pascal_case())
	var quad := QuadMesh.new()
	quad.size = size
	mesh.mesh = quad
	mesh.material_override = _print(key)
	mesh.position = at
	mesh.rotation = angles
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh

func _framed_sign(parent: Node3D, key: String, at: Vector3, size: Vector2, yaw: float = 0) -> Node3D:
	var sign := _group(parent, key.to_pascal_case() + "Frame")
	sign.position = at
	sign.rotation.y = yaw
	_box(sign, "Backing", Vector3.ZERO, Vector3(size.x + 0.07, size.y + 0.07, 0.034), "darksteel", false)
	_graphic(sign, key, Vector3(0, 0, 0.02), size)
	for x: float in [-size.x / 2, size.x / 2]:
		for y: float in [-size.y / 2, size.y / 2]: _sphere(sign, "Rivet", Vector3(x, y, 0.024), 0.005, "brass")
	return sign

func _scan(parent: Node3D, asset: String, at: Vector3, height: float = 0, yaw: float = 0, solid: bool = true, selected: String = "") -> Node3D:
	var source := load(SCANS + asset + "/" + asset + "_2k.gltf").instantiate() as Node3D
	var parts: Array[MeshInstance3D] = []
	var poses: Array[Transform3D] = []
	var bounds := AABB()
	var first := true
	for child: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		if not selected.is_empty() and not str(child.name).contains(selected): continue
		var pose := child.transform
		var ancestor := child.get_parent()
		while ancestor != source:
			if ancestor is Node3D: pose = ancestor.transform * pose
			ancestor = ancestor.get_parent()
		var box := pose * child.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
		parts.append(child)
		poses.append(pose)
	assert(not first, "Missing scanned mesh: " + asset + " / " + selected)
	var factor := height / bounds.size.y if height > 0 else 1.0
	var offset := Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z)
	var normalization := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * factor), offset * factor)
	# Solid shapes are baked into unit-scale bodies; visual scale is independent.
	var body: Node3D = StaticBody3D.new() if solid else Node3D.new()
	_add(body, parent, asset.to_pascal_case())
	body.position = at
	body.rotation.y = yaw
	body.set_meta("scanned_asset", asset)
	if solid: body.add_to_group("diner_static", true)
	for i: int in parts.size():
		var original := parts[i]
		var part := MeshInstance3D.new()
		_add(part, body, str(original.name))
		part.mesh = original.mesh
		part.transform = normalization * poses[i]
		for surface: int in part.mesh.get_surface_count():
			var material := original.get_active_material(surface)
			if material == null: continue
			var id := material.get_instance_id()
			if not _scan_materials.has(id):
				var filtered := material.duplicate() as BaseMaterial3D
				filtered.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				_scan_materials[id] = filtered
			part.set_surface_override_material(surface, _scan_materials[id])
		if solid:
			var shape := part.mesh.create_convex_shape(true, true)
			var points := shape.points
			for p: int in points.size(): points[p] = part.transform * points[p]
			shape.points = points
			var collision := CollisionShape3D.new()
			collision.shape = shape
			_add(collision, body, "Collision")
	source.free()
	return body

func _dining_finish(parent: Node3D) -> void:
	# Front-facing overlays leave the kitchen tile and all doorway collision intact.
	for entry: Vector2 in [Vector2(-6.15, 3.9), Vector2(0, 4), Vector2(6.15, 3.9)]:
		_box(parent, "PlasterFront", Vector3(entry.x, 2.08, 6.849), Vector3(entry.y, 2.4, 0.014), "plaster", false)
		_box(parent, "PaintedWainscot", Vector3(entry.x, 0.48, 6.86), Vector3(entry.y, 0.92, 0.02), "paint", false)
		_box(parent, "DadoRail", Vector3(entry.x, 0.96, 6.88), Vector3(entry.y, 0.06, 0.045), "wood", false)
	for x: float in [-7.987, 7.987]:
		_box(parent, "WallPanel", Vector3(x, 0.55, 10), Vector3(0.02, 1.08, 6.35), "paint", false)
		_box(parent, "DadoRail", Vector3(x, 1.12, 10), Vector3(0.05, 0.06, 6.35), "wood", false)
		for z: float in [7.1, 8.1, 9.1, 10.1, 11.1, 12.1, 13.1]:
			_box(parent, "PanelStile", Vector3(x - signf(x) * 0.016, 0.56, z), Vector3(0.018, 0.98, 0.045), "wood", false)
	_framed_sign(parent, "night_menu", Vector3(0, 2.16, 6.9), Vector2(3.55, 1.775))
	_framed_sign(parent, "incident", Vector3(-6.14, 2.05, 6.9), Vector2(0.64, 0.68))
	# A tiny workplace shrine; the duck is a scanned, normally scaled desk toy.
	_box(parent, "GaryShelf", Vector3(6.2, 1.5, 6.99), Vector3(0.9, 0.045, 0.28), "wood")
	_scan(parent, "rubber_duck_toy", Vector3(6.2, 1.525, 7.0), 0.22, PI * 0.88, false)
	_framed_sign(parent, "employee", Vector3(6.2, 1.26, 6.94), Vector2(0.68, 0.28))
	for x: float in [-7.3, 7.3]:
		# Curved chrome coat hook mounted above the outer furniture routes.
		_pipe(parent, "CoatHook", [Vector3(x, 1.7, 6.91), Vector3(x, 1.68, 7.04), Vector3(x, 1.75, 7.07)], 0.012)

func _front_door(parent: Node3D) -> void:
	var original := map.get_node("RestaurantExpansion/Shell/FrontDoorOpen") as Node3D
	original.get_node("Mesh").visible = false
	var door := _group(parent, "FrontDoorFinish")
	door.transform = original.transform
	# Glazing shares the original closed collision plane; this is a static door.
	for z: float in [-0.73, 0.73]: _box(door, "Stile", Vector3(0, 0, z), Vector3(0.077, 2.5, 0.14), "weathered_green", false)
	_box(door, "TopRail", Vector3(0, 1.17, 0), Vector3(0.077, 0.16, 1.32), "weathered_green", false)
	_box(door, "LowerPanel", Vector3(0, -0.85, 0), Vector3(0.077, 0.80, 1.32), "weathered_green", false)
	_box(door, "LockRail", Vector3(0, -0.39, 0), Vector3(0.085, 0.12, 1.32), "weathered_green", false)
	var glass := _solid(Color(0.44, 0.57, 0.52, 0.15), 0.18)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	materials["door_glass"] = glass
	_box(door, "Glazing", Vector3(0, 0.36, 0), Vector3(0.014, 1.43, 1.30), "door_glass", false)
	for side: float in [-1, 1]:
		_box(door, "KickPlate", Vector3(side * 0.043, -1.04, 0), Vector3(0.008, 0.30, 1.26), "steel", false)
		_pipe(door, "PushBar", [Vector3(side * 0.05, -0.24, -0.53), Vector3(side * 0.092, -0.24, -0.53), Vector3(side * 0.092, -0.24, 0.53), Vector3(side * 0.05, -0.24, 0.53)], 0.018)

func _coffee_bar(parent: Node3D) -> void:
	var bar := _group(parent, "GraveyardCoffee")
	bar.position = Vector3(-0.4, 0, 8.35)
	# Continuous edge profile unifies the three existing counter sections.
	_box(bar, "CounterNose", Vector3(0, 1.078, 0.503), Vector3(3.62, 0.065, 0.022), "steel", false)
	for x: float in [-1.19, 0, 1.19]:
		_box(bar, "CabinetInset", Vector3(x, 0.58, 0.469), Vector3(1.01, 0.81, 0.014), "wood", false)
		for dx: float in [-0.49, 0.49]:
			_box(bar, "CabinetTrim", Vector3(x + dx, 0.58, 0.48), Vector3(0.033, 0.87, 0.023), "brass", false)
	_pipe(bar, "FootRail", [Vector3(-1.75, 0.22, 0.69), Vector3(1.75, 0.22, 0.69)], 0.025, "brass")
	var coffee := _group(bar, "CoffeeUrn")
	coffee.position = Vector3(-1.03, 1.126, -0.09)
	_box(coffee, "Base", Vector3(0, 0.026, 0), Vector3(0.32, 0.05, 0.34), "rubber", false)
	_lathe(coffee, "Urn", Vector3.ZERO, [Vector2(0, 0.04), Vector2(0.115, 0.04), Vector2(0.14, 0.065), Vector2(0.145, 0.40), Vector2(0.139, 0.43), Vector2(0, 0.43)], "steel")
	_lathe(coffee, "Lid", Vector3.ZERO, [Vector2(0, 0.43), Vector2(0.151, 0.43), Vector2(0.15, 0.446), Vector2(0.11, 0.477), Vector2(0, 0.485)], "steel")
	_sphere(coffee, "LidKnob", Vector3(0, 0.493, 0), 0.028, "rubber")
	for x: float in [-0.17, 0.17]: _pipe(coffee, "Handle", [Vector3(x * 0.77, 0.35, 0), Vector3(x, 0.35, 0), Vector3(x, 0.28, 0), Vector3(x * 0.77, 0.28, 0)], 0.013, "rubber")
	_pipe(coffee, "Tap", [Vector3(0, 0.13, 0.139), Vector3(0, 0.13, 0.195), Vector3(0, 0.106, 0.2)], 0.012)
	_box(coffee, "TapHandle", Vector3(0, 0.158, 0.185), Vector3(0.018, 0.046, 0.012), "rubber", false)
	_graphic(coffee, "coffee", Vector3(0, 0.28, 0.146), Vector2(0.19, 0.119))
	for i: int in 3: _mug(bar, Vector3(-0.68 + i * 0.135, 1.124, 0.02), i * 0.5)
	_scan(bar, "plastic_thermos", Vector3(0.82, 1.124, -0.19), 0, -0.2, false)
	_bottle(bar, Vector3(1.31, 1.123, 0.11), "mustard", 1.0)
	_bottle(bar, Vector3(1.12, 1.123, 0.16), "ketchup", 1.15)
	_graphic(bar, "receipt", Vector3(0.23, 1.124, 0.23), Vector2(0.095, 0.17), Vector3(-PI / 2, 0.14, 0))
	_decal(parent, "coffee_ring", Vector3(0.08, 1.139, 8.40), Vector2(0.105, 0.105), 0.035)
	# A second oversized duck has been left under a table, creating insect cover.
	_scan(parent, "rubber_duck_toy", Vector3(5.94, 0, 11.53), 0.43, 0.7)

func _mug(parent: Node3D, at: Vector3, yaw: float = 0) -> void:
	var cup := _group(parent, "DinerMug")
	cup.position = at
	cup.rotation.y = yaw
	_lathe(cup, "GlazedCup", Vector3.ZERO, [Vector2(0, 0), Vector2(0.028, 0), Vector2(0.036, 0.009), Vector2(0.041, 0.086), Vector2(0.038, 0.091), Vector2(0.034, 0.086), Vector2(0.029, 0.015), Vector2(0, 0.015)], "ceramic")
	_pipe(cup, "Handle", [Vector3(0.034, 0.071, 0), Vector3(0.057, 0.076, 0), Vector3(0.069, 0.059, 0), Vector3(0.063, 0.033, 0), Vector3(0.034, 0.029, 0)], 0.006, "ceramic")
	_lathe(cup, "ColdCoffee", Vector3.ZERO, [Vector2(0.034, 0.066), Vector2(0, 0.066)], "coffee")

func _bottle(parent: Node3D, at: Vector3, material: String, factor: float = 1) -> void:
	var bottle := _group(parent, "SqueezeBottle")
	bottle.position = at
	bottle.scale = Vector3.ONE * factor
	_lathe(bottle, "Bottle", Vector3.ZERO, [Vector2(0, 0), Vector2(0.026, 0), Vector2(0.029, 0.01), Vector2(0.027, 0.115), Vector2(0.022, 0.13), Vector2(0.022, 0.145), Vector2(0.011, 0.15), Vector2(0.002, 0.19), Vector2(0, 0.19)], material)
	_lathe(bottle, "CapSeam", Vector3.ZERO, [Vector2(0.0225, 0.131), Vector2(0.0225, 0.14)], "cream")

func _table_settings(parent: Node3D) -> void:
	for x: float in [-5.5, 5.5]:
		for z: float in [8.4, 11.5]:
			var table := _group(parent, "LateTable")
			table.position = Vector3(x, 0, z)
			# Chrome perimeter and upholstery piping catch practical highlights.
			for dz: float in [-0.428, 0.428]: _box(table, "ChromeEdge", Vector3(0, 0.76, dz), Vector3(1.64, 0.045, 0.01), "steel", false)
			for dx: float in [-0.827, 0.827]: _box(table, "ChromeEdge", Vector3(dx, 0.76, 0), Vector3(0.012, 0.045, 0.83), "steel", false)
			_mug(table, Vector3(-0.45, 0.796, 0.21), 1.1)
			_mug(table, Vector3(0.58, 0.796, -0.15), -2.0)
			_bottle(table, Vector3(-0.05, 0.796, -0.17), "ketchup")
			_bottle(table, Vector3(0.04, 0.796, -0.19), "mustard", 0.86)
			_lathe(table, "Plate", Vector3(0.19, 0.80, 0.02), [Vector2(0, 0), Vector2(0.07, 0), Vector2(0.103, 0.008), Vector2(0.107, 0.015), Vector2(0.10, 0.017), Vector2(0.065, 0.006), Vector2(0, 0.006)], "ceramic")
			_graphic(table, "receipt", Vector3(0.45, 0.807, 0.19), Vector2(0.075, 0.133), Vector3(-PI / 2, -0.3, 0))
			for i: int in 7: _box(table, "Napkin", Vector3(-0.4, 0.93 + i * 0.0015, 0), Vector3(0.09, 0.001, 0.066), "paper", false)
			_decal(parent, "coffee_ring", Vector3(x - 0.22, 0.819, z + 0.19), Vector2(0.10, 0.10), 0.04)
	# A lost shoe and a tiny rent reminder are discoverable at bug height.
	_scan(parent, "rubber_boots", Vector3(-6.08, 0, 11.48), 0, 0.5, true, "dirty_l")
	_framed_sign(parent, "roach_notice", Vector3(-5.88, 0.15, 11.48), Vector2(0.05, 0.023), 0.4)

func _cleaning_corner(parent: Node3D) -> void:
	var station := _group(parent, "UnfinishedMopping")
	station.position = Vector3(6.95, 0, 4.52)
	# The janitor trolley creates an alternate route along the east wall.
	for x: float in [-0.22, 0.22]:
		for z: float in [-0.19, 0.19]:
			var wheel := _lathe(station, "Caster", Vector3(x, 0.057, z), [Vector2(0, -0.02), Vector2(0.055, -0.02), Vector2(0.055, 0.02), Vector2(0, 0.02)], "rubber")
			wheel.rotation.z = PI / 2
	_box(station, "TrolleyBase", Vector3(0, 0.13, 0), Vector3(0.55, 0.055, 0.49), "darksteel")
	_lathe(station, "Bucket", Vector3(0, 0.16, 0), [Vector2(0, 0), Vector2(0.195, 0), Vector2(0.228, 0.32), Vector2(0.219, 0.336), Vector2(0.206, 0.32), Vector2(0.18, 0.018), Vector2(0, 0.018)], "mustard")
	_box(station, "BucketCollision", Vector3(0, 0.32, 0), Vector3(0.4, 0.34, 0.4), "mustard").get_node("Mesh").visible = false
	_box(station, "Wringer", Vector3(0, 0.50, -0.13), Vector3(0.33, 0.12, 0.17), "mustard", false)
	for i: int in 9: _box(station, "WringerSlot", Vector3(-0.125 + i * 0.03, 0.545, -0.039), Vector3(0.013, 0.06, 0.003), "darksteel", false)
	_pipe(station, "PushHandle", [Vector3(-0.21, 0.15, -0.24), Vector3(-0.21, 0.83, -0.24), Vector3(0.21, 0.83, -0.24), Vector3(0.21, 0.15, -0.24)], 0.015)
	_scan(parent, "plastic_broom", Vector3(7.55, 0, 5.0), 0, -PI / 2)
	_scan(parent, "rubber_boots", Vector3(7.48, 0, 3.45), 0, -PI / 2, true, "dirt")
	_caution_sign(parent, Vector3(6.10, 0, 4.86), -0.3)
	_decal(parent, "spill", Vector3(6.12, 0.05, 3.87), Vector2(1.3, 0.76), 0.12)
	_scan(parent, "rubber_duck_toy", Vector3(6.89, 0.50, 4.63), 0.11, -1.2, false)

func _caution_sign(parent: Node3D, at: Vector3, yaw: float) -> void:
	var sign := _group(parent, "WetFloorSign")
	sign.position = at - Vector3.UP * 0.0205
	sign.rotation.y = yaw
	for side: float in [-1, 1]:
		var panel := _group(sign, "Panel")
		panel.position = Vector3(0, 0.335, side * 0.13)
		panel.rotation.x = side * 0.36
		_box(panel, "MoldedPlastic", Vector3.ZERO, Vector3(0.34, 0.59, 0.017), "mustard")
		_graphic(panel, "caution", Vector3(0, 0, side * 0.01), Vector2(0.30, 0.36), Vector3(0, PI if side < 0 else 0, 0))
		for x: float in [-0.15, 0.15]: _box(panel, "Leg", Vector3(x, -0.3, 0), Vector3(0.04, 0.065, 0.025), "mustard")
	_box(sign, "Hinge", Vector3(0, 0.613, 0), Vector3(0.32, 0.025, 0.05), "mustard", false)

func _kitchen_dressing(parent: Node3D) -> void:
	# Existing appliances, oven controls and the cart's swept aisle stay untouched.
	_scan(parent, "plastic_crate_02", Vector3(5.93, 0, 0.08), 0, -0.2)
	_scan(parent, "plastic_crate_02", Vector3(5.95, 0.255, 0.08), 0, -0.18)
	_scan(parent, "plastic_thermos", Vector3(-5.64, 0.945, 0.01), 0, 0.8, false)
	_scan(parent, "long_life_food", Vector3(-5.02, 0.945, -0.23), 0, 0.1, false)
	# Utility pipes and collars support the scale of the original blockout walls.
	for z: float in [-4.0, -2.8, -1.5, 0.2, 1.8]:
		_pipe(parent, "WallConduit", [Vector3(7.94, 0.18, z), Vector3(7.94, 2.85, z), Vector3(7.65, 3.12, z)], 0.014, "darksteel")
		for y: float in [0.36, 1.42, 2.65]: _box(parent, "PipeClip", Vector3(7.943, y, z), Vector3(0.027, 0.03, 0.06), "steel", false)
	for x: float in [-5.1, -2.5, 0.15, 2.4]:
		_box(parent, "ExtractorFilterFrame", Vector3(x, 2.078, -5.78), Vector3(1.65, 0.018, 1.03), "darksteel", false)
		for i: int in 13: _box(parent, "Baffle", Vector3(x - 0.72 + i * 0.12, 2.061, -5.78), Vector3(0.045, 0.019, 0.96), "steel", false)
	_framed_sign(parent, "incident", Vector3(7.968, 1.95, 3.6), Vector2(0.47, 0.50), -PI / 2)
	# Small cloth folds on the prep shelf, with real thickness and varied silhouette.
	for i: int in 5:
		_box(parent, "FoldedBarTowel", Vector3(-5.25 + sin(i * 1.1) * 0.004, 0.947 + i * 0.0035, 0.31), Vector3(0.24, 0.004, 0.18), "paper", false)

func _pantry_stock(parent: Node3D) -> void:
	# Replaces a few blank cartons with packaged stock; low crawl shelves are kept.
	var pantry := map.get_node("RestaurantExpansion/WalkInPantry")
	for rack: Node in pantry.get_children():
		if "Rack" in str(rack.name):
			for carton: Node in rack.get_children():
				if not str(carton.name).begins_with("SupplyCarton"): continue
				if str(rack.name).begins_with("BackRack") and carton.position.y > 0.95: continue
				var bounds: AABB = carton.get_node("Mesh").mesh.get_aabb()
				var at: Vector3 = carton.global_position
				var west := str(rack.name).begins_with("DryGoodsRack")
				var front := str(rack.name).begins_with("FrontRack")
				at += Vector3(bounds.size.x / 2 + 0.001, 0, 0) if west else Vector3(0, 0, (bounds.size.z / 2 + 0.001) * (-1 if front else 1))
				var width := minf(0.24, (bounds.size.z if west else bounds.size.x) * 0.75)
				_graphic(parent, "case_label", at, Vector2(width, width * 0.5), Vector3(0, PI / 2 if west else (PI if front else 0), 0))
		if not str(rack.name).begins_with("BackRack"): continue
		for child: Node in rack.get_children():
			if (str(child.name).begins_with("SupplyCarton") or str(child.name).begins_with("CartonTape")) and child.position.y > 0.95:
				child.visible = false
				if child is StaticBody3D: child.collision_layer = 0
	for y: float in [1.374, 1.954]:
		for x: float in [-9.92, -9.34, -8.76]:
			_scan(parent, "long_life_food", Vector3(x, y, -5.22), 0, _random.randf_range(-0.10, 0.10), false)
	for i: int in 3:
		_scan(parent, "plastic_crate_02", Vector3(-8.64, i * 0.256, -4.47), 0, 0.03 * i)
	_scan(parent, "plastic_thermos", Vector3(-11.6, 0.793, -4.9), 0, 0.4, false)
	_scan(parent, "plastic_broom", Vector3(-8.58, 0, -0.35), 0, -0.9)
	_framed_sign(parent, "roach_notice", Vector3(-10.80, 0.247, -4.144), Vector2(0.082, 0.038))
	_graphic(parent, "receipt", Vector3(-10.42, 0.0008, -3.89), Vector2(0.10, 0.177), Vector3(-PI / 2, 0.8, 0))

func _pallet(parent: Node3D, at: Vector3, yaw: float = 0) -> Node3D:
	var pallet := _group(parent, "DeliveryPallet")
	pallet.position = at
	pallet.rotation.y = yaw
	# Open runners provide a 9 cm high route across its 1.2 m width.
	for z: float in [-0.44, 0, 0.44]:
		_box(pallet, "Runner", Vector3(0, 0.018, z), Vector3(1.2, 0.035, 0.095), "wood")
		for x: float in [-0.48, 0, 0.48]: _box(pallet, "Block", Vector3(x, 0.079, z), Vector3(0.12, 0.088, 0.095), "wood")
	for x: float in [-0.51, -0.34, -0.17, 0, 0.17, 0.34, 0.51]:
		_box(pallet, "Slat", Vector3(x, 0.135, 0), Vector3(0.14, 0.024, 0.98), "wood")
		for z: float in [-0.43, 0.43]: _sphere(pallet, "Nail", Vector3(x, 0.148, z), 0.003, "darksteel")
	return pallet

func _yard(parent: Node3D) -> void:
	# Dressing is placed around the perimeter, clear of the truck ramp and doors.
	_pallet(parent, Vector3(-6.8, 0, -8.14), 0.1)
	for row: int in 2:
		for i: int in 3: _scan(parent, "plastic_crate_02", Vector3(-7.08 + row * 0.54, 0.148 + i * 0.254, -8.13), 0, 0.08 + row * 0.06)
	_pallet(parent, Vector3(10.65, 0, -8.92), -0.18)
	_scan(parent, "plastic_crate_02", Vector3(10.45, 0.148, -8.9), 0, -0.2)
	_scan(parent, "trashbag", Vector3(10.93, 0.148, -8.94), 0.53, 1.3)
	for i: int in 6:
		var at := Vector3(-11.87 + (i % 2) * 0.61, 0, -8.05 - (i / 2) * 0.59)
		_scan(parent, "trashbag", at, _random.randf_range(0.43, 0.63), _random.randf_range(-PI, PI))
	for i: int in 2: _scan(parent, "trashbag", Vector3(-9.59 + i * 0.68, 0, -10.97), 0.61, float(i))
	var dumpster := _group(parent, "DumpsterHardware")
	dumpster.position = Vector3(-10.1, 0, -9.8)
	for x: float in [-0.89, -0.44, 0, 0.44, 0.89]:
		_box(dumpster, "Rib", Vector3(x, 0.89, 0.636), Vector3(0.045, 1.19, 0.034), "weathered_green", false)
	for z: float in [-0.54, 0.54]:
		_box(dumpster, "LiftPocket", Vector3(1.065, 0.98, z), Vector3(0.06, 0.19, 0.17), "darksteel", false)
	for i: int in 10: _box(dumpster, "LidRib", Vector3(-0.97 + i * 0.216, 1.632, 0), Vector3(0.03, 0.012, 1.22), "rubber", false)
	# Exposed brick outer skins stop the kitchen tiles wrapping onto the building.
	for entry: Vector2 in [Vector2(-1.4, 13.4), Vector2(7.6, 1.0)]:
		_box(parent, "RearBrickSkin", Vector3(entry.x, 1.65, -6.859), Vector3(entry.y, 3.3, 0.015), "brick", false)
	_box(parent, "EastBrickSkin", Vector3(8.209, 1.65, 3.25), Vector3(0.016, 3.3, 20), "brick", false)
	for x: float in [-7.85, 4.82]:
		_pipe(parent, "Downpipe", [Vector3(x, 0.09, -7.04), Vector3(x, 0.19, -6.94), Vector3(x, 2.93, -6.94), Vector3(x - 0.12, 3.28, -6.94)], 0.04, "weathered_green")
		for y: float in [0.3, 1.6, 2.9]: _box(parent, "DownpipeClip", Vector3(x, y, -6.925), Vector3(0.11, 0.035, 0.10), "steel", false)
	_box(parent, "RainGutter", Vector3(0, 3.26, -6.92), Vector3(16.25, 0.13, 0.11), "darksteel", false)
	_framed_sign(parent, "deliveries", Vector3(4.56, 1.91, -6.89), Vector2(0.67, 0.50), PI)
	# Coiled service hose is solid visual context; no surprise trip mechanic.
	var points: Array[Vector3] = []
	for i: int in 180:
		var a := i * TAU / 60.0
		var radius := 0.38 + float(i) / 180 * 0.09
		points.append(Vector3(9.42 + cos(a) * radius, 0.025 + float(i) * 0.00007, 0.3 + sin(a) * radius))
	_pipe(parent, "CoiledHose", points, 0.015, "rubber")
	for z: float in [-4.3, 2.8]:
		for i: int in 2:
			var grille := _lathe(parent, "CondenserFan", Vector3(9.2, 1.065, z - 0.34 + i * 0.68), [Vector2(0.19, 0), Vector2(0.22, 0), Vector2(0.22, 0.012), Vector2(0.19, 0.012)], "darksteel")
			for radius: float in [0.08, 0.13, 0.175]:
				_lathe(parent, "FanGuard", grille.position + Vector3.UP * 0.016, [Vector2(radius, 0), Vector2(radius + 0.006, 0)], "steel")

func _frontage(parent: Node3D) -> void:
	for sign: Node in map.get_node("RestaurantExpansion/Shell").get_children():
		if sign is Label3D and "N I G H T" in sign.text: sign.visible = false
	_framed_sign(parent, "storefront", Vector3(0, 3.7, 13.449), Vector2(9.8, 0.83))
	_framed_sign(parent, "closed", Vector3(-3.0, 1.75, 13.30), Vector2(0.75, 0.47))
	_caution_sign(parent, Vector3(3.25, 0, 14.15), 0.14)
	for x: float in [-7.1, 7.1]:
		var pot := _group(parent, "ForgottenPlanter")
		pot.position = Vector3(x, 0, 14.07)
		_lathe(pot, "Pot", Vector3.ZERO, [Vector2(0, 0), Vector2(0.21, 0), Vector2(0.28, 0.40), Vector2(0.30, 0.41), Vector2(0.30, 0.45), Vector2(0.26, 0.45), Vector2(0.24, 0.38)], "ketchup")
		_box(pot, "Collision", Vector3(0, 0.22, 0), Vector3(0.49, 0.44, 0.49), "ketchup").get_node("Mesh").visible = false
		_lathe(pot, "Soil", Vector3.ZERO, [Vector2(0.25, 0.39), Vector2(0, 0.39)], "coffee")
		for i: int in 14:
			var dx := _random.randf_range(-0.19, 0.19)
			var dz := _random.randf_range(-0.19, 0.19)
			_pipe(pot, "DeadStem", [Vector3(dx, 0.39, dz), Vector3(dx * 0.7, 0.68, dz), Vector3(dx * 1.4, 0.83 + absf(dx), dz * 1.3)], 0.004, "wood")
	# Feet for existing wall lights; their old hovering housings are now supported.
	for x: float in [-8, 7]:
		_pipe(parent, "YardLampPost", [Vector3(x, 0, -16.84), Vector3(x, 3.7, -16.84), Vector3(x, 3.7, -16.7)], 0.038, "darksteel")
		_box(parent, "PostBase", Vector3(x, 0.1, -16.84), Vector3(0.22, 0.20, 0.22), "darksteel")

func _decal(parent: Node3D, graphic: String, at: Vector3, size: Vector2, depth: float = 0.15, yaw: float = 0) -> void:
	var decal := Decal.new()
	_add(decal, parent, graphic.to_pascal_case())
	decal.texture_albedo = load(GRAPHICS + graphic + ".png")
	if graphic == "spill": decal.texture_orm = load(GRAPHICS + "spill_orm.png")
	decal.position = at
	decal.size = Vector3(size.x, depth, size.y)
	decal.rotation.y = yaw
	decal.normal_fade = 0.8
	decal.distance_fade_enabled = true
	decal.distance_fade_begin = 14.0
	decal.distance_fade_length = 6.0

func _surface_history(parent: Node3D) -> void:
	var wear := _group(parent, "SurfaceWear")
	for at: Vector3 in [Vector3(-10, 0.04, -9.0), Vector3(-11.1, 0.04, -8.7), Vector3(-6.8, 0.04, -8.2), Vector3(9.3, 0.04, -4.3), Vector3(9.3, 0.04, 2.8), Vector3(5.95, 0.04, -4.1), Vector3(-5.7, 0.04, -4.5), Vector3(-10.95, 0.04, -1.35), Vector3(5.5, 0.04, 11.5), Vector3(-5.5, 0.04, 8.4)]:
		_decal(wear, "floor_grime", at, Vector2(1.5, 0.9), 0.12, _random.randf_range(0, TAU))
	for i: int in 9:
		_decal(wear, "bootprint", Vector3(6.06 + (0.18 if i % 2 else -0.18), 0.033, -8.1 + i * 0.43), Vector2(0.14, 0.30), 0.10, 0.09 if i % 2 else -0.06)
	for at: Vector3 in [Vector3(-5.3, 0.001, 9.0), Vector3(1.9, 0.001, 11.4), Vector3(-10.6, 0.001, -8.4)]:
		_graphic(wear, "receipt", at, Vector2(0.09, 0.16), Vector3(-PI / 2, _random.randf_range(0, TAU), 0))

func _lighting_finish(parent: Node3D) -> void:
	var room := map.get_node("RestaurantExpansion/DiningRoom")
	for node: Node in room.get_children():
		if node is OmniLight3D: node.light_energy = 0.55
		elif str(node.name).begins_with("LampHousing") or str(node.name).begins_with("LampDiffuser"): node.visible = false
	var environment: Environment = map.get_node("Lighting/WorldEnvironment").environment
	environment.ambient_light_energy = 0.26
	environment.ssao_radius = 0.18
	environment.ssao_intensity = 1.6
	var lighting := _group(parent, "WarmPracticals")
	for at: Vector3 in [Vector3(-5.5, 2.64, 8.4), Vector3(-5.5, 2.64, 11.5), Vector3(5.5, 2.64, 8.4), Vector3(5.5, 2.64, 11.5), Vector3(-1.1, 2.70, 8.35), Vector3(0.7, 2.70, 8.35)]:
		_pipe(lighting, "PendantCord", [at + Vector3(0, 0.018, 0), Vector3(at.x, 3.27, at.z)], 0.006, "rubber")
		_lathe(lighting, "EnamelShade", at, [Vector2(0.27, -0.20), Vector2(0.28, -0.19), Vector2(0.22, -0.13), Vector2(0.09, 0), Vector2(0.044, 0.028), Vector2(0, 0.028)], "paint")
		_lathe(lighting, "ShadeLining", at, [Vector2(0, 0.015), Vector2(0.085, -0.015), Vector2(0.208, -0.139), Vector2(0.27, -0.20)], "cream")
		_sphere(lighting, "WarmBulb", at - Vector3.UP * 0.13, 0.044, "bulb")
		var light := OmniLight3D.new()
		_add(light, lighting, "PendantLight")
		light.position = at - Vector3.UP * 0.23
		light.light_color = Color("ffd3a0")
		light.light_energy = 1.7
		light.omni_range = 3.3
		light.omni_attenuation = 1.2
		light.shadow_enabled = true
		light.shadow_bias = 0.025
	var probe := ReflectionProbe.new()
	_add(probe, lighting, "DiningReflection")
	probe.position = Vector3(0, 1.6, 10)
	probe.size = Vector3(16.1, 3.25, 6.4)
	probe.interior = true
	probe.box_projection = true
	probe.intensity = 0.75
	probe.max_distance = 20

func _batch_details(zone: Node3D, keep_sources: bool = false, destination: Node3D = null) -> void:
	if destination == null: destination = zone
	var batches: Dictionary[int, SurfaceTool] = {}
	var batch_materials: Dictionary[int, Material] = {}
	for mesh: MeshInstance3D in zone.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree(): continue
		if keep_sources and "Ceiling" in str(mesh.get_parent().name): continue
		var ancestor := mesh.get_parent()
		var imported := false
		while ancestor != zone:
			if ancestor.has_meta("scanned_asset"): imported = true
			ancestor = ancestor.get_parent()
		if imported: continue
		var material := mesh.material_override
		if material == null: continue
		if mesh.mesh.get_surface_count() != 1: continue
		var id := material.get_instance_id()
		if not batches.has(id):
			batches[id] = SurfaceTool.new()
			batches[id].begin(Mesh.PRIMITIVE_TRIANGLES)
			batch_materials[id] = material
		batches[id].append_from(mesh.mesh, 0, destination.global_transform.affine_inverse() * mesh.global_transform)
		if keep_sources:
			mesh.set_meta("atmosphere_batched", true)
			mesh.visible = false
		else: mesh.free()
	var directory := "res://assets/meshes/diner_atmosphere"
	DirAccess.make_dir_recursive_absolute(directory)
	var index := 0
	for id: int in batches:
		var mesh := batches[id].commit()
		var path := "%s/%s_%02d.res" % [directory, str(destination.name).to_snake_case(), index]
		var error := ResourceSaver.save(mesh, path)
		assert(error == OK, "Could not save atmosphere mesh: " + path)
		var instance := MeshInstance3D.new()
		_add(instance, destination, "DetailBatch%02d" % index)
		instance.mesh = mesh
		instance.material_override = batch_materials[id]
		index += 1

func _restore_batched_sources() -> void:
	for mesh: MeshInstance3D in map.find_children("*", "MeshInstance3D", true, false):
		if mesh.has_meta("atmosphere_batched"):
			mesh.visible = true
			mesh.remove_meta("atmosphere_batched")

func _batch_fixtures(parent: Node3D) -> void:
	var batches := _group(parent, "FixtureBatches")
	# These assemblies are static. Ovens, flames, storage doors, the cart,
	# climbing marks and showcase-controlled roofs retain their original meshes.
	for path: String in ["PrepLine", "DishPit", "CounterAndNest", "AfterHoursDetails", "RoachEyeDetails", "ServiceClutter", "KitchenWorkArea", "RestaurantExpansion/DiningRoom", "RestaurantExpansion/WalkInPantry"]:
		var source := map.get_node(path) as Node3D
		var destination := _group(batches, str(source.name) + "Baked")
		destination.global_transform = source.global_transform
		_batch_details(source, true, destination)
