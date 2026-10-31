extends SceneTree
## Real two-process lab: every station, both bodies, mechanics and clean reset.
const Catalog := preload("res://scripts/game/dev_room_catalog.gd")
var failures: Array[String] = []
var lab: Node
var world: Node3D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	lab = load("res://scenes/game/dev_room.tscn").instantiate()
	if lab.get_script() == null:
		printerr("DEV ROOM FAIL: room script failed to load")
		lab.free()
		quit(1)
		return
	root.add_child(lab)
	current_scene = lab
	if not await _until(func() -> bool: return lab.session_ready or not lab.error_message.is_empty(), 35000):
		_check(false, "dev room connection timed out")
	elif not lab.error_message.is_empty():
		_check(false, lab.error_message)
	else:
		world = lab.world
		if "--cart-only" in OS.get_cmdline_user_args():
			await _check_cart_access(world.players.get_node("1"))
		else:
			await _exercise()
	var child: int = lab.bot_pid
	var log_path: String = lab.bot_log_path
	var stop_results: Array = []
	lab.tree_exited.connect(func() -> void: stop_results.append(lab.opponent_stop_error))
	lab.leave_lab()
	await process_frame
	await process_frame
	_check(not root.get_node("Net").is_solo_test(), "room connection leaked into menu")
	_check(child <= 0 or stop_results == [OK], "room did not close its partner process")
	_check(current_scene.has_node("Margin/Layout/DevRoomButton"), "main menu has no dev-room entry")
	if FileAccess.file_exists(log_path):
		var log_text := FileAccess.get_file_as_string(log_path)
		_check(not log_text.contains("SCRIPT ERROR") and not log_text.contains("\nERROR:"), "partner reported errors: " + log_text)
	for failure: String in failures: printerr("DEV ROOM FAIL: ", failure)
	print("DEV ROOM TEST: ", "PASS" if failures.is_empty() else "FAIL")
	current_scene.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _exercise() -> void:
	var own := world.players.get_node("1") as CharacterBody3D
	var other := world.players.get_node(str(lab.bot_peer_id)) as CharacterBody3D
	_check(world.players.get_child_count() == 2 and own.camera.current and not other.camera.current, "room lacks two correctly owned peers")
	_check(world.kitchen_hazards._stations.size() == 1 and world.kitchen_hazards._volumes.size() == 6, "stove/oil fixtures incomplete")
	_check(world.ovens._ovens.size() == 2 and world.storage._props.size() == 4, "oven/storage fixtures incomplete")
	for index: int in Catalog.STATIONS.size():
		lab.select_scenario(index)
		if not await _ready_station(): return
		_check(world.get_node("DinerKitchen").has_node(Catalog.STATIONS[index].id), "station has no physical fixture")
		for role: String in ["cockroach", "exterminator"]:
			if own.player_role != role:
				lab.switch_character()
				if not await _ready_station(): return
			_check(own.player_role == role, "character selector did not apply " + role)
			_check(_body_clear(own) and _body_clear(other), "station spawn overlaps geometry: %d %s" % [index, role])
			_check(own.camera.current and not other.camera.current, "role swap changed camera ownership")
			_check(world.food_run.get_food_records().size() == 12 and world.get_food_delivered() == 0, "station reset changed supply or retained score")
			var clock: float = world.get_round_time_left()
			await create_timer(0.06).timeout
			_check(is_equal_approx(clock, world.get_round_time_left()), "held clock advanced")
		if not lab.play_as_roach:
			lab.switch_character()
			if not await _ready_station(): return
	# Real client role overrides must propagate to another peer and duplicate
	# ready messages must not let that client switch roles outside a lab reset.
	_check(world.get_role_for_peer(lab.bot_peer_id) == "exterminator", "combat partner role wrong")
	await _check_timer_ordering()
	await _check_food(own)
	await _check_food_supply()
	await _check_fixtures(own)
	await _check_room_routes(own)
	await _check_weapons(own)
	lab.expire_round()
	_check(world.get_match_phase() == 3, "expiry button did not end round")
	_check(not world.combat._damage(1, 100), "result allowed damage")
	lab.reset_scenario()
	await _ready_station()
	_check(world.get_match_phase() == 1, "result reset failed")
	# Session shutdown used to leave physics callbacks querying a missing peer.
	world.set_physics_process(false)

