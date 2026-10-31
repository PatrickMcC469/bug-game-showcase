extends Node3D
## The host owns loose-food availability; clients render snapshots.
## FoodCarry validates pickup before transferring possession with take_food.
const Types := preload("res://scripts/game/food_types.gd")
@export_range(1, 32) var target_count := 12
@export_range(0, 31) var low_count := 3
@export_range(0.1, 120.0) var refill_seconds := 15.0
var _world: Node3D
var _spots: Dictionary[String, Marker3D] = {}
var _records: Array[Dictionary] = []
var _models: Dictionary[int, Node3D] = {}
var _rng := RandomNumberGenerator.new()
var _next_id := 1
var _revision := 0
var _received_revision := -1
var _initial := true
var _refill_left := -1.0
var _retry_left := 0.0
var _sync_left := 0.0
var _wave := 0

func setup(world: Node3D) -> void:
	_world = world
	_rng.randomize()
	for marker: Node in world.find_children("*", "Marker3D", true, false):
		if marker.is_in_group("food_spawn_spots"):
			_spots[str(world.get_path_to(marker))] = marker

func _host() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()

func reset_supply() -> void:
	if not _host(): return
	_records.clear()
	_initial = true
	_refill_left = -1.0
	_retry_left = 0.0
	_wave = 0
	_publish()

func _physics_process(delta: float) -> void:
	if _world == null or not _host() or _world.get_match_phase() != 1: return
	_step_dropped(delta)
	_retry_left = maxf(0.0, _retry_left - delta)
	if _initial:
		if _retry_left <= 0.0:
			_spawn_wave()
			_initial = false
	elif _records.size() > mini(low_count, target_count - 1):
		_refill_left = -1.0
	else:
		if _refill_left < 0.0: _refill_left = maxf(0.1, refill_seconds)
		_refill_left = maxf(0.0, _refill_left - delta)
		if _refill_left <= 0.0 and _retry_left <= 0.0:
			_spawn_wave()
			_refill_left = -1.0 if _records.size() > mini(low_count, target_count - 1) else 0.0
	_sync_left -= delta
	if _sync_left <= 0.0:
		_sync_left = 1.0
		_publish()

## A trusted server-side transfer primitive, deliberately not an RPC or input.
## No scoring/carry choice is made by this spawning stage.
func take_food(id: int) -> Dictionary:
	if not _host() or _world == null or _world.get_match_phase() != 1: return {}
	for index: int in _records.size():
		if int(_records[index].id) == id:
			var record: Dictionary = _records[index].duplicate(true)
			_records.remove_at(index)
			_publish()
			return record
	return {}

func get_records() -> Array[Dictionary]:
	return _records.duplicate(true)

func get_status() -> Dictionary:
	return {"available": _records.size(), "spots": _spots.size(), "wave": _wave,
		"refill_left": _refill_left, "target": target_count}

func get_spot_positions() -> Dictionary:
	var result := {}
	for id: String in _spots: result[id] = _spots[id].global_position
	return result

func _spawn_wave() -> void:
	_retry_left = 1.0
	var occupied := {}
	for record: Dictionary in _records: occupied[record.spot] = true
	var candidates: Array[String] = []
	for id: String in _spots:
		var nearby := false
		for record: Dictionary in _records:
			if (record.position as Vector3).distance_to(_spots[id].global_position) < 0.08: nearby = true
		if not occupied.has(id) and not nearby and is_spot_clear(id): candidates.append(id)
	# Shuffle on the host once per wave. Peers never roll their own locations.
	for index: int in range(candidates.size() - 1, 0, -1):
		var other := _rng.randi_range(0, index)
		var swap := candidates[index]
		candidates[index] = candidates[other]
		candidates[other] = swap
	var held_count: int = _world.food_carry.carried_count() if _world.get("food_carry") != null else 0
	var count := mini(maxi(0, mini(target_count, 32 - held_count) - _records.size()), candidates.size())
	var offset := _rng.randi_range(0, Types.IDS.size() - 1)
	for index: int in count:
		var id := candidates[index]
		_records.append({"id": _next_id, "type": str(Types.IDS[(index + offset) % Types.IDS.size()]),
			"spot": id, "position": _spots[id].global_position, "yaw": _rng.randf_range(-PI, PI)})
		_next_id += 1
	if count > 0: _wave += 1
	_publish()

