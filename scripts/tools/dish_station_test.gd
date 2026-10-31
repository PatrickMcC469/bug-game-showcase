extends SceneTree
## Production geometry and actual owner climbing, with one real carried snack.
## Run again with -- --devmap to validate the reusable dev-room fixture.
var failures: Array[String] = []
var world: Node3D
var token: CharacterBody3D

func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.get_node("GameState").set_local_role_preference("cockroach")
	var net := root.get_node("Net")
	if not net.host_local_test(): quit(1); return
	world = load("res://scenes/game/game_world.tscn").instantiate()
	var dev := "--devmap" in OS.get_cmdline_user_args()
	if dev:
		world.get_node("DinerKitchen").free()
		var map: Node3D = load("res://scenes/game/maps/dev_room_map.tscn").instantiate()
		map.name = "DinerKitchen"
		world.add_child(map)
		map.owner = world
		map.unique_name_in_owner = true
	world.prototype_round_duration = 600
	root.add_child(world)
	await frames(20)
	token = world.players.get_node("1")
	var station: Node3D = world.get_node("DinerKitchen/climbing/CommercialDishStation" if dev else "DinerKitchen/DishPit/CommercialDishStation")
	var spots := station.get_node("ClimbPoints").get_children()
	check(spots.size() == 3, "expected three distinct routes")
	check(station.scene_file_path == "res://scenes/game/props/commercial_dish_station.tscn", "station is not a reusable instance")
	# The two bowls are actual recesses. The ray must hit their bottoms, not a
	# solid slab across the visible opening; the washer must stay solid too.
	for x: float in [-0.76, -0.01]:
		var hit := ray(station, Vector3(x, 1.16, 0.12), Vector3(x, 0.70, 0.12))
		check(not hit.is_empty() and absf(hit.position.y - 0.785) < 0.003, "basin opening/bottom mismatch")
	check(not ray(station, Vector3(0.92, 0.6, 0.8), Vector3(0.92, 0.6, 0)).is_empty(), "washer front lacks collision")
	if not dev:
		check(world.get_node("DinerKitchen/DishPit/DishTable/ScrapOnTop").global_position.distance_to(Vector3(4.93, 1.081, 2.415)) < 0.001, "dish-table top food moved")
		check(world.get_node("DinerKitchen/DishPit/DishTable/ScrapUnder").global_position.distance_to(Vector3(6.43, 0.001, 2.565)) < 0.001, "dish-table under food moved")
		check(not world.has_node("DinerKitchen/DishPit/SinkLine") and not world.has_node("DinerKitchen/Atmosphere/FixtureBatches/DishPitBaked"), "retired sink/cached render remains")
	# Use the public host-owned pickup path rather than setting cargo_count.
	for loaded: bool in [false, true]:
		if loaded:
			token.set_physics_process(false)
			var food: Dictionary = world.food_run.get_food_records()[0]
			token.position = food.pos + Vector3.UP * 0.002
			await frames(20)
			world.food_run.request_action("grab", int(food.id))
			await frames(20)
			check(token.cargo_count == 1, "one-item pickup failed")
			token.set_physics_process(true)
		for spot: Node3D in spots:
			for down: bool in [false, true]:
				await at(spot.endpoint(down))
				var label := "%s %s %s" % [spot.name, "down" if down else "up", "loaded" if loaded else "empty"]
				var accepted: bool = token.climber.request_climb()
				check(accepted, "cannot start " + label)
				if not accepted:
					printerr("START DETAIL: ", label, " position=", token.position, " target=", spot.endpoint(down), " floor=", token.is_on_floor(), " nearest=", token.climber.nearest_spot(), " clear=", token.climber._path_clear(spot.route_points(down), spot.route_normals(down)))
					continue
				var ticks := 0
				while token.climber.active and ticks < 600:
					await physics_frame
					ticks += 1
				await frames(8)
				check(not token.climber.active and token.position.distance_to(spot.endpoint(not down)) < 0.03, "failed landing " + label + " at " + str(token.position))
				check(token.camera_rig.global_basis.y.dot(Vector3.UP) > 0.999, "camera rolls " + label)
				if loaded: check(token.cargo_count == 1, "food lost " + label)
		# A continuous low path remains through both the sink and raised washer.
		token.set_physics_process(false)
		for x: float in [-1.25, 0.92]:
			token.global_position = station.to_global(Vector3(x, 0.002, 0.7))
			check(not token.test_move(token.global_transform, station.to_global(Vector3(x, 0.002, -0.20)) - token.global_position, null, token.safe_margin), "under-station path blocked: " + str(x))
		token.set_physics_process(true)
	# Existing human collision must fit the customer-facing aisle, but cannot
	# activate any of the bug-only routes.
	world._assign_role(1, "exterminator")
	world._apply_roles_to_tokens()
	await at(station.to_global(Vector3(-0.385, 0.002, 1.6)))
	var contact := KinematicCollision3D.new()
	var blocked := token.test_move(token.global_transform, station.global_basis * Vector3(0, 0, -0.65), contact, token.safe_margin)
	check(not blocked, "human aisle blocked: " + str(contact.get_collider().get_path() if blocked else "clear"))
	check(not token.climber.request_climb(), "human accepted a bug climb")
	for failure: String in failures: printerr("DISH STATION FAIL: " + failure)
	print("DISH STATION TEST: ", "PASS" if failures.is_empty() else "FAIL", " (dev)" if dev else " (diner)")
	world.free()
	net.leave()
	quit(0 if failures.is_empty() else 1)

func ray(station: Node3D, from: Vector3, to: Vector3) -> Dictionary:
	return world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(station.to_global(from), station.to_global(to), 1))
func at(point: Vector3) -> void:
	token.climber.cancel()
	token.surface_crawler.cancel()
	token.position = point + Vector3.UP * 0.002
	token.velocity = Vector3.ZERO
	await frames(25)
func frames(count: int) -> void:
	for index: int in count: await physics_frame
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
