extends Node3D
## F6 art/data review only. Does not host a match or create gameplay pickups.
const Types := preload("res://scripts/game/food_types.gd")
var _camera: Camera3D
var _models: Array[Node3D] = []
var _bases: Array[MeshInstance3D] = []
var _caption: Label
var _reference: Node3D
var _selection := -1
var _yaw := 0.18
var _pitch := 0.62
var _distance := 0.32
var _focus := Vector3.ZERO
var _dragging := false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("10191e")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b3cad5")
	environment.environment.ambient_light_energy = 0.65
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(environment)
	for i: int in 2:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-48, -35 if i == 0 else 145, 0)
		light.light_energy = 1.9 if i == 0 else 0.8
		light.light_color = Color("ffe6c7") if i == 0 else Color("b7d9ec")
		light.shadow_enabled = i == 0
		add_child(light)
	for i: int in Types.IDS.size():
		var model := Types.model(Types.IDS[i])
		add_child(model)
		model.position.x = (i - 1.5) * 0.065
		model.rotation.y = -0.3 if i % 2 == 0 else 0.35
		_models.append(model)
		var base := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.029
		cylinder.bottom_radius = 0.029
		cylinder.height = 0.002
		cylinder.radial_segments = 64
		base.mesh = cylinder
		base.position = Vector3(model.position.x, -0.001, 0)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("27383e")
		material.roughness = 0.55
		base.material_override = material
		add_child(base)
		_bases.append(base)
	_reference = load("res://scenes/game/cockroach_model.tscn").instantiate()
	add_child(_reference)
	_reference.scale = Vector3.ONE * 0.025
	_reference.position = Vector3(0, 0, 0.065)
	_reference.visible = false
	_camera = Camera3D.new()
	_camera.near = 0.0005
	_camera.far = 5
	_camera.fov = 44
	_camera.current = true
	add_child(_camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_bottom", 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	var title := Label.new()
	title.text = "FOOD VARIETIES / FIRST PASS"
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Reusable models and effect profiles · E/Q/F carry effects are available in the game"
	subtitle.modulate = Color("a5bcc4")
	column.add_child(subtitle)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	_caption = Label.new()
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_font_size_override("font_size", 18)
	column.add_child(_caption)
	var controls := Label.new()
	controls.text = "1–4 inspect food · Space all foods · Drag to orbit · Wheel zoom · C roach scale reference"
	controls.modulate = Color("a5bcc4")
	column.add_child(controls)
	_select(-1)

func _select(index: int) -> void:
	_selection = index
	for i: int in _models.size():
		_models[i].visible = index < 0 or i == index
		_bases[i].visible = index < 0 or i == index
	_distance = 0.32 if index < 0 else 0.095
	if index < 0:
		_caption.text = "1  SPICY PEPPER      2  FERMENTED GRAPE      3  FROZEN BLUEBERRY      4  FRENCH FRY"
	else:
		var food := Types.definition(Types.IDS[index])
		_caption.text = food.display_name.to_upper() + "\nPlanned carry effect: " + food.effect_description

func _process(delta: float) -> void:
	if _camera == null: return
	var target := Vector3(0, 0.008, 0) if _selection < 0 else _models[_selection].position + Vector3(0, 0.008, 0)
	_focus = _focus.lerp(target, 1-exp(-10*delta))
	_camera.position = _focus + Vector3(sin(_yaw)*cos(_pitch), sin(_pitch), cos(_yaw)*cos(_pitch)) * _distance
	_camera.look_at(_focus)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_4: _select(event.physical_keycode - KEY_1)
		elif event.physical_keycode == KEY_SPACE: _select(-1)
		elif event.physical_keycode == KEY_C:
			_reference.visible = not _reference.visible
			if _reference.visible: _select(-1)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT: _dragging = event.pressed
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP: _distance = maxf(0.04, _distance * 0.9)
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN: _distance = minf(0.7, _distance * 1.1)
	if event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x * 0.008
		_pitch = clampf(_pitch + event.relative.y * 0.008, 0.05, 1.5)
