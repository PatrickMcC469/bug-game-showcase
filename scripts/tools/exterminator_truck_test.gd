extends SceneTree
## Validate reusable placement, saved geometry, and real human-capsule access.
var failures: Array[String]=[]
var triangles := 0
var meshes := 0
var colliders := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/game/props/exterminator_truck.tscn") as PackedScene
	if packed==null:
		_check(false,"truck scene failed to load")
		_finish()
		return
	var truck := packed.instantiate() as Node3D
	root.add_child(truck)
	_scan(truck)
	_check_rear_doors(truck)
	_check(meshes<70,"truck batching exceeds 70 meshes")
	_check(triangles<70000,"truck exceeds 70k triangle regression ceiling")
	_check(colliders>10,"truck collision missing")
	var bounds := _bounds(truck,truck)
	_check(bounds.position.y>=-0.01 and bounds.end.y<3.4,"truck height or floor contact invalid")
	_check(bounds.size.z<9.0 and bounds.size.x<4.2,"parked footprint exceeds placement contract")
	_check(truck.get_node_or_null("Workshop/EquipmentWall/DisplayMount") is Marker3D,"equipment wall mount missing")
	_check(truck.get_node_or_null("Workshop/EquipmentWall/DisplayMount/ShotgunSilhouette/Profile") is MeshInstance3D,"shotgun silhouette missing")
	var station := truck.get_node_or_null("Workshop/GasRefillStation")
	_check(station != null and station.is_in_group("gas_refill_stations"), "gas refill station registration missing")
	if station != null:
		_check(station.get_node_or_null("Control") is Marker3D, "gas refill interaction marker missing")
		_check(station.get_node_or_null("Status") is Label3D, "gas refill progress label missing")
		_check(station.get_node_or_null("DockedGun/Muzzle") is Marker3D, "docked gas gun missing")
	_check(truck.get_node_or_null("RampApproach") is Marker3D,"ramp approach marker missing")
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size=Vector3(100,0.20,100)
	floor_shape.shape=box_shape
	floor_shape.position.y=-0.10
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)
	# Instance the actual player, retaining its collider and floor settings.
	var player := load("res://scenes/game/player_token.tscn").instantiate() as CharacterBody3D
	player.name="1"
	root.add_child(player)
	player.call("configure_role","exterminator")
	player.set_physics_process(false)
	player.set_process(false)
	for pose: Transform3D in [Transform3D.IDENTITY,Transform3D(Basis(Vector3.UP,1.17),Vector3(13,0,-9))]:
		truck.transform=pose
		_check_rear_doors(truck)
		player.global_position=pose*Vector3(-0.12,0.05,6.08)
		player.velocity=Vector3.ZERO
		await physics_frame
		await physics_frame
		# 2.0 m/s approaches and climbs the ramp, then enters the clear aisle.
		for frame: int in 164:
			await physics_frame
			player.velocity=pose.basis*Vector3(0,player.velocity.y, -2.0)
			player.velocity.y-=9.8/60.0
			player.move_and_slide()
		var inside := truck.to_local(player.global_position)
		_check(inside.z<1.0 and inside.z>0.15,"human cannot reach equipment wall from ramp: "+str(inside))
		_check(absf(inside.y-0.78)<0.055,"human does not stand on cargo deck: "+str(inside))
		for frame: int in 165:
			await physics_frame
			player.velocity=pose.basis*Vector3(0,player.velocity.y,2.0)
			player.velocity.y-=9.8/60.0
			player.move_and_slide()
		var outside := truck.to_local(player.global_position)
		_check(outside.z>5.8 and outside.y<0.09,"human cannot descend to ground: "+str(outside))
	# Two independent instances can coexist; moving one does not move the other.
	var second := packed.instantiate() as Node3D
	second.position=Vector3(-15,0,7)
	root.add_child(second)
	_check(second.get_node("StaticCollision").get_instance_id()!=truck.get_node("StaticCollision").get_instance_id(),"instances share collision nodes")
	_check(second.get_node("Workshop/EquipmentWall/DisplayMount").global_position.distance_to(truck.get_node("Workshop/EquipmentWall/DisplayMount").global_position)>10,"mounts do not follow instance placement")
	second.free()
	player.free()
	truck.free()
	floor_body.free()
	_finish()