func _check_food_supply() -> void:
	lab.select_scenario(6)
	if not await _ready_station(): return
	var supply: Node = world.food_supply
	_check(await _until(func() -> bool: return supply.get_records().size() == 12, 2000), "storage fixture lacks new foods")
	_check(supply.get_status().spots == 16, "storage food markers missing")
	_check(lab.get_status().contains("New food:"), "storage lacks supply instructions/status")
	supply.refill_seconds = 0.25
	lab.partner_action()
	_check(supply.get_records().size() == 3, "F3 did not deplete production supply")
	_check(await _until(func() -> bool: return supply.get_records().size() == 12, 2000), "storage refill failed")
	supply.refill_seconds = 15.0
	lab.reset_scenario()
	await _ready_station()
	_check(await _until(func() -> bool: return supply.get_status().wave == 1, 2000), "F5 did not reset food wave")

func _check_weapons(own: CharacterBody3D) -> void:
	lab.select_scenario(8)
	await _ready_station()
	if lab.play_as_roach:
		lab.switch_character()
		await _ready_station()
	var gas: Node = world.gas_weapon
	_check(gas._station != null, "combat station has no production refill cradle")
	if gas._station == null: return
	own.position = gas._station.get_node("Control").global_position - Vector3.UP
	own.velocity = Vector3.ZERO
	await create_timer(0.25).timeout
	_check(gas.can_dock(1), "combat cradle prompt is unreachable")
	_check(world.shotgun_ammo.consume_shell(1), "dev shotgun could not consume shell")
	world.shotgun_ammo.request_reload()
	_check(world.shotgun_ammo.is_reloading(1), "dev cradle could not start real reload")
	_check(await _until(func() -> bool: return world.shotgun_ammo.shells(1) == 6, 1500), "dev reload did not restore shell")
	gas.request_action("dock")
	_check(gas.is_selected(1), "dev cradle did not exchange shotgun for gas")
	_check(not own.shotgun.request_fire(), "dev gas still allowed shotgun fire")
	var target: Node3D = world.players.get_node(str(lab.bot_peer_id))
	own.position = target.position + Vector3(0, 0, 1.5)
	own.velocity = Vector3.ZERO
	gas._input_left = INF
	var direction := (target.position + Vector3.UP * 0.01 - (own.position + Vector3(0.13, 1.4, -0.19))).normalized()
	var deadline := Time.get_ticks_msec() + 1600
	while Time.get_ticks_msec() < deadline and int(world.combat.get_state(lab.bot_peer_id).health) == 100:
		gas.request_spray(true, direction)
		await create_timer(0.1).timeout
	gas.request_spray(false, direction)
	gas._input_left = 0
	_check(int(world.combat.get_state(lab.bot_peer_id).health) < 100, "dev gas did not damage the real partner")
	var spent: float = gas.get_state().fuel
	own.position = gas._station.get_node("Control").global_position - Vector3.UP
	own.velocity = Vector3.ZERO
	await create_timer(0.3).timeout
	gas.request_action("dock")
	_check(not gas.is_selected(1), "dev cradle did not accept returned gas")
	await create_timer(0.3).timeout
	_check(float(gas.get_state().fuel) > spent, "dev cradle did not refill docked gas")
	lab.switch_character()
	await _ready_station()
	_check(float(gas.get_state().fuel) == 8 and int(gas.get_state().carrier) == 0 and world.shotgun_ammo.shells(1) == 6, "weapon state survived dev reset")
	own.position = gas._station.get_node("Control").global_position - Vector3.UP
	await create_timer(0.1).timeout
	_check(not gas.can_dock(1) and not gas._handle_action(1, "dock"), "dev cockroach could use human weapons")

func _check_food(own: CharacterBody3D) -> void:
	lab.select_scenario(1)
	if not await _ready_station(): return
	for index: int in 1:
		await create_timer(0.22).timeout
		world.food_run.request_action("grab", world.food_run.find_candidate(1))
	await create_timer(0.05).timeout
	_check(world.food_run.get_cargo_ids(1).size() == 1, "dev food patch cannot pick up one snack from its start")
	var setup: Dictionary = lab.get_scenario_setup()
	own.position = setup.host_position
	own.velocity = Vector3.ZERO
	await create_timer(0.3).timeout
	lab.partner_action()
	await create_timer(0.1).timeout
	world.food_run.request_action("throw", -1, Vector3.FORWARD)
	_check(await _until(func() -> bool: return not world.food_run.get_cargo_ids(lab.bot_peer_id).is_empty(), 3000), "real partner did not catch the throw")
	lab.partner_action()
	_check(await _until(func() -> bool: return world.food_run.get_cargo_ids(lab.bot_peer_id).is_empty(), 3000), "real partner did not return the throw")
	# One-item capacity means the throw leaves no spare snack in the sender's hand.
	await create_timer(0.3).timeout
	world.food_run.request_action("grab", world.food_run.find_candidate(1))
	own.position = world.home_base.position
	own.velocity = Vector3.ZERO
	await create_timer(1.7).timeout
	_check(world.get_food_delivered() > 0, "dev pantry cannot unload")
	lab.defeat_bug()
	_check(world.combat.is_ghost(1) and not world.can_peer_act(1), "defeat button did not enter normal ghost state")
	lab.switch_character()
	await _ready_station()
	_check(own.player_role == "exterminator" and own.shotgun.recoil_phase == 0 and not world.is_peer_carrying_food(1), "switch retained ghost, recoil or cargo")

