extends SceneTree
var failures: Array[String] = []
var children: Array[Dictionary] = []
var world: Node3D
var connected := false
var mode := "host"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	mode = "human" if "--hiding-human" in args else "bug" if "--hiding-bug" in args else "host"
	var net := root.get_node("Net")
	root.get_node("GameState").set_local_role_preference("exterminator" if mode == "human" else "cockroach")
	if mode == "host": _check(net.host_local_test(), "host failed")
	else:
		net.connected.connect(func() -> void: connected = true)
		_check(net.join_local_test(), "join failed")
		if not await _until(func() -> bool: return connected): quit(1); return
	world = load("res://scenes/game/game_world.tscn").instantiate()
	world.prototype_round_duration = 600
	root.add_child(world)
	if mode == "host": await _host()
	else: await _client()
	multiplayer_poll = false
	world.queue_free()
	await process_frame
	net.leave()
	for failure: String in failures: printerr("HIDING NETWORK FAIL: " + failure)
	print("HIDING NETWORK %s: %s" % [mode.to_upper(), "PASS" if failures.is_empty() else "FAIL"])
	quit(0 if failures.is_empty() else 1)

func _host() -> void:
	await create_timer(0.2).timeout
	var token: CharacterBody3D = world.players.get_node("1")
	var box: Node3D = world.storage._props.PantryBox
	token.position = box.get_node("BugOutside").global_position
	token.velocity = Vector3.ZERO
	await create_timer(0.2).timeout
	_check(world.storage._handle_toggle(1, "PantryBox"), "initial box open rejected")
	token.position = Vector3(0, 0.001, 0)
	_check(await _until(func() -> bool: return world.storage.get_state("PantryBox").angle < -1.87), "initial lid failed")
	_launch("human")
	_check(await _until(func() -> bool: return world.storage.get_state("KitchenCabinet").angle < -1.62), "remote human door request missing")
	_launch("bug")
	_check(await _until(func() -> bool: return not world.storage.get_state("PantryBox").open), "remote bug close request missing")
	_check(await _until(func() -> bool: return _bug_crossed()), "vent movement did not replicate through pantry wall")
	_check(await _until(func() -> bool: return absf(world.storage.get_state("KitchenCabinet").angle) < 0.01), "human close did not replicate")
	for child: Dictionary in children:
		if not await _until(func() -> bool: return not OS.is_process_running(child.pid), 18000):
			OS.kill(child.pid)
			_check(false, "child timeout")
		else: _check(OS.get_process_exit_code(child.pid) == 0, "child failed")
		var log_text := FileAccess.get_file_as_string(child.log)
		_check(log_text.contains("HIDING NETWORK %s: PASS" % str(child.mode).to_upper()), "child PASS missing")
		_check(not log_text.contains("SCRIPT ERROR") and not log_text.contains("\nERROR:"), "child runtime error")
		if not failures.is_empty(): printerr(log_text)
		DirAccess.remove_absolute(child.log)

func _client() -> void:
	var id := world.multiplayer.get_unique_id()
	if not await _until(func() -> bool: return world.players.has_node(str(id)) and world.get_match_phase() == 1):
		_check(false, "world ready timeout"); return
	var token := world.players.get_node(str(id)) as CharacterBody3D
	_check(await _until(func() -> bool: return token.player_role == ("exterminator" if mode == "human" else "cockroach")), "role not applied")
	_check(await _until(func() -> bool: return world.storage.get_state("PantryBox").angle < -1.87), "late join lost open lid")
	_check(world.storage._props.PantryBox.get_node("Door").rotation.x < -1.87, "late-join lid visual wrong")
	_check(not world.storage._handle_toggle(id, "PantryBox"), "client directly changed host state")
	if mode == "human":
		var cabinet: Node3D = world.storage._props.KitchenCabinet
		token.position = cabinet.to_global(Vector3(1.15, 0.001, 1.10))
		token.velocity = Vector3.ZERO
		await create_timer(0.7).timeout
		_check(world.storage.can_reach(id, "KitchenCabinet"), "human cannot reach control at " + str(token.position))
		world.storage._request_toggle.rpc_id(1, "LobbyCabinet")
		world.storage.request_toggle("KitchenCabinet")
		_check(await _until(func() -> bool: return world.storage.get_state("KitchenCabinet").angle < -1.62), "remote cabinet did not open: " + str(world.storage.get_state("KitchenCabinet")))
		_check(not world.storage.get_state("LobbyCabinet").open, "forged distant request accepted")
		_check(await _until(func() -> bool: return not world.storage.get_state("PantryBox").open), "bug close missing")
		world.storage.request_toggle("KitchenCabinet")
		_check(await _until(func() -> bool: return absf(world.storage.get_state("KitchenCabinet").angle) < 0.01), "close pose missing")
		await create_timer(2).timeout
	else:
		_check(world.storage.get_state("KitchenCabinet").angle < -1.62, "late join lost cabinet angle")
		var box: Node3D = world.storage._props.PantryBox
		token.position = box.get_node("BugInside").global_position + Vector3(0, -0.031, -0.025)
		token.velocity = Vector3.ZERO
		await create_timer(0.7).timeout
		world.storage.request_toggle("PantryBox")
		_check(await _until(func() -> bool: return absf(world.storage.get_state("PantryBox").angle) < 0.01), "inside box close rejected")
		var vents: Node3D = world.get_node("DinerKitchen/BugVents")
		token.position = vents.get_node("PantryEntrance").global_position
		token.velocity = Vector3.ZERO
		# Exercise owner movement and its normal MultiplayerSynchronizer.
		token.camera_rig.rotation = Vector3.ZERO
		await create_timer(0.4).timeout
		Input.action_press("move_right")
		_check(await _until(func() -> bool: return token.position.x > -7.45, 6000), "client bug cannot cross vent")
		Input.action_release("move_right")
		_check(absf(token.position.z + 0.8) < 0.05, "vent escaped sideways")
		await create_timer(1).timeout

func _bug_crossed() -> bool:
	for peer_id: int in world.get_ready_peer_ids():
		if peer_id == 1 or world.get_role_for_peer(peer_id) != "cockroach": continue
		var token := world.players.get_node_or_null(str(peer_id)) as Node3D
		if token != null and token.position.x > -7.6 and absf(token.position.z + 0.8) < 0.05: return true
	return false

func _launch(child_mode: String) -> void:
	var log_path := OS.get_temp_dir().path_join("hiding-%s-%d.log" % [child_mode, Time.get_ticks_usec()])
	var pid := OS.create_process(OS.get_executable_path(), PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--log-file", log_path, "--script", "res://scripts/tools/hiding_network_test.gd", "--", "--hiding-" + child_mode]) + root.get_node("Net").get_local_test_arguments())
	_check(pid > 0, "child launch failed")
	children.append({"pid": pid, "log": log_path, "mode": child_mode})

func _until(check: Callable, timeout: int = 15000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout
	while Time.get_ticks_msec() < deadline:
		if check.call(): return true
		await process_frame
	return check.call()

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
