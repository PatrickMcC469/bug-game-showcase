extends SceneTree
## Rebuilds fine anatomy in the existing scene. Run after generate_roach_meshes.gd.
## Deterministic, project-owned geometry; no editor addon or DCC dependency.

const SCENE_PATH := "res://scenes/game/cockroach_model.tscn"
const CHITIN_SHADER := preload("res://assets/shaders/roach_chitin.gdshader")
var _failed := false
var _built_meshes: Dictionary[String, ArrayMesh] = {}

func _configure_surface(material: ShaderMaterial, wing: bool) -> void:
	var kind := "wing" if wing else "cuticle"
	material.set_shader_parameter("surface_normal", load("res://assets/textures/roach/roach_%s_normal.png" % kind))
	material.set_shader_parameter("surface_field", load("res://assets/textures/roach/roach_%s_field.png" % kind))
	material.set_shader_parameter("surface_scale", Vector2.ONE)
	material.set_shader_parameter("normal_strength", 1.6 if wing else 0.90)
	material.set_shader_parameter("wing_venation", 1.0 if wing else 0.0)
	material.set_shader_parameter("iridescence_strength", 0.035)
	material.set_shader_parameter("clearcoat_strength", 0.0)
	material.set_shader_parameter("clearcoat_gloss", 0.70)

