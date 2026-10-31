extends SceneTree
## Offline weapon art; -Z is the bore direction, origin is the receiver.
const Geometry := preload("res://scripts/tools/diner_detail_geometry.gd")
var weapon: Node3D
var groups: Dictionary[Material,Array]={}

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	weapon=Node3D.new()
	weapon.name="ShotgunModel"
	var steel := _material("303b3a",0.65,0.42)
	var grip := _material("515444",0.05,0.85)
	var trim := _material("b3914e",0.5,0.43)
	var dark := _material("131b1a",0.0,0.95)
	_box(Vector3(0.063,0.080,0.17),Vector3(0,0,0),steel,0.009)
	_box(Vector3(0.075,0.11,0.22),Vector3(0,-0.02,0.20),grip,0.02)
	_box(Vector3(0.078,0.12,0.018),Vector3(0,-0.02,0.32),dark,0.006)
	var handle := _box(Vector3(0.047,0.13,0.054),Vector3(0,-0.08,0.065),grip,0.012)
	handle.rotation.x=-0.25
	_tube([Vector3(-0.022,-0.042,0.045),Vector3(-0.022,-0.09,0.012),Vector3(-0.022,-0.084,-0.065),Vector3(-0.022,-0.039,-0.072)],0.006,steel)
	_tube([Vector3(0,-0.043,0.001),Vector3(0,-0.069,-0.008)],0.005,steel)
	# Open barrel bore, with a recessed dark interior rather than a solid cap.
	var bore := Geometry.lathe([Vector2(0.018,-0.61),Vector2(0.023,-0.61),Vector2(0.023,-0.065),Vector2(0.018,-0.065)],40)
	_mesh(bore,steel).rotation.x=PI/2
	_cylinder(0.017,0.003,Vector3(0,0,-0.59),dark)
	_cylinder(0.019,0.41,Vector3(0,-0.045,-0.29),steel)
	_box(Vector3(0.080,0.075,0.16),Vector3(0,-0.043,-0.27),grip,0.017)
	for i: int in 9:
		_box(Vector3(0.082,0.076,0.006),Vector3(0,-0.043,-0.34+i*0.018),dark,0.002)
	_box(Vector3(0.020,0.019,0.027),Vector3(0,0.026,-0.56),trim,0.003)
	_box(Vector3(0.030,0.009,0.25),Vector3(0,0.041,-0.035),steel,0.002)
	_box(Vector3(0.006,0.033,0.070),Vector3(0.034,0.005,-0.012),dark,0.004)
	_box(Vector3(0.008,0.027,0.035),Vector3(0.039,0.005,-0.012),trim,0.003)
	var muzzle := Marker3D.new()
	muzzle.name="Muzzle"
	weapon.add_child(muzzle)
	muzzle.owner=weapon
	muzzle.position=Vector3(0,0,-0.625)
	var index := 0
	for material: Material in groups:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part: MeshInstance3D in groups[material]:
			surface.append_from(part.mesh,0,part.transform)
			weapon.remove_child(part)
			part.free()
		var mesh := surface.commit()
		var path := "res://assets/meshes/shotgun/detail_"+str(index)+".res"
		mesh.take_over_path(path)
		ResourceSaver.save(mesh,path)
		var node := MeshInstance3D.new()
		node.name="Detail"+str(index)
		node.mesh=mesh
		node.material_override=material
		weapon.add_child(node)
		node.owner=weapon
		index+=1
	var packed := PackedScene.new()
	var error := packed.pack(weapon)
	if error==OK: error=ResourceSaver.save(packed,"res://scenes/game/weapons/shotgun_model.tscn")
	print("SHOTGUN BUILD: ",error_string(error))
	weapon.free()
	quit(0 if error==OK else 1)

func _material(color: String, metal: float, rough: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color=Color(color)
	mat.metallic=metal
	mat.roughness=rough
	return mat

func _mesh(shape: Mesh, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh=shape
	node.material_override=mat
	weapon.add_child(node)
	if not groups.has(mat): groups[mat]=[]
	groups[mat].append(node)
	return node

func _box(size: Vector3, at: Vector3, mat: Material, bevel: float) -> MeshInstance3D:
	var node := _mesh(Geometry.bevel_box(size,bevel),mat)
	node.position=at
	return node

func _tube(points: Array[Vector3], radius: float, mat: Material) -> void:
	_mesh(Geometry.pipe(points,radius,12),mat)

func _cylinder(radius: float, length: float, at: Vector3, mat: Material) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius=radius
	cylinder.bottom_radius=radius
	cylinder.height=length
	cylinder.radial_segments=32
	cylinder.rings=1
	var node := _mesh(cylinder,mat)
	node.position=at
	node.rotation.x=PI/2
