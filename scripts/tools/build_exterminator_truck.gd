extends SceneTree
## Offline authoring. The saved truck is a map-independent static prop.
const Geometry := preload("res://scripts/tools/diner_detail_geometry.gd")
const Surface := preload("res://assets/shaders/exterminator_surface.gdshader")
var truck: Node3D
var hull: StaticBody3D
var mats: Dictionary[String, Material] = {}
var serial := 0

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	truck = Node3D.new()
	truck.name = "ExterminatorTruck"
	truck.set_meta("front_axis", "-Z")
	truck.set_meta("equipment_wall_clear_size", Vector2(2.85,1.45))
	hull = StaticBody3D.new()
	hull.name = "StaticCollision"
	attach(truck,hull)
	mat("Ivory", "b9b6a5", 0.54, 0.30, 0.15)
	mat("Sage", "515f54", 0.61, 0.34, 0.18)
	mat("Ochre", "bc9145", 0.58, 0.2, 0.12)
	mat("Rubber", "232a28", 0.84, 0.0, 0.18)
	mat("Steel", "848d8b", 0.38, 0.85, 0.14)
	mat("DarkSteel", "384140", 0.56, 0.70, 0.2)
	mat("Glass", "233d40", 0.17, 0.65, 0.025)
	mat("Panel", "45534a", 0.91, 0.0, 0.13)
	mat("Red", "982c24", 0.3, 0.15, 0.03)
	mat("Light", "e6e2c9", 0.25, 0.3, 0.02)
	var frame := group(truck,"Chassis")
	box(frame,"Rails",Vector3(1.55,0.20,5.80),Vector3(0,0.47,0),"DarkSteel")
	box(frame,"FuelTank",Vector3(0.60,0.30,1.0),Vector3(-0.80,0.49,-0.20),"Steel",0.05)
	for z: float in [-2.03,1.88]:
		rod(frame,"Axle",Vector3(-1.03,0.46,z),Vector3(1.03,0.46,z),0.075,"DarkSteel")
		for side: float in [-1.0,1.0]: wheel(frame,side,z)
	_build_cab()
	_build_workshop()
	_build_rear()
	marker(truck,"ParkingOrigin",Vector3.ZERO)
	marker(truck,"RearEntry",Vector3(0,0.78,2.95))
	marker(truck,"RampApproach",Vector3(0,0,5.72))
	_batch(truck)
	# Keep the separately authored display scene intact when rebuilding the hull.
	var display := load("res://scenes/game/weapons/shotgun_silhouette.tscn").instantiate() as Node3D
	truck.get_node("Workshop/EquipmentWall/DisplayMount").add_child(display)
	display.owner=truck
	display.position=Vector3(-0.58,0.12,-0.016)
	var packed := PackedScene.new()
	var error := packed.pack(truck)
	if error==OK: error=ResourceSaver.save(packed,"res://scenes/game/props/exterminator_truck.tscn")
	print("TRUCK BUILD: ",error_string(error))
	truck.free()
	quit(0 if error==OK else 1)

