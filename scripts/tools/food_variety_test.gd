extends SceneTree
const Types := preload("res://scripts/game/food_types.gd")
var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_check(Types.definition(&"missing") == null, "unknown food silently became a valid food")
	var effects: Array[int] = []
	for id: StringName in Types.IDS:
		var food := Types.definition(id)
		_check(food != null, "definition missing: " + str(id))
		if food == null: continue
		_check(food.food_id == id and food.validate().is_empty(), "invalid profile: " + str(id))
		effects.append(food.effect)
		var copy := Types.definition(id)
		copy.speed_multiplier = 1.9
		_check(not is_equal_approx(food.speed_multiplier, copy.speed_multiplier), "mutable profile leaked between instances")
		var model := Types.model(id)
		root.add_child(model)
		_check(model.scale == Vector3.ONE and model.get_meta("food_id") == str(id), "model identity/scale invalid")
		_check(model.get_node_or_null("CarryAnchor") is Marker3D, "carry attachment marker missing")
		var bounds := AABB()
		var first := true
		var triangles := 0
		for node: Node in model.find_children("*", "", true, false):
			_check(node.get_script() == null, "food asset has live behavior before carry integration")
			_check(not node is Label3D and not node is Light3D and not node is GPUParticles3D, "automatic food clue in model")
			if not node is MeshInstance3D: continue
			var box: AABB = model.global_transform.affine_inverse() * node.global_transform * node.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
			for surface: int in node.mesh.get_surface_count():
				var arrays: Array = node.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				for vertex: Vector3 in vertices: _check(vertex.is_finite(), "nonfinite vertex")
				for normal: Vector3 in normals: _check(normal.is_finite() and normal.length() > 0.5, "invalid mesh normal")
				triangles += (arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null and arrays[Mesh.ARRAY_INDEX].size() > 0 else vertices.size()) / 3
		_check(not first and triangles < 20000, "missing geometry / excessive food triangle count")
		_check(absf(bounds.position.y) < 0.00005, "food does not rest on floor: " + str(id))
		_check(bounds.size.length() > 0.015 and bounds.size.length() < 0.08, "food not at insect-compatible scale")
		var second := Types.model(id)
		root.add_child(second)
		model.position.x = 1.0
		_check(second.position.x == 0, "food instances share transform")
		model.free()
		second.free()
	_check(effects.size() == 4 and effects[0] != effects[1] and effects[1] != effects[2] and effects[2] != effects[3], "food effects not distinct")
	var invalid := Types.definition(&"spicy_pepper")
	invalid.damage_per_second = -1
	_check(not invalid.validate().is_empty(), "negative damage accepted")
	var grease := Types.definition(&"french_fry")
	grease.trip_immunity_seconds = 0.1
	_check(not grease.validate().is_empty(), "chain-trip tuning accepted")
	for failure: String in _failures: printerr("FOOD VARIETY FAIL: " + failure)
	print("FOOD VARIETY TEST: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok and message not in _failures: _failures.append(message)
