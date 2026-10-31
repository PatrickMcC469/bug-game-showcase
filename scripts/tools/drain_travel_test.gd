extends SceneTree
var failures: Array[String] = []
var world: Node3D
var own: CharacterBody3D
var net: Node
var probe: Node
var child := -1
var connected := false
var dev := false
var route: Node3D
var id := ""

func _initialize() -> void: run.call_deferred()
func load_world() -> void:
	world = load("res://scenes/game/game_world.tscn").instantiate()
	if dev:
		world.get_node("DinerKitchen").free()
		var map: Node3D = load("res://scenes/game/maps/dev_room_map.tscn").instantiate()
		map.name = "DinerKitchen"
		world.add_child(map)
		map.owner = world
		map.unique_name_in_owner = true
	world.prototype_round_duration = 600
	root.add_child(world)
	probe.world = world
	route = world.get_node("DinerKitchen/DrainRoutes/KitchenDrain")
	id = str(world.get_path_to(route))
func run() -> void:
	dev = "--devmap" in OS.get_cmdline_user_args()
	net = root.get_node("Net")
	root.get_node("GameState").set_local_role_preference("cockroach")
	probe = preload("res://scripts/tools/drain_travel_test_peer.gd").new()
	probe.name = "DrainProbe"
	root.add_child(probe)
	if "--drain-client" in OS.get_cmdline_user_args():
		net.connected.connect(func() -> void: connected = true)
		if not net.join_local_test() or not await until(func() -> bool: return connected, 12000): quit(1); return
		load_world()
		await create_timer(90).timeout
		quit()
		return
	if not net.host_local_test(): quit(1); return
	load_world()
	own = world.players.get_node("1")
	own.set_physics_process(false)
	await create_timer(0.3).timeout
	check(world.drains._routes.size() == 1, "link not registered")
	check(not world.drains._handle_request(1, "unknown", false), "unknown route accepted")
	check(not world.drains._handle_request(1, id, false), "distant entry accepted")
	for outside: bool in [false, true]:
		await at(outside)
		check(world.drains.can_reach(1, id, outside), "control unreachable " + str(outside))
		check(world.drains.destination_clear(1, id, outside), "arrival blocked " + str(outside))
		check(world.drains._handle_request(1, id, outside), "host travel rejected")
		check(own.position.distance_to(arrival(not outside)) < 0.025, "host arrival wrong")
		check(not world.drains._handle_request(1, id, not outside), "cooldown bypass")
		await create_timer(1.05).timeout
	# Travel preserves actual host-owned food and health, including new food.
	var food: Dictionary = world.food_run.get_food_records()[0]
	own.position = food.pos + Vector3.UP * 0.002
	await create_timer(0.25).timeout
	world.food_run.request_action("grab", int(food.id))
	await create_timer(0.25).timeout
	check(own.cargo_count == 1, "legacy pickup failed")
	world.combat.damage_from_environment(1, 20)
	var health: int = world.combat.get_state(1).health
	await at(false)
	check(world.drains._handle_request(1, id, false), "loaded travel rejected")
	check(own.position.distance_to(arrival(true)) < 0.025 and own.cargo_count == 1, "legacy food lost/arrival wrong")
	check(world.combat.get_state(1).health == health, "travel changed health")
	world.food_run.request_action("drop")
	await create_timer(0.3).timeout
	for row: Dictionary in world.food_supply.get_records():
		if row.type != "french_fry": continue
		own.position = row.position + Vector3(0.045, 0.002, 0)
		await create_timer(0.3).timeout
		world.food_carry.request_action("grab", int(row.id))
		break
	await create_timer(0.3).timeout
	var held: Dictionary = world.food_carry.held(1)
	check(not held.is_empty(), "new food pickup failed")
	await at(false)
	check(world.drains._handle_request(1, id, false), "new food travel rejected")
	check(world.food_carry.held(1) == held, "travel changed held food record")
	await create_timer(1.05).timeout
	check(world.drains._handle_request(1, id, true), "new food return rejected")
	world.food_carry.request_action("drop")
	await create_timer(1.05).timeout
	# Obstruction, below-sink reach, roles, death, freeze and results are rejected.
	await at(false)
	var obstacle := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(0.15, 0.15, 0.15)
	obstacle.add_child(shape)
	world.add_child(obstacle)
	obstacle.position = arrival(true) + Vector3.UP * 0.06
	await physics_frame
	await physics_frame
	check(not world.drains._handle_request(1, id, false), "solid blocked exit accepted")
	check(own.position.distance_to(arrival(false)) < 0.025, "blocked entry moved actor")
	obstacle.free()
	await physics_frame
	own.position = route.endpoint(false).get_node("Control").global_position - Vector3.UP * 0.07
	check(not world.drains.can_reach(1, id, false), "used drain through sink bottom")
	await at(false)
	world._assign_role(1, "exterminator")
	world._apply_roles_to_tokens()
	check(not world.drains._handle_request(1, id, false), "human used drain")
	world._assign_role(1, "cockroach")
	world._apply_roles_to_tokens()
	world.combat.kill_from_environment(1)
	check(not world.drains._handle_request(1, id, false), "ghost used drain")
	world.combat.reset_round()
	await create_timer(0.2).timeout
	await at(false)
	world.food_carry._effects[1] = {"frozen": 2.0}
	check(not world.drains._handle_request(1, id, false), "frozen bug used drain")
	world.food_carry.reset_round()
	# Real late client sees host travel, then sends its own loaded round trip.
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://scripts/tools/drain_travel_test.gd", "--", "--drain-client"])
	if dev: args.append("--devmap")
	child = OS.create_process(OS.get_executable_path(), args + net.get_local_test_arguments())
	check(await until(func() -> bool: return world.get_ready_peer_ids().size() == 2, 15000), "client failed to join")
	var peers: Array = world.get_ready_peer_ids()
	peers.erase(1)
	if not peers.is_empty():
		var peer := int(peers[0])
		await at(false)
		check(world.drains._handle_request(1, id, false), "host network travel failed")
		await create_timer(0.4).timeout
		probe.reply = {}
		probe.inspect.rpc_id(peer, arrival(true), 0)
		check(await until(func() -> bool: return not probe.reply.is_empty()), "inspect timeout")
		check(probe.reply.get("pose", false) and probe.reply.get("cargo", false) and probe.reply.get("camera", false), "remote pose/cargo/camera wrong")
		probe.reply = {}
		probe.forbidden.rpc_id(peer, id)
		check(await until(func() -> bool: return not probe.reply.is_empty()), "rejection timeout")
		check(probe.reply.get("unchanged", false), "host accepted distant client request")
		own.position += Vector3(0.4, 0, 0)
		await create_timer(1.05).timeout
		probe.reply = {}
		probe.round_trip.rpc_id(peer)
		check(await until(func() -> bool: return not probe.reply.is_empty(), 7000), "client trip timeout")
		check(probe.reply.get("travel", false) and probe.reply.get("cargo", false) and probe.reply.get("camera", false), "owner client round trip failed")
		var remote: CharacterBody3D = world.players.get_node(str(peer))
		check(await until(func() -> bool: return remote.position.distance_to(arrival(false)) < 0.03), "client return did not replicate")
		await at(true)
		check(not world.drains._handle_request(1, id, true), "exit occupied by another player accepted")
	# A stale approved trip must not undo an ordinary round reset.
	var old_epoch: int = world.drains._epoch
	world._reset_to_waiting()
	await at(false)
	world.drains._approve(old_epoch, 99999, id, false)
	check(own.position.distance_to(arrival(false)) < 0.025, "old approval survived reset")
	check(world.drains._reservations.is_empty() and world.drains._cooldowns.is_empty(), "reset leaked drain state")
	world._match_phase = 3
	check(not world.drains._handle_request(1, id, false), "results allowed travel")
	if child > 0 and OS.is_process_running(child): OS.kill(child)
	multiplayer_poll = false
	world.free()
	net.leave()
	for failure: String in failures: printerr("DRAIN FAIL: " + failure)
	print("DRAIN TRAVEL TEST: ", "PASS" if failures.is_empty() else "FAIL", " (dev)" if dev else " (diner)")
	quit(0 if failures.is_empty() else 1)
func arrival(outside: bool) -> Vector3:
	return route.endpoint(outside).get_node("Arrival").global_position
func at(outside: bool) -> void:
	own.travel_through_drain(arrival(outside), 0)
	await create_timer(0.15).timeout
func until(predicate: Callable, milliseconds: int = 2500) -> bool:
	var end := Time.get_ticks_msec() + milliseconds
	while Time.get_ticks_msec() < end:
		if predicate.call(): return true
		await process_frame
	return predicate.call()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
