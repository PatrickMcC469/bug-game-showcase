extends SceneTree
## Real ENet peers exercise a client-owned shot and joining an existing tumble.
var failures: Array[String] = []
var connected := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var net := root.get_node("Net")
	var state := root.get_node("GameState")
	state.set_local_role_preference("exterminator")
	var client := "--shotgun-client" in OS.get_cmdline_user_args()
	if client:
		net.connected.connect(func() -> void: connected = true)
		_check(net.join_local_test(), "join failed")
		_check(await _until(func() -> bool: return connected), "connection timeout")
	else:
		_check(net.host_local_test(), "host failed")
	if not failures.is_empty():
		_finish(net, null, client)
		return
	var world := load("res://scenes/game/game_world.tscn").instantiate() as Node3D
	root.add_child(world)
	# Identical isolated floor above the diner keeps the test independent of props.
	_solid(world, Vector3(30, 0.4, 30), Vector3(0, 19.8, 0))
	if client:
		await _client(world, net)
	else:
		await _host(world)
	await _finish(net, world, client)

func _host(world: Node3D) -> void:
	var player := world.get_node("Players/1") as CharacterBody3D
	player.position = Vector3(-5, 20.01, 0)
	await create_timer(0.3).timeout
	var gun := player.get_node("Shotgun")
	_check(gun.request_fire(), "host practice shot denied")
	_check(await _until(func() -> bool: return gun.recoil_phase == 2), "host did not land")
	var roof := _solid(world, Vector3(4, 0.2, 4), player.position + Vector3(0, 1.2, 0))
	var log_path := OS.get_temp_dir().path_join("bug-shotgun-client-%d.log" % Time.get_ticks_usec())
	var pid := OS.create_process(OS.get_executable_path(), PackedStringArray([
		"--headless", "--log-file", log_path, "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://scripts/tools/shotgun_network_test.gd", "--", "--shotgun-client",
	]) + root.get_node("Net").get_local_test_arguments())
	_check(pid > 0, "could not launch client")
	var phases: Dictionary = {}
	var saw_serial := false
	var saw_travel := false
	var saw_reload := false
	var saw_reload_pose := false
	var deadline := Time.get_ticks_msec() + 20000
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		for other: Node in world.get_node("Players").get_children():
			if other.name == "1": continue
			var remote_gun := other.get_node("Shotgun")
			saw_reload = saw_reload or world.shotgun_ammo.is_reloading(other.name.to_int())
			saw_reload_pose = saw_reload_pose or other.exterminator_model.reload_blend > 0.5
			if remote_gun.shot_serial > 0:
				saw_serial = true
				phases[remote_gun.recoil_phase] = true
				saw_travel = saw_travel or other.position.z > 1.0
				_check(not other.camera.current, "remote camera stole host view")
				if is_instance_valid(roof): roof.free()
		await process_frame
	_check(saw_serial and saw_travel, "client-approved shot/movement did not replicate")
	_check(saw_reload and saw_reload_pose, "client truck reload / arm pose did not replicate to host")
	for phase: int in [0, 1, 2, 3]:
		_check(phases.has(phase), "host missed client recoil phase %d" % phase)
	_check(gun.recoil_phase == 0, "host failed to recover after ceiling cleared")
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
		_check(false, "client timed out")
	elif pid > 0:
		_check(OS.get_process_exit_code(pid) == 0, "client exited unsuccessfully")
	var client_log := FileAccess.get_file_as_string(log_path)
	_check(client_log.contains("SHOTGUN CLIENT: PASS"), "client pass marker missing")
	if not failures.is_empty(): printerr(client_log)
	DirAccess.remove_absolute(log_path)

