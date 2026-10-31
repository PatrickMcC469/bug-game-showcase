extends RefCounted
## Offline extension of the existing kitchen. All dimensions below are metres.
## Keeps the authored kitchen fixtures and adds ordinary floor-connected rooms.
const Detail := preload("res://scripts/tools/diner_detail_geometry.gd")
var map: Node3D
var materials: Dictionary = {}
var meshes: Dictionary = {}

func apply(target: Node3D) -> void:
	map = target
	for key: String in ["tile", "wall", "steel", "cream", "red", "wood", "rubber", "cardboard"]:
		materials[key] = _material(key)
	materials["concrete"] = _solid(Color("666763"), 0.95)
	materials["asphalt"] = _solid(Color("303735"), 0.97)
	materials["green"] = _solid(Color("40564b"), 0.75)
	materials["light"] = _solid(Color("e7c790"), 0.4)
	materials["light"].emission_enabled = true
	materials["light"].emission = Color("e7c790")
	materials["light"].emission_energy_multiplier = 1.8
	# Replace only the enclosing shell, preserving existing kitchen resource IDs.
	for path: String in ["Room/NorthWall", "Room/SouthWall", "Room/WestWall", "PrepLine/PrepBoardRamp", "PrepLine/BoardLanding", "PrepLine/BoardBridge", "DishPit/DishTrayRamp", "ServingCart/LoadingRamp", "ServingCart/LoadingRampCollision"]:
		_remove(path)
	for node: Node in map.get_node("Room").get_children():
		if node.name not in [&"Floor", &"Ceiling", &"EastWall"]:
			node.free()
	for name: String in ["MenuBoard", "Menu"]:
		_remove("AfterHoursDetails/" + name)
	_remove("CounterAndNest/NestSign")
	# The old narrow shelf stood across the new pantry doorway.
	for node: Node in map.get_node("CounterAndNest").get_children():
		if str(node.name).begins_with("PantryShelf") or str(node.name).begins_with("ShelfUpright") or str(node.name).begins_with("SupplyTin"):
			node.free()
	_remove("RestaurantExpansion")
	var expansion := _group(map, "RestaurantExpansion")
	_architecture(expansion)
	_dining(expansion)
	_pantry(expansion)
	_alley(expansion)
	var truck := load("res://scenes/game/props/exterminator_truck.tscn").instantiate() as Node3D
	_add(truck, expansion, "ExterminatorTruck")
	truck.position = Vector3(-1.5, 0, -12.2)
	truck.rotation.y = PI * 0.5
	# Truck deck loading ramp is part of the human service vehicle; kitchen
	# shortcut ramps are removed. Climb abilities/points are a later mechanic.
	for entry: Array in [["FrontEntry", Vector3(0, 0, 13.5)], ["RearEntry", Vector3(6.2, 0, -7.5)], ["PantryEntry", Vector3(-8.1, 0, -2.0)]]:
		var marker := Marker3D.new()
		_add(marker, expansion, entry[0])
		marker.position = entry[1]
	refine_details(map)
	furnish_kitchen(map)
	clear_rear_entry(map)
	add_climb_spots(map)
	detail_hot_line(map)
	load("res://scripts/tools/kitchen_equipment_builder.gd").new().dress_kitchen(map)
	load("res://scripts/tools/oven_builder.gd").new().build_ovens(map)
	move_bar_to_lobby(map)
	load("res://scripts/tools/hiding_builder.gd").new().build_hiding(map)
	load("res://scripts/tools/diner_atmosphere.gd").new().dress_map(map)

func move_bar_to_lobby(target: Node3D) -> void:
	# The old nest cabinet is gone; this group now contains only the bar and
	# its three stools. Move the complete assembly, including solid cabinets.
	target.get_node("CounterAndNest").position = Vector3(4.1, 0, 3.4)

