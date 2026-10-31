extends Node3D
## Short original synthesized Foley/chimes; cosmetic and identical on all peers.
const RoachScale := preload("res://scripts/game/roach_scale.gd")
var _sounds: Dictionary[String, AudioStreamWAV] = {}
var _active_sounds := 0

func setup(run: Node) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var guide := Node3D.new()
	guide.set_script(preload("res://scripts/game/food_throw_guide.gd"))
	add_child(guide)
	guide.setup(get_parent(), run)
	for kind: String in ["grab", "drop", "throw", "catch", "spill", "bank", "error"]:
		_sounds[kind] = _synthesize(kind)
	run.feedback.connect(_on_feedback)

func _on_feedback(_message: String, kind: String, at: Vector3) -> void:
	if _active_sounds < 10 and _sounds.has(kind):
		var sound := AudioStreamPlayer3D.new()
		sound.stream = _sounds[kind]
		sound.volume_db = -12.0 if kind == "bank" else -18.0
		sound.max_distance = 38.0
		sound.unit_size = 5.0
		add_child(sound)
		sound.global_position = at
		_active_sounds += 1
		sound.finished.connect(func() -> void:
			_active_sounds -= 1
			sound.queue_free())
		sound.play()
	if kind in ["bank", "catch", "spill"]:
		_burst(at + Vector3.UP * (0.5 * RoachScale.GEOMETRY), kind == "spill")
	if kind == "bank":
		var home: Area3D = get_parent().home_returns.nearest(at)
		if home != null: home.celebrate()

func _burst(at: Vector3, spilled: bool) -> void:
	var particles := GPUParticles3D.new()
	particles.amount = 18
	particles.lifetime = 0.75
	particles.one_shot = true
	particles.explosiveness = 1.0
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3.UP
	material.spread = 65.0
	material.initial_velocity_min = 1.1 * RoachScale.GEOMETRY
	material.initial_velocity_max = 2.5 * RoachScale.GEOMETRY
	material.gravity = Vector3(0.0, -6.0, 0.0) * RoachScale.GEOMETRY
	material.scale_min = 0.5
	material.scale_max = 1.2
	particles.process_material = material
	var crumb := BoxMesh.new()
	crumb.size = Vector3(0.055, 0.04, 0.055) * RoachScale.GEOMETRY
	var crumb_material := StandardMaterial3D.new()
	crumb_material.albedo_color = Color(0.85, 0.34, 0.12) if spilled else Color(0.98, 0.78, 0.34)
	crumb.material = crumb_material
	particles.draw_pass_1 = crumb
	add_child(particles)
	particles.global_position = at
	particles.emitting = true
	get_tree().create_timer(1.5).timeout.connect(particles.queue_free)

func _synthesize(kind: String) -> AudioStreamWAV:
	const RATE := 22050
	var duration := 0.42 if kind in ["bank", "catch"] else 0.20
	var count := int(RATE * duration)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = kind.hash()
	for index: int in count:
		var t := float(index) / RATE
		var envelope := sin(minf(t * 90.0, PI * 0.5)) * pow(1.0 - t / duration, 2.5)
		var frequency := 320.0
		match kind:
			"bank": frequency = 660.0 if t < 0.14 else (830.0 if t < 0.28 else 990.0)
			"catch": frequency = 550.0 + t * 1400.0
			"spill": frequency = 460.0 - t * 1500.0
			"throw": frequency = 250.0 + t * 1300.0
			"drop": frequency = 160.0
			"error": frequency = 130.0
		var tone := sin(TAU * frequency * t) * 0.48 + sin(TAU * frequency * 2.01 * t) * 0.12
		if kind in ["grab", "drop", "spill", "throw"]:
			tone = tone * 0.6 + rng.randf_range(-0.25, 0.25) * exp(-t * 22.0)
		bytes.encode_s16(index * 2, int(clampf(tone * envelope, -1.0, 1.0) * 24000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	return stream
