extends SceneTree
## Production map and real client intents. Also run with -- --devmap.
var failures: Array[String] = []
var world: Node3D
var net: Node
var probe: Node
var own: CharacterBody3D
var child := -1
var connected := false
var devmap := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	devmap = "--devmap" in OS.get_cmdline_user_args()
	net = root.get_node("Net")
	root.get_node("GameState").set_local_role_preference("cockroach")
	probe = preload("res://scripts/tools/home_returns_test_peer.gd").new()
	probe.name = "HomeProbe"
	root.add_child(probe)
	if "--home-client" in OS.get_cmdline_user_args():
		net.connected.connect(func() -> void: connected = true)
		if not net.join_local_test() or not await _until(func() -> bool: return connected, 10000): quit(1); return
		_load_world()
		await create_timer(60).timeout
		quit()
		return
	if not net.host_local_test(): quit(1); return
	_load_world()
	own = world.players.get_node("1")
	own.set_physics_process(false)
	await create_timer(0.25).timeout
	_check(world.home_returns.layout_errors().is_empty(), "layout invalid: " + str(world.home_returns.layout_errors()))
	_check(world.get_match_phase() == 1, "valid map did not start")
	_check(world.home_returns.points.size() == 2, "expected two map-owned instances")
	for home: Area3D in world.home_returns.points:
		_check(home.scene_file_path == "res://scenes/game/props/home_return_point.tscn", "map uses copied geometry instead of reusable instance")
		own.global_position = home.global_position + Vector3.UP * 0.002
		_check(world.home_returns.at_position(own.global_position) == home, "entrance obstructed")
		_check(world.home_returns.nearest(home.global_position) == home, "nearest-home query wrong")
		_check(world.home_returns.at_position(home.global_position + Vector3.UP * 0.15) == null, "delivery through upper floor")
		var floor_hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(home.global_position + Vector3.UP * 0.02, home.global_position - Vector3.UP * 0.03, 1))
		_check(not floor_hit.is_empty(), "home has no floor")
		# Actual body and cargo can enter from the front and leave either end.
		for offset: Vector3 in [Vector3(0, 0.002, 0.11), Vector3(0.16, 0.002, 0), Vector3(-0.16, 0.002, 0)]:
			own.global_position = home.to_global(offset)
			var contact := KinematicCollision3D.new()
			var blocked := own.test_move(own.global_transform, home.global_position + Vector3.UP * 0.002 - own.global_position, contact, own.safe_margin)
			_check(not blocked, "home crawl approach blocked: %s %s %s" % [home.name, offset, contact.get_collider().get_path() if blocked else "clear"])
	_check(await _until(func() -> bool: return world.food_supply.get_records().size() == 12, 3000), "supply missing")
	for index: int in 2:
		_check(await _grab(), "host food pickup failed")
		var before: int = world.get_food_delivered()
		await process_frame
		await physics_frame
		var destination: Area3D = world.home_returns.points[index]
		for offset: Vector3 in [Vector3(0, 0.002, 0.11), Vector3(0.16, 0.002, 0), Vector3(-0.16, 0.002, 0)]:
			own.global_position = destination.to_global(offset)
			_check(not own.test_move(own.global_transform, destination.global_position + Vector3.UP * 0.002 - own.global_position, null, own.safe_margin), "loaded approach blocked: " + str(destination.name))
		own.global_position = destination.global_position + Vector3.UP * 0.002
		await create_timer(0.85).timeout
		_check(world.food_carry.held(1).is_empty() and world.get_food_delivered() == before + 2, "home did not bank held food exactly once")
		await create_timer(0.3).timeout
		_check(world.get_food_delivered() == before + 2, "home duplicated servings")
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://scripts/tools/home_returns_test.gd", "--", "--home-client"])
	if devmap: args.append("--devmap")
	child = OS.create_process(OS.get_executable_path(), args + net.get_local_test_arguments())
	_check(await _until(func() -> bool: return world.get_ready_peer_ids().size() == 2, 12000), "late client did not join")
	var peers: Array = world.get_ready_peer_ids()
	peers.erase(1)
	if not peers.is_empty():
		var peer := int(peers[0])
		probe.inspect.rpc_id(peer, world.get_food_delivered())
		await _reply()
		_check(probe.reply.get("score", false) and probe.reply.get("homes", 0) == 2, "late client score/homes/authority mismatch")
		for index: int in 2:
			var before: int = world.get_food_delivered()
			probe.reply = {}
			probe.haul.rpc_id(peer, index)
			await _reply()
			_check(probe.reply.get("hauled", false) and world.get_food_delivered() == before + 2, "real client could not deliver to home " + str(index))
	# Blocking world geometry between actor and zone must reject delivery.
	var home: Area3D = world.home_returns.points[0]
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.002, 0.1, 0.15)
	collision.shape = shape
	wall.add_child(collision)
	world.add_child(wall)
	wall.global_position = home.global_position + Vector3(0.025, 0.05, 0)
	await physics_frame
	_check(world.home_returns.at_position(home.global_position + Vector3(0.05, 0.002, 0)) == null, "banking passed through wall")
	wall.free()
	# Bad layouts fail closed, and new food cannot spawn beside homes.
	var saved: Vector3 = home.position
	var spot: Vector3 = world.food_supply.get_spot_positions().values()[0]
	home.global_position = spot
	_check(not world.home_returns.layout_errors().is_empty(), "unsafe food/home spacing accepted")
	_check(not world.food_supply.is_spot_clear(world.food_supply.get_spot_positions().keys()[0]), "supply ignored home exclusion")
	home.position = saved
	world._reset_to_waiting()
	var removed: Area3D = world.home_returns.points.pop_back()
	world._start_round()
	_check(world.get_match_phase() == 0, "single-home map started")
	world.home_returns.points.append(removed)
	world._start_round()
	_check(world.get_match_phase() == 1 and world.get_food_delivered() == 0, "reset/restart did not restore quota")
	await _finish()

func _load_world() -> void:
	world = load("res://scenes/game/game_world.tscn").instantiate()
	if devmap:
		var old := world.get_node("DinerKitchen")
		world.remove_child(old)
		old.free()
		var map: Node = load("res://scenes/game/maps/dev_room_map.tscn").instantiate()
		map.name = "DinerKitchen"
		world.add_child(map)
		map.owner = world
		map.unique_name_in_owner = true
	root.add_child(world)
	probe.world = world

func _grab() -> bool:
	for record: Dictionary in world.food_supply.get_records():
		own.global_position = record.position + Vector3(0.045, 0.002, 0)
		own.velocity = Vector3.ZERO
		await create_timer(0.2).timeout
		if world.food_carry._action(1, "grab", int(record.id)): return true
	return false

func _reply() -> void:
	_check(await _until(func() -> bool: return not probe.reply.is_empty(), 12000), "client action timed out")
func _until(check: Callable, timeout: int) -> bool:
	var end := Time.get_ticks_msec() + timeout
	while not check.call() and Time.get_ticks_msec() < end: await process_frame
	return bool(check.call())
func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	if child > 0 and OS.is_process_running(child): OS.kill(child)
	multiplayer_poll = false
	world.free()
	probe.free()
	net.leave()
	for failure: String in failures: printerr("HOME RETURN FAIL: ", failure)
	print("HOME RETURN TEST: ", "PASS" if failures.is_empty() else "FAIL", " (dev room)" if devmap else " (diner)")
	quit(0 if failures.is_empty() else 1)