func _initialize() -> void:
	var scene := load(SCENE_PATH) as PackedScene
	var roach := scene.instantiate() as Node3D
	var body := roach.get_node("BodyRoot") as Node3D
	var limb := load("res://assets/materials/roach_limb_photoreal.tres") as Material
	var joint := load("res://assets/materials/roach_joint_photoreal.tres") as Material
	for material_name: String in ["elytra", "chitin_dark", "joint", "limb"]:
		var path := "res://assets/materials/roach_%s_photoreal.tres" % material_name
		var material := load(path) as ShaderMaterial
		_configure_surface(material, material_name == "elytra")
		material.set_shader_parameter("base_color", Color(0.17, 0.039, 0.012))
		material.set_shader_parameter("secondary_color", Color(0.37, 0.115, 0.031))
		material.set_shader_parameter("base_roughness", 0.175 if material_name == "elytra" else 0.275)
		if material_name == "elytra":
			material.set_shader_parameter("base_color", Color(0.12, 0.024, 0.008))
			material.set_shader_parameter("secondary_color", Color(0.30, 0.075, 0.021))
		if material_name == "chitin_dark":
			material.set_shader_parameter("base_color", Color(0.048, 0.018, 0.010))
			material.set_shader_parameter("secondary_color", Color(0.16, 0.057, 0.022))
		if material_name == "limb":
			material.set_shader_parameter("secondary_color", Color(0.43, 0.17, 0.045))
		_save(material, path)
	var shield := ShaderMaterial.new()
	shield.shader = CHITIN_SHADER
	_configure_surface(shield, false)
	shield.set_shader_parameter("base_color", Color(0.105, 0.026, 0.009))
	shield.set_shader_parameter("secondary_color", Color(0.29, 0.093, 0.025))
	shield.set_shader_parameter("pronotum_markings", 1.0)
	shield.set_shader_parameter("normal_strength", 0.75)
	shield.set_shader_parameter("base_roughness", 0.235)
	_save(shield, "res://assets/materials/roach_pronotum_photoreal.tres")
	(body.get_node("ShellAccent") as MeshInstance3D).material_override = shield
	for old_name: String in ["WingSeam", "AbdomenBand1", "AbdomenBand2", "AbdomenBand3"]:
		(body.get_node(old_name) as Node3D).visible = false
	(body.get_node("AbdomenUnder") as Node3D).scale = Vector3(0.82, 0.22, 1.38)
	# Overlapping tergites expose the posterior abdomen and lateral pleura.
	var abdominal_material := ShaderMaterial.new()
	abdominal_material.shader = CHITIN_SHADER
	_configure_surface(abdominal_material, false)
	abdominal_material.set_shader_parameter("base_color", Color(0.09, 0.022, 0.011))
	abdominal_material.set_shader_parameter("secondary_color", Color(0.30, 0.095, 0.026))
	abdominal_material.set_shader_parameter("abdominal_plates", 1.0)
	abdominal_material.set_shader_parameter("surface_scale", Vector2(1.0, 0.20))
	_save(abdominal_material, "res://assets/materials/roach_abdomen_photoreal.tres")
	_add_mesh(body, roach, "AbdominalPlates", _abdominal_plates(), abdominal_material)
	_add_mesh(body, roach, "MarginalSetae", _body_setae(), limb)
	var eye_material := ShaderMaterial.new()
	eye_material.shader = load("res://assets/shaders/roach_eye.gdshader") as Shader
	_save(eye_material, "res://assets/materials/roach_eye_faceted.tres")
	# Seat the head and compound eyes into the shield rather than separate beads.
	(body.get_node("Head") as Node3D).scale = Vector3(0.32, 0.18, 0.23)
	(body.get_node("Head") as Node3D).position = Vector3(0.0, 0.005, -0.75)
	_face_details(body, roach, limb, joint)
	for side: String in ["Left", "Right"]:
		var antenna := body.get_node("Antenna" + side) as Node3D
		antenna.position = Vector3(-0.125 if side == "Left" else 0.125, 0.006, -0.85)
		antenna.rotation = Vector3(-0.09, 0.62 if side == "Left" else -0.56, 0.0)
		var antenna_material := (joint as ShaderMaterial).duplicate() as ShaderMaterial
		antenna_material.set_shader_parameter("antenna_side", -1.0 if side == "Left" else 1.0)
		antenna_material.set_shader_parameter("surface_scale", Vector2(1.0, 4.0))
		_save(antenna_material, "res://assets/materials/roach_antenna_%s.tres" % side.to_lower())
		var segment := antenna.get_node("Segment1") as MeshInstance3D
		segment.position.z = -0.84
		segment.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		segment.mesh = _antenna_mesh(-1.0 if side == "Left" else 1.0)
		segment.material_override = antenna_material
		(antenna.get_node("Joint1/Segment2") as Node3D).visible = false
		(antenna.get_node("Joint1/Joint2/Segment3") as Node3D).visible = false
		(antenna.get_node("Joint1") as Node3D).position.z = -0.42
		(antenna.get_node("Joint1/Joint2") as Node3D).position.z = -0.5
		(body.get_node("Cercus" + side) as Node3D).position = Vector3(-0.13 if side == "Left" else 0.13, -0.05, 1.04)
		var cercus := body.get_node("Cercus" + side + "/Mesh") as MeshInstance3D
		cercus.mesh = _annulated_mesh(0.28, 0.022, 12, 0.05)
		var jaw := body.get_node("Mandible" + side) as MeshInstance3D
		jaw.mesh = _hooked_claw()
		jaw.scale = Vector3(1.0, 1.4, 1.2)
		jaw.position = Vector3(-0.055 if side == "Left" else 0.055, -0.115, -0.932)
		var eye := body.get_node("Eye" + side) as MeshInstance3D
		eye.material_override = eye_material
		eye.scale = Vector3(0.080, 0.075, 0.115)
		eye.position = Vector3(-0.148 if side == "Left" else 0.148, 0.024, -0.780)
		for row: String in ["Front", "Middle", "Rear"]:
			var leg := roach.get_node("Leg" + side + row) as Node3D
			var sign_value := -1.0 if side == "Left" else 1.0
			var femur := leg.get_node("Femur") as Node3D
			var tibia := femur.get_node("Tibia") as Node3D
			var tarsus := tibia.get_node("Tarsus") as Node3D
			(femur.get_node("Joint") as Node3D).scale = Vector3(0.52, 0.42, 0.52)
			(femur.get_node("Mesh") as MeshInstance3D).mesh = _tapered_limb(0.34, 0.060, 0.59)
			(tibia.get_node("Mesh") as MeshInstance3D).mesh = _tapered_limb(0.40, 0.031, 0.44)
			for claw_name: String in ["ClawInner", "ClawOuter"]:
				(tarsus.get_node(claw_name) as MeshInstance3D).mesh = _hooked_claw()
			(tarsus.get_node("Mesh") as MeshInstance3D).mesh = _annulated_mesh(0.32, 0.020, 5, 0.44)
			(tarsus.get_node("FootPad") as Node3D).scale = Vector3(0.032, 0.014, 0.034)
			for claw_name: String in ["ClawInner", "ClawOuter"]:
				(tarsus.get_node(claw_name) as Node3D).scale = Vector3(0.75, 0.85, 0.70)
			for spine_name: String in ["Spine1", "Spine2", "Spine3"]:
				(tibia.get_node(spine_name) as Node3D).visible = false
			_add_mesh(tibia, roach, "SensorySpines", _spines(sign_value, 0.37, 13, 0.087), limb)
			_add_mesh(femur, roach, "SensorySpines", _spines(sign_value, 0.30, 10, 0.036), limb)
			# Static editor pose agrees with the runtime's IK rest stance.
			var reach := 0.71
			var dy := 0.035 - leg.position.y
			var ankle_x := reach - 0.31
			var distance := Vector2(ankle_x, dy).length()
			var knee := -acos(clampf((distance * distance - 0.32 * 0.32 - 0.38 * 0.38) / (2.0 * 0.32 * 0.38), -1.0, 1.0))
			var upper := atan2(dy, ankle_x) - atan2(0.38 * sin(knee), 0.32 + 0.38 * cos(knee))
			femur.rotation.z = sign_value * upper
			tibia.rotation.z = sign_value * knee
			tarsus.rotation.z = -sign_value * (upper + knee)
	var packed := PackedScene.new()
	var error := packed.pack(roach)
	if error != OK:
		push_error("Could not pack cockroach: %s" % error_string(error))
		quit(1)
		return
	_save(packed, SCENE_PATH)
	ResourceSaver.set_uid(SCENE_PATH, ResourceUID.text_to_id("uid://cfiuep6wfsw10"))
	roach.free()
	if not _failed:
		print("ROACH DETAIL BUILD: PASS")
	quit(1 if _failed else 0)

