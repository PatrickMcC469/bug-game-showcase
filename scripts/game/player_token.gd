extends CharacterBody3D
## One player's avatar. GameWorld assigns authority on the host, and every peer
## derives the same authority from the stable node name before synchronization
## begins. Only that owning client drives movement; MultiplayerSynchronizer ships
## position and facing to everyone else.
##
## Note this movement is client-authoritative: the host owns objective state but
## still judges overlaps from positions a modified client could falsify. Fine for
## a gray box, not for persistent or ranked rewards. See Online-Stack in the vault.

const RoachScale := preload("res://scripts/game/roach_scale.gd")
const FoodCatalog := preload("res://scripts/game/food_catalog.gd")
const ROLE_COCKROACH := "cockroach"
const ROLE_EXTERMINATOR := "exterminator"

@export var move_speed := 5.5
@export var sprint_speed := 8.0
@export var acceleration := 30.0
@export var braking := 42.0
@export var turn_speed := 14.0
@export var dash_speed := 13.0
@export var dash_duration := 0.16
@export var dash_cooldown := 1.1
@export var dash_acceleration := 86.0
@export var gravity := 20.0
@export var mouse_sensitivity := 0.003
@export var roach_camera_fov := 64.0
@export var roach_speed_fov_gain := 5.0

@onready var roach_collision: CollisionShape3D = $Collision
@onready var exterminator_collision: CollisionShape3D = $ExterminatorCollision
@onready var cockroach_model: Node3D = %CockroachModel
@onready var exterminator_model: Node3D = %ExterminatorModel
@onready var name_label: Label3D = %NameLabel
@onready var camera_rig: Node3D = %CameraRig
@onready var spring_arm: SpringArm3D = %SpringArm
@onready var camera: Camera3D = %Camera
@onready var shotgun: Node = %Shotgun

var _cargo_collision: CollisionShape3D
var cargo_weight := 0.0
var cargo_instability := 0.0
var cargo_count := 0
var _cargo_speed_scale := 1.0
var _food_speed := 1.0
var _food_wobble := 0.0
var _food_frozen := 0.0
var _food_trip := 0.0

var _dash_time_left := 0.0
var _dash_cooldown_left := 0.0
var _dash_direction := Vector3.FORWARD
var _last_position := Vector3.ZERO
var _role_applied := false
var _facing_yaw := 0.0
var _surface_normal := Vector3.UP
var player_role := ROLE_COCKROACH
var vitals: Node
var climber: Node
var surface_crawler: Node

func food_input(input: Vector2) -> Vector2:
	return input.rotated(_food_wobble)

func set_food_effects(speed: float, wobble: float, frozen: float, trip: float) -> void:
	_food_speed = speed
	_food_wobble = wobble
	if (_food_frozen > 0) != (frozen > 0):
		if frozen > 0: cockroach_model.call("set_peer_color", Color(0.55, 0.8, 1.0))
		else: _tint(name.to_int())
	_food_frozen = frozen
	_food_trip = trip


func _enter_tree() -> void:
	# MultiplayerSpawner creates this scene independently on every peer. Its
	# stable numeric node name is available before _ready, so establish the same
	# recursive authority here before the child synchronizer begins replication.
	var peer_id := name.to_int()
	if peer_id > 0:
		set_multiplayer_authority(peer_id)
		# Spawn visibility stays host-owned even though movement is owned by this
		# token's peer. The host reveals tokens only after a joining peer reports
		# that GameWorld and its MultiplayerSpawner exist locally.
		var spawn_visibility := get_node_or_null("SpawnVisibility") as MultiplayerSynchronizer
		if spawn_visibility != null:
			spawn_visibility.set_multiplayer_authority(1)


