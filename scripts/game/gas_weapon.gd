extends Node
## Host-owned single truck sprayer: fuel, equipment, exposure and docking.
const CAPACITY := 8.0
const REFILL_SECONDS := 12.0
const RANGE := 3.0
const HALF_ANGLE := 0.38397244 # 22 degrees.
const WARMUP := 0.35
const TICK := 0.25
const DAMAGE := 5 # 20 HP/sec; five seconds of continuous exposure to defeat.
const WALK_SCALE := 0.15
const Gun := preload("res://scenes/game/weapons/gas_gun_model.tscn")
var _world: Node3D
var _station: Node3D
var _state := {"carrier": 0, "fuel": CAPACITY, "spraying": false, "warming": false, "direction": Vector3.FORWARD}
var _models: Dictionary = {}
var _plumes: Dictionary = {}
var _deadline := 0.0
var _warmup := 0.0
var _exposure: Dictionary = {}
var _revision := 0
var _received_revision := -1
var _sync_left := 0.0
var _input_left := 0.0
var _action_cooldowns: Dictionary = {}

func setup(world: Node3D) -> void:
	_world = world
	for node: Node3D in world.find_children("*", "Node3D", true, false):
		if node.is_in_group("gas_refill_stations"): _station = node; break

func get_state() -> Dictionary:
	return _state.duplicate(true)

func weapon_prompt() -> String:
	if float(_state.fuel) <= 0: return "GAS EMPTY · RETURN TO TRUCK TO SWAP / REFILL"
	var action := "PRESSURIZING…" if _state.warming else "SPRAYING" if _state.spraying else "HOLD LMB · GAS"
	return "%s · %d%% TANK · SWAP AT TRUCK" % [action, ceili(float(_state.fuel) / CAPACITY * 100)]

func dock_prompt(peer_id: int) -> String:
	if int(_state.carrier) == peer_id: return "[T] SWAP GAS FOR SHOTGUN · LEAVE GAS TO REFILL"
	if int(_state.carrier) != 0: return "GAS GUN IN USE"
	if float(_state.fuel) < CAPACITY - 0.001:
		return "GAS REFILLING · %ds · Gun must stay docked" % ceili((CAPACITY - float(_state.fuel)) * REFILL_SECONDS / CAPACITY)
	return "[T] SWAP SHOTGUN FOR GAS"

func is_selected(peer_id: int) -> bool:
	# Carrying gas replaces the shotgun; there is no second holstered weapon.
	return peer_id > 0 and int(_state.carrier) == peer_id

func movement_scale(peer_id: int) -> float:
	return WALK_SCALE if is_selected(peer_id) and (_state.spraying or _state.warming) else 1.0

func can_dock(peer_id: int) -> bool:
	if _station == null or not _valid_human(peer_id): return false
	var token: CharacterBody3D = _world.players.get_node(str(peer_id))
	var from := token.global_position + Vector3.UP * 1.0
	var control: Vector3 = _station.get_node("Control").global_position
	if from.distance_to(control) > 1.3: return false
	var exclude: Array[RID] = []
	for player: CharacterBody3D in _world.players.get_children(): exclude.append(player.get_rid())
	return _world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, control, 1, exclude)).is_empty()

func _valid_human(peer_id: int) -> bool:
	return _world != null and _world.is_peer_ready(peer_id) and _world.get_role_for_peer(peer_id) == "exterminator" and _world.can_peer_act(peer_id) and _world.get_match_phase() <= 1 and _world.players.has_node(str(peer_id))

func request_action(action: String) -> void:
	if not multiplayer.has_multiplayer_peer(): return
	if multiplayer.is_server(): _handle_action(multiplayer.get_unique_id(), action)
	else: _request_action.rpc_id(1, action)

@rpc("any_peer", "call_remote", "reliable")
func _request_action(action: String) -> void:
	if multiplayer.is_server(): _handle_action(multiplayer.get_remote_sender_id(), action)