func detail_hot_line(target: Node3D) -> void:
	map = target
	for key: String in ["steel", "rubber", "cream", "red"]: materials[key] = _material(key)
	materials["iron"] = _solid(Color("222826"), 0.82)
	materials["oil"] = _solid(Color("4b3617"), 0.25)
	materials["iron"].metallic = 0.45
	_remove("HotLineDetails")
	var details := _group(map, "HotLineDetails")
	var prep := map.get_node("PrepLine")
	for node: Node in prep.get_children():
		if str(node.name).begins_with("Burner"): node.free()
	var unit := 0
	for cabinet: Node in prep.get_children():
		if not str(cabinet.name).begins_with("CookLine"): continue
		# Lower the solid cabinet top; separate deck strips leave true recesses.
		_resize_box(cabinet, Vector3(2.07, 1.02, 1.44))
		cabinet.get_node("Mesh").position.y = -0.03
		cabinet.get_node("Collision").position.y = -0.03
		var top := _group(details, "Range%d" % (unit + 1))
		top.position = Vector3(cabinet.position.x, 0, cabinet.position.z)
		for x: float in [-0.905, 0.905]: _box(top, "DeckSide", Vector3(x, 1.06, 0), Vector3(0.26, 0.04, 1.44), "steel")
		_box(top, "DeckSpine", Vector3(0, 1.06, 0), Vector3(0.45, 0.04, 1.44), "steel")
		for x: float in [-0.5, 0.5]:
			for z: float in [-0.65, 0.65]: _box(top, "DeckEnd", Vector3(x, 1.06, z), Vector3(0.55, 0.04, 0.14), "steel")
			_box(top, "DeckCross", Vector3(x, 1.06, 0), Vector3(0.55, 0.04, 0.16), "steel")
			for z: float in [-0.33, 0.33]: _gas_burner(top, Vector3(x, 1.022, z))
		_box(top, "BackSplash", Vector3(0, 1.18, -0.707), Vector3(2.07, 0.22, 0.025), "steel")
		_box(top, "OvenDoor", Vector3(0, 0.49, 0.749), Vector3(1.8, 0.58, 0.025), "steel", false)
		_box(top, "OvenWindow", Vector3(0, 0.47, 0.765), Vector3(1.1, 0.27, 0.008), "rubber", false)
		_box(top, "DoorHandle", Vector3(0, 0.75, 0.805), Vector3(1.3, 0.035, 0.035), "iron", false)
		for x: float in [-0.6, 0.6]: _box(top, "HandleBracket", Vector3(x, 0.75, 0.78), Vector3(0.03, 0.045, 0.075), "steel", false)
		for i: int in 15: _box(top, "LowerVent", Vector3(-0.7 + i * 0.10, 0.13, 0.727), Vector3(0.048, 0.008, 0.009), "rubber", false)
		unit += 1
	# Extend the existing hood over the new left-end fryer; retain its right edge.
	var hood := prep.get_node("ExtractorHood") as Node3D
	hood.position.x = -2.075
	_resize_box(hood, Vector3(10, 0.495, 1.755))
	for x: float in [-6.75, -6.5, -6.25, -6.0, -5.75]: _box(details, "HoodVent", Vector3(x, 2.0835, -5.67), Vector3(0.025, 0.02, 1.35), "iron", false)
	_fryer(details)

func _gas_burner(parent: Node3D, at: Vector3) -> void:
	var burner := _group(parent, "Burner")
	burner.position = at
	_lathe_part(burner, "RecessedDripWell", [Vector2(0.001, 0), Vector2(0.215, 0), Vector2(0.252, 0.026), Vector2(0.252, 0.040), Vector2(0.245, 0.040), Vector2(0.210, 0.006), Vector2(0.001, 0.006)], "iron")
	_lathe_part(burner, "BurnerRing", [Vector2(0.075, 0.007), Vector2(0.118, 0.007), Vector2(0.118, 0.03), Vector2(0.103, 0.035), Vector2(0.075, 0.035), Vector2(0.075, 0.007)], "steel")
	for i: int in 16:
		var angle := TAU * i / 16
		var port := _box(burner, "GasPort", Vector3(sin(angle) * 0.117, 0.022, cos(angle) * 0.117), Vector3(0.012, 0.008, 0.006), "rubber", false)
		port.rotation.y = angle
	# Individual grate fingers leave the flame ring and drip well visible.
	for x: float in [-0.264, 0.264]:
		for z: float in [-0.264, 0.264]:
			_box(burner, "GrateFoot", Vector3(x, 0.061, z), Vector3(0.023, 0.008, 0.023), "iron", false)
	for side: float in [-1, 1]:
		_box(burner, "GrateFrame", Vector3(side * 0.264, 0.078, 0), Vector3(0.023, 0.028, 0.55), "iron")
		_box(burner, "GrateFrame", Vector3(0, 0.078, side * 0.264), Vector3(0.55, 0.028, 0.023), "iron")
		_box(burner, "GrateFinger", Vector3(side * 0.171, 0.078, 0), Vector3(0.19, 0.028, 0.032), "iron")
		_box(burner, "GrateFinger", Vector3(0, 0.078, side * 0.171), Vector3(0.032, 0.028, 0.19), "iron")
	var flame := Marker3D.new()
	_add(flame, burner, "FlameOrigin")
	flame.position.y = 0.04
	flame.set_meta("ring_radius", 0.112)

func _lathe_part(parent: Node3D, node_name: String, profile: Array[Vector2], material: String) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	_add(mesh, parent, node_name)
	mesh.mesh = Detail.lathe(profile)
	mesh.material_override = materials[material]
	return mesh

