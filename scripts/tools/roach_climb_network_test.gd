extends SceneTree
## A client joins a climbing host, then climbs itself while the host observes.
const LateJoinGate := preload("res://scripts/tools/late_join_gate.gd")
var failures: Array[String] = []
var connected := false
var child_pid := -1
var child_log := ""
var child_gate := ""
var probe: PoseProbe

class PoseProbe extends Node:
	var client_observed_wall := false

	@rpc("any_peer", "call_remote", "reliable")
	func confirm_wall_pose() -> void:
		if multiplayer.is_server() and multiplayer.get_remote_sender_id() > 1:
			client_observed_wall = true

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var client := "--climb-client" in OS.get_cmdline_user_args()
	var world_scene := load("res://scenes/game/game_world.tscn") as PackedScene
	if not await LateJoinGate.wait_for_release(self):
		printerr("CLIMB NETWORK FAIL: late-join readiness timed out")
		quit(1)
		return
	probe = PoseProbe.new()
	probe.name = "ClimbTestProbe"
	root.add_child(probe)
	var net := root.get_node("Net")
	root.get_node("GameState").set_local_role_preference("cockroach")
	if client:
		net.connected.connect(func() -> void: connected = true)
		_check(net.join_local_test(), "join failed")
		_check(await _until(func() -> bool: return connected), "connection timeout")
	else: _check(net.host_local_test(), "host failed")
	if not failures.is_empty():
		net.leave()
		quit(1)
		return
	var world := world_scene.instantiate() as Node3D
	world.prototype_round_duration = 90
	root.add_child(world)
	if client: await _client(world, net)
	else: await _host(world)
	multiplayer_poll = false
	world.queue_free()
	await process_frame
	net.leave()
	for failure: String in failures: printerr("CLIMB NETWORK FAIL: " + failure)
	print("ROACH CLIMB %s: %s" % ["CLIENT" if client else "HOST", "PASS" if failures.is_empty() else "FAIL"])
	quit(0 if failures.is_empty() else 1)

