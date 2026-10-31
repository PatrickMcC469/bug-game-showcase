extends SceneTree
## Character-specific guards: finite geometry, practical budget, anatomical
## scale, planted soles and scene/script integration across both player roles.
var failures: Array[String] = []
var triangles := 0
var meshes := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/game/exterminator_model.tscn") as PackedScene
	if packed == null:
		failures.append("packed model failed to load")
		_finish()
		return
	var model := packed.instantiate() as Node3D
	root.add_child(model)
	model.set_process(false)
	_check_arms(model,true)
	_scan(model)
	var bounds := _bounds(model,model)
	_check(bounds.position.y > -0.01 and bounds.end.y < 2.16,"model fits established human height and floor")
	_check(bounds.size.y > 2.0,"human retains realistic full height")
	_check(triangles < 110000,"triangle count exceeds 110k regression ceiling")
	_check(meshes < 85,"mesh count exceeds batching budget")
	for speed: float in [0.0,1.4,5.5]:
		model.set("motion_speed",speed)
		for frame: int in 180:
			model.call("_process",1.0/60.0)
			_check_arms(model,is_zero_approx(speed))
			for path: String in ["LegLeft/Shin/Foot","LegRight/Shin/Foot"]:
				var foot := model.get_node(path) as Node3D
				_check(foot.global_transform.is_finite(),"nonfinite foot pose")
				_check(foot.global_basis.y.dot(Vector3.UP)>0.999,"sole tilts away from local floor")
				_check(foot.global_position.y>=0.167,"sole penetrates floor")
				_check(foot.global_position.y<0.28,"foot lift exceeds stride contract")
			if not failures.is_empty(): break
	model.free()
	var token_scene := load("res://scenes/game/player_token.tscn") as PackedScene
	_check(token_scene != null,"player scene failed to load")
	if token_scene != null:
		var token := token_scene.instantiate()
		token.name = "1"
		root.add_child(token)
		token.call("configure_role","exterminator")
		var visual := token.get_node("ExterminatorModel") as Node3D
		_check(visual.scene_file_path == packed.resource_path,"player must instance reviewed character")
		_check(visual.visible and not (token.get_node("CockroachModel") as Node3D).visible,"exterminator role visibility")
		_check(is_equal_approx((token.get_node("ExterminatorCollision") as CollisionShape3D).shape.height,2.15),"human collider changed")
		token.call("configure_role","cockroach")
		_check(not visual.visible and (token.get_node("CockroachModel") as Node3D).visible,"cockroach role visibility")
		token.free()
	_finish()

func _check_arms(model: Node3D, resting: bool) -> void:
	for path: String in ["BodyRoot/ArmLeft","BodyRoot/ArmRight"]:
		var upper := model.get_node(path) as Node3D
		var elbow := upper.get_node("Forearm") as Node3D
		var hand := elbow.get_node("Hand") as Node3D
		var wrist_from_elbow := upper.to_local(hand.global_position)-elbow.position
		_check(wrist_from_elbow.is_finite(),"nonfinite arm pose")
		_check(wrist_from_elbow.z < -0.04,"elbow must flex toward the character front")
		if resting:
			_check(model.to_local(hand.global_position).z < model.to_local(upper.global_position).z,
				"resting hands must sit in front of shoulders")
			var side := signf(upper.position.x)
			var local_basis := model.global_basis.inverse()*hand.global_basis
			_check((-local_basis.z).dot(Vector3(-side,0,0))>0.8,
				"resting palms must face toward the thighs")
			_check((local_basis.x*side).dot(Vector3.FORWARD)>0.8,
				"resting thumb edges must face forward on both hands")

func _scan(node: Node) -> void:
	if node is MeshInstance3D:
		meshes += 1
		for i: int in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(i)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null: indices = arrays[Mesh.ARRAY_INDEX]
			triangles += (indices.size() if not indices.is_empty() else vertices.size())/3
			for vertex: Vector3 in vertices:
				_check(vertex.is_finite(),"nonfinite vertex")
			for normal: Vector3 in normals:
				_check(normal.is_finite() and normal.length()>0.8,"invalid normal")
	for child: Node in node.get_children(): _scan(child)

func _bounds(node: Node, model: Node3D) -> AABB:
	var result := AABB()
	if node is MeshInstance3D:
		result = (model.global_transform.affine_inverse()*node.global_transform)*node.get_aabb()
	for child: Node in node.get_children():
		var next := _bounds(child,model)
		if next.size != Vector3.ZERO:
			result = next if result.size == Vector3.ZERO else result.merge(next)
	return result

func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message): failures.append(message)

func _finish() -> void:
	print("EXTERMINATOR GEOMETRY: %d triangles, %d mesh instances" % [triangles,meshes])
	for failure: String in failures: push_error(failure)
	print("EXTERMINATOR ASSET TEST: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
