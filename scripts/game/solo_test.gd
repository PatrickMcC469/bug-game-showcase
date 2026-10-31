extends Node
## Developer-only local session. Both processes load this root and the real
## GameWorld at identical paths; the host remains the sole gameplay spawner.
const WORLD_SCENE := preload("res://scenes/game/game_world.tscn")
const BOT_SCRIPT := preload("res://scripts/game/solo_test_bot.gd")
const HUD_SCRIPT := preload("res://scripts/ui/solo_test_hud.gd")
const SCENE_PATH := "res://scenes/game/solo_test.tscn"
const SCENARIO_TITLES: Array[String] = ["Vent escape — play as roach", "Moving target — play as exterminator"]
const CONNECT_TIMEOUT := 120.0
const RESET_TIMEOUT := 10.0

var world: Node3D
var is_bot := false
var scenario := 0
var session_ready := false
var clock_paused := true
var bot_paused := false
var bot_peer_id := 0
var bot_pid := -1
var bot_log_path := ""
var opponent_stop_error: Error = OK
var error_message := ""
var _bot: Node
var _epoch := 0
var _applied_epoch := -1
var _pending := false
var _ready_reported := false
var _wait_left := CONNECT_TIMEOUT
var _elapsed := 0.0
var _shot_at_start := 0
var _heartbeat_path := ""
var _heartbeat_left := 0.0
var _previous_role := ""
var _hud: CanvasLayer
var _waiting_for_draw := false


func _ready() -> void:
	_start.call_deferred()


func _start() -> void:
	_previous_role = GameState.get_local_role_preference()
	var port := 0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--solo-bot-port="):
			is_bot = true
			port = argument.trim_prefix("--solo-bot-port=").to_int()
	if not is_bot:
		_hud = HUD_SCRIPT.new()
		add_child(_hud)
		_hud.setup(self)
	if not OS.is_debug_build():
		_fail("The solo lab requires a development build.")
		return
	Net.connection_failed.connect(_fail)
	Net.connected.connect(_create_world, CONNECT_ONE_SHOT)
	Net.player_left.connect(_on_peer_left)
	Net.host_left.connect(_on_host_left)
	GameState.set_local_role_preference("exterminator" if is_bot else "cockroach")
	if is_bot:
		if not Net.join_solo_test(port):
			_fail("Could not connect the scripted opponent.")
	elif not Net.host_solo_test():
		_fail("Could not start the local test session.")


func _create_world() -> void:
	world = create_test_world()
	world.name = "GameWorld"
	add_child(world)
	# Reserve the left side for the lab controls at the scaled UI resolution.
	world.get_node("%FoodHUD").set_stack_on_right(true)
	# The lab owns exit so its child process is closed before the connection.
	world.leave_button.pressed.disconnect(world._on_leave_pressed)
	world.leave_button.pressed.connect(leave_lab)
	if not is_bot:
		world.set_solo_clock_paused(true)
		# A cold renderer can spend minutes compiling the first room frame. Start
		# the client afterwards so ENet and its heartbeat do not expire mid-draw.
		if DisplayServer.get_name() != "headless":
			_waiting_for_draw = true
			await RenderingServer.frame_post_draw
			_waiting_for_draw = false
			if not is_inside_tree() or not error_message.is_empty(): return
		_wait_left = CONNECT_TIMEOUT
		_launch_bot()


func _launch_bot() -> void:
	var folder := OS.get_temp_dir().path_join("bug-game-solo-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		_fail("Could not create the opponent's temporary log directory.")
		return
	_heartbeat_path = folder.path_join("heartbeat.txt")
	bot_log_path = folder.path_join("opponent.log")
	if not _write_heartbeat():
		_fail("Could not write the opponent's heartbeat.")
		return
	bot_pid = OS.create_process(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--max-fps", "60", "--log-file", bot_log_path, get_scene_path(), "--",
		"--solo-bot-port=%d" % Net.get_solo_test_port(),
		"--local-test-heartbeat=" + _heartbeat_path,
		# First-frame shader compilation can stall the visible host for several
		# seconds. Normal scene exits still kill the child immediately.
		"--local-test-heartbeat-timeout=120",
	]))
	if bot_pid <= 0:
		_fail("Could not launch the scripted opponent. Reset to retry.")
	else:
		print("SOLO LAB: opponent pid=%d, log=%s" % [bot_pid, bot_log_path])


