extends SceneTree
## Offline authoring only. The packed character contains all geometry; gameplay
## only poses the saved rig. Rebuilding replaces the generated model scene.

const Geometry := preload("res://scripts/tools/diner_detail_geometry.gd")
const Surface := preload("res://assets/shaders/exterminator_surface.gdshader")
const HOOD_PROFILE: Array[Vector4] = [Vector4(-0.005,0.11,0.095,0),Vector4(0.055,0.12,0.108,0),
	Vector4(0.12,0.139,0.13,0),Vector4(0.23,0.145,0.143,0),Vector4(0.31,0.139,0.137,0),
	Vector4(0.365,0.11,0.11,0.01),Vector4(0.395,0.055,0.06,0.01),Vector4(0.404,0.001,0.001,0.01)]
const BODY_PROFILE: Array[Vector4] = [Vector4(0.92,0.08,0.08,0),Vector4(0.96,0.17,0.135,0), Vector4(1.02,0.215,0.15,0),
	Vector4(1.15,0.195,0.14,0), Vector4(1.3,0.215,0.145,0),
	Vector4(1.49,0.25,0.155,0), Vector4(1.61,0.27,0.135,0),
	Vector4(1.67,0.24,0.12,0), Vector4(1.71,0.12,0.10,0), Vector4(1.74,0.095,0.085,0)]
const SHIN_PROFILE: Array[Vector4] = [Vector4(-0.36,0.075,0.08,0),Vector4(-0.28,0.083,0.085,0),
	Vector4(-0.19,0.10,0.10,0.015),Vector4(-0.05,0.092,0.097,0),Vector4(0.025,0.09,0.095,0)]
const SLEEVE_PROFILE: Array[Vector4] = [Vector4(-0.34,0.077,0.078,0),Vector4(-0.25,0.082,0.088,0),
	Vector4(-0.12,0.091,0.10,0),Vector4(0.005,0.107,0.105,0),Vector4(0.075,0.073,0.073,0),
	Vector4(0.09,0.001,0.001,0)]
var model_root: Node3D
var suit: Material
var trim: Material
var rubber: Material
var metal: Material
var ochre: Material
var glass: Material
var stitch: Material
var _serial := 0
var _mesh_prefix := "exterminator_"

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	if "--head-only" in OS.get_cmdline_user_args():
		_rebuild_head()
		return
	model_root = Node3D.new()
	model_root.name = "ExterminatorModel"
	model_root.set_script(load("res://scripts/game/exterminator_model.gd"))
	suit = material("coverall", Color("949580"), 0.88, 0.0, 1.0, 0.28)
	trim = material("reinforcement", Color("424b41"), 0.9, 0.0, 1.0, 0.28)
	rubber = material("boot_rubber", Color("222b29"), 0.66, 0.0, 0.0, 0.34)
	metal = material("hardware", Color("a3a59b"), 0.34, 0.82, 0.0, 0.15)
	ochre = material("safety_ochre", Color("b99447"), 0.72, 0.0, 1.0, 0.18)
	glass = material("smoked_visor", Color("253c3d"), 0.22, 0.05, 0.0, 0.05)
	stitch = material("stitch", Color("b0ae93"), 0.94, 0.0, 1.0, 0.1)
	var body := pivot(model_root, "BodyRoot", Vector3.ZERO)
	loft(body, "Coveralls", BODY_PROFILE, suit, 0.008, 64)
	# Double storm flap and zipper pull are geometry, visible at grazing angles.
	fitted_cloth(body,"StormFlap",BODY_PROFILE,Vector4(-PI/2,0.065,1.125,1.665),0.008,suit,0.002,0.001,4,36)
	var zip_angle := -PI/2+0.095
	fitted_cloth(body,"ZipperTape",BODY_PROFILE,Vector4(zip_angle,0.019,1.12,1.65),0.008,rubber,0.0023,0.0,4,36)
	for n: int in 40:
		var height := 1.13+n*0.013
		var normal := garment_normal(BODY_PROFILE,height,zip_angle,0.008)
		var tooth := box(body,"ZipperTooth",Vector3(0.012,0.004,0.002),cloth_support(BODY_PROFILE,height,zip_angle,0.008)+normal*0.0038,metal,0.0007)
		tooth.basis=Basis.looking_at(-normal)
	var pull_normal := garment_normal(BODY_PROFILE,1.61,zip_angle,0.008)
	var pull := box(body,"ZipperPull",Vector3(0.014,0.029,0.004),cloth_support(BODY_PROFILE,1.61,zip_angle,0.008)+pull_normal*0.005,metal,0.003)
	pull.basis=Basis.looking_at(-pull_normal)
	for side: float in [-1.0, 1.0]:
		var angle := -PI/2+side*0.54
		var pocket_region := Vector4(angle,0.30,1.378,1.516)
		var flap_region := Vector4(angle,0.32,1.496,1.541)
		fitted_cloth(body,"ChestPocket",BODY_PROFILE,pocket_region,0.008,suit,0.0021,0.0032,16,12)
		fitted_cloth(body,"PocketFlap",BODY_PROFILE,flap_region,0.008,trim,0.0035,0.0024,16,6)
		var snap_normal := garment_normal(BODY_PROFILE,1.514,angle,0.008)
		var snap := button(body,cloth_point(BODY_PROFILE,flap_region,Vector2(0.5,0.4),0.008,0.0035,0.0024)+snap_normal*0.001,0.005)
		snap.basis=Basis.looking_at(-snap_normal)*Basis(Vector3.RIGHT,PI/2)
		var stitches: Array[Vector3]=[]
		for i: int in 12: stitches.append(cloth_point(BODY_PROFILE,pocket_region,Vector2(0.06,0.9-i*0.84/11),0.008,0.0028,0.0032))
		for i: int in 17: stitches.append(cloth_point(BODY_PROFILE,pocket_region,Vector2(0.06+i*0.88/16,0.06),0.008,0.0028,0.0032))
		for i: int in 12: stitches.append(cloth_point(BODY_PROFILE,pocket_region,Vector2(0.94,0.06+i*0.84/11),0.008,0.0028,0.0032))
		seam(body,stitches,0.00065)
		# Shoulder and side seams follow the authored coverall volume.
		seam(body,[Vector3(side*0.12,1.706,-0.047),Vector3(side*0.22,1.665,-0.085),
			Vector3(side*0.265,1.60,-0.065)],0.002)
		seam(body,[Vector3(side*0.214,1.08,0.03),Vector3(side*0.208,1.25,0.035),
			Vector3(side*0.246,1.48,0.03)],0.0018)
		leg(model_root, side)
		arm(body, side)
	# Sewn service patch, intentionally a small identity detail rather than UI.
	var name_region := Vector4(-PI/2-0.54,0.245,1.554,1.585)
	fitted_cloth(body,"ServicePatch",BODY_PROFILE,name_region,0.008,ochre,0.0022,0.0005,14,4)
	var name_normal := garment_normal(BODY_PROFILE,1.5695,name_region.x,0.008)
	var name_label := label(body,"NIGHT SHIFT",cloth_point(BODY_PROFILE,name_region,Vector2(0.5,0.5),0.008,0.004,0.0005),0.00022,27)
	name_label.basis=Basis.looking_at(-name_normal)
	fitted_belt(body)
	head(body)
	backpack(body)
	_batch(model_root)
	var packed := PackedScene.new()
	var error := packed.pack(model_root)
	if error == OK:
		error = ResourceSaver.save(packed, "res://scenes/game/exterminator_model.tscn")
	print("EXTERMINATOR BUILD: ", error_string(error))
	model_root.free()
	quit(0 if error == OK else 1)

