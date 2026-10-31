extends Node
var world: Node3D
var reply: Dictionary = {}

@rpc("authority", "call_remote", "reliable")
func inspect(expected: Vector3, cargo: int) -> void:
	await get_tree().create_timer(0.2).timeout
	var remote: CharacterBody3D = world.players.get_node("1")
	_respond.rpc_id(1, {"pose": remote.position.distance_to(expected) < 0.03, "cargo": remote.cargo_count == cargo, "camera": not remote.camera.current})

@rpc("authority", "call_remote", "reliable")
func round_trip() -> void:
	var own: CharacterBody3D = world.players.get_node(str(multiplayer.get_unique_id()))
	own.set_physics_process(false)
	var food: Dictionary = world.food_run.get_food_records()[1]
	own.position = food.pos + Vector3.UP * 0.002
	await get_tree().create_timer(0.35).timeout
	world.food_run.request_action("grab", int(food.id))
	await get_tree().create_timer(0.35).timeout
	var route: Node3D = world.get_node("DinerKitchen/DrainRoutes/KitchenDrain")
	var id := str(world.get_path_to(route))
	var cargo: bool = own.cargo_count == 1
	var passed := true
	for outside: bool in [false, true]:
		own.position = route.endpoint(outside).get_node("Arrival").global_position
		own.velocity = Vector3.ZERO
		await get_tree().create_timer(0.4).timeout
		world.drains.request_travel(id, outside)
		await get_tree().create_timer(0.6).timeout
		passed = passed and own.position.distance_to(route.endpoint(not outside).get_node("Arrival").global_position) < 0.025
		await get_tree().create_timer(0.5).timeout
	_respond.rpc_id(1, {"travel": passed, "cargo": cargo and own.cargo_count == 1, "camera": own.camera.current})

@rpc("authority", "call_remote", "reliable")
func forbidden(id: String) -> void:
	var own: Node3D = world.players.get_node(str(multiplayer.get_unique_id()))
	var before := own.position
	# Bypass the friendly local reach check to exercise the real host boundary.
	world.drains._request.rpc_id(1, id, false, world.drains._epoch)
	await get_tree().create_timer(0.25).timeout
	_respond.rpc_id(1, {"unchanged": own.position.distance_to(before) < 0.025})

@rpc("any_peer", "call_remote", "reliable")
func _respond(value: Dictionary) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() > 1: reply = value
