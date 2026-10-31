extends Node
## Host approves shots; the owning player simulates their existing movement body.
## Replicated pose fields are presentation, never damage or progression authority.
enum RecoilPhase { READY, AIRBORNE, DOWN, GETTING_UP }
const KICK_SPEED := 6.5
const KICK_LIFT := 4.6
const GROUND_PAUSE := 0.45
const GET_UP_TIME := 0.90
const SHOT_INTERVAL := 2.2
const SCOOT_SPEED := 1.1
const WeaponScene := preload("res://scenes/game/weapons/shotgun_model.tscn")
const Ballistics := preload("res://scripts/game/shotgun_ballistics.gd")

@export var recoil_phase := RecoilPhase.READY
@export var recoil_age := 0.0
@export var shot_serial := 0
@export var shot_yaw := 0.0
var preview_enabled := false
var _pending_nonce := 0
var _nonce := 0
var _last_host_shot := -10.0
var _host_nonce := 0
var _next_local_shot := 0.0
var _last_seen_shot := 0
var _flash_left := 0.0
var _weapon: Node3D
var _flash: MeshInstance3D
var _sound: AudioStreamPlayer3D
var _hud: Label
var _crosshair: Label
var _hit_left := 0.0
var _aim_pitch := 0.0
var _reload_shell: Node3D
@onready var token: CharacterBody3D = get_parent()

func setup() -> void:
	if _weapon!=null: return
	_weapon=WeaponScene.instantiate()
	token.exterminator_model.get_node("BodyRoot").add_child(_weapon)
	_weapon.position=Vector3(0.13,1.40,-0.19)
	_reload_shell = Node3D.new()
	token.exterminator_model.arm_left.get_node("Forearm/Hand").add_child(_reload_shell)
	_reload_shell.position = Vector3(0, -0.06, -0.02)
	_reload_shell.rotation.x = PI / 2
	for cap: bool in [false, true]:
		var part := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.0095 if cap else 0.009
		mesh.bottom_radius = mesh.top_radius
		mesh.height = 0.009 if cap else 0.055
		mesh.radial_segments = 12
		part.mesh = mesh
		part.position.y = -0.025 if cap else 0.0
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("c6a55b") if cap else Color("ad3528")
		material.metallic = 0.7 if cap else 0.0
		part.material_override = material
		_reload_shell.add_child(part)
	_reload_shell.visible = false
	_flash=MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius=0.07
	sphere.height=0.22
	_flash.mesh=sphere
	_flash.rotation.x=PI/2
	var glow := StandardMaterial3D.new()
	glow.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color=Color("ffe0a3")
	glow.emission_enabled=true
	glow.emission=Color("ffae4d")
	glow.emission_energy_multiplier=3.0
	_flash.material_override=glow
	_weapon.get_node("Muzzle").add_child(_flash)
	_flash.visible=false
	_sound=AudioStreamPlayer3D.new()
	_sound.stream=_shot_sound()
	_sound.volume_db=-10.0
	_sound.max_distance=32
	token.add_child(_sound)
	_sound.position=Vector3(0,1.4,0)
	if token.is_multiplayer_authority() and DisplayServer.get_name()!="headless":
		var canvas := CanvasLayer.new()
		token.add_child(canvas)
		_hud=Label.new()
		_hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_hud.position=Vector2(-220,-62)
		var world := token.get_parent().get_parent()
		if world!=null and world.has_method("get_match_phase"):
			_hud.position.y=-145
		_hud.size=Vector2(440,32)
		_hud.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		_hud.add_theme_font_size_override("font_size",19)
		canvas.add_child(_hud)
		_crosshair=Label.new()
		canvas.add_child(_crosshair)
		_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_crosshair.offset_left=-12
		_crosshair.offset_top=-17
		_crosshair.offset_right=12
		_crosshair.offset_bottom=17
		_crosshair.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		_crosshair.add_theme_font_size_override("font_size",24)
		_crosshair.text="+"
		_crosshair.mouse_filter=Control.MOUSE_FILTER_IGNORE