func _batch(parent: Node) -> void:
	# Keep articulated pivots, but batch hardware and seams per material to avoid
	# spending a draw call per stitch, zip tooth, filter louver or sole lug.
	var groups: Dictionary = {}
	for child: Node in parent.get_children():
		if child is MeshInstance3D:
			var mat: Material = child.material_override
			if not groups.has(mat): groups[mat] = []
			groups[mat].append(child)
		elif child is Node3D:
			_batch(child)
	for mat: Material in groups:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part: MeshInstance3D in groups[mat]:
			for index: int in part.mesh.get_surface_count():
				surface.append_from(part.mesh,index,part.transform)
			parent.remove_child(part)
			part.free()
		var combined := surface.commit()
		var path := "res://assets/meshes/"+_mesh_prefix+str(_serial)+".res"
		combined.take_over_path(path)
		ResourceSaver.save(combined,path)
		mesh(parent,"BatchedDetail",combined,mat)

func material(id: String, color: Color, rough: float, metallic: float, cloth: float, dirt: float) -> Material:
	var mat := ShaderMaterial.new()
	mat.shader = Surface
	mat.set_shader_parameter("base_color", color)
	mat.set_shader_parameter("roughness_base", rough)
	mat.set_shader_parameter("metalness", metallic)
	mat.set_shader_parameter("fabric", cloth)
	mat.set_shader_parameter("wear", dirt)
	var path := "res://assets/materials/exterminator_" + id + ".tres"
	mat.take_over_path(path)
	ResourceSaver.save(mat, path)
	return mat

