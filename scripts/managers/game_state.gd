extends Node
## Who is in the session. Deliberately tiny — this is a session roster, not a
## dumping ground. Gameplay rules live in scripts/game/, not here.
##
## Autoloads outlive every scene, so anything parked here leaks between matches.
## If you're tempted to add a field, ask whether it belongs on a game scene first.

signal roster_changed()

const ROLE_COCKROACH := "cockroach"
const ROLE_EXTERMINATOR := "exterminator"

var players: Dictionary[int, Dictionary] = {}
var _local_role_preference := ""


func set_local_role_preference(role: String) -> void:
	_local_role_preference = (
		role if role == ROLE_COCKROACH or role == ROLE_EXTERMINATOR else ""
	)


func get_local_role_preference() -> String:
	return _local_role_preference


func register_player(peer_id: int) -> void:
	if players.has(peer_id):
		return
	players[peer_id] = {"id": peer_id, "name": "Player %d" % peer_id}
	roster_changed.emit()


func unregister_player(peer_id: int) -> void:
	if players.erase(peer_id):
		roster_changed.emit()


func clear() -> void:
	players.clear()
	_local_role_preference = ""
	roster_changed.emit()


func player_count() -> int:
	return players.size()