func _unhandled_input(event: InputEvent) -> void:
	if not token.is_multiplayer_authority(): return
	if event.is_action_pressed("weapon_fire") and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		request_fire()

func request_fire() -> bool:
	if not token.is_multiplayer_authority() or token.player_role!="exterminator": return false
	var direction: Vector3=-token.camera_rig.global_basis.z
	var yaw := atan2(-direction.x,-direction.z)
	return _request_aimed_shot(yaw, _aim_direction(yaw))

func request_solo_test_shot(at: Vector3) -> bool:
	if not Net.is_solo_test() or not at.is_finite(): return false
	# Scripted actors aim from the weapon rather than a headless camera that
	# might sit behind furniture. This is still a normal, host-validated intent.
	var facing: Vector3 = at - token.global_position
	var yaw := atan2(-facing.x, -facing.z)
	var grip := token.global_position + Basis(Vector3.UP, yaw) * Vector3(0.13, 1.4, -0.19)
	return _request_aimed_shot(yaw, (at - grip).normalized())

func _request_aimed_shot(yaw: float, aimed: Vector3) -> bool:
	if not token.is_multiplayer_authority() or token.player_role!="exterminator": return false
	if _gas_selected(): return false
	var ammo := _ammo()
	if ammo != null and not ammo.can_fire(token.get_multiplayer_authority()): return false
	var now := Time.get_ticks_msec()/1000.0
	if recoil_phase!=RecoilPhase.READY or now<_next_local_shot: return false
	if _pending_nonce!=0: return false
	_nonce+=1
	_pending_nonce=_nonce
	if multiplayer.is_server():
		var approved := _approve_request(token.get_multiplayer_authority(),_nonce,yaw,aimed)
		if not approved: _pending_nonce = 0
		return approved
	_request_shot.rpc_id(1,_nonce,yaw,aimed)
	return true

@rpc("any_peer","call_remote","reliable")
func _request_shot(nonce: int, yaw: float, aimed: Vector3) -> void:
	if not multiplayer.is_server(): return
	var sender := multiplayer.get_remote_sender_id()
	if sender != token.get_multiplayer_authority(): return
	if not aimed.is_finite() or absf(aimed.length_squared() - 1.0) > 0.01 or not _approve_request(sender, nonce, yaw, aimed):
		_receive_denial.rpc_id(sender, nonce)

@rpc("any_peer", "call_remote", "reliable")
func _receive_denial(nonce: int) -> void:
	if multiplayer.get_remote_sender_id() == 1 and token.is_multiplayer_authority() and nonce == _pending_nonce:
		_pending_nonce = 0

func _approve_request(sender: int, nonce: int, yaw: float, aimed: Vector3 = Vector3.ZERO) -> bool:
	if not multiplayer.is_server() or sender!=token.get_multiplayer_authority(): return false
	if nonce<=_host_nonce or not is_finite(yaw): return false
	if not aimed.is_finite(): return false
	if aimed==Vector3.ZERO: aimed=Basis(Vector3.UP,yaw)*Vector3.FORWARD
	if absf(aimed.length_squared()-1.0)>0.01: return false
	var world := token.get_parent().get_parent()
	if world!=null and world.has_method("get_role_for_peer"):
		if not world.is_peer_ready(sender) or world.get_role_for_peer(sender)!="exterminator": return false
		if _gas_selected(): return false
		if world.get("shotgun_ammo") != null and not world.shotgun_ammo.can_fire(sender): return false
		# Permit solo practice while waiting; freeze new shots after a result.
		if world.get_match_phase()>1: return false
	elif not preview_enabled:
		return false
	if token.player_role!="exterminator" or recoil_phase!=RecoilPhase.READY: return false
	var now := Time.get_ticks_msec()/1000.0
	if now-_last_host_shot<SHOT_INTERVAL: return false
	var approved_yaw := wrapf(yaw,-PI,PI)
	if world!=null and world.get("combat")!=null:
		if world.combat.fire_shot(sender,nonce,approved_yaw,aimed).is_empty(): return false
	elif preview_enabled:
		var chest := token.global_position+Vector3.UP*1.4
		var grip := token.global_position+Basis(Vector3.UP,approved_yaw)*Vector3(0.13,1.4,-0.19)
		var shot := Ballistics.trace(token.get_world_3d().direct_space_state,chest,grip,
			aimed,[token.get_rid()],token.collision_mask,nonce)
		present_impacts(aimed,shot.origin,shot.ends,false)
	_host_nonce=nonce
	_last_host_shot=now
	if sender==multiplayer.get_unique_id(): _receive_approval(nonce,approved_yaw)
	else: _receive_approval.rpc_id(sender,nonce,approved_yaw)
	return true

