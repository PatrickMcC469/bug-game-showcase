extends Node
## Host owns switch state and lethal overlaps; clients send only a station ID.
var _world: Node3D
var _stations: Dictionary = {}
var _on: Dictionary = {}
var _cooldowns: Dictionary = {}
var _volumes: Array[Dictionary] = []
var _revision := 0
var _received_revision := -1

func setup(world: Node3D) -> void:
	_world = world
	for station: Node3D in world.find_children("*", "Node3D", true, false):
		if not station.is_in_group("kitchen_stoves"): continue
		var id := str(station.name)
		_stations[id] = station
		_on[id] = false
		for origin: Node3D in station.find_children("FlameOrigin", "Marker3D", true, false):
			var shape := CylinderShape3D.new()
			shape.radius = 0.135
			shape.height = float(origin.get_meta("flame_height", 0.14))
			_volumes.append({"station": id, "origin": origin, "shape": shape,
				"offset": Vector3.UP * shape.height * 0.5})
	for origin: Node3D in world.find_children("OilEffectOrigin", "Marker3D", true, false):
		for x: float in [-0.192, 0.192]:
			var shape := BoxShape3D.new()
			shape.size = Vector3(0.354, 0.10, 0.75)
			_volumes.append({"station": "", "origin": origin, "shape": shape,
				"offset": Vector3(x, -0.044, 0)})
	_present()

func is_on(id: String) -> bool:
	return bool(_on.get(id, false))

func find_control(peer_id: int) -> String:
	for id: String in _stations:
		if can_reach(peer_id, id): return id
	return ""

func can_reach(peer_id: int, id: String) -> bool:
	if _world == null or not _stations.has(id) or not _world.can_peer_act(peer_id): return false
	var token := _world.players.get_node_or_null(str(peer_id)) as CharacterBody3D
	if token == null: return false
	var roach: bool = _world.get_role_for_peer(peer_id) == "cockroach"
	var control: Node3D = _stations[id].get_node("FloorControl" if roach else "HandControl")
	var from := token.global_position + Vector3.UP * (0.012 if roach else 0.95)
	if from.distance_to(control.global_position) > (0.16 if roach else 1.05): return false
	var exclude: Array[RID] = []
	for player: CharacterBody3D in _world.players.get_children(): exclude.append(player.get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, control.global_position, 1, exclude)
	return token.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _unhandled_input(event: InputEvent) -> void:
	if _world == null or not multiplayer.has_multiplayer_peer(): return
	if event.is_action_pressed("kitchen_interact") and not event.is_echo() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		request_toggle(find_control(multiplayer.get_unique_id()))

func request_toggle(id: String) -> void:
	if _world == null or not multiplayer.has_multiplayer_peer() or id.is_empty(): return
	var peer_id := multiplayer.get_unique_id()
	if not can_reach(peer_id, id): return
	if _is_host(): _handle_toggle(peer_id, id)
	else: _request_toggle.rpc_id(1, id)

@rpc("any_peer", "call_remote", "reliable")
func _request_toggle(id: String) -> void:
	if _is_host(): _handle_toggle(multiplayer.get_remote_sender_id(), id)

func _handle_toggle(peer_id: int, id: String) -> bool:
	if not _is_host() or _world.get_match_phase() > 1: return false
	if not _world.is_peer_ready(peer_id) or not can_reach(peer_id, id): return false
	var now := Time.get_ticks_msec()
	if now < int(_cooldowns.get(id, 0)): return false
	_cooldowns[id] = now + 500
	_on[id] = not is_on(id)
	send_snapshot()
	return true

func _physics_process(_delta: float) -> void:
	if _world == null or not _is_host() or _world.get_match_phase() != 1: return
	var victims: Dictionary = {}
	for volume: Dictionary in _volumes:
		if volume.station != "" and not is_on(volume.station): continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = volume.shape
		query.transform = volume.origin.global_transform.translated_local(volume.offset)
		query.collision_mask = 1
		query.margin = 0.0
		for hit: Dictionary in _world.get_world_3d().direct_space_state.intersect_shape(query, 64):
			var token := hit.collider as CharacterBody3D
			if token == null or token.get_parent() != _world.players: continue
			var peer_id := token.name.to_int()
			if _world.get_role_for_peer(peer_id) != "cockroach": continue
			# A carried stack touching heat is not the bug's body entering it.
			var owner_id := token.shape_find_owner(int(hit.shape))
			if token.shape_owner_get_owner(owner_id) != token.roach_collision: continue
			victims[peer_id] = true
	for peer_id: int in victims: _world.combat.kill_from_environment(peer_id)

func reset_hazards() -> void:
	if not _is_host(): return
	for id: String in _on: _on[id] = false
	_cooldowns.clear()
	send_snapshot()

func send_snapshot(target_peer: int = 0) -> void:
	if not _is_host(): return
	_revision += 1
	_receive_snapshot(_revision, _on)
	if target_peer > 1:
		_receive_snapshot.rpc_id(target_peer, _revision, _on)
		return
	for peer_id: int in _world.get_ready_peer_ids():
		if peer_id != 1: _receive_snapshot.rpc_id(peer_id, _revision, _on)

@rpc("authority", "call_remote", "reliable")
func _receive_snapshot(revision: int, states: Dictionary) -> void:
	if revision <= _received_revision: return
	_received_revision = revision
	for id: String in _on: _on[id] = bool(states.get(id, false))
	_present()

func _present() -> void:
	for id: String in _stations:
		var station: Node3D = _stations[id]
		for flame: Node3D in station.find_children("FlameEffect", "Node3D", true, false): flame.visible = is_on(id)
		for lever: Node3D in station.find_children("GasLever", "Node3D", true, false):
			lever.rotation.z = PI * 0.5 if is_on(id) else 0.0

func _is_host() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()
