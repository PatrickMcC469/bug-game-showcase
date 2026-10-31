extends Node3D
## Local aiming aid. Dots describe a prediction; only the host moves real food.
const RoachScale := preload("res://scripts/game/roach_scale.gd")
var _world: Node
var _run: Node
var _dots: MultiMeshInstance3D
var _landing: MeshInstance3D
var _material: StandardMaterial3D
var _refresh_left := 0.0

func setup(world: Node, run: Node) -> void:
	_world = world
	_run = run
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = Color(0.95, 0.75, 0.33)
	var sphere := SphereMesh.new()
	sphere.radius = 0.036 * RoachScale.GEOMETRY
	sphere.height = 0.072 * RoachScale.GEOMETRY
	sphere.radial_segments = 8
	sphere.rings = 4
	sphere.material = _material
	_dots = MultiMeshInstance3D.new()
	_dots.multimesh = MultiMesh.new()
	_dots.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_dots.multimesh.mesh = sphere
	_dots.multimesh.instance_count = 25
	add_child(_dots)
	_landing = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.36 * RoachScale.GEOMETRY
	ring.outer_radius = 0.40 * RoachScale.GEOMETRY
	ring.rings = 24
	ring.ring_segments = 8
	_landing.mesh = ring
	_landing.material_override = _material
	add_child(_landing)
	visible = false

func _process(delta: float) -> void:
	if _run == null or not multiplayer.has_multiplayer_peer():
		return
	var peer_id := multiplayer.get_unique_id()
	visible = Input.is_action_pressed("food_aim") and _world.get_match_phase() == 1 and not _run.get_cargo_ids(peer_id).is_empty()
	if not visible:
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = 0.033
	var token := _world.players.get_node_or_null(str(peer_id)) as Node3D
	if token == null:
		visible = false
		return
	var points: PackedVector3Array = _run.get_throw_preview(peer_id, -token.camera_rig.global_basis.z)
	_dots.multimesh.visible_instance_count = points.size()
	for index: int in points.size():
		_dots.multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, to_local(points[index])))
	if not points.is_empty():
		_landing.global_position = points[points.size() - 1]
		var in_pantry: bool = _world.home_returns.at_position(_landing.global_position) != null
		_material.albedo_color = Color(0.55, 1.0, 0.47) if in_pantry else Color(0.95, 0.75, 0.33)
