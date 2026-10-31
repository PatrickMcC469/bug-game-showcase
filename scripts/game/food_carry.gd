extends Node3D
## Server-owned single-item carrying/effects. Owner movement consumes replicated modifiers.
const Types := preload("res://scripts/game/food_types.gd")
const REACH := 0.085
var world: Node3D
var _held: Dictionary = {}
var _effects: Dictionary = {}
var _slicks: Array[Dictionary] = []
var _models: Dictionary = {}
var _grease_models: Dictionary = {}
var _ice_models: Dictionary = {}
var _profiles: Dictionary = {}
var _action_until: Dictionary = {}
var _clock := 0.0
var _next_slick := 1
var _revision := 0
var _received := -1
var _sync_left := 0.0
var _unload: Dictionary = {}

func setup(owner_world: Node3D) -> void:
	world = owner_world
	for id: StringName in Types.IDS: _profiles[str(id)] = Types.definition(id)
	world.combat.damaged.connect(_on_damage)

func _host() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()

func _running() -> bool:
	return world != null and world.get_match_phase() == 1

func held(peer_id: int) -> Dictionary:
	return _held.get(peer_id, {}).duplicate(true)

func status(peer_id: int) -> Dictionary:
	return _effects.get(peer_id, {}).duplicate(true)

func immobilized(peer_id: int) -> bool:
	var state := status(peer_id)
	return float(state.get("frozen", 0.0)) > 0 or float(state.get("trip", 0.0)) > 0

func carried_count() -> int:
	return _held.size()

func _state(peer_id: int) -> Dictionary:
	if not _effects.has(peer_id):
		_effects[peer_id] = {"cold": 0.0, "frozen": 0.0, "trip": 0.0, "immune": 0.0,
			"damage": 0.0, "grease": 0.0, "speed": 1.0, "wobble": 0.0}
	return _effects[peer_id]

func reset_round() -> void:
	if not _host(): return
	_held.clear()
	_effects.clear()
	_slicks.clear()
	_action_until.clear()
	_unload.clear()
	_publish()

func _token(peer_id: int) -> CharacterBody3D:
	return world.players.get_node_or_null(str(peer_id)) as CharacterBody3D

func _excludes() -> Array[RID]:
	var result: Array[RID] = []
	for token: CharacterBody3D in world.players.get_children(): result.append(token.get_rid())
	return result

func _visible(from: Vector3, to: Vector3) -> bool:
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1, _excludes())).is_empty()

func candidate(peer_id: int) -> int:
	if not _running() or world.get_role_for_peer(peer_id) != "cockroach" or world.combat.is_ghost(peer_id): return -1
	var token := _token(peer_id)
	if token == null or immobilized(peer_id) or not held(peer_id).is_empty(): return -1
	if not world.food_run.get_cargo_ids(peer_id).is_empty(): return -1
	var best := -1
	var distance := REACH
	var from: Vector3 = token.global_position + token.cockroach_model.basis.orthonormalized().y * 0.012
	for record: Dictionary in world.food_supply.get_records():
		var target: Vector3 = record.position + Vector3.UP * 0.008
		var reach := from.distance_to(target)
		if reach < distance and _visible(from, target):
			distance = reach
			best = int(record.id)
	return best

func _unhandled_input(event: InputEvent) -> void:
	if not _running() or not multiplayer.has_multiplayer_peer() or event.is_echo(): return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return
	var peer := multiplayer.get_unique_id()
	if world.get_role_for_peer(peer) != "cockroach": return
	if event.is_action_pressed("food_drop") and not held(peer).is_empty(): request_action("drop")
	elif event.is_action_pressed("food_grab") and candidate(peer) >= 0: request_action("grab", candidate(peer))
	elif event.is_action_pressed("food_scent") and not held(peer).is_empty(): request_action("grease")

func request_action(action: String, food_id: int = -1) -> void:
	if not multiplayer.has_multiplayer_peer(): return
	if _host(): _action(1, action, food_id)
	else: _request.rpc_id(1, action, food_id)

@rpc("any_peer", "call_remote", "reliable")
func _request(action: String, food_id: int) -> void:
	if _host(): _action(multiplayer.get_remote_sender_id(), action, food_id)

func _action(peer: int, action: String, food_id: int) -> bool:
	if not _host() or not _running() or not world.is_peer_ready(peer): return false
	if world.get_role_for_peer(peer) != "cockroach" or world.combat.is_ghost(peer): return false
	# Dropping is always available; pickup/squeezing are blocked during freezing.
	if action == "drop": return drop(peer)
	if immobilized(peer) or _clock < float(_action_until.get(peer, 0.0)): return false
	_action_until[peer] = _clock + 0.15
	if action == "grease": return _squeeze(peer)
	if action != "grab" or candidate(peer) != food_id or food_id < 0: return false
	var token := _token(peer)
	var rows: Array = world.food_supply.get_records()
	for record: Dictionary in rows:
		if int(record.id) != food_id: continue
		if not _carry_fits(token): return false
		var taken: Dictionary = world.food_supply.take_food(food_id)
		if taken.is_empty(): return false
		_held[peer] = taken
		_publish()
		return true
	return false

