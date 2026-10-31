extends RefCounted
## Offline, shared mesh construction for manufactured diner surfaces.

static func bevel_box(size: Vector3, radius: float, wall_uv: bool = false) -> ArrayMesh:
	var half := size * 0.5
	var r := minf(radius, minf(half.x, minf(half.y, half.z)) * 0.8)
	var inner := half - Vector3.ONE * r
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Four samples per face axis preserve a broad planar center and bevel strip.
	for axis: int in 3:
		var u_axis := (axis + 1) % 3
		var v_axis := (axis + 2) % 3
		for side: float in [-1.0, 1.0]:
			var us := [-half[u_axis], -inner[u_axis], inner[u_axis], half[u_axis]]
			var vs := [-half[v_axis], -inner[v_axis], inner[v_axis], half[v_axis]]
			for u: int in 3:
				for v: int in 3:
					var corners: Array[Vector3] = []
					for offset: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
						var p := Vector3.ZERO
						p[axis] = half[axis] * side
						p[u_axis] = us[u + offset.x]
						p[v_axis] = vs[v + offset.y]
						corners.append(p)
					var order := [0, 2, 1, 0, 3, 2] if side > 0 else [0, 1, 2, 0, 2, 3]
					for index: int in order:
						var p := corners[index]
						var anchor := p.clamp(-inner, inner)
						var normal := (p - anchor).normalized()
						surface.set_normal(normal)
						# Wall scans run their long tile direction along texture Y.
						# Explicit planar UVs put it horizontally without triplanar
						# blending that distorts the grout grid on beveled corners.
						var uv := Vector2(p[u_axis], p[v_axis])
						if wall_uv and axis != 1:
							uv = Vector2(p.y, p.z if axis == 0 else p.x)
						surface.set_uv(uv)
						surface.add_vertex(anchor + normal * r)
	surface.generate_tangents()
	surface.index()
	return surface.commit()

static func lathe(profile: Array[Vector2], segments: int = 48) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row: int in profile.size() - 1:
		for segment: int in segments:
			for offset: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var point := profile[row + offset.y]
				var angle := TAU * (segment + offset.x) / segments
				surface.set_uv(Vector2(float(segment + offset.x) / segments, float(row + offset.y) / profile.size()))
				surface.add_vertex(Vector3(cos(angle) * point.x, point.y, sin(angle) * point.x))
	surface.generate_normals()
	surface.generate_tangents()
	surface.index()
	return surface.commit()

static func pipe(points: Array[Vector3], radius: float, segments: int = 16) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	var frame_x := Vector3.ZERO
	for index: int in points.size():
		var tangent := (points[mini(index + 1, points.size() - 1)] - points[maxi(0, index - 1)]).normalized()
		# Transport the previous cross-section through the bend. Selecting a
		# fresh reference axis at every ring twists handles near vertical bends.
		frame_x = frame_x.slide(tangent)
		if frame_x.length_squared() < 0.0001:
			var reference := Vector3.RIGHT if absf(tangent.dot(Vector3.UP)) > 0.9 else Vector3.UP
			frame_x = tangent.cross(reference)
		frame_x = frame_x.normalized()
		var x := frame_x
		var y := tangent.cross(x).normalized()
		var ring := PackedVector3Array()
		var normal_ring := PackedVector3Array()
		for segment: int in segments + 1:
			var normal := x * cos(TAU * segment / segments) + y * sin(TAU * segment / segments)
			ring.append(points[index] + normal * radius)
			normal_ring.append(normal)
		rings.append(ring)
		normals.append(normal_ring)
	for row: int in points.size() - 1:
		for segment: int in segments:
			for offset: Vector2i in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(1, 0), Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				surface.set_normal(normals[row + offset.y][segment + offset.x])
				surface.set_uv(Vector2(float(segment + offset.x) / segments, row + offset.y))
				surface.add_vertex(rings[row + offset.y][segment + offset.x])
	surface.generate_tangents()
	surface.index()
	return surface.commit()
