extends SceneTree
const Gas := preload("res://scripts/game/gas_weapon.gd")
var failures: Array[String] = []
var world: Node3D
var token: CharacterBody3D
var gas: Node

func _initialize() -> void:
	create_timer(65).timeout.connect(func() -> void: printerr("GAS TEST TIMEOUT"); quit(1))
	_run.call_deferred()

func _run() -> void:
	var net := root.get_node("Net")
	root.get_node("GameState").set_local_role_preference("exterminator")
	if not net.host_local_test(): quit(1); return
	world = load("res://scenes/game/game_world.tscn").instantiate()
	root.add_child(world)
	await _frames(5)
	gas = world.gas_weapon
	gas._input_left = INF
	token = world.players.get_node("1")
	_check(gas._station != null, "truck has no refill station")
	if gas._station == null: quit(1); return
	_check(not gas._handle_action(1, "dock"), "remote pickup allowed")
	var dock: Vector3 = gas._station.get_node("Control").global_position - Vector3.UP
	token.position = dock
	token.velocity = Vector3.ZERO
	await _frames(20)
	_check(gas.can_dock(1), "truck cradle not physically reachable: " + str(token.position))
	token.shotgun.recoil_phase = 1
	_check(not gas._handle_action(1, "dock"), "swapped at truck during shotgun tumble")
	token.shotgun.cancel_recoil()
	_check(gas._handle_action(1, "dock"), "full gun pickup failed")
	_check(gas.is_selected(1), "pickup did not select gas")
	_check(not token.shotgun.request_fire(), "LMB fired shotgun while gas selected")
	_check(not token.shotgun._approve_request(1, 999, 0), "host approved hidden shotgun")
	_check(world.combat.fire_shot(1, 999, 0, Vector3.FORWARD).is_empty(), "combat bypassed equipment gate")
	_check(not gas._handle_spray(44, true, Vector3.FORWARD), "noncarrier sprayed")
	_check(not gas._handle_spray(1, true, Vector3(NAN, 0, 0)), "nonfinite aim accepted")
	_check(not gas._handle_spray(1, true, Vector3(2, 0, 0)), "nonunit aim accepted")
	token.position = Vector3(4, 0.001, 0)
	token.velocity = Vector3.ZERO
	await _frames(5)
	gas._handle_spray(1, true, Vector3.FORWARD)
	await _frames(12)
	_check(gas.get_state().warming and not gas.get_state().spraying, "warmup absent")
	_check(gas.movement_scale(1) < 0.2, "spray lacks escape-enabling slowdown")
	await _frames(24)
	_check(not gas.get_state().spraying and not gas.get_state().warming, "stale trigger never expired")
	var start := token.position
	token.camera_rig.rotation = Vector3.ZERO
	Input.action_press("move_right")
	await _spray(60)
	Input.action_release("move_right")
	_check(token.position.x - start.x > 0.4 and token.position.x - start.x < 1.2, "actual spray movement speed wrong")
	var spent: float = gas.get_state().fuel
	_check(spent < 6.8 and spent > 6.3, "fuel consumption is not real-time: %f" % spent)
	gas._handle_spray(1, false, Vector3.FORWARD)
	await _frames(40)
	_check(is_equal_approx(float(gas.get_state().fuel), spent), "carried gun refilled")
	_check(not gas._handle_action(1, "shotgun"), "switched to shotgun away from truck")
	_check(not gas._handle_action(1, "gas"), "legacy weapon selector accepted")
	_check(not gas._handle_action(1, "dock"), "swapped away from truck")
	_check(gas.is_selected(1) and not token.shotgun.request_fire(), "carried a usable second weapon")
	await _spray(500)
	_check(float(gas.get_state().fuel) <= 0.001 and not gas.get_state().spraying, "empty tank kept firing")
	_check(not gas._handle_action(1, "dock"), "distant refill accepted")
	token.position = dock
	token.velocity = Vector3.ZERO
	await _frames(20)
	_check(gas._handle_action(1, "dock"), "return to cradle failed")
	_check(int(gas.get_state().carrier) == 0, "docked gun still carried")
	_check(not gas.is_selected(1), "returning gas did not restore shotgun")
	_check(not gas._handle_spray(1, true, Vector3.FORWARD), "returned gun still sprayed")
	_check(token.shotgun.request_fire(), "truck swap did not restore usable shotgun")
	token.shotgun.cancel_recoil()
	await _frames(180)
	var charge: float = gas.get_state().fuel
	_check(charge > 1.8 and charge < 2.2, "12-second refill rate wrong: %f" % charge)
	_check(not gas._handle_action(1, "dock"), "partly charged gun could be taken")
	await _frames(555)
	_check(gas._handle_action(1, "dock"), "fully charged gun unavailable")
	await _frames(20)
	world._assign_role(1, "cockroach")
	world._apply_roles_to_tokens()
	_check(not gas._handle_spray(1, true, Vector3.FORWARD), "bug sprayed")
	_check(not gas._handle_action(1, "dock"), "bug used truck weapon")
	await _frames(3)
	_check(int(gas.get_state().carrier) == 0, "role change stranded gun")
	world._assign_role(1, "exterminator")
	world._apply_roles_to_tokens()
	gas.reset_weapon()
	world._match_phase = 3
	_check(not gas._handle_action(1, "dock"), "post-round pickup allowed")
	world.queue_free()
	await process_frame
	net.leave()
	for failure: String in failures: printerr("GAS WEAPON FAIL: " + failure)
	print("GAS WEAPON TEST: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _spray(frames: int) -> void:
	for i: int in frames:
		if i % 6 == 0: gas._handle_spray(1, true, Vector3.FORWARD)
		await physics_frame

func _frames(count: int) -> void:
	for i: int in count: await physics_frame

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
