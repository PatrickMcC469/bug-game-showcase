extends SceneTree
var failures: Array[String] = []
var world: Node3D
var own: CharacterBody3D
var carry: Node
var net: Node
var probe: Node
var client_pid := -1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	net = root.get_node("Net")
	root.get_node("GameState").set_local_role_preference("cockroach")
	if not net.host_local_test(): quit(1); return
	probe = preload("res://scripts/tools/food_supply_test_peer.gd").new()
	probe.name = "SupplyProbe"
	root.add_child(probe)
	world = load("res://scenes/game/game_world.tscn").instantiate()
	root.add_child(world)
	probe.world = world
	carry = world.food_carry
	own = world.players.get_node("1")
	own.set_physics_process(false)
	await create_timer(0.2).timeout
	_check(await _until(func() -> bool: return world.food_supply.get_records().size() == 12, 3000), "initial food missing")
	var spicy := await _grab_type("spicy_pepper")
	_check(not spicy.is_empty(), "spicy pickup failed")
	if spicy.is_empty(): await _finish(); return
	var second: Dictionary = world.food_supply.get_records()[0]
	await create_timer(0.2).timeout
	_check(not carry._action(1, "grab", int(second.id)), "second new item accepted")
	world.food_run.request_action("grab", 0)
	_check(world.food_run.get_cargo_ids(1).is_empty(), "legacy food bypassed single capacity")
	await create_timer(1.1).timeout
	_check(own._food_speed == 1.25 and world.combat.get_state(1).health < 100, "spicy speed/damage absent")
	world.combat.damage_from_environment(1, 1)
	_check(not carry.held(1).is_empty(), "continuous damage dropped food")
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://scripts/tools/food_supply_test.gd", "--", "--food-client"])
	client_pid = OS.create_process(OS.get_executable_path(), args + net.get_local_test_arguments())
	_check(await _until(func() -> bool: return world.get_ready_peer_ids().size() == 2, 12000), "client did not join")
	await _peer_check(int(spicy.id), false)
	world.combat._damage(1, 1, "kinetic")
	_check(carry.held(1).is_empty(), "kinetic hit did not drop food")
	await create_timer(0.4).timeout
	_check(own._food_speed == 1, "spicy speed survived drop")
	_check(_loose_has(int(spicy.id)), "kinetic drop destroyed food")
	await _peer_check(-1, false)
	await _grab_type("fermented_fruit")
	await create_timer(0.3).timeout
	_check(absf(own._food_wobble) > 0.0001, "tipsy input lacks wobble")
	_check(carry._action(1, "drop", -1), "voluntary drop rejected")
	await process_frame
	_check(own._food_wobble == 0, "tipsy effect survived drop")
	var cold := await _grab_type("frozen_food")
	_check(not cold.is_empty(), "cold pickup failed")
	var profile: Resource = carry._profiles["frozen_food"]
	_check(profile.freeze_after_seconds == 15 and profile.freeze_duration_seconds == 3, "freeze tuning differs from chosen prototype")
	profile.freeze_after_seconds = 0.7
	await create_timer(0.25).timeout
	carry.request_action("drop")
	var early: float = carry.status(1).cold
	await create_timer(0.02).timeout
	_check(early > 0 and float(carry.status(1).cold) > 0, "dropping instantly reset buildup")
	await create_timer(0.25).timeout
	own.position = cold.position + Vector3(0.045, 0.002, 0)
	await create_timer(0.2).timeout
	carry.request_action("grab", int(cold.id))
	_check(await _until(func() -> bool: return carry.immobilized(1), 1800), "cold did not freeze")
	_check(carry.held(1).is_empty() and _loose_has(int(cold.id)), "freezing did not drop food")
	_check(not carry._action(1, "grab", int(cold.id)), "frozen bug picked food up")
	await _peer_check(-1, true)
	_check(await _until(func() -> bool: return not carry.immobilized(1), 4000), "bug never thawed")
	profile.freeze_after_seconds = 15
	var fry := await _grab_type("french_fry")
	_check(not fry.is_empty(), "fry pickup failed")
	await create_timer(0.2).timeout
	_check(carry._slicks.is_empty(), "fry dripped automatically")
	_check(carry._action(1, "grease", -1), "manual grease failed")
	_check(carry._slicks.size() == 1, "manual grease did not create one slick")
	_check(not carry._action(1, "grease", -1), "grease spam bypassed cooldown")
	var peers: Array = world.get_ready_peer_ids()
	peers.erase(1)
	if not peers.is_empty():
		var other_id := int(peers[0])
		world._assign_role(other_id, "exterminator")
		world._apply_roles_to_tokens()
		world._publish_snapshot()
		var other: CharacterBody3D = world.players.get_node(str(other_id))
		other.position = carry._slicks[0].position
		other.velocity = Vector3(1, 0, 0)
		carry._step_slicks(0.01)
		_check(carry.immobilized(other_id), "walking killer did not trip")
		var immunity: float = carry.status(other_id).immune
		carry._step_slicks(0.01)
		_check(carry.status(other_id).immune == immunity, "slick repeatedly extended trip")
		carry._publish()
		probe.reply = {}
		probe.inspect_trip.rpc_id(other_id, other_id)
		_check(await _until(func() -> bool: return not probe.reply.is_empty(), 1500), "trip replication timed out")
		_check(probe.reply.get("trip", false), "owner did not apply the replicated stumble")
	carry.request_action("drop")
	await create_timer(3.2).timeout
	_check(carry._slicks.is_empty(), "grease did not expire")
	await _grab_type("spicy_pepper")
	world.combat.kill_from_environment(1)
	_check(world.combat.is_ghost(1) and carry.held(1).is_empty(), "death retained item")
	world._reset_to_waiting()
	await process_frame
	_check(carry._held.is_empty() and carry._slicks.is_empty() and own._food_speed == 1, "round reset leaked carry/effects")
	await _finish()

func _grab_type(type_id: String) -> Dictionary:
	world.combat.reset_round()
	carry.drop(1)
	await create_timer(0.3).timeout
	for record: Dictionary in world.food_supply.get_records():
		if record.type != type_id: continue
		own.position = record.position + Vector3(0.045, 0.002, 0)
		own.velocity = Vector3.ZERO
		await physics_frame
		await process_frame
		if carry._action(1, "grab", int(record.id)):
			await process_frame
			return record
	return {}

func _peer_check(id: int, frozen: bool) -> void:
	var peers: Array = world.get_ready_peer_ids()
	peers.erase(1)
	if peers.is_empty(): return
	probe.reply = {}
	probe.inspect_carry.rpc_id(int(peers[0]), id, frozen)
	_check(await _until(func() -> bool: return not probe.reply.is_empty(), 2500), "carry probe timed out")
	_check(probe.reply.get("matched", false) and probe.reply.get("frozen", false) and probe.reply.get("model", false), "client carry/effect/model differs")

func _loose_has(id: int) -> bool:
	for record: Dictionary in world.food_supply.get_records():
		if int(record.id) == id: return true
	return false

func _until(check: Callable, timeout: int) -> bool:
	var end := Time.get_ticks_msec() + timeout
	while not check.call() and Time.get_ticks_msec() < end: await process_frame
	return bool(check.call())

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _finish() -> void:
	if client_pid > 0 and OS.is_process_running(client_pid): OS.kill(client_pid)
	multiplayer_poll = false
	world.free()
	probe.free()
	net.leave()
	for failure: String in failures: printerr("FOOD CARRY FAIL: ", failure)
	print("FOOD CARRY TEST: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
