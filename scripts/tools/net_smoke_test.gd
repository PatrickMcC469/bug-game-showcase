extends SceneTree
## Headless check that the multiplayer skeleton works across two real processes.
## Run from the repo root:
##   godot --headless --path . --script res://scripts/tools/net_smoke_test.gd
##
## The parent hosts over ENet and launches this script again as a localhost
## client. Together they verify roster lifecycle, replicated spawns, camera
## authority, owner movement, host-owned roles/objective state, and clean
## disconnect behavior.
##
## Autoloads are fetched through /root rather than by their global names: under
## --script this file is compiled before the autoloads are registered, so
## naming them directly is a compile error.

const Layout := preload("res://scripts/game/diner_layout.gd")
const RoachScale := preload("res://scripts/game/roach_scale.gd")
const LateJoinGate := preload("res://scripts/tools/late_join_gate.gd")
const CLIENT_PROBE_ARGUMENT := "--client-probe"
const CONNECTION_TIMEOUT_MS := 16000
const PROCESS_TIMEOUT_MS := 24000
const PROBE_STARTUP_TIMEOUT_MS := 60000
const REQUIRED_ACTIONS: Array[String] = [
	"move_forward", "move_back", "move_left", "move_right", "sprint", "dash",
	"food_grab", "food_drop", "food_throw", "food_scent", "food_aim", "environment_interact",
]

var _client_connected := false
var _client_pid := -1
var _client_log_path := ""
var _client_gate_path := ""
var _failures: Array[String] = []
var _world_scene: PackedScene


func _initialize() -> void:
	if CLIENT_PROBE_ARGUMENT in OS.get_cmdline_user_args():
		_run_client.call_deferred()
	else:
		_run_host.call_deferred()


func _run_host() -> void:
	_world_scene = load("res://scenes/game/game_world.tscn") as PackedScene
	var net: Node = root.get_node_or_null("Net")
	var game_state: Node = root.get_node_or_null("GameState")
	if net == null or game_state == null:
		_failures.append("autoloads missing (Net=%s GameState=%s)" % [net, game_state])
		_finish_host(net, null)
		return

	# Explicit roach preferences on both peers exercise cooperative food actions
	# while proving the menu override remains host-authoritative.
	game_state.call("set_local_role_preference", "cockroach")
	_check_input_actions()
	if not net.host_local_test():
		_failures.append("Net.host_local_test() returned false")
		_finish_host(net, null)
		return
	if net.get_local_test_port() <= 0 or net.is_solo_test():
		_failures.append("local test host did not get an isolated port/session")

	if game_state.player_count() != 1 or not _roster_has(game_state, 1):
		_failures.append("host roster should initially contain only peer 1")

	var world: Node = _load_world()
	if world != null:
		await process_frame
		await process_frame
		var host_token: Node = _token_for(world, 1)
		if host_token == null:
			_failures.append("host token '1' was not spawned")
		else:
			_check_local_token(host_token)
			_check_role(host_token, "cockroach")
			await _check_owner_movement(host_token)
			host_token.global_position = world.serving_cart.get_interaction_position(1) + Vector3(0, 0.002, 0.06)
			host_token.velocity = Vector3.ZERO
			await create_timer(0.1).timeout
			world.serving_cart.request_move()
			# Join while the host is already hauling food, exercising the initial
			# FoodRun snapshot rather than only empty-round joins.
			host_token.global_position = world.food_run.get_food_records()[0]["pos"] + Vector3.UP * (0.1 * RoachScale.GEOMETRY)
			host_token.velocity = Vector3.ZERO
			await create_timer(0.25).timeout
			world.food_run.request_action("grab", 0)
			# Existing model-rotation replication must also deliver the slope
			# pose to a late joiner, with its local collision matching the art.
			host_token.global_position = Layout.point(Vector3(-6, 1.4, -5.85)) + Vector3.UP * 10.0
			host_token.velocity = Vector3.ZERO
			await create_timer(0.4).timeout

	if _failures.is_empty() and world != null:
		await _check_two_peer_session(net, game_state, world)

	if world != null and _failures.is_empty():
		await _check_expiry_and_reset(world)
	_finish_host(net, world)


