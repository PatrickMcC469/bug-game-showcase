extends AnimatableBody3D
## Fixed-path shared prop. Only the host accepts requests and advances the cart;
## clients reproduce its ordered snapshots after GameWorld's scene-ready gate.
const RoachScale := preload("res://scripts/game/roach_scale.gd")
const Layout := preload("res://scripts/game/diner_layout.gd")
const DOCK_NORTH := Layout.CART_NORTH
const DOCK_SOUTH := Layout.CART_SOUTH
const SPEED := 0.9
const REACH := 1.08
var _world: Node3D
var _target_z := DOCK_NORTH
var _snapshot_z := DOCK_NORTH
var _tick := 0
var _last_tick := -1
var _sync_left := 0.0
var _request_cooldown := 0.0
var _blocked := false
@onready var _handle: Marker3D = $Handle

func setup(world: Node3D) -> void:
	_world = world

func _physics_process(delta: float) -> void:
	if _world == null or not multiplayer.has_multiplayer_peer():
		return
	_request_cooldown = maxf(_request_cooldown - delta, 0.0)
	if multiplayer.is_server():
		if _world.get_match_phase() == 1:
			var next := move_toward(position.z, _target_z, SPEED * delta)
			_blocked = not is_equal_approx(next, position.z) and _path_blocked(next - position.z)
			if not _blocked:
				position.z = next
		_sync_left -= delta
		if _sync_left <= 0.0:
			_sync_left = 0.05
			_tick += 1
			for peer_id: int in _world.get_ready_peer_ids():
				if peer_id != 1:
					_receive_state.rpc_id(peer_id, _tick, position.z, _target_z, _blocked)
	else:
		# Interpolate the collision body in physics time so riding uses Godot's
		# platform velocity, never an independent cosmetic-only transform.
		position.z = move_toward(position.z, _snapshot_z, SPEED * delta * 1.6)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("environment_interact") and not event.is_echo() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		request_move()

func can_reach_handle(peer_id: int) -> bool:
	if _world != null and not _world.can_peer_act(peer_id): return false
	if _world == null:
		return false
	var token := _world.players.get_node_or_null(str(peer_id)) as Node3D
	if token == null or _world.get_role_for_peer(peer_id) not in ["cockroach", "exterminator"]:
		return false
	var is_roach: bool = _world.get_role_for_peer(peer_id) == "cockroach"
	var contact := get_interaction_position(peer_id)
	var reach := 0.12 if is_roach else REACH
	if token.global_position.distance_to(contact) > reach:
		return false
	var excluded: Array[RID] = [get_rid()]
	for player: Node in _world.players.get_children():
		if player is CollisionObject3D:
			excluded.append(player.get_rid())
	var height := 0.5 * RoachScale.GEOMETRY if is_roach else 0.5
	var query := PhysicsRayQueryParameters3D.create(token.global_position + Vector3.UP * height, contact + Vector3.UP * height, 1, excluded)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

## Roaches work from the floor beside the caster; humans use the handle.
func get_interaction_position(peer_id: int) -> Vector3:
	if _world != null and _world.get_role_for_peer(peer_id) == "cockroach":
		return to_global(Layout.point(Vector3(1.05, 0, 1.6)))
	return _handle.global_position

func request_move() -> void:
	if _world == null or not multiplayer.has_multiplayer_peer():
		return
	var peer_id := multiplayer.get_unique_id()
	if not can_reach_handle(peer_id):
		return
	if multiplayer.is_server():
		_handle_request(peer_id)
	else:
		_request_move.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _request_move() -> void:
	if multiplayer.is_server():
		_handle_request(multiplayer.get_remote_sender_id())

func _handle_request(peer_id: int) -> bool:
	if not multiplayer.is_server() or _world == null or _world.get_match_phase() != 1:
		return false
	if not _world.is_peer_ready(peer_id) or _request_cooldown > 0.0 or is_moving() or not can_reach_handle(peer_id):
		return false
	_target_z = DOCK_SOUTH if is_equal_approx(_target_z, DOCK_NORTH) else DOCK_NORTH
	_request_cooldown = 0.75
	_sync_left = 0.0
	return true

func _path_blocked(motion_z: float) -> bool:
	# Check each moving shape against the actual player shapes. Standing riders
	# are above the deck and are carried; a player in front pauses the cart.
	var excluded: Array[RID] = [get_rid()]
	for body: Node in get_tree().get_nodes_in_group("diner_static"):
		if body is CollisionObject3D:
			excluded.append(body.get_rid())
	for player: CharacterBody3D in _world.players.get_children():
		# Riders rest above the deck; do not mistake their floor contact for an
		# obstacle. Everyone below it participates in the continuous sweep.
		if player.global_position.y >= global_position.y + 2.3 * Layout.SCALE:
			excluded.append(player.get_rid())
	for child: Node in get_children():
		if not child is CollisionShape3D or child.disabled:
			continue
		var shape := child as CollisionShape3D
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape.shape
		query.transform = shape.global_transform
		query.motion = Vector3(0, 0, motion_z)
		query.collision_mask = 1
		query.exclude = excluded
		query.margin = 0.005
		var space := get_world_3d().direct_space_state
		if not space.intersect_shape(query, 1).is_empty(): return true
		if space.cast_motion(query)[0] < 1.0: return true
	return false

func is_moving() -> bool:
	return absf(position.z - _target_z) > 0.015

func get_state() -> Dictionary:
	return {"z": position.z, "target_z": _target_z, "blocked": _blocked, "tick": _tick}

func send_snapshot(peer_id: int) -> void:
	if multiplayer.is_server() and peer_id > 1:
		_initial_state.rpc_id(peer_id, _tick, position.z, _target_z, _blocked)

@rpc("authority", "call_remote", "reliable")
func _initial_state(tick: int, z: float, target: float, blocked: bool) -> void:
	if tick < _last_tick:
		return
	_receive_state(tick, z, target, blocked)
	position.z = _snapshot_z

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _receive_state(tick: int, z: float, target: float, blocked: bool) -> void:
	if tick < _last_tick:
		return
	_last_tick = tick
	_snapshot_z = z
	_target_z = target
	_blocked = blocked

func reset_cart() -> void:
	if not multiplayer.is_server():
		return
	position.z = DOCK_NORTH
	_target_z = DOCK_NORTH
	_blocked = false
	_request_cooldown = 0.0
	_tick += 1
	for peer_id: int in _world.get_ready_peer_ids():
		if peer_id != 1:
			send_snapshot(peer_id)
