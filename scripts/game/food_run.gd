extends Node
## The host owns every food transition. Static scene nodes are presentation;
## reliable revisions carry ownership, while ordered motion updates carry flight.

signal feedback(message: String, kind: String, at: Vector3)
const RoachScale := preload("res://scripts/game/roach_scale.gd")
const Catalog := preload("res://scripts/game/food_catalog.gd")
const AVAILABLE := 0
const CARRIED := 1
const FLYING := 2
const BANKED := 3
const GRAB_RANGE := 1.85 * RoachScale.GEOMETRY
const HOME_RADIUS := 2.5 * RoachScale.GEOMETRY
const UNLOAD_SECONDS := 0.55
const ACTION_INTERVAL := 0.18
const GRAVITY := 16.0 * RoachScale.GEOMETRY
const THROW_SPEED := 10.0 * RoachScale.GEOMETRY
const THROW_LIFT := 5.8 * RoachScale.GEOMETRY
@export var recovery_bounds := AABB(Vector3(-19.5, -3, -19.5), Vector3(39, 100, 39))

var _world: Node3D
var _foods: Array[Dictionary] = []
var _visuals: Array[Node3D] = []
var _origins: Array[Vector3] = []
var _supports: Dictionary[int, Dictionary] = {}
var _motion: Dictionary = {}
var _stress: Dictionary = {}
var _unload: Dictionary = {}
var _action_times: Dictionary = {}
var _clock := 0.0
var _revision := 0
var _motion_tick := 0
var _last_motion_tick := -1
var _sync_left := 0.0
var _visual_age := 0.0
var _initialized := false
var _stats := {"catches": 0, "spills": 0, "airmail": 0, "relay": 0}

func setup(world: Node3D) -> void:
	_world = world
	for child: Node in _world.food_items.get_children():
		if child is Area3D and child.get("food_kind") != null:
			_visuals.append(child)
			_origins.append(child.global_position)
	_initialized = true
	if _is_host():
		reset_food()

func _is_host() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()

func _running() -> bool:
	return _initialized and _world.get_match_phase() == 1

func reset_food() -> void:
	if not _is_host():
		return
	_foods.clear()
	_supports.clear()
	_stress.clear()
	_unload.clear()
	_motion.clear()
	_action_times.clear()
	_stats = {"catches": 0, "spills": 0, "airmail": 0, "relay": 0}
	for index: int in _visuals.size():
		_foods.append({"id": index, "kind": int(_visuals[index].food_kind), "state": AVAILABLE,
			"carrier": 0, "slot": 0, "pos": _origins[index], "vel": Vector3.ZERO,
			"thrower": 0, "throw_origin": Vector3.ZERO, "relay": false,
			"lock_peer": 0, "lock_until": 0.0, "flight_time": 0.0})
	_publish()

func _physics_process(delta: float) -> void:
	if not _initialized:
		return
	_clock += delta
	if not _is_host() or not _running():
		return
	for peer_id: int in _world.get_ready_peer_ids():
		var token := _token(peer_id)
		if token == null or not _world.can_peer_act(peer_id):
			continue
		_measure_motion(peer_id, token, delta)
		_update_load(peer_id, delta)
		if not _running():
			break
	for food: Dictionary in _foods:
		if not _running():
			break
		if int(food["state"]) == AVAILABLE:
			_step_support(food)
		elif int(food["state"]) == FLYING:
			_step_flight(food, delta)
	_sync_left -= delta
	if _sync_left <= 0.0:
		_sync_left = 0.10
		_publish_motion()

