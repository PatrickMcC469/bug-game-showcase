extends SceneTree
## Deterministic host-rule regression coverage independent of rendering or ENet.
const S := preload("res://scripts/game/roach_scale.gd").GEOMETRY
const FoodRun := preload("res://scripts/game/food_run.gd")
var _failures: Array[String] = []
var _world: TestWorld
var _run: Node

class TestToken extends CharacterBody3D:
	var cockroach_model := Node3D.new()
	var cargo_weight := 0.0
	func _init() -> void:
		add_child(cockroach_model)
	func set_cargo(weight: float, _stress: float, _count: int) -> void:
		cargo_weight = weight

class TestSnack extends Area3D:
	var food_kind := 0
	func set_hint(_focus: bool, _scent: bool) -> void:
		pass
	func present(target: Vector3, _angles: Vector3, _carried: bool, _delta: float) -> void:
		global_position = target

class TestWorld extends Node3D:
	var players := Node3D.new()
	var food_items := Node3D.new()
	var home_base := preload("res://scripts/game/home_return_point.gd").new()
	var home_returns := preload("res://scripts/game/home_returns.gd").new()
	var phase := 1
	var delivered := 0
	func _init() -> void:
		add_child(players)
		add_child(food_items)
		add_child(home_base)
		add_child(home_returns)
		home_returns.world = self
		home_returns.points.append(home_base)
		home_base.position = Vector3(-8.0, 0.0, 0.0) * S
	func get_match_phase() -> int:
		return phase
	func get_role_for_peer(peer_id: int) -> String:
		return "exterminator" if peer_id == 3 else "cockroach"
	func get_ready_peer_ids() -> Array:
		# Simulated sender ids use the host validation method; never emit RPCs
		# to synthetic peers. Real two-process requests are covered by smoke.
		return [1]
	func is_peer_ready(peer_id: int) -> bool:
		return peer_id in [1, 2, 3]
	func can_peer_act(_peer_id: int) -> bool:
		# Ghost rejection is exercised with real Combat nodes in its network test.
		return true
	func accept_food_delivery(servings: int) -> void:
		delivered += servings

func _initialize() -> void:
	_test.call_deferred()

