extends SceneTree
## Real client fires at a host-owned roach; a third peer joins its ghost timer.
const LateJoinGate := preload("res://scripts/tools/late_join_gate.gd")
var failures: Array[String] = []
var connected := false
var children: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := "shooter" if "--combat-shooter" in args else "viewer" if "--combat-viewer" in args else "host"
	var world_scene := load("res://scenes/game/game_world.tscn") as PackedScene
	if not await LateJoinGate.wait_for_release(self):
		printerr("ROACH COMBAT: late-join readiness timed out")
		quit(1)
		return
	var net := root.get_node("Net")
	root.get_node("GameState").set_local_role_preference("cockroach" if mode=="host" else "exterminator")
	if mode=="host":
		_check(net.host_local_test(),"host failed")
	else:
		net.connected.connect(func() -> void: connected=true)
		_check(net.join_local_test(),"join failed")
		_check(await _until(func() -> bool: return connected),"connection timeout")
	if not failures.is_empty():
		for failure: String in failures: printerr(failure)
		net.leave()
		quit(1)
		return
	var world := world_scene.instantiate() as Node3D
	root.add_child(world)
	_floor(world)
	if mode=="host": await _host(world)
	else: await _client(world,net,mode)
	multiplayer_poll=false
	world.queue_free()
	await process_frame
	net.leave()
	for failure: String in failures: printerr(failure)
	print("ROACH COMBAT ",mode.to_upper(),": ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _host(world: Node3D) -> void:
	var roach := world.get_node("Players/1") as CharacterBody3D
	# Carry a real finite snack before defeat so the ghost cannot retain it.
	roach.position=world.food_run.get_food_records()[0].pos+Vector3.UP*0.0025
	await create_timer(0.3).timeout
	world.food_run.request_action("grab",0)
	_check(world.food_run.get_cargo_ids(1).size()==1,"setup could not grab food")
	roach.position=Vector3(0,20.001,0)
	roach.velocity=Vector3.ZERO
	await create_timer(0.2).timeout
	var viewer := _launch("viewer")
	_check(await _until(func() -> bool: return LateJoinGate.is_ready(viewer.gate),30000),"viewer assets did not become ready")
	_launch("shooter")
	_check(await _until(func() -> bool: return int(world.combat.get_state(1).health)<100),"remote shot never damaged host")
	_check(await _until(func() -> bool: return world.combat.is_ghost(1)),"roach never became ghost")
	var start := Time.get_ticks_msec()
	_check(world.food_run.get_cargo_ids(1).is_empty(),"ghost kept cargo")
	_check(not world.food_run._handle_action(1,"grab",0,Vector3.ZERO),"ghost could grab food")
	_check(not world.serving_cart._handle_request(1),"ghost could operate cart")
	_check(not world.combat._damage(1,100),"ghost took repeat damage")
	_check(float(world.combat.get_state(1).ghost_left)>9.5,"ghost timer did not start at ten seconds")
	_check(LateJoinGate.release(viewer.gate),"could not release late viewer join")
	var at := roach.position
	Input.action_press("move_forward")
	for frame: int in 18: await physics_frame
	Input.action_release("move_forward")
	_check(roach.position.distance_to(at)>0.1,"ghost could not walk")
	_check(roach.vitals.ghost,"ghost material state missing on owner")
	_check(await _until(func() -> bool: return not world.combat.is_ghost(1),14000),"ghost never respawned")
	var elapsed := (Time.get_ticks_msec()-start)/1000.0
	_check(elapsed>=9.8 and elapsed<10.5,"ghost duration wrong: %.2fs" % elapsed)
	await create_timer(0.3).timeout
	_check(roach.position.distance_to(world.home_base.global_position)<0.3,"respawn did not return to home base")
	_check(roach.vitals.health==100 and not roach.vitals.ghost,"respawn did not restore health/art")
	for mesh: MeshInstance3D in roach.vitals._materials:
		_check(mesh.material_override==roach.vitals._materials[mesh],"ghost material was not restored")
	_check(world.can_peer_act(1),"respawn did not restore interactions")
	_check(not world.combat._damage(1,-10),"negative damage accepted")
	world._finish_round(3)
	_check(not world.combat._damage(1,60),"damage applied after round result")
	for child: Dictionary in children:
		if not await _until(func() -> bool: return not OS.is_process_running(child.pid),10000):
			OS.kill(child.pid)
			_check(false,"child process timeout")
		else: _check(OS.get_process_exit_code(child.pid)==0,"child process failed")
		var log_text := FileAccess.get_file_as_string(child.log)
		_check(log_text.contains("ROACH COMBAT %s: PASS" % str(child.mode).to_upper()),"child pass marker missing")
		if not failures.is_empty(): printerr(log_text)
		LateJoinGate.cleanup(child.gate)
		DirAccess.remove_absolute(child.log)

func _client(world: Node3D, net: Node, mode: String) -> void:
	var peer_id: int=net.get_multiplayer().get_unique_id()
	var own_path := "Players/%d" % peer_id
	if not await _until(func() -> bool: return world.has_node(own_path) and world.has_node("Players/1") and world.get_role_for_peer(peer_id)=="exterminator"):
		_check(false,"missing replicated tokens/roles")
		return
	var own := world.get_node(own_path) as CharacterBody3D
	_check(await _until(func() -> bool: return own.player_role=="exterminator"),"client role not applied")
	await physics_frame
	var roach := world.get_node("Players/1") as CharacterBody3D
	_check(own.camera.current and not roach.camera.current,"camera ownership wrong")
	_check(not world.combat._damage(1,999),"client could assign damage locally")
	if mode=="shooter":
		own.position=Vector3(0,20.001,2)
		own.velocity=Vector3.ZERO
		await create_timer(0.4).timeout
		for attempt: int in 4:
			if world.combat.is_ghost(1): break
			own.camera.look_at(roach.global_position+Vector3.UP*0.011)
			_check(own.shotgun.request_fire(),"client shot rejected")
			await create_timer(2.6).timeout
		_check(await _until(func() -> bool: return world.combat.is_ghost(1)),"client never received defeat")
	else:
		_check(await _until(func() -> bool: return world.combat.is_ghost(1)),"late join lost ghost state")
		for other: int in world.get_ready_peer_ids():
			if other != 1: _check(world.get_role_for_peer(other) == "exterminator", "late join lost another player's role override")
		_check(float(world.combat.get_state(1).ghost_left)>0 and float(world.combat.get_state(1).ghost_left)<10,"late join restarted ghost timer")
	_check(await _until(func() -> bool: return roach.vitals.ghost),"remote roach never turned translucent")
	_check(not world.can_peer_act(1),"ghost interaction state missing remotely")
	_check(await _until(func() -> bool: return not world.combat.is_ghost(1),14000),"remote respawn missing")
	_check(int(world.combat.get_state(1).health)==100,"remote health not restored")
	await create_timer(0.5).timeout
	_check(roach.position.distance_to(world.home_base.global_position)<0.3,"owner respawn position did not replicate")
	# Finish one client disconnect before the other closes its ENet channels.
	if mode=="viewer": await create_timer(0.8).timeout

func _launch(mode: String) -> Dictionary:
	var log_path := OS.get_temp_dir().path_join("roach-combat-%s-%d-%d.log" % [mode,OS.get_process_id(),Time.get_ticks_usec()])
	var gate_path := log_path + ".gate" if mode == "viewer" else ""
	var arguments: PackedStringArray = PackedStringArray([
		"--headless","--path",ProjectSettings.globalize_path("res://"),"--log-file",log_path,
		"--script","res://scripts/tools/roach_combat_network_test.gd","--","--combat-"+mode]) + root.get_node("Net").get_local_test_arguments()
	if not gate_path.is_empty():
		arguments.append(LateJoinGate.ARGUMENT_PREFIX + gate_path)
	var pid := OS.create_process(OS.get_executable_path(),arguments)
	_check(pid>0,"could not launch "+mode)
	var child := {"pid":pid,"log":log_path,"mode":mode,"gate":gate_path}
	children.append(child)
	return child

func _floor(world: Node3D) -> void:
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size=Vector3(30,0.4,30)
	var collision := CollisionShape3D.new()
	collision.shape=shape
	body.add_child(collision)
	world.add_child(body)
	body.position=Vector3(0,19.8,0)

func _until(check: Callable, timeout: int=18000) -> bool:
	var end := Time.get_ticks_msec()+timeout
	while Time.get_ticks_msec()<end:
		if check.call(): return true
		await process_frame
	return check.call()

func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message): failures.append(message)