func pivot(parent: Node, title: String, at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = title
	parent.add_child(node)
	node.owner = model_root
	node.position = at
	return node

func mesh(parent: Node, title: String, shape: Mesh, mat: Material, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	_serial += 1
	node.name = title + str(_serial)
	node.mesh = shape
	node.material_override = mat
	parent.add_child(node)
	node.owner = model_root
	node.position = at
	return node

func box(parent: Node, title: String, size: Vector3, at: Vector3, mat: Material, bevel: float = 0.01) -> MeshInstance3D:
	return mesh(parent,title,Geometry.bevel_box(size,bevel),mat,at)

func tube(parent: Node, title: String, points: Array[Vector3], radius: float, mat: Material, segments: int = 10) -> MeshInstance3D:
	return mesh(parent,title,Geometry.pipe(points,radius,segments),mat)

func seam(parent: Node, points: Array[Vector3], radius: float) -> void:
	tube(parent,"FelledSeam",points,radius,stitch,6)

func glove_digit(parent: Node, title: String, profile: Array[Vector4]) -> void:
	# A continuous rounded sweep avoids the cut pipe ends and angular joints of
	# equipment tubing. Each control stores a center and glove radius.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	var centers: Array[Vector3] = []
	var rows := (profile.size()-1)*6
	const SIDES := 16
	for row: int in rows+1:
		var t := float(row)/6.0
		var index := mini(int(t),profile.size()-2)
		var blend := clampf(t-index,0,1)
		var previous := profile[maxi(0,index-1)]
		var next := profile[mini(profile.size()-1,index+2)]
		var p := profile[index].cubic_interpolate(profile[index+1],previous,next,blend)
		var nearby := profile[index].cubic_interpolate(profile[index+1],previous,next,
			blend+0.001 if blend<0.999 else blend-0.001)
		var tangent := Vector3(nearby.x-p.x,nearby.y-p.y,nearby.z-p.z).normalized()
		if blend>=0.999: tangent = -tangent
		var across := (Vector3.RIGHT-tangent*Vector3.RIGHT.dot(tangent)).normalized()
		var depth := across.cross(tangent).normalized()
		var center := Vector3(p.x,p.y,p.z)
		var ring := PackedVector3Array()
		for segment: int in SIDES:
			var angle := TAU*segment/SIDES
			ring.append(center+(across*cos(angle)+depth*sin(angle))*maxf(p.w,0.0004))
		rings.append(ring)
		centers.append(center)
	for row: int in rows:
		for segment: int in SIDES:
			for offset: Vector2i in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]:
				surface.set_uv(Vector2(float(segment+offset.x)/SIDES,float(row+offset.y)/rows))
				surface.add_vertex(rings[row+offset.y][(segment+offset.x)%SIDES])
	for end: int in [0,rows]:
		for segment: int in SIDES:
			var a := segment if end==0 else (segment+1)%SIDES
			var b := (segment+1)%SIDES if end==0 else segment
			for point: Vector3 in [centers[end],rings[end][b],rings[end][a]]:
				surface.set_uv(Vector2(0.5,float(end)/rows))
				surface.add_vertex(point)
	surface.generate_normals()
	surface.generate_tangents()
	surface.index()
	mesh(parent,title,surface.commit(),rubber)

func cylinder(parent: Node, title: String, radius: float, depth: float, at: Vector3, mat: Material, front: bool = false) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = depth
	shape.radial_segments = 40
	var node := mesh(parent,title,shape,mat,at)
	if front:
		node.rotation.x = PI * 0.5
	return node

func button(parent: Node, at: Vector3, radius: float) -> MeshInstance3D:
	return cylinder(parent,"Snap",radius,0.003,at,metal,true)

func label(parent: Node, words: String, at: Vector3, pixel: float, font_size: int) -> Label3D:
	var node := Label3D.new()
	node.name = "EquipmentMarking" + str(_serial)
	_serial += 1
	node.text = words
	node.font_size = font_size
	node.pixel_size = pixel
	node.outline_size = 0
	node.modulate = Color("242d2a")
	node.rotation.y = PI
	node.position = at
	parent.add_child(node)
	node.owner = model_root
	return node

func loft(parent: Node, title: String, profile: Array[Vector4], mat: Material, wrinkles: float = 0.0, segments: int = 48) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := (profile.size()-1)*5
	for row: int in rows:
		for segment: int in segments:
			for offset: Vector2i in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]:
				var t := float(row+offset.y)/5.0
				var index := mini(int(t),profile.size()-2)
				var blend := clampf(t-index,0,1)
				var p := profile[index].cubic_interpolate(profile[index+1],profile[maxi(0,index-1)],profile[mini(profile.size()-1,index+2)],blend)
				p.y = maxf(p.y,0.001)
				p.z = maxf(p.z,0.001)
				var a := TAU * (segment+offset.x)/segments
				var wave := wrinkles * sin(PI*(row+offset.y)/rows) * (
					0.6*sin(p.x*49.0+sin(a*3.0)*1.6)+0.25*sin(p.x*97.0-a*4.0)+0.15*sin(a*13.0))
				surface.set_uv(Vector2(float(segment+offset.x)/segments,float(row+offset.y)/rows))
				surface.add_vertex(Vector3(cos(a)*(p.y+wave),p.x,sin(a)*(p.z+wave)+p.w))
	surface.generate_normals()
	surface.generate_tangents()
	surface.index()
	return mesh(parent,title,surface.commit(),mat)

func garment_point(profile: Array[Vector4], height: float, angle: float, wrinkles: float) -> Vector3:
	# Sample the same authored loft and wrinkle field as the garment, so attached
	# details follow its surface instead of using a flat plane in front of it.
	var low := 0.0
	var high := float(profile.size()-1)
	var p := Vector4.ZERO
	var t := 0.0
	for iteration: int in 18:
		t = (low+high)*0.5
		var index := mini(int(t),profile.size()-2)
		p = profile[index].cubic_interpolate(profile[index+1],profile[maxi(0,index-1)],
			profile[mini(profile.size()-1,index+2)],t-index)
		if p.x < height: low = t
		else: high = t
	var wave := wrinkles*sin(PI*t/(profile.size()-1))*(0.6*sin(p.x*49.0+sin(angle*3.0)*1.6)+0.25*sin(p.x*97.0-angle*4.0)+0.15*sin(angle*13.0))
	return Vector3(cos(angle)*(p.y+wave),height,sin(angle)*(p.z+wave)+p.w)