func _fryer(parent: Node3D) -> void:
	var fryer := _group(parent, "TwinBasketFryer")
	fryer.position = Vector3(-6.5, 0, -5.84)
	_box(fryer, "Cabinet", Vector3(0, 0.46, 0), Vector3(0.82, 0.76, 0.84), "steel")
	for x: float in [-0.33, 0.33]:
		for z: float in [-0.33, 0.33]: _box(fryer, "Foot", Vector3(x, 0.04, z), Vector3(0.065, 0.08, 0.065), "rubber")
	_box(fryer, "VatBottom", Vector3(0, 0.85, 0), Vector3(0.78, 0.02, 0.78), "steel")
	for x: float in [-0.39, 0.39]: _box(fryer, "VatSide", Vector3(x, 0.97, 0), Vector3(0.04, 0.26, 0.84), "steel")
	for z: float in [-0.40, 0.40]: _box(fryer, "VatEnd", Vector3(0, 0.97, z), Vector3(0.74, 0.26, 0.04), "steel")
	_box(fryer, "Divider", Vector3(0, 0.97, 0), Vector3(0.018, 0.25, 0.76), "steel")
	for x: float in [-0.192, 0.192]:
		_box(fryer, "OilSurface", Vector3(x, 0.946, 0), Vector3(0.354, 0.002, 0.75), "oil", false)
	_box(fryer, "ControlHead", Vector3(0, 1.27, -0.37), Vector3(0.82, 0.34, 0.13), "steel")
	_box(fryer, "ControlFace", Vector3(0, 1.28, -0.3), Vector3(0.71, 0.20, 0.012), "rubber", false)
	for x: float in [-0.2, 0.2]:
		var dial := _lathe_part(fryer, "TemperatureDial", [Vector2(0.001, 0), Vector2(0.042, 0), Vector2(0.042, 0.024), Vector2(0.001, 0.024)], "iron")
		dial.position = Vector3(x, 1.27, -0.288)
		dial.rotation.x = PI * 0.5
		_box(fryer, "DialPointer", Vector3(x, 1.29, -0.26), Vector3(0.004, 0.021, 0.006), "cream", false)
		_box(fryer, "Indicator", Vector3(x + 0.065, 1.3, -0.29), Vector3(0.012, 0.012, 0.008), "red", false)
	_box(fryer, "DoorSeam", Vector3(0, 0.47, 0.426), Vector3(0.004, 0.67, 0.006), "rubber", false)
	_box(fryer, "DoorPull", Vector3(0.06, 0.65, 0.45), Vector3(0.022, 0.18, 0.025), "iron", false)
	for x: float in [-0.192, 0.192]: _fryer_basket(fryer, Vector3(x, 0.96 if x < 0 else 1.10, -0.015))
	var heat := Marker3D.new()
	_add(heat, fryer, "OilEffectOrigin")
	heat.position = Vector3(0, 0.95, 0)

func _fryer_basket(parent: Node3D, at: Vector3) -> void:
	var basket := _group(parent, "WireBasket")
	basket.position = at
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Batch the wire lattice into one mesh per basket, with a genuinely open top.
	for i: int in 11:
		var x := -0.145 + i * 0.029
		surface.append_from(Detail.pipe([Vector3(x, 0.15, -0.27), Vector3(x, 0, -0.27), Vector3(x, 0, 0.25), Vector3(x, 0.15, 0.25)], 0.0022), 0, Transform3D.IDENTITY)
	for i: int in 17:
		var z := -0.27 + i * 0.0325
		surface.append_from(Detail.pipe([Vector3(-0.145, 0.15, z), Vector3(-0.145, 0, z), Vector3(0.145, 0, z), Vector3(0.145, 0.15, z)], 0.0022), 0, Transform3D.IDENTITY)
	for y: float in [0.05, 0.10, 0.15]:
		surface.append_from(Detail.pipe([Vector3(-0.145, y, -0.27), Vector3(0.145, y, -0.27), Vector3(0.145, y, 0.25), Vector3(-0.145, y, 0.25), Vector3(-0.145, y, -0.27)], 0.003), 0, Transform3D.IDENTITY)
	var wire := MeshInstance3D.new()
	_add(wire, basket, "WireMesh")
	wire.mesh = surface.commit()
	wire.material_override = materials["steel"]
	for x: float in [-0.055, 0.055]:
		_box(basket, "HandleStem", Vector3(x, 0.19, 0.40), Vector3(0.012, 0.016, 0.32), "steel", false).rotation.x = -0.2
	_box(basket, "HandleGrip", Vector3(0, 0.222, 0.54), Vector3(0.15, 0.04, 0.035), "rubber", false)
	_box(basket, "RearHook", Vector3(0, 0.17, -0.31), Vector3(0.07, 0.035, 0.10), "steel", false)

func add_climb_spots(target: Node3D) -> void:
	map = target
	_remove("ClimbSpots")
	var spots := _group(map, "ClimbSpots")
	var scene := load("res://scenes/game/props/roach_climb_spot.tscn") as PackedScene
	for row: Array in [
		["PrepIsland", Vector3(1.5, 0, -2.01), 1.08, "Prep island"],
		["DishTable", Vector3(6.0, 0, 3.255), 1.08, "Dish table"],
		["PrepBench", Vector3(-4.75, 0, 0.54), 0.945, "Prep bench"],
		["ServiceRack", Vector3(-0.3, 0, 2.74), 1.23, "Service rack"],
		["PantryShelf", Vector3(-9.3, 0, -4.91), 1.9525, "Pantry shelf"]]:
		var spot := scene.instantiate() as Node3D
		spot.height = row[2]
		spot.destination_name = row[3]
		_add(spot, spots, row[0])
		spot.position = row[1]
		spot.configure_visuals()

func clear_rear_entry(target: Node3D) -> void:
	# Move the tall cabinet as one assembly, including its collision and doors.
	# Face it into the kitchen from the west wall, clear of the pantry doorway.
	var cabinet := target.get_node("ServiceClutter/ReachInFridge") as Node3D
	cabinet.position = Vector3(-7.45, 1.025, -4.7)
	cabinet.rotation.y = PI * 0.5