func _handle_action(peer_id: int, action: String) -> bool:
	if not multiplayer.is_server() or not _valid_human(peer_id): return false
	var token: CharacterBody3D = _world.players.get_node(str(peer_id))
	if token.shotgun.recoil_phase != 0: return false
	if action != "dock" or not can_dock(peer_id): return false
	if Time.get_ticks_msec() < int(_action_cooldowns.get(peer_id, 0)): return false
	if int(_state.carrier) == peer_id:
		_state.carrier = 0
	elif int(_state.carrier) == 0 and float(_state.fuel) >= CAPACITY - 0.001:
		_state.carrier = peer_id
	else: return false
	if _world.get("shotgun_ammo") != null: _world.shotgun_ammo.cancel_reload(peer_id)
	_stop()
	_action_cooldowns[peer_id] = Time.get_ticks_msec() + 250
	send_snapshot()
	return true

func request_spray(held: bool, direction: Vector3) -> void:
	if not multiplayer.has_multiplayer_peer(): return
	if multiplayer.is_server(): _handle_spray(multiplayer.get_unique_id(), held, direction)
	else: _request_spray.rpc_id(1, held, direction)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _request_spray(held: bool, direction: Vector3) -> void:
	if multiplayer.is_server(): _handle_spray(multiplayer.get_remote_sender_id(), held, direction)

func _handle_spray(peer_id: int, held: bool, direction: Vector3) -> bool:
	if not multiplayer.is_server() or not _valid_human(peer_id) or not is_selected(peer_id): return false
	if not direction.is_finite() or absf(direction.length_squared() - 1.0) > 0.01: return false
	if _world.players.get_node(str(peer_id)).shotgun.recoil_phase != 0: return false
	_state.direction = direction
	if not held or float(_state.fuel) <= 0:
		_stop()
		send_snapshot()
		return true
	if not _state.spraying and not _state.warming:
		_warmup = WARMUP
		_state.warming = true
	_deadline = Time.get_ticks_msec() / 1000.0 + 0.35
	return true

func _stop() -> void:
	_state.spraying = false
	_state.warming = false
	_deadline = 0
	_warmup = 0
	_exposure.clear()

func _physics_process(delta: float) -> void:
	if _world == null or not multiplayer.has_multiplayer_peer(): return
	_local_input(delta)
	if not multiplayer.is_server(): return
	var carrier := int(_state.carrier)
	if carrier > 0 and not _valid_human(carrier):
		_stop()
		# Recover an abandoned weapon to its physical cradle; preserve spent fuel.
		_state.carrier = 0
	if int(_state.carrier) == 0:
		_state.fuel = minf(CAPACITY, float(_state.fuel) + delta * CAPACITY / REFILL_SECONDS)
	elif _state.warming or _state.spraying:
		if Time.get_ticks_msec() / 1000.0 > _deadline or float(_state.fuel) <= 0:
			_stop()
		else:
			var used := minf(delta, float(_state.fuel))
			_state.fuel = maxf(0, float(_state.fuel) - used)
			_warmup = maxf(0, _warmup - used)
			_state.warming = _warmup > 0
			_state.spraying = not _state.warming
			if _state.spraying: _damage_tick(used)
			if float(_state.fuel) <= 0: _stop()
	_sync_left -= delta
	if _sync_left <= 0:
		_sync_left = 0.1
		send_snapshot()

func _local_input(delta: float) -> void:
	_input_left -= delta
	if _input_left > 0: return
	_input_left = 0.1
	var peer_id := multiplayer.get_unique_id()
	if not is_selected(peer_id) or not _world.players.has_node(str(peer_id)): return
	var token: CharacterBody3D = _world.players.get_node(str(peer_id))
	request_spray(Input.is_action_pressed("weapon_fire") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, token.shotgun.aim_direction())

func _unhandled_input(event: InputEvent) -> void:
	if _world == null or event.is_echo() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return
	if event.is_action_pressed("gas_dock"): request_action("dock")

func spray_origin() -> Dictionary:
	var token := _world.players.get_node_or_null(str(_state.carrier)) as CharacterBody3D
	if token == null: return {}
	var direction: Vector3 = _state.direction
	var yaw := atan2(-direction.x, -direction.z)
	var chest := token.global_position + Vector3.UP * 1.4
	var origin := token.global_position + Basis(Vector3.UP, yaw) * Vector3(0.13, 1.4, -0.19) + direction * 0.435
	var exclude: Array[RID] = []
	for player: CharacterBody3D in _world.players.get_children(): exclude.append(player.get_rid())
	var ray := PhysicsRayQueryParameters3D.create(chest, origin, 1, exclude)
	return {"at": origin, "blocked": not _world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "exclude": exclude}

