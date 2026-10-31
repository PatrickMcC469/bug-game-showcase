extends SceneTree
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
	token = world.players.get_node("1")
	await _frames(10)
	_check(world.ovens._ovens.size() == 4, "missing ovens")
	for id: String in world.ovens._ovens:
		var oven: Node3D = world.ovens._ovens[id]
		token.position = oven.get_node("BugEntrance").global_position
		token.velocity = Vector3.ZERO
		await _frames(20)
		for i: int in 70:
			token.velocity = Vector3(0, 0, -0.45)
			token.move_and_slide()
			await physics_frame
		_check(oven.to_local(token.position).z < 0.64, "closed vent entrance blocked: " + id)
		_check(world.ovens._bugs_inside(id).has(1), "interior not detected: " + id)
		_check(token.vitals.health == 100, "cold oven hurt bug")
		for i: int in 70:
			token.velocity = Vector3(0, 0, 0.45)
			token.move_and_slide()
			await physics_frame
		_check(oven.to_local(token.position).z > 0.86, "closed vent exit blocked: " + id)
	# Human controls open all doors, and a nearby player safely pauses the arc.
	world._assign_role(1, "exterminator")
	world._apply_roles_to_tokens()
	for id: String in world.ovens._ovens:
		var oven: Node3D = world.ovens._ovens[id]
		token.position = oven.to_global(Vector3(0.52, 0.001, 1.82))
		token.velocity = Vector3.ZERO
		await _frames(20)
		_check(world.ovens._handle_action(1, id, "door"), "human open rejected: " + id)
		await _frames(85)
		_check(absf(float(world.ovens.get_state(id).angle) - PI * 0.5) < 0.01, "door failed to open: " + id)
		_check(world.ovens._handle_action(1, id, "heat"), "human heat rejected: " + id)
		_check(world.ovens.get_state(id).hot, "oven heat not set")
		_check(not world.kitchen_hazards.is_on("Range" + id.trim_prefix("Oven")), "oven switched stove burners")
	var oven: Node3D = world.ovens._ovens.Oven1
	token.position = oven.to_global(Vector3(0, 0.001, 1.13))
	token.velocity = Vector3.ZERO
	token.set_physics_process(false)
	await _frames(4)
	world.ovens._states.Oven1.open = false
	await _frames(15)
	_check(world.ovens.get_state("Oven1").blocked, "door did not stop for player")
	token.position = Vector3(0, 0.01, 0)
	await _frames(90)
	_check(float(world.ovens.get_state("Oven1").angle) < 0.01, "door did not resume after clearing")
	_check(not world.ovens._handle_action(1, "Oven1", "heat"), "distant oven control accepted")
	_check(not world.ovens._handle_action(1, "Oven1", "anything"), "unknown action accepted")
	world._assign_role(1, "cockroach")
	world._apply_roles_to_tokens()
	await _frames(3)
	token.position = oven.to_global(Vector3(-0.55, 0.001, 0.55))
	await _frames(4)
	_check(world.ovens.can_reach(1, "Oven1"), "inside shutoff unreachable")
	_check(not world.ovens._handle_action(1, "Oven1", "door"), "bug opened door")
	await _frames(35)
	var health: int = world.combat.get_state(1).health
	_check(health < 100 and health >= 80, "oven did not apply gradual damage: %d" % health)
	_check(world.ovens._handle_action(1, "Oven1", "heat"), "bug could not shut off hot oven inside")
	await _frames(70)
	_check(int(world.combat.get_state(1).health) == health, "damage continued after shutoff")
	_check(not world.ovens._handle_action(1, "Oven1", "heat"), "bug could turn oven on")
	token.position = oven.to_global(Vector3(-0.55, 0.001, 0.92))
	await _frames(3)
	world.ovens._states.Oven1.hot = true
	_check(world.ovens._handle_action(1, "Oven1", "heat"), "outside bug shutoff unreachable")
	world.ovens._states.Oven1.hot = true
	world.ovens.send_snapshot()
	await _frames(65)
	_check(int(world.combat.get_state(1).health) == health, "heat leaked outside oven")
	token.position = oven.to_global(Vector3(0.94, 0.001, 0))
	await _frames(35)
	_check(int(world.combat.get_state(1).health) < health, "heat missed bug beside interior wall")
	token.position = oven.to_global(Vector3(0.2, 0.001, 0))
	await _frames(320)
	_check(world.combat.is_ghost(1), "oven exposure never defeated bug")
	_check(not world.ovens._handle_action(1, "Oven1", "heat"), "ghost used shutoff")
	world.ovens.reset_ovens()
	_check(not world.ovens.get_state("Oven1").hot and world.ovens._exposure.is_empty(), "reset did not clear oven heat/exposure")
	world._finish_round(3)
	_check(not world.ovens._handle_action(1, "Oven1", "door"), "oven input accepted after result")
	world.queue_free()
	await process_frame
	net.leave()
	for failure: String in failures: printerr("OVEN FAIL: " + failure)
	print("OVEN TEST: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _frames(count: int) -> void:
	for i: int in count: await physics_frame

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
