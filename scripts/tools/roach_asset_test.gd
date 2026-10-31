extends SceneTree
## Checks observable asset contracts: ground contact, finite poses, mesh budget,
## per-instance tint isolation and recovery after a dash. No networking needed.

var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var packed := load("res://scenes/game/cockroach_model.tscn") as PackedScene
	var roach := packed.instantiate() as Node3D
	var other := packed.instantiate() as Node3D
	root.add_child(roach)
	root.add_child(other)
	roach.set_process(false)
	other.set_process(false)
	var untouched := (other.get_node("BodyRoot/ElytronLeft") as MeshInstance3D).material_override as ShaderMaterial
	var original_color: Color = untouched.get_shader_parameter("base_color")
	roach.call("set_peer_color", Color.RED)
	_check(untouched.get_shader_parameter("base_color") == original_color, "peer tint leaked into another instance")
	for side: String in ["Left", "Right"]:
		var antenna := roach.get_node("BodyRoot/Antenna" + side + "/Segment1") as MeshInstance3D
		var other_antenna := other.get_node("BodyRoot/Antenna" + side + "/Segment1") as MeshInstance3D
		_check(antenna.material_override != other_antenna.material_override, "antenna flex material shared across avatars")
		var socket := antenna.get_parent() as Node3D
		var proximal := antenna.to_global(Vector3(0.0, -0.84, 0.0))
		var distal := antenna.to_global(Vector3(0.0, 0.84, 0.0))
		_check(proximal.distance_to(socket.global_position) < 0.002, "antenna thick end detached from socket")
		_check(distal.distance_to(socket.global_position) > 1.6, "antenna tip does not extend from head")
	var other_flex := (other.get_node("BodyRoot/AntennaLeft/Segment1") as MeshInstance3D).material_override as ShaderMaterial
	var original_phase: Variant = other_flex.get_shader_parameter("antenna_phase")
	var mesh_nodes := roach.find_children("*", "MeshInstance3D", true, false)
	var triangles := 0
	var visible_meshes := 0
	for node: Node in mesh_nodes:
		var instance := node as MeshInstance3D
		if not instance.visible:
			continue
		visible_meshes += 1
		for surface_index: int in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangles += (indices.size() if not indices.is_empty() else vertices.size()) / 3
			for vertex: Vector3 in vertices:
				_check(vertex.is_finite(), "non-finite mesh vertex")
	_check(triangles < 100000, "asset exceeds 100k triangle budget")
	for speed: float in [0.0, 2.0, 5.5, 8.0, 13.0]:
		roach.set("motion_speed", speed)
		roach.set("is_dashing", speed > 10.0)
		for frame: int in 180:
			roach.rotation.y += 0.007 if frame < 90 else -0.007
			roach.call("_process", 1.0 / 120.0)
			var planted := 0
			for leg: Node in roach.get_children():
				if not str(leg.name).begins_with("Leg"):
					continue
				var foot := leg.get_node("Femur/Tibia/Tarsus/FootPad") as Node3D
				var height := roach.to_local(foot.global_position).y
				_check(is_finite(height) and height >= 0.025 and height <= 0.14, "foot leaves valid ground/swing envelope at speed %s: %s" % [speed, height])
				if height < 0.04:
					planted += 1
			_check(planted >= 3, "no supporting tripod at speed %s" % speed)
	roach.set("motion_speed", 0.0)
	roach.set("is_dashing", false)
	for frame: int in 240:
		roach.call("_process", 1.0 / 120.0)
	_check(absf((roach.get_node("BodyRoot") as Node3D).position.y - 0.24) < 0.002, "dash crouch did not recover")
	_check(other_flex.get_shader_parameter("antenna_phase") == original_phase, "antenna animation leaked between avatars")
	for node: Node in mesh_nodes:
		_check((node as Node3D).transform.is_finite(), "non-finite resting transform")
	print("ROACH ASSET: %d visible mesh nodes, %d triangles" % [visible_meshes, triangles])
	roach.free()
	other.free()
	if _failures.is_empty():
		print("ROACH ASSET TEST: PASS")
		quit()
	else:
		for failure: String in _failures:
			push_error(failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
