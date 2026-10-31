extends Node3D
## Art viewer uses the gameplay scene. No network session or gameplay actions.

var _model: Node3D
var _camera: Camera3D
var _label: Label
var _mode := 0
var _paused := false
var _turntable := false
var _azimuth := -0.55
var _elevation := 0.12
var _distance := 3.9
var _target := Vector3(0,1.08,0)
var _dragging := false
var _frames := 0
var _capture := ""

func _ready() -> void:
	get_viewport().msaa_3d = Viewport.MSAA_4X
	get_viewport().use_taa = true
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("1b2223")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b8c5cf")
	env.ambient_light_energy = 0.40
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://assets/shaders/roach_studio.gdshader")
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_512
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ssao_enabled = true
	env.ssao_radius = 0.16
	env.ssao_intensity = 1.5
	env.ssao_detail = 0.7
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	_light(Vector3(-2.5,3.8,-3),Color("ffebd2"),2.0,0.7)
	_light(Vector3(2.1,2.8,1.5),Color("b5d5e2"),2.2,0.5)
	_light(Vector3(2,1.8,-3),Color("d2ded6"),0.85,0.7)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200,200)
	ground.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/shaders/roach_studio_floor.gdshader")
	ground.material_override = mat
	ground.position.y = -0.006
	add_child(ground)
	_model = load("res://scenes/game/exterminator_model.tscn").instantiate() as Node3D
	add_child(_model)
	_camera = Camera3D.new()
	_camera.fov = 37
	_camera.near = 0.01
	add_child(_camera)
	_camera.current = true
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_label = Label.new()
	_label.position = Vector2(30,24)
	_label.add_theme_font_size_override("font_size",23)
	canvas.add_child(_label)
	var controls := Label.new()
	controls.position = Vector2(30,61)
	controls.text = "1 Idle   2 Walk   3 Hurry     /     Drag orbit • Wheel zoom     /     Space pause • R turntable • V detail"
	controls.add_theme_font_size_override("font_size",14)
	controls.modulate = Color("a3b3b0")
	canvas.add_child(controls)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--exterminator-capture="):
			_capture = arg.trim_prefix("--exterminator-capture=")
		if arg == "--detail=mask":
			_target = Vector3(0,1.9,-0.02)
			_distance = 0.9
			_elevation = 0.06
		if arg == "--detail=boots":
			_target = Vector3(0,0.24,-0.03)
			_distance = 1.0
			_elevation = 0.10
		if arg in ["--detail=mask-side","--detail=mask-back"]:
			_target = Vector3(0,1.96,0)
			_distance = 0.9
			_elevation = 0.08
			_azimuth = PI/2 if arg == "--detail=mask-side" else PI-0.65
		if arg == "--detail=hands":
			_target = Vector3(0,0.90,-0.03)
			_distance = 1.55
			_elevation = 0.0
			_azimuth = 0.0
		if arg == "--detail=back":
			_azimuth = PI-0.6
		if arg == "--detail=hand":
			_target = Vector3(-0.335,0.875,-0.105)
			_distance = 0.66
			_elevation = 0.03
			_azimuth = -1.05
		if arg == "--detail=arms":
			_target = Vector3(0,1.25,0)
			_distance = 2.65
			_elevation = 0.0
			_azimuth = -1.32
		if arg == "--detail=belt":
			_target = Vector3(0,1.11,0)
			_distance = 1.10
			_elevation = 0.06
			_azimuth = -0.72
		if arg == "--detail=pockets":
			_target = Vector3(0,1.48,-0.05)
			_distance = 1.10
			_elevation = 0.07
			_azimuth = -0.40
		if arg == "--detail=sleeve":
			_target = Vector3(-0.32,1.48,0)
			_distance = 0.74
			_elevation = 0.06
			_azimuth = -1.68
		if arg == "--detail=knees":
			_target = Vector3(0,0.53,-0.035)
			_distance = 0.95
			_elevation = 0.04
			_azimuth = -0.6
		if arg == "--pose=walk":
			_mode = 1
		if arg == "--pose=hurry":
			_mode = 2
	_update_camera()

func _light(at: Vector3, color: Color, energy: float, size: float) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.light_specular = 0.25
	light.light_size = size
	light.omni_range = 12
	light.shadow_enabled = true
	light.shadow_bias = 0.012
	light.shadow_normal_bias = 0.02
	add_child(light)

func _process(delta: float) -> void:
	_frames += 1
	_model.set("motion_speed",[0.0,1.4,5.5][_mode])
	_model.set_process(not _paused)
	if _turntable and not _paused:
		_azimuth += delta*0.23
		_update_camera()
	_label.text = "NIGHT SHIFT  /  EXTERMINATOR 07    —    " + ["IDLE","WALK","HURRY"][_mode]
	if _frames == 50 and not _capture.is_empty():
		await RenderingServer.frame_post_draw
		var error := get_viewport().get_texture().get_image().save_png(_capture)
		print("EXTERMINATOR CAPTURE: ",error_string(error))
		get_tree().quit(0 if error == OK else 1)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1,KEY_2,KEY_3: _mode = event.keycode-KEY_1
			KEY_SPACE: _paused = not _paused
			KEY_R: _turntable = not _turntable
			KEY_V:
				if _distance > 2.0:
					_target = Vector3(0,1.9,-0.02)
					_distance = 0.9
				else:
					_target = Vector3(0,1.08,0)
					_distance = 3.9
				_update_camera()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			_distance = clampf(_distance+(-0.15 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 0.15),0.5,7)
			_update_camera()
	if event is InputEventMouseMotion and _dragging:
		_azimuth -= event.relative.x*0.007
		_elevation = clampf(_elevation+event.relative.y*0.006,-0.2,1.3)
		_update_camera()

func _update_camera() -> void:
	_camera.position = _target + Vector3(sin(_azimuth)*cos(_elevation),sin(_elevation),-cos(_azimuth)*cos(_elevation))*_distance
	_camera.look_at(_target)