func attach(parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner=truck

func group(parent: Node, title: String) -> Node3D:
	var node := Node3D.new()
	node.name=title
	attach(parent,node)
	return node

func marker(parent: Node, title: String, at: Vector3) -> Marker3D:
	var node := Marker3D.new()
	node.name=title
	attach(parent,node)
	node.position=at
	return node

func mat(title: String, color: String, roughness: float, metalness: float, wear: float) -> void:
	if title=="Glass":
		var glass := StandardMaterial3D.new()
		glass.albedo_color=Color(color)
		glass.roughness=roughness
		glass.metallic=0.45
		glass.clearcoat_enabled=true
		glass.clearcoat=0.6
		glass.clearcoat_roughness=0.15
		glass.take_over_path("res://assets/materials/truck/glass.tres")
		ResourceSaver.save(glass,glass.resource_path)
		mats[title]=glass
		return
	var resource := ShaderMaterial.new()
	resource.shader=Surface
	resource.set_shader_parameter("base_color",Color(color))
	resource.set_shader_parameter("roughness_base",roughness)
	resource.set_shader_parameter("metalness",metalness)
	resource.set_shader_parameter("fabric",0.0)
	resource.set_shader_parameter("wear",wear)
	var path := "res://assets/materials/truck/"+title.to_snake_case()+".tres"
	resource.take_over_path(path)
	ResourceSaver.save(resource,path)
	mats[title]=resource

func mesh(parent: Node, title: String, shape: Mesh, material: String, at := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	serial+=1
	node.name=title+str(serial)
	node.mesh=shape
	node.material_override=mats[material]
	attach(parent,node)
	node.position=at
	return node

func box(parent: Node, title: String, size: Vector3, at: Vector3, material: String, bevel := 0.015) -> MeshInstance3D:
	return mesh(parent,title,Geometry.bevel_box(size,bevel),material,at)

func solid(parent: Node, title: String, size: Vector3, at: Vector3, material: String, bevel := 0.015) -> MeshInstance3D:
	var node := box(parent,title,size,at,material,bevel)
	collision_box(title,size,at)
	return node

func collision_box(title: String, size: Vector3, at: Vector3, rotation := Vector3.ZERO) -> void:
	var collision := CollisionShape3D.new()
	collision.name=title+"Collision"
	var shape := BoxShape3D.new()
	shape.size=size
	collision.shape=shape
	attach(hull,collision)
	collision.position=at
	collision.rotation=rotation

func rod(parent: Node, title: String, a: Vector3, b: Vector3, radius: float, material: String) -> void:
	mesh(parent,title,Geometry.pipe([a,b],radius,12),material)

func cylinder(parent: Node, title: String, radius: float, depth: float, at: Vector3, material: String, rotation := Vector3.ZERO) -> void:
	var shape := CylinderMesh.new()
	shape.top_radius=radius
	shape.bottom_radius=radius
	shape.height=depth
	shape.radial_segments=8 if radius<0.02 else (12 if radius<0.05 else 40)
	shape.rings=1
	mesh(parent,title,shape,material,at).rotation=rotation

func text_label(parent: Node, words: String, at: Vector3, yaw: float, size: float, color := "ece8d2") -> void:
	var node := Label3D.new()
	node.name="Sign"+str(serial)
	serial+=1
	node.text=words
	node.font_size=64
	node.pixel_size=size/64.0
	node.outline_size=0
	node.modulate=Color(color)
	node.no_depth_test=false
	attach(parent,node)
	node.position=at
	node.rotation.y=yaw

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	var points: Array[Vector3]=[a,b,c]
	if (b-a).cross(c-a).dot(normal)>0: points.assign([a,c,b])
	for p: Vector3 in points:
		surface.set_normal(normal)
		surface.set_uv(Vector2(p.x+p.z,p.y))
		surface.add_vertex(p)

func panel(parent: Node, title: String, corners: Array[Vector3], normal: Vector3, material: String) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_triangle(surface,corners[0],corners[1],corners[2],normal)
	if corners.size()==4: _triangle(surface,corners[0],corners[2],corners[3],normal)
	surface.generate_tangents()
	surface.index()
	mesh(parent,title,surface.commit(),material)

func wheel(parent: Node, side: float, z: float) -> void:
	var at := Vector3(side*1.03,0.465,z)
	var profile: Array[Vector2]=[Vector2(0.27,-0.185),Vector2(0.38,-0.18),
		Vector2(0.43,-0.14),Vector2(0.465,-0.085),Vector2(0.465,0.085),
		Vector2(0.43,0.14),Vector2(0.38,0.18),Vector2(0.27,0.185)]
	mesh(parent,"Tire",Geometry.lathe(profile,64),"Rubber",at).rotation.z=PI/2
	cylinder(parent,"Rim",0.282,0.345,at,"Steel",Vector3(0,0,PI/2))
	cylinder(parent,"Hub",0.13,0.045,at+Vector3(side*0.183,0,0),"DarkSteel",Vector3(0,0,PI/2))
	for n: int in 8:
		var a := TAU*n/8
		var p := at+Vector3(side*0.186,sin(a)*0.205,cos(a)*0.205)
		cylinder(parent,"Vent",0.038,0.006,p,"DarkSteel",Vector3(0,0,PI/2))
		cylinder(parent,"Lug",0.016,0.025,at+Vector3(side*0.21,sin(a)*0.09,cos(a)*0.09),"Steel",Vector3(0,0,PI/2))
	var tread_shape := BoxMesh.new()
	tread_shape.size=Vector3(0.065,0.008,0.031)
	for n: int in 44:
		var a := TAU*n/44
		for lane: int in [-1,1]:
			var tread := mesh(parent,"Tread",tread_shape,"Rubber",at+Vector3(lane*0.055,cos(a)*0.464,sin(a)*0.464))
			tread.rotation.x=a
	var arc: Array[Vector3]=[]
	for n: int in 33:
		var a := PI*n/32
		arc.append(Vector3(side*1.24,0.46+sin(a)*0.60,z+cos(a)*0.60))
	mesh(parent,"WheelArch",Geometry.pipe(arc,0.065,12),"Sage")
	box(parent,"MudFlap",Vector3(0.34,0.35,0.025),Vector3(side*1.05,0.27,z+0.51),"Rubber",0.004)
	collision_box("Wheel",Vector3(0.38,0.85,0.88),at)

func _build_cab() -> void:
	var cab := group(truck,"Cab")
	# A sloped windscreen and short bonnet give the cab a service-van profile.
	var profile: Array[Vector2]=[Vector2(0.78,-3.08),Vector2(1.42,-3.08),
		Vector2(1.53,-2.68),Vector2(2.63,-2.27),Vector2(2.74,-1.12),Vector2(0.78,-1.12)]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var polygon := PackedVector2Array(profile)
	var indices := Geometry2D.triangulate_polygon(polygon)
	for side: float in [-1.0,1.0]:
		for n: int in range(0,indices.size(),3):
			var a := profile[indices[n]]
			var b := profile[indices[n+1]]
			var c := profile[indices[n+2]]
			_triangle(surface,Vector3(side*1.08,a.x,a.y),Vector3(side*1.08,b.x,b.y),Vector3(side*1.08,c.x,c.y),Vector3(side,0,0))
	for n: int in profile.size():
		var a := profile[n]
		var b := profile[(n+1)%profile.size()]
		var normal := Vector3(0,b.y-a.y,a.x-b.x).normalized()
		if normal.dot(Vector3(0,(a.x+b.x)/2-1.6,(a.y+b.y)/2+2.0))<0: normal=-normal
		_triangle(surface,Vector3(-1.08,a.x,a.y),Vector3(1.08,a.x,a.y),Vector3(1.08,b.x,b.y),normal)
		_triangle(surface,Vector3(-1.08,a.x,a.y),Vector3(1.08,b.x,b.y),Vector3(-1.08,b.x,b.y),normal)
	surface.generate_tangents()
	surface.index()
	mesh(cab,"CabShell",surface.commit(),"Ivory")
	collision_box("Cab",Vector3(2.16,1.9,1.93),Vector3(0,1.72,-2.10))
	for side: float in [-1.0,1.0]:
		var glass := box(cab,"WindscreenSeal",Vector3(0.94,1.12,0.027),Vector3(side*0.50,2.062,-2.500),"Rubber",0.04)
		glass.rotation.x=0.357
		var pane := box(cab,"Windscreen",Vector3(0.88,1.055,0.016),Vector3(side*0.50,2.063,-2.520),"Glass",0.025)
		pane.rotation.x=0.357
		panel(cab,"SideWindowSeal",[Vector3(side*1.087,1.63,-2.55),Vector3(side*1.087,2.58,-2.20),Vector3(side*1.087,2.59,-1.26),Vector3(side*1.087,1.63,-1.26)],Vector3(side,0,0),"Rubber")
		panel(cab,"SideWindow",[Vector3(side*1.092,1.69,-2.46),Vector3(side*1.092,2.52,-2.16),Vector3(side*1.092,2.53,-1.32),Vector3(side*1.092,1.69,-1.32)],Vector3(side,0,0),"Glass")
		box(cab,"Door",Vector3(0.025,0.76,1.21),Vector3(side*1.095,1.22,-1.92),"Sage",0.025)
		rod(cab,"WindowDivision",Vector3(side*1.11,1.65,-2.16),Vector3(side*1.11,2.5,-2.16),0.012,"Rubber")
		box(cab,"DoorHandle",Vector3(0.055,0.036,0.18),Vector3(side*1.132,1.48,-1.43),"Steel",0.008)
		box(cab,"Step",Vector3(0.20,0.095,0.67),Vector3(side*1.10,0.65,-1.34),"DarkSteel")
		rod(cab,"MirrorArm",Vector3(side*1.10,1.81,-2.46),Vector3(side*1.43,1.86,-2.60),0.017,"DarkSteel")
		box(cab,"MirrorCase",Vector3(0.20,0.36,0.09),Vector3(side*1.43,2.0,-2.61),"Rubber",0.035)
		box(cab,"MirrorGlass",Vector3(0.16,0.30,0.008),Vector3(side*1.43,2.0,-2.559),"Glass",0.025)
		box(cab,"HeadlightBezel",Vector3(0.45,0.25,0.10),Vector3(side*0.78,1.16,-3.085),"DarkSteel",0.035)
		box(cab,"Headlight",Vector3(0.36,0.16,0.016),Vector3(side*0.78,1.18,-3.145),"Light",0.025)
		box(cab,"TurnSignal",Vector3(0.22,0.06,0.02),Vector3(side*0.79,1.035,-3.14),"Ochre",0.007)
		rod(cab,"Wiper",Vector3(side*0.15,1.61,-2.73),Vector3(side*0.65,1.89,-2.63),0.012,"Rubber")
		text_label(cab,"07",Vector3(side*1.113,1.18,-1.78),side*PI/2,0.21)
	box(cab,"Bumper",Vector3(2.27,0.19,0.23),Vector3(0,0.81,-3.17),"DarkSteel",0.055)
	box(cab,"Grille",Vector3(0.90,0.25,0.05),Vector3(0,1.16,-3.10),"Rubber",0.02)
	for n: int in 5:
		box(cab,"GrilleSlat",Vector3(0.84,0.013,0.023),Vector3(0,1.065+n*0.044,-3.14),"Steel",0.004)
	text_label(cab,"N S",Vector3(0,1.46,-3.075),PI,0.075,"424e45")
	box(cab,"Roof",Vector3(2.20,0.085,1.23),Vector3(0,2.735,-1.72),"Ivory",0.04)
	for side: float in [-1.0,1.0]:
		cylinder(cab,"BeaconBase",0.105,0.045,Vector3(side*0.72,2.81,-1.77),"DarkSteel")
		cylinder(cab,"AmberBeacon",0.082,0.13,Vector3(side*0.72,2.9,-1.77),"Ochre")

func _build_workshop() -> void:
	var body := group(truck,"Workshop")
	solid(body,"Deck",Vector3(2.40,0.16,4.10),Vector3(0,0.70,1.0),"DarkSteel",0.025)
	solid(body,"Roof",Vector3(2.46,0.10,4.16),Vector3(0,3.16,1.0),"Ivory",0.045)
	solid(body,"FrontWall",Vector3(2.38,2.30,0.095),Vector3(0,1.93,-1.0),"Ivory")
	solid(body,"LeftWall",Vector3(0.095,2.30,4.05),Vector3(-1.15,1.93,1.0),"Ivory")
	# Right side service hatch: lower apron, end posts and raised awning.
	solid(body,"RightApron",Vector3(0.095,0.55,4.05),Vector3(1.15,1.055,1.0),"Sage")
	solid(body,"RightFront",Vector3(0.095,1.75,1.03),Vector3(1.15,2.205,-0.51),"Ivory")
	solid(body,"RightRear",Vector3(0.095,1.75,0.42),Vector3(1.15,2.205,2.80),"Ivory")
	solid(body,"HatchHeader",Vector3(0.10,0.18,2.60),Vector3(1.15,3.00,1.30),"Sage")
	var awning := box(body,"RaisedHatch",Vector3(1.18,0.065,2.57),Vector3(1.70,3.17,1.30),"Sage",0.025)
	awning.rotation.z=-0.10
	collision_box("RaisedHatch",Vector3(1.18,0.065,2.57),awning.position,awning.rotation)
	for z: float in [0.12,2.48]:
		rod(body,"HatchStrut",Vector3(1.18,2.32,z),Vector3(2.18,3.12,z),0.019,"Steel")
	for side: float in [-1.0,1.0]:
		box(body,"RoofDripRail",Vector3(0.035,0.055,4.14),Vector3(side*1.225,3.16,1.0),"Steel",0.008)
		box(body,"LowerRubRail",Vector3(0.035,0.095,4.10),Vector3(side*1.205,0.91,1.0),"DarkSteel",0.006)
		for z: float in [-0.98,3.00]:
			box(body,"CornerGuard",Vector3(0.055,2.24,0.075),Vector3(side*1.205,1.95,z),"Steel",0.012)
		for n: int in 22:
			for y: float in [1.05,3.035]:
				cylinder(body,"Rivet",0.009,0.009,Vector3(side*1.205,y,-0.94+n*0.185),"Steel",Vector3(0,0,PI/2))
		for z: float in [-0.75,0.85,2.65]:
			box(body,"Reflector",Vector3(0.012,0.046,0.17),Vector3(side*1.222,0.915,z),"Ochre",0.007)
	# Livery wraps the closed driver's side; the interior reserves display space.
	box(body,"BrandBand",Vector3(0.020,0.77,3.90),Vector3(-1.208,2.06,1.0),"Sage",0.003)
	box(body,"OchreStripe",Vector3(0.025,0.045,3.90),Vector3(-1.21,1.625,1.0),"Ochre",0.003)
	text_label(body,"NIGHT SHIFT",Vector3(-1.225,2.20,0.97),-PI/2,0.28)
	text_label(body,"PEST CONTROL  /  FIELD SERVICE",Vector3(-1.225,1.86,0.98),-PI/2,0.093)
	text_label(body,"SERVICE UNIT 07",Vector3(-1.217,1.28,1.05),-PI/2,0.10,"48574b")
	text_label(body,"PEST CONTROL",Vector3(1.208,1.12,1.18),PI/2,0.145)
	text_label(body,"NIGHT SHIFT",Vector3(1.208,3.00,1.30),PI/2,0.095)
	var wall := group(body,"EquipmentWall")
	wall.position=Vector3(-1.095,1.98,1.14)
	wall.rotation.y=PI/2
	# Local +Z points into the cargo bay. Keep this 2.85 x 1.45 m face clear.
	for n: int in 3:
		box(wall,"BlankPanel",Vector3(0.935,1.45,0.035),Vector3((n-1)*0.955,0,0),"Panel",0.014)
		for x: float in [-0.425,0.425]:
			for y: float in [-0.67,0.67]:
				cylinder(wall,"PanelFastener",0.010,0.005,Vector3((n-1)*0.955+x,y,0.021),"Steel",Vector3(PI/2,0,0))
	marker(wall,"DisplayMount",Vector3(0,0,0.035))
	text_label(wall,"NIGHT SHIFT  /  EQUIPMENT",Vector3(0,0.88,0.03),0,0.080)
	for side: float in [-1.0,1.0]:
		solid(body,"WheelTub",Vector3(0.39,0.27,1.14),Vector3(side*0.98,0.89,1.88),"DarkSteel",0.075)
	solid(body,"BenchCabinet",Vector3(0.48,0.80,2.44),Vector3(0.86,1.18,1.21),"Sage",0.025)
	solid(body,"Worktop",Vector3(0.57,0.055,2.52),Vector3(0.825,1.605,1.21),"Steel",0.02)
	for n: int in 4:
		box(body,"Drawer",Vector3(0.016,0.15,1.05),Vector3(0.605,0.905+n*0.18,1.83),"Ivory",0.01)
		rod(body,"DrawerPull",Vector3(0.576,0.93+n*0.18,1.62),Vector3(0.576,0.93+n*0.18,2.04),0.011,"Steel")
	box(body,"CabinetDoor",Vector3(0.016,0.69,1.05),Vector3(0.605,1.18,0.63),"Sage")
	box(body,"CabinetHandle",Vector3(0.036,0.16,0.03),Vector3(0.57,1.20,0.99),"Steel",0.006)
	# Recessed storage on the front bulkhead leaves the rear aisle unobstructed.
	solid(body,"FrontLocker",Vector3(0.68,1.83,0.24),Vector3(0.63,1.695,-0.82),"Sage",0.025)
	for n: int in 8:
		box(body,"LockerVent",Vector3(0.40,0.014,0.008),Vector3(0.63,2.32-n*0.045,-0.69),"DarkSteel",0.003)
	box(body,"LockerLatch",Vector3(0.033,0.15,0.05),Vector3(0.88,1.78,-0.67),"Steel",0.008)
	text_label(body,"FIELD SUPPLIES",Vector3(0.63,2.52,-0.685),0,0.047)
	for z: float in [-0.45,1.1,2.65]:
		box(body,"CeilingRib",Vector3(2.18,0.055,0.035),Vector3(0,3.083,z),"Steel",0.008)
		box(body,"WorkLight",Vector3(0.085,0.028,0.82),Vector3(0,3.045,z),"Light",0.006)
	# Dark raised floor strips give close-range traction detail without snagging.
	for n: int in 32:
		box(body,"FloorRib",Vector3(2.12,0.005,0.014),Vector3(0,0.782,-0.83+n*0.119),"Rubber",0.002)
	var light := OmniLight3D.new()
	light.name="WorkshopLight"
	light.light_color=Color("f0e8ca")
	light.light_energy=0.65
	light.omni_range=3.2
	light.omni_attenuation=1.3
	light.shadow_enabled=true
	attach(body,light)
	light.position=Vector3(0,2.95,1.15)

func _build_rear() -> void:
	var rear := group(truck,"RearAccess")
	for side: float in [-1.0,1.0]:
		solid(rear,"RearPillar",Vector3(0.18,2.30,0.12),Vector3(side*1.09,1.93,3.025),"Sage")
		box(rear,"TailCluster",Vector3(0.12,0.29,0.045),Vector3(side*1.09,1.15,3.105),"DarkSteel",0.014)
		box(rear,"BrakeLens",Vector3(0.083,0.15,0.020),Vector3(side*1.09,1.20,3.135),"Red",0.01)
		box(rear,"ReverseLens",Vector3(0.083,0.064,0.02),Vector3(side*1.09,1.075,3.135),"Light",0.007)
		var door := group(rear,"RearDoorLeft" if side<0 else "RearDoorRight")
		# Rear-facing hinges sit behind the frame. Mirrored positive-side yaw
		# swings each leaf into +Z, clear of the side panels and rear pillars.
		door.position=Vector3(side*1.02,1.94,3.165)
		door.rotation.y=side*deg_to_rad(112)
		box(door,"DoorLeaf",Vector3(0.99,2.19,0.075),Vector3(-side*0.50,0,0),"Ivory",0.025)
		box(door,"DoorInset",Vector3(0.86,1.92,0.025),Vector3(-side*0.50,0,-0.05),"Sage",0.018)
		rod(door,"LockBar",Vector3(-side*0.72,-0.94,0.055),Vector3(-side*0.72,0.95,0.055),0.017,"Steel")
		box(door,"LockHandle",Vector3(0.22,0.04,0.055),Vector3(-side*0.63,-0.12,0.075),"DarkSteel",0.007)
		for y: float in [-0.88,0.0,0.88]:
			box(door,"Hinge",Vector3(0.16,0.075,0.055),Vector3(-side*0.045,y,0.035),"Steel",0.008)
			box(rear,"HingeBracket",Vector3(0.10,0.075,0.15),Vector3(side*1.06,1.94+y,3.095),"Steel",0.008)
			cylinder(rear,"HingePin",0.018,0.105,Vector3(side*1.02,1.94+y,3.165),"Steel")
		var leaf_at := door.transform*Vector3(-side*0.50,0,0)
		collision_box(str(door.name),Vector3(0.99,2.19,0.075),leaf_at,door.rotation)
		text_label(door,"07",Vector3(-side*0.50,0.50,-0.07),PI,0.24)
		rod(rear,"EntryGrabRail",Vector3(side*0.96,1.08,3.16),Vector3(side*0.96,1.89,3.16),0.021,"Ochre")
	solid(rear,"RearHeader",Vector3(2.15,0.11,0.13),Vector3(0,3.095,3.025),"Sage")
	box(rear,"Threshold",Vector3(1.95,0.015,0.17),Vector3(0,0.782,3.0),"Steel",0.004)
	# Solid wedge: the bottom of the ramp meets y=0 exactly. Characters have
	# no step-up/jump mechanic, so stair-only access would make the bay unusable.
	var vertices := PackedVector3Array([Vector3(-0.76,0,3.04),Vector3(0.76,0,3.04),
		Vector3(-0.76,0.78,3.04),Vector3(0.76,0.78,3.04),Vector3(-0.76,0,5.54),Vector3(0.76,0,5.54)])
	var shape := ConvexPolygonShape3D.new()
	shape.points=vertices
	var collision := CollisionShape3D.new()
	collision.name="RampCollision"
	collision.shape=shape
	attach(hull,collision)
	panel(rear,"RampDeck",[vertices[2],vertices[3],vertices[5],vertices[4]],Vector3(0,2.5,0.78).normalized(),"DarkSteel")
	panel(rear,"RampLeft",[vertices[0],vertices[2],vertices[4]],Vector3.LEFT,"Steel")
	panel(rear,"RampRight",[vertices[1],vertices[5],vertices[3]],Vector3.RIGHT,"Steel")
	for side: float in [-1.0,1.0]:
		rod(rear,"RampEdge",Vector3(side*0.745,0.793,3.04),Vector3(side*0.745,0.013,5.54),0.013,"Ochre")
	for n: int in 28:
		var t := float(n+1)/29
		var tread := box(rear,"RampGrip",Vector3(1.39,0.004,0.025),Vector3(0,0.78*(1-t)+0.003,3.04+2.50*t),"Rubber",0.001)
		tread.rotation.x=-atan2(0.78,2.50)

func _batch(parent: Node) -> void:
	var groups: Dictionary[Material,Array] = {}
	for child: Node in parent.get_children():
		if child is MeshInstance3D:
			var material: Material=child.material_override
			if not groups.has(material): groups[material]=[]
			groups[material].append(child)
		elif child is Node3D:
			_batch(child)
	for material: Material in groups:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part: MeshInstance3D in groups[material]:
			for index: int in part.mesh.get_surface_count(): surface.append_from(part.mesh,index,part.transform)
			parent.remove_child(part)
			part.free()
		var combined := surface.commit()
		var material_name := material.resource_path.get_file().get_basename()
		var path := "res://assets/meshes/truck/"+str(parent.name).to_snake_case()+"_"+material_name+".res"
		combined.take_over_path(path)
		ResourceSaver.save(combined,path)
		var node := MeshInstance3D.new()
		node.name=material_name.to_pascal_case()+"Detail"
		node.mesh=combined
		node.material_override=material
		attach(parent,node)