func _carry_fits(token: CharacterBody3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.06, 0.035, 0.06)
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, token.global_position + Vector3.UP * 0.04)
	query.collision_mask = 1
	query.exclude = _excludes()
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func drop(peer: int) -> bool:
	if not _host() or not _held.has(peer): return false
	var token := _token(peer)
	var record: Dictionary = _held[peer].duplicate(true)
	# Release from the bug's clear body volume, then let the host settle it.
	if token != null:
		record.position = _drop_position(token)
		record.yaw = token.cockroach_model.rotation.y
	_held.erase(peer)
	_unload.erase(peer)
	record.spot = ""
	record["falling"] = true
	record["velocity"] = Vector3.ZERO
	world.food_supply.return_food(record)
	var state := _state(peer)
	state.speed = 1.0
	state.wobble = 0.0
	if token != null: token.set_food_effects(1.0, 0.0, float(state.frozen), float(state.trip))
	_publish()
	return true

func _drop_position(token: CharacterBody3D) -> Vector3:
	var basis: Basis = token.cockroach_model.basis.orthonormalized()
	var start: Vector3 = token.global_position + basis.y * 0.012
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.06, 0.03, 0.06)
	for direction: Vector3 in [-basis.z, basis.x, -basis.x, basis.z]:
		var at := start + direction * 0.06
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.016)
		query.exclude = _excludes()
		query.collision_mask = 1
		if _visible(start, at) and get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return at
	return start

func release_peer(peer: int) -> void:
	if not _host(): return
	drop(peer)
	_effects.erase(peer)
	_action_until.erase(peer)
	_publish()

func _on_damage(peer: int, _amount: int, kind: String) -> void:
	if not _host(): return
	if kind == "kinetic" or world.combat.is_ghost(peer):
		drop(peer)
		world.food_run.release_peer(peer)
	if world.combat.is_ghost(peer): _effects.erase(peer)

func _physics_process(delta: float) -> void:
	if not _host() or not _running(): return
	_clock += delta
	for peer: int in world.get_ready_peer_ids():
		var state := _state(peer)
		for key: String in ["frozen", "trip", "immune", "grease"]: state[key] = maxf(0.0, float(state[key]) - delta)
		state.speed = 1.0
		state.wobble = 0.0
		var item := held(peer)
		if item.is_empty() or world.combat.is_ghost(peer):
			state.cold = maxf(0.0, float(state.cold) - 15.0 / 4.0 * delta)
			continue
		var profile: Resource = _profiles[item.type]
		match str(item.type):
			"spicy_pepper":
				state.speed = profile.speed_multiplier
				state.damage = float(state.damage) + profile.damage_per_second * delta
				var damage := floori(state.damage)
				if damage > 0:
					state.damage -= damage
					world.combat.damage_from_environment(peer, damage)
			"fermented_fruit": state.wobble = sin(_clock * TAU / profile.wobble_period_seconds) * profile.steering_wobble
			"frozen_food":
				state.cold = float(state.cold) + delta
				if state.cold >= profile.freeze_after_seconds:
					state.frozen = profile.freeze_duration_seconds
					state.cold = 0.0
					drop(peer)
		if str(item.type) != "frozen_food": state.cold = maxf(0, float(state.cold) - 15.0 / 4.0 * delta)
		# Both food catalogs bank through the same map-owned return entrances.
		var token := _token(peer)
		if _held.has(peer) and world.food_run.is_at_home(peer) and token.velocity.length() < 0.04:
			_unload[peer] = float(_unload.get(peer, 0.0)) + delta
			if float(_unload[peer]) >= 0.55:
				_held.erase(peer)
				_unload.erase(peer)
				world.accept_food_delivery(2)
		else: _unload.erase(peer)
	_step_slicks(delta)
	_sync_left -= delta
	if _sync_left <= 0.0:
		_sync_left = 0.1
		_publish()

func _squeeze(peer: int) -> bool:
	var item := held(peer)
	var state := _state(peer)
	if str(item.get("type", "")) != "french_fry" or float(state.grease) > 0: return false
	var token := _token(peer)
	var at := token.global_position
	var floor_hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.02, at - Vector3.UP * 0.04, 1, _excludes()))
	if floor_hit.is_empty() or floor_hit.normal.y < 0.9: return false
	var profile: Resource = _profiles["french_fry"]
	var owned: Array[int] = []
	for index: int in _slicks.size():
		if int(_slicks[index].owner) == peer: owned.append(index)
	if owned.size() >= profile.max_live_slicks: _slicks.remove_at(owned[0])
	_slicks.append({"id": _next_slick, "owner": peer, "position": floor_hit.position + Vector3.UP * 0.001, "yaw": token.cockroach_model.rotation.y, "left": profile.slick_lifetime_seconds})
	_next_slick += 1
	state.grease = profile.slick_interval_seconds
	_publish()
	return true

