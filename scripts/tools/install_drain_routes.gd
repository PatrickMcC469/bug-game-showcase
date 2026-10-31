extends SceneTree
## Reusable endpoint geometry, map-owned paths; never hard-code travel in actors.
func _initialize() -> void: install.call_deferred()
func install() -> void:
	var ok := true
	for dev: bool in [false, true]:
		var path := "res://scenes/game/maps/dev_room_map.tscn" if dev else "res://scenes/game/maps/diner_kitchen.tscn"
		var map: Node3D = load(path).instantiate()
		root.add_child(map)
		add_routes(map, dev)
		var packed := PackedScene.new()
		var error := packed.pack(map)
		if error == OK: error = ResourceSaver.save(packed, path)
		ok = ok and error == OK
		map.free()
	print("DRAIN ROUTES INSTALL: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
static func add_routes(map: Node3D, dev: bool) -> void:
	for label: String in ["DrainRoutes", "ExteriorDrainPipe"]:
		var old := map.get_node_or_null(label)
		if old != null: old.free()
	var outlet: Node3D = load("res://scenes/game/props/exterior_drain_pipe.tscn").instantiate()
	outlet.name = "ExteriorDrainPipe"
	outlet.position = Vector3(4.85, 0, -7.15) if not dev else Vector3(8, 0, 18.8)
	outlet.rotation.y = PI if not dev else 0.0
	map.add_child(outlet)
	outlet.owner = map
	var routes := Node3D.new()
	routes.name = "DrainRoutes"
	map.add_child(routes)
	routes.owner = map
	var link := Node3D.new()
	link.set_script(load("res://scripts/game/drain_route.gd"))
	link.name = "KitchenDrain"
	routes.add_child(link)
	link.owner = map
	var sink := map.get_node(("climbing" if dev else "DishPit") + "/CommercialDishStation/DrainEntrance")
	link.sink_path = link.get_path_to(sink)
	link.outside_path = link.get_path_to(outlet)
