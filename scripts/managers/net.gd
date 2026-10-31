extends Node
## Single entry point for going online. UI talks to this and nothing else.
##
## Two transports behind one interface:
##   ENET  — works right now, no dependencies. Localhost/LAN. Use this to test
##           gameplay by launching two editor windows (F5 twice, or Debug >
##           Run Multiple Instances).
##   STEAM — Valve's relay: NAT traversal and friend invites for free, which is
##           the whole reason we're shipping on Steam. Needs GodotSteam.
##
## Both feed Godot's high-level MultiplayerAPI, so every rpc(),
## MultiplayerSpawner and MultiplayerSynchronizer works identically on either.
## Nothing in scenes/ or scripts/game/ should know which one is active.

signal connected()
signal connection_failed(reason: String)
signal player_joined(peer_id: int)
signal player_left(peer_id: int)
signal host_left()

enum Transport { ENET, STEAM }

const DEFAULT_PORT := 27015
const MAX_PLAYERS := 4
const LOCAL_TEST_HEARTBEAT_ARGUMENT_PREFIX := "--local-test-heartbeat="
const LOCAL_TEST_HEARTBEAT_CHECK_SECONDS := 0.5
const LOCAL_TEST_HEARTBEAT_TIMEOUT_SECONDS := 3.0

var transport: int = Transport.ENET
var is_host := false
var _local_test_heartbeat_path := ""
var _local_test_heartbeat_check_elapsed := 0.0
var _local_test_heartbeat_timeout := LOCAL_TEST_HEARTBEAT_TIMEOUT_SECONDS
var _last_test_heartbeat := 0.0
var _solo_test_port := 0
var _local_test_port := 0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_read_local_test_heartbeat_path()
	_last_test_heartbeat = Time.get_unix_time_from_system()
	set_process(not _local_test_heartbeat_path.is_empty())


func _process(delta: float) -> void:
	_local_test_heartbeat_check_elapsed += delta
	if _local_test_heartbeat_check_elapsed < LOCAL_TEST_HEARTBEAT_CHECK_SECONDS:
		return
	_local_test_heartbeat_check_elapsed = 0.0
	var file := FileAccess.open(_local_test_heartbeat_path, FileAccess.READ)
	var last_heartbeat := file.get_as_text().to_float() if file != null else 0.0
	# A write briefly truncates this file. Keep the last valid timestamp instead
	# of treating that read/write race as an immediate launcher shutdown.
	if last_heartbeat > 0.0:
		_last_test_heartbeat = last_heartbeat
	var heartbeat_age := Time.get_unix_time_from_system() - _last_test_heartbeat
	if heartbeat_age > _local_test_heartbeat_timeout:
		print("LOCAL TEST: launcher closed; quitting this game window")
		get_tree().quit()


func _read_local_test_heartbeat_path() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(LOCAL_TEST_HEARTBEAT_ARGUMENT_PREFIX):
			_local_test_heartbeat_path = argument.trim_prefix(LOCAL_TEST_HEARTBEAT_ARGUMENT_PREFIX)
		elif argument.begins_with("--local-test-heartbeat-timeout="):
			_local_test_heartbeat_timeout = clampf(argument.trim_prefix("--local-test-heartbeat-timeout=").to_float(), 3.0, 120.0)


## Preferred transport, given what's actually installed.
func best_transport() -> int:
	return Transport.STEAM if SteamManager.available else Transport.ENET


## Test harness entry points intentionally bypass Steam without leaking the
## transport enum or ENet peer setup into UI code.
func host_local_test(port: int = 0) -> bool:
	port = _local_test_port_argument(port)
	if port < 0 or port > 65535:
		return _fail("Local test port must be 0 (automatic) or 1–65535")
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip("127.0.0.1")
	# Bind first and retain the socket: probing then releasing a free port would
	# let another concurrently starting test claim it before this host does.
	if peer.create_server(port, MAX_PLAYERS - 1) != OK:
		return _fail("Could not bind local test port %d; use 0 for an available port" % port)
	_local_test_port = peer.get_host().get_local_port()
	_solo_test_port = 0
	transport = Transport.ENET
	multiplayer.multiplayer_peer = peer
	is_host = true
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--local-test-port-file="):
			var file := FileAccess.open(argument.trim_prefix("--local-test-port-file="), FileAccess.WRITE)
			if file == null: return _fail("Could not publish the local test port")
			file.store_string(str(_local_test_port))
			file.close()
	GameState.register_player(1)
	print("LOCAL TEST: host listening on 127.0.0.1:%d" % _local_test_port)
	connected.emit()
	return true


func join_local_test(port: int = DEFAULT_PORT) -> bool:
	port = _local_test_port_argument(port)
	if port < 1 or port > 65535:
		return _fail("Local test client needs the host's port (1–65535)")
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client("127.0.0.1", port) != OK:
		return _fail("Could not join local test port %d" % port)
	_local_test_port = port
	_solo_test_port = 0
	transport = Transport.ENET
	multiplayer.multiplayer_peer = peer
	is_host = false
	return true