func exposed_peers() -> Array[int]:
	var result: Array[int] = []
	var source := spray_origin()
	if source.is_empty() or source.blocked: return result
	var origin: Vector3 = source.at
	for token: CharacterBody3D in _world.players.get_children():
		var id := token.name.to_int()
		if _world.get_role_for_peer(id) != "cockroach" or not _world.is_peer_ready(id) or not _world.can_peer_act(id): continue
		var center: Vector3 = token.roach_collision.global_position
		var offset := center - origin
		if offset.length() > RANGE or offset.length() < 0.001 or offset.normalized().dot(_state.direction) < cos(HALF_ANGLE): continue
		var ray := PhysicsRayQueryParameters3D.create(origin, center, 1, source.exclude)
		if _world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): result.append(id)
	return result

func _damage_tick(delta: float) -> void:
	var inside: Array[int] = []
	if _world.get_match_phase() == 1: inside = exposed_peers()
	for id: int in _exposure.keys():
		if id not in inside: _exposure.erase(id)
	for id: int in inside:
		_exposure[id] = float(_exposure.get(id, 0)) + delta
		if float(_exposure[id]) >= TICK:
			_exposure[id] = fmod(float(_exposure[id]), TICK)
			_world.combat.damage_from_environment(id, DAMAGE)

func reset_weapon() -> void:
	if not multiplayer.is_server(): return
	_stop()
	_state.carrier = 0
	_state.fuel = CAPACITY
	_action_cooldowns.clear()
	send_snapshot()

func send_snapshot(target_peer: int = 0) -> void:
	if not multiplayer.is_server(): return
	_revision += 1
	_receive_snapshot(_revision, _state)
	if target_peer > 1: _receive_snapshot.rpc_id(target_peer, _revision, _state); return
	for id: int in _world.get_ready_peer_ids():
		if id != 1: _receive_snapshot.rpc_id(id, _revision, _state)

@rpc("authority", "call_remote", "reliable")
func _receive_snapshot(revision: int, state: Dictionary) -> void:
	if revision <= _received_revision: return
	_received_revision = revision
	if not multiplayer.is_server(): _state = state.duplicate(true)

func _process(_delta: float) -> void:
	if _world == null: return
	if _station != null:
		_station.get_node("DockedGun").visible = int(_state.carrier) == 0
		_station.get_node("Status").text = "GAS / IN USE" if int(_state.carrier) > 0 else "GAS / READY" if float(_state.fuel) >= CAPACITY - 0.001 else "REFILLING / %d%%" % roundi(float(_state.fuel) / CAPACITY * 100)
	for token: CharacterBody3D in _world.players.get_children():
		var id := token.name.to_int()
		if not _models.has(id) or not is_instance_valid(_models[id]):
			var model := Gun.instantiate() as Node3D
			token.exterminator_model.get_node("BodyRoot").add_child(model)
			_models[id] = model
			var plume := preload("res://scripts/game/gas_spray_visual.gd").new()
			_world.add_child(plume)
			_plumes[id] = plume
		var visible: bool = is_selected(id) and token.player_role == "exterminator"
		_models[id].visible = visible
		if visible:
			var pitch := asin(clampf((_state.direction as Vector3).y, -1, 1))
			_models[id].transform = Transform3D(Basis(Vector3.RIGHT, pitch), Vector3(0.13, 1.4, -0.19))
			if _state.spraying or _state.warming:
				var direction: Vector3 = _state.direction
				token.exterminator_model.shotgun_pitch = pitch
				if token.is_multiplayer_authority(): token.face_shotgun_direction(atan2(-direction.x, -direction.z))
		var source := spray_origin() if visible and _state.spraying else {}
		_plumes[id].update_spray(source, _state.direction, RANGE, HALF_ANGLE)
	for id: int in _models.keys():
		if not _world.players.has_node(str(id)):
			if is_instance_valid(_plumes[id]): _plumes[id].queue_free()
			_models.erase(id)
			_plumes.erase(id)