func _client(world: Node3D, net: Node) -> void:
	var id: int = net.get_multiplayer().get_unique_id()
	var own_path := "Players/%d" % id
	if not await _until(func() -> bool:
		return world.has_node(own_path) and world.has_node("Players/1") and world.get_role_for_peer(id) == "exterminator"):
		_check(false, "client missing tokens/role snapshot")
		return
	var player := world.get_node(own_path) as CharacterBody3D
	_check(await _until(func() -> bool: return player.player_role=="exterminator"),
		"client token role was not applied")
	await physics_frame
	var host := world.get_node("Players/1")
	var host_gun := host.get_node("Shotgun")
	_check(await _until(func() -> bool: return host_gun.shot_serial == 1 and host_gun.recoil_phase == 2),
		"late join lost existing shot/down pose")
	_check(not host.camera.current and player.camera.current, "camera ownership wrong")
	_check(await _until(func() -> bool: return host.exterminator_collision.position.y < 0.5),
		"late join did not derive prone collision from the received pose")
	_check(not host_gun.request_fire(), "client could fire host token")
	_check(world.shotgun_ammo.shells(1) == 5, "late join lost host shell count")
	world._report_world_ready.rpc_id(1, "cockroach")
	await create_timer(0.15).timeout
	_check(world.get_role_for_peer(id) == "exterminator", "repeated readiness message changed the client's role")
	player.position = Vector3(5, 20.01, 0)
	player.velocity = Vector3.ZERO
	await create_timer(0.3).timeout
	var gun := player.get_node("Shotgun")
	gun._pending_nonce = 999
	_check(not gun.request_fire(), "slow reliable approval was replaced by another nonce")
	gun._pending_nonce = 0
	_check(gun._request_aimed_shot(NAN, Vector3.FORWARD), "invalid host-bound request was not sent")
	_check(await _until(func() -> bool: return gun._pending_nonce == 0), "host rejection left the weapon permanently pending")
	_check(gun.shot_serial == 0, "rejected request fired a shot")
	_check(gun.request_fire(), "client request rejected locally")
	_check(await _until(func() -> bool: return gun.shot_serial == 1), "host never approved client shot")
	_check(await _until(func() -> bool: return world.shotgun_ammo.shells(id) == 5), "client ammo consumption did not replicate")
	_check(not gun.request_fire(), "client could fire during recoil")
	var phases: Dictionary = {}
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		phases[gun.recoil_phase] = true
		if gun.recoil_phase == 0 and host_gun.recoil_phase == 0: break
		await process_frame
	for phase: int in [0, 1, 2, 3]:
		_check(phases.has(phase), "client missed own phase %d" % phase)
	_check(player.position.z > 1.0 and player.position.z < 5.0, "client recoil travel wrong: "+str(player.position))
	_check(host_gun.recoil_phase == 0, "host recovery did not replicate")
	var ammo: Node = world.shotgun_ammo
	ammo.request_reload()
	await create_timer(0.3).timeout
	_check(not ammo.is_reloading(id) and ammo.shells(id) == 5, "host accepted reload away from truck")
	_check(not ammo._begin_reload(1) and not ammo.consume_shell(1), "client mutated host ammo")
	player.position = world.gas_weapon._station.get_node("Control").global_position - Vector3.UP
	player.velocity = Vector3.ZERO
	await create_timer(0.4).timeout
	ammo.request_reload()
	_check(await _until(func() -> bool: return ammo.is_reloading(id)), "remote reload request rejected")
	_check(not gun.request_fire(), "client fired during truck reload")
	_check(await _until(func() -> bool: return ammo.shells(id) == 6 and not ammo.is_reloading(id)), "remote reload failed to restore ammo")
	await create_timer(0.4).timeout

func _solid(parent: Node, size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	body.position = at
	return body

func _until(check: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline:
		if check.call(): return true
		await process_frame
	return check.call()

func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message): failures.append(message)

func _finish(net: Node, world: Node, client: bool) -> void:
	multiplayer_poll = false
	if world != null:
		world.queue_free()
		await process_frame
	net.leave()
	for failure: String in failures: printerr(failure)
	print("SHOTGUN CLIENT: " if client else "SHOTGUN NETWORK TEST: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
