extends Node
## Host approves authored links; only the owning token applies a relocation.
## Reliable epoch/sequence checks prevent old approvals surviving round resets.
const REACH := 0.13
const COOLDOWN_MS := 1000
var _world: Node3D
var _routes: Dictionary = {}
var _cooldowns: Dictionary = {}
var _reservations: Dictionary = {}
var _epoch := 0
var _serial := 0
var _last_serial := -1
var _label: Label
var _notice := ""
var _notice_until := 0

func setup(world: Node3D) -> void:
	_world = world
	for route: Node in world.find_children("*", "Node3D", true, false):
		if not route.is_in_group("drain_routes"): continue
		var valid := true
		for outside: bool in [false, true]:
			var endpoint: Node3D = route.endpoint(outside)
			if endpoint == null or not endpoint.has_node("Control") or not endpoint.has_node("Arrival"): valid = false
		if valid: _routes[str(world.get_path_to(route))] = route
		else: push_warning("Drain link has missing endpoints: " + str(route.get_path()))
	if DisplayServer.get_name() != "headless":
		var canvas := CanvasLayer.new()
		add_child(canvas)
		_label = Label.new()
		canvas.add_child(_label)
		_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_label.offset_left = -340
		_label.offset_right = 340
		_label.offset_top = -245
		_label.offset_bottom = -215
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.add_theme_font_size_override("font_size", 19)
		_label.modulate = Color(0.65, 0.91, 0.86)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _eligible(peer: int) -> bool:
	return _world != null and _world.is_peer_ready(peer) and _world.get_match_phase() <= 1 and _world.get_role_for_peer(peer) == "cockroach" and _world.can_peer_act(peer) and not _world.food_carry.immobilized(peer)

func _token(peer: int) -> CharacterBody3D:
	return _world.players.get_node_or_null(str(peer)) as CharacterBody3D

func can_reach(peer: int, id: String, outside: bool) -> bool:
	if not _eligible(peer) or not _routes.has(id): return false
	var token := _token(peer)
	if token == null: return false
	var control: Node3D = _routes[id].endpoint(outside).get_node("Control")
	var from := token.global_position + Vector3.UP * 0.012
	if from.distance_to(control.global_position) > REACH: return false
	var query := PhysicsRayQueryParameters3D.create(from, control.global_position, 1, [token.get_rid()])
	return token.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func find_entrance(peer: int) -> Dictionary:
	var best := {}
	var distance := INF
	for id: String in _routes:
		for outside: bool in [false, true]:
			if not can_reach(peer, id, outside): continue
			var control: Node3D = _routes[id].endpoint(outside).get_node("Control")
			var next := _token(peer).global_position.distance_to(control.global_position)
			if next < distance:
				distance = next
				best = {"id": id, "outside": outside}
	return best

func _process(_delta: float) -> void:
	if _label == null or not multiplayer.has_multiplayer_peer(): return
	_label.text = ""
	var peer := multiplayer.get_unique_id()
	if not _eligible(peer): return
	if Time.get_ticks_msec() < _notice_until:
		_label.text = _notice
		return
	var found := find_entrance(peer)
	if not found.is_empty(): _label.text = "[B] ENTER PIPE · TO SINK" if found.outside else "[B] ENTER DRAIN · TO OUTSIDE PIPE"

func _unhandled_input(event: InputEvent) -> void:
	if not multiplayer.has_multiplayer_peer() or event.is_echo() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return
	if event.is_action_pressed("storage_interact"):
		var found := find_entrance(multiplayer.get_unique_id())
		if found.is_empty(): return
		request_travel(found.id, found.outside)
		get_viewport().set_input_as_handled()

func request_travel(id: String, outside: bool) -> void:
	if not multiplayer.has_multiplayer_peer() or not can_reach(multiplayer.get_unique_id(), id, outside): return
	if _is_host(): _handle_request(multiplayer.get_unique_id(), id, outside)
	else: _request.rpc_id(1, id, outside, _epoch)

