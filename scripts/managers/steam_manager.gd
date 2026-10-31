extends Node
## Optional wrapper around the GodotSteam singleton.
##
## The project must run and be multiplayer-testable BEFORE GodotSteam is
## installed, so nothing here references the `Steam` global by name — that would
## be a parse error on a machine without the extension. It is resolved at
## runtime instead, and every call goes through `Object.call()` for the same
## reason. If the extension is absent, `available` stays false and Net quietly
## uses the ENet transport.

signal lobby_created(new_lobby_id: int)
signal lobby_joined(new_lobby_id: int)
signal lobby_failed(reason: String)
signal invite_requested(target_lobby_id: int)

## Spacewar — Valve's public test AppID. Any Steam client may run it, so it is
## the standard stand-in until we pay Steam Direct and get our own.
const DEV_APP_ID := 480

var available := false
var steam_id := 0
var steam_name := ""
var lobby_id := 0

var _steam = null
var _creating_lobby := false
var _joining_lobby_id := 0

func _ready() -> void:
	if not Engine.has_singleton("Steam"):
		push_warning("GodotSteam not installed. Steam transport disabled; ENet only.")
		return
	_steam = Engine.get_singleton("Steam")

	var result: Dictionary = _steam.call("steamInitEx", false, DEV_APP_ID)
	if int(result.get("status", 1)) != 0:
		push_warning("Steam init failed: %s" % result.get("verbal", "unknown"))
		_steam = null
		return

	available = true
	steam_id = _steam.call("getSteamID")
	steam_name = _steam.call("getPersonaName")

	_steam.connect("lobby_created", _on_lobby_created)
	_steam.connect("lobby_joined", _on_lobby_joined)
	_steam.connect("join_requested", _on_join_requested)
	print("Steam ready: %s (%s)" % [steam_name, steam_id])


func _process(_delta: float) -> void:
	# Steamworks is callback-driven; it needs pumping every frame.
	if _steam != null:
		_steam.call("run_callbacks")


## Opens a friends-only lobby. Emits lobby_created on success.
func create_lobby(max_players: int) -> void:
	if not available:
		lobby_failed.emit("Steam unavailable")
		return
	if _creating_lobby or _joining_lobby_id != 0:
		return
	_creating_lobby = true
	# 1 == LOBBY_TYPE_FRIENDS_ONLY
	_steam.call("createLobby", 1, max_players)


func join_lobby(target_lobby_id: int) -> void:
	if not available:
		lobby_failed.emit("Steam unavailable")
		return
	if target_lobby_id <= 0:
		lobby_failed.emit("Invalid Steam lobby")
		return
	if _creating_lobby or _joining_lobby_id != 0:
		return
	_joining_lobby_id = target_lobby_id
	_steam.call("joinLobby", target_lobby_id)


func leave_lobby() -> void:
	_creating_lobby = false
	_joining_lobby_id = 0
	if available and lobby_id != 0:
		_steam.call("leaveLobby", lobby_id)
	lobby_id = 0


## Pops the Steam overlay so the host can invite friends directly.
func open_invite_overlay() -> void:
	if available and lobby_id != 0:
		_steam.call("activateGameOverlayInviteDialog", lobby_id)


func _on_lobby_created(connect_result: int, new_lobby_id: int) -> void:
	if not _creating_lobby:
		_leave_stale_lobby(connect_result, new_lobby_id)
		return
	_creating_lobby = false
	if connect_result != 1:
		lobby_failed.emit("Could not create lobby (code %d)" % connect_result)
		return
	lobby_id = new_lobby_id
	# The owner's Steam ID is how joining peers find us — ENet uses an IP here.
	_steam.call("setLobbyData", lobby_id, "host_steam_id", str(steam_id))
	lobby_created.emit(lobby_id)


func _on_lobby_joined(new_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	# Steam also emits lobby_joined when creating our own lobby. Only a matching
	# explicit join should dial another host; ignore duplicates and cancelled work.
	if new_lobby_id != _joining_lobby_id or _joining_lobby_id == 0:
		if not _creating_lobby:
			_leave_stale_lobby(response, new_lobby_id)
		return
	_joining_lobby_id = 0
	if response != 1:
		lobby_failed.emit("Could not join lobby (code %d)" % response)
		return
	lobby_id = new_lobby_id
	lobby_joined.emit(lobby_id)


## Fired when a friend accepts an invite from the Steam overlay.
func _on_join_requested(target_lobby_id: int, _friend_id: int) -> void:
	# The menu prepares assets before joining. An invite must not replace the
	# active lobby underneath an already-running game scene.
	invite_requested.emit(target_lobby_id)


func _leave_stale_lobby(result: int, stale_id: int) -> void:
	if available and result == 1 and stale_id != 0 and stale_id != lobby_id:
		_steam.call("leaveLobby", stale_id)


## Steam ID of whoever owns the current lobby — the peer we dial into.
func get_lobby_host_id() -> int:
	if not available or lobby_id == 0:
		return 0
	return int(_steam.call("getLobbyData", lobby_id, "host_steam_id"))