func _check_rear_doors(truck: Node3D) -> void:
	for title: String in ["RearDoorLeft","RearDoorRight"]:
		var door := truck.get_node("RearAccess/"+title) as Node3D
		var leaf := door.get_node("IvoryDetail") as MeshInstance3D
		var bounds := leaf.get_aabb()
		var panel_pose := leaf.global_transform*Transform3D(Basis.IDENTITY,bounds.get_center())
		var matched_collision := false
		for child: Node in truck.get_node("StaticCollision").get_children():
			if not child is CollisionShape3D or not child.shape is BoxShape3D: continue
			var size: Vector3=child.shape.size
			if child.global_position.distance_to(panel_pose.origin)<0.001:
				matched_collision=true
				_check(size.is_equal_approx(bounds.size) and child.global_basis.is_equal_approx(panel_pose.basis),
					"rear door collision does not match visible leaf: "+title)
				continue
			_check(not _boxes_overlap(panel_pose,bounds.size,child.global_transform,size),
				title+" intersects truck collision: "+str(child.name))
		_check(matched_collision,"missing collision at rear door: "+title)
		var local_center := truck.to_local(panel_pose.origin)
		_check(local_center.z>3.2,"rear door must open behind the truck: "+title)

func _boxes_overlap(a: Transform3D, a_size: Vector3, b: Transform3D, b_size: Vector3) -> bool:
	# Separating-axis test on oriented boxes, including the nine cross axes.
	# A world-space AABB would report false collisions for angled open doors.
	var axes: Array[Vector3]=[a.basis.x,a.basis.y,a.basis.z,b.basis.x,b.basis.y,b.basis.z]
	for i: int in 3:
		for j: int in 3: axes.append(a.basis[i].cross(b.basis[j]))
	for candidate: Vector3 in axes:
		if candidate.length_squared()<0.000001: continue
		var axis := candidate.normalized()
		var radius_a := 0.0
		var radius_b := 0.0
		for i: int in 3:
			radius_a+=absf(axis.dot(a.basis[i]))*a_size[i]*0.5
			radius_b+=absf(axis.dot(b.basis[i]))*b_size[i]*0.5
		if absf(axis.dot(a.origin-b.origin))>=radius_a+radius_b-0.0001: return false
	return true

func _scan(node: Node) -> void:
	_check(node.get_script()==null,"truck must not require runtime or map scripts: "+str(node.name))
	if node is CollisionShape3D:
		colliders+=1
		_check(node.shape!=null and not node.disabled,"disabled or missing collider")
	if node is MeshInstance3D:
		meshes+=1
		_check(node.mesh!=null and node.material_override!=null,"missing truck mesh or material")
		if node.mesh==null: return
		var path: String = node.mesh.resource_path
		var saved_gas_mesh := path.begins_with("res://scenes/game/weapons/gas_gun_model.tscn::") or path.begins_with("res://scenes/game/props/gas_refill_station.tscn::")
		_check(path.begins_with("res://assets/meshes/truck/") or path=="res://assets/meshes/shotgun/silhouette.res" or saved_gas_mesh,"mesh must be a saved truck or weapon-display resource")
		for surface: int in node.mesh.get_surface_count():
			var arrays: Array=node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			triangles+=(indices.size() if indices.size()>0 else vertices.size())/3
			for v: Vector3 in vertices: _check(v.is_finite(),"nonfinite truck vertex")
			for n: Vector3 in normals: _check(n.is_finite() and n.length()>0.8,"invalid truck normal")
			var count := indices.size() if indices.size()>0 else vertices.size()
			for t: int in range(0,count,3):
				var a := indices[t] if indices.size()>0 else t
				var b := indices[t+1] if indices.size()>0 else t+1
				var c := indices[t+2] if indices.size()>0 else t+2
				var cross := (vertices[b]-vertices[a]).cross(vertices[c]-vertices[a])
				var average := normals[a]+normals[b]+normals[c]
				_check(cross.dot(average)<=0.000001,"triangle winding disagrees with normals: "+str(node.name))
	for child: Node in node.get_children(): _scan(child)

func _bounds(node: Node, reference: Node3D) -> AABB:
	var result := AABB()
	if node is MeshInstance3D: result=(reference.global_transform.affine_inverse()*node.global_transform)*node.get_aabb()
	for child: Node in node.get_children():
		var next := _bounds(child,reference)
		if next.size!=Vector3.ZERO: result=next if result.size==Vector3.ZERO else result.merge(next)
	return result

func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message): failures.append(message)

func _finish() -> void:
	print("TRUCK GEOMETRY: %d triangles, %d mesh instances, %d collision shapes" % [triangles,meshes,colliders])
	for failure: String in failures: push_error(failure)
	print("EXTERMINATOR TRUCK TEST: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