func _process(delta: float) -> void:
	if not _initialized:
		return
	_visual_age += delta
	for peer_id: int in _world.get_ready_peer_ids():
		var token := _token(peer_id)
		if token != null and (_world.get("food_carry") == null or _world.food_carry.held(peer_id).is_empty()):
			token.set_cargo(get_cargo_weight(peer_id), float(_stress.get(peer_id, 0.0)), get_cargo_ids(peer_id).size())
			if token.has_method("set_cargo_clearance"):
				token.set_cargo_clearance(_cargo_top(peer_id))
	for food: Dictionary in _foods:
		var index := int(food["id"])
		var visual := _visuals[index]
		var state := int(food["state"])
		var target: Vector3 = food["pos"]
		var angles := Vector3.ZERO
		if state == CARRIED:
			var carrier := _token(int(food["carrier"]))
			if carrier == null:
				visual.visible = false
				continue
			target = _cargo_position(food)
			var wobble := float(_stress.get(int(food["carrier"]), 0.0))
			var phase := _clock * 8.0 + float(food["slot"]) * 0.7
			angles = Vector3(sin(phase * 0.83) * wobble * 0.17,
				carrier.cockroach_model.rotation.y, sin(phase) * wobble * 0.28)
			target.x += sin(phase) * wobble * 0.1 * RoachScale.GEOMETRY * (int(food["slot"]) + 1)
		elif state == FLYING:
			if not _is_host():
				target += (food["vel"] as Vector3) * minf(_visual_age, 0.12)
			angles = Vector3(_clock * 3.5, _clock * 1.8, float(index))
		visual.visible = true
		visual.scale = visual.scale.lerp(Vector3.ONE * RoachScale.GEOMETRY * (0.45 if state == BANKED else 1.0), minf(delta * 10.0, 1.0))
		visual.set_hint(false, false)
		visual.present(target, angles, state == CARRIED, delta)

func _unhandled_input(event: InputEvent) -> void:
	if not _running() or not multiplayer.has_multiplayer_peer() or event.is_echo() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var peer_id := multiplayer.get_unique_id()
	var token := _token(peer_id)
	if token == null or not token.is_multiplayer_authority() or _world.get_role_for_peer(peer_id) != "cockroach":
		return
	if _world.get("food_carry") != null and (not _world.food_carry.held(peer_id).is_empty() or _world.food_carry.candidate(peer_id) >= 0): return
	if event.is_action_pressed("food_grab"):
		request_action("grab", find_candidate(peer_id))
	elif event.is_action_pressed("food_drop"):
		request_action("drop")
	elif event.is_action_pressed("food_throw"):
		request_action("throw", -1, -token.camera_rig.global_basis.z)

## Callers express intent only. Sender identity comes from the transport, never
## from a client-provided peer id, position, item value or inventory.
func request_action(action: String, food_id: int = -1, direction: Vector3 = Vector3.ZERO) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if _is_host():
		_handle_action(1, action, food_id, direction)
	else:
		_request_action.rpc_id(1, action, food_id, direction)

@rpc("any_peer", "call_remote", "reliable")
func _request_action(action: String, food_id: int, direction: Vector3) -> void:
	if _is_host():
		_handle_action(multiplayer.get_remote_sender_id(), action, food_id, direction)

func _handle_action(peer_id: int, action: String, food_id: int, direction: Vector3) -> bool:
	if not _world.can_peer_act(peer_id): return false
	if not _running() or not _world.is_peer_ready(peer_id) or _world.get_role_for_peer(peer_id) != "cockroach":
		return false
	if _clock < float(_action_times.get(peer_id, -1.0)) + ACTION_INTERVAL:
		return false
	_action_times[peer_id] = _clock
	var token := _token(peer_id)
	if token == null or not direction.is_finite():
		return false
	if action == "grab":
		if get_cargo_ids(peer_id).size() >= Catalog.STACK_LIMIT or (_world.get("food_carry") != null and (not _world.food_carry.held(peer_id).is_empty() or _world.food_carry.immobilized(peer_id))):
			_reject(peer_id, "Already carrying food. Drop or deliver it first.")
			return false
		if food_id < 0 or food_id >= _foods.size():
			_reject(peer_id, "Get closer to the food.")
			return false
		var food := _foods[food_id]
		if not _can_grab(peer_id, food):
			return false
		var caught := int(food["state"]) == FLYING and int(food["thrower"]) > 0 and int(food["thrower"]) != peer_id
		food["relay"] = bool(food["relay"]) or caught
		_supports.erase(int(food["id"]))
		food["state"] = CARRIED
		food["slot"] = get_cargo_ids(peer_id).size()
		food["carrier"] = peer_id
		food["vel"] = Vector3.ZERO
		if caught:
			_stats["catches"] += 1
			_announce("SNACK SNATCH!  Relay bonus secured", "catch", token.global_position)
		else:
			_announce("%s on board" % Catalog.info(food["kind"])["name"], "grab", token.global_position)
		_publish()
		return true
	if action not in ["drop", "throw"] or get_cargo_ids(peer_id).is_empty():
		return false
	_launch_top(peer_id, direction, action == "throw")
	return true

