extends SceneTree
var failures: Array[String] = []
var world: Node3D
var token: CharacterBody3D
var hazards: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var net := root.get_node("Net")
	root.get_node("GameState").set_local_role_preference("cockroach")
	_check(net.host_local_test(), "host failed")
	world = load("res://scenes/game/game_world.tscn").instantiate()
	world.prototype_round_duration = 600
	root.add_child(world)
	hazards = world.kitchen_hazards
	token = world.players.get_node("1")
	await _frames(5)
	token.set_physics_process(false)
	_check(hazards._stations.size() == 4, "missing stove banks")
	_check(hazards._volumes.size() == 18, "missing burner/oil volumes")
	for origin: Marker3D in world.find_children("FlameOrigin", "Marker3D", true, false):
		var jets := origin.get_node("FlameEffect/GasJets") as MeshInstance3D
		_check(jets.mesh.get_aabb().size.y > 0.04, "saved flame geometry missing")
	for role: String in ["exterminator", "cockroach"]:
		world._roles[1] = role
		world._apply_role_to_token(1)
		for id: String in hazards._stations:
			var station: Node3D = hazards._stations[id]
			var control: Node3D = station.get_node("FloorControl" if role == "cockroach" else "HandControl")
			token.position = control.global_position + Vector3(0, -control.position.y + 0.001, 0.10 if role == "cockroach" else 0.65)
			await _frames(3)
			_check(hazards.can_reach(1, id), role + " cannot reach " + id)
			_check(hazards._handle_toggle(1, id), role + " toggle rejected")
			_check(hazards.is_on(id), "flames not activated")
			_check(not hazards._handle_toggle(1, id), "toggle spam accepted")
			hazards.reset_hazards()
	_check(not hazards._handle_toggle(1, "Missing"), "invalid station accepted")
	world._match_phase = 0
	_check(hazards._handle_toggle(1, "Range4"), "waiting-room practice switch rejected")
	hazards.reset_hazards()
	world._match_phase = 1
	token.position = Vector3(0, 0.01, 0)
	await _frames(2)
	_check(not hazards._handle_toggle(1, "Range1"), "remote-distance toggle accepted")
	# Verify line of sight, not distance alone, gates control requests.
	var control: Node3D = hazards._stations.Range1.get_node("FloorControl")
	token.position = control.global_position + Vector3(0, -0.044, 0.1)
	var blocker := StaticBody3D.new()
	var block_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 0.2, 0.015)
	block_shape.shape = box
	blocker.add_child(block_shape)
	world.add_child(blocker)
	blocker.position = control.global_position + Vector3(0, 0, 0.05)
	await _frames(3)
	_check(not hazards.can_reach(1, "Range1"), "control used through obstacle")
	blocker.free()
	await _frames(2)
	# A real carried snack must release through the existing death lifecycle.
	var food: Dictionary = world.food_run.get_food_records()[0]
	token.position = food.pos + Vector3.UP * 0.002
	await _frames(3)
	world.food_run.request_action("grab", 0)
	_check(world.food_run.get_cargo_ids(1).size() == 1, "food setup failed")
	var flames: Array[Node] = hazards._stations.Range1.find_children("FlameOrigin", "Marker3D", true, false)
	token.position = (flames[1] as Node3D).global_position + Vector3.UP * 0.065
	await _frames(4)
	_check(not world.combat.is_ghost(1), "unlit burner killed bug")
	hazards._on.Range1 = true
	hazards.send_snapshot()
	await _frames(4)
	_check(world.combat.is_ghost(1), "lit burner did not kill bug")
	_check(float(world.combat.get_state(1).ghost_left) > 9.7, "death did not start ten-second ghost")
	_check(world.food_run.get_cargo_ids(1).is_empty(), "hazard death kept food")
	token.position = control.global_position + Vector3(0, -0.044, 0.1)
	await _frames(2)
	_check(not hazards._handle_toggle(1, "Range1"), "ghost operated stove")
	world.combat.reset_round()
	await _frames(65)
	# Cookware bottoms protect bugs inside; neighboring bare flames remain lethal.
	var pot := world.get_node("DinerKitchen/KitchenEquipment/Saucepan") as Node3D
	token.position = pot.global_position + Vector3.UP * 0.012
	await _frames(4)
	_check(not world.combat.is_ghost(1), "flame damage passed through pot bottom")
	var fryer := world.get_node("DinerKitchen/HotLineDetails/TwinBasketFryer") as Node3D
	token.position = fryer.global_position + Vector3(-0.39, 1.101, 0)
	await _frames(4)
	_check(not world.combat.is_ghost(1), "safe fryer rim killed bug")
	token.position = fryer.global_position + Vector3(0.35, 0.946, 0)
	await _frames(4)
	_check(world.combat.is_ghost(1), "oil contact did not kill bug")
	world.combat.reset_round()
	await _frames(65)
	world._roles[1] = "exterminator"
	world._apply_role_to_token(1)
	token.position = fryer.global_position + Vector3(0.19, 0.946, 0)
	await _frames(3)
	_check(int(world.combat.get_state(1).health) == 100, "exterminator death behavior changed")
	token.position = Vector3(0, 0.001, 0)
	await _frames(3)
	world._roles[1] = "cockroach"
	world._apply_role_to_token(1)
	await _frames(3)
	hazards.reset_hazards()
	_check(not hazards.is_on("Range1"), "reset left stove on")
	# Exercise each new marked route with the actual moving capsule and cookware.
	token.set_physics_process(true)
	for spot: Node3D in world.get_node("DinerKitchen/KitchenEquipment/ClimbSpots").get_children():
		token.position = spot.endpoint(false) + Vector3.UP * 0.002
		token.velocity = Vector3.ZERO
		await _frames(20)
		_check(token.climber.request_climb(), "new climb rejected: " + str(spot.name))
		var ticks := 0
		while token.climber.active and ticks < 600:
			await physics_frame
			ticks += 1
		await _frames(5)
		_check(token.position.distance_to(spot.endpoint(true)) < 0.06, "climb failed: %s at %s expected %s" % [spot.name, token.position, spot.endpoint(true)])
		_check(not world.combat.is_ghost(1), "safe climb landing killed bug: " + str(spot.name))
		await _frames(22)
		_check(token.climber.request_climb(), "descent rejected: " + str(spot.name))
		ticks = 0
		while token.climber.active and ticks < 600:
			await physics_frame
			ticks += 1
		await _frames(5)
		_check(token.position.distance_to(spot.endpoint(false)) < 0.06, "descent failed: " + str(spot.name))
	world._finish_round(3)
	_check(not hazards._handle_toggle(1, "Range1"), "toggle accepted after result")
	token.set_physics_process(false)
	token.position = fryer.global_position + Vector3(0.35, 0.946, 0)
	await _frames(4)
	_check(not world.combat.is_ghost(1), "oil killed after result")
	world.queue_free()
	await process_frame
	net.leave()
	for failure: String in failures: printerr("KITCHEN FAIL: " + failure)
	print("KITCHEN HAZARDS TEST: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _frames(count: int) -> void:
	for i: int in count: await physics_frame

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
