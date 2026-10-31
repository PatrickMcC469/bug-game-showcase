extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var lab: Node = load("res://scenes/game/dev_room.tscn").instantiate()
	root.add_child(lab)
	current_scene = lab
	if not await until(func() -> bool: return lab.session_ready, 35000):
		printerr("DRAIN DEV ROOM TEST: connection failed")
		lab.free()
		quit(1)
		return
	lab.select_scenario(2)
	check(await until(func() -> bool: return lab.session_ready, 15000), "climbing setup failed")
	var world: Node3D = lab.world
	var remote: CharacterBody3D = world.players.get_node(str(lab.bot_peer_id))
	var own: CharacterBody3D = world.players.get_node("1")
	var route: Node3D = world.get_node("DinerKitchen/DrainRoutes/KitchenDrain")
	check(world.get_role_for_peer(lab.bot_peer_id) == "cockroach", "partner not a bug")
	lab.partner_action()
	check(await until(func() -> bool: return remote.position.distance_to(route.endpoint(true).get_node("Arrival").global_position) < 0.03, 8000), "F3 partner did not emerge outside")
	check(await until(func() -> bool: return remote.position.distance_to(route.endpoint(false).get_node("Arrival").global_position) < 0.03, 8000), "F3 partner did not return")
	lab.reset_scenario()
	check(await until(func() -> bool: return lab.session_ready, 15000), "reset failed")
	check(world.drains._cooldowns.is_empty() and world.drains._reservations.is_empty(), "reset leaked travel state")
	# Actual walking controller can enter and escape the basin around its drain.
	own.respawn_from_combat(route.endpoint(false).get_node("Arrival").global_position)
	await create_timer(0.3).timeout
	own.camera_rig.rotation.y = PI
	Input.action_press("move_forward")
	check(await until(func() -> bool: return own.position.y > 1.075, 5000), "bug could not crawl back out of the sink")
	Input.action_release("move_forward")
	lab.switch_character()
	check(await until(func() -> bool: return lab.session_ready, 15000), "human reset failed")
	check(own.player_role == "exterminator", "human body selection failed")
	check(world.drains.find_entrance(1).is_empty(), "human got drain prompt")
	lab.leave_lab()
	await process_frame
	await process_frame
	for failure: String in failures: printerr("DRAIN DEV FAIL: " + failure)
	print("DRAIN DEV ROOM TEST: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
func until(predicate: Callable, ms: int) -> bool:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		if predicate.call(): return true
		await process_frame
	return predicate.call()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
