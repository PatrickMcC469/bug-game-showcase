extends SceneTree
## Production map, host timer and real late-joining peer. Run again with -- --devmap.
var failures: Array[String] = []
var world: Node3D
var net: Node
var probe: Node
var child_pid := -1
var connected := false
var client := false
var devmap := false
var child_log := ""

func _initialize() -> void:
	client = "--food-client" in OS.get_cmdline_user_args()
	devmap = "--devmap" in OS.get_cmdline_user_args()
	_run.call_deferred()

func _load_world() -> void:
	world = load("res://scenes/game/game_world.tscn").instantiate()
	if devmap:
		var old: Node = world.get_node("DinerKitchen")
		world.remove_child(old)
		old.free()
		var map: Node = load("res://scenes/game/maps/dev_room_map.tscn").instantiate()
		map.name = "DinerKitchen"
		world.add_child(map)
		map.owner = world
		map.unique_name_in_owner = true
	root.add_child(world)
	probe.world = world

func _run() -> void:
	net = root.get_node("Net")
	root.get_node("GameState").set_local_role_preference("cockroach")
	probe = preload("res://scripts/tools/food_supply_test_peer.gd").new()
	probe.name = "SupplyProbe"
	root.add_child(probe)
	if client:
		net.connected.connect(func() -> void: connected = true)
		if not net.join_local_test() or not await _until(func() -> bool: return connected, 10000):
			quit(1)
			return
		_load_world()
		await create_timer(60).timeout
		quit()
		return
	if not net.host_local_test():
		printerr("FOOD SUPPLY TEST: cannot host")
		quit(1)
		return
	_load_world()
	var supply: Node = world.food_supply
	await physics_frame
	await physics_frame
	_check(await _until(func() -> bool: return supply.get_records().size() == 12, 5000), "initial supply is not twelve")
	_check(supply.refill_seconds == 15.0 and supply.low_count == 3, "default tuning changed")
	var spots: Dictionary = supply.get_spot_positions()
	_check(spots.size() == (16 if devmap else 30), "map markers missing")
	for id: String in spots:
		_check(supply.is_spot_clear(id), "unsupported or obstructed marker: " + id)
	var rows: Array = supply.get_records()
	var occupied := {}
	var types := {}
	for record: Dictionary in rows:
		_check(not occupied.has(record.spot), "two pieces share a spot")
		occupied[record.spot] = true
		types[record.type] = true
	_check(types.size() == 4, "initial wave lacks variety")
	# An occupied position must never be selected for a new piece.
	var own: Node3D = world.players.get_node("1")
	var saved := own.position
	own.position = rows[0].position
	_check(not supply.is_spot_clear(rows[0].spot), "actor does not block spawn")
	own.position = saved
	supply.refill_seconds = 0.2
	for index: int in 8: supply.take_food(int(rows[index].id))
	await create_timer(0.35).timeout
	_check(supply.get_records().size() == 4, "refilled above scarcity threshold")
	supply.set_physics_process(false)
	_check(not supply.take_food(int(rows[8].id)).is_empty(), "host transfer failed")
	_check(supply.take_food(int(rows[0].id)).is_empty(), "same food transferred twice")
	_check(supply.get_records().size() == 3, "depletion failed")
	child_log = "user://food-supply-%d.log" % OS.get_process_id()
	var arguments := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--log-file", ProjectSettings.globalize_path(child_log), "--script", "res://scripts/tools/food_supply_test.gd", "--", "--food-client"])
	if devmap: arguments.append("--devmap")
	child_pid = OS.create_process(OS.get_executable_path(), arguments + net.get_local_test_arguments())
	_check(child_pid > 0, "client process did not start")
	_check(await _until(func() -> bool: return world.get_ready_peer_ids().size() == 2, 16000), "late client not ready")
	await _check_peer()
	supply.refill_seconds = 0.4
	supply.set_physics_process(true)
	await create_timer(0.1).timeout
	_check(supply.get_records().size() == 3, "replenished before cooldown")
	_check(await _until(func() -> bool: return supply.get_records().size() == 12, 3000), "scarcity did not refill")
	_check(supply.get_status().wave == 2, "wave counted incorrectly")
	await _check_peer()
	var wave: int = supply.get_status().wave
	await create_timer(0.6).timeout
	_check(supply.get_status().wave == wave and supply.get_records().size() == 12, "ample supply keeps spawning")
	var stale_id: int = supply.get_records()[0].id
	supply.reset_supply()
	_check(await _until(func() -> bool: return supply.get_records().size() == 12, 2000), "reset did not populate")
	_check(supply.take_food(stale_id).is_empty(), "reset reused a transferable ID")
	await _check_peer()
	var final_rows: Array = supply.get_records()
	for index: int in 9: supply.take_food(int(final_rows[index].id))
	world.call("_finish_round", 3)
	var ended: Array = supply.get_records()
	_check(supply.take_food(int(ended[0].id)).is_empty(), "finished round allows transfer")
	await create_timer(0.5).timeout
	_check(supply.get_records() == ended, "finished round changed food")
	world.call("_reset_to_waiting")
	await create_timer(0.5).timeout
	_check(supply.get_records().is_empty(), "waiting round spawned food")
	if child_pid > 0 and OS.is_process_running(child_pid): OS.kill(child_pid)
	if FileAccess.file_exists(child_log):
		var log_text := FileAccess.get_file_as_string(child_log)
		_check(not log_text.contains("SCRIPT ERROR") and not log_text.contains("\nERROR:"), "client runtime errors: " + log_text)
	multiplayer_poll = false
	world.free()
	probe.free()
	net.leave()
	for failure: String in failures: printerr("FOOD SUPPLY FAIL: ", failure)
	print("FOOD SUPPLY TEST: ", "PASS" if failures.is_empty() else "FAIL", " (", "dev room" if devmap else "diner", ")")
	quit(0 if failures.is_empty() else 1)

func _check_peer() -> void:
	var peers: Array = world.get_ready_peer_ids()
	peers.erase(1)
	if peers.is_empty(): return
	probe.reply = {}
	probe.inspect.rpc_id(int(peers[0]), world.food_supply.get_records())
	_check(await _until(func() -> bool: return not probe.reply.is_empty(), 3000), "peer inspection timed out")
	_check(probe.reply.get("matched", false), "peer snapshot differs from host")
	_check(probe.reply.get("denied", false), "client took host-owned food")
	_check(probe.reply.get("models", false), "client visuals differ from snapshot")

func _until(condition: Callable, timeout: int) -> bool:
	var end := Time.get_ticks_msec() + timeout
	while not condition.call() and Time.get_ticks_msec() < end: await process_frame
	return bool(condition.call())

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