func _check_fixtures(own: CharacterBody3D) -> void:
	lab.select_scenario(5)
	await _ready_station()
	_check(world.ovens._handle_action(1, "Oven2", "heat"), "dev human cannot reach oven heat")
	_check(world.ovens._handle_action(1, "Oven2", "door"), "dev human cannot open oven")
	lab.switch_character()
	await _ready_station()
	_check(world.ovens.can_reach(1, "Oven2"), "dev bug cannot reach oven shutoff")
	lab.select_scenario(4)
	await _ready_station()
	_check(world.kitchen_hazards._handle_toggle(1, "Range1"), "dev bug cannot reach stove")
	lab.select_scenario(2)
	await _ready_station()
	_check(own.climber.request_climb(), "dev climb cannot start: " + _climb_state(own))
	_check(await _until(func() -> bool: return not own.climber.active, 6000), "dev climb cannot finish")
	_check(own.position.y > 0.78, "dev climb did not reach platform")
	lab.select_scenario(3)
	await _ready_station()
	var cart: Node = world.serving_cart
	_check(cart._handle_request(1), "dev cart cannot activate")
	own.position = Catalog.STATIONS[3].at + Vector3(-2, 0.003, 2)
	_check(await _until(func() -> bool: return not cart.is_moving(), 7000), "dev cart path obstructed")
	# A thin obstacle crossed between two cart positions must still block it.
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.01, 0.06, 0.01)
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)
	body.position = cart.global_position + Vector3(-0.4725, 0.65, -0.9)
	await physics_frame
	await physics_frame
	_check(cart._path_blocked(-0.65), "cart skipped a thin obstruction during a large step")
	body.free()
	# Loaded replicas and owner movement must retain the final clear pose after a reset.
	lab.reset_scenario()
	await _ready_station()
	_check(not cart.get_state().blocked and not cart.is_moving(), "cart reset retained motion/blockage")

func _check_timer_ordering() -> void:
	world.set_solo_clock_paused(false)
	var revision: int = world._received_match_revision
	var tick: int = world._last_timer_tick + 1
	world._receive_timer(revision, tick, 80)
	_check(world.get_round_time_left() == 80, "current timer packet rejected")
	world._receive_timer(revision, tick - 1, 99)
	_check(world.get_round_time_left() == 80, "out-of-order timer moved clock backward")
	world.set_solo_clock_paused(true)
	world._receive_timer(revision, tick + 1, 70)
	_check(world.get_round_time_left() == 80, "stale timer overwrote held clock")
	world._finish_round(3)
	world._receive_timer(revision, tick + 2, 60)
	_check(world.get_match_phase() == 3 and world.get_round_time_left() == 80, "stale timer overwrote result")
	lab.reset_scenario()
	await _ready_station()

func _check_room_routes(own: CharacterBody3D) -> void:
	lab.select_scenario(4)
	await _ready_station()
	for spot: Node in get_nodes_in_group("roach_climb_spots"):
		own.respawn_from_combat(spot.endpoint(false) + Vector3.UP * 0.002)
		await create_timer(0.35).timeout
		_check(own.climber.request_climb(), "copied route cannot start: " + str(spot.name) + " " + _climb_state(own))
		await _until(func() -> bool: return not own.climber.active, 6000)
		_check(own.position.distance_to(spot.endpoint(true)) < 0.03, "copied route blocked: " + str(spot.name))
		await create_timer(0.35).timeout
		_check(own.climber.request_climb(), "copied route cannot descend: " + str(spot.name))
		await _until(func() -> bool: return not own.climber.active, 6000)
		_check(own.position.distance_to(spot.endpoint(false)) < 0.03, "copied route descent blocked: " + str(spot.name))
	lab.select_scenario(6)
	await _ready_station()
	for id: String in world.storage._props:
		var prop: Node3D = world.storage._props[id]
		own.respawn_from_combat(prop.get_node("BugInside").global_position + Vector3(0, -0.031, -0.02))
		await create_timer(0.1).timeout
		_check(world.storage._handle_toggle(1, id), "copied storage inside control blocked: " + id)
		await create_timer(1.3).timeout
		_check(absf(float(world.storage.get_state(id).angle) - float(prop.get_meta("open_angle"))) < 0.01, "copied storage sweep blocked: " + id)
		_check(world.storage._handle_toggle(1, id), "copied storage cannot close: " + id)
		await create_timer(1.3).timeout
		_check(absf(float(world.storage.get_state(id).angle)) < 0.01, "copied storage cannot finish closing: " + id)
	lab.select_scenario(7)
	await _ready_station()
	var vents: Node3D = world.get_node("DinerKitchen/vents/BugVents")
	own.respawn_from_combat(vents.get_node("PantryEntrance").global_position)
	own.set_physics_process(false)
	var north: Vector3 = vents.to_global(Vector3(-8.1, 0.001, -0.8))
	var south: Vector3 = vents.to_global(Vector3(-8.1, 0.001, 3.2))
	var lobby: Vector3 = vents.to_global(Vector3(-8.1, 0.001, 7.2))
	for point: Vector3 in [north, vents.get_node("KitchenNorthEntrance").global_position, north,
		south, vents.get_node("KitchenSouthEntrance").global_position, south,
		lobby, vents.get_node("LobbyEntrance").global_position]:
		await _walk_to(own, point)
	own.set_physics_process(true)
	await _check_cart_access(own)