func _save(resource: Resource, path: String) -> void:
	resource.take_over_path(path)
	var error := ResourceSaver.save(resource, path)
	if error != OK:
		push_error("Could not save %s: %s" % [path, error_string(error)])
		_failed = true


func _append_bristle(surface: SurfaceTool, origin: Vector3, direction: Vector3, length_value: float, radius: float) -> void:
	# Tapered curved setae are actual silhouette geometry, batched by body part.
	for index: int in 3:
		var t := float(index) / 3.0
		var next_t := float(index + 1) / 3.0
		var start := origin + direction * length_value * t + Vector3.UP * t * t * length_value * 0.12
		var end := origin + direction * length_value * next_t + Vector3.UP * next_t * next_t * length_value * 0.12
		var spine := CylinderMesh.new()
		spine.bottom_radius = radius * pow(1.0 - t, 1.5)
		spine.top_radius = maxf(0.00003, radius * pow(1.0 - next_t, 1.5))
		spine.height = start.distance_to(end) * 1.015
		spine.radial_segments = 5 if radius > 0.002 else 3
		spine.rings = 0
		spine.cap_top = false
		spine.cap_bottom = false
		surface.append_from(spine, 0, Transform3D(Basis(Quaternion(Vector3.UP, (end - start).normalized())), (start + end) * 0.5))


func _abdominal_plates() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for plate: int in 8:
		for row: int in 6:
			for column: int in 48:
				for corner: Vector2i in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
					var u := float(column + corner.x) / 48.0
					var v := float(row + corner.y) / 6.0
					var angle := u * TAU
					var z := -0.10 + plate * 0.145 + v * 0.183
					var width := 0.455 * sqrt(maxf(0.045, 1.0 - pow((z - 0.26) / 0.94, 2.0)))
					var rim := sin(v * PI * 0.8) * 0.012
					var y := -0.040 + sin(angle) * (0.105 + rim) - plate * 0.001
					if plate == 7:
						var tip := sqrt(maxf(0.0001, 1.0 - v * v))
						width *= tip
						rim *= tip
						y = -0.047 + sin(angle) * 0.105 * tip
					surface.set_uv(Vector2(u, v))
					surface.add_vertex(Vector3(cos(angle) * (width + rim), y, z + cos(angle) * cos(angle) * 0.033))
	surface.index()
	surface.generate_normals()
	surface.generate_tangents()
	return surface.commit()


func _body_setae() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in 68:
		var z := -0.08 + float(index) / 67.0 * 1.22
		var width := 0.455 * sqrt(maxf(0.045, 1.0 - pow((z - 0.26) / 0.94, 2.0)))
		for side: float in [-1.0, 1.0]:
			var origin := Vector3(side * width, -0.036, z)
			var direction := Vector3(side, 0.25 + sin(index * 1.7) * 0.3, 0.4).normalized()
			_append_bristle(surface, origin, direction, 0.021 + absf(sin(index * 3.7)) * 0.018, 0.0009)
	return surface.commit()