func cloth_support(profile: Array[Vector4], height: float, angle: float, wrinkles: float) -> Vector3:
	# Interpolate the actual loft triangles, not just the ideal curved profile.
	# Otherwise thin appliques can sink into the coarser cloth mesh between rows.
	var segments := 48 if profile==SLEEVE_PROFILE else 64
	var low := 0.0
	var high := float(profile.size()-1)
	for iteration: int in 18:
		var t := (low+high)*0.5
		if _loft_vertex(profile,t,0,wrinkles).y<height: low=t
		else: high=t
	var row := mini(int((low+high)*2.5),(profile.size()-1)*5-1)
	var around := wrapf(angle,0,TAU)*segments/TAU
	var column := int(around)
	var u := around-column
	var a := _loft_vertex(profile,row/5.0,column*TAU/segments,wrinkles)
	var b := _loft_vertex(profile,row/5.0,(column+1)*TAU/segments,wrinkles)
	var c := _loft_vertex(profile,(row+1)/5.0,(column+1)*TAU/segments,wrinkles)
	var d := _loft_vertex(profile,(row+1)/5.0,column*TAU/segments,wrinkles)
	var v := clampf((height-a.y)/(d.y-a.y),0,1)
	return a*(1-u)+b*(u-v)+c*v if u>=v else a*(1-v)+c*u+d*(v-u)

func _loft_vertex(profile: Array[Vector4], t: float, angle: float, wrinkles: float) -> Vector3:
	var index := mini(int(t),profile.size()-2)
	var p := profile[index].cubic_interpolate(profile[index+1],profile[maxi(0,index-1)],profile[mini(profile.size()-1,index+2)],t-index)
	var wave := wrinkles*sin(PI*t/(profile.size()-1))*(0.6*sin(p.x*49.0+sin(angle*3.0)*1.6)+0.25*sin(p.x*97.0-angle*4.0)+0.15*sin(angle*13.0))
	return Vector3(cos(angle)*(maxf(p.y,0.001)+wave),p.x,sin(angle)*(maxf(p.z,0.001)+wave)+p.w)

func garment_normal(profile: Array[Vector4], height: float, angle: float, wrinkles: float) -> Vector3:
	var vertical := cloth_support(profile,height+0.0005,angle,wrinkles)-cloth_support(profile,height-0.0005,angle,wrinkles)
	var around := cloth_support(profile,height,angle+0.001,wrinkles)-cloth_support(profile,height,angle-0.001,wrinkles)
	return vertical.cross(around).normalized()

func cloth_point(profile: Array[Vector4], region: Vector4, uv: Vector2, wrinkles: float, thickness: float, fullness: float) -> Vector3:
	# Region is center angle, half angle, bottom and top. Rounded corners and
	# tapered relief read as sewn cloth while following the garment's folds.
	var height := lerpf(region.z,region.w,uv.y)
	var width := region.y*(0.90+0.10*sqrt(maxf(0,sin(PI*uv.y))))
	var angle := region.x+(uv.x*2-1)*width
	var puff := fullness*pow(maxf(0,sin(PI*uv.x)*sin(PI*uv.y)),0.65)
	return cloth_support(profile,height,angle,wrinkles)+garment_normal(profile,height,angle,wrinkles)*(thickness+puff)

func fitted_cloth(parent: Node, title: String, profile: Array[Vector4], region: Vector4,
		wrinkles: float, mat: Material, thickness: float, fullness: float, segments: int, rows: int) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var front := PackedVector3Array()
	var back := PackedVector3Array()
	for row: int in rows+1:
		for column: int in segments+1:
			var uv := Vector2(column/float(segments),row/float(rows))
			front.append(cloth_point(profile,region,uv,wrinkles,thickness,fullness))
			back.append(cloth_point(profile,region,uv,wrinkles,0.0003,0))
	for backing: bool in [false,true]:
		for row: int in rows:
			for column: int in segments:
				var order := [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]
				if backing: order.reverse()
				for offset: Vector2i in order:
					var index := (row+offset.y)*(segments+1)+column+offset.x
					surface.set_uv(Vector2((column+offset.x)/float(segments),(row+offset.y)/float(rows)))
					surface.add_vertex(back[index] if backing else front[index])
	var perimeter: Array[int]=[]
	for column: int in segments: perimeter.append(column)
	for row: int in rows: perimeter.append(row*(segments+1)+segments)
	for column: int in segments: perimeter.append(rows*(segments+1)+segments-column)
	for row: int in rows: perimeter.append((rows-row)*(segments+1))
	for i: int in perimeter.size():
		var a := perimeter[i]
		var b := perimeter[(i+1)%perimeter.size()]
		for index: int in [0,1,2,0,2,3]:
			surface.set_uv(Vector2(float(index%2),float(i)/perimeter.size()))
			surface.add_vertex([front[a],back[a],back[b],front[b]][index])
	surface.generate_normals()
	surface.generate_tangents()
	surface.index()
	mesh(parent,title,surface.commit(),mat)

