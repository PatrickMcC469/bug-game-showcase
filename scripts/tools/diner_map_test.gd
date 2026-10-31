extends SceneTree
## Real collision and interaction checks against the playable diner scene.
const Layout := preload("res://scripts/game/diner_layout.gd")
const RoachScale := preload("res://scripts/game/roach_scale.gd")
var _failures: Array[String] = []
var _world: Node3D
var _token: CharacterBody3D

func _initialize() -> void:
	_test.call_deferred()

func _test() -> void:
	var net := root.get_node("Net")
	root.get_node("GameState").set_local_role_preference("cockroach")
	if not net.host_local_test():
		printerr("DINER MAP TEST: could not host")
		quit(1)
		return
	_world = load("res://scenes/game/game_world.tscn").instantiate()
	_world.prototype_round_duration = 600
	root.add_child(_world)
	await _frames(5)
	_token = _world.players.get_node("1")
	var run: Node = _world.food_run
	var cart: AnimatableBody3D = _world.serving_cart
	_check(cart.position.is_equal_approx(Layout.point(Vector3(9, 0, -3))), "cart did not start at its north dock")
	_check(run.get_food_records().size() == 12, "diner changed finite food count")

	var floor_mesh: MeshInstance3D = _world.get_node("DinerKitchen/Room/Floor/Mesh")
	_check(floor_mesh.mesh.get_aabb().size.x < 16.3 and floor_mesh.mesh.get_aabb().size.z < 13.6, "room retained its oversized footprint")
	_check(cart.scale.is_equal_approx(Vector3.ONE), "cart physics root was scaled")
	_check_cart_clutter_clearance(cart)
	_check_floor_connectivity(run)
	for label: Label3D in _world.get_node("DinerKitchen").find_children("*", "Label3D", true, false):
		_check("ExterminatorTruck" in str(label.get_path()), "loose map label remains: " + str(label.get_path()))
	# Production fallen tray: approach in its own rotated frame and finish on
	# top. This failed when its visible mesh had no collision at all.
	var tray: Node3D = _world.get_node("DinerKitchen/DishPit/FallenTray")
	_place(tray.to_global(Vector3(0, -0.0115, 0.60)))
	_token.camera_rig.rotation.y = tray.rotation.y
	await _walk("move_forward", 75)
	_check(_token.position.y > 0.025 and _token.position.y < 0.032, "roach passed through fallen tray: " + str(_token.position))
	_place(Vector3(-10.8, 0.002, -4.5))

	# Repeated role application must preserve the actual body size on each peer.
	var dimensions := AABB()
	var first := true
	for path: String in ["BodyRoot/ElytronLeft", "BodyRoot/ElytronRight", "BodyRoot/Head"]:
		var mesh := _token.cockroach_model.get_node(path) as MeshInstance3D
		var bounds: AABB = _token.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		dimensions = bounds if first else dimensions.merge(bounds)
		first = false
	_check(dimensions.size.z > 0.035 and dimensions.size.z < 0.055, "roach body is not approximately 4–5 cm")
	_check(_token.roach_collision.shape.radius < 0.015, "roach retained a giant collision capsule")
	_check(_token.scale.is_equal_approx(Vector3.ONE), "CharacterBody root must remain unscaled")
	await _frames(90)
	_check(absf(_token.position.y) < 0.0015, "small roach sinks into or floats above the floor: %s" % _token.position)

	# Kitchen ramps are intentionally absent; test actual new door thresholds.
	for path: String in ["PrepLine/PrepBoardRamp", "DishPit/DishTrayRamp", "ServingCart/LoadingRamp", "ServingCart/LoadingRampCollision"]:
		_check(_world.get_node("DinerKitchen").get_node_or_null(path) == null, "retired kitchen ramp remains: " + path)
	for role: String in ["cockroach", "exterminator"]:
		_world._assign_role(1, role)
		_world._apply_roles_to_tokens()
		# Test across the doorway, not only its center: a tall cabinet formerly
		# pinched the kitchen approach along the west side of the opening.
		for x: float in [5.7, 6.2, 6.7]:
			_place(Vector3(x, 0.002, -5.2))
			await _walk("move_forward", 360 if role == "cockroach" else 90)
			_check(_token.position.z < -7.0, "%s rear-door approach blocked at x=%.1f" % [role, x])
		_place(Vector3(-7.6, 0.002, -2))
		await _walk("move_left", 220 if role == "cockroach" else 60)
		_check(_token.position.x < -8.6, role + " cannot enter walk-in pantry")
		_place(Vector3(0, 0.002, 12.6))
		await _walk("move_back", 220 if role == "cockroach" else 60)
		_check(_token.position.z > 13.5, role + " cannot use front entrance")
		if role == "exterminator":
			_place(Vector3(4.8, 0.002, -12.2))
			await _walk("move_left", 130)
			_check(_token.position.y > 0.7 and _token.position.x < 1.6, "parked truck workshop entrance is obstructed")
	_world._assign_role(1, "cockroach")
	_world._apply_roles_to_tokens()
	_place(Vector3(-5.5, 0.002, 7.8))
	await _walk("move_back", 230)
	_check(_token.position.z > 9.0, "roach cannot crawl under dining table")
	# The delivery pallet has real separated runners, not a solid box under
	# its scanned crates. Protect the new sheltered route at insect scale.
	_place(Vector3(-7.6, 0.002, -8.34))
	await _walk("move_right", 280)
	_check(_token.position.x > -6.1, "delivery pallet blocks its low crosswise crawl route")
	_place(Vector3(-11.75, 0.002, -2.5))
	await _walk("move_forward", 230)
	_check(_token.position.z < -3.5, "roach cannot crawl beneath dry-goods shelving")
	# The removed desk must no longer leave invisible collision in its footprint.
	_check(_world.get_node("DinerKitchen/CounterAndNest").get_node_or_null("CounterTop") == null, "oversized desk remains")
	_world._assign_role(1, "exterminator")
	_world._apply_roles_to_tokens()
	_place(Vector3(-3.15, 0.002, -1.485))
	await _walk("move_left", 65)
	_check(_token.position.x < -4.5, "removed desk left blocking collision")
	_world._assign_role(1, "cockroach")
	_world._apply_roles_to_tokens()
	_place(Vector3(-5.1, 0.002, -0.6))
	await _walk("move_back", 250)
	_check(_token.position.z > 0.7, "new prep bench blocks its crawl route")
	_world._assign_role(1, "exterminator")
	_world._apply_roles_to_tokens()
	_place(Vector3(-5.1, 0.002, -0.8))
	await _walk("move_back", 65)
	_check(_token.position.z < -0.3, "human passes through new prep bench")
	_world._assign_role(1, "cockroach")
	_world._apply_roles_to_tokens()
	# Crawl through the new rack; a human has to go around its shelves.
	_place(Vector3(-0.9, 0.002, 1.6))
	await _walk("move_back", 260)
	_check(_token.position.z > 2.8, "new service rack's roach shortcut is blocked")
	_world._assign_role(1, "exterminator")
	_world._apply_roles_to_tokens()
	_place(Vector3(-0.9, 0.002, 1.6))
	await _walk("move_back", 60)
	_check(_token.position.z < 1.97, "human passed through service rack")
	_world._assign_role(1, "cockroach")
	_world._apply_roles_to_tokens()

	# Every original finite pickup must still be individually reachable by the
	# host's real grab validator, including food adjacent to new countertop props.
	for index: int in 12:
		_world._start_round()
		_place(run.get_food_records()[index]["pos"] + Vector3.UP * 0.0025)
		await _frames(18)
		run.request_action("grab", index)
		await _frames(3)
		_check(run.get_cargo_ids(1).has(index), "clutter obstructed pickup %d" % index)
	_world._start_round()

	# Build an actual stack and prove the extra clearance blocks that same route.
	for index: int in 3:
		_place(run.get_food_records()[index]["pos"] + Vector3.UP * (0.1 * RoachScale.GEOMETRY))
		await _frames(18)
		run.request_action("grab", index)
		await _frames(3)
	_check(run.get_cargo_ids(1).size() == 3, "could not collect floor and countertop snacks")
	_place(Vector3(-0.9, 0.002, 1.6))
	await _walk("move_back", 60)
	_check(_token.position.z < 1.97, "full stack clipped through rack shelf")
	_place(_world.home_base.position + Vector3.UP * (3.4 * Layout.SCALE))
	await _frames(90)
	_check(_world.get_food_delivered() == 0, "food banked through the counter roof")
	_place(_world.home_base.position + Vector3.UP * 0.002)
	await _frames(150)
	_check(_world.get_food_delivered() == 6, "walk-in pantry home cannot unload")

	_world._start_round()
	_place(Vector3.ZERO)
	_check(not cart._handle_request(1), "distant cart activation accepted")
	_check(not cart._handle_request(444), "unready cart sender accepted")
	_place(cart.get_interaction_position(1) + Vector3(0, 0.002, 0.06))
	await _frames(3)
	_check(cart._handle_request(1), "nearby cart activation rejected")
	_check(not cart._handle_request(1), "cart reversal spam accepted")
	_world._assign_role(1, "exterminator")
	_world._apply_roles_to_tokens()
	_place(Layout.point(Vector3(9, 0.02, 1.0)))
	await _frames(70)
	_check(cart.get_state()["blocked"], "cart did not pause for a player in its path")
	_place(Layout.point(Vector3(0, 0.03, 0)))
	await _frames(310)
	_check(absf(cart.position.z - Layout.CART_SOUTH) < 0.02, "cart did not reach dish dock after path cleared")

	_world._assign_role(1, "cockroach")
	_world._apply_roles_to_tokens()
	# Land a dropped snack on the actual moving deck and transport it back.
	_place(run.get_food_records()[0]["pos"] + Vector3.UP * (0.1 * RoachScale.GEOMETRY))
	await _frames(20)
	run.request_action("grab", 0)
	await _frames(20)
	_place(cart.position + Layout.point(Vector3(0, 2.42, 0.5)))
	_token.cockroach_model.rotation.y = 0
	await _frames(4)
	run.request_action("drop", -1, Vector3.FORWARD)
	_place(Vector3.ZERO)
	await _frames(120)
	var food: Dictionary = run.get_food_records()[0]
	_check(food["state"] == 0 and food["pos"].y > 2.4 * Layout.SCALE, "dropped snack did not settle on cart")
	var offset: Vector3 = food["pos"] - cart.position
	_place(cart.get_interaction_position(1) + Vector3(0, 0.002, 0.06))
	await _frames(4)
	_check(cart._handle_request(1), "return cart request failed")
	_place(cart.position + Layout.point(Vector3(0, 2.42, 0)))
	await _frames(310)
	food = run.get_food_records()[0]
	_check((food["pos"] - cart.position).distance_to(offset) < 0.1, "snack did not travel with cart")
	_check(_token.position.y > 2.2 * Layout.SCALE and absf(_token.position.z - cart.position.z) < 1.6 * Layout.SCALE, "roach rider was not carried to the hot line")
	_world._reset_to_waiting()
	_check(not cart._handle_request(1), "cart moved outside a live round")
	_check(cart.position.is_equal_approx(Layout.point(Vector3(9, 0, -3))), "cart reset leaked prior round position")
	for failure: String in _failures:
		printerr("DINER MAP FAIL: " + failure)
	print("DINER MAP TEST: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	_world.queue_free()
	await process_frame
	net.leave()
	quit(0 if _failures.is_empty() else 1)

func _place(at: Vector3) -> void:
	_token.position = at
	_token.velocity = Vector3.ZERO
	_token.camera_rig.rotation.y = 0

func _walk(action: String, count: int) -> void:
	Input.action_press(action)
	await _frames(ceili(count * Layout.SCALE))
	Input.action_release(action)
	await _frames(3)

func _walk_slope(action: String, count: int, label: String) -> void:
	var unsupported := 0
	var misaligned := 0
	var bad_contact := 0
	Input.action_press(action)
	for frame: int in ceili(count * Layout.SCALE):
		await physics_frame
		if not _token.is_on_floor():
			unsupported += 1
		var query := PhysicsRayQueryParameters3D.create(
			_token.position + Vector3.UP * 0.05,
			_token.position - Vector3.UP * 0.05, _token.collision_mask, [_token.get_rid()])
		var hit := _token.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			bad_contact += 1
			continue
		var normal: Vector3 = hit["normal"]
		var up: Vector3 = _token.cockroach_model.basis.y.normalized()
		var capsule_axis: Vector3 = _token.roach_collision.basis.y.normalized()
		if up.dot(normal) < 0.999 or absf(capsule_axis.dot(normal)) > 0.001:
			misaligned += 1
		if absf(_token.position.y - hit["position"].y) > 0.0015:
			bad_contact += 1
	Input.action_release(action)
	await _frames(3)
	_check(unsupported == 0, "%s lost floor contact for %d frames" % [label, unsupported])
	_check(misaligned == 0, "%s body/capsule missed supporting angle for %d frames" % [label, misaligned])
	_check(bad_contact == 0, "%s body floated or sank for %d frames" % [label, bad_contact])
	_check(_token.camera_rig.global_basis.y.dot(Vector3.UP) > 0.999, "%s rolled the camera rig" % label)

func _frames(count: int) -> void:
	for i: int in count:
		await physics_frame

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _check_cart_clutter_clearance(cart: AnimatableBody3D) -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = 1
	query.exclude = [cart.get_rid(), _token.get_rid()]
	for step: int in 25:
		var z := lerpf(Layout.CART_NORTH, Layout.CART_SOUTH, step / 24.0)
		for child: Node in cart.get_children():
			if not child is CollisionShape3D:
				continue
			query.shape = child.shape
			var pose: Transform3D = child.global_transform
			pose.origin.z += z - cart.position.z
			query.transform = pose
			for hit: Dictionary in cart.get_world_3d().direct_space_state.intersect_shape(query, 32):
				_check(not hit["collider"].is_in_group("diner_clutter"), "new clutter intersects the cart's swept path: %s" % hit["collider"].name)

func _check_floor_connectivity(run: Node) -> void:
	# Conservative 5 cm square footprint on a 10 cm grid, at insect height.
	# Include support up to 4 cm above the floor now that mats/trays are solid.
	# Production controller tests separately exercise those edge transitions.
	var query := PhysicsShapeQueryParameters3D.new()
	var footprint := BoxShape3D.new()
	footprint.size = Vector3(0.05, 0.0215, 0.05)
	query.shape = footprint
	query.collision_mask = 1
	query.exclude = [_token.get_rid()]
	var space := _token.get_world_3d().direct_space_state
	var start := Vector2i(roundi(_world.home_base.position.x * 10), roundi(_world.home_base.position.z * 10))
	var queue: Array[Vector2i] = [start]
	var seen: Dictionary[Vector2i, bool] = {start: true}
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		index += 1
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := cell + direction
			if seen.has(next) or next.x < -138 or next.x > 128 or next.y < -178 or next.y > 168:
				continue
			var at := Vector3(next.x * 0.1, 0.0115, next.y * 0.1)
			var support := space.intersect_ray(PhysicsRayQueryParameters3D.create(
				Vector3(at.x, 0.04, at.z), Vector3(at.x, -0.01, at.z), 1, [_token.get_rid()]))
			if not support.is_empty(): at.y += support.position.y
			query.transform = Transform3D(Basis.IDENTITY, at)
			var clear := space.intersect_shape(query, 1).is_empty()
			seen[next] = clear
			if clear:
				queue.append(next)
	for food: Dictionary in run.get_food_records():
		var pos: Vector3 = food["pos"]
		if pos.y > 0.1:
			continue
		var cell := Vector2i(roundi(pos.x * 10), roundi(pos.z * 10))
		_check(seen.get(cell, false), "floor food lost its route to the pantry: %s" % pos)
	for at: Vector3 in [Vector3(6.2, 0, -8), Vector3(0, 0, 14), Vector3(-10.2, 0, -2), Vector3(0, 0, 10), Vector3(11, 0, 0)]:
		var cell := Vector2i(roundi(at.x * 10), roundi(at.z * 10))
		_check(seen.get(cell, false), "new map area is disconnected from pantry: %s" % at)
