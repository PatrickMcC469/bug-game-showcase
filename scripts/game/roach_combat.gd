extends Node
## Host-owned health and ghost lifecycle, separate from owner movement Sync.
const Ballistics := preload("res://scripts/game/shotgun_ballistics.gd")
signal damaged(peer_id: int, amount: int, kind: String)
const MAX_HEALTH := 100
const GHOST_SECONDS := 10.0
var _world: Node3D
var _states: Dictionary = {}
var _view: Dictionary = {}
var _last_shots: Dictionary = {}
var _hazard_grace_until: Dictionary = {}
var _revision := 0
var _received_revision := -1
var _sync_left := 0.0
var _snapshot_age := 0.0

func setup(world: Node3D) -> void:
	_world = world

func register_peer(peer_id: int, at: Vector3) -> void:
	if not _is_host() or _states.has(peer_id): return
	_states[peer_id] = {"health": MAX_HEALTH, "ghost_left": 0.0, "hit_serial": 0,
		"respawn_serial": 0, "respawn_position": at, "initial_spawn": at}

func remove_peer(peer_id: int) -> void:
	_states.erase(peer_id)
	_view.erase(peer_id)
	_last_shots.erase(peer_id)
	_hazard_grace_until.erase(peer_id)
	if _is_host(): publish()

func reset_round() -> void:
	if not _is_host(): return
	for peer_id: int in _states:
		var state: Dictionary = _states[peer_id]
		if int(state.health) == 0: _respawn(peer_id)
		state.health = MAX_HEALTH
		state.ghost_left = 0.0
	publish()

func get_state(peer_id: int) -> Dictionary:
	var source: Dictionary = _states if _is_host() else _view
	return source.get(peer_id, {"health": MAX_HEALTH, "ghost_left": 0.0,
		"hit_serial": 0, "respawn_serial": 0, "respawn_position": Vector3.ZERO}).duplicate()

func is_ghost(peer_id: int) -> bool:
	return _world.get_role_for_peer(peer_id) == "cockroach" and int(get_state(peer_id).health) == 0

func _physics_process(delta: float) -> void:
	if _world == null or not _is_host(): return
	var ticking := false
	var changed := false
	for peer_id: int in _states:
		var state: Dictionary = _states[peer_id]
		if int(state.health) != 0: continue
		ticking = true
		state.ghost_left = maxf(0, float(state.ghost_left) - delta)
		if float(state.ghost_left) <= 0:
			_respawn(peer_id)
			changed = true
	_sync_left -= delta
	if changed or (ticking and _sync_left <= 0):
		_sync_left = 0.2
		publish()

func _process(delta: float) -> void:
	if _world == null: return
	_snapshot_age += delta
	for token: Node in _world.players.get_children():
		var state := get_state(token.name.to_int())
		if not _is_host():
			state.ghost_left = maxf(0, float(state.ghost_left) - _snapshot_age)
		token.apply_combat_state(state)

func fire_shot(shooter_id: int, nonce: int, yaw: float, direction: Vector3) -> Dictionary:
	if not _is_host() or not _world.is_peer_ready(shooter_id): return {}
	if _world.get("gas_weapon") != null and _world.gas_weapon.is_selected(shooter_id): return {}
	if _world.get_role_for_peer(shooter_id) != "exterminator" or _world.get_match_phase() > 1: return {}
	if _world.get("food_carry") != null and _world.food_carry.immobilized(shooter_id): return {}
	if nonce <= int(_last_shots.get(shooter_id, 0)): return {}
	if not direction.is_finite() or absf(direction.length_squared() - 1.0) > 0.01: return {}
	var shooter := _world.players.get_node_or_null(str(shooter_id)) as CharacterBody3D
	if shooter == null: return {}
	if _world.get("shotgun_ammo") != null and not _world.shotgun_ammo.consume_shell(shooter_id): return {}
	_last_shots[shooter_id] = nonce
	var exclude: Array[RID] = [shooter.get_rid()]
	for token: CharacterBody3D in _world.players.get_children():
		if is_ghost(token.name.to_int()): exclude.append(token.get_rid())
	var chest := shooter.global_position + Vector3.UP * 1.4
	var grip := shooter.global_position + Basis(Vector3.UP, yaw) * Vector3(0.13, 1.40, -0.19)
	var shot := Ballistics.trace(shooter.get_world_3d().direct_space_state, chest, grip,
		direction, exclude, shooter.collision_mask, nonce * 7919 + shooter_id)
	var damages: Dictionary = {}
	for hit: Dictionary in shot.hits:
		var victim: Node = hit.collider
		if victim.get_parent() != _world.players: continue
		var peer_id := victim.name.to_int()
		if _world.get_role_for_peer(peer_id) != "cockroach" or not _world.is_peer_ready(peer_id): continue
		damages[peer_id] = int(damages.get(peer_id, 0)) + int(hit.damage)
	var victims := PackedInt32Array()
	if _world.get_match_phase() == 1:
		for peer_id: int in damages:
			if _damage(peer_id, damages[peer_id], "kinetic"): victims.append(peer_id)
	if not victims.is_empty(): publish()
	_receive_shot(shooter_id, direction, shot.origin, shot.ends, victims)
	for peer_id: int in _world.get_ready_peer_ids():
		if peer_id != 1: _receive_shot.rpc_id(peer_id, shooter_id, direction, shot.origin, shot.ends, victims)
	shot["victims"] = victims
	return shot

