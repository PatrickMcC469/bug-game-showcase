extends SceneTree
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(35).timeout.connect(func() -> void: printerr("AMMO TEST TIMEOUT"); quit(1))
	_run.call_deferred()

func _run() -> void:
	var net := root.get_node("Net")
	root.get_node("GameState").set_local_role_preference("exterminator")
	if not net.host_local_test(): quit(1); return
	var world := load("res://scenes/game/game_world.tscn").instantiate() as Node3D
	root.add_child(world)
	await create_timer(0.2).timeout
	var ammo: Node = world.shotgun_ammo
	var gas: Node = world.gas_weapon
	var token: CharacterBody3D = world.players.get_node("1")
	var gun: Node = token.shotgun
	_check(ammo.shells(1) == 6, "initial shells not six")
	_check(gun.request_fire(), "first real shot failed")
	_check(ammo.shells(1) == 5 and gun.shot_serial == 1, "approved shot did not spend exactly one shell")
	_check(not gun.request_fire() and ammo.shells(1) == 5, "recoil rejection spent ammo")
	gun.cancel_recoil()
	_check(not gun._approve_request(1, 99, 0) and ammo.shells(1) == 5, "cooldown rejection spent ammo")
	for nonce: int in range(2, 7):
		gun._last_host_shot = -10.0
		_check(gun._approve_request(1, nonce, 0, Vector3.UP), "valid shot failed")
	_check(ammo.shells(1) == 0, "six shots did not empty shotgun")
	gun._last_host_shot = -10.0
	gun._next_local_shot = -10.0
	_check(not gun.request_fire(), "empty shotgun fired locally")
	_check(not gun._approve_request(1, 100, 0), "host approved empty shotgun")
	_check(world.combat.fire_shot(1, 100, 0, Vector3.UP).is_empty(), "combat bypassed empty ammo")
	_check(not ammo._begin_reload(1), "reload allowed away from truck")
	var dock: Vector3 = gas._station.get_node("Control").global_position - Vector3.UP
	token.position = dock
	token.velocity = Vector3.ZERO
	await create_timer(0.4).timeout
	_check(ammo._begin_reload(1), "truck reload rejected")
	_check(not gun._approve_request(1, 100, 0), "shot during reload")
	await create_timer(0.25).timeout
	_check(ammo.shells(1) == 0, "shell added before insertion")
	_check(not ammo._begin_reload(1), "duplicate reload restarted animation")
	await create_timer(0.4).timeout
	_check(ammo.shells(1) == 1, "first insertion did not add one shell")
	token.position.x += 0.25
	await create_timer(0.12).timeout
	_check(not ammo.is_reloading(1) and ammo.shells(1) == 1, "walking did not interrupt with partial ammo retained")
	token.position = dock
	token.velocity = Vector3.ZERO
	await create_timer(0.3).timeout
	_check(ammo._begin_reload(1), "partial reload could not resume")
	await create_timer(2.7).timeout
	_check(ammo.shells(1) == 6 and not ammo.is_reloading(1), "reload did not finish at six")
	_check(not ammo._begin_reload(1), "full shotgun reload allowed")
	gun._last_host_shot = -10.0
	_check(gun._approve_request(1, 100, 0, Vector3.UP), "reloaded shotgun could not fire")
	_check(ammo._begin_reload(1), "second partial reload failed")
	_check(gas._handle_action(1, "dock"), "swap to gas failed")
	_check(not ammo.is_reloading(1) and ammo.shells(1) == 5, "swap did not cancel reload / preserve shells")
	_check(not ammo._begin_reload(1) and not ammo.consume_shell(1), "gas carrier used shotgun ammo")
	await create_timer(0.3).timeout
	_check(gas._handle_action(1, "dock") and ammo.shells(1) == 5, "swap back granted free shells")
	world._match_phase = 3
	_check(not ammo._begin_reload(1), "post-result reload allowed")
	ammo.reset_round()
	_check(ammo.shells(1) == 6 and not ammo.is_reloading(1), "round reset did not restore shells")
	world.queue_free()
	await process_frame
	net.leave()
	for failure: String in failures: printerr("AMMO FAIL: " + failure)
	print("SHOTGUN AMMO TEST: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