@rpc("any_peer","call_remote","reliable")
func _receive_approval(nonce: int, yaw: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender!=1 and not (sender==0 and multiplayer.is_server()): return
	if not token.is_multiplayer_authority() or nonce!=_pending_nonce: return
	_pending_nonce=0
	if token.player_role!="exterminator" or recoil_phase!=RecoilPhase.READY: return
	shot_serial+=1
	shot_yaw=yaw
	recoil_phase=RecoilPhase.AIRBORNE
	recoil_age=0
	_next_local_shot=Time.get_ticks_msec()/1000.0+SHOT_INTERVAL
	token.face_shotgun_direction(yaw)
	token.velocity=Basis(Vector3.UP,yaw)*Vector3(0,KICK_LIFT,KICK_SPEED)
	_apply_collision_pose()
	_play_shot()
	_last_seen_shot=shot_serial

func step_recoil(delta: float) -> bool:
	if token.player_role!="exterminator" or recoil_phase==RecoilPhase.READY: return false
	recoil_age+=delta
	_apply_collision_pose()
	token.velocity.y-=token.gravity*delta
	if token.is_on_floor() and (recoil_phase!=RecoilPhase.AIRBORNE or recoil_age>0.12):
		var target := Vector3.ZERO
		if recoil_phase == RecoilPhase.DOWN and not _can_stand() and token.can_read_movement_input():
			var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
			target = token.camera_rig.global_basis * Vector3(input.x, 0, input.y) * SCOOT_SPEED
			target.y = 0.0
		var flat := Vector3(token.velocity.x,0,token.velocity.z).move_toward(target,18.0*delta)
		token.velocity.x=flat.x
		token.velocity.z=flat.z
	token.move_and_slide()
	if recoil_phase==RecoilPhase.AIRBORNE and token.is_on_floor() and recoil_age>0.14:
		recoil_phase=RecoilPhase.DOWN
		recoil_age=0
	elif recoil_phase==RecoilPhase.DOWN and recoil_age>=GROUND_PAUSE and _can_stand():
		recoil_phase=RecoilPhase.GETTING_UP
		recoil_age=0
	elif recoil_phase==RecoilPhase.GETTING_UP:
		if not _can_stand():
			recoil_phase=RecoilPhase.DOWN
			recoil_age=GROUND_PAUSE
		elif recoil_age>=GET_UP_TIME:
			recoil_phase=RecoilPhase.READY
			recoil_age=0
			token.velocity=Vector3.ZERO
			_apply_collision_pose()
	return true

func _can_stand() -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=token.exterminator_collision.shape
	query.transform=Transform3D(Basis.IDENTITY,token.global_position+Vector3(0,1.086,0))
	query.collision_mask=token.collision_mask
	query.exclude=[token.get_rid()]
	query.margin=0.001
	return token.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _apply_collision_pose() -> void:
	if recoil_phase==RecoilPhase.READY:
		token.exterminator_collision.basis=Basis.IDENTITY
		token.exterminator_collision.position=Vector3(0,1.075,0)
	else:
		token.exterminator_collision.basis=Basis(Vector3.UP,shot_yaw)*Basis(Vector3.RIGHT,PI/2)
		token.exterminator_collision.position=Vector3(0,0.42,0)

func cancel_recoil() -> void:
	recoil_phase=RecoilPhase.READY
	recoil_age=0
	_pending_nonce=0
	_apply_collision_pose()

func reset_for_solo_test() -> void:
	if not Net.is_solo_test(): return
	# Keep nonces/serials monotonic so delayed packets cannot replay a prior shot.
	if multiplayer.is_server(): _last_host_shot = -10.0
	if not token.is_multiplayer_authority(): return
	cancel_recoil()
	_next_local_shot = 0.0
	_flash_left = 0.0
	_hit_left = 0.0
	if _sound != null: _sound.stop()

func _process(delta: float) -> void:
	if _weapon==null or not multiplayer.has_multiplayer_peer(): return
	var equipped: bool=token.player_role=="exterminator"
	_hit_left=maxf(0,_hit_left-delta)
	if equipped and token.is_multiplayer_authority() and recoil_phase==RecoilPhase.READY:
		var facing: Vector3=-token.camera_rig.global_basis.z
		var aimed := _aim_direction(atan2(-facing.x,-facing.z))
		_aim_pitch=asin(clampf(aimed.y,-1,1))
	token.exterminator_model.shotgun_pitch=_aim_pitch
	var gas_selected := _gas_selected()
	var ammo := _ammo()
	var peer_id := token.get_multiplayer_authority()
	var reloading: bool = ammo != null and ammo.is_reloading(peer_id) and not gas_selected
	token.exterminator_model.reload_blend = move_toward(token.exterminator_model.reload_blend, 1.0 if reloading else 0.0, delta * 8.0)
	token.exterminator_model.reload_cycle = ammo.reload_cycle(peer_id) if reloading else 0.0
	_reload_shell.visible = reloading and token.exterminator_model.reload_cycle > 0.12 and token.exterminator_model.reload_cycle < 0.86
	_weapon.visible=equipped and not gas_selected
	token.exterminator_model.shotgun_equipped=equipped
	token.exterminator_model.recoil_phase=recoil_phase if equipped else 0
	token.exterminator_model.recoil_age=recoil_age
	if recoil_phase!=RecoilPhase.READY:
		var hand := token.exterminator_model.get_node("BodyRoot/ArmRight/Forearm/Hand") as Node3D
		var gun_basis := hand.global_basis*Basis(Vector3.UP,-1.22)
		_weapon.global_transform=Transform3D(gun_basis,hand.global_position+gun_basis*Vector3(0,0.06,-0.065))
	else:
		_weapon.transform=Transform3D(token.exterminator_model.weapon_basis(),Vector3(0.13,1.40,-0.19))
	if equipped: _apply_collision_pose()
	if shot_serial!=_last_seen_shot:
		_last_seen_shot=shot_serial
		if equipped and recoil_phase==RecoilPhase.AIRBORNE and recoil_age<0.25: _play_shot()
	_flash_left=maxf(0,_flash_left-delta)
	_flash.visible=equipped and _flash_left>0
	if _hud!=null:
		_hud.visible=equipped
		var world := token.get_parent().get_parent()
		if world!=null and world.has_method("get_match_phase"):
			_hud.visible=equipped and world.get_match_phase()<=1
		_hud.text=["LMB  FIRE SHOTGUN","WHOA!","CATCHING YOUR BREATH…","GETTING UP…"][recoil_phase]
		if recoil_phase == RecoilPhase.DOWN and not _can_stand(): _hud.text = "LOW CEILING · WASD TO SCOOT CLEAR"
		if recoil_phase==RecoilPhase.READY and Time.get_ticks_msec()/1000.0<_next_local_shot: _hud.text="READYING SHOTGUN…"
		if gas_selected: _hud.text = world.gas_weapon.weapon_prompt()
		elif ammo != null:
			if reloading: _hud.text = ammo.prompt(peer_id)
			elif ammo.shells(peer_id) == 0: _hud.text = "SHOTGUN EMPTY · [R] RELOAD AT TRUCK"
			else: _hud.text += " · %d / %d SHELLS" % [ammo.shells(peer_id), ammo.CAPACITY]
		_crosshair.visible=_hud.visible and recoil_phase==RecoilPhase.READY
		if _hit_left>0: _crosshair.visible=_hud.visible
		_crosshair.text="×" if _hit_left>0 else "+"
		_crosshair.modulate=Color(1,0.65,0.2) if _hit_left>0 else Color.WHITE
	if equipped and token.is_multiplayer_authority():
		# Shoulder view leaves the aimed floor visible beside the character.
		# Clip the lateral offset first so nearby walls cannot put the camera outside.
		var pivot: Vector3=token.camera_rig.global_position
		var shoulder: Vector3=pivot+token.camera_rig.global_basis.x*0.75
		var obstruction := token.get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(pivot,shoulder,token.collision_mask,[token.get_rid()]))
		token.spring_arm.position.x=maxf(0,pivot.distance_to(obstruction.position)-0.08) if not obstruction.is_empty() else 0.75
		var height := 1.65 if recoil_phase==RecoilPhase.READY else 0.85
		token.camera_rig.position.y=lerpf(token.camera_rig.position.y,height,1-exp(-5*delta))
		token.camera.fov=lerpf(token.camera.fov,74.0 if _flash_left>0 else 68.0,1-exp(-9*delta))

