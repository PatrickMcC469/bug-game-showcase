extends Node
## Runs only in the lab's background client. Inputs go through the same owning
## player controller and host-approved weapon requests as a human client.
const SHOT_DELAY := 3.0
var token: CharacterBody3D
var world: Node3D
var scenario := 0
var elapsed := 0.0
var paused := true
var fired := false
var _route := PackedVector3Array()
var _waypoint := 1
var _was_ghost := false


func setup(player: CharacterBody3D, game_world: Node3D) -> void:
	token = player
	world = game_world
	# Set the intended input before the player's ordinary physics step.
	process_physics_priority = -10


func reset(next_scenario: int, route: PackedVector3Array) -> void:
	clear_input()
	scenario = next_scenario
	_route = route
	_waypoint = 1
	elapsed = 0.0
	fired = false
	paused = true
	_was_ghost = false


func set_paused(value: bool) -> void:
	paused = value
	if paused:
		clear_input()


func clear_input() -> void:
	for action: String in ["move_forward", "move_back", "move_left", "move_right", "sprint", "dash"]:
		Input.action_release(action)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(token) or not Net.is_solo_test() or not token.is_multiplayer_authority():
		return
	var ghost: bool = world.combat.is_ghost(token.name.to_int())
	if _was_ghost and not ghost and scenario == 1 and not _route.is_empty():
		# Consume the real ten-second respawn, then return this test target to
		# its practice route rather than requiring navigation from the pantry.
		token.apply_combat_state(world.combat.get_state(token.name.to_int()))
		token.reset_for_solo_test(_route[0], 0, -0.24)
		_waypoint = 1
	_was_ghost = ghost
	if paused or world.get_match_phase() != 1 or ghost:
		clear_input()
		return
	elapsed += delta
	if scenario == 0:
		_aim_and_fire()
	else:
		_follow_route()


func _aim_and_fire() -> void:
	if fired:
		return
	var target := world.players.get_node_or_null("1") as Node3D
	if target == null:
		return
	var to_target := target.global_position - token.global_position
	var yaw := atan2(-to_target.x, -to_target.z)
	token.camera_rig.rotation.y = yaw
	token.face_shotgun_direction(yaw)
	token.camera.look_at(target.global_position + Vector3.UP * 0.011)
	if elapsed >= SHOT_DELAY:
		fired = token.shotgun.request_solo_test_shot(target.global_position + Vector3.UP * 0.011)


func _follow_route() -> void:
	if _route.size() < 2:
		return
	var direction := _route[_waypoint] - token.global_position
	direction.y = 0.0
	if direction.length() < 0.06:
		_waypoint = (_waypoint + 1) % _route.size()
		direction = _route[_waypoint] - token.global_position
		direction.y = 0.0
	token.camera_rig.rotation.y = atan2(-direction.x, -direction.z)
	Input.action_press("move_forward")


func _exit_tree() -> void:
	clear_input()
