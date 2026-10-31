extends Node3D
## Isolated art-review scene. Instantiates exactly the same asset as gameplay.
## Keys 1–4 preview cosmetic motion; no game state or network session is created.

const ROACH := preload("res://scenes/game/cockroach_model.tscn")
var _model: Node3D
var _camera: Camera3D
var _environment: Environment
var _label: Label
var _mode := 0
var _elapsed := 0.0
var _paused := false
var _rotate := false
var _azimuth := 0.55
var _elevation := 0.78
var _distance := 4.05
var _dragging := false
var _capture_frame := 0

func _ready() -> void:
	get_viewport().msaa_3d = Viewport.MSAA_4X
	get_viewport().use_taa = true
	RenderingServer.set_default_clear_color(Color(0.045, 0.052, 0.06))
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color(0.045, 0.052, 0.06)
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color(0.79, 0.82, 0.88)
	_environment.ambient_light_energy = 0.38
	_environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	_environment.tonemap_exposure = 1.2
	var studio_sky := Sky.new()
	var sky_material := ShaderMaterial.new()
	sky_material.shader = preload("res://assets/shaders/roach_studio.gdshader")
	studio_sky.sky_material = sky_material
	studio_sky.radiance_size = Sky.RADIANCE_SIZE_512
	_environment.sky = studio_sky
	_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_environment.ssao_enabled = true
	_environment.ssao_radius = 0.22
	_environment.ssao_intensity = 1.4
	_environment.ssao_detail = 0.8
	_environment.ssao_light_affect = 0.35
	var world_environment := WorldEnvironment.new()
	world_environment.environment = _environment
	add_child(world_environment)
	_light(Vector3(-2.0, 4.0, -2.5), Color(1.0, 0.93, 0.84), 1.25, 0.65)
	_light(Vector3(2.5, 2.8, 1.4), Color(0.80, 0.88, 1.0), 0.85, 0.55)
	_light(Vector3(0.5, 1.4, -3.0), Color(1.0, 0.96, 0.88), 0.45, 0.4)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200.0, 200.0)
	floor_mesh.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/roach_studio_floor.gdshader")
	floor_mesh.material_override = material
	floor_mesh.position.y = -0.008
	add_child(floor_mesh)
	_model = ROACH.instantiate() as Node3D
	add_child(_model)
	_camera = Camera3D.new()
	_camera.fov = 42.0
	_camera.near = 0.025
	add_child(_camera)
	_camera.current = true
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_label = Label.new()
	_label.position = Vector2(30.0, 22.0)
	_label.add_theme_font_size_override("font_size", 20)
	canvas.add_child(_label)
	var controls := Label.new()
	controls.text = "1 Idle   2 Walk   3 Sprint   4 Dash     •     Drag to orbit / wheel to zoom     •     Space pause   R turntable   V view   L lighting"
	controls.position = Vector2(30.0, 58.0)
	controls.add_theme_font_size_override("font_size", 14)
	controls.modulate = Color(0.65, 0.70, 0.76)
	canvas.add_child(controls)
	_update_camera()

func _light(at: Vector3, color: Color, energy: float, size: float) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.light_size = size
	light.omni_range = 12.0
	light.shadow_enabled = true
	light.shadow_bias = 0.015
	light.shadow_normal_bias = 0.025
	add_child(light)

func _process(delta: float) -> void:
	_capture_frame += 1
	if not _paused:
		_elapsed += delta
	var speeds: Array[float] = [0.0, 2.0, 8.0, 13.0]
	var dashing := _mode == 3 and fposmod(_elapsed, 1.5) < 0.18
	_model.set("motion_speed", speeds[_mode] if _mode != 3 else (13.0 if dashing else 0.0))
	_model.set("is_dashing", dashing)
	_model.set_process(not _paused)
	if _rotate and not _paused:
		_azimuth += delta * 0.22
		_update_camera()
	_label.text = "PERIPLANETA AMERICANA   /   " + ["IDLE", "WALK", "SPRINT", "DASH"][_mode] + ("   /   PAUSED" if _paused else "")
	if _capture_frame == 40:
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--roach-capture="):
				await RenderingServer.frame_post_draw
				var error := get_viewport().get_texture().get_image().save_png(argument.trim_prefix("--roach-capture="))
				print("ROACH CAPTURE: ", error_string(error))
				get_tree().quit(0 if error == OK else 1)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4:
				_mode = event.keycode - KEY_1
			KEY_SPACE:
				_paused = not _paused
			KEY_R:
				_rotate = not _rotate
			KEY_V:
				_elevation = 1.5 if _elevation < 1.0 else 0.35
				_update_camera()
			KEY_L:
				_environment.ambient_light_energy = 0.85 if _environment.ambient_light_energy < 0.6 else 0.45
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_distance = clampf(_distance + (-0.25 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.25), 1.6, 8.0)
			_update_camera()
	if event is InputEventMouseMotion and _dragging:
		_azimuth -= event.relative.x * 0.007
		_elevation = clampf(_elevation + event.relative.y * 0.006, 0.08, 1.52)
		_update_camera()

func _update_camera() -> void:
	var target := Vector3(0.0, 0.14, -0.22)
	_camera.position = target + Vector3(sin(_azimuth) * cos(_elevation), sin(_elevation), cos(_azimuth) * cos(_elevation)) * _distance
	_camera.look_at(target)