func _process(delta: float) -> void:
	if not error_message.is_empty() or _waiting_for_draw:
		return
	if not is_bot and bot_pid > 0:
		_heartbeat_left -= delta
		if _heartbeat_left <= 0:
			_heartbeat_left = 0.5
			if not OS.is_process_running(bot_pid):
				bot_pid = -1
				_fail("The opponent stopped. Reset to reconnect. Log: " + bot_log_path)
				return
			if not _write_heartbeat():
				_fail("Lost the opponent heartbeat. Reset to reconnect.")
				return
	if not session_ready:
		_wait_left -= delta
		if _wait_left <= 0:
			_fail("The opponent did not finish connecting/resetting. Reset to retry. Log: " + bot_log_path)
			return
	if is_bot and world != null and not _ready_reported:
		var own := world.players.get_node_or_null(str(multiplayer.get_unique_id())) as CharacterBody3D
		if own != null and world.players.has_node("1") and not world.get_role_for_peer(own.name.to_int()).is_empty():
			_bot = BOT_SCRIPT.new()
			add_child(_bot)
			_bot.setup(own, world)
			_ready_reported = true
			_bot_ready.rpc_id(1)
	if session_ready and not bot_paused and world.get_match_phase() == 1:
		_elapsed += delta


@rpc("any_peer", "call_remote", "reliable")
func _bot_ready() -> void:
	if not Net.is_host or not Net.is_solo_test() or world == null or bot_peer_id != 0:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not world.is_peer_ready(sender):
		return
	bot_peer_id = sender
	reset_scenario()


func select_scenario(index: int) -> void:
	if index < 0 or index >= get_scenario_titles().size() or not session_ready:
		return
	scenario = index
	reset_scenario()


func get_scenario_setup() -> Dictionary:
	var entrance: Vector3 = world.get_node("DinerKitchen/BugVents/LobbyEntrance").global_position
	var roach_at := entrance + Vector3(0.70, 0.002, 0)
	var human_at := entrance + Vector3(1.90, 0.002, 0.25)
	var route := PackedVector3Array([roach_at + Vector3(0, 0, 0.35), roach_at + Vector3(0, 0, 1.25)])
	if scenario == 1:
		# The central dining aisle leaves the shoulder camera and recoil clear
		# of the vent's wall and the neighboring chairs.
		human_at = Vector3(0, 0.003, 11.7)
		# Stay clear of the fallen dining-room prop's production collision.
		route = PackedVector3Array([Vector3(-0.7, 0.003, 10.2), Vector3(0.7, 0.003, 10.2)])
	return {
		"host_role": "cockroach" if scenario == 0 else "exterminator",
		"bot_role": "exterminator" if scenario == 0 else "cockroach",
		"host_position": roach_at if scenario == 0 else human_at,
		"bot_position": human_at if scenario == 0 else route[0],
		"host_yaw": PI / 2 if scenario == 0 else 0.6,
		"host_pitch": -0.24 if scenario == 0 else -0.62,
		"route": route,
	}


func reset_scenario() -> void:
	if is_bot:
		return
	if not error_message.is_empty():
		get_tree().change_scene_to_file(get_scene_path())
		return
	if not Net.is_host or bot_peer_id == 0 or _pending:
		return
	session_ready = false
	_pending = true
	_wait_left = CONNECT_TIMEOUT if _epoch == 0 else RESET_TIMEOUT
	_epoch += 1
	var setup := get_scenario_setup()
	prepare_scenario(setup)
	world.prepare_solo_round({1: setup.host_role, bot_peer_id: setup.bot_role})
	_apply_scenario(_epoch, scenario, setup)
	_apply_scenario.rpc_id(bot_peer_id, _epoch, scenario, setup)


