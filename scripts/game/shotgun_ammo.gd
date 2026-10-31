extends Node
## Host-owned shells and truck reloads; owner movement never grants ammunition.
const CAPACITY := 6
const SHELL_SECONDS := 0.5
var _world: Node3D
var _states: Dictionary = {}
var _revision := 0
var _received_revision := -1
var _sync_left := 0.0
var _snapshot_age := 0.0

func setup(world: Node3D) -> void:
	_world = world

func get_state(peer_id: int) -> Dictionary:
	return _states.get(peer_id, {"shells": CAPACITY, "reloading": false, "elapsed": 0.0, "anchor": Vector3.ZERO}).duplicate()

func shells(peer_id: int) -> int:
	return int(get_state(peer_id).shells)

func is_reloading(peer_id: int) -> bool:
	return bool(get_state(peer_id).reloading)

func reload_cycle(peer_id: int) -> float:
	var elapsed := float(get_state(peer_id).elapsed)
	if not multiplayer.is_server(): elapsed += minf(_snapshot_age, 0.15)
	return clampf(elapsed / SHELL_SECONDS, 0.0, 1.0)

func can_fire(peer_id: int) -> bool:
	return shells(peer_id) > 0 and not is_reloading(peer_id)

func consume_shell(peer_id: int) -> bool:
	if not multiplayer.is_server() or not _valid_shotgun(peer_id) or not can_fire(peer_id): return false
	var state := get_state(peer_id)
	state.shells = int(state.shells) - 1
	_states[peer_id] = state
	send_snapshot()
	return true

func _valid_shotgun(peer_id: int) -> bool:
	return _world != null and _world.is_peer_ready(peer_id) and _world.get_role_for_peer(peer_id) == "exterminator" and _world.can_peer_act(peer_id) and _world.get_match_phase() <= 1 and not _world.gas_weapon.is_selected(peer_id) and _world.players.has_node(str(peer_id))

func request_reload() -> void:
	if not multiplayer.has_multiplayer_peer(): return
	if multiplayer.is_server(): _begin_reload(multiplayer.get_unique_id())
	else: _request_reload.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _request_reload() -> void:
	if multiplayer.is_server(): _begin_reload(multiplayer.get_remote_sender_id())

func _begin_reload(peer_id: int) -> bool:
	if not multiplayer.is_server() or not _valid_shotgun(peer_id): return false
	if not _world.gas_weapon.can_dock(peer_id) or shells(peer_id) >= CAPACITY or is_reloading(peer_id): return false
	var token: CharacterBody3D = _world.players.get_node(str(peer_id))
	if token.shotgun.recoil_phase != 0: return false
	var state := get_state(peer_id)
	state.reloading = true
	state.elapsed = 0.0
	state.anchor = token.global_position
	_states[peer_id] = state
	send_snapshot()
	return true

func cancel_reload(peer_id: int) -> void:
	if not multiplayer.is_server() or not is_reloading(peer_id): return
	_states[peer_id].reloading = false
	_states[peer_id].elapsed = 0.0
	send_snapshot()

func prompt(peer_id: int) -> String:
	if is_reloading(peer_id): return "RELOADING · %d / %d SHELLS · STAY AT TRUCK" % [shells(peer_id), CAPACITY]
	return "[R] RELOAD SHOTGUN · %d / %d SHELLS" % [shells(peer_id), CAPACITY] if shells(peer_id) < CAPACITY else "SHOTGUN AMMO FULL · %d / %d" % [CAPACITY, CAPACITY]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return
	if event.is_action_pressed("shotgun_refill"): request_reload()

func _physics_process(delta: float) -> void:
	_snapshot_age += delta
	if _world == null or not multiplayer.has_multiplayer_peer() or not multiplayer.is_server(): return
	var active := false
	var changed := false
	for peer_id: int in _states.keys():
		if not _world.players.has_node(str(peer_id)):
			_states.erase(peer_id)
			changed = true
			continue
		var state: Dictionary = _states[peer_id]
		if not state.reloading: continue
		var token: CharacterBody3D = _world.players.get_node(str(peer_id))
		if not _valid_shotgun(peer_id) or not _world.gas_weapon.can_dock(peer_id) or token.global_position.distance_to(state.anchor) > 0.12 or token.shotgun.recoil_phase != 0:
			state.reloading = false
			state.elapsed = 0.0
			changed = true
			continue
		active = true
		state.elapsed = float(state.elapsed) + delta
		if float(state.elapsed) >= SHELL_SECONDS:
			state.shells = mini(CAPACITY, int(state.shells) + 1)
			state.elapsed = float(state.elapsed) - SHELL_SECONDS
			changed = true
			if int(state.shells) == CAPACITY:
				state.reloading = false
				state.elapsed = 0.0
	_sync_left -= delta
	if changed or (active and _sync_left <= 0):
		_sync_left = 0.1
		send_snapshot()

func reset_round() -> void:
	if not multiplayer.is_server(): return
	_states.clear()
	send_snapshot()

func send_snapshot(peer_id: int = 0) -> void:
	if not multiplayer.is_server(): return
	_revision += 1
	if peer_id > 1:
		_receive_snapshot.rpc_id(peer_id, _revision, _states)
		return
	for id: int in _world.get_ready_peer_ids():
		if id != 1: _receive_snapshot.rpc_id(id, _revision, _states)

@rpc("authority", "call_remote", "reliable")
func _receive_snapshot(revision: int, states: Dictionary) -> void:
	if revision <= _received_revision: return
	_received_revision = revision
	_states = states.duplicate(true)
	_snapshot_age = 0.0
