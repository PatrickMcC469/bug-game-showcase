extends SceneTree
## A remote human toggles gas; a late-joining bug uses a valve and dies in oil.
var failures: Array[String] = []
var connected := false
var children: Array[Dictionary] = []
var world: Node3D
var mode := "host"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	mode = "human" if "--kitchen-human" in args else "bug" if "--kitchen-bug" in args else "host"
	var net := root.get_node("Net")
	root.get_node("GameState").set_local_role_preference("exterminator" if mode == "human" else "cockroach")
	if mode == "host": _check(net.host_local_test(), "host failed")
	else:
		net.connected.connect(func() -> void: connected = true)
		_check(net.join_local_test(), "join failed")
		_check(await _until(func() -> bool: return connected), "connection timeout")
	world = load("res://scenes/game/game_world.tscn").instantiate()
	world.prototype_round_duration = 600
	root.add_child(world)
	if mode == "host": await _host()
	else: await _client()
	multiplayer_poll = false
	world.queue_free()
	await process_frame
	net.leave()
	for failure: String in failures: printerr("KITCHEN NETWORK FAIL: " + failure)
	print("KITCHEN NETWORK %s: %s" % [mode.to_upper(), "PASS" if failures.is_empty() else "FAIL"])
	quit(0 if failures.is_empty() else 1)

func _host() -> void:
	var token := world.players.get_node("1") as CharacterBody3D
	_launch("human")
	_check(await _until(func() -> bool: return world.kitchen_hazards.is_on("Range1")), "client human switch never arrived")
	_check(not world.kitchen_hazards.is_on("Range4"), "distant forged request changed another stove")
	var flames: Array[Node] = world.kitchen_hazards._stations.Range1.find_children("FlameOrigin", "Marker3D", true, false)
	token.position = (flames[1] as Node3D).global_position + Vector3.UP * 0.065
	token.velocity = Vector3.ZERO
	_check(await _until(func() -> bool: return world.combat.is_ghost(1)), "stove did not defeat host bug")
	_launch("bug")
	_check(await _until(func() -> bool: return world.kitchen_hazards.is_on("Range2")), "late client bug switch never arrived")
	_check(await _until(func() -> bool: return not world.combat.is_ghost(1), 14000), "host bug did not respawn")
	await create_timer(1.2).timeout
	_check(int(world.combat.get_state(1).health) == 100 and token.position.distance_to(world.home_base.global_position) < 0.3, "respawn repeated damage or missed home")
	_check(await _until(func() -> bool: return not world.kitchen_hazards.is_on("Range1")), "human could not turn stove off")
	for child: Dictionary in children:
		if not await _until(func() -> bool: return not OS.is_process_running(child.pid), 25000):
			OS.kill(child.pid)
			_check(false, "child timed out")
		else: _check(OS.get_process_exit_code(child.pid) == 0, "child failed: " + str(child.mode))
		var log_text := FileAccess.get_file_as_string(child.log)
		_check(log_text.contains("KITCHEN NETWORK %s: PASS" % str(child.mode).to_upper()), "child PASS missing")
		_check(not log_text.contains("SCRIPT ERROR") and not log_text.contains("\nERROR:"), "child runtime error")
		if not failures.is_empty(): printerr(log_text)
		DirAccess.remove_absolute(child.log)

func _client() -> void:
	var id := world.multiplayer.get_unique_id()
	_check(await _until(func() -> bool: return world.players.has_node(str(id)) and world.players.has_node("1") and world.get_match_phase() == 1), "world not ready")
	var token := world.players.get_node(str(id)) as CharacterBody3D
	_check(await _until(func() -> bool: return token.player_role == ("exterminator" if mode == "human" else "cockroach")), "role not applied")
	_check(not world.combat.kill_from_environment(1), "client assigned lethal damage")
	if mode == "human":
		var control: Node3D = world.kitchen_hazards._stations.Range1.get_node("HandControl")
		token.position = Vector3(control.global_position.x, 0.001, control.global_position.z + 0.65)
		token.velocity = Vector3.ZERO
		await create_timer(0.5).timeout
		world.kitchen_hazards._request_toggle.rpc_id(1, "Range4")
		world.kitchen_hazards.request_toggle("Range1")
		_check(await _until(func() -> bool: return world.kitchen_hazards.is_on("Range1")), "human did not receive on state")
		_check(await _until(func() -> bool: return world.combat.is_ghost(1)), "human missed host death")
		_check(await _until(func() -> bool: return not world.combat.is_ghost(1), 14000), "human missed host respawn")
		world.kitchen_hazards.request_toggle("Range1")
		_check(await _until(func() -> bool: return not world.kitchen_hazards.is_on("Range1")), "human off state missing")
		await create_timer(8.0).timeout
	else:
		_check(await _until(func() -> bool: return world.kitchen_hazards.is_on("Range1") and world.combat.is_ghost(1)), "late join missed active stove/ghost")
		for effect: Node3D in world.kitchen_hazards._stations.Range1.find_children("FlameEffect", "Node3D", true, false):
			_check(effect.visible, "late-join flame art hidden")
		var control: Node3D = world.kitchen_hazards._stations.Range2.get_node("FloorControl")
		token.position = Vector3(control.global_position.x, 0.001, control.global_position.z + 0.10)
		token.velocity = Vector3.ZERO
		await create_timer(0.5).timeout
		world.kitchen_hazards.request_toggle("Range2")
		_check(await _until(func() -> bool: return world.kitchen_hazards.is_on("Range2")), "bug toggle missing")
		var fryer := world.get_node("DinerKitchen/HotLineDetails/TwinBasketFryer") as Node3D
		token.position = fryer.global_position + Vector3(0.35, 0.946, 0)
		token.velocity = Vector3.ZERO
		_check(await _until(func() -> bool: return world.combat.is_ghost(id)), "client oil death missing")
		var died_at := Time.get_ticks_msec()
		token.position = Vector3(control.global_position.x, 0.001, control.global_position.z + 0.10)
		token.velocity = Vector3.ZERO
		await create_timer(0.3).timeout
		world.kitchen_hazards._request_toggle.rpc_id(1, "Range2")
		await create_timer(0.4).timeout
		_check(world.kitchen_hazards.is_on("Range2"), "ghost forged toggle accepted")
		_check(await _until(func() -> bool: return not world.combat.is_ghost(id), 14000), "client did not respawn")
		_check(Time.get_ticks_msec() - died_at >= 9600, "client ghost ended early")
		await create_timer(1.2).timeout
		_check(int(world.combat.get_state(id).health) == 100 and token.position.distance_to(world.home_base.global_position) < 0.3, "client respawn position or health wrong")

func _launch(child_mode: String) -> void:
	var log_path := OS.get_temp_dir().path_join("kitchen-%s-%d.log" % [child_mode, Time.get_ticks_usec()])
	var pid := OS.create_process(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"), "--log-file", log_path,
		"--script", "res://scripts/tools/kitchen_hazards_network_test.gd", "--", "--kitchen-" + child_mode]) + root.get_node("Net").get_local_test_arguments())
	_check(pid > 0, "could not launch client")
	children.append({"pid": pid, "log": log_path, "mode": child_mode})

func _until(check: Callable, timeout: int = 15000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout
	while Time.get_ticks_msec() < deadline:
		if check.call(): return true
		await process_frame
	return check.call()

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
