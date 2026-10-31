extends Node
## Owner-only traversal over real physics surfaces. Root/camera stay upright;
## the existing model rotation snapshot also drives remote collision orientation.
const Scale := preload("res://scripts/game/roach_scale.gd")
const REACH := 0.038
const GAP := 0.001
const STEP_SIZE := 0.003
const CRAWL_SPEED := 0.65
var active := false
var _normal := Vector3.UP
var _frame := Basis.IDENTITY
var _camera_yaw := 0.0
var _cooldown := 0.0
var _path: Array[Transform3D] = []
var _path_index := 0
var _support: Node3D
var _support_transform := Transform3D.IDENTITY
@onready var token: CharacterBody3D = get_parent()

func step(delta: float) -> bool:
	_cooldown = maxf(0.0, _cooldown - delta)
	if not token.is_multiplayer_authority() or token.player_role != "cockroach": return false
	if token.climber.active: return false
	var input: Vector2 = token.food_input(Input.get_vector("move_left", "move_right", "move_forward", "move_back")) if token.can_read_movement_input() else Vector2.ZERO
	if not active:
		if _cooldown > 0.0 or not token.is_on_floor() or input.is_zero_approx(): return false
		_normal = token._surface_normal
		_frame = Basis(Quaternion(Vector3.UP, _normal)) * token.camera_rig.global_basis
		_camera_yaw = token.camera_rig.rotation.y
		var direction := (_frame.x * input.x + _frame.z * input.y).slide(_normal).normalized()
		if not _obstacle(direction) and not _edge(direction): return false
	if not _follow_support():
		cancel()
		return false
	if not _path.is_empty():
		_advance_path(delta)
		return true
	_frame = Basis(_normal, angle_difference(_camera_yaw, token.camera_rig.rotation.y)) * _frame
	_camera_yaw = token.camera_rig.rotation.y
	var direction := (_frame.x * input.x + _frame.z * input.y).slide(_normal).normalized()
	var pace: float = CRAWL_SPEED * token._cargo_speed_scale * token._food_speed
	if token.can_read_movement_input() and Input.is_action_pressed("sprint"): pace *= token.sprint_speed / token.move_speed
	token._dash_time_left = maxf(0, token._dash_time_left - delta)
	token._dash_cooldown_left = maxf(0, token._dash_cooldown_left - delta)
	if token.can_read_movement_input() and Input.is_action_just_pressed("dash") and token._dash_cooldown_left <= 0:
		token._dash_direction = direction if not direction.is_zero_approx() else -token.cockroach_model.basis.orthonormalized().z
		token._dash_time_left = token.dash_duration
		token._dash_cooldown_left = token.dash_cooldown
	if token._dash_time_left > 0:
		direction = token._dash_direction.slide(_normal).normalized()
		pace = token.dash_speed * Scale.MOVEMENT * token._cargo_speed_scale * token._food_speed
	var start := token.global_position
	var distance := pace * delta
	while distance > 0.00001 and not direction.is_zero_approx():
		if _obstacle(direction) or _edge(direction): break
		var amount := minf(distance, STEP_SIZE)
		var pose := _pose(_normal, direction)
		var at := token.global_position + direction * amount
		if not _move(at, pose): break
		distance -= amount
	token.velocity = (token.global_position - start) / maxf(delta, 0.001)
	if not _path.is_empty(): return true
	var support := _ray(token.global_position + _normal * 0.012, token.global_position - _normal * 0.018)
	if support.is_empty():
		cancel()
	elif _normal.dot(Vector3.UP) > 0.7:
		# Resume ordinary floor motion and its moving-platform/slope handling.
		_finish()
	return true

func cancel() -> void:
	active = false
	_path.clear()
	_support = null
	_cooldown = 0.3
	token._surface_normal = Vector3.UP
	token._dash_time_left = 0.0
	# Uprighting in a tight corner can itself intersect geometry. The normal
	# walking controller restores the floor pose once the detached body is clear.
	var upright := _pose(Vector3.UP, -token.camera_rig.global_basis.z)
	if _clear(token.global_position, upright):
		token.cockroach_model.basis = upright.scaled(Vector3.ONE * Scale.GEOMETRY)
		token._sync_roach_collision_pose()

func _obstacle(direction: Vector3) -> bool:
	if direction.is_zero_approx(): return false
	var at := token.global_position
	var hit := _ray(at + _normal * 0.004, at + _normal * 0.004 + direction * REACH)
	if hit.is_empty() or (hit.normal as Vector3).dot(_normal) > 0.7: return false
	# A tray lip shorter than the body is stepped over with a swept lift and
	# advance, rather than turning the entire insect vertical for a few mm.
	var top := _ray(at + direction * REACH + _normal * 0.045, at + direction * REACH - _normal * 0.002)
	if not top.is_empty() and (top.normal as Vector3).dot(_normal) > 0.95:
		var end: Vector3 = top.position + _normal * GAP
		if (end - at).dot(_normal) > 0.002:
			var lifted := at + _normal * ((end - at).dot(_normal) + GAP)
			return _plan(end, _normal, direction, hit.collider, lifted, true)
	var wall := _ray(at + _normal * REACH, at + _normal * REACH + direction * REACH)
	if wall.is_empty(): return false
	var next_normal: Vector3 = wall.normal
	if next_normal.dot(_normal) > 0.7 or next_normal.dot(direction) > -0.35: return false
	return _plan(wall.position + next_normal * _surface_gap(next_normal), next_normal, direction, wall.collider)

