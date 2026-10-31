extends Node3D
## Standalone art review. The truck itself owns no camera or map lighting.
var camera: Camera3D
var target := Vector3(0,1.4,0.65)
var azimuth := 0.82
var elevation := 0.25
var distance := 12.5
var dragging := false
var frames := 0
var capture := ""
var caption: Label

func _ready() -> void:
	get_viewport().msaa_3d=Viewport.MSAA_4X
	get_viewport().use_taa=true
	var environment := Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color("202b2e")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("c6d1d1")
	environment.ambient_light_energy=0.55
	environment.tonemap_mode=Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure=1.0
	environment.ssao_enabled=true
	environment.ssao_radius=0.35
	environment.ssao_intensity=1.3
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader=preload("res://assets/shaders/roach_studio.gdshader")
	sky.sky_material=sky_mat
	environment.sky=sky
	environment.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	var world := WorldEnvironment.new()
	world.environment=environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-44,-35,0)
	sun.light_color=Color("f7e9cc")
	sun.light_energy=1.6
	sun.shadow_enabled=true
	sun.directional_shadow_max_distance=45
	add_child(sun)
	for at: Vector3 in [Vector3(6,6,5),Vector3(-6,5,-5)]:
		var light := OmniLight3D.new()
		light.position=at
		light.light_energy=2.0
		light.omni_range=16
		light.light_color=Color("bbcfd9")
		light.shadow_enabled=true
		add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size=Vector2(200,200)
	floor_mesh.mesh=plane
	var ground := StandardMaterial3D.new()
	ground.albedo_color=Color("424b4b")
	ground.roughness=0.97
	floor_mesh.material_override=ground
	floor_mesh.position.y=-0.007
	add_child(floor_mesh)
	add_child(preload("res://scenes/game/props/exterminator_truck.tscn").instantiate())
	var worker := preload("res://scenes/game/exterminator_model.tscn").instantiate() as Node3D
	worker.position=Vector3(2.95,0,-0.50)
	worker.rotation.y=-0.3
	add_child(worker)
	camera=Camera3D.new()
	camera.fov=48
	camera.near=0.03
	camera.current=true
	add_child(camera)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	caption=Label.new()
	caption.position=Vector2(30,24)
	caption.add_theme_font_size_override("font_size",24)
	caption.text="NIGHT SHIFT  /  FIELD SERVICE 07"
	canvas.add_child(caption)
	var controls := Label.new()
	controls.position=Vector2(30,60)
	controls.text="1 Front   2 Rear workshop   3 Equipment wall   4 Driver side   5 Doors     /     Drag orbit • Wheel zoom"
	controls.add_theme_font_size_override("font_size",15)
	controls.modulate=Color("c3cdcb")
	canvas.add_child(controls)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--truck-capture="): capture=arg.trim_prefix("--truck-capture=")
		if arg=="--view=rear": _view(2)
		if arg=="--view=wall": _view(3)
		if arg=="--view=side": _view(4)
		if arg=="--view=doors": _view(5)
	_update_camera()

func _view(index: int) -> void:
	match index:
		1:
			target=Vector3(0,1.4,0.65); distance=12.5; azimuth=0.82; elevation=0.25
		2:
			target=Vector3(0,1.40,1.75); distance=10.8; azimuth=2.52; elevation=0.20
		3:
			target=Vector3(-0.72,1.97,1.22); distance=3.45; azimuth=1.27; elevation=0.02
		4:
			target=Vector3(0,1.40,0); distance=11.5; azimuth=-1.02; elevation=0.18
		5:
			target=Vector3(0,1.94,3.16)
			distance=5.4
			azimuth=PI-0.32
			elevation=0.15
	_update_camera()

func _update_camera() -> void:
	camera.position=target+Vector3(sin(azimuth)*cos(elevation),sin(elevation),-cos(azimuth)*cos(elevation))*distance
	camera.look_at(target)

func _process(_delta: float) -> void:
	frames+=1
	if frames==70 and not capture.is_empty():
		await RenderingServer.frame_post_draw
		var error := get_viewport().get_texture().get_image().save_png(capture)
		print("TRUCK CAPTURE: ",error_string(error))
		get_tree().quit(0 if error==OK else 1)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_1,KEY_2,KEY_3,KEY_4,KEY_5]: _view(event.keycode-KEY_1+1)
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT: dragging=event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			distance=clampf(distance+(-0.4 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 0.4),0.4,22)
			_update_camera()
	if event is InputEventMouseMotion and dragging:
		azimuth-=event.relative.x*0.006
		elevation=clampf(elevation+event.relative.y*0.006,-0.15,1.2)
		_update_camera()
