extends SceneTree
## Exercise real ENet session limits and menu/lobby callbacks without Steam.
var failures: Array[String] = []

class SteamStub extends RefCounted:
	var creations := 0
	var joins: Array[int] = []
	var leaves: Array[int] = []
	var host_id := ""
	func run_callbacks() -> void: pass
	func createLobby(_kind: int, _limit: int) -> void: creations += 1
	func joinLobby(id: int) -> void: joins.append(id)
	func leaveLobby(id: int) -> void: leaves.append(id)
	func setLobbyData(_id: int, _key: String, value: String) -> void: host_id = value
	func getLobbyData(_id: int, _key: String) -> String: return host_id

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _check_sessions()
	await _check_loading_exit()
	await _check_menu_lobbies()
	await process_frame
	await process_frame
	for failure: String in failures: printerr("SESSION FAIL: " + failure)
	print("SESSION TEST: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _check_sessions() -> void:
	var net := root.get_node("Net")
	var state := root.get_node("GameState")
	_check(not net.host_game(99), "invalid host transport accepted")
	_check(not net.join_game("127.0.0.1", 99), "invalid join transport accepted")
	_check(not net.join_game(" ", net.Transport.ENET), "blank address accepted")
	_check(not net.join_game("Host's Steam ID", net.Transport.STEAM), "placeholder became a Steam address")
	_check(net.host_local_test(), "local host failed")
	var port: int = net.get_local_test_port()
	var clients: Array[Node] = []
	# Each subtree runs the production Net API with its own MultiplayerAPI.
	# No gameplay or UI chooses or instantiates a transport for this capacity test.
	for index: int in net.MAX_PLAYERS:
		var client := (load("res://scripts/managers/net.gd") as GDScript).new() as Node
		client.name = "SessionClient%d" % index
		set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + str(client.name)))
		root.add_child(client)
		clients.append(client)
		_check(client.join_local_test(port), "could not begin local client")
		if index < net.MAX_PLAYERS - 1:
			_check(await _until(func() -> bool: return client.multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED), "allowed client could not connect")
	await create_timer(0.5).timeout
	_check(net.multiplayer.get_peers().size() == net.MAX_PLAYERS - 1, "player cap does not include host")
	_check(clients.back().multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED, "extra player connected beyond cap")
	for client: Node in clients:
		var path := client.get_path()
		client.leave()
		client.free()
		set_multiplayer(null, path)
	net.leave()
	_check(not net.is_host and net.transport == net.Transport.ENET and net.get_local_test_port() == 0 and not net.is_solo_test(), "session state leaked after leave")
	_check(state.player_count() == 0 and state.get_local_role_preference().is_empty(), "session roster/preference leaked")
	_check(net.host_solo_test(), "lab could not start after normal session")
	net.leave()
	_check(net.host_local_test(), "normal session could not restart after lab")
	net.leave()

func _check_loading_exit() -> void:
	var menu := load("res://scenes/ui/main_menu.tscn").instantiate() as Control
	root.add_child(menu)
	var path: String = menu.game_scene_path
	menu.queue_free()
	await process_frame
	await process_frame
	_check(ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_IN_PROGRESS, "closing menu left asset compilation running")

func _check_menu_lobbies() -> void:
	var steam := root.get_node("SteamManager")
	var original_backend: Variant = steam._steam
	var original_available: bool = steam.available
	var stub := SteamStub.new()
	steam._steam = stub
	steam.available = true
	var menu := load("res://scenes/ui/main_menu.tscn").instantiate() as Control
	root.add_child(menu)
	# An invite can arrive while the asynchronous resource loader is working.
	steam._on_join_requested(701, 123)
	_check(await _until(func() -> bool: return menu._game_scene != null, 30000), "menu did not prepare its scene")
	_check(stub.joins == [701], "invite was dropped or joined more than once while loading")
	steam._on_lobby_joined(701, 0, false, 1)
	_check(menu.status_label.text.contains("no host") and not menu.host_button.disabled, "invalid lobby did not recover menu")
	_check(steam.lobby_id == 0 and 701 in stub.leaves, "invalid lobby was not left")
	# Persistent scene-owned connections must survive a failure/retry without
	# accumulating one-shot handlers on the outcome that did not fire.
	for attempt: int in 2:
		menu._on_host_pressed()
		steam._on_lobby_created(2, 0)
		_check(not menu.host_button.disabled and not menu._connecting, "failed lobby creation left menu busy")
	_check(stub.creations == 2, "host retry issued duplicate lobby creation")
	_check(steam.lobby_created.get_connections().size() == 1 and steam.lobby_failed.get_connections().size() == 1, "retry accumulated lobby handlers")
	steam.join_lobby(702)
	steam.leave_lobby()
	steam._on_lobby_joined(702, 0, false, 1)
	_check(steam.lobby_id == 0 and 702 in stub.leaves, "cancelled join restored an abandoned lobby")
	# With the optional transport absent, reaching its explicit error verifies
	# that a valid invite progresses from the lobby to Net.join_game().
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		stub.host_id = "76561198000000001"
		steam._on_join_requested(703, 123)
		steam._on_lobby_joined(703, 0, false, 1)
		_check(menu.status_label.text == "Steam peer unavailable", "valid invite never reached the transport boundary")
		menu._on_host_pressed()
		steam._on_lobby_created(1, 704)
		steam._on_lobby_joined(704, 0, false, 1)
		_check(not menu._connecting and steam.lobby_id == 0, "host callback echo rejoined a failed lobby")
	menu.free()
	_check(steam.invite_requested.get_connections().is_empty(), "menu invite handler outlived scene")
	steam.leave_lobby()
	steam._steam = original_backend
	steam.available = original_available

func _until(check: Callable, timeout: int = 5000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout
	while Time.get_ticks_msec() < deadline:
		if check.call(): return true
		await process_frame
	return check.call()

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
