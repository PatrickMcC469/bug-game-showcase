extends "res://scripts/tools/diner_makeover.gd"
## Offline construction: hollow storage and continuous, floor-level crawl ducts.
const CELL := 0.16
const ORIGIN := Vector3(-8.1, 0, -0.8)

func build_hiding(target: Node3D) -> void:
	map = target
	for key: String in ["steel", "wood", "cream", "rubber", "wall"]: materials[key] = _material(key)
	materials["paint"] = _solid(Color("52665d"), 0.8)
	materials["duct"] = _solid(Color("7b8989"), 0.68)
	materials["duct"].metallic = 0.55
	materials["duct"].emission_enabled = true
	materials["duct"].emission = Color("132222")
	materials["duct"].emission_energy_multiplier = 0.25
	materials["guide"] = _solid(Color("77cdb5"), 0.7)
	materials["guide"].emission_enabled = true
	materials["guide"].emission = Color("77cdb5")
	materials["guide"].emission_energy_multiplier = 0.45
	_remove("HidingPlaces")
	# Replace the solid delivery carton at the new kitchen box's footprint.
	_remove("ServiceClutter/DeliveryCarton7")
	var storage := _group(map, "HidingPlaces")
	_cabinet(storage, "LobbyCabinet", Vector3(7.45, 0, 10), -PI / 2, Vector3(1.1, 0.95, 0.7))
	_cabinet(storage, "KitchenCabinet", Vector3(-7.15, 0, 5.15), PI / 2, Vector3(1.3, 2.5, 1.15))
	_crate(storage, "PantryBox", Vector3(-9.4, 0, -3.6), Vector3(0.65, 0.42, 0.55))
	_crate(storage, "KitchenBox", Vector3(-6.6, 0, 3.0), Vector3(0.85, 0.55, 0.70))
	_build_vents()

func _marker(parent: Node3D, node_name: String, at: Vector3) -> void:
	var marker := Marker3D.new()
	_add(marker, parent, node_name)
	marker.position = at

func _moving_box(parent: AnimatableBody3D, node_name: String, at: Vector3, size: Vector3, material: String) -> void:
	_box(parent, node_name, at, size, material, false)
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	collision.shape.size = size
	collision.position = at
	_add(collision, parent, node_name + "Collision")

func _shell(parent: Node3D, size: Vector3, material: String) -> void:
	# Flush floor: no centimetre-high threshold across an insect's entrance.
	_box(parent, "Floor", Vector3(0, -0.0098, 0), Vector3(size.x, 0.02, size.z), material)
	for x: float in [-1, 1]: _box(parent, "Side", Vector3(x * (size.x / 2 - 0.015), size.y / 2, 0), Vector3(0.03, size.y, size.z), material)
	_box(parent, "Back", Vector3(0, size.y / 2, -size.z / 2 + 0.015), Vector3(size.x - 0.06, size.y, 0.03), material)
	_marker(parent, "HiddenItemPlacement", Vector3(0.1, 0.004, -size.z * 0.25))
	_marker(parent, "Interior", Vector3(0, 0.001, 0))
	parent.add_to_group("openable_storage", true)

func _controls(parent: Node3D, depth: float, human_height: float) -> void:
	for outside: bool in [true, false]:
		var suffix := "Outside" if outside else "Inside"
		var z := depth / 2 + (0.07 if outside else -0.08)
		_marker(parent, "Bug" + suffix, Vector3(0, 0.032, z))
		_marker(parent, "Human" + suffix, Vector3(0, human_height, z))
		_box(parent, "PushTab" + suffix, Vector3(0.075, 0.031, z), Vector3(0.025, 0.025, 0.012), "guide", false)
	_marker(parent, "Approach", Vector3(0, 0.001, depth / 2 + 0.5))