func _step_slicks(delta: float) -> void:
	for index: int in range(_slicks.size() - 1, -1, -1):
		_slicks[index].left -= delta
		if _slicks[index].left <= 0: _slicks.remove_at(index)
	for peer: int in world.get_ready_peer_ids():
		if world.get_role_for_peer(peer) != "exterminator": continue
		var state := _state(peer)
		if float(state.immune) > 0: continue
		var token := _token(peer)
		if token == null or Vector2(token.velocity.x, token.velocity.z).length() < 0.15: continue
		for slick: Dictionary in _slicks:
			var distance := token.global_position - (slick.position as Vector3)
			if absf(distance.y) < 0.06 and Vector2(distance.x, distance.z).length() < 0.23 and _visible(token.global_position + Vector3.UP * 0.02, slick.position + Vector3.UP * 0.02):
				var profile: Resource = _profiles["french_fry"]
				state.trip = profile.trip_duration_seconds
				state.immune = profile.trip_immunity_seconds
				break

func _process(_delta: float) -> void:
	if world == null: return
	for token: CharacterBody3D in world.players.get_children():
		var peer := token.name.to_int()
		var state := status(peer) if _running() else {}
		token.set_food_effects(float(state.get("speed", 1.0)), float(state.get("wobble", 0.0)), float(state.get("frozen", 0.0)), float(state.get("trip", 0.0)))
		if _held.has(peer):
			token.set_cargo(0, 0, 1)
			token.set_cargo_clearance(0.06)
			(token.get("_cargo_collision").shape as BoxShape3D).size.x = 0.06
			(token.get("_cargo_collision").shape as BoxShape3D).size.z = 0.06
		if _models.has(peer):
			_models[peer].global_position = token.global_position + Vector3.UP * 0.013
			_models[peer].rotation.y = token.cockroach_model.rotation.y
		if float(state.get("frozen", 0.0)) > 0:
			if not _ice_models.has(peer):
				var ice := MeshInstance3D.new()
				var shell := SphereMesh.new()
				shell.radius = 1.0
				shell.height = 2.0
				shell.radial_segments = 10
				shell.rings = 6
				ice.mesh = shell
				var material := StandardMaterial3D.new()
				material.albedo_color = Color(0.45, 0.8, 1.0, 0.55)
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				material.roughness = 0.25
				ice.material_override = material
				ice.name = "Frozen_%d" % peer
				ice.set_multiplayer_authority(1)
				add_child(ice)
				_ice_models[peer] = ice
			_ice_models[peer].global_transform = Transform3D(token.cockroach_model.basis.orthonormalized().scaled(Vector3(0.013, 0.011, 0.025)), token.global_position + Vector3.UP * 0.009)
		elif _ice_models.has(peer):
			_ice_models[peer].free()
			_ice_models.erase(peer)
	for peer: int in _ice_models.keys():
		if _token(peer) == null:
			_ice_models[peer].free()
			_ice_models.erase(peer)

func send_snapshot(peer: int) -> void:
	if _host() and world.is_peer_ready(peer): _receive.rpc_id(peer, _snapshot())

func _snapshot() -> Dictionary:
	return {"revision": _revision, "held": _held.duplicate(true), "effects": _effects.duplicate(true), "slicks": _slicks.duplicate(true)}

func _publish() -> void:
	_revision += 1
	_present()
	for peer: int in world.get_ready_peer_ids():
		if peer != 1: send_snapshot(peer)

@rpc("authority", "call_remote", "reliable")
func _receive(snapshot: Dictionary) -> void:
	if _host() or int(snapshot.revision) <= _received: return
	_received = int(snapshot.revision)
	_held = snapshot.held.duplicate(true)
	_effects = snapshot.effects.duplicate(true)
	_slicks.assign(snapshot.slicks)
	_present()

func _present() -> void:
	for peer: int in _models.keys():
		if not _held.has(peer) or _models[peer].get_meta("id") != _held[peer].id:
			_models[peer].free()
			_models.erase(peer)
	for peer: int in _held:
		if not _models.has(peer):
			var model := Types.model(StringName(_held[peer].type))
			model.name = "Carried_%d" % peer
			model.set_meta("id", _held[peer].id)
			model.set_multiplayer_authority(1)
			add_child(model)
			_models[peer] = model
	var live := {}
	for slick: Dictionary in _slicks:
		var id := int(slick.id)
		live[id] = true
		if not _grease_models.has(id):
			var visual := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.07
			mesh.bottom_radius = 0.075
			mesh.height = 0.0005
			visual.mesh = mesh
			visual.scale = Vector3(0.65, 1, 1.7)
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(0.18, 0.13, 0.035, 0.65)
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.roughness = 0.08
			visual.material_override = material
			visual.name = "Grease_%d" % id
			visual.set_multiplayer_authority(1)
			add_child(visual)
			visual.global_position = slick.position
			visual.rotation.y = slick.yaw
			_grease_models[id] = visual
	for id: int in _grease_models.keys():
		if not live.has(id):
			_grease_models[id].free()
			_grease_models.erase(id)