func _run_client() -> void:
	_world_scene = load("res://scenes/game/game_world.tscn") as PackedScene
	if not await LateJoinGate.wait_for_release(self):
		printerr("CLIENT PROBE FAIL: host did not release the prepared client")
		quit(1)
		return
	var net: Node = root.get_node_or_null("Net")
	var game_state: Node = root.get_node_or_null("GameState")
	if net == null or game_state == null:
		_failures.append("client autoloads missing (Net=%s GameState=%s)" % [net, game_state])
		_finish_client(net, null)
		return

	game_state.call("set_local_role_preference", "cockroach")
	net.connected.connect(func() -> void: _client_connected = true)
	net.connection_failed.connect(
		func(reason: String) -> void: _failures.append("client connection failed: %s" % reason))

	if not net.join_local_test():
		_failures.append("client Net.join_local_test() returned false")

	if not await _wait_until(func() -> bool: return _client_connected, CONNECTION_TIMEOUT_MS):
		_failures.append("client did not connect before timeout")

	var world: Node = null
	if _failures.is_empty():
		world = _load_world()
	if world != null:
		await process_frame
		await process_frame
		var own_id: int = net.get_multiplayer().get_unique_id()
		if not await _wait_until(
			func() -> bool: return game_state.player_count() == 2,
			CONNECTION_TIMEOUT_MS,
		):
			_failures.append("client roster did not reach two peers")
		elif not _roster_has(game_state, 1) or not _roster_has(game_state, own_id):
			_failures.append("client roster is missing the host or local peer")

		if not await _wait_until(
			func() -> bool: return _token_for(world, 1) != null and _token_for(world, own_id) != null,
			CONNECTION_TIMEOUT_MS,
		):
			_failures.append("client did not receive both player tokens")
		else:
			var host_token: Node = _token_for(world, 1)
			var own_token: Node = _token_for(world, own_id)
			if not await _wait_until(
				func() -> bool:
					return (
						world.call("get_match_phase") == 1
						and world.call("get_role_for_peer", 1) == "cockroach"
						and world.call("get_role_for_peer", own_id) == "cockroach"
					),
				CONNECTION_TIMEOUT_MS,
			):
				_failures.append("client did not receive the running match and role snapshot")
			_check_local_token(own_token)
			_check_remote_camera(host_token)
			_check_role(host_token, "cockroach")
			_check_role(own_token, "cockroach")
			# A preloaded join can receive all snapshots in one process frame.
			# Let Jolt register the spawned body and role-specific shapes before
			# teleporting the probe beside the cart.
			await physics_frame
			await physics_frame
			var ramp_normal := Vector3(0, 5.5, 2.399).normalized()
			if not await _wait_until(
				func() -> bool: return host_token.cockroach_model.basis.y.normalized().dot(ramp_normal) > 0.999,
				CONNECTION_TIMEOUT_MS,
			):
				_failures.append("late join lost the host's supporting slope pose")
			if absf(host_token.roach_collision.basis.y.normalized().dot(ramp_normal)) > 0.001:
				_failures.append("remote capsule did not follow the replicated slope pose")
			if not await _wait_until(func() -> bool: return world.is_peer_carrying_food(1), CONNECTION_TIMEOUT_MS):
				_failures.append("late join lost the host's existing cargo")
			if not await _wait_until(func() -> bool: return world.serving_cart.get_state()["target_z"] > 5.0 * Layout.SCALE, CONNECTION_TIMEOUT_MS):
				_failures.append("late join lost the cart's destination")
			if not await _wait_until(func() -> bool: return not world.serving_cart.is_moving(), CONNECTION_TIMEOUT_MS):
				_failures.append("replicated cart did not reach the dish dock")
			own_token.global_position = world.serving_cart.get_interaction_position(own_id) + Vector3(0, 0.002, 0.06)
			own_token.velocity = Vector3.ZERO
			await create_timer(0.35).timeout
			world.serving_cart.request_move()
			if not await _wait_until(func() -> bool: return world.serving_cart.get_state()["target_z"] < 0.0, CONNECTION_TIMEOUT_MS):
				_failures.append("client cart request did not receive host acceptance")
			own_token.global_position = Vector3(0, 0.03, 0)
			own_token.velocity = Vector3.ZERO
			await _check_owner_movement(own_token, false)
			# This request travels client -> host -> snapshot. It must not rely on
			# the host executing the pickup locally.
			var remote_food := world.get_node("Objectives/FoodItems/Food12") as Node3D
			own_token.global_position = remote_food.global_position + Vector3.UP * (0.1 * RoachScale.GEOMETRY)
			own_token.velocity = Vector3.ZERO
			await create_timer(0.35).timeout
			world.get_node("FoodRun").request_action("grab", 11)
			if not await _wait_until(func() -> bool: return world.is_peer_carrying_food(own_id), CONNECTION_TIMEOUT_MS):
				_failures.append("client grab did not receive host-owned cargo")
			if not await _wait_until(
				func() -> bool: return world.call("get_match_phase") == 2,
				CONNECTION_TIMEOUT_MS,
			):
				_failures.append("client did not receive the cockroach win snapshot")
			# Leave enough time for the final owner position to reach the host.
			await create_timer(0.4).timeout

	_finish_client(net, world)


