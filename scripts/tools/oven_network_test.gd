extends SceneTree
var failures: Array[String] = []
var connected := false
var children: Array[Dictionary] = []
var world: Node3D
var mode := "host"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	mode = "human" if "--oven-human" in args else "bug" if "--oven-bug" in args else "host"
	var net := root.get_node("Net")
	root.get_node("GameState").set_local_role_preference("exterminator" if mode == "human" else "cockroach")
	if mode == "host": _check(net.host_local_test(), "host failed")
	else:
		net.connected.connect(func() -> void: connected = true)
		_check(net.join_local_test(), "join failed")
		_check(await _until(func() -> bool: return connected), "connect timeout")
	world = load("res://scenes/game/game_world.tscn").instantiate()
	world.prototype_round_duration = 600
	root.add_child(world)
	if mode == "host": await _host()
	else: await _client()
	multiplayer_poll = false
	world.queue_free()
	await process_frame
	net.leave()
	for failure: String in failures: printerr("OVEN NETWORK FAIL: " + failure)
	print("OVEN NETWORK %s: %s" % [mode.to_upper(), "PASS" if failures.is_empty() else "FAIL"])
	quit(0 if failures.is_empty() else 1)

func _host() -> void:
	_launch("human")
	_check(await _until(func() -> bool: return world.ovens.get_state("Oven1").hot and float(world.ovens.get_state("Oven1").angle) > 1.56), "human open/hot requests missing")
	_launch("bug")
	_check(await _until(func() -> bool: return not world.ovens.get_state("Oven1").hot), "bug shutoff missing")
	_check(await _until(func() -> bool: return world.ovens.get_state("Oven1").hot), "human reheat missing")
	_check(await _until(func() -> bool: return _remote_bug() > 0 and world.combat.is_ghost(_remote_bug())), "oven never defeated client bug")
	var bug_id := _remote_bug()
	_check(await _until(func() -> bool: return not world.combat.is_ghost(bug_id), 14000), "bug respawn missing")
	await create_timer(0.7).timeout
	var bug := world.players.get_node_or_null(str(bug_id)) as Node3D
	_check(bug != null and bug.position.distance_to(world.home_base.global_position) < 0.3, "owner respawn did not replicate")
	_check(await _until(func() -> bool: return float(world.ovens.get_state("Oven1").angle) < 0.01), "remote close did not complete")
	for child: Dictionary in children:
		if not await _until(func() -> bool: return not OS.is_process_running(child.pid), 18000):
			OS.kill(child.pid)
			_check(false, "child timeout")
		else: _check(OS.get_process_exit_code(child.pid) == 0, "child failed")
		var log_text := FileAccess.get_file_as_string(child.log)
		_check(log_text.contains("OVEN NETWORK %s: PASS" % str(child.mode).to_upper()), "child PASS missing")
		_check(not log_text.contains("SCRIPT ERROR") and not log_text.contains("\nERROR:"), "child runtime error")
		if not failures.is_empty(): printerr(log_text)
		DirAccess.remove_absolute(child.log)