func _test() -> void:
	_world = TestWorld.new()
	root.add_child(_world)
	for peer_id: int in [1, 2, 3]:
		var token := TestToken.new()
		token.name = str(peer_id)
		_world.players.add_child(token)
	for index: int in 5:
		var snack := TestSnack.new()
		snack.food_kind = index % 4
		snack.position = Vector3(float(index) * 3.0, 0.32, 0.0) * S
		_world.food_items.add_child(snack)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	ground.add_child(shape)
	ground.position.y = -0.5
	_world.add_child(ground)
	_run = FoodRun.new()
	_world.add_child(_run)
	_run.setup(_world)
	_run.set_physics_process(false)
	_run.set_process(false)
	await physics_frame
	await physics_frame

	_place(1, Vector3(16.0, 0.0, 0.0) * S)
	_check(not _action(1, "grab", 0), "out-of-range grab accepted")
	_place(3, Vector3.ZERO)
	_check(not _action(3, "grab", 0), "exterminator collected food")
	_check(not _action(77, "grab", 0), "unready sender accepted")
	_check(not _action(1, "grab", 999), "invalid food id accepted")
	for index: int in 1:
		_place(1, Vector3(float(index) * 3.0, 0.0, 0.0) * S)
		_check(_action(1, "grab", index), "valid pickup rejected")
		_check(not _run._handle_action(1, "grab", index, Vector3.ZERO), "RPC spam bypassed cooldown")
	_check(_run.get_cargo_ids(1).size() == 1, "single-item inventory did not fill")
	_place(2, Vector3.ZERO)
	_check(not _action(2, "grab", 0), "simultaneous pickup stole owned food")
	_place(1, Vector3(9.0, 0.0, 0.0) * S)
	_check(not _action(1, "grab", 3), "second snack exceeded carry limit")
	_check(_run.get_cargo_weight(1) == 1.0, "weight does not match contents")

	# Drop is top-first and does not consume or duplicate supply.
	_check(_action(1, "drop"), "drop failed")
	_check(_run.get_cargo_ids(1).is_empty(), "drop removed the wrong item")
	_check(_run.get_food_records()[0]["state"] == 2, "drop did not become airborne")
	_step(240)
	_check(_run.get_food_records()[0]["state"] == 0, "dropped snack did not settle")
	_check(_run.get_food_records().size() == 5, "drop changed food supply")

	# A different roach catches a deliberate throw and earns one relay flag.
	_reset()
	_place(1, Vector3.ZERO)
	_check(_action(1, "grab", 0), "relay setup pickup failed")
	_check(_action(1, "throw", -1, Vector3.RIGHT), "throw failed")
	_place(2, Vector3(0.2, 0.0, 0.0) * S)
	_check(_action(2, "grab", 0), "teammate catch failed")
	_check(_run.get_food_records()[0]["relay"], "catch did not attach relay credit")
	_place(2, _world.home_base.position)
	_run._motion[2] = {"speed": 0.0, "turn": 0.0}
	for step: int in 40:
		_run._update_load(2, 1.0 / 60.0)
	_check(_world.delivered == 2, "relay delivery should bank sugar + one bonus")
	_run._bank(_run._foods[0], true)
	_check(_world.delivered == 2, "duplicate bank changed score")
	_check(not _action(2, "grab", 0), "banked food could be recollected")

	# Ballistic pantry shot, tested against an actual physics floor.
	_reset()
	_place(1, Vector3.ZERO)
	_check(_action(1, "grab", 0), "airmail setup failed")
	_place(1, Vector3(-8.0, 0.0, 8.0) * S)
	_check(_action(1, "throw", -1, Vector3.FORWARD), "airmail launch failed")
	_step(180)
	_check(_world.delivered == 2 and _run.get_stats()["airmail"] == 1, "long shot did not score once with bonus")

	# A single carried item is stable during a sharp turn.
	_reset()
	for index: int in 1:
		_place(1, Vector3(float(index) * 3.0, 0.0, 0.0) * S)
		_action(1, "grab", index)
	_run._motion[1] = {"speed": 10.0, "turn": 6.0}
	for step: int in 45:
		_run._update_load(1, 1.0 / 60.0)
	_check(_run.get_stats()["spills"] == 0 and _run.get_cargo_ids(1).size() == 1, "single carried item spilled during a turn")
	_run._motion[1] = {"speed": 0.0, "turn": 0.0}
	for step: int in 300:
		_run._update_load(1, 1.0 / 60.0)
	_check(_run.get_stress(1) < 0.01, "stationary load did not recover")

	# Disconnect releases cargo; expiry freezes interactions and scoring.
	_run.release_peer(1)
	_check(_run.get_cargo_ids(1).is_empty(), "disconnect retained ownership")
	_step(240)
	for food: Dictionary in _run.get_food_records():
		_check(food["carrier"] == 0, "orphaned food carrier after disconnect")
	_world.phase = 3
	var before := _world.delivered
	_check(not _action(1, "grab", 4), "pickup accepted after time expired")
	_run._bank(_run._foods[4], true)
	_check(_world.delivered == before, "food scored after time expired")

	# Late motion from an earlier revision cannot resurrect a consumed item.
	_run._foods[4]["state"] = 3
	var original_position: Vector3 = _run._foods[4]["pos"]
	_run._receive_motion(_run._revision - 1, 999, [[4, Vector3(99, 99, 99), Vector3.ONE]], {}, {})
	_check(_run._foods[4]["pos"] == original_position and _run._foods[4]["state"] == 3, "stale flight packet overwrote banked food")
	await _check_stack_edges()
	_world.free()
	if _failures.is_empty():
		print("FOOD RULES TEST: PASS")
	else:
		for failure: String in _failures:
			printerr("FOOD RULES FAIL: ", failure)
	quit(0 if _failures.is_empty() else 1)

func _reset() -> void:
	_world.phase = 1
	_world.delivered = 0
	_run.reset_food()

func _check_stack_edges() -> void:
	_reset()
	for index: int in 1:
		_place(1, Vector3(float(index) * 3.0, 0.0, 0.0) * S)
		_check(_action(1, "grab", index), "release setup failed")
	var positions: Array[Vector3] = []
	for id: int in _run.get_cargo_ids(1):
		positions.append(_run._cargo_position(_run._foods[id]))
	_run.release_peer(1)
	for index: int in positions.size():
		_check((_run._foods[index].pos as Vector3).is_equal_approx(positions[index]),
			"releasing a stack moved an upper snack into the lower snack")

	# A center ray fits beside this overhang, but the actual stack does not.
	_reset()
	_place(1, Vector3.ZERO)
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.006, 0.02, 0.04)
	collision.shape = box
	body.add_child(collision)
	_world.add_child(body)
	body.position = Vector3(0.007, 0.025, 0)
	await physics_frame
	await physics_frame
	_check(not _action(1, "grab", 0), "pickup expanded the stack into an adjacent overhang")
	body.free()
	await physics_frame
	_check(_action(1, "grab", 0), "clear stack pickup rejected after overhang removed")

func _place(peer_id: int, at: Vector3) -> void:
	(_world.players.get_node(str(peer_id)) as Node3D).position = at

func _action(peer_id: int, action: String, food_id: int = -1, direction: Vector3 = Vector3.ZERO) -> bool:
	_run._clock += 0.2
	return _run._handle_action(peer_id, action, food_id, direction)

func _step(frames: int) -> void:
	for frame: int in frames:
		_run._physics_process(1.0 / 60.0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
