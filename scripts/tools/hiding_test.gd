extends SceneTree
## Real swept collisions: storage access/escape and every vent connection.
var failures: Array[String] = []
var world: Node3D
var token: CharacterBody3D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var net := root.get_node("Net")
	root.get_node("GameState").set_local_role_preference("cockroach")
	if not net.host_local_test(): quit(1); return
	world = load("res://scenes/game/game_world.tscn").instantiate()
	world.prototype_round_duration = 600
	root.add_child(world)
	await _frames(10)
	token = world.players.get_node("1")
	token.set_physics_process(false)
	_check(world.storage._props.size() == 4, "four storage props missing")
	for id: String in world.storage._props:
		var prop: Node3D = world.storage._props[id]
		var front: Vector3 = prop.get_node("BugOutside").position + Vector3(0, -0.031, 0.055)
		await _place(prop.to_global(front))
		_check(world.storage.can_reach(1, id), "outside bug control blocked: " + id)
		await _walk_to(prop.to_global(Vector3(0, 0.001, 0)))
		var inside: Vector3 = prop.get_node("BugInside").position + Vector3(0, -0.031, -0.02)
		await _walk_to(prop.to_global(inside))
		_check(world.storage._handle_toggle(1, id), "inside opening rejected: " + id)
		await _frames(95)
		_check(absf(float(world.storage.get_state(id).angle) - float(prop.get_meta("open_angle"))) < 0.01, "door/lid did not fully open: " + id + str(world.storage.get_state(id)))
		_check(world.storage._handle_toggle(1, id), "inside closing rejected: " + id)
		await _frames(95)
		_check(absf(float(world.storage.get_state(id).angle)) < 0.01, "door/lid did not fully close: " + id)
		await _walk_to(prop.to_global(front))
		_check(prop.has_node("HiddenItemPlacement"), "hidden-item marker missing")
	# Human can walk inside the tall cabinet, close it, and reopen from inside.
	world._assign_role(1, "exterminator")
	world._apply_roles_to_tokens()
	var cabinet: Node3D = world.storage._props.KitchenCabinet
	await _place(cabinet.to_global(Vector3(1.15, 0.001, 1.10)))
	_check(world.storage._handle_toggle(1, "KitchenCabinet"), "human open rejected")
	await _frames(95)
	await _walk_to(cabinet.to_global(Vector3(0, 0.001, 1.10)), 1.2)
	await _walk_to(cabinet.get_node("Interior").global_position, 1.2)
	_check(world.storage._handle_toggle(1, "KitchenCabinet"), "human inside close rejected")
	await _frames(95)
	_check(absf(float(world.storage.get_state("KitchenCabinet").angle)) < 0.01, "cabinet cannot close with human inside")
	_check(world.storage._handle_toggle(1, "KitchenCabinet"), "human trapped inside cabinet")
	await _frames(95)
	await _walk_to(cabinet.get_node("Approach").global_position, 1.2)
	# An occupied doorway must pause, then resume after the obstruction leaves.
	await _place(cabinet.to_global(Vector3(0, 0.001, 0.58)))
	world.storage._states.KitchenCabinet.open = false
	await _frames(95)
	_check(world.storage.get_state("KitchenCabinet").blocked, "door crushed player instead of pausing")
	await _place(Vector3(0, 0.001, 0))
	await _frames(95)
	_check(absf(float(world.storage.get_state("KitchenCabinet").angle)) < 0.01, "blocked door never resumed")
	_check(not world.storage._handle_toggle(1, "KitchenCabinet"), "distant request accepted")
	_check(not world.storage._handle_toggle(1, "unknown"), "unknown prop accepted")
	# The human's actual capsule cannot enter a duct mouth.
	var vents: Node3D = world.get_node("DinerKitchen/BugVents")
	await _place(vents.get_node("KitchenNorthEntrance").global_position + Vector3(0.5, 0, 0))
	for i: int in 120:
		token.velocity = Vector3(-1, -0.2, 0)
		token.move_and_slide()
		await physics_frame
	_check(token.position.x > -7.99, "human crossed wall through bug duct: " + str(token.position))
	world._assign_role(1, "cockroach")
	world._apply_roles_to_tokens()
	await _place(vents.get_node("PantryEntrance").global_position)
	# Walk both directions through every branch and both wall cutouts.
	var junction := Vector3(-8.1, 0.001, -0.8)
	var route: Array[Vector3] = [junction, vents.get_node("KitchenNorthEntrance").global_position, junction,
		Vector3(-8.1, 0.001, 3.2), vents.get_node("KitchenSouthEntrance").global_position,
		Vector3(-8.1, 0.001, 3.2), Vector3(-8.1, 0.001, 7.2), vents.get_node("LobbyEntrance").global_position,
		Vector3(-8.1, 0.001, 7.2), junction, vents.get_node("PantryEntrance").global_position]
	for point: Vector3 in route: await _walk_to(point, 1.0)
	# Ghosts still traverse physical spaces but cannot operate storage.
	world.combat.damage_from_environment(1, 100)
	_check(world.combat.is_ghost(1), "ghost setup failed")
	await _place(world.storage._props.PantryBox.get_node("BugOutside").global_position)
	_check(not world.storage._handle_toggle(1, "PantryBox"), "ghost operated storage")
	world.storage.reset_storage()
	for id: String in world.storage._states: _check(not world.storage.get_state(id).open, "reset retained open target")
	world.queue_free()
	await process_frame
	net.leave()
	for failure: String in failures: printerr("HIDING FAIL: " + failure)
	print("HIDING TEST: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _place(at: Vector3) -> void:
	token.position = at
	token.velocity = Vector3.ZERO
	await _frames(3)

func _walk_to(at: Vector3, speed: float = 0.5) -> void:
	var count := ceili(token.position.distance_to(at) / speed * 60) + 35
	for i: int in count:
		var offset := at - token.position
		offset.y = 0
		if offset.length() < 0.012: break
		token.velocity = offset.normalized() * minf(speed, offset.length() * 60)
		token.velocity.y = -0.2
		token.move_and_slide()
		await physics_frame
	_check(Vector2(token.position.x - at.x, token.position.z - at.z).length() < 0.035, "route blocked to %s, stopped at %s" % [at, token.position])
	token.velocity = Vector3.ZERO

func _frames(count: int) -> void:
	for i: int in count: await physics_frame

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