func _can_grab(peer_id: int, food: Dictionary) -> bool:
	if not _world.can_peer_act(peer_id): return false
	if int(food["state"]) not in [AVAILABLE, FLYING]:
		return false
	if int(food["lock_peer"]) == peer_id and _clock < float(food["lock_until"]):
		return false
	var token := _token(peer_id)
	if token == null:
		return false
	var from := token.global_position + Vector3.UP * (0.5 * RoachScale.GEOMETRY)
	var at: Vector3 = food["pos"]
	if from.distance_to(at) > GRAB_RANGE:
		return false
	return _clear_path(from, at) and _cargo_fits(peer_id, int(food["id"]))

func _cargo_fits(peer_id: int, extra_id: int) -> bool:
	var token := _token(peer_id)
	var bottom := 0.55 * RoachScale.GEOMETRY
	var height := maxf(_cargo_top(peer_id, extra_id) - bottom, 0.05 * RoachScale.GEOMETRY)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.64 * RoachScale.GEOMETRY, height, 0.64 * RoachScale.GEOMETRY)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, token.global_position + Vector3.UP * (bottom + height * 0.5))
	query.collision_mask = 1
	query.exclude = [token.get_rid()]
	return _world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _clear_path(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, _player_rids())
	query.hit_from_inside = true
	return _world.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _player_rids() -> Array[RID]:
	var result: Array[RID] = []
	for token: Node in _world.players.get_children():
		if token is CollisionObject3D:
			result.append(token.get_rid())
	return result

func find_candidate(peer_id: int) -> int:
	if not _world.can_peer_act(peer_id): return -1
	if not _initialized or _world.get_role_for_peer(peer_id) != "cockroach":
		return -1
	var token := _token(peer_id)
	if token == null:
		return -1
	var best := -1
	var distance := GRAB_RANGE
	for food: Dictionary in _foods:
		var d := (token.global_position + Vector3.UP * (0.5 * RoachScale.GEOMETRY)).distance_to(food["pos"])
		if d < distance and _can_grab(peer_id, food):
			distance = d
			best = int(food["id"])
	return best

func _launch_top(peer_id: int, direction: Vector3, thrown: bool, spilled: bool = false) -> void:
	var ids := get_cargo_ids(peer_id)
	var token := _token(peer_id)
	if ids.is_empty() or token == null:
		return
	var food := _foods[ids.back()]
	var origin := _cargo_position(food)
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		direction = -token.cockroach_model.global_basis.z
	direction = direction.normalized()
	_supports.erase(int(food["id"]))
	food["pos"] = origin
	food["state"] = FLYING
	food["carrier"] = 0
	food["thrower"] = peer_id if thrown else 0
	food["throw_origin"] = token.global_position
	food["lock_peer"] = peer_id
	food["lock_until"] = _clock + 0.65
	food["flight_time"] = 0.0
	food["vel"] = direction * (THROW_SPEED if thrown else 2.2 * RoachScale.GEOMETRY) + Vector3.UP * (THROW_LIFT if thrown else 2.0 * RoachScale.GEOMETRY)
	_stress[peer_id] = 0.18
	_unload[peer_id] = 0.0
	if spilled:
		_stats["spills"] += 1
		_announce("SNACK AVALANCHE!  Your top snack bailed.", "spill", origin)
	else:
		_announce("AIR MAIL!" if thrown else "Snack parked", "throw" if thrown else "drop", origin)
	_publish()