func furnish_kitchen(target: Node3D) -> void:
	map = target
	for key: String in ["steel", "wood", "rubber", "cream", "cardboard", "red"]:
		materials[key] = _material(key)
	_remove("KitchenWorkArea")
	var area := _group(map, "KitchenWorkArea")
	# Human-size prep station: an open underside and a separate lower shelf
	# give insects two routes without walling off the pantry approach at z=-2.
	var bench := _group(area, "PrepBench")
	bench.position = Vector3(-5.1, 0, 0.1)
	_box(bench, "Worktop", Vector3(0, 0.91, 0), Vector3(1.75, 0.07, 0.85), "steel")
	_box(bench, "LowerShelf", Vector3(0, 0.19, 0), Vector3(1.55, 0.035, 0.67), "steel")
	for x: float in [-0.76, 0.76]:
		for z: float in [-0.32, 0.32]:
			_box(bench, "Leg", Vector3(x, 0.44, z), Vector3(0.045, 0.88, 0.045), "steel")
			_box(bench, "RubberFoot", Vector3(x, 0.022, z), Vector3(0.06, 0.044, 0.06), "rubber", false)
	_box(bench, "CuttingBoard", Vector3(-0.32, 0.962, 0.03), Vector3(0.52, 0.032, 0.38), "wood")
	_box(bench, "KnifeBlade", Vector3(-0.3, 0.981, 0.06), Vector3(0.18, 0.004, 0.035), "steel", false).rotation.y = -0.22
	_box(bench, "KnifeHandle", Vector3(-0.435, 0.988, 0.09), Vector3(0.09, 0.018, 0.035), "rubber", false).rotation.y = -0.22
	_bowl(bench, Vector3(0.42, 0.946, -0.08), 0.14, 0.13)
	_box(bench, "FoldedTowel", Vector3(0.55, 0.954, 0.25), Vector3(0.22, 0.018, 0.15), "cream", false)
	for x: float in [-0.38, 0.28]:
		_box(bench, "IngredientCarton", Vector3(x, 0.3175, 0.02), Vector3(0.38, 0.22, 0.42), "cardboard")
	# A narrow sheet-pan rack breaks sight lines while retaining a 12 cm floor gap.
	var rack := _group(area, "SheetPanRack")
	rack.position = Vector3(-3.9, 0, 2.8)
	for x: float in [-0.30, 0.30]:
		for z: float in [-0.34, 0.34]:
			_box(rack, "Upright", Vector3(x, 0.93, z), Vector3(0.032, 1.65, 0.032), "steel")
			var wheel := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.06
			cylinder.bottom_radius = 0.06
			cylinder.height = 0.035
			cylinder.radial_segments = 16
			wheel.mesh = cylinder
			wheel.material_override = materials["rubber"]
			_add(wheel, rack, "Caster")
			wheel.position = Vector3(x, 0.06, z)
			wheel.rotation.z = PI * 0.5
			_box(rack, "CasterFork", Vector3(x, 0.10, z), Vector3(0.055, 0.12, 0.04), "steel")
	for i: int in 8:
		var y := 0.14 + i * 0.205
		_box(rack, "Tray", Vector3(0, y, -0.025 if i % 3 == 0 else 0.015), Vector3(0.58, 0.024, 0.68), "steel")
		for x: float in [-0.275, 0.275]:
			_box(rack, "TrayLip", Vector3(x, y + 0.024, 0), Vector3(0.015, 0.03, 0.68), "steel", false)
	_box(rack, "TopRail", Vector3(0, 1.755, -0.34), Vector3(0.63, 0.035, 0.035), "steel")
	# A wall-side shelf carries cookware, with room to pass between it and bench.
	var storage := _group(area, "CookwareShelf")
	storage.position = Vector3(-7.55, 0, 0.9)
	for x: float in [-0.24, 0.24]:
		for z: float in [-0.75, 0.75]: _box(storage, "Post", Vector3(x, 0.84, z), Vector3(0.035, 1.68, 0.035), "steel")
	for y: float in [0.16, 0.69, 1.22, 1.69]:
		_box(storage, "Shelf", Vector3(0, y, 0), Vector3(0.55, 0.035, 1.58), "steel")
		for z: float in [-0.47, 0.38]: _bowl(storage, Vector3(0, y + 0.018, z), 0.16 if z < 0 else 0.12, 0.18 if z < 0 else 0.11)
	var crate := _group(area, "ProduceCrate")
	crate.position = Vector3(-6.8, 0, 2.1)
	_box(crate, "Base", Vector3(0, 0.075, 0), Vector3(0.62, 0.035, 0.43), "wood")
	for x: float in [-0.275, 0.275]: _box(crate, "Foot", Vector3(x, 0.029, 0), Vector3(0.07, 0.058, 0.43), "wood")
	for y: float in [0.14, 0.24, 0.34]:
		for z: float in [-0.22, 0.22]: _box(crate, "Slat", Vector3(0, y, z), Vector3(0.64, 0.065, 0.025), "wood")
		for x: float in [-0.315, 0.315]: _box(crate, "EndSlat", Vector3(x, y, 0), Vector3(0.025, 0.065, 0.43), "wood")
	for body: Node in area.find_children("*", "StaticBody3D", true, false): body.add_to_group("diner_clutter", true)