func is_spot_clear(id: String) -> bool:
	if not _spots.has(id): return false
	var at := _spots[id].global_position
	if not _world.home_returns.allows_food_spawn(at): return false
	var space := get_world_3d().direct_space_state
	# A marker rests on a solid surface. A conservative food-sized volume above
	# it prevents spawning into dressing or a closed lid; actors also block it.
	var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.004, at - Vector3.UP * 0.012, 1))
	if floor_hit.is_empty() or floor_hit.normal.y < 0.9: return false
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.075, 0.034, 0.075)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.019)
	query.collision_mask = 1
	query.margin = 0.0001
	if not space.intersect_shape(query, 1).is_empty(): return false
	for player: Node3D in _world.players.get_children():
		if player.global_position.distance_to(at) < 0.15: return false
	return true

## Only trusted host carry code returns an existing piece; IDs never duplicate.
func return_food(record: Dictionary) -> void:
	if not _host(): return
	for existing: Dictionary in _records:
		if existing.id == record.id: return
	_records.append(record.duplicate(true))
	_publish()

func _step_dropped(delta: float) -> void:
	var changed := false
	var excludes: Array[RID] = []
	for token: CharacterBody3D in _world.players.get_children(): excludes.append(token.get_rid())
	var space := get_world_3d().direct_space_state
	for record: Dictionary in _records:
		if not bool(record.get("falling", false)): continue
		var velocity: Vector3 = record.get("velocity", Vector3.ZERO)
		velocity.y -= 0.5 * delta
		var at: Vector3 = record.position
		var next := at + velocity * delta
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.003, next - Vector3.UP * 0.001, 1, excludes))
		if not hit.is_empty():
			record.position = hit.position + hit.normal * 0.001
			record.falling = false
		else:
			record.position = next
			record.velocity = velocity
			if next.y < -3.0:
				# Recovery uses the existing authored map spots rather than deleting food.
				for id: String in _spots:
					if is_spot_clear(id):
						record.position = _spots[id].global_position
						record.spot = id
						record.falling = false
						break
		changed = true
	if changed: _publish()

func send_snapshot(peer_id: int) -> void:
	if _host() and _world.is_peer_ready(peer_id): _receive_snapshot.rpc_id(peer_id, _snapshot())

func _snapshot() -> Dictionary:
	return {"revision": _revision, "records": _records.duplicate(true), "wave": _wave, "refill_left": _refill_left}

func _publish() -> void:
	_revision += 1
	_present()
	for peer_id: int in _world.get_ready_peer_ids():
		if peer_id != 1: send_snapshot(peer_id)

@rpc("authority", "call_remote", "reliable")
func _receive_snapshot(snapshot: Dictionary) -> void:
	if _host() or int(snapshot.revision) <= _received_revision: return
	_received_revision = int(snapshot.revision)
	_records.assign(snapshot.records)
	_wave = int(snapshot.wave)
	_refill_left = float(snapshot.refill_left)
	_present()

func _present() -> void:
	var keep := {}
	for record: Dictionary in _records:
		var id := int(record.id)
		keep[id] = true
		if not _models.has(id):
			var model := Types.model(StringName(record.type))
			if model == null: continue
			model.name = "Food_%d" % id
			model.set_multiplayer_authority(1)
			add_child(model)
			_models[id] = model
		_models[id].global_position = record.position
		_models[id].rotation.y = float(record.yaw)
	for id: int in _models.keys():
		if not keep.has(id):
			_models[id].free()
			_models.erase(id)
