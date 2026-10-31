extends Node3D
## Local map review. This camera and roof cutaway never run in the game world.
var camera: Camera3D
var map: Node3D
var target := Vector3.ZERO
var azimuth := 0.0
var elevation := 0.2
var distance := 10.0
var dragging := false
var capture := ""
var frames := 0
var caption: Label
var capture_directory := ""
var capture_views: Array[int] = [2, 6, 9, 3, 4, 1, 7, 8]
var capture_index := 0

func _ready() -> void:
	map = load("res://scenes/game/maps/diner_kitchen.tscn").instantiate()
	add_child(map)
	camera = Camera3D.new()
	camera.current = true
	camera.near = 0.015
	camera.fov = 65
	add_child(camera)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	caption = Label.new()
	caption.position = Vector2(25, 20)
	caption.add_theme_font_size_override("font_size", 23)
	canvas.add_child(caption)
	var controls := Label.new()
	controls.position = Vector2(25, 53)
	controls.text = "1 Front   2 Dining   3 Pantry   4 Alley   5 Cutaway   6 Kitchen   7 Bug view   8 Coffee   9 Cleaning  |  Drag orbit • Wheel zoom"
	canvas.add_child(controls)
	_view(1)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--map-capture="): capture = arg.trim_prefix("--map-capture=")
		if arg.begins_with("--view="): _view(arg.trim_prefix("--view=").to_int())
		if arg.begins_with("--capture-all="): capture_directory = arg.trim_prefix("--capture-all=")
	if not capture_directory.is_empty():
		DirAccess.make_dir_recursive_absolute(capture_directory)
		_next_capture()
	_update_camera()

func _view(index: int) -> void:
	for node: Node in map.get_node("RestaurantExpansion/Exterior").get_children():
		if str(node.name).begins_with("BoundaryWall"): node.visible = index == 5
	for path: String in ["Room/Ceiling", "RestaurantExpansion/Shell/DiningCeiling", "RestaurantExpansion/WalkInPantry/Ceiling"]:
		map.get_node(path).visible = index != 5
	match index:
		1:
			target = Vector3(0, 1.8, 12)
			azimuth = 0.3; elevation = 0.12; distance = 13
			caption.text = "NIGHT OWL / RESTAURANT FRONT"
		2:
			_pose(Vector3(2.55, 1.68, 12.68), Vector3(-1.05, 1.45, 8.3))
			caption.text = "NIGHT OWL / THE GRAVEYARD SHIFT"
		3:
			target = Vector3(-10.5, 1.2, -3.3)
			azimuth = 1.04; elevation = 0.10; distance = 2.8
			caption.text = "WALK-IN PANTRY / DRY STORAGE + ROACH HOME"
		4:
			target = Vector3(0, 1.2, -10)
			azimuth = 2.7; elevation = 0.19; distance = 14
			caption.text = "REAR ALLEY / SERVICE TRUCK + BACK ENTRANCE"
		5:
			target = Vector3(-1, 0, -0.2)
			azimuth = 0.5; elevation = 1.14; distance = 36
			caption.text = "NIGHT OWL / ROOF CUTAWAY"
		6:
			_pose(Vector3(5.2, 1.72, 5.8), Vector3(-1.1, 1.10, -3.1))
			caption.text = "BACK OF HOUSE / AFTER THE RUSH"
		7:
			_pose(Vector3(5.53, 0.072, 5.47), Vector3(6.65, 0.10, 4.40))
			caption.text = "ROACH HEIGHT / A DIFFERENT KIND OF OBSTACLE"
		8:
			_pose(Vector3(-1.84, 1.63, 9.45), Vector3(-1.1, 1.33, 8.35))
			caption.text = "GRAVEYARD ROAST / COUNTER DETAIL"
		9:
			_pose(Vector3(4.95, 1.3, 6.02), Vector3(6.96, 0.53, 4.30))
			caption.text = "CLEANING IN PROGRESS / APPARENTLY"
	_update_camera()

func _pose(from: Vector3, to: Vector3) -> void:
	target = to
	var offset := from - to
	distance = offset.length()
	elevation = asin(offset.y / distance)
	azimuth = atan2(offset.x, offset.z)

func _next_capture() -> void:
	var index := capture_views[capture_index]
	_view(index)
	capture = capture_directory.path_join("diner-%d.png" % index)
	frames = 0

func _update_camera() -> void:
	if camera == null: return
	camera.position = target + Vector3(sin(azimuth) * cos(elevation), sin(elevation), cos(azimuth) * cos(elevation)) * distance
	camera.look_at(target)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode >= KEY_1 and event.keycode <= KEY_9: _view(event.keycode - KEY_0)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT: dragging = event.pressed
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP: distance = maxf(0.15, distance * 0.9)
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN: distance = minf(65, distance * 1.1)
	if event is InputEventMouseMotion and dragging:
		azimuth -= event.relative.x * 0.006
		elevation = clampf(elevation + event.relative.y * 0.006, -0.5, 1.5)
	_update_camera()

func _process(_delta: float) -> void:
	if capture.is_empty(): return
	frames += 1
	if frames == 80:
		await RenderingServer.frame_post_draw
		var result := get_viewport().get_texture().get_image().save_png(capture)
		print("DINER CAPTURE: %s" % ("PASS" if result == OK else "FAIL"))
		print("DINER VIEW %d: %d draw calls / %d visible primitives" % [capture_views[capture_index] if not capture_directory.is_empty() else 0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
		if result == OK and not capture_directory.is_empty() and capture_index + 1 < capture_views.size():
			capture_index += 1
			_next_capture()
			return
		get_tree().quit(0 if result == OK else 1)
