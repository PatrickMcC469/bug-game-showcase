extends SceneTree
## Bake the existing shotgun's side projection into a flat equipment-wall mark.
const SOURCE := "res://scenes/game/weapons/shotgun_model.tscn"
const OUTPUT := "res://assets/meshes/shotgun/silhouette.res"
var projected: Array[Vector3] = []

func _initialize() -> void:
	_build.call_deferred()

func _build() -> void:
	var weapon := load(SOURCE).instantiate() as Node3D
	_collect(weapon, Transform3D.IDENTITY)
	weapon.free()
	if projected.is_empty():
		push_error("Shotgun projection has no faces")
		quit(1)
		return
	var bounds := AABB(projected[0], Vector3.ZERO)
	for vertex: Vector3 in projected: bounds=bounds.expand(vertex)
	var center := bounds.get_center()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex: Vector3 in projected:
		surface.set_normal(Vector3.BACK)
		surface.set_uv(Vector2(vertex.x-bounds.position.x, vertex.y-bounds.position.y))
		surface.add_vertex(vertex-center)
	var mesh := surface.commit()
	var error := ResourceSaver.save(mesh,OUTPUT)
	print("SHOTGUN SILHOUETTE: ",projected.size()/3," triangles; ",error_string(error))
	quit(0 if error==OK else 1)

func _collect(node: Node3D, parent_pose: Transform3D) -> void:
	var pose := parent_pose*node.transform
	if node is MeshInstance3D and node.mesh!=null:
		var faces: PackedVector3Array=node.mesh.get_faces()
		for index: int in range(0,faces.size(),3):
			var points: Array[Vector3]=[]
			for corner: int in 3:
				var p := pose*faces[index+corner]
				points.append(Vector3(-p.z,p.y,0))
			var area := (points[1]-points[0]).cross(points[2]-points[0]).z
			if absf(area)<0.00000001: continue
			if area>0: points=[points[0],points[2],points[1]]
			projected.append_array(points)
	for child: Node in node.get_children():
		if child is Node3D: _collect(child,pose)