func _bowl(parent: Node3D, at: Vector3, radius: float, height: float) -> void:
	var bowl := StaticBody3D.new()
	_add(bowl, parent, "MixingBowl")
	bowl.position = at
	bowl.add_to_group("diner_static", true)
	var mesh := MeshInstance3D.new()
	mesh.mesh = Detail.lathe([Vector2(0.001, 0), Vector2(radius * 0.45, 0), Vector2(radius * 0.67, height * 0.35), Vector2(radius, height * 0.92), Vector2(radius, height), Vector2(radius - 0.006, height), Vector2(radius * 0.62, height * 0.35), Vector2(radius * 0.4, 0.008), Vector2(0.001, 0.008)])
	mesh.material_override = materials["steel"]
	_add(mesh, bowl, "Mesh")
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	collision.position.y = height * 0.5
	_add(collision, bowl, "Collision")

func refine_details(target: Node3D) -> void:
	map = target
	# The former home counter is a single oversized desk-like assembly. Remove
	# the whole unit, including low roofs and dressing, now that home is in storage.
	for node: Node in map.get_node("CounterAndNest").get_children():
		for prefix: String in ["CounterTop", "CounterBack", "LowPassageRoof", "CabinetUpper", "DrawerPull", "LooseBaseboard", "CabinetSeam", "NestSign"]:
			if str(node.name).begins_with(prefix):
				node.free()
				break
	_offset_plates(map.get_node("DishPit"), "Plate", 0.003)
	_offset_plates(map.get_node("ServiceClutter/ServiceRack"), "CleanPlate", 0.008)
	var pantry := map.get_node("RestaurantExpansion/WalkInPantry")
	var rack_index := 0
	for rack: Node in pantry.get_children():
		if not (str(rack.name).begins_with("DryGoodsRack") or rack.name in [&"BackRack", &"FrontRack"]): continue
		var boxes: Array[Node] = []
		var tapes: Array[Node] = []
		for child: Node in rack.get_children():
			if str(child.name).begins_with("SupplyCarton"): boxes.append(child)
			if str(child.name).begins_with("CartonTape"): tapes.append(child)
		var long_rack := str(rack.name).begins_with("DryGoodsRack")
		for i: int in boxes.size():
			var box := boxes[i] as Node3D
			var variant := (i + rack_index * 3) % 5
			var sizes: Array[Vector3] = [Vector3(0.48, 0.22, 0.42), Vector3(0.57, 0.40, 0.51), Vector3(0.39, 0.31, 0.37), Vector3(0.61, 0.27, 0.54), Vector3(0.45, 0.46, 0.43)]
			var size := sizes[variant]
			var shelf_y := 0.19 + floori(i / 2.0) * 0.58
			var side := -1.0 if i % 2 == 0 else 1.0
			box.position = Vector3(0.025 * sin(i * 1.7), shelf_y + 0.0225 + size.y * 0.5, side * 0.67) if long_rack else Vector3(side * 0.45, shelf_y + 0.0225 + size.y * 0.5, 0.02 * cos(i))
			box.rotation.y = [-0.055, 0.035, -0.025, 0.065, 0.0][variant]
			_resize_box(box, size)
			# Keep tape resting on each lid as height, footprint and yaw change.
			var tape := tapes[i] as Node3D
			tape.transform = box.transform
			tape.position += Vector3.UP * (size.y * 0.5 + 0.003)
			_resize_box(tape, Vector3(0.048, 0.006, size.z))
		rack_index += 1
	# The service rack gets a shorter parcel, a medium carton and a tall box.
	var index := 0
	for box: Node in map.get_node("ServiceClutter/ServiceRack").get_children():
		if not str(box.name).begins_with("DeliveryCarton"): continue
		var size: Vector3 = [Vector3(0.44, 0.20, 0.40), Vector3(0.50, 0.43, 0.47), Vector3(0.36, 0.29, 0.38)][index % 3]
		box.position.y = 0.635 + size.y * 0.5
		_resize_box(box, size)
		for child: Node in box.get_children():
			if child.name == &"Tape" or child.name == &"FoldSeam":
				child.position.y = size.y * 0.5 + (0.0006 if child.name == &"Tape" else 0.0012)
				_resize_box(child, Vector3(0.055 if child.name == &"Tape" else 0.002, 0.001 if child.name == &"Tape" else 0.0005, size.z))
		index += 1

func _resize_box(body: Node3D, size: Vector3) -> void:
	var mesh := body.get_node("Mesh") as MeshInstance3D
	mesh.mesh = Detail.bevel_box(size, minf(0.006, minf(size.x, minf(size.y, size.z)) * 0.15))
	var collision := body.get_node_or_null("Collision") as CollisionShape3D
	if collision != null:
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape

func _offset_plates(parent: Node, prefix: String, amount: float) -> void:
	var index := 0
	for plate: Node in parent.get_children():
		if not str(plate.name).begins_with(prefix) or not plate is MeshInstance3D: continue
		# Persist the authored center so rerunning this pass never accumulates drift.
		if not plate.has_meta("stack_center"): plate.set_meta("stack_center", plate.position)
		plate.position = plate.get_meta("stack_center") + Vector3(sin(index * 2.3) * amount, 0, cos(index * 1.7) * amount)
		plate.rotation.y = sin(index * 1.9) * 0.17
		index += 1

func _remove(path: String) -> void:
	var node := map.get_node_or_null(path)
	if node != null: node.free()