func _edge(direction: Vector3) -> bool:
	var at := token.global_position
	var ahead := at + direction * REACH
	if not _ray(ahead + _normal * 0.01, ahead - _normal * 0.016).is_empty(): return false
	# Probe around the outside edge onto the adjacent face. Only real nearby
	# support may create a transition; no bridging gaps or climbing other actors.
	var next := _ray(ahead - _normal * REACH, ahead - _normal * REACH - direction * REACH * 2)
	if next.is_empty() or (next.normal as Vector3).dot(_normal) > 0.7: return false
	var next_normal: Vector3 = next.normal
	var corner: Vector3 = next.position + _normal * REACH
	var control := corner + (_normal + next_normal) * REACH
	return _plan(next.position + next_normal * _surface_gap(next_normal), next_normal, direction, next.collider, control)

func _surface_gap(normal: Vector3) -> float:
	# Upright cargo needs its half-width outside vertical faces. Keep the
	# existing food pose/ownership, and still reject ceilings that hit the stack.
	if token.cargo_count > 0 and absf(normal.y) < 0.5:
		return GAP + (token._cargo_collision.shape as BoxShape3D).size.x * 0.5
	return GAP

func _plan(end: Vector3, next_normal: Vector3, direction: Vector3, body: Node3D, control: Vector3 = Vector3.INF, step_up: bool = false) -> bool:
	var at := token.global_position
	var turn := Quaternion(_normal, next_normal)
	var points: Array[Transform3D] = []
	var count := maxi(16, ceili((at.distance_to(end) + REACH * 2) / STEP_SIZE))
	for i: int in range(1, count + 1):
		var t := float(i) / count
		var normal := _normal.slerp(next_normal, t).normalized()
		var position := at.lerp(end, t)
		if control != Vector3.INF:
			position = at.lerp(control, t).lerp(control.lerp(end, t), t)
			if step_up:
				position = at.lerp(control, t * 2) if t < 0.5 else control.lerp(end, (t - 0.5) * 2)
		var pose := _pose(normal, Quaternion.IDENTITY.slerp(turn, t) * direction)
		if not _clear(position, pose): return false
		points.append(Transform3D(pose, position))
	_path = points
	_path_index = 0
	_frame = Basis(turn) * _frame
	_normal = next_normal
	_support = body
	_support_transform = body.global_transform
	active = true
	token._dash_time_left = 0.0
	return true

func _advance_path(delta: float) -> void:
	var distance: float = CRAWL_SPEED * token._cargo_speed_scale * token._food_speed * delta
	var start := token.global_position
	while distance > 0 and _path_index < _path.size():
		var next := _path[_path_index]
		var length := token.global_position.distance_to(next.origin)
		var fraction := minf(1.0, distance / maxf(length, 0.00001))
		var pose: Basis = token.cockroach_model.basis.orthonormalized().slerp(next.basis, fraction)
		if not _move(token.global_position.lerp(next.origin, fraction), pose):
			cancel()
			return
		distance -= length
		if fraction >= 1: _path_index += 1
	token.velocity = (token.global_position - start) / maxf(delta, 0.001)
	if _path_index == _path.size():
		_path.clear()
		if _normal.dot(Vector3.UP) > 0.7: _finish()

func _finish() -> void:
	active = false
	_support = null
	token._surface_normal = _normal
	token._facing_yaw = atan2(token.cockroach_model.basis.z.x, token.cockroach_model.basis.z.z)
	token.velocity = Vector3.ZERO

func _follow_support() -> bool:
	if not is_instance_valid(_support): return false
	if _support.global_transform.is_equal_approx(_support_transform): return true
	# A door/cart moving away releases the insect, rather than teleporting it
	# through a neighbour or continuing a stale world-space edge path.
	return false

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, token.collision_mask, [token.get_rid()])
	var hit := token.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider is CharacterBody3D: return {}
	return hit

func _pose(normal: Vector3, forward: Vector3) -> Basis:
	forward = forward.slide(normal).normalized()
	if forward.is_zero_approx(): forward = _frame.x.cross(normal).normalized()
	return Basis(forward.cross(normal), normal, -forward).orthonormalized()

func _clear(at: Vector3, pose: Basis) -> bool:
	return token.climber.can_occupy(at, pose)

func _move(at: Vector3, pose: Basis) -> bool:
	if not _clear(at, pose): return false
	var previous: Basis = token.cockroach_model.basis
	token.cockroach_model.basis = pose.scaled(Vector3.ONE * Scale.GEOMETRY)
	token._sync_roach_collision_pose()
	var hit := token.move_and_collide(at - token.global_position, false, Scale.COLLISION_MARGIN)
	if hit != null:
		token.cockroach_model.basis = previous
		token._sync_roach_collision_pose()
		return false
	token._surface_normal = pose.y
	return true