func fitted_belt(parent: Node) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# A closed, softly edged 4.5 mm webbing band around the whole waist.
	var section: Array[Vector2] = [Vector2(1.098,0.0008),Vector2(1.0965,0.002),
		Vector2(1.099,0.0045),Vector2(1.141,0.0045),Vector2(1.1435,0.002),
		Vector2(1.142,0.0008),Vector2(1.098,0.0008)]
	for row: int in section.size()-1:
		for column: int in 128:
			for offset: Vector2i in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]:
				var point := section[row+offset.y]
				var angle := TAU*(column+offset.x)/128.0
				var normal := Vector3(cos(angle)/0.2,0,sin(angle)/0.14).normalized()
				surface.set_uv(Vector2((column+offset.x)/128.0,(row+offset.y)/6.0))
				surface.add_vertex(garment_point(BODY_PROFILE,point.x,angle,0.008)+normal*point.y)
	surface.generate_normals()
	surface.generate_tangents()
	surface.index()
	mesh(parent,"FittedBelt",surface.commit(),trim)
	var angle := -1.25
	var normal := Vector3(cos(angle)/0.2,0,sin(angle)/0.14).normalized()
	var mount := garment_point(BODY_PROFILE,1.12,angle,0.008)
	var buckle := box(parent,"BeltBuckle",Vector3(0.050,0.043,0.005),mount+normal*0.0065,metal,0.004)
	buckle.basis = Basis.looking_at(normal)
	var inset := box(parent,"BuckleInset",Vector3(0.034,0.027,0.003),mount+normal*0.008,rubber,0.003)
	inset.basis = buckle.basis

func knee_pad_point(u: float, v: float, extra: float = 0.0, backing: bool = false) -> Vector3:
	var height := lerpf(-0.108,0.018,v)
	var half_angle := 0.84*(0.82+0.18*sqrt(maxf(0,sin(PI*v))))
	var angle := -PI*0.5+(u*2.0-1.0)*half_angle
	var radial := Vector3(cos(angle),0,sin(angle))
	var support := garment_point(SHIN_PROFILE,height,angle,0.006)
	# The knee gusset can protrude past the trouser loft near the joint. Fit over
	# the outside of both surfaces, keeping the upper edge below the flex crease.
	if absf(height)<0.095:
		var ring := sqrt(1.0-pow(height/0.095,2))
		var gusset := Vector3(cos(angle)*0.094*ring,height,sin(angle)*0.096*ring)
		if gusset.dot(radial)>support.dot(radial): support = gusset
	var normal := Vector3(cos(angle)/0.094,0,sin(angle)/0.10).normalized()
	var padding := 0.0015+0.0035*pow(maxf(0,sin(PI*u)*sin(PI*v)),0.55)
	return support+normal*((0.0004 if backing else padding)+extra)

func fitted_knee_pad(parent: Node) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 32
	var rows := 16
	for backing: bool in [false,true]:
		for row: int in rows:
			for column: int in segments:
				var order := [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]
				if backing: order.reverse()
				for offset: Vector2i in order:
					var uv := Vector2((column+offset.x)/float(segments),(row+offset.y)/float(rows))
					surface.set_uv(uv)
					surface.add_vertex(knee_pad_point(uv.x,uv.y,0,backing))
	var perimeter: Array[Vector2] = []
	for i: int in segments: perimeter.append(Vector2(i/float(segments),0))
	for i: int in rows: perimeter.append(Vector2(1,i/float(rows)))
	for i: int in segments: perimeter.append(Vector2(1-i/float(segments),1))
	for i: int in rows: perimeter.append(Vector2(0,1-i/float(rows)))
	for i: int in perimeter.size():
		var a := perimeter[i]
		var b := perimeter[(i+1)%perimeter.size()]
		var points := [knee_pad_point(a.x,a.y),knee_pad_point(b.x,b.y),
			knee_pad_point(b.x,b.y,0,true),knee_pad_point(a.x,a.y,0,true)]
		for index: int in [0,2,1,0,3,2]:
			surface.set_uv(a if index in [0,3] else b)
			surface.add_vertex(points[index])
	surface.generate_normals()
	surface.generate_tangents()
	surface.index()
	mesh(parent,"FittedKneePad",surface.commit(),trim)