@rpc("any_peer", "call_remote", "reliable")
func _request(id: String, outside: bool, epoch: int) -> void:
	if _is_host() and epoch == _epoch: _handle_request(multiplayer.get_remote_sender_id(), id, outside)

func destination_clear(peer: int, id: String, outside: bool) -> bool:
	if not _routes.has(id) or _token(peer) == null: return false
	var arrival: Node3D = _routes[id].endpoint(not outside).get_node("Arrival")
	var token := _token(peer)
	if not token.climber.can_occupy(arrival.global_position, arrival.global_basis.orthonormalized()): return false
	# Refuse unsupported map placements, as well as bodies/cargo occupying them.
	var query := PhysicsRayQueryParameters3D.create(arrival.global_position + Vector3.UP * 0.006, arrival.global_position - Vector3.UP * 0.035, 1, [token.get_rid()])
	var hit := token.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.normal.y > 0.8

func _handle_request(peer: int, id: String, outside: bool) -> bool:
	if not _is_host() or not can_reach(peer, id, outside): return false
	var now := Time.get_ticks_msec()
	if now < int(_cooldowns.get(peer, 0)): return false
	var arrival: Node3D = _routes[id].endpoint(not outside).get_node("Arrival")
	for reserved: Dictionary in _reservations.values():
		if now < int(reserved.until) and arrival.global_position.distance_to(reserved.at) < 0.10:
			deny(peer)
			return false
	if not destination_clear(peer, id, outside):
		deny(peer)
		return false
	_cooldowns[peer] = now + COOLDOWN_MS
	# Reserve before sending the approval: a second request can arrive before
	# the first owner's normal position snapshot reaches the host.
	_reservations[peer] = {"at": arrival.global_position, "until": now + COOLDOWN_MS}
	_serial += 1
	if peer == multiplayer.get_unique_id(): _approve(_epoch, _serial, id, outside)
	else: _approve.rpc_id(peer, _epoch, _serial, id, outside)
	return true

@rpc("authority", "call_remote", "reliable")
func _approve(epoch: int, serial: int, id: String, outside: bool) -> void:
	if epoch != _epoch or serial <= _last_serial: return
	_last_serial = serial
	var peer := multiplayer.get_unique_id()
	# The owner may have moved, died, frozen, or encountered a newly occupied
	# exit while the approval was travelling. Recheck without moving other peers.
	if not can_reach(peer, id, outside) or not destination_clear(peer, id, outside):
		_blocked()
		return
	var arrival: Node3D = _routes[id].endpoint(not outside).get_node("Arrival")
	_token(peer).travel_through_drain(arrival.global_position, arrival.global_rotation.y)
	_notice = "BACK IN THE SINK" if outside else "OUTSIDE PIPE"
	_notice_until = Time.get_ticks_msec() + 800

func deny(peer: int) -> void:
	if peer == multiplayer.get_unique_id(): _blocked()
	else: _blocked.rpc_id(peer)

@rpc("authority", "call_remote", "reliable")
func _blocked() -> void:
	_notice = "DRAIN EXIT BLOCKED · TRY AGAIN WHEN CLEAR"
	_notice_until = Time.get_ticks_msec() + 1200

func release_peer(peer: int) -> void:
	_cooldowns.erase(peer)
	_reservations.erase(peer)

func reset_round() -> void:
	if not _is_host(): return
	_epoch += 1
	_cooldowns.clear()
	_reservations.clear()
	_notice_until = 0
	for peer: int in _world.get_ready_peer_ids(): send_snapshot(peer)

func send_snapshot(peer: int) -> void:
	if _is_host() and peer > 1: _receive_epoch.rpc_id(peer, _epoch)

@rpc("authority", "call_remote", "reliable")
func _receive_epoch(epoch: int) -> void:
	if epoch < _epoch: return
	_epoch = epoch
	_notice_until = 0

func _is_host() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()