func _step_flight(food: Dictionary, delta: float) -> void:
	food["flight_time"] = float(food["flight_time"]) + delta
	var position: Vector3 = food["pos"]
	var velocity: Vector3 = food["vel"]
	velocity.y -= GRAVITY * delta
	var next := position + velocity * delta
	var radius := float(Catalog.info(food["kind"])["radius"])
	var query := PhysicsRayQueryParameters3D.create(position - Vector3.UP * radius, next - Vector3.UP * radius, 1, _player_rids())
	var hit := _world.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var normal: Vector3 = hit["normal"]
		next = (hit["position"] as Vector3) + Vector3.UP * radius + normal * (0.015 * RoachScale.GEOMETRY)
		if normal.y > 0.65 and _near_home(next):
			food["pos"] = next
			var airmail := int(food["thrower"]) > 0 and _flat_distance(food["throw_origin"], _world.home_returns.at_position(next).global_position) > HOME_RADIUS + 2.0 * RoachScale.GEOMETRY
			_bank(food, airmail)
			return
		velocity = velocity.bounce(normal) * float(Catalog.info(food["kind"])["bounce"])
		if normal.y > 0.65 and (absf(velocity.y) < 0.9 * RoachScale.GEOMETRY or float(food["flight_time"]) > 2.5):
			food["state"] = AVAILABLE
			velocity = Vector3.ZERO
			food["pos"] = next
			food["vel"] = velocity
			if hit["collider"] is AnimatableBody3D:
				var support := hit["collider"] as Node3D
				_supports[int(food["id"])] = {"body": support, "offset": support.to_local(next)}
			_publish()
			return
	food["pos"] = next
	food["vel"] = velocity
	if not next.is_finite() or not recovery_bounds.has_point(next) or float(food["flight_time"]) > 5.0:
		food["state"] = AVAILABLE
		food["pos"] = _origins[int(food["id"])]
		food["vel"] = Vector3.ZERO
		food["relay"] = false
		_announce("Lost snack returned to its crumb patch", "drop", food["pos"])
		_publish()

func _measure_motion(peer_id: int, token: Node3D, delta: float) -> void:
	var yaw: float = token.cockroach_model.rotation.y
	var previous: Dictionary = _motion.get(peer_id, {"pos": token.global_position, "yaw": yaw, "speed": 0.0, "turn": 0.0})
	var speed := _flat_distance(token.global_position, previous["pos"]) / (delta * RoachScale.MOVEMENT)
	var turn := absf(wrapf(yaw - float(previous["yaw"]), -PI, PI)) / delta
	# Smooth packet-sized displacement before using it as a gameplay stressor.
	_motion[peer_id] = {"pos": token.global_position, "yaw": yaw,
		"speed": lerpf(float(previous["speed"]), minf(speed, 35.0), 1.0 - exp(-7.0 * delta)),
		"turn": lerpf(float(previous["turn"]), minf(turn, 20.0), 1.0 - exp(-7.0 * delta))}

func _update_load(peer_id: int, delta: float) -> void:
	var ids := get_cargo_ids(peer_id)
	if ids.is_empty():
		_stress[peer_id] = 0.0
		_unload[peer_id] = 0.0
		return
	var speed := float(_motion[peer_id]["speed"])
	var turn := float(_motion[peer_id]["turn"])
	var token := _token(peer_id)
	if _near_home(token.global_position) and speed < 1.4:
		_unload[peer_id] = float(_unload.get(peer_id, 0.0)) + delta
		_stress[peer_id] = maxf(float(_stress.get(peer_id, 0.0)) - delta, 0.0)
		if float(_unload[peer_id]) >= UNLOAD_SECONDS:
			_unload[peer_id] = 0.0
			_bank(_foods[ids.front()], false)
		return
	_unload[peer_id] = 0.0
	var wobble := 0.0
	for id: int in ids:
		wobble += float(Catalog.info(_foods[id]["kind"])["wobble"])
	var pressure := (maxf(speed - 3.3, 0.0) * 0.065 + turn * 0.075) * wobble
	var stress := clampf(float(_stress.get(peer_id, 0.0)) + (pressure - 0.24) * delta, 0.0, 1.0) if ids.size() > 1 else 0.0
	_stress[peer_id] = stress
	if stress >= 1.0:
		_launch_top(peer_id, token.cockroach_model.global_basis.x.normalized(), false, true)

func _bank(food: Dictionary, airmail: bool) -> void:
	if not _running() or int(food["state"]) == BANKED:
		return
	var carrier := int(food["carrier"])
	var at: Vector3 = _token(carrier).global_position if carrier > 0 else food["pos"]
	var home: Area3D = _world.home_returns.at_position(at)
	if home == null: return
	var value := int(Catalog.info(food["kind"])["value"])
	var bonus := (1 if airmail else 0) + (1 if bool(food["relay"]) else 0)
	# Consume before scoring, so another overlap/RPC cannot bank the same item.
	food["state"] = BANKED
	food["carrier"] = 0
	food["vel"] = Vector3.ZERO
	var index := int(food["id"])
	food["pos"] = home.global_position + Vector3(sin(index * 2.4) * 1.2, 0.24 + (index % 3) * 0.17, cos(index * 2.4) * 1.2) * RoachScale.GEOMETRY
	_normalize_slots(carrier)
	if airmail:
		_stats["airmail"] += 1
	if bool(food["relay"]):
		_stats["relay"] += 1
	var tag := "AIR MAIL" if airmail else ("RELAY DELIVERY" if bool(food["relay"]) else "HOME DELIVERY")
	_announce("%s  +%d serving%s" % [tag, value + bonus, "" if value + bonus == 1 else "s"], "bank", home.global_position)
	_world.accept_food_delivery(value + bonus)
	_publish()

