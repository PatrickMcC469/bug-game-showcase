extends SceneTree
const TARGET := Vector3(6, 0.001, -12)
const SHOOTER := Vector3(6, 0.001, -10)
var failures: Array[String] = []
var world: Node3D
var gas: Node
var mode := "host"
var connected := false
var children: Array[Dictionary] = []

func _initialize() -> void:
	create_timer(100).timeout.connect(func() -> void: printerr("GAS NETWORK TIMEOUT"); quit(1))
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	mode = "human" if "--gas-human" in args else "observer" if "--gas-observer" in args else "host"
	root.get_node("GameState").set_local_role_preference("exterminator" if mode == "human" else "cockroach")
	var world_scene := load("res://scenes/game/game_world.tscn") as PackedScene
	var net := root.get_node("Net")
	if mode == "host": _check(net.host_local_test(), "host failed")
	else:
		net.connected.connect(func() -> void: connected = true)
		_check(net.join_local_test(), "join failed")
		if not await _until(func() -> bool: return connected): quit(1); return
	world = world_scene.instantiate()
	world.prototype_round_duration = 600
	root.add_child(world)
	gas = world.gas_weapon
	gas._input_left = INF
	if mode == "host": await _host()
	elif mode == "human": await _human()
	else: await _observer()
	multiplayer_poll = false
	world.queue_free()
	await process_frame
	net.leave()
	for failure: String in failures: printerr("GAS NETWORK FAIL: " + failure)
	print("GAS NETWORK %s: %s" % [mode.to_upper(), "PASS" if failures.is_empty() else "FAIL"])
	quit(0 if failures.is_empty() else 1)

func _host() -> void:
	var bug: CharacterBody3D = world.players.get_node("1")
	bug.position = TARGET
	bug.velocity = Vector3.ZERO
	bug.set_physics_process(false)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(2, 2, 0.03)
	wall.add_child(shape)
	world.add_child(wall)
	wall.position = Vector3(6, 1, -11)
	_launch("human")
	_check(await _until(func() -> bool: return gas.get_state().spraying), "remote spray not accepted")
	await create_timer(0.7).timeout
	_check(int(world.combat.get_state(1).health) == 100, "gas damaged through wall")
	wall.position.x = 10
	_check(await _until(func() -> bool: return int(world.combat.get_state(1).health) <= 90), "gas never damaged exposed bug")
	_check(int(world.combat.get_state(1).health) >= 85, "gas damage was not gradual")
	_launch("observer")
	wall.position = Vector3(6, 1, -10.25)
	await create_timer(0.1).timeout
	var health: int = world.combat.get_state(1).health
	await create_timer(0.6).timeout
	_check(int(world.combat.get_state(1).health) == health, "clipped muzzle sprayed through thin wall")
	wall.free()
	bug.position = Vector3(6, 0.001, -16)
	await create_timer(0.1).timeout
	health = world.combat.get_state(1).health
	await create_timer(0.6).timeout
	_check(int(world.combat.get_state(1).health) == health, "gas exceeded three-metre range")
	bug.position = Vector3(8, 0.001, -12)
	await create_timer(0.7).timeout
	_check(int(world.combat.get_state(1).health) == health, "gas damaged outside cone")
	_check(await _until(func() -> bool: return float(gas.get_state().fuel) <= 0.001), "tank never depleted")
	await create_timer(0.6).timeout
	_check(float(gas.get_state().fuel) <= 0.001 and int(gas.get_state().carrier) > 0, "carried gun recharged")
	_check(await _until(func() -> bool: return int(gas.get_state().carrier) == 0), "remote docking failed")
	bug.position = TARGET
	world.combat.reset_round()
	var started := Time.get_ticks_msec()
	_check(await _until(func() -> bool: return int(gas.get_state().carrier) > 0, 16000), "refilled pickup missing")
	_check(Time.get_ticks_msec() - started >= 11000, "empty tank recharged too quickly")
	started = Time.get_ticks_msec()
	_check(await _until(func() -> bool: return world.combat.is_ghost(1)), "sustained gas never defeated bug")
	_check(Time.get_ticks_msec() - started >= 5000, "full-health defeat was too fast")
	started = Time.get_ticks_msec()
	_check(await _until(func() -> bool: return not world.combat.is_ghost(1), 14000), "ghost did not respawn")
	_check(Time.get_ticks_msec() - started >= 9600, "gas shortened ghost duration")
	await create_timer(0.3).timeout
	_check(bug.position.distance_to(world.home_base.global_position) < 0.3, "gas respawn missed pantry")
	for child: Dictionary in children:
		if not await _until(func() -> bool: return not OS.is_process_running(child.pid), 8000): OS.kill(child.pid); _check(false, "child timed out")
		var output := FileAccess.get_file_as_string(child.log)
		_check(output.contains("GAS NETWORK %s: PASS" % str(child.mode).to_upper()), "child PASS missing")
		_check(not output.contains("SCRIPT ERROR") and not output.contains("\nERROR:"), "child runtime error")
		if not failures.is_empty(): printerr(output)
		DirAccess.remove_absolute(child.log)
	await create_timer(0.3).timeout
	_check(int(gas.get_state().carrier) == 0, "disconnect stranded the gun")

