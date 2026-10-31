extends SceneTree
## Rebuilds the project-owned parametric cockroach shell meshes. These meshes
## stay deliberately procedural so their proportions remain easy to tune while
## the character is still in prototype production.

const MESH_DIR := "res://assets/meshes"
var _failed := false


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MESH_DIR))
	_save_mesh(_build_elytron(-1.0), MESH_DIR + "/roach_elytron_left.tres")
	_save_mesh(_build_elytron(1.0), MESH_DIR + "/roach_elytron_right.tres")
	_save_mesh(_build_pronotum(), MESH_DIR + "/roach_pronotum.tres")
	if not _failed:
		print("ROACH MESH GENERATION: PASS")
	quit(1 if _failed else 0)


func _save_mesh(mesh: ArrayMesh, path: String) -> void:
	var error := ResourceSaver.save(mesh, path)
	if error != OK:
		push_error("Failed to save %s: %s" % [path, error_string(error)])
		_failed = true


func _build_elytron(side: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	const LENGTH_STEPS := 64
	const WIDTH_STEPS := 24

	for length_index: int in LENGTH_STEPS:
		var v0 := float(length_index) / float(LENGTH_STEPS)
		var v1 := float(length_index + 1) / float(LENGTH_STEPS)
		for width_index: int in WIDTH_STEPS:
			var u0 := float(width_index) / float(WIDTH_STEPS)
			var u1 := float(width_index + 1) / float(WIDTH_STEPS)
			var top_00 := _elytron_point(side, u0, v0, false)
			var top_10 := _elytron_point(side, u1, v0, false)
			var top_01 := _elytron_point(side, u0, v1, false)
			var top_11 := _elytron_point(side, u1, v1, false)
			var bottom_00 := _elytron_point(side, u0, v0, true)
			var bottom_10 := _elytron_point(side, u1, v0, true)
			var bottom_01 := _elytron_point(side, u0, v1, true)
			var bottom_11 := _elytron_point(side, u1, v1, true)

			if side > 0.0:
				_add_triangle(surface, top_00, top_10, top_01, Vector2(u0, v0), Vector2(u1, v0), Vector2(u0, v1))
				_add_triangle(surface, top_10, top_11, top_01, Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1))
				_add_triangle(surface, bottom_00, bottom_01, bottom_10, Vector2(u0, v0), Vector2(u0, v1), Vector2(u1, v0))
				_add_triangle(surface, bottom_10, bottom_01, bottom_11, Vector2(u1, v0), Vector2(u0, v1), Vector2(u1, v1))
			else:
				_add_triangle(surface, top_00, top_01, top_10, Vector2(u0, v0), Vector2(u0, v1), Vector2(u1, v0))
				_add_triangle(surface, top_10, top_01, top_11, Vector2(u1, v0), Vector2(u0, v1), Vector2(u1, v1))
				_add_triangle(surface, bottom_00, bottom_10, bottom_01, Vector2(u0, v0), Vector2(u1, v0), Vector2(u0, v1))
				_add_triangle(surface, bottom_10, bottom_11, bottom_01, Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1))

	# Close the inner seam, outer edge, and both ends so grazing highlights reveal
	# the thin layered edge instead of an infinitely thin card.
	for length_index: int in LENGTH_STEPS:
		var v0 := float(length_index) / float(LENGTH_STEPS)
		var v1 := float(length_index + 1) / float(LENGTH_STEPS)
		_add_elytron_edge(surface, side, 0.0, v0, v1, true)
		_add_elytron_edge(surface, side, 1.0, v0, v1, false)
	for width_index: int in WIDTH_STEPS:
		var u0 := float(width_index) / float(WIDTH_STEPS)
		var u1 := float(width_index + 1) / float(WIDTH_STEPS)
		_add_elytron_end(surface, side, u0, u1, 0.0, true)
		_add_elytron_end(surface, side, u0, u1, 1.0, false)

	surface.index()
	surface.generate_normals()
	surface.generate_tangents()
	return surface.commit()


func _elytron_point(side: float, u: float, v: float, underside: bool) -> Vector3:
	var z := lerpf(-0.35, 1.015 if side < 0.0 else 0.98, v)
	# Broad leathery forewings with rounded tips, rather than a pointed beetle shell.
	var width := 0.455 * sqrt(maxf(1.0 - pow(v, 3.3), 0.0002))
	width *= 0.96 + sin(v * PI) * 0.04
	width *= lerpf(0.83, 1.0, smoothstep(0.0, 0.20, v))
	var inner_x := 0.012 + sin(v * PI) * 0.023
	var x := lerpf(inner_x, side * width, u)
	var cross_dome := cos(u * PI * 0.5) * 0.074
	var length_dome := sin(v * PI) * 0.028
	var y := 0.073 + cross_dome + length_dome - pow(v, 6.0) * 0.060
	y += sin(u * 24.0 + v * 11.0) * sin(v * PI) * 0.0012
	# A slightly raised left seam suggests the natural overlap.
	y += (1.0 - u) * (0.008 if side < 0.0 else 0.0)
	if underside:
		y -= 0.0045
	return Vector3(x, y, z)


