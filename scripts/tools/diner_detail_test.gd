extends SceneTree
## Geometry checks for the offline realism pass; no networking or game state.
const Detail := preload("res://scripts/tools/diner_detail_geometry.gd")
var _failures: Array[String] = []

func _initialize() -> void:
	var size := Vector3(10, 0.16, 3)
	var box := Detail.bevel_box(size, 0.012)
	_check(box.get_aabb().size.is_equal_approx(size), "bevel changed worktop extents")
	_check(box.get_aabb().position.is_equal_approx(-size * 0.5), "bevel moved worktop center")
	_check_mesh(box, "beveled worktop")
	# The open cylinder isolates the exterior winding of a revolved profile.
	# A reversed shell can otherwise look like a sliced/open mug in the game.
	var cylinder := Detail.lathe([Vector2(0.4, 0), Vector2(0.4, 1)])
	_check_mesh(cylinder, "revolved wall")
	var arrays := cylinder.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i: int in vertices.size():
		var outward := Vector3(vertices[i].x, 0, vertices[i].z).normalized()
		_check(normals[i].dot(outward) > 0.99, "revolved exterior faces inward")
	_check_mesh(Detail.pipe([Vector3.ZERO, Vector3.UP, Vector3(0.3, 1.3, 0), Vector3(1, 1.3, 0)], 0.035), "pipe")
	for failure: String in _failures:
		printerr("DINER DETAIL FAIL: " + failure)
	print("DINER DETAIL TEST: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)

func _check_mesh(mesh: ArrayMesh, label: String) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	_check(not vertices.is_empty() and vertices.size() == normals.size(), label + " has missing geometry/normals")
	for i: int in vertices.size():
		_check(vertices[i].is_finite() and normals[i].is_finite(), label + " has nonfinite geometry")
		_check(absf(normals[i].length() - 1.0) < 0.001, label + " has a non-unit normal")
	for i: int in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		var cross_product := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
		_check(cross_product.dot(normals[a] + normals[b] + normals[c]) < 0.0, label + " disagrees with clockwise surface winding")

func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
