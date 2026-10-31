extends SceneTree
## Uses the same packed fixtures/controller as the interactive mechanics room.
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
	var old_map := world.get_node("DinerKitchen")
	world.remove_child(old_map)
	old_map.free()
	var map: Node3D = load("res://scenes/game/maps/dev_room_map.tscn").instantiate()
	map.name = "DinerKitchen"
	world.add_child(map)
	map.owner = world
	map.unique_name_in_owner = true
	root.add_child(world)
	await _frames(8)
	token = world.players.get_node("1")
	_check(token.surface_crawler != null, "crawler failed to load")
	if token.surface_crawler == null:
		quit(1)
		return
	await _at(Vector3(1.5, 0.002, 11.65))
	await _walk(40)
	_check(token.position.y > 0.025 and token.position.y < 0.032, "tray did not support the roach: " + str(token.position))
	await _at(Vector3(6.5, 0.002, 10.48))
	await _walk(34)
	_check(token.surface_crawler.active and token.position.y > 0.08, "box wall did not attach: " + str(token.position))
	_check(absf(token.cockroach_model.basis.orthonormalized().y.y) < 0.2, "roach did not turn onto wall")
	var stopped := token.position
	await _frames(20)
	_check(token.position.distance_to(stopped) < 0.003, "idle roach slipped off wall")
	_check(token.camera_rig.global_basis.y.dot(Vector3.UP) > 0.999, "camera rolled")
	await _walk(50)
	_check(token.position.y >= 0.399 and token.position.z < 10.29, "could not round box edge: " + str(token.position))
	await _at(Vector3(6.5, 0.402, 10), -PI / 2)
	await _walk(40)
	_check(token.surface_crawler.active and token.cockroach_model.basis.orthonormalized().y.x > 0.9 and token.position.y < 0.38, "could not crawl down an unmarked edge: " + str(token.position))
	# Approach the rear wall under the overhang, then crawl onto its underside.
	await _at(Vector3(6.5, 0.002, 9.50), PI)
	await _walk(80)
	_check(token.surface_crawler.active and token.cockroach_model.basis.orthonormalized().y.y < -0.9, "did not crawl onto underside: " + str(token.position))
	token.surface_crawler.cancel()
	await _frames(55)
	_check(token.position.y < 0.01, "letting go did not return to floor")
	await _at(Vector3(6.5, 0.002, 10.48))
	await _walk(34)
	token.respawn_from_combat(Vector3(0, 0.002, 0))
	await _frames(25)
	_check(not token.surface_crawler.active and token.position.distance_to(Vector3.ZERO) < 0.02, "respawn retained wall attachment")
	# Fast approaches must still sweep the thin tray.
	await _at(Vector3(1.5, 0.002, 11.65))
	Input.action_press("sprint")
	Input.action_press("dash")
	await _walk(15)
	Input.action_release("dash")
	Input.action_release("sprint")
	_check(token.position.y >= 0.025, "dash clipped through tray")
	# Carry the real finite snacks. Their upright clearance must follow the
	# same route and reject an obstructed overhang without losing possession.
	for index: int in 3:
		await _at(world.food_run.get_food_records()[index].pos)
		world.food_run.request_action("grab", index)
		await _frames(18)
	_check(token.cargo_count == 3, "could not prepare real cargo")
	await _at(Vector3(6.5, 0.002, 10.48))
	await _walk(150)
	_check(token.position.y > 0.399 and token.cargo_count == 3, "loaded crawl failed: " + str(token.position))
	await _at(Vector3(6.5, 0.002, 9.50), PI)
	await _walk(180)
	_check(token.position.y < 0.399, "upright cargo passed through overhang")
	_check(token.climber.can_occupy(token.position, token.cockroach_model.basis.orthonormalized()), "blocked cargo overlaps solid geometry")
	world._assign_role(1, "exterminator")
	world._apply_roles_to_tokens()
	await _at(Vector3(6.5, 0.002, 11.1))
	await _walk(50)
	_check(not token.surface_crawler.active and token.position.z > 10.6, "human crawled through or over box")
	for failure: String in failures: printerr("SURFACE FAIL: ", failure)
	print("ROACH SURFACE TEST: ", "PASS" if failures.is_empty() else "FAIL")
	world.queue_free()
	await process_frame
	net.leave()
	quit(0 if failures.is_empty() else 1)

func _at(at: Vector3, yaw: float = 0) -> void:
	token.respawn_from_combat(at)
	token.camera_rig.rotation = Vector3(0, yaw, 0)
	token._facing_yaw = yaw
	token._surface_normal = Vector3.UP
	token._pose_roach_on_surface()
	await _frames(25)

func _walk(frames: int) -> void:
	Input.action_press("move_forward")
	await _frames(frames)
	Input.action_release("move_forward")
	await _frames(2)

func _frames(count: int) -> void:
	for i: int in count: await physics_frame

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