func _gas_selected() -> bool:
	var world := token.get_parent().get_parent()
	return world != null and world.get("gas_weapon") != null and world.gas_weapon.is_selected(token.get_multiplayer_authority())

func _ammo() -> Node:
	var world := token.get_parent().get_parent()
	return world.get("shotgun_ammo") if world != null else null

func _play_shot() -> void:
	_flash_left=0.07
	if _sound!=null: _sound.play()

func aim_direction() -> Vector3:
	var facing: Vector3 = -token.camera_rig.global_basis.z
	return _aim_direction(atan2(-facing.x, -facing.z))

func _aim_direction(yaw: float) -> Vector3:
	var center := token.get_viewport().get_visible_rect().size*0.5
	var origin: Vector3=token.camera.project_ray_origin(center)
	var end: Vector3=origin+token.camera.project_ray_normal(center)*40.0
	var hit := token.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(origin,end,token.collision_mask,[token.get_rid()]))
	if not hit.is_empty(): end=hit.position
	var grip := token.global_position+Basis(Vector3.UP,yaw)*Vector3(0.13,1.4,-0.19)
	var aimed := end-grip
	return aimed.normalized() if aimed.length_squared()>0.001 else Basis(Vector3.UP,yaw)*Vector3.FORWARD

func present_impacts(direction: Vector3, origin: Vector3, ends: PackedVector3Array, hit: bool) -> void:
	_aim_pitch=asin(clampf(direction.y,-1,1))
	if hit and token.is_multiplayer_authority(): _hit_left=0.4
	if DisplayServer.get_name()=="headless" or ends.is_empty(): return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for end: Vector3 in ends:
		mesh.surface_add_vertex(origin)
		mesh.surface_add_vertex(end)
	mesh.surface_end()
	var trail := MeshInstance3D.new()
	trail.mesh=mesh
	trail.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color(1.0,0.76,0.35)
	trail.material_override=material
	token.add_child(trail)
	trail.top_level=true
	trail.global_transform=Transform3D.IDENTITY
	get_tree().create_timer(0.08).timeout.connect(func() -> void:
		if is_instance_valid(trail): trail.queue_free())

static func _shot_sound() -> AudioStreamWAV:
	var audio := AudioStreamWAV.new()
	audio.format=AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate=22050
	var data := PackedByteArray()
	data.resize(11025*2)
	var rng := RandomNumberGenerator.new()
	rng.seed=701
	for i: int in 11025:
		var t := i/22050.0
		var sample := (rng.randf_range(-1,1)*exp(-t*28)*0.65+sin(TAU*(76*t-24*t*t))*exp(-t*14)*0.35)
		data.encode_s16(i*2,int(clampf(sample,-1,1)*28000))
	audio.data=data
	return audio
