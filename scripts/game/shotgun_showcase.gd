extends Node3D
## Isolated firing range using the real player and recoil controller.
var player: CharacterBody3D
var camera: Camera3D
var capture := ""
var moment := "ready"
var frames := 0
var capturing := false

func _ready() -> void:
	get_viewport().msaa_3d=Viewport.MSAA_4X
	get_viewport().use_taa=true
	var environment := Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color("202b2e")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_energy=0.6
	environment.tonemap_mode=Environment.TONE_MAPPER_AGX
	environment.ssao_enabled=true
	var world := WorldEnvironment.new()
	world.environment=environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-48,-30,0)
	sun.light_energy=1.4
	sun.shadow_enabled=true
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.position=Vector3(4,5,-4)
	fill.light_energy=2
	fill.omni_range=20
	add_child(fill)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size=Vector3(30,0.4,30)
	collision.shape=floor_shape
	floor_body.add_child(collision)
	floor_body.position.y=-0.2
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size=floor_shape.size
	mesh.mesh=box
	var mat := StandardMaterial3D.new()
	mat.albedo_color=Color("4d5551")
	mesh.material_override=mat
	floor_body.add_child(mesh)
	add_child(floor_body)
	var truck := preload("res://scenes/game/props/exterminator_truck.tscn").instantiate() as Node3D
	truck.position=Vector3(-5,0,0)
	add_child(truck)
	player=preload("res://scenes/game/player_token.tscn").instantiate() as CharacterBody3D
	player.name="1"
	player.get_node("Shotgun").preview_enabled=true
	add_child(player)
	player.configure_role("exterminator")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shotgun-capture="): capture=arg.trim_prefix("--shotgun-capture=")
		if arg.begins_with("--moment="): moment=arg.trim_prefix("--moment=")
	if not capture.is_empty():
		camera=Camera3D.new()
		camera.fov=42
		camera.current=true
		add_child(camera)
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func _process(_delta: float) -> void:
	frames+=1
	if capture.is_empty(): return
	camera.position=player.position+Vector3(3.4,2.2,-4.2)
	camera.look_at(player.position+Vector3(0,0.95,0))
	var gun := player.get_node("Shotgun")
	if frames==45 and moment!="ready": gun.request_fire()
	var ready := moment=="ready" and frames>=50
	ready=ready or (moment=="airborne" and gun.recoil_phase==1 and gun.recoil_age>0.18)
	ready=ready or (moment=="down" and gun.recoil_phase==2 and gun.recoil_age>0.12)
	ready=ready or (moment=="getup" and gun.recoil_phase==3 and gun.recoil_age>0.46)
	if ready and not capturing:
		capturing=true
		await RenderingServer.frame_post_draw
		var error := get_viewport().get_texture().get_image().save_png(capture)
		print("SHOTGUN CAPTURE: ",error_string(error))
		get_tree().quit(0 if error==OK else 1)
