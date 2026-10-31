extends Node3D
## Local mist/audio only. The host separately resolves cone and cover damage.
var _puffs: Array[MeshInstance3D] = []
var _sound: AudioStreamPlayer3D
var _active := false
var _source: Dictionary = {}
var _direction := Vector3.FORWARD
var _range := 3.0
var _angle := 0.38
var _age := 0.0

func _ready() -> void:
	if DisplayServer.get_name() == "headless": return
	var sphere := SphereMesh.new()
	sphere.radius = 1
	sphere.height = 2
	sphere.radial_segments = 12
	sphere.rings = 6
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, cull_back, depth_draw_never; void fragment(){ ALBEDO=vec3(0.63,0.71,0.40); ALPHA=0.055*pow(max(dot(NORMAL,VIEW),0.0),1.4); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	for i: int in 60:
		var puff := MeshInstance3D.new()
		puff.mesh = sphere
		puff.material_override = material
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(puff)
		puff.visible = false
		_puffs.append(puff)
	_sound = AudioStreamPlayer3D.new()
	add_child(_sound)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 16000
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = 16000
	var bytes := PackedByteArray()
	bytes.resize(32000)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8371
	for i: int in 16000: bytes.encode_s16(i * 2, int(rng.randf_range(-1, 1) * 5000))
	stream.data = bytes
	_sound.stream = stream
	_sound.volume_db = -17
	_sound.max_distance = 12

func update_spray(source: Dictionary, direction: Vector3, reach: float, angle: float) -> void:
	_source = source
	_active = not source.is_empty() and not source.blocked
	_direction = direction
	_range = reach
	_angle = angle

func _process(delta: float) -> void:
	_age += delta
	if _sound != null:
		if _active and not _sound.playing: _sound.play()
		elif not _active and _sound.playing: _sound.stop()
		if _active: _sound.global_position = _source.at
	var side := _direction.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.1: side = Vector3.RIGHT
	var up := side.cross(_direction).normalized()
	for i: int in _puffs.size():
		var puff := _puffs[i]
		puff.visible = _active
		if not _active: continue
		var travel := fposmod(float(i) / _puffs.size() + _age * 0.9, 1.0)
		var spin := i * 2.39996 + _age
		var spread := tan(_angle) * travel * _range * 0.6
		var offset := _direction * (0.05 + travel * (_range - 0.1)) + (side * cos(spin) + up * sin(spin)) * spread
		var origin: Vector3 = _source.at
		var ray := PhysicsRayQueryParameters3D.create(origin, origin + offset, 1, _source.exclude)
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty(): puff.visible = false; continue
		var radius := minf(0.045 + travel * 0.24, maxf(0.001, _range - offset.length()))
		var query := PhysicsShapeQueryParameters3D.new()
		var shape := SphereShape3D.new()
		shape.radius = radius
		query.shape = shape
		query.transform.origin = origin + offset
		query.exclude = _source.exclude
		query.collision_mask = 1
		# Keep the visible mist out of walls/floors as well as its host damage.
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): puff.visible = false; continue
		puff.global_position = origin + offset
		puff.scale = Vector3.ONE * radius