func _host(world: Node3D) -> void:
	var own := world.players.get_node("1") as CharacterBody3D
	var spot := world.get_node("DinerKitchen/ClimbSpots/PantryShelf")
	own.position = spot.endpoint(false)
	child_log = OS.get_temp_dir().path_join("bug-climb-client-%d-%d.log" % [OS.get_process_id(),Time.get_ticks_usec()])
	child_gate = child_log + ".gate"
	child_pid = OS.create_process(OS.get_executable_path(), PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://scripts/tools/roach_climb_network_test.gd", "--log-file", child_log, "--", "--climb-client", LateJoinGate.ARGUMENT_PREFIX + child_gate]) + root.get_node("Net").get_local_test_arguments())
	_check(child_pid > 0, "client launch failed")
	_check(await _until(func() -> bool: return LateJoinGate.is_ready(child_gate),30000), "client assets did not become ready")
	await create_timer(0.4).timeout
	_check(own.climber.request_climb(), "host climb rejected")
	_check(await _until(func() -> bool: return own.position.y > 0.15 and absf(own.cockroach_model.basis.orthonormalized().y.y) < 0.2), "host never reached wall pose")
	# Hold a real mid-climb pose while the late joiner loads. A fixed sleep made
	# this assertion depend on shader/import/startup speed rather than Sync.
	own.set_physics_process(false)
	_check(LateJoinGate.release(child_gate), "could not release late client join")
	_check(await _until(func() -> bool: return world.players.get_child_count() == 2), "client token missing")
	_check(await _until(func() -> bool: return probe.client_observed_wall), "client did not acknowledge host wall pose")
	own.set_physics_process(true)
	var remote: CharacterBody3D
	for token: Node in world.players.get_children():
		if token.name != &"1": remote = token
	if remote != null:
		_check(await _until(func() -> bool: return remote.position.y > 0.2 and absf(remote.cockroach_model.basis.orthonormalized().y.y) < 0.2), "client vertical climb/pose did not replicate")
		_check(not remote.climber.request_climb(), "host could drive client climb")
		_check(await _until(func() -> bool: return remote.position.y > 0.94 and remote.position.z < 0.45), "client landing did not replicate")
		_check(await _until(func() -> bool: return remote.position.y < 0.02 and remote.position.x < -4), "client descent did not replicate")
		_check(await _until(func() -> bool: return absf(remote.position.x + 1.575) < 0.1 and remote.position.y > 0.06 and absf(remote.cockroach_model.basis.orthonormalized().y.y) < 0.2), "automatic surface crawl did not replicate")
		_check(not remote.surface_crawler.step(0.016), "host could drive client surface crawl")
		_check(await _until(func() -> bool: return absf(remote.position.x + 1.575) < 0.1 and remote.position.y > 0.49 and remote.position.z < 3.48), "automatic box-top landing did not replicate")
	_check(await _until(func() -> bool: return not OS.is_process_running(child_pid), 15000), "client did not finish")
	if OS.is_process_running(child_pid): OS.kill(child_pid)
	else: _check(OS.get_process_exit_code(child_pid) == 0, "client failed")
	if FileAccess.file_exists(child_log):
		var output := FileAccess.get_file_as_string(child_log)
		_check(output.contains("ROACH CLIMB CLIENT: PASS") and not output.contains("SCRIPT ERROR") and not output.contains("ERROR:"), "client log failed")
		if not failures.is_empty(): printerr(output)
		DirAccess.remove_absolute(child_log)
	LateJoinGate.cleanup(child_gate)

func _client(world: Node3D, net: Node) -> void:
	var id: int = net.get_multiplayer().get_unique_id()
	var path := "Players/%d" % id
	if not await _until(func() -> bool: return world.has_node(path) and world.has_node("Players/1") and world.get_role_for_peer(id) == "cockroach"):
		_check(false, "client roles or tokens missing")
		return
	var own := world.get_node(path) as CharacterBody3D
	var remote := world.players.get_node("1") as CharacterBody3D
	_check(own.camera.current and not remote.camera.current, "camera ownership changed")
	_check(await _until(func() -> bool: return remote.position.y > 0.1 and absf(remote.cockroach_model.basis.orthonormalized().y.y) < 0.2), "late join missed host wall pose")
	# The rotation snapshot is applied before the remote token's next presenter
	# frame derives its capsule. Allow that update rather than checking mid-frame.
	_check(await _until(func() -> bool: return absf(remote.cockroach_model.basis.orthonormalized().y.y) < 0.2 and absf(remote.roach_collision.basis.y.dot(remote.cockroach_model.basis.orthonormalized().y)) < 0.01), "remote capsule and wall pose disagree")
	probe.confirm_wall_pose.rpc_id(1)
	_check(not remote.climber.request_climb(), "client could drive host climb")
	_check(await _until(func() -> bool: return remote.position.y > 1.95 and remote.position.z < -5), "late join missed host landing")
	var spot := world.get_node("DinerKitchen/ClimbSpots/PrepBench")
	own.position = spot.endpoint(false)
	own.velocity = Vector3.ZERO
	await create_timer(0.4).timeout
	_check(own.climber.request_climb(), "client climb rejected")
	_check(await _until(func() -> bool: return not own.climber.active), "client climb timeout")
	_check(own.position.distance_to(spot.endpoint(true)) < 0.03, "client did not reach platform")
	await create_timer(0.5).timeout
	_check(own.climber.request_climb(), "client descent rejected")
	_check(await _until(func() -> bool: return not own.climber.active), "client descent timeout")
	_check(own.position.distance_to(spot.endpoint(false)) < 0.03, "client did not reach floor")
	await create_timer(0.6).timeout
	# No authored climb spot: only this peer's normal WASD reaches the carton.
	own.respawn_from_combat(Vector3(-1.575, 0.002, 3.68))
	own.camera_rig.rotation.y = 0
	await create_timer(0.4).timeout
	Input.action_press("move_forward")
	_check(await _until(func() -> bool: return own.surface_crawler.active and own.position.y > 0.1), "client surface attachment failed")
	Input.action_release("move_forward")
	await create_timer(0.6).timeout
	Input.action_press("move_forward")
	_check(await _until(func() -> bool: return own.position.y > 0.49 and own.position.z < 3.48), "client failed to crawl onto carton")
	Input.action_release("move_forward")
	await create_timer(0.6).timeout

func _until(predicate: Callable, timeout: int = 12000) -> bool:
	var end := Time.get_ticks_msec() + timeout
	while Time.get_ticks_msec() < end:
		if predicate.call(): return true
		await process_frame
	return predicate.call()

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