func _ready() -> void:
	var peer_id := name.to_int()
	_tint(peer_id)
	_last_position = global_position
	_facing_yaw = cockroach_model.rotation.y
	# Keep the CharacterBody root unscaled and give each peer private, correctly
	# sized shapes. The macro art viewer continues to use the unscaled source.
	cockroach_model.scale = Vector3.ONE * RoachScale.GEOMETRY
	roach_collision.shape = roach_collision.shape.duplicate()
	var capsule := roach_collision.shape as CapsuleShape3D
	capsule.radius *= RoachScale.GEOMETRY
	capsule.height *= RoachScale.GEOMETRY
	capsule.margin = RoachScale.COLLISION_MARGIN
	roach_collision.position *= RoachScale.GEOMETRY
	spring_arm.margin = 0.001
	spring_arm.add_excluded_object(get_rid())
	# Derived cargo clearance keeps a loaded tower out of low map passages.
	_cargo_collision = CollisionShape3D.new()
	_cargo_collision.name = "CargoClearance"
	_cargo_collision.shape = BoxShape3D.new()
	_cargo_collision.shape.margin = RoachScale.COLLISION_MARGIN
	_cargo_collision.disabled = true
	add_child(_cargo_collision)

	# Every peer instantiates every player, so only the local one may own a
	# camera — otherwise whichever token spawned last decides what you look at.
	var mine := is_multiplayer_authority()
	camera.current = mine
	name_label.hide()
	if mine:
		# Client-owned movement synchronizers become public only after the host's
		# private spawn gate has delivered this token into the loaded world.
		if not multiplayer.is_server():
			(get_node("Sync") as MultiplayerSynchronizer).public_visibility = true
		_capture_mouse(true)
	configure_role(player_role)
	shotgun.setup()
	vitals = preload("res://scripts/game/roach_vitals.gd").new()
	vitals.name = "Vitals"
	add_child(vitals)
	climber = preload("res://scripts/game/roach_climber.gd").new()
	climber.name = "Climber"
	add_child(climber)
	surface_crawler = preload("res://scripts/game/roach_surface_crawler.gd").new()
	surface_crawler.name = "SurfaceCrawler"
	add_child(surface_crawler)


func _physics_process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not is_multiplayer_authority():
		return
	if _food_frozen > 0 or _food_trip > 0:
		_dash_time_left = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		if not climber.active and not surface_crawler.active:
			velocity.y -= gravity * delta * (RoachScale.MOVEMENT if player_role == ROLE_COCKROACH else 1.0)
			move_and_slide()
		return
	if shotgun.step_recoil(delta):
		return
	if climber != null and climber.step(delta):
		return
	if surface_crawler != null and surface_crawler.step(delta):
		return

	if is_on_floor():
		velocity.y = 0.0
	velocity.y -= gravity * delta * (RoachScale.MOVEMENT if player_role == ROLE_COCKROACH else 1.0)
	_dash_time_left = maxf(_dash_time_left - delta, 0.0)
	_dash_cooldown_left = maxf(_dash_cooldown_left - delta, 0.0)

	# Movement is camera-relative: pushing forward means "away from the camera",
	# not "along world -Z", which is what makes a third-person camera feel right.
	var input := food_input(Input.get_vector("move_left", "move_right", "move_forward", "move_back")) if can_read_movement_input() else Vector2.ZERO
	var rig := camera_rig.global_transform.basis
	var direction := rig.x * input.x + rig.z * input.y
	direction.y = 0.0
	direction = direction.normalized()

	var is_roach := player_role == ROLE_COCKROACH
	var pace := (RoachScale.MOVEMENT if is_roach else 1.0) * _food_speed
	if is_roach and can_read_movement_input() and Input.is_action_just_pressed("dash") and _dash_cooldown_left <= 0.0:
		_dash_direction = direction if not direction.is_zero_approx() else -camera_rig.global_basis.z
		_dash_direction.y = 0.0
		_dash_direction = _dash_direction.normalized()
		_dash_time_left = dash_duration
		_dash_cooldown_left = dash_cooldown

	if _dash_time_left > 0.0:
		velocity.x = move_toward(
			velocity.x, _dash_direction.x * dash_speed * pace * _cargo_speed_scale, dash_acceleration * pace * delta * _cargo_speed_scale
		)
		velocity.z = move_toward(
			velocity.z, _dash_direction.z * dash_speed * pace * _cargo_speed_scale, dash_acceleration * pace * delta * _cargo_speed_scale
		)
	else:
		var target_speed := (
			sprint_speed if is_roach and Input.is_action_pressed("sprint") else move_speed
		)
		var target_velocity := direction * target_speed * pace * _cargo_speed_scale
		var world := get_parent().get_parent()
		if not is_roach and world.get("gas_weapon") != null:
			target_velocity *= world.gas_weapon.movement_scale(get_multiplayer_authority())
		var traction := acceleration if not direction.is_zero_approx() else braking
		var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(
			target_velocity, traction * pace * delta * _cargo_speed_scale
		)
		velocity.x = horizontal.x
		velocity.z = horizontal.z

	var facing := _dash_direction if _dash_time_left > 0.0 else direction
	if not facing.is_zero_approx():
		var target_yaw := atan2(-facing.x, -facing.z)
		_facing_yaw = lerp_angle(
			_facing_yaw, target_yaw, 1.0 - exp(-turn_speed * _cargo_speed_scale * delta))
	if is_roach:
		_pose_roach_on_surface()
		# A geometry-scaled snap alone is shorter than one downhill sprint/dash
		# step. Cover this tick's maximum walkable drop, including at lower FPS.
		floor_snap_length = maxf(0.22 * RoachScale.GEOMETRY,
			Vector2(velocity.x, velocity.z).length() * delta * tan(floor_max_angle) + safe_margin * 2.0)
	else:
		cockroach_model.rotation = Vector3(0, _facing_yaw, 0)
	move_and_slide()
	if is_roach:
		_settle_small_roach()
		_pose_roach_on_surface()