func _cabinet(parent: Node3D, id: String, at: Vector3, yaw: float, size: Vector3) -> void:
	var cabinet := _group(parent, id)
	cabinet.position = at
	cabinet.rotation.y = yaw
	cabinet.set_meta("display_name", "storage cabinet")
	cabinet.set_meta("axis", Vector3.UP)
	cabinet.set_meta("open_angle", -PI * 0.52)
	_shell(cabinet, size, "paint")
	_box(cabinet, "Top", Vector3(0, size.y - 0.02, 0), Vector3(size.x, 0.04, size.z), "steel")
	# A high shelf leaves standing room in the tall cabinet.
	_box(cabinet, "Shelf", Vector3(0, size.y - 0.16, -0.015), Vector3(size.x - 0.06, 0.02, size.z - 0.06), "cream")
	var door := AnimatableBody3D.new()
	door.sync_to_physics = false
	_add(door, cabinet, "Door")
	door.position = Vector3(-size.x / 2 + 0.025, 0, size.z / 2)
	_moving_box(door, "Panel", Vector3((size.x - 0.05) / 2, (size.y + 0.06) / 2, 0), Vector3(size.x - 0.05, size.y - 0.06, 0.035), "paint")
	_moving_box(door, "Handle", Vector3(size.x - 0.15, minf(1.05, size.y * 0.65), 0.05), Vector3(0.025, 0.18, 0.025), "steel")
	for y: float in [size.y * 0.2, size.y * 0.8]: _box(door, "Hinge", Vector3(0, y, 0.014), Vector3(0.04, 0.10, 0.04), "steel", false)
	for i: int in 5: _box(door, "Louver", Vector3((size.x - 0.05) / 2, size.y - 0.25 - i * 0.035, 0.02), Vector3(size.x * 0.35, 0.01, 0.008), "rubber", false)
	_controls(cabinet, size.z, minf(0.95, size.y * 0.65))

func _crate(parent: Node3D, id: String, at: Vector3, size: Vector3) -> void:
	var box := _group(parent, id)
	box.position = at
	box.set_meta("display_name", "delivery box")
	box.set_meta("axis", Vector3.RIGHT)
	box.set_meta("open_angle", -PI * 0.60)
	_shell(box, size, "wood")
	# The low hand cutout is also a bug entrance, even with the lid down.
	for x: float in [-1, 1]: _box(box, "FrontSide", Vector3(x * (size.x + 0.12) / 4, size.y / 2, size.z / 2 - 0.015), Vector3((size.x - 0.12) / 2, size.y, 0.03), "wood")
	_box(box, "FrontHeader", Vector3(0, (size.y + 0.065) / 2, size.z / 2 - 0.015), Vector3(0.12, size.y - 0.065, 0.03), "wood")
	for x: float in [-size.x / 2 + 0.045, size.x / 2 - 0.045]:
		_box(box, "CornerStrap", Vector3(x, size.y / 2, size.z / 2 + 0.002), Vector3(0.035, size.y, 0.012), "steel", false)
	var lid := AnimatableBody3D.new()
	lid.sync_to_physics = false
	_add(lid, box, "Door")
	lid.position = Vector3(0, size.y, -size.z / 2)
	_moving_box(lid, "Lid", Vector3(0, 0, size.z / 2), Vector3(size.x + 0.025, 0.025, size.z + 0.025), "wood")
	for x: float in [-size.x * 0.3, size.x * 0.3]: _box(lid, "Brace", Vector3(x, 0.023, size.z / 2), Vector3(0.055, 0.02, size.z), "steel", false)
	_controls(box, size.z, size.y + 0.10)
	# Human inside marker is above the box; bugs use the reachable floor tabs.
	_label(box, "DRY GOODS", Vector3(0, size.y * 0.65, size.z / 2 + 0.018), 0.0008)

func _cut_wall(path: String, along_x: bool, center: float, width: float) -> void:
	var old := map.get_node(path) as StaticBody3D
	old.get_node("Mesh").visible = false
	old.get_node("Collision").disabled = true
	var shape: BoxShape3D = old.get_node("Collision").shape
	var extent := shape.size.x if along_x else shape.size.z
	var middle := old.position.x if along_x else old.position.z
	var low := maxf(center - width / 2, middle - extent / 2)
	var high := minf(center + width / 2, middle + extent / 2)
	center = (low + high) / 2
	width = high - low
	var local_cut := center - middle
	var parent := old.get_parent() as Node3D
	# Replace just this wall's solid geometry around a 12 cm floor aperture.
	for span: Vector2 in [Vector2(-extent / 2, local_cut - width / 2), Vector2(local_cut + width / 2, extent / 2)]:
		if span.y - span.x < 0.0001: continue
		var size := shape.size
		var at := old.position
		if along_x: size.x = span.y - span.x; at.x += (span.x + span.y) / 2
		else: size.z = span.y - span.x; at.z += (span.x + span.y) / 2
		_box(parent, str(old.name) + "VentSide", at, size, "wall")
	var size := shape.size
	var at := old.position
	size.y -= 0.12
	at.y += 0.06
	if along_x: size.x = width; at.x = center
	else: size.z = width; at.z = center
	_box(parent, str(old.name) + "VentHeader", at, size, "wall")