func kill_from_environment(peer_id: int) -> bool:
	return damage_from_environment(peer_id, MAX_HEALTH)

func damage_from_environment(peer_id: int, amount: int) -> bool:
	# The owner applies respawn movement after the host's physics tick; allow
	# that position to replicate before judging the old hazard overlap again.
	if Time.get_ticks_msec() < int(_hazard_grace_until.get(peer_id, 0)): return false
	if not _damage(peer_id, amount): return false
	publish()
	return true

func _damage(peer_id: int, amount: int, kind: String = "environment") -> bool:
	if not _is_host() or _world.get_match_phase() != 1 or amount <= 0: return false
	if _world.get_role_for_peer(peer_id)!="cockroach" or not _world.is_peer_ready(peer_id): return false
	if not _states.has(peer_id) or is_ghost(peer_id): return false
	var state: Dictionary = _states[peer_id]
	state.health = maxi(0, int(state.health) - amount)
	state.hit_serial = int(state.hit_serial) + 1
	if int(state.health) == 0:
		state.ghost_left = GHOST_SECONDS
		# Reuse the existing finite-supply release path; ghosts cannot carry cargo.
		_world.food_run.release_peer(peer_id)
	damaged.emit(peer_id, amount, kind)
	return true

func _respawn(peer_id: int) -> void:
	_hazard_grace_until[peer_id] = Time.get_ticks_msec() + 1000
	var state: Dictionary = _states[peer_id]
	state.health = MAX_HEALTH
	state.ghost_left = 0.0
	state.respawn_serial = int(state.respawn_serial) + 1
	state.respawn_position = _safe_home_position(peer_id, state.initial_spawn)

func _safe_home_position(peer_id: int, fallback: Vector3) -> Vector3:
	var token := _world.players.get_node_or_null(str(peer_id)) as CharacterBody3D
	if token == null: return fallback
	var space := token.get_world_3d().direct_space_state
	var radius: float = token.roach_collision.shape.radius
	for offset: Vector3 in [Vector3.ZERO, Vector3(0.06,0,0), Vector3(-0.06,0,0),
			Vector3(0,0,0.06), Vector3(0,0,-0.06), Vector3(0.12,0,0), Vector3(-0.12,0,0)]:
		var at: Vector3 = _world.home_base.global_position + offset
		var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			at + Vector3.UP * 0.2, at - Vector3.UP * 0.3, token.collision_mask, [token.get_rid()]))
		if floor_hit.is_empty() or (floor_hit.normal as Vector3).y < 0.9: continue
		at = floor_hit.position + Vector3.UP * 0.001
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = token.roach_collision.shape
		query.transform = Transform3D(Basis(Vector3.RIGHT, PI/2), at + Vector3.UP * radius)
		query.exclude = [token.get_rid()]
		query.collision_mask = token.collision_mask
		if space.intersect_shape(query, 1).is_empty(): return at
	return fallback

func publish(target_peer: int = 0) -> void:
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
	_view = states.duplicate(true)
	_snapshot_age = 0.0

@rpc("authority", "call_remote", "reliable")
func _receive_shot(shooter_id: int, direction: Vector3, origin: Vector3,
		ends: PackedVector3Array, victims: PackedInt32Array) -> void:
	var token: Node = _world.players.get_node_or_null(str(shooter_id))
	if token != null: token.shotgun.present_impacts(direction, origin, ends, not victims.is_empty())

func _is_host() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()