func _add_mesh(parent: Node3D, owner_node: Node3D, node_name: String, mesh: ArrayMesh, material: Material) -> void:
	var instance := parent.get_node_or_null(node_name) as MeshInstance3D
	if instance == null:
		instance = MeshInstance3D.new()
		instance.name = node_name
		parent.add_child(instance)
		instance.owner = owner_node
	var path := "res://assets/meshes/roach_%s_%s.res" % [str(owner_node.get_path_to(parent)).replace("/", "_"), node_name]
	_save(mesh, path)
	instance.mesh = mesh
	instance.material_override = material

func _annulated_mesh(length_value: float, radius: float, segments: int, taper: float) -> ArrayMesh:
	var path := "res://assets/meshes/roach_annulated_%s_%d.res" % [str(length_value).replace(".", "_"), segments]
	if _built_meshes.has(path):
		return _built_meshes[path]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := segments * 4
	for row: int in rows:
		for column: int in 10:
			for corner: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var t := float(row + corner.y) / float(rows)
				var angle := float(column + corner.x) / 10.0 * TAU
				var r := radius * lerpf(1.0, taper, t)
				r *= 0.85 + 0.15 * sin(fposmod(t * segments, 1.0) * PI)
				var bend := sin(t * PI) * (0.021 if segments > 15 else 0.006)
				surface.set_uv(Vector2(float(column + corner.x) / 10.0, t))
				surface.add_vertex(Vector3(cos(angle) * r + bend, (t - 0.5) * length_value, sin(angle) * r))
	surface.index()
	surface.generate_normals()
	surface.generate_tangents()
	for index: int in segments:
		if index % 2 != 0:
			continue
		var t := (float(index) + 0.5) / float(segments)
		for flank: float in [-1.0, 1.0]:
			var direction := Vector3(flank, 0.30, sin(index * 2.1) * 0.6).normalized()
			var bend := sin(t * PI) * (0.021 if segments > 15 else 0.006)
			var at := Vector3(bend, (t - 0.5) * length_value, 0.0) + direction * radius * lerpf(1.0, taper, t)
			_append_bristle(surface, at, direction, 0.015 * (1.0 - t * 0.55), 0.00065)
	var mesh := surface.commit()
	_save(mesh, path)
	_built_meshes[path] = mesh
	return mesh