func _client() -> void:
	var id := world.multiplayer.get_unique_id()
	_check(await _until(func() -> bool: return world.players.has_node(str(id)) and world.get_match_phase() == 1), "world not ready")
	var token := world.players.get_node(str(id)) as CharacterBody3D
	_check(await _until(func() -> bool: return token.player_role == ("exterminator" if mode == "human" else "cockroach")), "role missing")
	var oven: Node3D = world.ovens._ovens.Oven1
	_check(not world.combat.damage_from_environment(1, 100), "client assigned heat damage")
	if mode == "human":
		token.position = oven.to_global(Vector3(0.52, 0.001, 1.82))
		token.velocity = Vector3.ZERO
		await create_timer(0.6).timeout
		world.ovens._request_action.rpc_id(1, "Oven4", "heat")
		world.ovens.request_action("Oven1", "door")
		world.ovens.request_action("Oven1", "heat")
		_check(await _until(func() -> bool: return world.ovens.get_state("Oven1").hot), "on state missing")
		_check(not world.ovens.get_state("Oven4").hot, "distant forged request accepted")
		_check(await _until(func() -> bool: return not world.ovens.get_state("Oven1").hot), "bug shutoff not replicated")
		await create_timer(1.4).timeout
		world.ovens.request_action("Oven1", "heat")
		_check(await _until(func() -> bool: return _remote_bug() > 0 and world.combat.is_ghost(_remote_bug())), "client death not replicated")
		_check(await _until(func() -> bool: return not world.combat.is_ghost(_remote_bug()), 14000), "client respawn not replicated")
		await create_timer(1.0).timeout
		world.ovens.request_action("Oven1", "door")
		_check(await _until(func() -> bool: return float(world.ovens.get_state("Oven1").angle) < 0.01), "closed pose missing")
		await create_timer(2.0).timeout
	else:
		_check(await _until(func() -> bool: return world.ovens.get_state("Oven1").hot and float(world.ovens.get_state("Oven1").angle) > 1.56), "late join lost door/heat")
		_check(oven.get_node("HeatGlow").visible and oven.get_node("Door").rotation.x > 1.56, "late-join visuals wrong")
		token.position = oven.to_global(Vector3(-0.55, 0.001, 0.55))
		token.velocity = Vector3.ZERO
		_check(await _until(func() -> bool: return int(world.combat.get_state(id).health) < 100), "heat did not hurt client")
		world.ovens._request_action.rpc_id(1, "Oven1", "door")
		world.ovens.request_action("Oven1", "heat")
		_check(await _until(func() -> bool: return not world.ovens.get_state("Oven1").hot), "inside shutoff rejected")
		var health: int = world.combat.get_state(id).health
		await create_timer(0.8).timeout
		_check(int(world.combat.get_state(id).health) == health and health > 0, "shutoff did not stop damage")
		_check(world.ovens.get_state("Oven1").open, "bug could close oven")
		_check(await _until(func() -> bool: return world.ovens.get_state("Oven1").hot), "reheat state missing")
		_check(await _until(func() -> bool: return world.combat.is_ghost(id)), "client never became ghost")
		var death_time := Time.get_ticks_msec()
		world.ovens._request_action.rpc_id(1, "Oven1", "heat")
		await create_timer(0.5).timeout
		_check(world.ovens.get_state("Oven1").hot, "ghost switched oven off")
		_check(await _until(func() -> bool: return not world.combat.is_ghost(id), 14000), "client never respawned")
		_check(Time.get_ticks_msec() - death_time >= 9600, "ghost duration too short")
		await create_timer(0.6).timeout
		_check(token.position.distance_to(world.home_base.global_position) < 0.3, "client respawn missed home")
		_check(await _until(func() -> bool: return float(world.ovens.get_state("Oven1").angle) < 0.01), "human closing pose missing")
		await create_timer(0.3).timeout

func _remote_bug() -> int:
	for peer_id: int in world.get_ready_peer_ids():
		if peer_id != 1 and world.get_role_for_peer(peer_id) == "cockroach": return peer_id
	return 0

func _launch(child_mode: String) -> void:
	var log_path := OS.get_temp_dir().path_join("oven-%s-%d.log" % [child_mode, Time.get_ticks_usec()])
	var pid := OS.create_process(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"), "--log-file", log_path,
		"--script", "res://scripts/tools/oven_network_test.gd", "--", "--oven-" + child_mode]) + root.get_node("Net").get_local_test_arguments())
	_check(pid > 0, "launch failed")
	children.append({"pid": pid, "log": log_path, "mode": child_mode})

func _until(check: Callable, timeout: int = 15000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout
	while Time.get_ticks_msec() < deadline:
		if check.call(): return true
		await process_frame
	return check.call()

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
