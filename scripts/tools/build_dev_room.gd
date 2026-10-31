extends SceneTree
## Offline map authoring. Extract production props, preserving their scripts,
## collision, controls and groups; only arrangement and test fixtures are new.
const Catalog := preload("res://scripts/game/dev_room_catalog.gd")
var map: Node3D
var source: Node3D

func _initialize() -> void:
	_build.call_deferred()

func _build() -> void:
	source = load("res://scenes/game/maps/diner_kitchen.tscn").instantiate()
	root.add_child(source)
	map = Node3D.new()
	map.name = "DevRoomMap"
	root.add_child(map)
	_box(map, "Floor", Vector3(4, -0.15, 13), Vector3(40, 0.3, 38), Color("434a50"))
	for station: Dictionary in Catalog.STATIONS:
		var pad := _group(map, station.id)
		pad.position = station.at
		pad.set_meta("mechanic_station", station.id)
		_box(pad, "BackWall", Vector3(0, 1.3, -4.2), Vector3(9, 2.6, 0.15), Color("606e74"))
		_label(pad, station.title, Vector3(0, 2.1, -4.1), 0.006)
		for x: int in range(-4, 5):
			_box(pad, "Grid", Vector3(x, 0.0005, 0), Vector3(0.008, 0.001, 8), Color("718182"), false)
		for z: int in range(-4, 5):
			_box(pad, "Grid", Vector3(0, 0.0005, z), Vector3(8, 0.001, 0.008), Color("718182"), false)
		_label(pad, "1 m grid · F1 controls / F2 character / F5 reset", Vector3(0, 1.5, -4.09), 0.003)
	_box(map, "WestBoundary", Vector3(-16, 2, 13), Vector3(0.2, 4, 38), Color("323a42"))
	_box(map, "EastBoundary", Vector3(24, 2, 13), Vector3(0.2, 4, 38), Color("323a42"))
	_box(map, "NorthBoundary", Vector3(4, 2, -6), Vector3(40, 4, 0.2), Color("323a42"))
	_box(map, "SouthBoundary", Vector3(4, 2, 32), Vector3(40, 4, 0.2), Color("323a42"))
	var sun := DirectionalLight3D.new()
	map.add_child(sun)
	sun.name = "LabLight"
	sun.rotation_degrees = Vector3(-65, -25, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	var lighting := WorldEnvironment.new()
	lighting.name = "LabEnvironment"
	lighting.environment = Environment.new()
	lighting.environment.background_mode = Environment.BG_COLOR
	lighting.environment.background_color = Color("313c43")
	lighting.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	lighting.environment.ambient_light_color = Color("dce9ed")
	lighting.environment.ambient_light_energy = 0.6
	map.add_child(lighting)
	var movement := map.get_node("movement")
	_ramp(movement, Vector3(-1.5, 0, -1), 0.65, 2.4)
	_box(movement, "CrawlRoof", Vector3(1.5, 0.08, -1), Vector3(1, 0.08, 2), Color("cbb487"))
	_label(movement, "4 cm clearance", Vector3(1.5, 0.35, 0.2), 0.0015)
	var climb := map.get_node("climbing")
	_box(climb, "Platform", Vector3(0, 0.4, -1), Vector3(2, 0.8, 2), Color("697d78"))
	var spot := load("res://scenes/game/props/roach_climb_spot.tscn").instantiate() as Node3D
	climb.add_child(spot)
	spot.name = "ClimbSpot"
	spot.height = 0.8
	spot.destination_name = "Dev platform"
	var dish: Node3D = load("res://scenes/game/props/commercial_dish_station.tscn").instantiate()
	dish.name = "CommercialDishStation"
	dish.position = Vector3(0, 0, 5)
	climb.add_child(dish)
	var tray := _take("DishPit/FallenTray", climb)
	tray.name = "FallenTray"
	tray.position = Vector3(-2.5, 0.0135, 1)
	tray.rotation = Vector3.ZERO
	# The exact production tray includes its repaired mesh collision. An open
	# underside and an unmarked carton exercise automatic wall/edge traversal.
	_box(climb, "CrawlBox", Vector3(2.5, 0.2, 0), Vector3(0.5, 0.4, 0.6), Color("97724b"))
	_box(climb, "CrawlOverhang", Vector3(2.5, 0.42, -0.65), Vector3(0.5, 0.04, 0.7), Color("697d78"))
	var cart := _take("ServingCart", map)
	map.get_node("cart/BackWall").free()
	cart.position = Vector3(4.05, 0, -1.35)
	# Test-only deck access; normal diners continue to omit the retired ramps.
	var access := _group(map, "CartAccess")
	access.position = Vector3(4.05, 0, -4.42)
	# End just above the deck: an exact-height ramp leaves the long bug capsule
	# catching the cart's vertical lip before its center reaches the ramp crest.
	_ramp(access, Vector3.ZERO, 1.11, 2.4)
	access.rotation.y = PI
	var stoves := map.get_node("stoves")
	var range_node := _take("HotLineDetails/Range1", stoves)
	var range_origin := range_node.position
	range_node.position = Vector3.ZERO
	var pot := _take("KitchenEquipment/Saucepan", stoves)
	pot.position -= range_origin
	var stove_route := _take("KitchenEquipment/ClimbSpots/Range1", stoves)
	stove_route.name = "StoveClimb"
	stove_route.position -= range_origin
	# A hollow cabinet supports the copied stovetop; use the real oven shell too.
	var stove_shell := _take("OvenInteriors/Oven1", stoves)
	stove_shell.position -= range_origin
	var fryer := _take("HotLineDetails/TwinBasketFryer", stoves)
	var fryer_delta := Vector3(-2.5, 0, 0) - fryer.position
	fryer.position += fryer_delta
	var fryer_route := _take("KitchenEquipment/ClimbSpots/FryerRim", stoves)
	fryer_route.position += fryer_delta
	var ovens := map.get_node("ovens")
	var oven := _take("OvenInteriors/Oven2", ovens)
	oven.position = Vector3.ZERO
	var storage := map.get_node("storage")
	for row: Array in [["KitchenCabinet", Vector3(-2, 0, -1)], ["LobbyCabinet", Vector3(0, 0, -1)],
		["KitchenBox", Vector3(2, 0, -1)], ["PantryBox", Vector3(2, 0, 1)]]:
		var prop := _take("HidingPlaces/" + row[0], storage)
		prop.position = row[1]
		prop.rotation = Vector3.ZERO
	var ducts := _take("BugVents", map.get_node("vents"))
	ducts.position = Vector3(8.1, 0, -2.4)
	# Exposed duct collision stays intact. A nearby wall provides a separate
	# cover test without the diner's unrelated walls concealing the fixture.
	_box(map.get_node("vents"), "Cover", Vector3(2, 0.5, 0), Vector3(1, 1, 0.05), Color("65766c"))
	var combat := map.get_node("combat")
	_box(combat, "Cover", Vector3(-2, 0.75, 0), Vector3(1.4, 1.5, 0.1), Color("73867c"))
	_box(combat, "RecoveryRoof", Vector3(2, 1.2, 0), Vector3(2, 0.2, 3), Color("b1a27f"))
	_label(combat, "RECOIL / SCOOT CLEAR", Vector3(2, 1.6, 1.5), 0.002)
	_box(combat, "RefillMount", Vector3(-3.3, 0.75, 2.1), Vector3(0.9, 1.5, 0.12), Color("73867c"))
	var cradle := load("res://scenes/game/props/gas_refill_station.tscn").instantiate() as Node3D
	cradle.name = "GasRefillStation"
	combat.add_child(cradle)
	cradle.position = Vector3(-3.3, 1.0, 2.2)
	_own(map)
	preload("res://scripts/tools/install_drain_routes.gd").add_routes(map, true)
	var packed := PackedScene.new()
	var result := packed.pack(map)
	if result == OK: result = ResourceSaver.save(packed, "res://scenes/game/maps/dev_room_map.tscn")
	print("DEV ROOM BUILD: ", "PASS" if result == OK else error_string(result))
	map.free()
	source.free()
	quit(0 if result == OK else 1)

func _take(path: String, parent: Node3D) -> Node3D:
	var node := source.get_node(path) as Node3D
	node.reparent(parent, false)
	return node

func _own(node: Node) -> void:
	for child: Node in node.get_children():
		child.owner = map
		# Instance internals belong to their own packed scene. Saving them again
		# as map children creates duplicate meshes on load and orphaned resources.
		if child.scene_file_path.is_empty(): _own(child)

func _group(parent: Node, node_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	parent.add_child(node)
	return node

func _box(parent: Node, node_name: String, at: Vector3, size: Vector3, color: Color, solid: bool = true) -> void:
	var body: Node3D = StaticBody3D.new() if solid else Node3D.new()
	body.name = node_name
	parent.add_child(body, true)
	body.position = at
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	mesh.material_override = material
	body.add_child(mesh)
	if solid:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)

func _label(parent: Node, words: String, at: Vector3, pixels: float) -> void:
	var label := Label3D.new()
	label.text = words
	label.font_size = 48
	label.pixel_size = pixels
	label.position = at
	label.modulate = Color("e1eade")
	parent.add_child(label)

func _ramp(parent: Node3D, at: Vector3, height: float, length: float) -> void:
	var body := StaticBody3D.new()
	body.name = "TestRamp"
	body.add_to_group("diner_static", true)
	body.position = at
	parent.add_child(body)
	var points := PackedVector3Array([Vector3(-0.6, 0, 0), Vector3(0.6, 0, 0),
		Vector3(-0.6, 0, -length), Vector3(0.6, 0, -length), Vector3(-0.6, height, -length), Vector3(0.6, height, -length)])
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	var mesh := MeshInstance3D.new()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Solid faces make the ramp surface legible from insect height.
	for face: Array in [[0, 1, 2], [1, 3, 2], [0, 4, 1], [1, 4, 5],
		[0, 2, 4], [1, 5, 3], [2, 3, 4], [3, 5, 4]]:
		for index: int in face: surface.add_vertex(points[index])
	surface.generate_normals()
	mesh.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("a8bc9e")
	mesh.material_override = material
	body.add_child(mesh)