func leg(parent: Node, side: float) -> void:
	var suffix := "Left" if side < 0 else "Right"
	var thigh := pivot(parent,"Leg"+suffix,Vector3(side*0.125,1.02,0))
	loft(thigh,"TrouserThigh",[Vector4(-0.46,0.09,0.095,0),Vector4(-0.39,0.098,0.102,0),
		Vector4(-0.25,0.114,0.125,0),Vector4(-0.07,0.12,0.137,0),Vector4(0.035,0.11,0.11,0),
		Vector4(0.06,0.001,0.001,0)],suit,0.007)
	var shin := pivot(thigh,"Shin",Vector3(0,-0.45,0))
	joint(shin,"KneeGusset",Vector3(0.094,0.095,0.096),suit)
	loft(shin,"TrouserShin",SHIN_PROFILE,suit,0.006)
	fitted_knee_pad(shin)
	for i: int in 3:
		var points: Array[Vector3] = []
		for step: int in 25:
			points.append(knee_pad_point(lerpf(0.13,0.87,step/24.0),0.22+i*0.28,0.001))
		tube(shin,"KneePleat",points,0.0015,suit,6)
	seam(thigh,[Vector3(side*0.11,-0.075,0.01),Vector3(side*0.111,-0.25,0.01),Vector3(side*0.095,-0.4,0.01)],0.0017)
	var pocket := box(thigh,"CargoPocket",Vector3(0.043,0.17,0.135),Vector3(side*0.113,-0.22,0.005),suit,0.014)
	pocket.rotation.z = side*0.04
	box(thigh,"CargoFlap",Vector3(0.047,0.043,0.143),Vector3(side*0.121,-0.15,0.005),trim,0.006)
	var foot := pivot(shin,"Foot",Vector3(0,-0.40,0))
	loft(foot,"MoldedBoot",[Vector4(-0.135,0.071,0.125,-0.034),Vector4(-0.10,0.084,0.16,-0.05),
		Vector4(-0.055,0.085,0.158,-0.049),Vector4(-0.012,0.081,0.12,-0.022),
		Vector4(0.055,0.078,0.079,0.004),Vector4(0.16,0.081,0.081,0.004),
		Vector4(0.172,0.072,0.072,0.004)],rubber,0.001,48)
	loft(foot,"Welt",[Vector4(-0.154,0.082,0.15,-0.042),Vector4(-0.143,0.09,0.166,-0.046),
		Vector4(-0.118,0.09,0.164,-0.046),Vector4(-0.107,0.084,0.158,-0.047)],rubber,0,48)
	for i: int in 7:
		for j: int in 2:
			var z := -0.167+i*0.038
			var half_width := 0.082*sqrt(1.0-pow((z+0.046)/0.166,2))
			var lug := box(foot,"SoleLug",Vector3(half_width*0.85,0.014,0.029),Vector3((j-0.5)*half_width*0.96,-0.161,z),rubber,0.004)
			lug.rotation.y = (-0.16 if j==0 else 0.16)
	var toe_seam: Array[Vector3] = []
	for i: int in 25:
		var a := PI+PI*i/24.0
		toe_seam.append(Vector3(cos(a)*0.086,-0.048,sin(a)*0.16-0.049))
	tube(foot,"MoldedToeSeam",toe_seam,0.0025,rubber,8)
	box(foot,"BootPull",Vector3(0.035,0.063,0.013),Vector3(0,0.16,0.082),trim,0.004)
	loft(foot,"BootCollar",[Vector4(0.12,0.082,0.083,0.004),Vector4(0.15,0.086,0.086,0.004),
		Vector4(0.17,0.083,0.083,0.004)],rubber,0,48)
	box(foot,"HeelMark",Vector3(0.03,0.015,0.006),Vector3(0,0.04,0.084),ochre,0.002)

func arm(parent: Node, side: float) -> void:
	var suffix := "Left" if side < 0 else "Right"
	var arm_root := pivot(parent,"Arm"+suffix,Vector3(side*0.267,1.625,0))
	arm_root.rotation.z = side*0.10
	arm_root.rotation.x = 0.055
	loft(arm_root,"SleeveUpper",SLEEVE_PROFILE,suit,0.006,48)
	var elbow := pivot(arm_root,"Forearm",Vector3(0,-0.33,0))
	joint(elbow,"ElbowGusset",Vector3(0.078,0.078,0.080),suit)
	# Match the runtime's forward elbow bend in the saved editor rest pose.
	elbow.rotation.x = 0.17
	loft(elbow,"SleeveLower",[Vector4(-0.285,0.052,0.057,0),Vector4(-0.21,0.065,0.069,0),
		Vector4(-0.10,0.074,0.076,0),Vector4(0.025,0.076,0.079,0)],suit,0.005)
	loft(elbow,"GloveCuff",[Vector4(-0.315,0.055,0.061,0),Vector4(-0.25,0.06,0.065,0),
		Vector4(-0.23,0.057,0.06,0)],rubber,0.001,32)
	var sleeve_seam: Array[Vector3]=[]
	var seam_angle := PI+0.58 if side<0 else -0.58
	for i: int in 25:
		var height := lerpf(-0.29,0.004,i/24.0)
		sleeve_seam.append(cloth_support(SLEEVE_PROFILE,height,seam_angle,0.006)+garment_normal(SLEEVE_PROFILE,height,seam_angle,0.006)*0.0009)
	seam(arm_root,sleeve_seam,0.0007)
	fitted_cloth(arm_root,"SleeveBadge",SLEEVE_PROFILE,Vector4(PI if side<0 else 0,0.41,-0.153,-0.048),0.006,ochre,0.0021,0.0006,16,12)
	var hand := pivot(elbow,"Hand",Vector3(0,-0.32,0))
	# Turn palms toward the thighs, keeping the thumb edge toward -Z (front).
	# The wrist sits inside the cuff so this neutral twist has no exposed join.
	hand.rotation = Vector3(0.06,side*1.22,-side*0.04)
	loft(hand,"GlovePalm",[Vector4(-0.106,0.001,0.001,-0.010),
		Vector4(-0.092,0.031,0.014,-0.004),Vector4(-0.075,0.044,0.023,0),
		Vector4(-0.042,0.044,0.027,0.002),Vector4(-0.012,0.037,0.026,0),
		Vector4(0.025,0.038,0.030,0)],rubber,0.0005,32)
	for finger: int in 4:
		var fx := side*(1.5-finger)*0.0215
		var length := [0.073,0.084,0.079,0.061][finger] as float
		var root_y := [-0.076,-0.084,-0.080,-0.071][finger] as float
		var radius := [0.0108,0.0112,0.0105,0.0090][finger] as float
		var curl := 0.031+finger*0.004
		glove_digit(hand,"GloveFinger",[Vector4(fx,root_y+0.010,0,radius),
			Vector4(fx,root_y-length*0.35,-0.004,radius),
			Vector4(fx-side*0.001,root_y-length*0.67,-curl*0.40,radius*0.94),
			Vector4(fx-side*0.002,root_y-length*0.84,-curl*0.80,radius*0.78),
			Vector4(fx-side*0.002,root_y-length*0.91,-curl,radius*0.50),
			Vector4(fx-side*0.002,root_y-length*0.94,-curl-0.005,0.0004)])
		# Small curved stitched arcs follow the backs of the knuckles.
		tube(hand,"KnuckleSeam",[Vector3(fx-side*0.007,root_y-0.005,0.008),
			Vector3(fx,root_y-0.006,0.011),Vector3(fx+side*0.007,root_y-0.005,0.008)],0.0012,trim,8)
	glove_digit(hand,"Thumb",[Vector4(side*0.019,-0.022,-0.002,0.013),
		Vector4(side*0.040,-0.047,-0.014,0.020),
		Vector4(side*0.053,-0.069,-0.025,0.0135),
		Vector4(side*0.050,-0.086,-0.035,0.011),
		Vector4(side*0.046,-0.091,-0.040,0.007),
		Vector4(side*0.043,-0.092,-0.043,0.0004)])

