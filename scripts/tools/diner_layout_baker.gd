extends RefCounted
## Bake room dimensions into geometry and collision resources, avoiding scaled
## physics bodies and leaving the interactive cart's root at unit scale.
var _meshes: Dictionary[int, ArrayMesh] = {}
var _factor := 1.0

func bake(node: Node, factor: float) -> void:
	_factor = factor
	_bake_node(node)

func _mesh(source: Mesh) -> ArrayMesh:
	var id := source.get_instance_id()
	if _meshes.has(id):
		return _meshes[id]
	var result := ArrayMesh.new()
	for surface: int in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface).duplicate(true)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i: int in vertices.size():
			vertices[i] *= _factor
		arrays[Mesh.ARRAY_VERTEX] = vertices
		# Planar UVs are in authoring metres; preserve the material's real repeat
		# size. Triplanar materials already use the resized vertex positions.
		if arrays[Mesh.ARRAY_TEX_UV] != null:
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			for i: int in uv.size():
				uv[i] *= _factor
			arrays[Mesh.ARRAY_TEX_UV] = uv
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(surface, source.surface_get_material(surface))
	_meshes[id] = result
	return result

func _bake_node(node: Node) -> void:
	if node is Node3D:
		node.position *= _factor
	if node is MeshInstance3D and node.mesh != null:
		node.mesh = _mesh(node.mesh)
	elif node is MultiMeshInstance3D and node.multimesh != null:
		var source: MultiMesh = node.multimesh
		var batch := MultiMesh.new()
		batch.transform_format = source.transform_format
		batch.use_colors = source.use_colors
		batch.use_custom_data = source.use_custom_data
		batch.mesh = _mesh(source.mesh)
		batch.instance_count = source.instance_count
		for i: int in batch.instance_count:
			var pose := source.get_instance_transform(i)
			pose.origin *= _factor
			batch.set_instance_transform(i, pose)
			if source.use_colors:
				batch.set_instance_color(i, source.get_instance_color(i))
			if source.use_custom_data:
				batch.set_instance_custom_data(i, source.get_instance_custom_data(i))
		node.multimesh = batch
	elif node is CollisionShape3D:
		node.shape = node.shape.duplicate()
		if node.shape is BoxShape3D:
			node.shape.size *= _factor
		else:
			push_error("Diner layout bake needs explicit support for " + node.shape.get_class())
	elif node is Label3D:
		node.pixel_size *= _factor
	elif node is OmniLight3D:
		node.omni_range *= _factor
	elif node is ReflectionProbe:
		node.size *= _factor
		node.max_distance *= _factor
	elif node is WorldEnvironment:
		node.environment.ssao_radius *= _factor
	for child: Node in node.get_children():
		_bake_node(child)