@rpc("authority", "call_remote", "reliable")
func _apply_scenario(epoch: int, next_scenario: int, setup: Dictionary) -> void:
	if not Net.is_solo_test() or epoch <= _applied_epoch or world == null:
		return
	_applied_epoch = epoch
	_epoch = epoch
	scenario = next_scenario
	prepare_scenario(setup)
	session_ready = false
	_wait_left = CONNECT_TIMEOUT if epoch == 1 else RESET_TIMEOUT
	var own := world.players.get_node(str(multiplayer.get_unique_id())) as CharacterBody3D
	own.set_physics_process(false)
	# Consume the preceding reliable combat reset before relocation; otherwise a
	# ghost's old respawn serial could move its owner home on the following frame.
	own.apply_combat_state(world.combat.get_state(own.name.to_int()))
	for token: Node in world.players.get_children():
		token.shotgun.reset_for_solo_test()
	own.configure_role(setup.bot_role if is_bot else setup.host_role)
	own.reset_for_solo_test(setup.bot_position if is_bot else setup.host_position,
		PI / 2 if is_bot else setup.host_yaw, -0.35 if is_bot else setup.host_pitch)
	_elapsed = 0.0
	if is_bot:
		_bot.reset(int(setup.get("bot_scenario", scenario)), setup.route)
		_acknowledge_scenario(epoch, setup.host_position)
	else:
		var opponent: Node = world.players.get_node(str(bot_peer_id))
		var opponent_is_roach: bool = setup.bot_role == "cockroach"
		_shot_at_start = opponent.shotgun.shot_serial
		# A small fixed-size marker makes the insect-sized practice target easy
		# to locate. This is local lab presentation, not replicated gameplay.
		opponent.name_label.text = "TARGET" if opponent_is_roach else "SCRIPTED OPPONENT"
		opponent.name_label.fixed_size = true
		opponent.name_label.pixel_size = 0.0015
		opponent.name_label.font_size = 14
		opponent.name_label.position.y = 0.12 if opponent_is_roach else 2.45


func _acknowledge_scenario(epoch: int, host_position: Vector3) -> void:
	if await _wait_for_pose(1, host_position, epoch):
		_scenario_ready.rpc_id(1, epoch)


func _wait_for_pose(peer_id: int, at: Vector3, epoch: int) -> bool:
	# Movement Sync is a different stream from the reliable reset RPC. Let it
	# converge before either owner resumes physics, or the old opponent pose can
	# become a moving floor underneath a newly enlarged exterminator capsule.
	var deadline := Time.get_ticks_msec() + int((CONNECT_TIMEOUT if epoch == 1 else RESET_TIMEOUT) * 1000)
	while is_inside_tree() and epoch == _epoch and error_message.is_empty():
		var token := world.players.get_node_or_null(str(peer_id)) as Node3D
		if token != null and token.position.distance_to(at) < 0.025:
			return true
		if Time.get_ticks_msec() >= deadline:
			break
		await get_tree().physics_frame
	return false


@rpc("any_peer", "call_remote", "reliable")
func _scenario_ready(epoch: int) -> void:
	if not Net.is_host or not Net.is_solo_test() or multiplayer.get_remote_sender_id() != bot_peer_id:
		return
	if epoch != _epoch or not _pending:
		return
	if not await _wait_for_pose(bot_peer_id, get_scenario_setup().bot_position, epoch):
		return
	_pending = false
	world.start_solo_round(clock_paused)
	_begin_scenario(epoch, bot_paused)
	_begin_scenario.rpc_id(bot_peer_id, epoch, bot_paused)
	print("SOLO LAB: ready, scenario=%d, attempt=%d" % [scenario, epoch])