func release_peer(peer_id: int) -> void:
	if not _is_host():
		return
	# Preserve finite food supply when somebody disconnects mid-haul.
	var ids := get_cargo_ids(peer_id)
	var positions: Dictionary[int, Vector3] = {}
	for id: int in ids:
		positions[id] = _cargo_position(_foods[id])
	for id: int in ids:
		var food := _foods[id]
		food["pos"] = positions[id]
		food["state"] = FLYING
		food["carrier"] = 0
		food["vel"] = Vector3.UP * RoachScale.GEOMETRY
		food["thrower"] = 0
		food["flight_time"] = 0.0
	_motion.erase(peer_id)
	_stress.erase(peer_id)
	_unload.erase(peer_id)
	_action_times.erase(peer_id)
	_publish()

func _normalize_slots(peer_id: int) -> void:
	var ids := get_cargo_ids(peer_id)
	for index: int in ids.size():
		_foods[ids[index]]["slot"] = index

func get_cargo_ids(peer_id: int) -> Array[int]:
	var ids: Array[int] = []
	for food: Dictionary in _foods:
		if int(food["state"]) == CARRIED and int(food["carrier"]) == peer_id:
			ids.append(int(food["id"]))
	ids.sort_custom(func(a: int, b: int) -> bool: return int(_foods[a]["slot"]) < int(_foods[b]["slot"]))
	return ids

func get_cargo_weight(peer_id: int) -> float:
	var weight := 0.0
	for id: int in get_cargo_ids(peer_id):
		weight += float(Catalog.info(_foods[id]["kind"])["weight"])
	return weight

func get_food_records() -> Array[Dictionary]:
	return _foods.duplicate(true)

func get_stats() -> Dictionary:
	return _stats.duplicate()

## Development-room layout changes use the normal finite-supply reset afterward.
func set_solo_origins(origins: Array[Vector3]) -> void:
	var net := get_node("/root/Net")
	if not _is_host() or not net.is_solo_test() or origins.size() != _origins.size(): return
	for at: Vector3 in origins:
		if not at.is_finite(): return
	_origins.assign(origins)

func get_stress(peer_id: int) -> float:
	return float(_stress.get(peer_id, 0.0))

func get_unload_progress(peer_id: int) -> float:
	return clampf(float(_unload.get(peer_id, 0.0)) / UNLOAD_SECONDS, 0.0, 1.0)

func get_spawn_positions() -> Array[Vector3]:
	return _origins.duplicate()

func is_at_home(peer_id: int) -> bool:
	var token := _token(peer_id)
	return token != null and _near_home(token.global_position)

func _cargo_position(food: Dictionary) -> Vector3:
	var carrier := _token(int(food["carrier"]))
	if carrier == null:
		return food["pos"]
	var height := 0.55 * RoachScale.GEOMETRY
	for id: int in get_cargo_ids(int(food["carrier"])):
		if id == int(food["id"]):
			break
		height += float(Catalog.info(_foods[id]["kind"])["height"]) * 0.82
	height += float(Catalog.info(food["kind"])["radius"])
	return carrier.global_position + Vector3.UP * height + carrier.cockroach_model.global_basis.z.normalized() * (0.18 * RoachScale.GEOMETRY)

func _token(peer_id: int) -> Node3D:
	return _world.players.get_node_or_null(str(peer_id)) as Node3D

func _near_home(position: Vector3) -> bool:
	return _world.home_returns.at_position(position) != null

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func send_snapshot(peer_id: int) -> void:
	if _is_host() and peer_id > 1:
		_receive_state.rpc_id(peer_id, _snapshot())

func _snapshot() -> Dictionary:
	return {"revision": _revision, "foods": _foods.duplicate(true), "stress": _stress.duplicate(), "unload": _unload.duplicate(), "stats": _stats.duplicate(), "clock": _clock}

