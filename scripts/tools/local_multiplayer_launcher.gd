extends SceneTree
## Opens a local ENet host and one to three auto-joining clients for hands-on
## multiplayer testing. Keep this process running and press Ctrl+C to close all
## child windows.
##
## Run from the repo root:
##   godot --headless --path . --script res://scripts/tools/local_multiplayer_launcher.gd
##   godot --headless --path . --script res://scripts/tools/local_multiplayer_launcher.gd -- --clients=3

const CLIENTS_ARGUMENT_PREFIX := "--clients="
const DEFAULT_CLIENTS := 1
const MAX_CLIENTS := 3
const HOST_STARTUP_TIMEOUT_MS := 60000
const CLIENT_STARTUP_DELAY_SECONDS := 0.35
const WINDOW_SIZE := Vector2i(720, 405)
const WINDOW_POSITIONS: Array[Vector2i] = [
	Vector2i(20, 40),
	Vector2i(760, 40),
	Vector2i(20, 485),
	Vector2i(760, 485),
]

var _child_pids: Array[int] = []
var _log_directory := ""
var _heartbeat_path := ""
var _port_path := ""
var _port := 0


func _initialize() -> void:
	_launch_session.call_deferred()


func _launch_session() -> void:
	var client_count := _read_client_count()
	_log_directory = OS.get_temp_dir().path_join(
		"bug-game-local-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	var directory_error := DirAccess.make_dir_recursive_absolute(_log_directory)
	if directory_error != OK:
		printerr("LOCAL MULTIPLAYER: could not create log directory: %s" % _log_directory)
		quit(1)
		return
	_heartbeat_path = _log_directory.path_join("launcher-heartbeat.txt")
	_port_path = _log_directory.path_join("host-port.txt")
	if not _write_heartbeat():
		quit(1)
		return

	if not _launch_instance("host", 0):
		quit(1)
		return

	# Wait for the live host's bound port before launching clients. Every
	# launcher has its own directory, so simultaneous sessions cannot cross-join.
	var deadline := Time.get_ticks_msec() + HOST_STARTUP_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline and OS.is_process_running(_child_pids[0]):
		_write_heartbeat()
		if FileAccess.file_exists(_port_path):
			var value := FileAccess.get_file_as_string(_port_path).strip_edges()
			if value.is_valid_int() and value.to_int() > 0 and value.to_int() <= 65535:
				_port = value.to_int()
				break
		await create_timer(0.1).timeout
	if _port == 0:
		printerr("LOCAL MULTIPLAYER: host did not publish its port; see " + _log_directory)
		_shutdown_children()
		quit(1)
		return
	print("LOCAL MULTIPLAYER: using 127.0.0.1:%d" % _port)
	for client_index in range(client_count):
		if not _launch_instance("client", client_index + 1):
			_shutdown_children()
			quit(1)
			return
		await create_timer(CLIENT_STARTUP_DELAY_SECONDS).timeout
		_write_heartbeat()

	print("LOCAL MULTIPLAYER: started 1 host + %d client(s)" % client_count)
	print("LOCAL MULTIPLAYER: logs: %s" % _log_directory)
	print("LOCAL MULTIPLAYER: press Esc to release the mouse; Ctrl+C closes every window")

	while not _child_pids.is_empty():
		await create_timer(0.5).timeout
		_write_heartbeat()
		_remove_finished_processes()
	quit()


func _read_client_count() -> int:
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with(CLIENTS_ARGUMENT_PREFIX):
			continue
		var raw_count := argument.trim_prefix(CLIENTS_ARGUMENT_PREFIX)
		if raw_count.is_valid_int():
			return clampi(raw_count.to_int(), 1, MAX_CLIENTS)
		push_warning("Ignoring invalid client count: %s" % raw_count)
	return DEFAULT_CLIENTS


func _launch_instance(role: String, slot: int) -> bool:
	var position := WINDOW_POSITIONS[slot]
	var log_path := _log_directory.path_join("%s-%d.log" % [role, slot])
	var arguments := PackedStringArray([
		"--path", ProjectSettings.globalize_path("res://"),
		"--windowed",
		"--resolution", "%dx%d" % [WINDOW_SIZE.x, WINDOW_SIZE.y],
		"--position", "%d,%d" % [position.x, position.y],
		"--max-fps", "60",
		"--log-file", log_path,
		"--",
		"--local-test=%s" % role,
		"--local-test-heartbeat=%s" % _heartbeat_path,
	])
	if role == "host":
		arguments.append("--local-test-port-file=" + _port_path)
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--local-test-port="): arguments.append(argument)
	else:
		arguments.append("--local-test-port=%d" % _port)
	var pid := OS.create_process(OS.get_executable_path(), arguments)
	if pid <= 0:
		printerr("LOCAL MULTIPLAYER: could not launch %s window" % role)
		return false
	_child_pids.append(pid)
	print("LOCAL MULTIPLAYER: %s pid=%d" % [role, pid])
	return true


func _write_heartbeat() -> bool:
	var heartbeat_file := FileAccess.open(_heartbeat_path, FileAccess.WRITE)
	if heartbeat_file == null:
		printerr("LOCAL MULTIPLAYER: could not write heartbeat: %s" % _heartbeat_path)
		return false
	heartbeat_file.store_string(str(Time.get_unix_time_from_system()))
	return true


func _remove_finished_processes() -> void:
	var running_pids: Array[int] = []
	for pid in _child_pids:
		if OS.is_process_running(pid):
			running_pids.append(pid)
	_child_pids = running_pids


func _shutdown_children() -> void:
	for pid in _child_pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
	_child_pids.clear()


func _finalize() -> void:
	_shutdown_children()