func _add(node: Node, parent: Node, node_name: String) -> void:
	node.name = node_name
	parent.add_child(node, true)
	node.owner = map

func _group(parent: Node, node_name: String) -> Node3D:
	var node := Node3D.new()
	_add(node, parent, node_name)
	return node

func _solid(color: Color, roughness: float) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	return result

func _material(key: String) -> Material:
	var colors := {"tile": "8d7963", "wall": "c7c4ac", "steel": "919e9d", "cream": "d0c8ac", "red": "662b28", "wood": "755943", "rubber": "1c2522", "cardboard": "967754"}
	var result := _solid(Color(colors[key]), 0.7)
	if key == "steel": result.metallic = 0.8
	var textures := {"tile": "brown_floor_tiles", "wall": "long_white_tiles", "wood": "kitchen_wood"}
	if textures.has(key):
		var prefix: String = "res://assets/textures/diner/" + textures[key]
		result.albedo_color = Color.WHITE
		result.albedo_texture = load(prefix + "_diff_2k.jpg")
		result.normal_enabled = true
		result.normal_texture = load(prefix + "_nor_gl_2k.jpg")
		result.normal_scale = 0.5
		result.roughness_texture = load(prefix + "_rough_2k.jpg")
		result.uv1_triplanar = key != "wall"
		result.uv1_world_triplanar = key != "wall"
		result.uv1_scale = Vector3.ONE / (2.0 if key == "wall" else 1.7)
		result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return result

func _box(parent: Node, node_name: String, at: Vector3, size: Vector3, material: String, solid: bool = true) -> Node3D:
	var body: Node3D = StaticBody3D.new() if solid else Node3D.new()
	_add(body, parent, node_name)
	body.position = at
	if solid: body.add_to_group("diner_static", true)
	var mesh := MeshInstance3D.new()
	var key := str(size) + material
	if not meshes.has(key): meshes[key] = Detail.bevel_box(size, minf(0.009, minf(size.x, minf(size.y, size.z)) * 0.15), material == "wall")
	mesh.mesh = meshes[key]
	mesh.material_override = materials[material]
	_add(mesh, body, "Mesh")
	if solid:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		_add(collision, body, "Collision")
	return body

func _label(parent: Node, words: String, at: Vector3, width_scale: float = 0.004, yaw: float = 0) -> void:
	var label := Label3D.new()
	_add(label, parent, "Sign")
	label.text = words
	label.position = at
	label.rotation.y = yaw
	label.font_size = 64
	label.pixel_size = width_scale
	label.modulate = Color("e7dab8")
	label.outline_size = 0

func _lamp(parent: Node, at: Vector3, warm: bool = true, reach: float = 7) -> void:
	_box(parent, "LampHousing", at, Vector3(0.7, 0.12, 0.28), "steel", false)
	_box(parent, "LampDiffuser", at - Vector3.UP * 0.075, Vector3(0.61, 0.03, 0.22), "light", false)
	var light := OmniLight3D.new()
	_add(light, parent, "PracticalLight")
	light.position = at - Vector3.UP * 0.22
	light.light_color = Color("ffe4bd") if warm else Color("d9e8e6")
	light.light_energy = 2.4
	light.omni_range = reach
	light.shadow_enabled = true

