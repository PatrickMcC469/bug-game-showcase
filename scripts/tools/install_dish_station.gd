extends SceneTree
## Scoped installer: preserves dish-table food/climb paths and unrelated art.
const MAP := "res://scenes/game/maps/diner_kitchen.tscn"
func _initialize() -> void: install.call_deferred()
func install() -> void:
	var map: Node3D = load(MAP).instantiate()
	root.add_child(map)
	var dish: Node3D = map.get_node("DishPit")
	for path: String in ["Atmosphere/FixtureBatches/DishPitBaked", "DishPit/RetainedBatches", "DishPit/CommercialDishStation"]:
		var old := map.get_node_or_null(path)
		if old != null: old.free()
	# Old fixture geometry was hidden behind a dish-pit-only render batch.
	# Restore only its sources so the retired sink cannot remain as ghost art.
	for mesh: MeshInstance3D in dish.find_children("*", "MeshInstance3D", true, false):
		if mesh.has_meta("atmosphere_batched"):
			mesh.visible = true
			mesh.remove_meta("atmosphere_batched")
	for node: Node in dish.get_children():
		for prefix: String in ["SinkLine", "Basin", "SinkDrain", "Tap", "GooseneckTap"]:
			if str(node.name).begins_with(prefix):
				node.free()
				break
	batch_retained(dish, map)
	var station: Node3D = load("res://scenes/game/props/commercial_dish_station.tscn").instantiate()
	station.name = "CommercialDishStation"
	station.position = Vector3(7.34, 0, -1.60)
	station.rotation.y = -PI / 2
	dish.add_child(station)
	station.owner = map
	var packed := PackedScene.new()
	var error := packed.pack(map)
	if error == OK: error = ResourceSaver.save(packed, MAP)
	print("DISH STATION INSTALL: ", "PASS" if error == OK else error_string(error))
	map.free()
	if error == OK: error = install_dev_fixture()
	quit(0 if error == OK else 1)
func install_dev_fixture() -> Error:
	var path := "res://scenes/game/maps/dev_room_map.tscn"
	var map: Node3D = load(path).instantiate()
	root.add_child(map)
	var parent := map.get_node("climbing")
	var old := parent.get_node_or_null("CommercialDishStation")
	if old != null: old.free()
	var station: Node3D = load("res://scenes/game/props/commercial_dish_station.tscn").instantiate()
	station.name = "CommercialDishStation"
	station.position = Vector3(0, 0, 5)
	parent.add_child(station)
	station.owner = map
	var packed := PackedScene.new()
	var error := packed.pack(map)
	if error == OK: error = ResourceSaver.save(packed, path)
	map.free()
	print("DISH STATION DEV INSTALL: ", "PASS" if error == OK else error_string(error))
	return error
func batch_retained(dish: Node3D, map: Node3D) -> void:
	var batches := Node3D.new()
	batches.name = "RetainedBatches"
	dish.add_child(batches)
	batches.owner = map
	var surfaces: Dictionary = {}
	var materials: Dictionary = {}
	for mesh: MeshInstance3D in dish.find_children("*", "MeshInstance3D", true, false):
		if not mesh.visible or mesh.material_override == null or mesh.mesh.get_surface_count() != 1: continue
		var id := mesh.material_override.get_instance_id()
		if not surfaces.has(id):
			surfaces[id] = SurfaceTool.new()
			surfaces[id].begin(Mesh.PRIMITIVE_TRIANGLES)
			materials[id] = mesh.material_override
		surfaces[id].append_from(mesh.mesh, 0, batches.global_transform.affine_inverse() * mesh.global_transform)
		mesh.visible = false
		mesh.set_meta("atmosphere_batched", true)
	for id: int in surfaces:
		var visual := MeshInstance3D.new()
		visual.name = "RetainedSurface"
		visual.mesh = surfaces[id].commit()
		visual.material_override = materials[id]
		batches.add_child(visual, true)
		visual.owner = map