func _check_two_peer_session(net: Node, game_state: Node, world: Node) -> void:
	_client_log_path = OS.get_temp_dir().path_join(
		"bug-game-client-smoke-%d-%d.log" % [OS.get_process_id(), Time.get_ticks_usec()])
	_client_gate_path = _client_log_path + ".gate"
	var arguments := PackedStringArray([
		"--headless",
		"--log-file", _client_log_path,
		"--path", ProjectSettings.globalize_path("res://"),
		"--script", ProjectSettings.globalize_path("res://scripts/tools/net_smoke_test.gd"),
		"--", CLIENT_PROBE_ARGUMENT, LateJoinGate.ARGUMENT_PREFIX + _client_gate_path,
	])
	_client_pid = OS.create_process(OS.get_executable_path(), arguments + net.get_local_test_arguments())
	if _client_pid <= 0:
		_failures.append("could not launch the localhost client probe")
		return
	if not await _wait_until(func() -> bool: return LateJoinGate.is_ready(_client_gate_path), PROBE_STARTUP_TIMEOUT_MS):
		_failures.append("client probe did not finish preparing its assets")
		OS.kill(_client_pid)
		await _finish_client_process()
		return
	if not LateJoinGate.release(_client_gate_path):
		_failures.append("could not release the prepared client probe")
		OS.kill(_client_pid)
		await _finish_client_process()
		return

	if not await _wait_until(
		func() -> bool: return game_state.player_count() == 2,
		CONNECTION_TIMEOUT_MS,
	):
		_failures.append("host roster did not reach two peers")
		await _finish_client_process()
		return

	var client_id := _find_client_id(game_state)
	if client_id <= 1:
		_failures.append("host roster did not expose a valid client peer ID")
	else:
		if not await _wait_until(
			func() -> bool: return _token_for(world, client_id) != null,
			CONNECTION_TIMEOUT_MS,
		):
			_failures.append("host did not spawn the client token")
		else:
			var client_token: Node = _token_for(world, client_id)
			_check_remote_camera(client_token)
			if not await _wait_until(
				func() -> bool:
					return (
						world.call("get_match_phase") == 1
						and world.call("get_role_for_peer", 1) == "cockroach"
						and world.call("get_role_for_peer", client_id) == "cockroach"
					),
				CONNECTION_TIMEOUT_MS,
			):
				_failures.append("host did not apply the cooperative role preferences")
			var start_position: Vector3 = client_token.position
			if not await _wait_until(
				func() -> bool: return is_instance_valid(client_token) and client_token.position.distance_to(start_position) > 0.25 * RoachScale.MOVEMENT,
				CONNECTION_TIMEOUT_MS,
			):
				_failures.append("client-owned movement did not replicate to the host")
			if not await _wait_until(func() -> bool: return world.is_peer_carrying_food(client_id), CONNECTION_TIMEOUT_MS):
				_failures.append("client food request never reached the host")
			var host_token := _token_for(world, 1) as CharacterBody3D
			if host_token == null:
				_failures.append("host cockroach token disappeared during the session")
			else:
				await _check_food_delivery(world, host_token, 1)
			if not await _wait_until(
				func() -> bool:
					return (
						world.call("get_match_phase") == 2
						and world.call("get_food_delivered") == world.call("get_food_quota")
					),
				CONNECTION_TIMEOUT_MS,
			):
				_failures.append("host did not finish the round after the food quota")

	await _finish_client_process()
	if not await _wait_until(
		func() -> bool:
			return game_state.player_count() == 1 and _token_for(world, client_id) == null,
		CONNECTION_TIMEOUT_MS,
	):
		_failures.append("client roster/token were not removed after disconnect")


