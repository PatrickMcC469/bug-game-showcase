extends Control
## Host / join entry point. Knows nothing about transports — that's Net's job.

const LOCAL_TEST_ARGUMENT_PREFIX := "--local-test="
const ROLE_AUTO := ""
const ROLE_EXTERMINATOR := "exterminator"
const ROLE_COCKROACH := "cockroach"

enum RoleChoice {
	AUTO,
	EXTERMINATOR,
	COCKROACH,
}

@export_file("*.tscn") var game_scene_path: String = "res://scenes/game/game_world.tscn"

@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var address_field: LineEdit = %AddressField
@onready var role_option: OptionButton = %RoleOption
@onready var status_label: Label = %StatusLabel

var _local_test_role := ""
var _solo_test_button: Button
var _game_scene: PackedScene
var _dev_room_button: Button
var _connecting := false
var _entering_game := false
var _pending_lobby_id := 0
var _hosting_lobby := false
var _loading_scene := false


func _ready() -> void:
	theme = Theme.new()
	theme.default_font_size = 20
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_configure_role_option()
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	Net.connected.connect(_enter_game)
	Net.connection_failed.connect(_on_failed)
	SteamManager.lobby_created.connect(_on_lobby_ready)
	SteamManager.lobby_joined.connect(_on_lobby_joined)
	SteamManager.lobby_failed.connect(_on_failed)
	SteamManager.invite_requested.connect(_on_invite_requested)
	if OS.is_debug_build():
		_solo_test_button = Button.new()
		_solo_test_button.name = "SoloTestButton"
		_solo_test_button.text = "Solo Test Lab (developer)"
		_solo_test_button.custom_minimum_size.y = 42
		_solo_test_button.pressed.connect(_on_solo_test_pressed)
		host_button.add_sibling(_solo_test_button)
		_dev_room_button = Button.new()
		_dev_room_button.name = "DevRoomButton"
		_dev_room_button.text = "Mechanics Dev Room (developer)"
		_dev_room_button.custom_minimum_size.y = 42
		_dev_room_button.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/game/dev_room.tscn"))
		_solo_test_button.add_sibling(_dev_room_button)

	if SteamManager.available:
		status_label.text = "Steam ready — %s. Hosting uses the Steam relay." % SteamManager.steam_name
		address_field.placeholder_text = "Host's Steam ID"
	else:
		status_label.text = "ENet (local). Run a second window to test."
		address_field.placeholder_text = "127.0.0.1"

	_local_test_role = _get_local_test_role()
	# Keep the connection handshake and initial snapshots clear of asset I/O.
	# The scanned diner can take several seconds to load on a cold machine.
	var ready_status := status_label.text
	_set_busy(true)
	status_label.text = "Preparing diner..."
	if ResourceLoader.load_threaded_request(game_scene_path) != OK:
		status_label.text = "Could not prepare the diner. Check the project log."
		return
	_loading_scene = true
	while ResourceLoader.load_threaded_get_status(game_scene_path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	if ResourceLoader.load_threaded_get_status(game_scene_path) != ResourceLoader.THREAD_LOAD_LOADED:
		_loading_scene = false
		status_label.text = "Could not load the diner. Check the project log."
		return
	_game_scene = ResourceLoader.load_threaded_get(game_scene_path) as PackedScene
	_loading_scene = false
	if _game_scene == null:
		status_label.text = "The diner scene could not be opened."
		return
	status_label.text = ready_status
	_set_busy(false)
	if not _local_test_role.is_empty():
		_start_local_test.call_deferred(_local_test_role)
	elif _pending_lobby_id > 0:
		_join_pending_lobby()


func _exit_tree() -> void:
	if _loading_scene:
		# Godot cannot cancel a threaded load. Drain it before shutdown frees the
		# autoloads that background GDScript compilation still needs to resolve.
		ResourceLoader.load_threaded_get(game_scene_path)
		_loading_scene = false


func _configure_role_option() -> void:
	role_option.add_item("Automatic (host exterminator)", RoleChoice.AUTO)
	role_option.add_item("Exterminator", RoleChoice.EXTERMINATOR)
	role_option.add_item("Cockroach", RoleChoice.COCKROACH)
	match GameState.get_local_role_preference():
		ROLE_EXTERMINATOR:
			role_option.select(RoleChoice.EXTERMINATOR)
		ROLE_COCKROACH:
			role_option.select(RoleChoice.COCKROACH)
		_:
			role_option.select(RoleChoice.AUTO)


func _get_local_test_role() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(LOCAL_TEST_ARGUMENT_PREFIX):
			return argument.trim_prefix(LOCAL_TEST_ARGUMENT_PREFIX).to_lower()
	return ""


func _start_local_test(role: String) -> void:
	# The launcher uses the automatic pairing: host exterminator, clients roaches.
	GameState.set_local_role_preference(ROLE_AUTO)
	role_option.select(RoleChoice.AUTO)
	_set_busy(true)
	match role:
		"host":
			get_window().title = "Bug Game — Local Host"
			status_label.text = "Local test: starting ENet host..."
			if not Net.host_local_test():
				_set_busy(false)
		"client":
			get_window().title = "Bug Game — Local Client"
			address_field.text = "127.0.0.1"
			status_label.text = "Local test: joining 127.0.0.1..."
			if not Net.join_local_test():
				_set_busy(false)
		_:
			push_warning("Unknown local test role: %s" % role)
			status_label.text = "Unknown local test role: %s" % role
			_set_busy(false)


func _on_host_pressed() -> void:
	if _game_scene == null or _connecting:
		return
	_connecting = true
	_store_role_preference()
	_set_busy(true)
	status_label.text = "Starting host..."
	if SteamManager.available:
		_hosting_lobby = true
		SteamManager.create_lobby(Net.MAX_PLAYERS)
	elif not Net.host_game():
		_set_busy(false)


func _on_lobby_ready(_lobby_id: int) -> void:
	if not _hosting_lobby:
		return
	_hosting_lobby = false
	if not Net.host_game():
		_set_busy(false)


func _on_invite_requested(lobby_id: int) -> void:
	if lobby_id <= 0 or _connecting or not _local_test_role.is_empty():
		return
	_pending_lobby_id = lobby_id
	if _game_scene != null:
		_join_pending_lobby()


func _join_pending_lobby() -> void:
	var lobby_id := _pending_lobby_id
	_pending_lobby_id = 0
	_connecting = true
	_store_role_preference()
	_set_busy(true)
	status_label.text = "Joining Steam lobby..."
	SteamManager.join_lobby(lobby_id)


func _on_lobby_joined(_lobby_id: int) -> void:
	var host_id := SteamManager.get_lobby_host_id()
	if host_id <= 0:
		SteamManager.leave_lobby()
		_on_failed("The lobby has no host. Ask your friend to host again.")
		return
	status_label.text = "Connecting to Steam host..."
	Net.join_game(str(host_id))


func _on_join_pressed() -> void:
	if _game_scene == null or _connecting:
		return
	_connecting = true
	_store_role_preference()
	var address := address_field.text.strip_edges()
	if address.is_empty() and not SteamManager.available:
		address = "127.0.0.1"
	_set_busy(true)
	status_label.text = "Connecting to %s..." % address
	if not Net.join_game(address):
		_set_busy(false)


func _enter_game() -> void:
	if _entering_game or _game_scene == null:
		return
	_entering_game = true
	if not _local_test_role.is_empty():
		print(
			"LOCAL TEST: %s connected as peer %d"
			% [_local_test_role, multiplayer.get_unique_id()]
		)
	var error := get_tree().change_scene_to_packed(_game_scene)
	if error != OK:
		_entering_game = false
		Net.leave()
		_on_failed("Could not open the game: %s" % error_string(error))


func _on_failed(reason: String) -> void:
	_connecting = false
	_hosting_lobby = false
	status_label.text = reason
	_set_busy(_game_scene == null)


func _set_busy(busy: bool) -> void:
	host_button.disabled = busy
	join_button.disabled = busy
	role_option.disabled = busy
	if _solo_test_button != null:
		_solo_test_button.disabled = busy
	if _dev_room_button != null:
		_dev_room_button.disabled = busy


func _on_solo_test_pressed() -> void:
	if not OS.is_debug_build():
		return
	get_tree().change_scene_to_file("res://scenes/game/solo_test.tscn")


func _store_role_preference() -> void:
	match role_option.get_selected_id():
		RoleChoice.EXTERMINATOR:
			GameState.set_local_role_preference(ROLE_EXTERMINATOR)
		RoleChoice.COCKROACH:
			GameState.set_local_role_preference(ROLE_COCKROACH)
		_:
			GameState.set_local_role_preference(ROLE_AUTO)