func _architecture(parent: Node3D) -> void:
	var shell := _group(parent, "Shell")
	# Open rear door: 1.8 m wide, 2.45 m tall, level with the alley.
	_box(shell, "RearWallWest", Vector3(-1.4, 1.65, -6.75), Vector3(13.4, 3.3, 0.2), "wall")
	_box(shell, "RearWallEast", Vector3(7.6, 1.65, -6.75), Vector3(1.0, 3.3, 0.2), "wall")
	_box(shell, "RearDoorHeader", Vector3(6.2, 2.875, -6.75), Vector3(1.8, 0.85, 0.2), "wall")
	_box(shell, "RearDoorOpen", Vector3(7.2, 1.2, -7.55), Vector3(0.09, 2.4, 1.5), "green")
	_label(shell, "DELIVERIES", Vector3(6.2, 2.82, -6.87), 0.003, PI)
	_lamp(shell, Vector3(6.2, 2.6, -7.1), false)
	# West wall doorway connects kitchen to the walk-in dry pantry.
	_box(shell, "WestNorth", Vector3(-8.1, 1.65, -4.775), Vector3(0.2, 3.3, 3.95), "wall")
	_box(shell, "WestSouth", Vector3(-8.1, 1.65, 2.775), Vector3(0.2, 3.3, 7.95), "wall")
	_box(shell, "PantryHeader", Vector3(-8.1, 2.875, -2), Vector3(0.2, 0.85, 1.6), "wall")
	_label(shell, "DRY PANTRY", Vector3(-7.975, 2.7, -2), 0.003, PI * 0.5)
	# A real partition defines front of house; two generous openings form a loop.
	for entry: Vector2 in [Vector2(-6.15, 3.9), Vector2(0, 4.0), Vector2(6.15, 3.9)]:
		_box(shell, "DiningPartition", Vector3(entry.x, 1.65, 6.75), Vector3(entry.y, 3.3, 0.18), "wall")
	for x: float in [-3.1, 3.1]:
		_box(shell, "PassageLintel", Vector3(x, 2.95, 6.75), Vector3(2.2, 0.7, 0.18), "wall")
	_box(shell, "DiningFloor", Vector3(0, -0.15, 10), Vector3(16.2, 0.3, 6.5), "tile")
	_box(shell, "DiningCeiling", Vector3(0, 3.35, 10), Vector3(16.2, 0.15, 6.5), "cream")
	for x: float in [-8.1, 8.1]:
		_box(shell, "DiningSide", Vector3(x, 1.65, 10), Vector3(0.2, 3.3, 6.5), "wall")
	for x: float in [-4.55, 4.55]:
		_box(shell, "StorefrontBase", Vector3(x, 0.45, 13.25), Vector3(7.1, 0.9, 0.2), "red")
		_box(shell, "StorefrontHeader", Vector3(x, 2.95, 13.25), Vector3(7.1, 0.7, 0.2), "cream")
		var glass := _solid(Color(0.35, 0.52, 0.49, 0.18), 0.12)
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		materials["glass"] = glass
		_box(shell, "WindowGlass", Vector3(x, 1.75, 13.25), Vector3(7.0, 1.7, 0.035), "glass")
		for offset: float in [-3.5, -1.17, 1.17, 3.5]:
			_box(shell, "WindowMullion", Vector3(x + offset, 1.75, 13.28), Vector3(0.065, 1.75, 0.09), "steel")
	_box(shell, "FrontEntryHeader", Vector3(0, 2.95, 13.25), Vector3(2, 0.7, 0.2), "cream")
	_box(shell, "FrontDoorOpen", Vector3(-0.98, 1.25, 12.38), Vector3(0.075, 2.5, 1.6), "green")
	_box(shell, "Awning", Vector3(0, 3.1, 13.8), Vector3(16.5, 0.18, 1.35), "red")
	_box(shell, "SignBacking", Vector3(0, 3.7, 13.35), Vector3(10, 0.9, 0.15), "green", false)
	_label(shell, "N I G H T  O W L   /   D I N E R", Vector3(0, 3.7, 13.45), 0.005)
	_label(shell, "COFFEE  •  PIE  •  OPEN LATE", Vector3(4.5, 2.95, 13.39), 0.0027)
	_lamp(shell, Vector3(0, 2.9, 13.8))

func _dining(parent: Node3D) -> void:
	var room := _group(parent, "DiningRoom")
	# Open table/chair bases retain human furniture proportions and insect routes.
	for x: float in [-5.5, 5.5]:
		for z: float in [8.4, 11.5]:
			var table := _group(room, "DiningTable")
			table.position = Vector3(x, 0, z)
			_box(table, "Top", Vector3(0, 0.76, 0), Vector3(1.65, 0.07, 0.85), "wood")
			for dx: float in [-0.65, 0.65]:
				for dz: float in [-0.29, 0.29]:
					_box(table, "Leg", Vector3(dx, 0.36, dz), Vector3(0.06, 0.72, 0.06), "steel")
			for dz: float in [-0.85, 0.85]:
				var chair := _group(table, "Chair")
				chair.position = Vector3(0.25, 0, dz)
				_box(chair, "Seat", Vector3(0, 0.46, 0), Vector3(0.46, 0.09, 0.43), "red")
				_box(chair, "Back", Vector3(0, 0.74, signf(dz) * 0.19), Vector3(0.46, 0.53, 0.06), "red")
				for a: float in [-0.18, 0.18]:
					for b: float in [-0.16, 0.16]: _box(chair, "Leg", Vector3(a, 0.22, b), Vector3(0.035, 0.44, 0.035), "steel")
			_box(table, "NapkinHolder", Vector3(-0.4, 0.87, 0), Vector3(0.12, 0.16, 0.10), "steel", false)
			_box(table, "Menu", Vector3(0.3, 0.801, 0.12), Vector3(0.3, 0.008, 0.22), "cream", false)
		_lamp(room, Vector3(x, 3.12, 9.9))
	# Two low bench seats make a short protected loop alongside the front glass.
	for x: float in [-2.5, 2.5]:
		_box(room, "WaitingBench", Vector3(x, 0.45, 12.2), Vector3(1.25, 0.15, 0.43), "red")
		for dx: float in [-0.5, 0.5]: _box(room, "BenchLeg", Vector3(x + dx, 0.19, 12.2), Vector3(0.08, 0.38, 0.35), "steel")
	_lamp(room, Vector3(0, 3.1, 9.7))

func _shelf(parent: Node3D, at: Vector3, width: float, depth: float, node_name: String) -> void:
	var shelf := _group(parent, node_name)
	shelf.position = at
	for x: float in [-width * 0.5 + 0.03, width * 0.5 - 0.03]:
		for z: float in [-depth * 0.5 + 0.03, depth * 0.5 - 0.03]:
			_box(shelf, "Upright", Vector3(x, 1.1, z), Vector3(0.045, 2.2, 0.045), "steel")
	for y: float in [0.19, 0.77, 1.35, 1.93]:
		_box(shelf, "Shelf", Vector3(0, y, 0), Vector3(width, 0.045, depth), "steel")
		for x: float in [-width * 0.28, width * 0.28]:
			_box(shelf, "SupplyCarton", Vector3(x, y + 0.2, 0), Vector3(width * 0.35, 0.35, depth * 0.75), "cardboard")
			_box(shelf, "CartonTape", Vector3(x, y + 0.38, 0), Vector3(0.05, 0.008, depth * 0.75), "cream", false)

