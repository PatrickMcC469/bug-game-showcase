extends "res://scripts/tools/diner_makeover.gd"
## Offline Godot-native pressure sprayer and reusable truck charging cradle.
func build_assets() -> void:
	for key: String in ["steel", "rubber", "cream"]: materials[key] = _material(key)
	materials["paint"] = _solid(Color("657647"), 0.72)
	materials["brass"] = _solid(Color("b99b56"), 0.4)
	materials["brass"].metallic = 0.65
	map = Node3D.new()
	map.name = "GasGunModel"
	_box(map, "Receiver", Vector3.ZERO, Vector3(0.075, 0.085, 0.22), "paint", false)
	var handle := _box(map, "Grip", Vector3(0, -0.095, 0.065), Vector3(0.052, 0.15, 0.06), "rubber", false)
	handle.rotation.x = -0.18
	_box(map, "ShoulderPad", Vector3(0, -0.005, 0.19), Vector3(0.078, 0.10, 0.16), "rubber", false)
	_cylinder_part("PressureTank", Vector3(0, -0.16, -0.15), 0.09, 0.22, "paint", false)
	for y: float in [-0.25, -0.075]: _cylinder_part("TankBand", Vector3(0, y, -0.15), 0.093, 0.025, "steel", false)
	_cylinder_part("Valve", Vector3(0, -0.035, -0.15), 0.035, 0.055, "brass", false)
	_cylinder_part("NozzleTube", Vector3(0, 0, -0.27), 0.021, 0.29, "steel", true)
	_cylinder_part("NozzleCollar", Vector3(0, 0, -0.40), 0.034, 0.055, "brass", true)
	_cylinder_part("Bore", Vector3(0, 0, -0.43), 0.025, 0.003, "rubber", true)
	for i: int in 5: _box(map, "CoolingRib", Vector3(0, 0, -0.18 - i * 0.035), Vector3(0.06, 0.065, 0.009), "rubber", false)
	_box(map, "TriggerGuard", Vector3(0, -0.10, -0.005), Vector3(0.025, 0.012, 0.075), "steel", false)
	_box(map, "GuardFront", Vector3(0, -0.068, -0.04), Vector3(0.025, 0.075, 0.012), "steel", false)
	_box(map, "Trigger", Vector3(0, -0.055, 0.015), Vector3(0.009, 0.035, 0.012), "brass", false)
	_box(map, "GaugeBacking", Vector3(0.045, 0.022, -0.005), Vector3(0.014, 0.055, 0.065), "steel", false)
	_box(map, "Gauge", Vector3(0.053, 0.022, -0.005), Vector3(0.002, 0.043, 0.052), "cream", false)
	var needle := _box(map, "GaugeNeedle", Vector3(0.055, 0.026, -0.005), Vector3(0.003, 0.003, 0.036), "rubber", false)
	needle.rotation.x = 0.5
	var muzzle := Marker3D.new()
	_add(muzzle, map, "Muzzle")
	muzzle.position.z = -0.435
	_save("res://scenes/game/weapons/gas_gun_model.tscn")
	map.free()
	map = Node3D.new()
	map.name = "GasRefillStation"
	map.add_to_group("gas_refill_stations", true)
	_box(map, "Backing", Vector3.ZERO, Vector3(0.65, 0.6, 0.045), "paint", false)
	_box(map, "Shelf", Vector3(0, -0.28, 0.17), Vector3(0.65, 0.035, 0.35), "steel", false)
	for x: float in [-0.2, 0.2]: _box(map, "Cradle", Vector3(x, -0.2, 0.13), Vector3(0.035, 0.15, 0.06), "rubber", false)
	var gun := load("res://scenes/game/weapons/gas_gun_model.tscn").instantiate() as Node3D
	_add(gun, map, "DockedGun")
	gun.position = Vector3(0.08, 0.04, 0.13)
	gun.rotation.y = PI / 2
	var control := Marker3D.new()
	_add(control, map, "Control")
	control.position = Vector3(0, 0, 0.45)
	var status := Label3D.new()
	_add(status, map, "Status")
	status.position = Vector3(0, 0.37, 0.035)
	status.text = "GAS / READY"
	status.pixel_size = 0.0013
	status.font_size = 36
	_label(map, "REFILL CRADLE", Vector3(0, -0.28, 0.351), 0.00045)
	_save("res://scenes/game/props/gas_refill_station.tscn")
	map.free()

func fit_truck() -> void:
	var path := "res://scenes/game/props/exterminator_truck.tscn"
	map = load(path).instantiate()
	_remove("Workshop/GasRefillStation")
	var station := load("res://scenes/game/props/gas_refill_station.tscn").instantiate() as Node3D
	_add(station, map.get_node("Workshop"), "GasRefillStation")
	# Opposite the equipment silhouettes, accessible from the rear workshop.
	station.position = Vector3(1.17, 1.95, 2.0)
	station.rotation.y = -PI / 2
	_save(path)
	map.free()

func _cylinder_part(node_name: String, at: Vector3, radius: float, height: float, material: String, barrel: bool) -> void:
	var part := MeshInstance3D.new()
	part.mesh = CylinderMesh.new()
	part.mesh.top_radius = radius
	part.mesh.bottom_radius = radius
	part.mesh.height = height
	part.mesh.radial_segments = 24
	part.material_override = materials[material]
	_add(part, map, node_name)
	part.position = at
	if barrel: part.rotation.x = PI / 2

func _save(path: String) -> void:
	var scene := PackedScene.new()
	var error := scene.pack(map)
	if error == OK: error = ResourceSaver.save(scene, path)
	assert(error == OK, "Gas asset save failed: " + path)