func _settle_small_roach() -> void:
	# The root and camera stay upright. Sample the actual supporting plane:
	# capsule contact normals near ramp seams can point around the rounded end.
	_surface_normal = Vector3.UP
	if not is_on_floor():
		return
	_surface_normal = get_floor_normal()
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.03,
		global_position - Vector3.UP * 0.02, collision_mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or (hit["normal"] as Vector3).dot(Vector3.UP) < cos(floor_max_angle):
		return
	_surface_normal = hit["normal"]
	var floor_y: float = hit["position"].y
	# Correct millimeter-scale penetration after normal movement, including
	# slopes. Limit this to nearby support so ledges still lead to a real fall.
	if absf(global_position.y - floor_y) < 0.02:
		var settled := Vector3(global_position.x, floor_y + RoachScale.COLLISION_MARGIN, global_position.z)
		var pose := cockroach_model.basis.orthonormalized()
		# A second recovery sweep here lifts the capsule off support every other
		# tick. Validate the final pose without disturbing move_and_slide's floor
		# contact; never settle the body or its cargo inside an overhang.
		if climber == null or climber.can_occupy(settled, pose): global_position = settled


func _pose_roach_on_surface() -> void:
	# Store heading separately: writing an Euler yaw into a pitched/banked basis
	# loses the supporting plane when the player turns across an incline.
	var back := (Basis(Vector3.UP, _facing_yaw).z).slide(_surface_normal).normalized()
	var right := _surface_normal.cross(back).normalized()
	var pose := Basis(right, _surface_normal, back)
	if climber != null and not climber.can_occupy(global_position, pose): return
	cockroach_model.basis = pose.scaled(Vector3.ONE * RoachScale.GEOMETRY)
	_sync_roach_collision_pose()


func _sync_roach_collision_pose() -> void:
	# The existing replicated model rotation carries the entire support pose.
	# Derive the same capsule orientation/center on owners and remote peers.
	var pose := cockroach_model.basis.orthonormalized()
	roach_collision.basis = pose * Basis(Vector3.RIGHT, PI * 0.5)
	roach_collision.position = pose.y * (roach_collision.shape as CapsuleShape3D).radius


