extends SceneTree
const Ballistics := preload("res://scripts/game/shotgun_ballistics.gd")
var failures: Array[String] = []
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var arena := Node3D.new()
	root.add_child(arena)
	_solid(arena, Vector3(30,0.4,30), Vector3(0,-0.2,0))
	var roach := load("res://scenes/game/player_token.tscn").instantiate() as CharacterBody3D
	roach.name = "1"
	arena.add_child(roach)
	roach.configure_role("cockroach")
	roach.position = Vector3(0,0.001,-2)
	roach.set_physics_process(false)
	await physics_frame
	await physics_frame
	var chest := Vector3(0,1.4,0)
	var grip := Vector3(0.13,1.4,-0.19)
	var direction := (roach.position + Vector3.UP*0.011 - grip).normalized()
	var shot := Ballistics.trace(roach.get_world_3d().direct_space_state,chest,grip,direction,[],1,1)
	_check(_hits(shot,roach)>0,"aimed pellet missed insect-sized collision")
	_check(shot.ends.size()==12,"pellet count wrong")
	var wall := _solid(arena,Vector3(2,2,0.02),Vector3(0,1,-1))
	await physics_frame
	await physics_frame
	shot = Ballistics.trace(roach.get_world_3d().direct_space_state,chest,grip,direction,[],1,1)
	_check(_hits(shot,roach)==0,"pellets damaged through cover")
	wall.position.z=-0.3
	await physics_frame
	await physics_frame
	shot = Ballistics.trace(roach.get_world_3d().direct_space_state,chest,grip,direction,[],1,1)
	_check(shot.blocked and shot.hits.is_empty(),"clipped muzzle fired through thin wall")
	wall.free()
	await physics_frame
	shot = Ballistics.trace(roach.get_world_3d().direct_space_state,chest,grip,direction,[roach.get_rid()],1,1)
	_check(_hits(shot,roach)==0,"excluded ghost still absorbed pellets")
	# The barrel's cover check must not create a damage-free point-blank zone.
	roach.position = Vector3(0, 1.389, -0.3)
	await physics_frame
	await physics_frame
	shot = Ballistics.trace(roach.get_world_3d().direct_space_state, chest, chest,
		Vector3.FORWARD, [], 1, 1)
	_check(_hits(shot, roach) > 0, "point-blank target inside barrel length was immune")
	roach.position = Vector3(0, 0.001, -2)
	wall = _solid(arena, Vector3(2, 2, 0.2), Vector3(0, 1, 0))
	await physics_frame
	await physics_frame
	shot = Ballistics.trace(roach.get_world_3d().direct_space_state, chest, grip,
		direction, [], 1, 1)
	_check(shot.blocked and shot.hits.is_empty(), "shot starting inside cover escaped the wall")
	wall.free()
	_check(Ballistics.damage_at(2)>Ballistics.damage_at(14),"damage does not fall off")
	roach.configure_role("exterminator")
	roach.shotgun.preview_enabled=true
	_check(not roach.shotgun._approve_request(1,999,0,Vector3(NAN,0,0)),"nonfinite aim accepted")
	_check(not roach.shotgun._approve_request(1,999,0,Vector3(2,0,0)),"non-unit aim accepted")
	for aimed: Vector3 in [Vector3.UP,Vector3.DOWN,Vector3.FORWARD]:
		for pellet: Vector3 in Ballistics.pellet_directions(aimed,23):
			_check(pellet.is_finite() and absf(pellet.length()-1)<0.001,"invalid pellet direction")
			_check(pellet.dot(aimed)>=cos(Ballistics.SPREAD)-0.0001,"pellet outside spread cone")
	arena.free()
	for failure: String in failures: printerr(failure)
	print("SHOTGUN DAMAGE TEST: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
func _hits(shot: Dictionary, target: Node) -> int:
	var count := 0
	for hit: Dictionary in shot.hits:
		if hit.collider==target: count+=1
	return count
func _solid(parent: Node, size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size=size
	var collision := CollisionShape3D.new()
	collision.shape=shape
	body.add_child(collision)
	parent.add_child(body)
	body.position=at
	return body
func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