func get_local_test_port() -> int:
	return _local_test_port


func get_local_test_arguments() -> PackedStringArray:
	return PackedStringArray(["--local-test-port=%d" % _local_test_port])


func _local_test_port_argument(fallback: int) -> int:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--local-test-port="):
			var value := argument.trim_prefix("--local-test-port=")
			return value.to_int() if value.is_valid_int() else -1
	return fallback


## A separate loopback-only session for the developer lab. An ephemeral port
## lets it coexist with normal local matches and other copies of the editor.
func host_solo_test() -> bool:
	if not OS.is_debug_build():
		return false
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip("127.0.0.1")
	if peer.create_server(0, 1) != OK:
		return _fail("Could not start the solo test session")
	_solo_test_port = peer.get_host().get_local_port()
	_local_test_port = 0
	transport = Transport.ENET
	multiplayer.multiplayer_peer = peer
	is_host = true
	GameState.register_player(1)
	connected.emit()
	return true


func join_solo_test(port: int) -> bool:
	if not OS.is_debug_build() or port < 1 or port > 65535:
		return false
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client("127.0.0.1", port) != OK:
		return _fail("Could not join the solo test session")
	_solo_test_port = port
	_local_test_port = 0
	transport = Transport.ENET
	multiplayer.multiplayer_peer = peer
	is_host = false
	return true


func is_solo_test() -> bool:
	return OS.is_debug_build() and _solo_test_port > 0


func get_solo_test_port() -> int:
	return _solo_test_port


func host_game(use: int = -1) -> bool:
	if use not in [-1, Transport.ENET, Transport.STEAM]:
		return _fail("Unknown network transport")
	_solo_test_port = 0
	_local_test_port = 0
	transport = use if use >= 0 else best_transport()
	var peer: MultiplayerPeer = null

	if transport == Transport.STEAM:
		peer = _make_steam_peer()
		if peer == null:
			return _fail("Steam peer unavailable")
		# Steam hosts listen on their own ID; there is no port to bind.
		if peer.call("create_host", 0) != OK:
			return _fail("Could not open Steam host")
	else:
		var enet := ENetMultiplayerPeer.new()
		# ENet's limit counts remote clients; the lobby cap includes the host.
		if enet.create_server(DEFAULT_PORT, MAX_PLAYERS - 1) != OK:
			return _fail("Port %d is busy" % DEFAULT_PORT)
		peer = enet

	multiplayer.multiplayer_peer = peer
	is_host = true
	GameState.register_player(1)
	connected.emit()
	return true


## `address` is an IP for ENet, or the host's Steam ID for the Steam transport.
func join_game(address: String = "127.0.0.1", use: int = -1) -> bool:
	if use not in [-1, Transport.ENET, Transport.STEAM]:
		return _fail("Unknown network transport")
	_solo_test_port = 0
	_local_test_port = 0
	transport = use if use >= 0 else best_transport()
	address = address.strip_edges()
	if address.is_empty():
		return _fail("Enter a host address")
	var peer: MultiplayerPeer = null

	if transport == Transport.STEAM:
		if not address.is_valid_int() or address.to_int() <= 0:
			return _fail("Enter the host's numeric Steam ID")
		peer = _make_steam_peer()
		if peer == null:
			return _fail("Steam peer unavailable")
		if peer.call("create_client", int(address), 0) != OK:
			return _fail("Could not reach that Steam host")
	else:
		var enet := ENetMultiplayerPeer.new()
		if enet.create_client(address, DEFAULT_PORT) != OK:
			return _fail("Could not reach %s" % address)
		peer = enet

	multiplayer.multiplayer_peer = peer
	is_host = false
	return true


func leave() -> void:
	_reset_session()


func _reset_session() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	is_host = false
	transport = Transport.ENET
	_solo_test_port = 0
	_local_test_port = 0
	SteamManager.leave_lobby()
	GameState.clear()


## Built by name so this file still parses without GodotSteam installed.
func _make_steam_peer() -> MultiplayerPeer:
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		return null
	return ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer


func _fail(reason: String) -> bool:
	_reset_session()
	push_warning(reason)
	connection_failed.emit(reason)
	return false


func _on_peer_connected(peer_id: int) -> void:
	# ENet/Steam relay peer events are delivered to every participant. Mirroring
	# them locally keeps the lightweight session roster available on clients too;
	# only host-authoritative gameplay state should require explicit replication.
	GameState.register_player(peer_id)
	player_joined.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	GameState.unregister_player(peer_id)
	player_left.emit(peer_id)


func _on_connected_to_server() -> void:
	# peer_connected reports the remote peers, not this client's own ID.
	GameState.register_player(multiplayer.get_unique_id())
	connected.emit()


func _on_connection_failed() -> void:
	_reset_session()
	connection_failed.emit("Connection failed")


func _on_server_disconnected() -> void:
	_reset_session()
	host_left.emit()