func _finish_client_process() -> void:
	if _client_pid <= 0:
		return
	if not await _wait_until(
		func() -> bool: return not OS.is_process_running(_client_pid),
		PROCESS_TIMEOUT_MS,
	):
		_failures.append("client probe process did not exit before timeout")
		OS.kill(_client_pid)
		await create_timer(0.1).timeout
	else:
		var exit_code := OS.get_process_exit_code(_client_pid)
		if exit_code != 0:
			_failures.append("client probe exited with code %d" % exit_code)

	if FileAccess.file_exists(_client_log_path):
		if not _failures.is_empty():
			printerr("CLIENT PROBE LOG:\n%s" % FileAccess.get_file_as_string(_client_log_path))
		DirAccess.remove_absolute(_client_log_path)
	LateJoinGate.cleanup(_client_gate_path)
	_client_pid = -1


func _load_world() -> Node:
	if _world_scene == null:
		_failures.append("game_world.tscn failed to load")
		return null
	var world: Node = _world_scene.instantiate()
	world.set("prototype_food_quota", 6)
	root.add_child(world)
	preload("res://scripts/tools/diner_test_slope.gd").add_to(world)
	return world


func _token_for(world: Node, peer_id: int) -> Node:
	if world == null:
		return null
	var players: Node = world.get_node_or_null("Players")
	return players.get_node_or_null(str(peer_id)) if players != null else null


func _roster_has(game_state: Node, peer_id: int) -> bool:
	var roster: Dictionary = game_state.get("players")
	return roster.has(peer_id)


func _find_client_id(game_state: Node) -> int:
	var roster: Dictionary = game_state.get("players")
	for peer_id: Variant in roster:
		var id := int(peer_id)
		if id != 1:
			return id
	return 0


func _check_input_actions() -> void:
	for action: String in REQUIRED_ACTIONS:
		if not InputMap.has_action(action):
			_failures.append("input action '%s' is not defined" % action)


## The 3D-specific wiring that is easy to break and silent when it does: if the
## local player's camera stops being current you render from nowhere, and if a
## remote player's camera becomes current you render from a stranger.
func _check_local_token(token: Node) -> void:
	if not (token is CharacterBody3D):
		_failures.append("player token is %s, expected CharacterBody3D" % token.get_class())
		return

	var camera: Camera3D = token.get_node_or_null("CameraRig/SpringArm/Camera")
	if camera == null:
		_failures.append("player camera missing at CameraRig/SpringArm/Camera")
	elif not camera.current:
		_failures.append("local player's camera is not current")

	if token.get_node_or_null("Sync") == null:
		_failures.append("MultiplayerSynchronizer missing — position will not replicate")

	if token.get_node_or_null("CockroachModel") == null:
		_failures.append("cockroach model missing from player token")


func _check_remote_camera(token: Node) -> void:
	var camera: Camera3D = token.get_node_or_null("CameraRig/SpringArm/Camera")
	if camera == null:
		_failures.append("remote player camera is missing")
	elif camera.current:
		_failures.append("remote player camera became current")


func _check_role(token: Node, expected_role: String) -> void:
	if str(token.get("player_role")) != expected_role:
		_failures.append(
			"token %s role was '%s', expected '%s'" % [
				token.name, token.get("player_role"), expected_role,
			]
		)
	var roach_model := token.get_node_or_null("CockroachModel") as Node3D
	var exterminator_model := token.get_node_or_null("ExterminatorModel") as Node3D
	if roach_model == null or exterminator_model == null:
		_failures.append("token %s is missing a role model" % token.name)
	elif expected_role == "exterminator":
		if roach_model.visible or not exterminator_model.visible:
			_failures.append("token %s did not switch to exterminator visuals" % token.name)
	elif not roach_model.visible or exterminator_model.visible:
		_failures.append("token %s did not switch to cockroach visuals" % token.name)


