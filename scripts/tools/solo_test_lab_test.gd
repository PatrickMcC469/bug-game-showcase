extends SceneTree
## Exercise the real lab and its real background client, including scene teardown.
var failures: Array[String] = []
var lab: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var net := root.get_node("Net")
	var state := root.get_node("GameState")
	state.set_local_role_preference("exterminator")
	lab = load("res://scenes/game/solo_test.tscn").instantiate()
	root.add_child(lab)
	current_scene = lab
	if not await _until(func() -> bool: return lab.session_ready or not lab.error_message.is_empty(), 35000):
		_check(false, "lab connection timed out")
	elif not lab.error_message.is_empty():
		_check(false, lab.error_message)
	else:
		await _exercise()
	var child_pid: int = lab.bot_pid
	var child_log: String = lab.bot_log_path
	var stop_results: Array = []
	lab.tree_exited.connect(func() -> void: stop_results.append(lab.opponent_stop_error))
	lab.leave_lab()
	await process_frame
	await process_frame
	_check(not net.is_solo_test() and state.player_count() == 0, "lab session leaked into menu")
	_check(state.get_local_role_preference() == "exterminator", "lab lost the menu role preference")
	_check(child_pid <= 0 or stop_results == [OK], "leaving the lab did not close its opponent process")
	_check(current_scene != null and current_scene.has_node("Margin/Layout/SoloTestButton"), "developer entry is missing from menu")
	if not child_log.is_empty() and FileAccess.file_exists(child_log):
		var output := FileAccess.get_file_as_string(child_log)
		_check(not output.contains("SCRIPT ERROR") and not output.contains("\nERROR:"), "background client reported an error: " + output)
	# Public development controls must be inert in an ordinary multiplayer session.
	var menu := current_scene
	current_scene = null
	menu.queue_free()
	await process_frame
	await process_frame
	_check(net.host_local_test(), "normal host failed after lab teardown")
	var world := load("res://scenes/game/game_world.tscn").instantiate() as Node3D
	root.add_child(world)
	_check(not world.prepare_solo_round({1: "cockroach"}), "normal match accepted lab role/reset controls")
	world.set_solo_clock_paused(true)
	_check(not world.is_round_clock_paused(), "normal match accepted clock hold")
	multiplayer_poll = false
	world.queue_free()
	await process_frame
	await process_frame
	net.leave()
	for failure: String in failures:
		printerr("SOLO LAB FAIL: " + failure)
	print("SOLO LAB TEST: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _exercise() -> void:
	var world: Node3D = lab.world
	var own := world.players.get_node("1") as CharacterBody3D
	var other := world.players.get_node(str(lab.bot_peer_id)) as CharacterBody3D
	_check(world.players.get_child_count() == 2, "lab did not spawn two real peers")
	_check(own.is_multiplayer_authority() and not other.is_multiplayer_authority(), "opponent authority is not its client")
	_check(own.camera.current and not other.camera.current, "remote opponent took the player's camera")
	_check(own.player_role == "cockroach" and other.player_role == "exterminator", "escape roles are wrong")
	lab.toggle_bot()
	await create_timer(0.35).timeout
	_check(_clear_body(own) and _clear_body(other), "escape spawn intersects scenery")
	var frozen: float = world.get_round_time_left()
	await create_timer(0.4).timeout
	_check(is_equal_approx(frozen, world.get_round_time_left()), "held round clock advanced")
	_check(other.shotgun.shot_serial == 0, "paused opponent fired")
	lab.toggle_clock()
	await create_timer(0.4).timeout
	_check(world.get_round_time_left() < frozen - 0.2, "running round clock did not advance")
	lab.toggle_clock()
	var before: float = world.get_round_time_left()
	lab.add_time()
	_check(is_equal_approx(world.get_round_time_left(), before + 30), "add-time control failed")
	world.add_solo_time(-1000)
	_check(world.get_match_phase() == 3, "timer expiry did not end the round")
	await _reset()
	_check(world.get_match_phase() == 1 and is_equal_approx(world.get_round_time_left(), 120), "result did not reset to a fresh held round")
	# Standing in the open must actually be dangerous; a decorative shot would
	# make the escape drill pass even if cover and aiming were broken.
	lab.toggle_bot()
	_check(await _until(func() -> bool: return int(world.combat.get_state(1).health) < 100, 5000), "scripted shot did not damage the exposed player")
	lab.toggle_bot()
	await _reset()
	await create_timer(1.1).timeout
	# A defeated carrier must be cleared before the scenario position is applied.
	own.position = world.food_run.get_food_records()[0].pos + Vector3.UP * 0.003
	own.velocity = Vector3.ZERO
	await create_timer(0.3).timeout
	world.food_run.request_action("grab", 0)
	_check(world.is_peer_carrying_food(1), "could not set up a carried snack")
	_check(world.combat.kill_from_environment(1), "could not set up ghost reset")
	await create_timer(0.1).timeout
	await _reset()
	await create_timer(0.3).timeout
	var setup: Dictionary = lab.get_scenario_setup()
	_check(own.position.distance_to(setup.host_position) < 0.04, "ghost reset was overwritten by the old home respawn")
	_check(not world.combat.is_ghost(1) and own.vitals.health == 100, "reset did not restore the living player")
	_check(not world.is_peer_carrying_food(1) and world.get_food_delivered() == 0, "reset retained cargo or score")
	# The authored escape must be traversable with ordinary input and solid cover.
	lab.toggle_bot()
	Input.action_press("move_forward")
	_check(await _until(func() -> bool: return own.position.x < -8.06, 2500), "roach could not enter the wall vent")
	Input.action_release("move_forward")
	_check(await _until(func() -> bool: return other.shotgun.shot_serial > lab._shot_at_start, 5000), "scripted client never fired its approved shot")
	_check(own.vitals.health == 100, "vent did not protect the escaped roach")
	# Switching scenarios changes roles on the same two peer identities.
	lab.select_scenario(1)
	_check(await _until(func() -> bool: return lab.session_ready), "moving-target setup timed out")
	await create_timer(0.35).timeout
	_check(own.player_role == "exterminator" and other.player_role == "cockroach", "scenario role swap failed")
	_check(_clear_body(own) and _clear_body(other), "moving-target spawn intersects scenery")
	var start := other.position
	await create_timer(0.5).timeout
	_check(other.position.distance_to(start) > 0.15, "scripted roach did not replicate its walking")
	lab.toggle_bot()
	await create_timer(0.35).timeout
	start = other.position
	await create_timer(0.4).timeout
	_check(other.position.distance_to(start) < 0.02, "pausing the bot left movement input held")
	# Reset while the shooter is tumbling and its target is a ghost.
	own.camera.look_at(other.global_position + Vector3.UP * 0.011)
	_check(own.shotgun.request_fire(), "test shooter could not fire")
	_check(own.shotgun.recoil_phase != 0, "shot did not enter recoil")
	world.combat.kill_from_environment(lab.bot_peer_id)
	await _reset()
	await create_timer(0.4).timeout
	setup = lab.get_scenario_setup()
	_check(own.shotgun.recoil_phase == 0 and own.velocity.length() < 0.05, "reset retained recoil or movement")
	_check(other.position.distance_to(setup.bot_position) < 0.04, "client reset position did not replicate")
	_check(not world.combat.is_ghost(lab.bot_peer_id), "reset retained the ghost target")
	# The moving target also returns to its route after the normal ghost lifetime.
	await create_timer(0.8).timeout
	lab.toggle_bot()
	_check(world.combat.kill_from_environment(lab.bot_peer_id), "could not defeat the moving target")
	_check(await _until(func() -> bool: return not world.combat.is_ghost(lab.bot_peer_id), 12000), "normal ghost respawn failed")
	_check(await _until(func() -> bool: return other.position.distance_to(setup.bot_position) < 1.0, 3000), "respawned target did not return to practice route")
	_check(own.camera.current and not other.camera.current, "role switch changed camera ownership")


func _reset() -> void:
	lab.reset_scenario()
	_check(await _until(func() -> bool: return lab.session_ready), "scenario reset acknowledgement timed out")


func _clear_body(token: CharacterBody3D) -> bool:
	var collision: CollisionShape3D = token.roach_collision if token.player_role == "cockroach" else token.exterminator_collision
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	query.transform = collision.global_transform
	# Jolt permits submillimeter resting penetration; this checks scenery
	# clearance rather than mistaking ordinary floor contact for a blocked spawn.
	query.transform.origin.y += 0.005
	query.exclude = [token.get_rid()]
	query.collision_mask = token.collision_mask
	var hits := token.get_world_3d().direct_space_state.intersect_shape(query, 4)
	if not hits.is_empty():
		printerr("SOLO LAB overlap at ", token.position, ": ", hits)
		for hit: Dictionary in hits:
			printerr("COLLIDER POSITION: ", hit.collider.global_position)
	return hits.is_empty()


func _until(check: Callable, timeout_ms: int = 10000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if check.call():
			return true
		await process_frame
	return check.call()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
