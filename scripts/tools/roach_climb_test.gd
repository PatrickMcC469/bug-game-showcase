extends SceneTree
var failures: Array[String] = []
var world: Node3D
var token: CharacterBody3D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.get_node("GameState").set_local_role_preference("cockroach")
	var net := root.get_node("Net")
	if not net.host_local_test():
		quit(1)
		return
	world = load("res://scenes/game/game_world.tscn").instantiate()
	world.prototype_round_duration = 600
	root.add_child(world)
	await _frames(10)
	token = world.players.get_node("1")
	var spots := world.get_node("DinerKitchen/ClimbSpots").get_children()
	for spot: Node in spots:
		await _at(spot.endpoint(false))
		_check(token.climber.request_climb(), "cannot start " + str(spot.name))
		await _finish_climb()
		_check(token.position.distance_to(spot.endpoint(true)) < 0.025, "did not reach " + str(spot.name) + ": " + str(token.position))
		_check(token.camera_rig.global_basis.y.dot(Vector3.UP) > 0.999, "camera rolled during " + str(spot.name))
		await _frames(22)
		_check(token.climber.request_climb(), "cannot descend " + str(spot.name))
		await _finish_climb()
		_check(token.position.distance_to(spot.endpoint(false)) < 0.03, "descent did not reach floor: " + str(spot.name))
	# The human role cannot activate routes, even standing exactly on a mark.
	world._assign_role(1, "exterminator")
	world._apply_roles_to_tokens()
	await _at(spots[0].endpoint(false))
	_check(not token.climber.request_climb(), "human could climb")
	world._assign_role(1, "cockroach")
	world._apply_roles_to_tokens()
	# Block the arrival pad: startup must reject it rather than clipping through.
	await _at(spots[0].endpoint(false))
	var obstacle := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.2, 0.2, 0.2)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	obstacle.add_child(collision)
	world.add_child(obstacle)
	obstacle.position = spots[0].endpoint(true) + Vector3.UP * 0.08
	await _frames(3)
	_check(not token.climber.request_climb(), "blocked landing accepted")
	obstacle.free()
	await _frames(3)
	# Carried food uses its real host-owned stack and clearance during climbing.
	for index: int in 3:
		await _at(world.food_run.get_food_records()[index].pos)
		world.food_run.request_action("grab", index)
		await _frames(18)
	_check(token.cargo_count == 3, "could not prepare full stack")
	await _at(spots[0].endpoint(false))
	_check(token.climber.request_climb(), "full stack could not start clear route")
	await _finish_climb()
	_check(token.position.distance_to(spots[0].endpoint(true)) < 0.03, "full stack failed to arrive")
	_check(token.cargo_count == 3, "climbing unexpectedly lost the full food stack")
	# Letting go must return to ordinary gravity rather than hanging in the air.
	await _at(spots[0].endpoint(false))
	_check(token.climber.request_climb(), "could not start cancel check")
	await _frames(40)
	token.climber.cancel()
	await _frames(70)
	_check(token.position.y < 0.02, "cancelled climb did not fall back to floor")
	# Respawn must not let an old route pull the owner back onto the worktop.
	await _at(spots[0].endpoint(false))
	_check(token.climber.request_climb(), "could not start respawn interruption check")
	await _frames(30)
	token.respawn_from_combat(world.home_base.global_position)
	await _frames(30)
	_check(not token.climber.active and token.position.distance_to(world.home_base.global_position) < 0.04, "climb survived respawn")
	for failure: String in failures: printerr("CLIMB FAIL: " + failure)
	print("ROACH CLIMB TEST: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	world.queue_free()
	await process_frame
	net.leave()
	quit(0 if failures.is_empty() else 1)

func _at(at: Vector3) -> void:
	token.climber.cancel()
	token.position = at + Vector3.UP * 0.002
	token.velocity = Vector3.ZERO
	await _frames(25)

func _finish_climb() -> void:
	var ticks := 0
	while token.climber.active and ticks < 600:
		await physics_frame
		ticks += 1
	_check(not token.climber.active, "climb never ended")
	await _frames(8)

func _frames(count: int) -> void:
	for i: int in count: await physics_frame

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