## A tiny owner-input exercise catches broken action names and controllers that
## still instantiate correctly but no longer move once the scene is running.
func _check_owner_movement(token: CharacterBody3D, check_dash: bool = true) -> void:
	var walk_start := token.position
	Input.action_press("move_forward")
	for frame: int in 12:
		await physics_frame
	Input.action_release("move_forward")
	if token.position.distance_to(walk_start) < 0.25 * RoachScale.MOVEMENT:
		_failures.append("cockroach did not move from owner input")

	if not check_dash:
		return
	for frame: int in 12:
		await physics_frame
	var dash_start := token.position
	Input.action_press("dash")
	await physics_frame
	Input.action_release("dash")
	for frame: int in 8:
		await physics_frame
	if token.position.distance_to(dash_start) < 0.4 * RoachScale.MOVEMENT:
		_failures.append("cockroach dash did not produce a movement burst")


func _check_food_delivery(world: Node, token: CharacterBody3D, peer_id: int) -> void:
	var run: Node = world.food_run
	for index: int in 3:
		if index not in run.get_cargo_ids(peer_id):
			var records: Array = run.get_food_records()
			token.global_position = records[index].pos + Vector3.UP * 0.002
			token.velocity = Vector3.ZERO
			await create_timer(0.25).timeout
			run.request_action("grab", index)
			if not await _wait_until(func() -> bool: return run.get_cargo_ids(peer_id).size() == 1, CONNECTION_TIMEOUT_MS):
				_failures.append("host could not pick up one snack")
				return
		token.global_position = world.home_base.global_position + Vector3.UP * 0.002
		token.velocity = Vector3.ZERO
		if not await _wait_until(func() -> bool: return run.get_cargo_ids(peer_id).is_empty(), CONNECTION_TIMEOUT_MS):
			_failures.append("single-item pantry delivery failed")
	if world.get_match_phase() != 2: _failures.append("three individual deliveries did not meet quota")
	for index: int in 3:
		if run.get_food_records()[index].state != 3: _failures.append("delivered food was not banked")

func _check_expiry_and_reset(world: Node) -> void:
	world.prototype_round_duration = 0.03
	world._start_round()
	if not await _wait_until(func() -> bool: return world.get_match_phase() == 3, CONNECTION_TIMEOUT_MS):
		_failures.append("round did not end when the host clock expired")
	world.food_run.request_action("grab", 0)
	if world.is_peer_carrying_food(1) or world.get_food_delivered() != 0:
		_failures.append("expiry allowed inventory or score changes")
	world._reset_to_waiting()
	for food: Dictionary in world.food_run.get_food_records():
		if food["state"] != 0 or food["carrier"] != 0:
			_failures.append("waiting reset leaked food ownership or banked state")


func _wait_until(check: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if check.call():
			return true
		await create_timer(0.05).timeout
	return check.call()


func _finish_client(net: Node, world: Node) -> void:
	# No more RPC dispatch once teardown begins: the host can still send cart
	# motion during the frame between freeing GameWorld and closing the peer.
	multiplayer_poll = false
	if world != null:
		world.queue_free()
		await process_frame
	if net != null:
		net.leave()
		if net.get_local_test_port() != 0:
			_failures.append("client retained the local test port after leaving")
	if _failures.is_empty():
		print("CLIENT PROBE: PASS")
	else:
		for failure: String in _failures:
			printerr("CLIENT PROBE FAIL: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _finish_host(net: Node, world: Node) -> void:
	if world != null:
		world.queue_free()
		# Finish destroying authority-aware gameplay nodes before removing the
		# MultiplayerPeer they consult from their physics callbacks.
		await process_frame
	if net != null:
		net.leave()
		if net.get_local_test_port() != 0:
			_failures.append("host retained the local test port after leaving")

	if _failures.is_empty():
		print("SMOKE TEST: PASS")
	else:
		for failure: String in _failures:
			printerr("SMOKE TEST FAIL: %s" % failure)
	quit(0 if _failures.is_empty() else 1)