func _check_cart_access(own: CharacterBody3D) -> void:
	lab.select_scenario(3)
	await _ready_station()
	own.respawn_from_combat(Vector3(4.05, 0.003, -4.5))
	own.camera_rig.rotation.y = PI
	await create_timer(0.1).timeout
	# Ramp transitions depend on the production controller's surface pose and
	# floor support correction, not a bare unrotated move_and_slide capsule.
	Input.action_press("move_forward")
	var reached := await _until(func() -> bool: return own.position.z > -1.4, 12000)
	Input.action_release("move_forward")
	_check(reached, "cart access route blocked: " + str(own.position))
	_check(own.position.y > 1.07, "cart access ramp does not reach deck")
	await create_timer(0.3).timeout
	lab.partner_action()
	_check(await _until(func() -> bool: return world.serving_cart.is_moving(), 2000), "real partner cannot start rider's cart")
	_check(await _until(func() -> bool: return not world.serving_cart.is_moving(), 12000), "ridden cart cannot reach dock")
	_check(own.position.y > 1.07 and absf(own.position.z - world.serving_cart.position.z) < 0.5, "dev-room cart did not carry its rider")

func _walk_to(own: CharacterBody3D, at: Vector3) -> void:
	var ticks := ceili(own.position.distance_to(at) * 60) + 45
	for index: int in ticks:
		var offset := at - own.position
		offset.y = 0
		if offset.length() < 0.012: break
		own.velocity = offset.normalized() * minf(1.0, offset.length() * 60)
		own.velocity.y = -0.2
		own.move_and_slide()
		await physics_frame
	_check(Vector2(own.position.x - at.x, own.position.z - at.z).length() < 0.035, "dev route blocked to %s at %s" % [at, own.position])
	own.velocity = Vector3.ZERO

func _ready_station() -> bool:
	var ok := await _until(func() -> bool: return lab.session_ready or not lab.error_message.is_empty())
	ok = ok and lab.error_message.is_empty()
	_check(ok, "station reset failed: " + lab.error_message)
	await create_timer(0.25).timeout
	# RPCs and process timers can finish before PhysicsServer flushes new body
	# transforms. Query spawn clearance only after the next completed physics step.
	await physics_frame
	await process_frame
	return ok

func _body_clear(token: CharacterBody3D) -> bool:
	var collision: CollisionShape3D = token.roach_collision if token.player_role == "cockroach" else token.exterminator_collision
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	query.transform = collision.global_transform
	query.transform.origin.y += 0.005
	query.exclude = [token.get_rid()]
	query.collision_mask = token.collision_mask
	var hits := token.get_world_3d().direct_space_state.intersect_shape(query, 4)
	for hit: Dictionary in hits:
		printerr("DEV ROOM overlap: peer=%s role=%s at=%s collider=%s at=%s" % [token.name, token.player_role,
			token.position, hit.collider.get_path(), hit.collider.global_position])
	return hits.is_empty()

func _until(check: Callable, timeout_ms: int = 10000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if check.call(): return true
		await process_frame
	return check.call()

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _climb_state(own: CharacterBody3D) -> String:
	return "position=%s floor=%s role=%s crawl=%s cooldown=%s message=%s" % [own.position,
		own.is_on_floor(), own.player_role, own.surface_crawler.active,
		own.climber._cooldown, own.climber._message]