func _wall_chase(path: String, inner_mouths: Array, outer_mouths: Array) -> void:
	var old := map.get_node(path) as StaticBody3D
	old.get_node("Mesh").visible = false
	old.get_node("Collision").disabled = true
	var size: Vector3 = old.get_node("Collision").shape.size
	var parent := old.get_parent()
	_box(parent, str(old.name) + "VentHeader", old.position + Vector3(0, 0.06, 0), Vector3(size.x, size.y - 0.12, size.z), "wall")
	# Thin tiled skins conceal the duct within the existing wall thickness.
	for side: int in [-1, 1]:
		var cuts: Array = outer_mouths if side < 0 else inner_mouths
		var start := old.position.z - size.z / 2
		var end := old.position.z + size.z / 2
		var stops: Array[float] = [start]
		for cut: float in cuts:
			stops.append(cut - 0.082)
			stops.append(cut + 0.082)
		stops.append(end)
		for i: int in range(0, stops.size(), 2):
			_box(parent, str(old.name) + "VentSide", Vector3(old.position.x + side * 0.095, 0.06, (stops[i] + stops[i + 1]) / 2), Vector3(0.01, 0.12, stops[i + 1] - stops[i]), "wall")

func _build_vents() -> void:
	# Rebuild only generated wall patches, making the offline tool repeatable.
	for path: String in ["RestaurantExpansion/Shell", "RestaurantExpansion/WalkInPantry"]:
		for node: Node in map.get_node(path).get_children():
			if "VentSide" in str(node.name) or "VentHeader" in str(node.name): node.free()
	_wall_chase("RestaurantExpansion/Shell/WestSouth", [-0.8, 3.2], [-0.8])
	_wall_chase("RestaurantExpansion/Shell/DiningSide", [7.2], [])
	_cut_wall("RestaurantExpansion/Shell/DiningPartition", true, -8.1, 0.18)
	_cut_wall("RestaurantExpansion/WalkInPantry/EndWall2", true, -8.1, 0.18)
	_remove("BugVents")
	var vents := _group(map, "BugVents")
	var cells: Dictionary = {}
	for z: int in 51: cells[Vector2i(0, z)] = true
	var mouths := {Vector2i(0, 0): [Vector2i.LEFT, Vector2i.RIGHT], Vector2i(0, 25): [Vector2i.RIGHT], Vector2i(0, 50): [Vector2i.RIGHT]}
	for cell: Vector2i in cells:
		var section := _group(vents, "Duct_%d_%d" % [cell.x, cell.y])
		section.position = ORIGIN + Vector3(cell.x * CELL, 0, cell.y * CELL)
		_box(section, "Floor", Vector3(0, -0.0048, 0), Vector3(CELL, 0.01, CELL), "duct")
		_box(section, "Roof", Vector3(0, 0.105, 0), Vector3(CELL, 0.01, CELL), "duct")
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if cells.has(cell + direction) or direction in mouths.get(cell, []): continue
			var x_side := direction.x != 0
			_box(section, "Wall", Vector3(direction.x * 0.076, 0.05, direction.y * 0.076), Vector3(0.008 if x_side else CELL, 0.10, CELL if x_side else 0.008), "duct")
		if mouths.has(cell):
			for direction: Vector2i in mouths[cell]:
				var id := "Pantry" if direction.x < 0 else "KitchenNorth" if cell.y == 0 else "KitchenSouth" if cell.y == 25 else "Lobby"
				var at := section.position + Vector3(direction.x * 0.105, 0, 0)
				_marker(vents, id + "Entrance", at + Vector3(direction.x * 0.10, 0.001, 0))
				_marker(vents, id + "Inside", section.position + Vector3(0, 0.001, 0))
				var frame := _group(vents, id + "Mouth")
				frame.position = at
				frame.rotation.y = PI / 2 if direction.x > 0 else -PI / 2
				_box(frame, "Header", Vector3(0, 0.128, 0), Vector3(0.20, 0.025, 0.018), "steel")
				for x: float in [-0.09, 0.09]: _box(frame, "Jamb", Vector3(x, 0.064, 0), Vector3(0.02, 0.128, 0.018), "steel")
				for y: float in [0.080, 0.099, 0.118]:
					var fin := _box(frame, "Louver", Vector3(0, y, 0.005), Vector3(0.16, 0.008, 0.016), "steel")
					fin.rotation.x = -0.25
				# Two bent lower fins leave a believable damaged crawl opening.
				for x: float in [-0.066, 0.066]:
					var fin := _box(frame, "BentLouver", Vector3(x, 0.035, 0.01), Vector3(0.012, 0.06, 0.008), "steel")
					fin.rotation.z = -0.12 if x < 0 else 0.12
				for x: float in [-0.09, 0.09]:
					for y: float in [0.018, 0.124]:
						var screw := MeshInstance3D.new()
						screw.mesh = SphereMesh.new()
						screw.mesh.radius = 0.003
						screw.mesh.height = 0.006
						screw.material_override = materials["rubber"]
						_add(screw, frame, "Screw")
						screw.position = Vector3(x, y, 0.011)
