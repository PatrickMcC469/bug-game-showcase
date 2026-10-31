extends "res://scripts/tools/diner_makeover.gd"
## Adds static cookware, controls and flame visuals to the saved range geometry.
func dress_kitchen(target: Node3D) -> void:
	map = target
	for key: String in ["steel", "rubber", "red"]: materials[key] = _material(key)
	materials["iron"] = _solid(Color("252a28"), 0.75)
	materials["iron"].metallic = 0.55
	_remove("KitchenEquipment")
	var equipment := _group(map, "KitchenEquipment")
	var routes := _group(equipment, "ClimbSpots")
	var climb_scene := load("res://scenes/game/props/roach_climb_spot.tscn") as PackedScene
	for i: int in 4:
		var station := map.get_node("HotLineDetails/Range%d" % (i + 1)) as Node3D
		station.add_to_group("kitchen_stoves", true)
		for child_name: String in ["Controls", "FloorControl", "HandControl", "GasStatus"]:
			var previous := station.get_node_or_null(child_name)
			if previous != null: previous.free()
		var controls := _group(station, "Controls")
		_box(controls, "GasLinkage", Vector3(0, 0.48, 0.77), Vector3(0.012, 0.86, 0.012), "steel", false)
		for y: float in [0.045, 0.92]:
			_box(controls, "ValveBacking", Vector3(0, y, 0.79), Vector3(0.09, 0.06, 0.024), "iron", false)
			var lever := _group(controls, "GasLever")
			lever.position = Vector3(0, y, 0.81)
			_box(lever, "Grip", Vector3.ZERO, Vector3(0.012, 0.052, 0.014), "red", false)
			var marker := Marker3D.new()
			_add(marker, station, "FloorControl" if y < 0.1 else "HandControl")
			marker.position = Vector3(0, y, 0.83)
		var burners := station.find_children("FlameOrigin", "Marker3D", true, false)
		for j: int in burners.size():
			var origin := burners[j] as Marker3D
			# A pot bottom shields its interior: its flames stay below the cookware.
			var covered := (i == 0 and j == 0) or (i == 1 and j == 3) or (i == 3 and j == 2)
			var height := 0.045 if covered else 0.14
			origin.set_meta("flame_height", height)
			_flame_visual(origin, height)
			if covered:
				var pot := _cookware(equipment, "Saucepan" if i == 0 else "FryingPan" if i == 1 else "StockPot",
					0.15 if i == 0 else 0.21, 0.17 if i == 0 else 0.05 if i == 1 else 0.29)
				pot.position = origin.global_position - map.global_position
				pot.position.y = 1.114
		var route := climb_scene.instantiate() as Node3D
		_add(route, routes, "Range%d" % (i + 1))
		route.position = Vector3(station.position.x + 0.93, 0, -5.03)
		route.height = 1.08
		route.destination_name = "Stove %d · hot when lit" % (i + 1)
	var fryer := map.get_node("HotLineDetails/TwinBasketFryer") as Node3D
	for basket: Node3D in fryer.get_children():
		if not str(basket.name).begins_with("WireBasket"): continue
		var previous := basket.get_node_or_null("WireCollision")
		if previous != null: previous.free()
		var body := StaticBody3D.new()
		_add(body, basket, "WireCollision")
		body.add_to_group("diner_static", true)
		var shape := CollisionShape3D.new()
		shape.shape = (basket.get_node("WireMesh") as MeshInstance3D).mesh.create_trimesh_shape()
		_add(shape, body, "Collision")
	var route := climb_scene.instantiate() as Node3D
	_add(route, routes, "FryerRim")
	route.position = Vector3(-6.89, 0, -5.41)
	route.height = 1.10
	route.destination_name = "Fryer rim · lethal oil"

func _flame_visual(origin: Marker3D, height: float) -> void:
	var previous := origin.get_node_or_null("FlameEffect")
	if previous != null: previous.free()
	var effect := _group(origin, "FlameEffect")
	effect.visible = false
	var flames := MeshInstance3D.new()
	_add(flames, effect, "GasJets")
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var jet := Detail.lathe([Vector2(0.007, 0), Vector2(0.010, 0.2), Vector2(0.006, 0.55), Vector2(0.0001, 1.0)], 12)
	for i: int in 20:
		var angle := TAU * i / 20
		surface.append_from(jet, 0, Transform3D(Basis.IDENTITY.scaled(Vector3(1, height, 1)), Vector3(sin(angle) * 0.112, 0, cos(angle) * 0.112)))
	flames.mesh = surface.commit()
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/shaders/stove_flame.gdshader")
	material.set_shader_parameter("flame_height", height)
	flames.material_override = material
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	_add(light, effect, "FlameLight")
	light.position.y = 0.04
	light.light_color = Color("528eff")
	light.light_energy = 0.18
	light.omni_range = 0.5
	light.shadow_enabled = false

func _cookware(parent: Node3D, node_name: String, radius: float, height: float) -> Node3D:
	var body := StaticBody3D.new()
	_add(body, parent, node_name)
	body.add_to_group("diner_static", true)
	var mesh := _lathe_part(body, "Vessel", [Vector2(0.001, 0), Vector2(radius * 0.8, 0),
		Vector2(radius, height * 0.85), Vector2(radius, height), Vector2(radius - 0.007, height),
		Vector2(radius * 0.8 - 0.007, 0.009), Vector2(0.001, 0.009)], "iron" if node_name == "FryingPan" else "steel")
	var collision := CollisionShape3D.new()
	collision.shape = mesh.mesh.create_trimesh_shape()
	_add(collision, body, "Collision")
	if node_name == "StockPot":
		for x: float in [-1, 1]:
			_box(body, "Handle", Vector3(x * (radius + 0.05), height * 0.7, 0), Vector3(0.11, 0.026, 0.085), "steel")
	else:
		var handle := _box(body, "LongHandle", Vector3(radius + 0.125, height * 0.65, 0), Vector3(0.27, 0.028, 0.038), "iron")
		handle.rotation.z = 0.08
	return body
