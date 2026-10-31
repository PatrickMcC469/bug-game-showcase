extends "res://scripts/game/solo_test.gd"
## Isolated mechanic fixtures with the normal host and a real client-owned peer.
const Catalog := preload("res://scripts/game/dev_room_catalog.gd")
const ROOM_PATH := "res://scenes/game/dev_room.tscn"
var play_as_roach := true
var _catch_until := 0
var _return_at := 0

func _ready() -> void:
	bot_paused = true
	super._ready()

func create_test_world() -> Node3D:
	var result := WORLD_SCENE.instantiate() as Node3D
	var original := result.get_node("DinerKitchen")
	result.remove_child(original)
	original.free()
	var map := load("res://scenes/game/maps/dev_room_map.tscn").instantiate() as Node3D
	map.name = "DinerKitchen"
	result.add_child(map)
	map.owner = result
	map.unique_name_in_owner = true
	result.get_node("FoodRun").recovery_bounds = AABB(Vector3(-16, -3, -6), Vector3(42, 100, 40))
	return result

func get_scene_path() -> String:
	return ROOM_PATH

func get_scenario_titles() -> Array[String]:
	return Catalog.titles()

func get_lab_title() -> String:
	return "MECHANICS DEV ROOM"

func get_instruction() -> String:
	return Catalog.STATIONS[scenario].help

func get_scenario_setup() -> Dictionary:
	var station: Dictionary = Catalog.STATIONS[scenario]
	var at: Vector3 = station.at
	var host_at := at + Vector3(0, 0.003, 2.5)
	var bot_at := at + Vector3(2.5, 0.003, 2.5)
	var yaw := 0.0
	if station.id == "movement" and not play_as_roach:
		# Keep the next station's sign out of the seven-meter human camera boom.
		host_at = at + Vector3(0, 0.003, 0.6)
	elif station.id == "cart":
		host_at = Vector3(4.05, 0.003, -0.28) if not play_as_roach else Vector3(4.5225, 0.003, -0.57)
		bot_at = Vector3(4.6325, 0.003, -0.59) if not play_as_roach else Vector3(5.05, 0.003, -0.3375)
	elif station.id == "stoves":
		var control: Node3D = world.get_node("DinerKitchen/stoves/Range1/" + ("FloorControl" if play_as_roach else "HandControl"))
		host_at = control.global_position + Vector3(0, -control.position.y + 0.003, 0.10 if play_as_roach else 0.65)
	elif station.id == "ovens":
		host_at = at + Vector3(0.52 if not play_as_roach else -0.55, 0.003, 1.82 if not play_as_roach else 0.94)
	elif station.id == "climbing":
		host_at = at + Vector3(0, 0.003, 0.13 if play_as_roach else 2)
	elif station.id == "food" and play_as_roach:
		host_at = at + Vector3(0, 0.003, 1)
		bot_at = host_at + Vector3(0, 0, -0.18)
	elif station.id == "vents":
		host_at = at + Vector3(0.5 if not play_as_roach else 0.24, 0.003, -3.2)
		yaw = PI / 2
	elif station.id == "combat":
		host_at = at + Vector3(0, 0.003, 3 if not play_as_roach else 0)
		bot_at = at + Vector3(0, 0.003, 0 if not play_as_roach else 3)
	var bot_roach: bool = not play_as_roach or station.id in ["food", "climbing"]
	return {"host_role": "cockroach" if play_as_roach else "exterminator",
		"bot_role": "cockroach" if bot_roach else "exterminator",
		"host_position": host_at, "bot_position": bot_at, "host_yaw": yaw,
		"host_pitch": -0.24 if play_as_roach else (-0.7 if station.id == "stoves" else -0.5),
		"home": at + Vector3(-1.0, 0, 2.1 if station.id == "stoves" else 1.0),
		"bot_scenario": (0 if play_as_roach else 1) if station.id == "combat" else 2,
		"route": PackedVector3Array([bot_at + Vector3(-0.7, 0, 0), bot_at + Vector3(0.7, 0, 0)]) if station.id == "combat" else PackedVector3Array()}

