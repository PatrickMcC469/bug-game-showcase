extends Node
## Host-owned doors, oven heat and exposure. Stove burners remain independent.
const DOOR_SPEED := 1.4
const DAMAGE_INTERVAL := 0.5
const DAMAGE_PER_TICK := 10
var _world: Node3D
var _ovens: Dictionary = {}
var _states: Dictionary = {}
var _cooldowns: Dictionary = {}
var _exposure: Dictionary = {}
var _revision := 0
var _received_revision := -1
var _sync_left := 0.0
var _inside_shape: BoxShape3D

func setup(world: Node3D) -> void:
	_world = world
	_inside_shape = BoxShape3D.new()
	_inside_shape.size = Vector3(1.90, 0.86, 1.38)
	for oven: Node3D in world.find_children("*", "Node3D", true, false):
		if not oven.is_in_group("kitchen_ovens"): continue
		var id := str(oven.name)
		_ovens[id] = oven
		_states[id] = {"hot": false, "open": false, "angle": 0.0, "blocked": false}
	_present()

func get_state(id: String) -> Dictionary:
	return _states.get(id, {}).duplicate()

func find_control(peer_id: int) -> String:
	for id: String in _ovens:
		if can_reach(peer_id, id): return id
	return ""

func can_reach(peer_id: int, id: String) -> bool:
	if _world == null or not _ovens.has(id) or not _world.can_peer_act(peer_id): return false
	var token := _world.players.get_node_or_null(str(peer_id)) as CharacterBody3D
	if token == null: return false
	var roach: bool = _world.get_role_for_peer(peer_id) == "cockroach"
	var from := token.global_position + Vector3.UP * (0.012 if roach else 0.95)
	var exclude: Array[RID] = []
	for player: CharacterBody3D in _world.players.get_children(): exclude.append(player.get_rid())
	for path: String in (["OutsideShutoff", "InsideShutoff"] if roach else ["HumanControl"]):
		var control: Node3D = _ovens[id].get_node(path)
		if from.distance_to(control.global_position) > (0.16 if roach else 1.25): continue
		var ray := PhysicsRayQueryParameters3D.create(from, control.global_position, 1, exclude)
		if token.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if _world == null or not multiplayer.has_multiplayer_peer() or event.is_echo() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return
	var action := "door" if event.is_action_pressed("oven_door") else "heat" if event.is_action_pressed("oven_heat") else ""
	if action != "": request_action(find_control(multiplayer.get_unique_id()), action)

func request_action(id: String, action: String) -> void:
	if _world == null or not multiplayer.has_multiplayer_peer() or not can_reach(multiplayer.get_unique_id(), id): return
	if _is_host(): _handle_action(multiplayer.get_unique_id(), id, action)
	else: _request_action.rpc_id(1, id, action)

@rpc("any_peer", "call_remote", "reliable")
func _request_action(id: String, action: String) -> void:
	if _is_host(): _handle_action(multiplayer.get_remote_sender_id(), id, action)

func _handle_action(peer_id: int, id: String, action: String) -> bool:
	if not _is_host() or _world.get_match_phase() > 1: return false
	if action not in ["door", "heat"] or not _world.is_peer_ready(peer_id) or not can_reach(peer_id, id): return false
	var human: bool = _world.get_role_for_peer(peer_id) == "exterminator"
	var state: Dictionary = _states[id]
	if not human and (action == "door" or not bool(state.hot)): return false
	var key := id + action
	if Time.get_ticks_msec() < int(_cooldowns.get(key, 0)): return false
	_cooldowns[key] = Time.get_ticks_msec() + 400
	if action == "door": state.open = not bool(state.open)
	else: state.hot = not bool(state.hot) if human else false
	send_snapshot()
	return true