func _process(delta: float) -> void:
	if delta <= 0.0 or not multiplayer.has_multiplayer_peer():
		return
	var frame_motion := global_position - _last_position
	if absf(cockroach_model.basis.orthonormalized().y.y) > 0.95:
		frame_motion.y = 0.0
	var motion_speed := frame_motion.length() / delta
	cockroach_model.set("motion_speed", motion_speed / RoachScale.MOVEMENT)
	cockroach_model.set("is_dashing", _dash_time_left > 0.0)
	if not is_multiplayer_authority():
		_sync_roach_collision_pose()
	# Cockroach facing is already replicated by Sync; the exterminator copies it
	# locally so its presentation does not add another network channel.
	exterminator_model.rotation.y = cockroach_model.rotation.y
	exterminator_model.rotation.z = lerpf(exterminator_model.rotation.z, 0.65 if _food_trip > 0 else 0.0, minf(delta * 16, 1.0))
	exterminator_model.set("motion_speed", motion_speed)
	if is_multiplayer_authority() and player_role == ROLE_COCKROACH:
		var camera_response := 1.0 - exp(-6.0 * delta)
		var camera_up := cockroach_model.basis.orthonormalized().y if surface_crawler != null and surface_crawler.active else Vector3.UP
		camera_rig.position = camera_rig.position.lerp(camera_up * (RoachScale.CAMERA_HEIGHT + cargo_count * 0.22 * RoachScale.GEOMETRY), camera_response)
		spring_arm.spring_length = lerpf(spring_arm.spring_length, RoachScale.CAMERA_DISTANCE + cargo_count * 0.35 * RoachScale.GEOMETRY, camera_response)
		var speed_blend := clampf(motion_speed / (sprint_speed * RoachScale.MOVEMENT), 0.0, 1.0)
		var dash_gain := 2.5 if _dash_time_left > 0.0 else 0.0
		var target_fov := roach_camera_fov + speed_blend * roach_speed_fov_gain + dash_gain
		camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-7.0 * delta))
	_last_position = global_position


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	if event.is_action_pressed("ui_cancel"):
		_capture_mouse(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Yaw turns the whole rig; pitch only tilts the arm, so the camera
		# orbits rather than rolling the player.
		camera_rig.rotate_y(-event.relative.x * mouse_sensitivity)
		spring_arm.rotation.x = clampf(
			spring_arm.rotation.x - event.relative.y * mouse_sensitivity, -1.2, 0.4)


## GameWorld owns the authoritative role map and calls this on every peer after
## the matching token exists. Host-as-exterminator is only a prototype rule.
func configure_role(new_role: String) -> void:
	var normalized_role := (
		ROLE_EXTERMINATOR if new_role == ROLE_EXTERMINATOR else ROLE_COCKROACH
	)
	if _role_applied and player_role == normalized_role:
		return
	player_role = normalized_role
	if not is_node_ready():
		return

	_role_applied = true
	shotgun.cancel_recoil()
	_dash_time_left = 0.0
	_dash_cooldown_left = 0.0
	if climber != null: climber.cancel()
	if surface_crawler != null: surface_crawler.cancel()
	var is_exterminator := player_role == ROLE_EXTERMINATOR
	cockroach_model.visible = not is_exterminator
	exterminator_model.visible = is_exterminator
	roach_collision.disabled = is_exterminator
	exterminator_collision.disabled = not is_exterminator
	camera_rig.position.y = 1.65 if is_exterminator else RoachScale.CAMERA_HEIGHT
	spring_arm.spring_length = 7.0 if is_exterminator else RoachScale.CAMERA_DISTANCE
	spring_arm.position.x = 0.0
	spring_arm.rotation.x = -0.35 if is_exterminator else -0.24
	camera.fov = 68.0 if is_exterminator else roach_camera_fov
	camera.near = 0.06 if is_exterminator else RoachScale.CAMERA_NEAR
	safe_margin = 0.001 if is_exterminator else RoachScale.COLLISION_MARGIN
	floor_snap_length = 0.22 if is_exterminator else 0.22 * RoachScale.GEOMETRY
	floor_constant_speed = not is_exterminator
	_surface_normal = Vector3.UP
	name_label.position.y = 2.45 if is_exterminator else 0.06
	name_label.fixed_size = is_exterminator
	name_label.pixel_size = 0.0015 if is_exterminator else 0.0002
	_refresh_name_label()


func _refresh_name_label() -> void:
	var suffix := " (you)" if is_multiplayer_authority() else ""
	name_label.text = "P%d  %s%s" % [name.to_int(), player_role.to_upper(), suffix]

func face_shotgun_direction(yaw: float) -> void:
	_facing_yaw=yaw
	cockroach_model.rotation=Vector3(0,yaw,0)
	exterminator_model.rotation.y=yaw


func apply_combat_state(state: Dictionary) -> void:
	if vitals != null: vitals.apply_state(state)


## Drain travel preserves cargo, health and food effects; it only resets motion.
func travel_through_drain(at: Vector3, yaw: float) -> void:
	if not is_multiplayer_authority() or player_role != ROLE_COCKROACH: return
	climber.cancel()
	surface_crawler.cancel()
	global_position = at
	velocity = Vector3.ZERO
	_dash_time_left = 0.0
	_last_position = at
	_surface_normal = Vector3.UP
	_facing_yaw = yaw
	_pose_roach_on_surface()
	camera_rig.rotation = Vector3(0, yaw, 0)
	camera_rig.position = Vector3.UP * RoachScale.CAMERA_HEIGHT
	reset_physics_interpolation()

func respawn_from_combat(at: Vector3) -> void:
	if not is_multiplayer_authority(): return
	if climber != null: climber.cancel()
	if surface_crawler != null: surface_crawler.cancel()
	global_position = at
	velocity = Vector3.ZERO
	_dash_time_left = 0.0
	_dash_cooldown_left = 0.0
	_last_position = at
	_surface_normal = Vector3.UP


## Only the owning process relocates a lab actor; ordinary Sync carries the pose.
func reset_for_solo_test(at: Vector3, yaw: float, pitch: float) -> void:
	if not Net.is_solo_test() or not is_multiplayer_authority():
		return
	respawn_from_combat(at)
	shotgun.reset_for_solo_test()
	camera_rig.rotation = Vector3(0, yaw, 0)
	camera_rig.position.y = 1.65 if player_role == ROLE_EXTERMINATOR else RoachScale.CAMERA_HEIGHT
	spring_arm.spring_length = 7.0 if player_role == ROLE_EXTERMINATOR else RoachScale.CAMERA_DISTANCE
	spring_arm.rotation.x = pitch
	camera.rotation = Vector3.ZERO
	camera.fov = 68.0 if player_role == ROLE_EXTERMINATOR else roach_camera_fov
	_facing_yaw = yaw
	_surface_normal = Vector3.UP
	if player_role == ROLE_COCKROACH:
		_pose_roach_on_surface()
	else:
		face_shotgun_direction(yaw)


## Deterministic per-peer colour so every machine agrees without syncing it.
func _tint(peer_id: int) -> void:
	var color := Color.from_hsv(fmod(float(peer_id) * 0.381966, 1.0), 0.55, 0.95)
	cockroach_model.call("set_peer_color", color)


func _capture_mouse(capture: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE

func can_read_movement_input() -> bool:
	return is_multiplayer_authority() and (DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)


## Called by the host's GameWorld after a peer has loaded the matching scene.
func set_spawn_visible_to(peer_id: int, should_be_visible: bool) -> void:
	var spawn_visibility := get_node("SpawnVisibility") as MultiplayerSynchronizer
	spawn_visibility.set_visibility_for(peer_id, should_be_visible)
	var movement_sync := get_node("Sync") as MultiplayerSynchronizer
	if movement_sync.is_multiplayer_authority():
		movement_sync.set_visibility_for(peer_id, should_be_visible)


## FoodRun applies the host's cargo snapshot on every peer. Only the owning
## controller uses these modifiers to move; this adds no inventory authority.
func set_cargo(weight: float, instability: float, count: int) -> void:
	cargo_weight = maxf(weight, 0.0)
	cargo_instability = clampf(instability, 0.0, 1.0)
	cargo_count = count
	_cargo_speed_scale = FoodCatalog.speed_scale(cargo_weight)


func set_cargo_clearance(top: float) -> void:
	if _cargo_collision == null:
		return
	var should_disable := cargo_count == 0
	if _cargo_collision.disabled != should_disable:
		_cargo_collision.set_deferred("disabled", should_disable)
	var height := maxf(top - 0.55 * RoachScale.GEOMETRY, 0.05 * RoachScale.GEOMETRY)
	(_cargo_collision.shape as BoxShape3D).size = Vector3(0.64 * RoachScale.GEOMETRY, height, 0.64 * RoachScale.GEOMETRY)
	_cargo_collision.position = Vector3(0, 0.55 * RoachScale.GEOMETRY + height * 0.5, 0)