func prepare_scenario(setup: Dictionary) -> void:
	# Return fixtures stay separated from food when switching stations.
	play_as_roach = setup.host_role == "cockroach"
	_catch_until = 0
	_return_at = 0
	if not Net.is_host: return
	var origins: Array[Vector3] = []
	var at: Vector3 = setup.host_position
	# A complete, finite set at each selected station supports loaded traversal
	# without requiring a several-minute insect walk from the food station.
	for index: int in world.food_items.get_child_count():
		origins.append(at + Vector3(-0.026 - (index % 4) * 0.035, 0.005, ((index / 4) - 1) * 0.020))
	world.food_run.set_solo_origins(origins)

func switch_character() -> void:
	if is_bot or not session_ready: return
	play_as_roach = not play_as_roach
	reset_scenario()

func partner_action() -> void:
	if is_bot or not session_ready or not Net.is_host: return
	if Catalog.STATIONS[scenario].id == "storage":
		# Development depletion exercises the production refill without choosing carry rules.
		var rows: Array = world.food_supply.get_records()
		for index: int in maxi(0, rows.size() - 3): world.food_supply.take_food(int(rows[index].id))
		return
	_partner_action.rpc_id(bot_peer_id, _epoch)

@rpc("authority", "call_remote", "reliable")
func _partner_action(epoch: int) -> void:
	if not is_bot or not Net.is_solo_test() or not session_ready or epoch != _epoch: return
	if Catalog.STATIONS[scenario].id == "cart":
		world.serving_cart.request_move()
		return
	if Catalog.STATIONS[scenario].id == "climbing":
		var id := multiplayer.get_unique_id()
		var own: CharacterBody3D = world.players.get_node(str(id))
		var route: Node3D = world.get_node("DinerKitchen/DrainRoutes/KitchenDrain")
		own.reset_for_solo_test(route.endpoint(false).get_node("Arrival").global_position, PI, -0.24)
		await get_tree().create_timer(0.5).timeout
		if epoch != _epoch or not session_ready: return
		var link_id := str(world.get_path_to(route))
		world.drains.request_travel(link_id, false)
		await get_tree().create_timer(1.5).timeout
		if epoch != _epoch or not session_ready: return
		world.drains.request_travel(link_id, true)
		return
	var id := multiplayer.get_unique_id()
	if world.get_role_for_peer(id) != "cockroach": return
	if world.food_run.get_cargo_ids(id).is_empty():
		_catch_until = Time.get_ticks_msec() + 2000
	else:
		_return_at = Time.get_ticks_msec() + 250

func _process(delta: float) -> void:
	super._process(delta)
	if not is_bot or not session_ready or world == null: return
	var id := multiplayer.get_unique_id()
	if _return_at > 0 and Time.get_ticks_msec() >= _return_at:
		_return_at = 0
		var own: Node3D = world.players.get_node(str(id))
		var other: Node3D = world.players.get_node("1")
		world.food_run.request_action("throw", -1, other.position - own.position)
	if Time.get_ticks_msec() >= _catch_until: return
	if not world.food_run.get_cargo_ids(id).is_empty():
		_catch_until = 0
		return
	var candidate: int = world.food_run.find_candidate(id)
	if candidate >= 0 and int(world.food_run.get_food_records()[candidate].state) == 2:
		world.food_run.request_action("grab", candidate)

func defeat_bug() -> void:
	if session_ready and Net.is_host:
		world.combat.kill_from_environment(1 if play_as_roach else bot_peer_id)

func expire_round() -> void:
	if session_ready and Net.is_host: world.add_solo_time(-1000)

func get_status() -> String:
	if not error_message.is_empty() or not session_ready: return super.get_status()
	if world.get_match_phase() > 1: return "Round finished. F5 resets this station."
	if Catalog.STATIONS[scenario].id == "storage":
		var supply: Dictionary = world.food_supply.get_status()
		return "New food: %d · wave %d · refill %s · F3 depletes to 3" % [supply.available, supply.wave, ("%.1fs" % supply.refill_left) if supply.refill_left >= 0 else "idle"]
	return "%s · real connected partner · clock %s" % ["Cockroach" if play_as_roach else "Exterminator", "held" if clock_paused else "running"]

func _input(event: InputEvent) -> void:
	if not is_bot and event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F2: switch_character()
			KEY_F3: partner_action()
			KEY_F4: defeat_bug()
			_: super._input(event); return
		get_viewport().set_input_as_handled()
	else: super._input(event)