func _antenna_mesh(side: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row: int in 320:
		for column: int in 8:
			for corner: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var t := float(row + corner.y) / 320.0
				var angle := float(column + corner.x) / 8.0 * TAU
				var radius := lerpf(0.015, 0.00012, pow(t, 0.72)) * (0.87 + 0.13 * sin(t * 80.0 * TAU))
				var origin := Vector3(side * t * t * 0.38, (t - 0.5) * 1.68, sin(t * PI) * 0.052)
				var tangent := Vector3(side * t * 0.76, 1.68, cos(t * PI) * PI * 0.052).normalized()
				var frame := Basis(Quaternion(Vector3.UP, tangent))
				surface.set_uv(Vector2(float(column + corner.x) / 8.0, t))
				surface.add_vertex(origin + frame * Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
	surface.index()
	surface.generate_normals()
	surface.generate_tangents()
	for index: int in 55:
		var t := float(index) / 55.0
		var at := Vector3(side * t * t * 0.38, (t - 0.5) * 1.68, sin(t * PI) * 0.052)
		var direction := Vector3(cos(index * 2.4), 0.25, sin(index * 2.4)).normalized()
		_append_bristle(surface, at + direction * (1.0 - t) * 0.014, direction, (1.0 - t * 0.7) * 0.017, 0.0006)
	var mesh := surface.commit()
	_save(mesh, "res://assets/meshes/roach_antenna_%s.res" % ("left" if side < 0.0 else "right"))
	return mesh

func _spines(side: float, length_value: float, count: int, height: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in count:
		for flank: float in [-1.0, 1.0]:
			var t := (float(index) + 0.65 + flank * 0.16) / float(count + 1)
			var direction := Vector3(side * (0.3 + sin(index * 3.1) * 0.13), 0.12 + sin(index * 1.7) * 0.18, flank).normalized()
			var root_radius := (0.031 if length_value > 0.35 else 0.054) * lerpf(0.75, 0.40, t)
			var origin := Vector3(side * length_value * t, 0.0, flank * root_radius)
			_append_bristle(surface, origin, direction, height * (0.6 + 0.4 * absf(sin(index * 2.3 + flank))), 0.0037)
			for hair_index: int in 2:
				var hair_t := clampf(t + hair_index * 0.025, 0.02, 0.98)
				var hair_origin := Vector3(side * length_value * hair_t, root_radius * 0.65, flank * root_radius * 0.75)
				_append_bristle(surface, hair_origin, (direction + Vector3(0.0, 0.7, 0.0)).normalized(), 0.028, 0.0007)
	return surface.commit()


func _hooked_claw() -> ArrayMesh:
	const PATH := "res://assets/meshes/roach_hooked_claw.res"
	if _built_meshes.has(PATH):
		return _built_meshes[PATH]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in 8:
		var t := float(index) / 8.0
		var next_t := float(index + 1) / 8.0
		var start := Vector3(0.0, -0.04 + t * 0.085, sin(t * PI * 0.7) * 0.027)
		var end := Vector3(0.0, -0.04 + next_t * 0.085, sin(next_t * PI * 0.7) * 0.027)
		var segment := CylinderMesh.new()
		segment.bottom_radius = lerpf(0.009, 0.0004, t)
		segment.top_radius = lerpf(0.009, 0.0004, next_t)
		segment.height = start.distance_to(end) * 1.08
		segment.radial_segments = 8
		segment.rings = 1
		surface.append_from(segment, 0, Transform3D(Basis(Quaternion(Vector3.UP, (end - start).normalized())), (start + end) * 0.5))
	var mesh := surface.commit()
	_save(mesh, PATH)
	_built_meshes[PATH] = mesh
	return mesh


func _tapered_limb(length_value: float, radius: float, taper: float) -> ArrayMesh:
	var path := "res://assets/meshes/roach_limb_%s.res" % str(length_value).replace(".", "_")
	if _built_meshes.has(path):
		return _built_meshes[path]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row: int in 16:
		for column: int in 16:
			for corner: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var t := float(row + corner.y) / 16.0
				var a := float(column + corner.x) / 16.0 * TAU
				var r := radius * lerpf(1.0, taper, t) * (0.62 + 0.38 * pow(sin(t * PI), 0.65))
				surface.set_uv(Vector2(float(column + corner.x) / 16.0, t))
				surface.add_vertex(Vector3(cos(a) * r, (t - 0.5) * length_value, sin(a) * r * 0.74))
	surface.index()
	surface.generate_normals()
	surface.generate_tangents()
	var mesh := surface.commit()
	_save(mesh, path)
	_built_meshes[path] = mesh
	return mesh


func _face_details(body: Node3D, owner_node: Node3D, shell: Material, membrane: Material) -> void:
	var face := SurfaceTool.new()
	face.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in 3:
		var plate := SphereMesh.new()
		plate.radial_segments = 24
		plate.rings = 12
		face.append_from(plate, 0, Transform3D(Basis.from_scale(Vector3(
			0.21 - index * 0.045, 0.080, 0.035)), Vector3(0.0, -0.025 - index * 0.04, -0.86 - index * 0.018)))
	_add_mesh(body, owner_node, "FacialPlates", face.commit(), shell)
	for side: float in [-1.0, 1.0]:
		var palp := SurfaceTool.new()
		palp.begin(Mesh.PRIMITIVE_TRIANGLES)
		var points: Array[Vector3] = [Vector3(side * 0.12, -0.06, -0.89), Vector3(side * 0.19, -0.09, -0.97), Vector3(side * 0.19, -0.11, -1.07), Vector3(side * 0.13, -0.12, -1.12)]
		for index: int in 3:
			var segment := CapsuleMesh.new()
			segment.radius = 0.013 - index * 0.003
			segment.height = points[index].distance_to(points[index + 1])
			segment.radial_segments = 10
			segment.rings = 4
			var direction := (points[index + 1] - points[index]).normalized()
			palp.append_from(segment, 0, Transform3D(Basis(Quaternion(Vector3.UP, direction)), (points[index] + points[index + 1]) * 0.5 - points[0]))
		var part_name := "PalpLeft" if side < 0.0 else "PalpRight"
		_add_mesh(body, owner_node, part_name, palp.commit(), membrane)
		(body.get_node(part_name) as Node3D).position = points[0]