func _publish() -> void:
	_revision += 1
	for peer_id: int in _world.get_ready_peer_ids():
		if peer_id != 1:
			send_snapshot(peer_id)

@rpc("authority", "call_remote", "reliable")
func _receive_state(snapshot: Dictionary) -> void:
	if int(snapshot["revision"]) < _revision:
		return
	_revision = int(snapshot["revision"])
	_foods.assign(snapshot["foods"])
	_stress = snapshot["stress"]
	_unload = snapshot["unload"]
	_stats = snapshot["stats"]
	_clock = float(snapshot["clock"])
	_visual_age = 0.0

func _publish_motion() -> void:
	_motion_tick += 1
	var rows: Array = []
	for food: Dictionary in _foods:
		if int(food["state"]) == FLYING or (int(food["state"]) == AVAILABLE and _supports.has(int(food["id"]))):
			rows.append([food["id"], food["pos"], food["vel"]])
	for peer_id: int in _world.get_ready_peer_ids():
		if peer_id != 1:
			_receive_motion.rpc_id(peer_id, _revision, _motion_tick, rows, _stress, _unload)

@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _receive_motion(revision: int, tick: int, rows: Array, stress: Dictionary, unload: Dictionary) -> void:
	# A late flight packet must never resurrect a carried or already banked item.
	if revision != _revision or tick <= _last_motion_tick:
		return
	_last_motion_tick = tick
	for row: Array in rows:
		var id := int(row[0])
		if id >= 0 and id < _foods.size() and int(_foods[id]["state"]) in [AVAILABLE, FLYING]:
			_foods[id]["pos"] = row[1]
			_foods[id]["vel"] = row[2]
	_stress = stress
	_unload = unload
	_visual_age = 0.0

func _announce(message: String, kind: String, at: Vector3) -> void:
	_receive_feedback(message, kind, at)
	for peer_id: int in _world.get_ready_peer_ids():
		if peer_id != 1:
			_receive_feedback.rpc_id(peer_id, message, kind, at)

func _reject(peer_id: int, message: String) -> void:
	if peer_id == 1:
		_receive_feedback(message, "error", Vector3.ZERO)
	else:
		_receive_feedback.rpc_id(peer_id, message, "error", Vector3.ZERO)

@rpc("authority", "call_remote", "reliable")
func _receive_feedback(message: String, kind: String, at: Vector3) -> void:
	feedback.emit(message, kind, at)


## Cosmetic aiming samples the same launch constants and world collision mask.
func get_throw_preview(peer_id: int, direction: Vector3) -> PackedVector3Array:
	var points := PackedVector3Array()
	var ids := get_cargo_ids(peer_id)
	if ids.is_empty():
		return points
	var food := _foods[ids.back()]
	var origin := _cargo_position(food)
	var radius := float(Catalog.info(food["kind"])["radius"])
	direction.y = 0.0
	var velocity := direction.normalized() * THROW_SPEED + Vector3.UP * THROW_LIFT
	var previous := origin
	points.append(origin)
	for index: int in range(1, 25):
		var t := index * 0.06
		var next := origin + velocity * t - Vector3.UP * GRAVITY * t * t * 0.5
		var query := PhysicsRayQueryParameters3D.create(previous - Vector3.UP * radius, next - Vector3.UP * radius, 1, _player_rids())
		var hit := _world.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			points.append((hit["position"] as Vector3) + Vector3.UP * (0.04 * RoachScale.GEOMETRY))
			break
		points.append(next)
		previous = next
	return points


func _cargo_top(peer_id: int, extra_id: int = -1) -> float:
	var ids := get_cargo_ids(peer_id)
	if extra_id >= 0:
		ids.append(extra_id)
	var top := 0.55 * RoachScale.GEOMETRY
	for index: int in ids.size():
		var info := Catalog.info(_foods[ids[index]]["kind"])
		top += float(info["radius"]) * 2.0 if index == ids.size() - 1 else float(info["height"]) * 0.82
	return top

func _step_support(food: Dictionary) -> void:
	var id := int(food["id"])
	if not _supports.has(id):
		return
	var support: Node3D = _supports[id]["body"]
	if not is_instance_valid(support):
		_supports.erase(id)
		food["state"] = FLYING
		food["vel"] = Vector3.ZERO
		food["flight_time"] = 0.0
		_publish()
		return
	food["pos"] = support.to_global(_supports[id]["offset"])
