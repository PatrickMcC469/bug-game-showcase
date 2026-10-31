extends Node
## Real-peer assertions for the spawning regression, never used by gameplay.
var world: Node3D
var reply: Dictionary = {}

@rpc("authority", "call_remote", "reliable")
func inspect_trip(peer_id: int) -> void:
	await get_tree().create_timer(0.15).timeout
	var token: Node = world.players.get_node(str(peer_id))
	result.rpc_id(1, {"trip": token.player_role == "exterminator" and token._food_trip > 0})

@rpc("authority", "call_remote", "reliable")
func inspect_carry(expected_id: int, frozen: bool) -> void:
	await get_tree().create_timer(0.15).timeout
	var carry: Node = world.food_carry
	var item: Dictionary = carry.held(1)
	result.rpc_id(1, {"matched": int(item.get("id", -1)) == expected_id,
		"frozen": (float(carry.status(1).get("frozen", 0.0)) > 0) == frozen,
		"model": carry.has_node("Carried_1") == (expected_id >= 0)})

@rpc("authority", "call_remote", "reliable")
func inspect(expected: Array) -> void:
	await get_tree().process_frame
	var supply: Node = world.food_supply
	var rows: Array = supply.get_records()
	var unchanged: bool = rows == expected
	var denied: bool = rows.is_empty() or supply.take_food(int(rows[0].id)).is_empty()
	var names: Array[String] = []
	for model: Node in supply.get_children(): names.append(str(model.name))
	var expected_names: Array[String] = []
	for record: Dictionary in rows: expected_names.append("Food_%d" % int(record.id))
	names.sort()
	expected_names.sort()
	result.rpc_id(1, {"matched": unchanged, "denied": denied, "models": names == expected_names})

@rpc("any_peer", "call_remote", "reliable")
func result(value: Dictionary) -> void:
	if multiplayer.is_server() and world.is_peer_ready(multiplayer.get_remote_sender_id()): reply = value
