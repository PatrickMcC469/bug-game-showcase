extends Node
var world: Node3D
var reply: Dictionary = {}

@rpc("authority", "call_remote", "reliable")
func inspect(expected: int) -> void:
	await get_tree().create_timer(0.15).timeout
	var before: int = world.get_food_delivered()
	world.accept_food_delivery(100)
	result.rpc_id(1, {"score": before == expected and world.get_food_delivered() == before,
		"homes": world.home_returns.points.size()})

@rpc("authority", "call_remote", "reliable")
func haul(home_index: int) -> void:
	var id := multiplayer.get_unique_id()
	var token: CharacterBody3D = world.players.get_node(str(id))
	token.set_physics_process(false)
	var grabbed := false
	for record: Dictionary in world.food_supply.get_records():
		token.global_position = record.position + Vector3(0.045, 0.002, 0)
		token.velocity = Vector3.ZERO
		await get_tree().create_timer(0.3).timeout
		world.food_carry.request_action("grab", int(record.id))
		await get_tree().create_timer(0.3).timeout
		if not world.food_carry.held(id).is_empty():
			grabbed = true
			break
	if grabbed:
		token.global_position = world.home_returns.points[home_index].global_position + Vector3.UP * 0.002
		await get_tree().create_timer(1.0).timeout
	result.rpc_id(1, {"hauled": grabbed and world.food_carry.held(id).is_empty()})

@rpc("any_peer", "call_remote", "reliable")
func result(value: Dictionary) -> void:
	if multiplayer.is_server() and world.is_peer_ready(multiplayer.get_remote_sender_id()): reply = value