func _human() -> void:
	var id := world.multiplayer.get_unique_id()
	if not await _until(func() -> bool: return world.players.has_node(str(id)) and world.get_role_for_peer(id) == "exterminator"):
		_check(false, "human spawn timeout"); return
	var token: CharacterBody3D = world.players.get_node(str(id))
	var dock: Vector3 = gas._station.get_node("Control").global_position - Vector3.UP
	token.position = dock
	token.velocity = Vector3.ZERO
	await create_timer(0.5).timeout
	_check(world.is_peer_ready(id), "client lost its own scene readiness")
	_check(gas.can_dock(id), "connected human cannot see the truck interaction prompt")
	gas.request_action("dock")
	_check(await _until(func() -> bool: return gas.is_selected(id)), "remote pickup rejected")
	_check(not token.shotgun.request_fire(), "gas trigger fired shotgun")
	token.position = SHOOTER
	token.velocity = Vector3.ZERO
	token.set_physics_process(false)
	await create_timer(0.5).timeout
	gas.request_action("shotgun")
	gas.request_action("dock")
	await create_timer(0.3).timeout
	_check(gas.is_selected(id) and not token.shotgun.request_fire(), "host allowed remote weapon swap away from truck")
	var aim := (TARGET + Vector3.UP * 0.01 - (SHOOTER + Vector3(0.13, 1.4, -0.19))).normalized()
	var deadline := Time.get_ticks_msec() + 12000
	while float(gas.get_state().fuel) > 0.001 and Time.get_ticks_msec() < deadline:
		gas.request_spray(true, aim)
		await create_timer(0.1).timeout
	gas.request_spray(false, aim)
	_check(float(gas.get_state().fuel) <= 0.001, "remote fuel did not empty")
	await create_timer(1.1).timeout
	token.position = dock
	token.velocity = Vector3.ZERO
	await create_timer(0.4).timeout
	gas.request_action("dock")
	_check(await _until(func() -> bool: return int(gas.get_state().carrier) == 0), "dock snapshot missing")
	_check(not gas.is_selected(id) and not token.shotgun._gas_selected(), "truck exchange did not restore remote shotgun")
	gas.request_spray(true, aim)
	await create_timer(3).timeout
	_check(not gas.get_state().spraying, "remote player fired returned gas gun")
	gas.request_action("dock")
	await create_timer(0.3).timeout
	_check(int(gas.get_state().carrier) == 0, "partial refill pickup accepted")
	_check(await _until(func() -> bool: return float(gas.get_state().fuel) >= 7.999, 13000), "refill never finished")
	gas.request_action("dock")
	_check(await _until(func() -> bool: return gas.is_selected(id)), "second pickup rejected")
	token.position = SHOOTER
	await create_timer(0.5).timeout
	deadline = Time.get_ticks_msec() + 10000
	while not world.combat.is_ghost(1) and Time.get_ticks_msec() < deadline:
		gas.request_spray(true, aim)
		await create_timer(0.1).timeout
	gas.request_spray(false, aim)
	_check(world.combat.is_ghost(1), "gas defeat did not replicate to shooter")
	_check(await _until(func() -> bool: return not world.combat.is_ghost(1), 14000), "respawn did not replicate to shooter")
	await create_timer(0.7).timeout

func _observer() -> void:
	var id := world.multiplayer.get_unique_id()
	_check(await _until(func() -> bool: return world.players.has_node(str(id)) and int(gas.get_state().carrier) > 0), "late join lost carrier")
	_check(float(gas.get_state().fuel) < 7.5, "late join reset fuel")
	_check(not gas._handle_spray(id, true, Vector3.FORWARD), "client assigned host spray state")
	gas._request_spray.rpc_id(1, true, Vector3.FORWARD)
	gas._request_action.rpc_id(1, "gas")
	await create_timer(0.3).timeout
	_check(int(gas.get_state().carrier) != id, "bug stole gas weapon")
	_check(await _until(func() -> bool: return int(gas.get_state().carrier) == 0), "observer missed docking")
	_check(await _until(func() -> bool: return int(gas.get_state().carrier) > 0, 16000), "observer missed refill pickup")
	_check(await _until(func() -> bool: return world.combat.is_ghost(1)), "observer missed gas defeat")
	_check(await _until(func() -> bool: return not world.combat.is_ghost(1), 14000), "observer missed respawn")
	await create_timer(0.5).timeout

func _launch(child_mode: String) -> void:
	var log_path := OS.get_temp_dir().path_join("gas-%s-%d.log" % [child_mode, Time.get_ticks_usec()])
	var pid := OS.create_process(OS.get_executable_path(), PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://scripts/tools/gas_weapon_network_test.gd", "--log-file", log_path, "--", "--gas-" + child_mode]) + root.get_node("Net").get_local_test_arguments())
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