@rpc("authority", "call_remote", "reliable")
func _begin_scenario(epoch: int, paused: bool) -> void:
	if not Net.is_solo_test() or epoch != _epoch:
		return
	session_ready = true
	bot_paused = paused
	_elapsed = 0.0
	world.players.get_node(str(multiplayer.get_unique_id())).set_physics_process(true)
	if _bot != null:
		_bot.set_paused(paused)


func toggle_clock() -> void:
	if not session_ready or not Net.is_host:
		return
	clock_paused = not clock_paused
	world.set_solo_clock_paused(clock_paused)


func add_time() -> void:
	if session_ready and Net.is_host:
		world.add_solo_time(30)


func toggle_bot() -> void:
	if not session_ready or not Net.is_host:
		return
	bot_paused = not bot_paused
	_set_bot_paused.rpc_id(bot_peer_id, _epoch, bot_paused)


@rpc("authority", "call_remote", "reliable")
func _set_bot_paused(epoch: int, paused: bool) -> void:
	if not Net.is_solo_test() or epoch != _epoch or _bot == null:
		return
	bot_paused = paused
	_bot.set_paused(paused)


func get_status() -> String:
	if not error_message.is_empty():
		return error_message
	if _waiting_for_draw:
		return "Preparing the room…"
	if not session_ready:
		return "Resetting both players…" if _pending else "Starting scripted opponent…"
	if world.get_match_phase() > 1:
		return "Round finished. Reset to try again."
	if bot_paused:
		return "Opponent paused. Explore or set up your shot."
	if scenario == 1:
		return "Target health: %d / 100%s" % [world.combat.get_state(bot_peer_id).health,
			" · ghost respawning" if world.combat.is_ghost(bot_peer_id) else " · walking its route"]
	var gun: Node = world.players.get_node(str(bot_peer_id)).shotgun
	if gun.shot_serial > _shot_at_start:
		return "Shot fired. Reset to repeat the escape."
	return "Shot in %.1fs — run into the wall vent!" % maxf(0, BOT_SCRIPT.SHOT_DELAY - _elapsed)


func _input(event: InputEvent) -> void:
	if is_bot or not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F1:
			if _hud != null: _hud.toggle_panel()
		KEY_F5: reset_scenario()
		KEY_F6: toggle_clock()
		KEY_F7: toggle_bot()
		KEY_F8: add_time()
		_: return
	get_viewport().set_input_as_handled()


func _write_heartbeat() -> bool:
	var file := FileAccess.open(_heartbeat_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(str(Time.get_unix_time_from_system()))
	return true


func _on_peer_left(peer_id: int) -> void:
	if not is_bot and peer_id == bot_peer_id:
		_fail("The opponent disconnected. Reset to reconnect. Log: " + bot_log_path)


func _on_host_left() -> void:
	if is_bot:
		get_tree().quit()


func _fail(message: String) -> void:
	error_message = message
	session_ready = false
	push_warning("SOLO LAB: " + message)
	if is_bot:
		get_tree().quit(1)


func leave_lab() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _exit_tree() -> void:
	# Own only the process launched by this scene. The heartbeat also ends the
	# child if the host crashes or the editor stops it without a graceful exit.
	if bot_pid > 0 and OS.is_process_running(bot_pid):
		opponent_stop_error = OS.kill(bot_pid)
	bot_pid = -1
	if not _heartbeat_path.is_empty():
		DirAccess.remove_absolute(_heartbeat_path)
	if Net.is_solo_test():
		Net.leave()
	if not is_bot:
		GameState.set_local_role_preference(_previous_role)
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func create_test_world() -> Node3D:
	return WORLD_SCENE.instantiate()

func prepare_scenario(_setup: Dictionary) -> void:
	pass

func get_scene_path() -> String:
	return SCENE_PATH

func get_scenario_titles() -> Array[String]:
	return SCENARIO_TITLES

func get_lab_title() -> String:
	return "SOLO TEST LAB"

func get_instruction() -> String:
	return "You are the roach. Run straight ahead into the wall vent before the exterminator fires once." if scenario == 0 else "You are the exterminator. Aim at the roach crossing the dining aisle. Pause it to practice a stationary shot."
