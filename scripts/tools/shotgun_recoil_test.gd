extends SceneTree
var failures: Array[String]=[]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var arena := Node3D.new()
	root.add_child(arena)
	_solid(arena,Vector3(30,0.4,30),Vector3(0,-0.2,0))
	var player := load("res://scenes/game/player_token.tscn").instantiate() as CharacterBody3D
	player.name="1"
	player.get_node("Shotgun").preview_enabled=true
	arena.add_child(player)
	player.configure_role("exterminator")
	var gun := player.get_node("Shotgun")
	await _frames(12)
	var start := player.position
	_check(gun.request_fire(),"first shot rejected")
	_check(player.velocity.z>6 and player.velocity.y>4,"shot does not launch shooter backward/up")
	_check(not gun.request_fire(),"repeat fire during tumble allowed")
	var saw_down := false
	var saw_getup := false
	for frame: int in 150:
		await physics_frame
		saw_down=saw_down or gun.recoil_phase==2
		saw_getup=saw_getup or gun.recoil_phase==3
		_check(player.global_transform.is_finite() and player.exterminator_model.transform.is_finite(),"nonfinite recoil pose")
	_check(saw_down and saw_getup and gun.recoil_phase==0,"tumble/land/get-up/ready sequence incomplete")
	print("SHOTGUN TRAVEL: ",player.position-start)
	_check(player.position.z-start.z>1 and player.position.z-start.z<5,"recoil displacement outside useful range: "+str(player.position-start))
	_check(player.exterminator_collision.basis.is_equal_approx(Basis.IDENTITY),"upright collision not restored")
	_check(player.exterminator_model.position.length()<0.01,"visual root did not return to standing")
	_check(gun.request_fire(),"second shot after recovery rejected")
	for frame: int in 90:
		await physics_frame
		if gun.recoil_phase==2: break
	var roof := _solid(arena,Vector3(4,0.2,4),player.position+Vector3(0,1.2,0))
	await _frames(90)
	_check(gun.recoil_phase==2,"stood up through low ceiling")
	var trapped_at := player.position
	Input.action_press("move_right")
	await _frames(210)
	Input.action_release("move_right")
	await _frames(90)
	_check(player.position.x > trapped_at.x + 2.0 and gun.recoil_phase == 0,
		"player cannot scoot clear and recover after recoiling under furniture")
	roof.free()
	await _frames(75)
	_check(gun.recoil_phase==0,"did not recover when ceiling cleared")
	player.position=Vector3(0,0.01,0)
	player.velocity=Vector3.ZERO
	_solid(arena,Vector3(4,3,0.2),Vector3(0,1.5,1.65))
	await _frames(15)
	_check(gun.request_fire(),"wall test shot rejected")
	await _frames(150)
	_check(player.position.z<0.6,"recoil passed through wall")
	_check(gun.recoil_phase==0,"wall impact prevented recovery")
	player.configure_role("cockroach")
	_check(not gun.request_fire(),"cockroach allowed to fire shotgun")
	_check(not gun._approve_request(99,999,0.0),"host accepted another peer's token request")
	_check(not gun._approve_request(1,999,NAN),"host accepted nonfinite aim")
	player.configure_role("exterminator")
	_check(not gun._approve_request(1,1,0.0),"host accepted stale shot nonce")
	arena.free()
	for failure: String in failures: push_error(failure)
	print("SHOTGUN RECOIL TEST: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _solid(parent: Node, size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size=size
	collision.shape=shape
	body.add_child(collision)
	parent.add_child(body)
	body.position=at
	return body

func _frames(count: int) -> void:
	for frame: int in count: await physics_frame

func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message): failures.append(message)