func _physics_process(delta: float) -> void:
	if _world == null or not _is_host(): return
	var changed := false
	for id: String in _states:
		var state: Dictionary = _states[id]
		var target := PI * 0.5 if bool(state.open) else 0.0
		var next := move_toward(float(state.angle), target, DOOR_SPEED * delta)
		var blocked := false
		if not is_equal_approx(next, float(state.angle)):
			blocked = _door_blocked(id, float(state.angle), next)
			if not blocked:
				state.angle = next
				_ovens[id].get_node("Door").rotation.x = next
				changed = true
		if bool(state.blocked) != blocked:
			state.blocked = blocked
			changed = true
	_sync_left -= delta
	if changed and _sync_left <= 0:
		_sync_left = 0.05
		send_snapshot()
	# Always publish the final angle, even if it fell between sync ticks.
	elif not changed and _sync_left <= 0 and _sync_left > -delta * 2:
		send_snapshot()
	if _world.get_match_phase() != 1:
		_exposure.clear()
		return
	var inside: Dictionary = {}
	for id: String in _states:
		if not bool(_states[id].hot): continue
		for peer_id: int in _bugs_inside(id): inside[peer_id] = true
	for peer_id: int in _exposure.keys():
		if not inside.has(peer_id): _exposure.erase(peer_id)
	for peer_id: int in inside:
		_exposure[peer_id] = float(_exposure.get(peer_id, 0.0)) + delta
		if float(_exposure[peer_id]) >= DAMAGE_INTERVAL:
			_exposure[peer_id] = fmod(float(_exposure[peer_id]), DAMAGE_INTERVAL)
			_world.combat.damage_from_environment(peer_id, DAMAGE_PER_TICK)

func _bugs_inside(id: String) -> Array[int]:
	var result: Array[int] = []
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _inside_shape
	query.transform = _ovens[id].global_transform.translated_local(Vector3(0, 0.43, 0.04))
	query.collision_mask = 1
	for hit: Dictionary in _world.get_world_3d().direct_space_state.intersect_shape(query, 128):
		var token := hit.collider as CharacterBody3D
		if token == null or token.get_parent() != _world.players: continue
		var peer_id := token.name.to_int()
		if _world.get_role_for_peer(peer_id) != "cockroach" or not _world.can_peer_act(peer_id): continue
		if token.shape_owner_get_owner(token.shape_find_owner(int(hit.shape))) == token.roach_collision:
			if not result.has(peer_id): result.append(peer_id)
	return result

func _door_blocked(id: String, from: float, to: float) -> bool:
	var door := _ovens[id].get_node("Door") as AnimatableBody3D
	# Subdivide the arc so a frame hitch cannot sweep through an insect.
	var samples := maxi(1, ceili(absf(to - from) / 0.008))
	for i: int in range(1, samples + 1):
		var pose := Transform3D(Basis(Vector3.RIGHT, lerpf(from, to, float(i) / samples)), door.position)
		for child: Node in door.get_children():
			if not child is CollisionShape3D: continue
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = child.shape
			query.transform = _ovens[id].global_transform * pose * child.transform
			query.collision_mask = 1
			query.exclude = [door.get_rid()]
			for hit: Dictionary in _world.get_world_3d().direct_space_state.intersect_shape(query, 128):
				if hit.collider is CharacterBody3D and hit.collider.get_parent() == _world.players: return true
	return false

func reset_ovens() -> void:
	if not _is_host(): return
	for id: String in _states:
		_states[id].hot = false
		_states[id].open = false
	_exposure.clear()
	_cooldowns.clear()
	send_snapshot()

func send_snapshot(target_peer: int = 0) -> void:
	if not _is_host(): return
	_revision += 1
	_receive_snapshot(_revision, _states)
	if target_peer > 1:
		_receive_snapshot.rpc_id(target_peer, _revision, _states)
		return
	for peer_id: int in _world.get_ready_peer_ids():
		if peer_id != 1: _receive_snapshot.rpc_id(peer_id, _revision, _states)

@rpc("authority", "call_remote", "reliable")
func _receive_snapshot(revision: int, states: Dictionary) -> void:
	if revision <= _received_revision: return
	_received_revision = revision
	if not _is_host(): _states = states.duplicate(true)
	_present()

func _present() -> void:
	for id: String in _ovens:
		var oven: Node3D = _ovens[id]
		var state: Dictionary = _states[id]
		oven.get_node("Door").rotation.x = float(state.angle)
		oven.get_node("HeatGlow").visible = bool(state.hot)

func _is_host() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()