func _pantry(parent: Node3D) -> void:
	var room := _group(parent, "WalkInPantry")
	_box(room, "Floor", Vector3(-10.2, -0.15, -2.8), Vector3(4.2, 0.3, 6), "tile")
	_box(room, "Ceiling", Vector3(-10.2, 3.35, -2.8), Vector3(4.2, 0.15, 6), "cream")
	_box(room, "WestWall", Vector3(-12.3, 1.65, -2.8), Vector3(0.2, 3.3, 6), "wall")
	for z: float in [-5.8, 0.2]: _box(room, "EndWall", Vector3(-10.2, 1.65, z), Vector3(4.2, 3.3, 0.2), "wall")
	for z: float in [-4.3, -1.2]: _shelf(room, Vector3(-11.75, 0, z), 0.75, 2.45, "DryGoodsRack")
	_shelf(room, Vector3(-9.3, 0, -5.25), 1.8, 0.65, "BackRack")
	_shelf(room, Vector3(-9.3, 0, -0.32), 1.8, 0.65, "FrontRack")
	# Home sits beneath an open-footed storage stand, away from the human aisle.
	_box(room, "NestCover", Vector3(-10.8, 0.2, -4.5), Vector3(0.6, 0.08, 0.7), "wood")
	for x: float in [-11.05, -10.55]:
		_box(room, "NestFoot", Vector3(x, 0.08, -4.5), Vector3(0.045, 0.16, 0.65), "wood")
	_label(room, "DRY GOODS\nKEEP AISLE CLEAR", Vector3(-10.15, 2.4, -5.67), 0.0035)
	_lamp(room, Vector3(-10.1, 3.1, -2.5), false)

func _alley(parent: Node3D) -> void:
	var outdoors := _group(parent, "Exterior")
	_box(outdoors, "AlleyFloor", Vector3(-0.5, -0.18, -12.375), Vector3(27, 0.36, 11.25), "asphalt")
	_box(outdoors, "FrontWalk", Vector3(-0.5, -0.18, 15.125), Vector3(27, 0.36, 3.75), "concrete")
	_box(outdoors, "EastPassage", Vector3(10.55, -0.18, 3.25), Vector3(4.9, 0.36, 20), "asphalt")
	_box(outdoors, "WestPassage", Vector3(-13.15, -0.18, 3.25), Vector3(1.7, 0.36, 20), "asphalt")
	_box(outdoors, "PantryNorthGround", Vector3(-10.2, -0.18, -6.275), Vector3(4.2, 0.36, 0.95), "asphalt")
	_box(outdoors, "PantrySouthGround", Vector3(-10.2, -0.18, 6.725), Vector3(4.2, 0.36, 13.05), "asphalt")
	# Level thresholds remain traversable by centimetre-sized roaches.
	for x: float in [-14, 13]: _box(outdoors, "BoundaryWall", Vector3(x, 2.2, -0.5), Vector3(0.2, 4.4, 35), "concrete")
	for z: float in [-18, 17]: _box(outdoors, "BoundaryWall", Vector3(-0.5, 2.2, z), Vector3(27, 4.4, 0.2), "concrete")
	for x: float in [-10, -6, -2, 2, 6]:
		_box(outdoors, "BayLine", Vector3(x, 0.002, -15.1), Vector3(0.065, 0.004, 3.2), "cream", false)
	# Dumpster raised on feet: open underside and sheltered perimeter route.
	_box(outdoors, "Dumpster", Vector3(-10.1, 0.85, -9.8), Vector3(2.1, 1.4, 1.25), "green")
	_box(outdoors, "DumpsterLid", Vector3(-10.1, 1.58, -9.8), Vector3(2.2, 0.09, 1.32), "rubber")
	for dx: float in [-0.85, 0.85]:
		for dz: float in [-0.45, 0.45]: _box(outdoors, "DumpsterFoot", Vector3(-10.1 + dx, 0.075, -9.8 + dz), Vector3(0.12, 0.15, 0.12), "steel")
	_label(outdoors, "NIGHT OWL\nWASTE ONLY", Vector3(-10.1, 0.95, -9.165), 0.0024)
	for at: Vector3 in [Vector3(9.2, 0, -4.3), Vector3(9.2, 0, 2.8)]:
		_box(outdoors, "Condenser", at + Vector3.UP * 0.6, Vector3(0.8, 0.9, 1.5), "steel")
		for z: float in [-0.55, 0.55]: _box(outdoors, "CondenserFoot", at + Vector3(0, 0.075, z), Vector3(0.65, 0.15, 0.06), "rubber")
		for i: int in 10: _box(outdoors, "VentSlat", at + Vector3(0.409, 0.24 + i * 0.07, 0), Vector3(0.02, 0.023, 1.3), "rubber", false)
	for x: float in [-8, 7]: _lamp(outdoors, Vector3(x, 3.7, -16.7), false, 11)
	var moon := DirectionalLight3D.new()
	_add(moon, outdoors, "Moonlight")
	moon.rotation_degrees = Vector3(-42, -25, 0)
	moon.light_color = Color("acc4cf")
	moon.light_energy = 0.6
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 70
