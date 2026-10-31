extends Node
## Movement belongs to the owning token, like walking. The existing position/
## model-rotation synchronizer carries climbing to peers, including late joiners.
const Scale := preload("res://scripts/game/roach_scale.gd")
const SPEED := 0.65
var active := false
var _points := PackedVector3Array()
var _normals := PackedVector3Array()
var _segment := 1
var _progress := 0.0
var _spot: Node3D
var _cooldown := 0.0
var _message := ""
var _message_left := 0.0
var _hud: Label
@onready var token: CharacterBody3D = get_parent()

func _ready() -> void:
	if token.is_multiplayer_authority() and DisplayServer.get_name() != "headless":
		var canvas := CanvasLayer.new()
		add_child(canvas)
		_hud = Label.new()
		canvas.add_child(_hud)
		_hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_hud.offset_left = -300
		_hud.offset_right = 300
		_hud.offset_top = -205
		_hud.offset_bottom = -170
		_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hud.add_theme_font_size_override("font_size", 19)
		_hud.modulate = Color(0.6, 0.95, 0.8)
		_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_cooldown = maxf(0, _cooldown - delta)
	_message_left = maxf(0, _message_left - delta)
	if _hud == null: return
	_hud.text = ""
	if token.player_role != "cockroach": return
	if active:
		_hud.text = "CLIMBING · [C] LET GO"
	elif token.surface_crawler != null and token.surface_crawler.active:
		_hud.text = "CRAWLING · WASD MOVE · [C] LET GO"
	elif _message_left > 0:
		_hud.text = _message
	else:
		var nearest := nearest_spot()
		if not nearest.is_empty():
			_hud.text = "[C] CLIMB %s · %s" % ["DOWN" if nearest.down else "UP", nearest.spot.destination_name.to_upper()]

func _unhandled_input(event: InputEvent) -> void:
	if not token.is_multiplayer_authority() or token.player_role != "cockroach": return
	if event.is_action_pressed("roach_climb") and not event.is_echo() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if token.surface_crawler != null and token.surface_crawler.active: token.surface_crawler.cancel()
		elif active: cancel()
		else: request_climb()
		get_viewport().set_input_as_handled()

func nearest_spot() -> Dictionary:
	var best := {}
	var distance := 0.16
	for spot: Node in get_tree().get_nodes_in_group("roach_climb_spots"):
		for down: bool in [false, true]:
			var endpoint: Vector3 = spot.endpoint(down)
			if absf(endpoint.y - token.global_position.y) > 0.055: continue
			var candidate: float = token.global_position.distance_to(endpoint)
			if candidate < distance:
				distance = candidate
				best = {"spot": spot, "down": down}
	return best

func request_climb() -> bool:
	if not token.is_multiplayer_authority() or token.player_role != "cockroach" or active or _cooldown > 0: return false
	if token.surface_crawler != null and token.surface_crawler.active: return false
	var nearest := nearest_spot()
	if nearest.is_empty() or not token.is_on_floor(): return false
	var points: PackedVector3Array = nearest.spot.route_points(nearest.down)
	var normals: PackedVector3Array = nearest.spot.route_normals(nearest.down)
	# Approach is swept too. Never teleport to a marker through an obstruction.
	points.insert(0, token.global_position + Vector3.UP * 0.001)
	normals.insert(0, Vector3.UP)
	if not _path_clear(points, normals):
		_message = "CLIMB BLOCKED · CLEAR THE ROUTE OR MAKE ROOM FOR YOUR STACK"
		_message_left = 2.0
		return false
	_points = points
	_normals = normals
	_spot = nearest.spot
	_segment = 1
	_progress = 0.0
	active = true
	token.velocity = Vector3.ZERO
	token._dash_time_left = 0.0
	return true

func step(delta: float) -> bool:
	if not active: return false
	if token.player_role != "cockroach" or not is_instance_valid(_spot):
		cancel()
		return false
	var remaining: float = SPEED * token._cargo_speed_scale * token._food_speed * delta
	while remaining > 0 and active:
		var length := _points[_segment - 1].distance_to(_points[_segment])
		var advance := minf(remaining, maxf(0, length - _progress))
		_progress += advance
		remaining -= advance
		var weight := 1.0 if length < 0.00001 else _progress / length
		var at := _points[_segment - 1].lerp(_points[_segment], weight)
		var normal := _normals[_segment - 1].slerp(_normals[_segment], weight).normalized()
		var direction := _points[_segment] - _points[_segment - 1]
		var pose := _pose(normal, direction)
		# Recheck shape and cargo clearance while moving: another player or new
		# cargo can obstruct a route that was clear when the climb started.
		if not can_occupy(at, pose):
			cancel()
			return true
		token.cockroach_model.basis = pose.scaled(Vector3.ONE * Scale.GEOMETRY)
		token._sync_roach_collision_pose()
		var movement := at - token.global_position
		var hit := token.move_and_collide(movement)
		token.velocity = movement / maxf(delta, 0.001)
		if hit != null:
			cancel()
			return true
		if weight >= 0.99999:
			_segment += 1
			_progress = 0
			if _segment == _points.size(): cancel()
	return true

func cancel() -> void:
	if not active: return
	active = false
	_spot = null
	_cooldown = 0.25
	token.velocity = Vector3.ZERO
	token._surface_normal = Vector3.UP
	token._facing_yaw = token.cockroach_model.rotation.y
	token._pose_roach_on_surface()

func _pose(normal: Vector3, movement: Vector3) -> Basis:
	var forward := movement.slide(normal).normalized()
	if forward.length_squared() < 0.01:
		forward = Vector3.UP if absf(normal.y) < 0.8 else Vector3.FORWARD
	return Basis(forward.cross(normal).normalized(), normal, -forward).orthonormalized()

func can_occupy(at: Vector3, pose: Basis) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = token.collision_mask
	query.exclude = [token.get_rid()]
	query.margin = 0.0
	query.shape = token.roach_collision.shape
	var radius: float = token.roach_collision.shape.radius
	query.transform = Transform3D(pose * Basis(Vector3.RIGHT, PI * 0.5), at + pose.y * radius)
	var space := token.get_world_3d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty(): return false
	if token.cargo_count > 0:
		query.shape = token._cargo_collision.shape
		# Food stacks are currently world-up on every peer, including on slopes.
		query.transform = Transform3D(Basis.IDENTITY, at + token._cargo_collision.position)
		if not space.intersect_shape(query, 1).is_empty(): return false
	return true

func _path_clear(points: PackedVector3Array, normals: PackedVector3Array) -> bool:
	for i: int in range(1, points.size()):
		var movement := points[i] - points[i - 1]
		var samples := maxi(1, ceili(movement.length() / 0.008))
		for j: int in range(samples + 1):
			var fraction := float(j) / samples
			var at := points[i - 1].lerp(points[i], fraction)
			var normal := normals[i - 1].slerp(normals[i], fraction).normalized()
			if not can_occupy(at, _pose(normal, movement)): return false
	return true