func _rebuild_head() -> void:
	# Preserve the reviewed body, rig, hands and material resources verbatim.
	model_root = load("res://scenes/game/exterminator_model.tscn").instantiate()
	root.add_child(model_root)
	model_root.set_process(false)
	suit = load("res://assets/materials/exterminator_coverall.tres")
	trim = load("res://assets/materials/exterminator_reinforcement.tres")
	rubber = load("res://assets/materials/exterminator_boot_rubber.tres")
	metal = load("res://assets/materials/exterminator_hardware.tres")
	ochre = load("res://assets/materials/exterminator_safety_ochre.tres")
	glass = load("res://assets/materials/exterminator_smoked_visor.tres")
	stitch = load("res://assets/materials/exterminator_stitch.tres")
	var body := model_root.get_node("BodyRoot")
	body.get_node("Head").free()
	_mesh_prefix = "exterminator_head_fit_"
	head(body)
	_batch(body.get_node("Head"))
	var packed := PackedScene.new()
	var error := packed.pack(model_root)
	if error == OK: error = ResourceSaver.save(packed,"res://scenes/game/exterminator_model.tscn")
	print("EXTERMINATOR HEAD BUILD: ",error_string(error))
	model_root.free()
	quit(0 if error == OK else 1)

func head(parent: Node) -> void:
	var hood := pivot(parent,"Head",Vector3(0,1.72,0))
	loft(hood,"SealedHood",HOOD_PROFILE,suit,0.003,64)
	seam(hood,[Vector3(0,0.045,0.111),Vector3(0,0.23,0.144),Vector3(0,0.335,0.13),
		Vector3(0,0.398,0.046),Vector3(0,0.391,-0.035),Vector3(0,0.35,-0.115)],0.0018)
	# Sample the hood triangles at the temples as well as the front. The old
	# shallow cylindrical patch left its side edges floating ahead of the head.
	head_patch(hood,"CurvedVisor",visor_point,glass,40,16)
	var rim: Array[Vector3] = []
	for i: int in 41: rim.append(visor_point(i/40.0,0))
	for i: int in 17: rim.append(visor_point(1,i/16.0))
	for i: int in 41: rim.append(visor_point(1-i/40.0,1))
	for i: int in 17: rim.append(visor_point(0,1-i/16.0))
	tube(hood,"VisorSeal",rim,0.006,rubber,12)
	head_patch(hood,"RespiratorFacepiece",respirator_point,rubber,32,16)
	var seal: Array[Vector3] = []
	for i: int in 33: seal.append(respirator_point(i/32.0,0))
	for i: int in 17: seal.append(respirator_point(1,i/16.0))
	for i: int in 33: seal.append(respirator_point(1-i/32.0,1))
	for i: int in 17: seal.append(respirator_point(0,1-i/16.0))
	tube(hood,"CheekSeal",seal,0.005,rubber,10)
	cylinder(hood,"ExhaleRim",0.037,0.019,Vector3(0,0.125,-0.172),metal,true)
	cylinder(hood,"ExhaleValve",0.032,0.022,Vector3(0,0.125,-0.182),rubber,true)
	for i: int in 5:
		box(hood,"ExhaleSlit",Vector3(0.043-absf(i-2)*0.005,0.003,0.003),Vector3(0,0.109+i*0.008,-0.195),trim,0.001)
	for side: float in [-1.0,1.0]:
		var filter := pivot(hood,"FilterLeft" if side<0 else "FilterRight",Vector3(side*0.101,0.115,-0.120))
		filter.rotation.y = -side*0.64
		cylinder(filter,"CartridgeBase",0.048,0.045,Vector3(0,0,-0.009),rubber,true)
		cylinder(filter,"CartridgeShell",0.052,0.055,Vector3(0,0,-0.04),ochre,true)
		cylinder(filter,"CartridgeBand",0.053,0.012,Vector3(0,0,-0.04),trim,true)
		cylinder(filter,"CartridgeCap",0.051,0.012,Vector3(0,0,-0.072),rubber,true)
		for i: int in 7:
			var width := sqrt(maxf(0.0018-pow((i-3)*0.011,2),0.0001))*2
			box(filter,"FilterLouver",Vector3(width,0.0035,0.004),Vector3(0,(i-3)*0.011,-0.080),metal,0.001)
		var strap := func(u: float,v: float) -> Vector3: return harness_point(u,v,side)
		head_patch(hood,"MaskHarness",strap,trim,48,4,side<0)
		var angle := -PI/2+side*1.08
		var normal := garment_normal(HOOD_PROFILE,0.255,angle,0.003)
		var snap := button(hood,cloth_support(HOOD_PROFILE,0.255,angle,0.003)+normal*0.007,0.006)
		snap.basis=Basis.looking_at(-normal)*Basis(Vector3.RIGHT,PI/2)
	var brow_angle := -PI/2
	var brow_normal := garment_normal(HOOD_PROFILE,0.337,brow_angle,0.003)
	var brow := box(hood,"BrowLabel",Vector3(0.068,0.017,0.008),cloth_support(HOOD_PROFILE,0.337,brow_angle,0.003)+brow_normal*0.005,ochre,0.003)
	brow.basis=Basis.looking_at(-brow_normal)
	var tag := label(hood,"07",brow.position+brow_normal*0.0045,0.00027,32)
	tag.basis=brow.basis