func _add_elytron_edge(
	surface: SurfaceTool,
	side: float,
	u: float,
	v0: float,
	v1: float,
	inner: bool,
) -> void:
	var top_0 := _elytron_point(side, u, v0, false)
	var top_1 := _elytron_point(side, u, v1, false)
	var bottom_0 := _elytron_point(side, u, v0, true)
	var bottom_1 := _elytron_point(side, u, v1, true)
	if (side > 0.0) == inner:
		_add_triangle(surface, top_0, bottom_0, top_1, Vector2(u, v0), Vector2(u, v0), Vector2(u, v1))
		_add_triangle(surface, top_1, bottom_0, bottom_1, Vector2(u, v1), Vector2(u, v0), Vector2(u, v1))
	else:
		_add_triangle(surface, top_0, top_1, bottom_0, Vector2(u, v0), Vector2(u, v1), Vector2(u, v0))
		_add_triangle(surface, top_1, bottom_1, bottom_0, Vector2(u, v1), Vector2(u, v1), Vector2(u, v0))


func _add_elytron_end(
	surface: SurfaceTool,
	side: float,
	u0: float,
	u1: float,
	v: float,
	front: bool,
) -> void:
	var top_0 := _elytron_point(side, u0, v, false)
	var top_1 := _elytron_point(side, u1, v, false)
	var bottom_0 := _elytron_point(side, u0, v, true)
	var bottom_1 := _elytron_point(side, u1, v, true)
	if (side > 0.0) == front:
		_add_triangle(surface, top_0, top_1, bottom_0, Vector2(u0, v), Vector2(u1, v), Vector2(u0, v))
		_add_triangle(surface, top_1, bottom_1, bottom_0, Vector2(u1, v), Vector2(u1, v), Vector2(u0, v))
	else:
		_add_triangle(surface, top_0, bottom_0, top_1, Vector2(u0, v), Vector2(u0, v), Vector2(u1, v))
		_add_triangle(surface, top_1, bottom_0, bottom_1, Vector2(u1, v), Vector2(u0, v), Vector2(u1, v))


func _build_pronotum() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	const RING_STEPS := 16
	const ANGLE_STEPS := 64
	var center := Vector3(0.0, 0.071, -0.48)

	for ring_index: int in RING_STEPS:
		var r0 := float(ring_index) / float(RING_STEPS)
		var r1 := float(ring_index + 1) / float(RING_STEPS)
		for angle_index: int in ANGLE_STEPS:
			var a0 := TAU * float(angle_index) / float(ANGLE_STEPS)
			var a1 := TAU * float(angle_index + 1) / float(ANGLE_STEPS)
			var p00 := _pronotum_point(center, r0, a0)
			var p10 := _pronotum_point(center, r1, a0)
			var p01 := _pronotum_point(center, r0, a1)
			var p11 := _pronotum_point(center, r1, a1)
			var uv00 := Vector2(0.5 + cos(a0) * r0 * 0.5, 0.5 + sin(a0) * r0 * 0.5)
			var uv10 := Vector2(0.5 + cos(a0) * r1 * 0.5, 0.5 + sin(a0) * r1 * 0.5)
			var uv01 := Vector2(0.5 + cos(a1) * r0 * 0.5, 0.5 + sin(a1) * r0 * 0.5)
			var uv11 := Vector2(0.5 + cos(a1) * r1 * 0.5, 0.5 + sin(a1) * r1 * 0.5)
			if ring_index > 0:
				_add_triangle(surface, p00, p10, p01, uv00, uv10, uv01)
			_add_triangle(surface, p10, p11, p01, uv10, uv11, uv01)

	# A narrow underside lip gives the shield believable thickness.
	for angle_index: int in ANGLE_STEPS:
		var a0 := TAU * float(angle_index) / float(ANGLE_STEPS)
		var a1 := TAU * float(angle_index + 1) / float(ANGLE_STEPS)
		var top_0 := _pronotum_point(center, 1.0, a0)
		var top_1 := _pronotum_point(center, 1.0, a1)
		var bottom_0 := top_0 - Vector3(0.0, 0.006, 0.0)
		var bottom_1 := top_1 - Vector3(0.0, 0.006, 0.0)
		_add_triangle(surface, top_0, bottom_0, top_1, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		_add_triangle(surface, top_1, bottom_0, bottom_1, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)

	surface.index()
	surface.generate_normals()
	surface.generate_tangents()
	return surface.commit()


func _pronotum_point(center: Vector3, radius: float, angle: float) -> Vector3:
	var x := cos(angle) * radius * 0.435 * (1.0 + sin(angle) * 0.10)
	var z_scale := 0.32 * (1.0 - maxf(sin(angle), 0.0) * 0.12)
	var fore_aft := sin(angle)
	if fore_aft > 0.0:
		fore_aft = tanh(fore_aft * 2.8) / tanh(2.8)
	var z := fore_aft * radius * z_scale
	var dome := pow(maxf(1.0 - radius * radius, 0.0), 0.62) * 0.112
	dome -= exp(-pow(x * 9.0, 2.0)) * maxf(z, 0.0) * 0.075
	# The posterior shield margin sits over the wing roots, not through them.
	dome += maxf(sin(angle), 0.0) * radius * radius * 0.105
	return center + Vector3(x, dome, z)


func _add_triangle(
	surface: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	uv_a: Vector2,
	uv_b: Vector2,
	uv_c: Vector2,
) -> void:
	surface.set_uv(uv_a)
	surface.add_vertex(a)
	surface.set_uv(uv_b)
	surface.add_vertex(b)
	surface.set_uv(uv_c)
	surface.add_vertex(c)
