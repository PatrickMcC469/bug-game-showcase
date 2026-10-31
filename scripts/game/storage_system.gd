extends Node
## Host-owned storage doors. Physical cavities and vents use ordinary movement.
const SPEED := 1.5
var _world: Node3D
var _props: Dictionary = {}
var _states: Dictionary = {}
var _cooldowns: Dictionary = {}
var _revision := 0
var _received_revision := -1
var _sync_left := 0.0
var _dirty := false

func setup(world: Node3D) -> void:
	_world = world
	for prop: Node3D in world.find_children("*", "Node3D", true, false):
		if not prop.is_in_group("openable_storage"): continue
		var id := str(prop.name)
		_props[id] = prop
		_states[id] = {"open": false, "angle": 0.0, "blocked": false}
	_present()

func get_state(id: String) -> Dictionary:
	return _states.get(id, {}).duplicate()

func get_display_name(id: String) -> String:
	return str(_props[id].get_meta("display_name")) if _props.has(id) else "storage"

func find_control(peer_id: int) -> String:
	var best := ""
	var distance := INF
	for id: String in _props:
		var reach := _control_distance(peer_id, id)
		if reach < distance: best = id; distance = reach
	return best

func _control_distance(peer_id: int, id: String) -> float:
	if _world == null or not _props.has(id) or not _world.can_peer_act(peer_id): return INF
	var token := _world.players.get_node_or_null(str(peer_id)) as CharacterBody3D
	if token == null: return INF
	var bug: bool = _world.get_role_for_peer(peer_id) == "cockroach"
	var from := token.global_position + Vector3.UP * (0.012 if bug else 0.95)
	var exclude: Array[RID] = []
	for player: CharacterBody3D in _world.players.get_children(): exclude.append(player.get_rid())
	var best := INF
	for suffix: String in ["Outside", "Inside"]:
		var marker: Node3D = _props[id].get_node(("Bug" if bug else "Human") + suffix)
		var distance := from.distance_to(marker.global_position)
		if distance > (0.16 if bug else 1.25): continue
		var query := PhysicsRayQueryParameters3D.create(from, marker.global_position, 1, exclude)
		if token.get_world_3d().direct_space_state.intersect_ray(query).is_empty(): best = minf(best, distance)
	return best

func can_reach(peer_id: int, id: String) -> bool:
	return is_finite(_control_distance(peer_id, id))

func _unhandled_input(event: InputEvent) -> void:
	if _world == null or not multiplayer.has_multiplayer_peer() or event.is_echo() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return
	if event.is_action_pressed("storage_interact"): request_toggle(find_control(multiplayer.get_unique_id()))

func request_toggle(id: String) -> void:
	if _world == null or not multiplayer.has_multiplayer_peer() or not can_reach(multiplayer.get_unique_id(), id): return
	if _is_host(): _handle_toggle(multiplayer.get_unique_id(), id)
	else: _request_toggle.rpc_id(1, id)

@rpc("any_peer", "call_remote", "reliable")
func _request_toggle(id: String) -> void:
	if _is_host(): _handle_toggle(multiplayer.get_remote_sender_id(), id)

func _handle_toggle(peer_id: int, id: String) -> bool:
	if not _is_host() or _world.get_match_phase() > 1: return false
	if not _world.is_peer_ready(peer_id) or not can_reach(peer_id, id): return false
	if Time.get_ticks_msec() < int(_cooldowns.get(id, 0)): return false
	_cooldowns[id] = Time.get_ticks_msec() + 350
	_states[id].open = not bool(_states[id].open)
	send_snapshot()
	return true

func _physics_process(delta: float) -> void:
	if _world == null or not _is_host(): return
	for id: String in _props:
		var state: Dictionary = _states[id]
		var target: float = float(_props[id].get_meta("open_angle")) if state.open else 0.0
		var next := move_toward(float(state.angle), target, SPEED * delta)
		var blocked := false
		if not is_equal_approx(next, float(state.angle)):
			blocked = _blocked(id, float(state.angle), next)
			if not blocked:
				state.angle = next
				_pose(id)
				_dirty = true
		if bool(state.blocked) != blocked: state.blocked = blocked; _dirty = true
	_sync_left -= delta
	if _dirty and _sync_left <= 0:
		_sync_left = 0.05
		send_snapshot()

func _blocked(id: String, from: float, to: float) -> bool:
	var prop: Node3D = _props[id]
	var door := prop.get_node("Door") as AnimatableBody3D
	var axis: Vector3 = prop.get_meta("axis")
	var samples := maxi(1, ceili(absf(to - from) / 0.006))
	# Only ignore this prop's frame, which intentionally meets its own door.
	# Other scenery, carried food and players all stop the swept panel.
	var exclude: Array[RID] = [door.get_rid()]
	for body: Node in prop.find_children("*", "StaticBody3D", true, false): exclude.append(body.get_rid())
	for i: int in range(1, samples + 1):
		var pose := prop.global_transform * Transform3D(Basis(axis, lerpf(from, to, float(i) / samples)), door.position)
		for shape: Node in door.get_children():
			if not shape is CollisionShape3D: continue
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape.shape
			query.transform = pose * shape.transform
			query.collision_mask = 1
			query.exclude = exclude
			if not _world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return true
	return false

func reset_storage() -> void:
	if not _is_host(): return
	for id: String in _states: _states[id].open = false
	_cooldowns.clear()
	send_snapshot()

func send_snapshot(target_peer: int = 0) -> void:
	if not _is_host(): return
	_revision += 1
	_dirty = false
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

func _pose(id: String) -> void:
	var prop: Node3D = _props[id]
	prop.get_node("Door").basis = Basis(prop.get_meta("axis"), float(_states[id].angle))

func _present() -> void:
	for id: String in _props: _pose(id)

func _is_host() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()