func visor_point(u: float, v: float) -> Vector3:
	var sweep := lerpf(-1.08,1.08,u)
	var height := 0.255+(v*2-1)*0.065*(1-0.19*pow(absf(sweep/1.08),4))
	var angle := -PI/2+sweep
	var relief := 0.005+0.011*sin(PI*u)*sin(PI*v)
	return cloth_support(HOOD_PROFILE,height,angle,0.003)+garment_normal(HOOD_PROFILE,height,angle,0.003)*relief

func respirator_point(u: float,v: float) -> Vector3:
	var height := lerpf(0.071,0.209,v)
	var angle := -PI/2+(u*2-1)*(0.22+0.56*sin(PI*v))
	var relief := 0.004+0.036*sin(PI*u)*sin(PI*v)
	return cloth_support(HOOD_PROFILE,height,angle,0.003)+garment_normal(HOOD_PROFILE,height,angle,0.003)*relief

func harness_point(u: float,v: float,side: float) -> Vector3:
	var angle := -PI/2+side*lerpf(0.80,PI,u)
	var height := lerpf(0.147,0.261,sin(u*PI/2))+(v-0.5)*0.020
	return cloth_support(HOOD_PROFILE,height,angle,0.003)+garment_normal(HOOD_PROFILE,height,angle,0.003)*0.003

func head_patch(parent: Node,title: String,sample: Callable,mat: Material,columns: int,rows: int,reverse: bool=false) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var order := [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]
	if reverse: order.reverse()
	for row: int in rows:
		for column: int in columns:
			for offset: Vector2i in order:
				var u := float(column+offset.x)/columns
				var v := float(row+offset.y)/rows
				surface.set_uv(Vector2(u,v))
				surface.add_vertex(sample.call(u,v))
	surface.generate_normals()
	surface.generate_tangents()
	surface.index()
	mesh(parent,title,surface.commit(),mat)

func joint(parent: Node, title: String, radii: Vector3, mat: Material) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	mesh(parent,title,sphere,mat).scale = radii

func backpack(parent: Node) -> void:
	var pack := pivot(parent,"EquipmentPack",Vector3(0,1.36,0.17))
	box(pack,"Backplate",Vector3(0.30,0.44,0.045),Vector3(0,0,0.018),rubber,0.02)
	loft(pack,"ServiceCanister",[Vector4(-0.20,0.001,0.001,0.08),Vector4(-0.18,0.105,0.082,0.08),
		Vector4(-0.13,0.12,0.093,0.08),Vector4(0.14,0.12,0.093,0.08),
		Vector4(0.18,0.104,0.077,0.08),Vector4(0.20,0.043,0.043,0.08)],ochre,0,48)
	cylinder(pack,"TankCap",0.044,0.035,Vector3(0,0.205,0.08),rubber)
	for height: float in [-0.12,0.10]:
		loft(pack,"TankRetainer",[Vector4(height,0.123,0.096,0.08),Vector4(height+0.026,0.123,0.096,0.08)],trim,0,48)
	for side: float in [-1.0,1.0]:
		tube(parent,"ShoulderHarness",[Vector3(side*0.1,1.50,0.195),Vector3(side*0.17,1.65,0.11),
			Vector3(side*0.20,1.668,0),Vector3(side*0.204,1.58,-0.10),Vector3(side*0.195,1.33,-0.10)],0.015,trim,10)
		box(parent,"HarnessAdjuster",Vector3(0.033,0.047,0.021),Vector3(side*0.20,1.41,-0.10),metal,0.004)
	var hose: Array[Vector3] = []
	for i: int in 41:
		var t := i/40.0
		hose.append(Vector3(0.12+sin(t*PI)*0.15,1.18-sin(t*PI)*0.18,0.25-t*0.33))
	tube(parent,"StowedServiceHose",hose,0.016,rubber,12)
	for i: int in range(1,40,2):
		var ring := TorusMesh.new()
		ring.inner_radius = 0.014
		ring.outer_radius = 0.020
		ring.rings = 12
		ring.ring_segments = 6
		var rib := mesh(parent,"HoseRib",ring,trim,hose[i])
		rib.quaternion = Quaternion(Vector3.UP,(hose[i+1]-hose[i-1]).normalized())
