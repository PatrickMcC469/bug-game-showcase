extends "res://scripts/tools/diner_makeover.gd"
## Offline replacement of solid range cabinets with real oven cavities.
func build_ovens(target: Node3D) -> void:
	map = target
	for key: String in ["steel", "rubber", "red"]: materials[key] = _material(key)
	materials["enamel"] = _solid(Color("303632"), 0.76)
	materials["glass"] = _solid(Color(0.13, 0.18, 0.16, 0.32), 0.18)
	materials["glass"].transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	materials["hot"] = _solid(Color("e35418"), 0.6)
	materials["hot"].emission_enabled = true
	materials["hot"].emission = Color("ff5b12")
	materials["hot"].emission_energy_multiplier = 1.4
	_remove("OvenInteriors")
	var ovens := _group(map, "OvenInteriors")
	for i: int in 4:
		var cabinet := map.get_node("PrepLine/CookLine" + (str(i + 1) if i > 0 else "")) as Node3D
		cabinet.get_node("Mesh").visible = false
		cabinet.get_node("Collision").disabled = true
		cabinet.get_node("FrontPanel").visible = false
		var range_top := map.get_node("HotLineDetails/Range%d" % (i + 1)) as Node3D
		for child: Node in range_top.get_children():
			if str(child.name).begins_with("Oven") or str(child.name).begins_with("DoorHandle") or str(child.name).begins_with("HandleBracket"):
				child.free()
		# Keep the existing burner linkage beside, rather than across, the door.
		range_top.get_node("Controls").position.x = -0.99
		range_top.get_node("FloorControl").position.x = -0.99
		range_top.get_node("HandControl").position.x = -0.99
		range_top.get_node("GasStatus").position.x = -0.80
		# New front jambs stand forward of the old cabinet face. Keep the grip
		# route outside that face, then round onto the unchanged top deck.
		map.get_node("KitchenEquipment/ClimbSpots/Range%d" % (i + 1)).position.z = -5.01
		var oven := _group(ovens, "Oven%d" % (i + 1))
		oven.position = range_top.position
		oven.add_to_group("kitchen_ovens", true)
		for x: float in [-0.995, 0.995]:
			_box(oven, "SideWall", Vector3(x, 0.51, 0), Vector3(0.08, 1.02, 1.44), "steel")
		_box(oven, "BackWall", Vector3(0, 0.51, -0.685), Vector3(1.91, 1.02, 0.07), "enamel")
		_box(oven, "Ceiling", Vector3(0, 0.94, 0), Vector3(1.91, 0.16, 1.44), "enamel")
		# A flush lower chamber lets centimetre-size bugs use the vent without ramps.
		_box(oven, "Floor", Vector3(0, -0.0098, 0), Vector3(1.91, 0.02, 1.44), "enamel")
		for x: float in [-0.9775, 0.9775]:
			_box(oven, "FrontJamb", Vector3(x, 0.51, 0.735), Vector3(0.115, 1.02, 0.10), "steel")
		_box(oven, "ControlPanel", Vector3(0, 0.93, 0.735), Vector3(1.84, 0.18, 0.10), "steel")
		_box(oven, "VentLeft", Vector3(-0.84, 0.1, 0.735), Vector3(0.16, 0.20, 0.10), "steel")
		_box(oven, "VentRight", Vector3(0.14, 0.1, 0.735), Vector3(1.56, 0.20, 0.10), "steel")
		_box(oven, "VentHeader", Vector3(-0.70, 0.1325, 0.735), Vector3(0.12, 0.135, 0.10), "steel")
		# Rack rods stay separate so insects can move above and beneath them.
		for y: float in [0.30, 0.58]:
			for x: float in [-0.90, 0.90]: _box(oven, "RackRail", Vector3(x, y, 0), Vector3(0.025, 0.022, 1.22), "steel")
			for z: float in [-0.57, 0.56]: _box(oven, "RackFrame", Vector3(0, y, z), Vector3(1.82, 0.015, 0.015), "steel")
			for bar: int in 11: _box(oven, "RackBar", Vector3(-0.82 + bar * 0.164, y, 0), Vector3(0.012, 0.012, 1.12), "steel")
		var heat := _group(oven, "HeatGlow")
		heat.visible = false
		for row: int in 4:
			_box(heat, "Element", Vector3(0, 0.12 + row * 0.17, -0.643), Vector3(1.45, 0.016, 0.012), "hot", false)
		var lamp := OmniLight3D.new()
		_add(lamp, heat, "WarmLight")
		lamp.position = Vector3(0, 0.6, -0.25)
		lamp.light_color = Color("ff8438")
		lamp.light_energy = 1.0
		lamp.omni_range = 1.2
		lamp.shadow_enabled = true
		_door(oven)
		_marker(oven, "HumanControl", Vector3(0.52, 0.92, 0.84))
		_marker(oven, "OutsideShutoff", Vector3(-0.55, 0.035, 0.83))
		_marker(oven, "InsideShutoff", Vector3(-0.55, 0.035, 0.62))
		for z: float in [0.805, 0.62]:
			_box(oven, "ShutoffBacking", Vector3(-0.55, 0.034, z), Vector3(0.075, 0.055, 0.014), "rubber", false)
			_box(oven, "Shutoff", Vector3(-0.55, 0.034, z + 0.01), Vector3(0.03, 0.032, 0.012), "red", false)
		_box(oven, "HeatSwitch", Vector3(0.52, 0.92, 0.80), Vector3(0.045, 0.065, 0.025), "red", false)
		for z: float in [0.95, 0.50]: _marker(oven, "BugEntrance" if z > 0.8 else "BugInterior", Vector3(-0.70, 0.001, z))
		_marker(oven, "ScrapPlacement", Vector3(0.35, 0.004, -0.32))

func _marker(parent: Node3D, node_name: String, at: Vector3) -> void:
	var marker := Marker3D.new()
	_add(marker, parent, node_name)
	marker.position = at

func _door(oven: Node3D) -> void:
	var door := AnimatableBody3D.new()
	door.sync_to_physics = false
	_add(door, oven, "Door")
	door.position = Vector3(0, 0.20, 0.76)
	for x: float in [-0.84, 0.84]: _box(door, "SideFrame", Vector3(x, 0.315, 0), Vector3(0.16, 0.63, 0.06), "steel", false)
	for y: float in [0.065, 0.565]: _box(door, "EndFrame", Vector3(0, y, 0), Vector3(1.52, 0.13, 0.06), "steel", false)
	_box(door, "Window", Vector3(0, 0.315, 0), Vector3(1.52, 0.37, 0.028), "glass", false)
	_box(door, "Handle", Vector3(0, 0.53, 0.11), Vector3(1.3, 0.035, 0.035), "rubber", false)
	for x: float in [-0.60, 0.60]: _box(door, "HandleMount", Vector3(x, 0.53, 0.055), Vector3(0.035, 0.045, 0.11), "steel", false)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.84, 0.63, 0.06)
	collision.shape = shape
	collision.position.y = 0.315
	_add(collision, door, "Collision")
	var handle_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.30, 0.035, 0.145)
	handle_shape.shape = box
	handle_shape.position = Vector3(0, 0.53, 0.055)
	_add(handle_shape, door, "HandleCollision")
