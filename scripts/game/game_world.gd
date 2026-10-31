extends Node3D
## Host-authoritative first-playable loop. Player movement remains owned by each
## client, but roles, food possession, banking, the quota, and the clock are
## decided by the host and mirrored to scene-ready peers.

enum MatchPhase {
	WAITING,
	RUNNING,
	ROACHES_WIN,
	EXTERMINATOR_WIN,
}

const ROLE_COCKROACH := "cockroach"
const ROLE_EXTERMINATOR := "exterminator"
const TIMER_SYNC_INTERVAL := 0.25
const DinerLayout := preload("res://scripts/game/diner_layout.gd")
const CombatScript := preload("res://scripts/game/roach_combat.gd")
var combat: Node
var kitchen_hazards: Node
var ovens: Node
var storage: Node
var drains: Node
var gas_weapon: Node
var shotgun_ammo: Node
var food_supply: Node3D
var food_carry: Node3D

@export_file("*.tscn") var menu_scene_path: String = "res://scenes/ui/main_menu.tscn"
@export var player_scene: PackedScene
@export_range(10.0, 600.0, 1.0) var prototype_round_duration := 120.0
@export_range(1, 60, 1) var prototype_food_quota := 16

@onready var food_run: Node = %FoodRun
@onready var serving_cart: AnimatableBody3D = %DinerKitchen.get_node("ServingCart")
@onready var players: Node3D = %Players
var home_base: Area3D # Primary spawn anchor; food delivery queries all map returns.
var home_returns: Node
@onready var food_items: Node3D = %FoodItems
@onready var roster_label: Label = %RosterLabel
@onready var round_label: Label = %RoundLabel
@onready var objective_label: Label = %ObjectiveLabel
@onready var carry_label: Label = %CarryLabel
@onready var invite_button: Button = %InviteButton
@onready var leave_button: Button = %LeaveButton

var _ready_peers: Dictionary[int, bool] = {}
var _roles: Dictionary[int, String] = {}
var _match_phase := MatchPhase.WAITING
var _food_delivered := 0
var _round_time_left := 0.0
var _timer_sync_left := 0.0
var _clock_paused := false
var _match_revision := 0
var _received_match_revision := -1
var _timer_tick := 0
var _last_timer_tick := -1


func _ready() -> void:
	home_returns = preload("res://scripts/game/home_returns.gd").new()
	home_returns.name = "HomeReturns"
	add_child(home_returns)
	home_returns.setup(self)
	if not home_returns.points.is_empty(): home_base = home_returns.points[0]
	# Identical path on every peer before any scene-ready handshake or snapshots.
	combat = CombatScript.new()
	combat.name = "Combat"
	add_child(combat)
	combat.setup(self)
	kitchen_hazards = preload("res://scripts/game/kitchen_hazards.gd").new()
	kitchen_hazards.name = "KitchenHazards"
	add_child(kitchen_hazards)
	kitchen_hazards.setup(self)
	ovens = preload("res://scripts/game/oven_system.gd").new()
	ovens.name = "Ovens"
	add_child(ovens)
	ovens.setup(self)
	storage = preload("res://scripts/game/storage_system.gd").new()
	storage.name = "Storage"
	add_child(storage)
	storage.setup(self)
	gas_weapon = preload("res://scripts/game/gas_weapon.gd").new()
	gas_weapon.name = "GasWeapon"
	add_child(gas_weapon)
	gas_weapon.setup(self)
	shotgun_ammo = preload("res://scripts/game/shotgun_ammo.gd").new()
	shotgun_ammo.name = "ShotgunAmmo"
	add_child(shotgun_ammo)
	shotgun_ammo.setup(self)
	leave_button.pressed.connect(_on_leave_pressed)
	invite_button.pressed.connect(SteamManager.open_invite_overlay)
	invite_button.visible = SteamManager.available and Net.is_host

	GameState.roster_changed.connect(_refresh_roster)
	Net.player_joined.connect(_on_player_joined)
	Net.player_left.connect(_on_player_left)
	Net.host_left.connect(_on_leave_pressed)
	serving_cart.setup(self)
	food_run.setup(self)
	food_supply = preload("res://scripts/game/food_supply.gd").new()
	food_supply.name = "FoodSupply"
	add_child(food_supply)
	food_supply.setup(self)
	food_carry = preload("res://scripts/game/food_carry.gd").new()
	food_carry.name = "FoodCarry"
	add_child(food_carry)
	food_carry.setup(self)
	drains = preload("res://scripts/game/drain_travel.gd").new()
	drains.name = "Drains"
	add_child(drains)
	drains.setup(self)
	%FoodHUD.setup(self, food_run)
	%FoodFeedback.setup(food_run)

	# Only the host spawns and assigns roles. Menu choices are testing overrides;
	# automatic assignment keeps the temporary host-exterminator prototype rule.
	if Net.is_host:
		_ready_peers[1] = true
		_assign_role(1, GameState.get_local_role_preference())
		_spawn_token(1)
		for peer_id in multiplayer.get_peers():
			_assign_role(peer_id)
			_spawn_token(peer_id)
		if _has_ready_cockroach():
			_start_round()
	elif multiplayer.has_multiplayer_peer():
		# MultiplayerSpawner requires the same scene path on both peers. Waiting
		# for this handshake prevents the host from sending spawn packets while a
		# joining client is still changing away from the menu.
		_report_world_ready.rpc_id(1, GameState.get_local_role_preference())
	_refresh_roster()
	_refresh_match_hud()


func _physics_process(delta: float) -> void:
	if not Net.is_host or _match_phase != MatchPhase.RUNNING or _clock_paused:
		return

	_round_time_left = maxf(_round_time_left - delta, 0.0)
	_timer_sync_left -= delta
	if _timer_sync_left <= 0.0:
		_timer_sync_left = TIMER_SYNC_INTERVAL
		_publish_timer()
	if _round_time_left <= 0.0:
		_finish_round(MatchPhase.EXTERMINATOR_WIN)


func _process(_delta: float) -> void:
	_apply_roles_to_tokens()
	_refresh_match_hud()


func _on_player_joined(peer_id: int) -> void:
	if not Net.is_host:
		return
	_assign_role(peer_id)
	_spawn_token(peer_id)
	_publish_snapshot()


func _on_player_left(peer_id: int) -> void:
	_ready_peers.erase(peer_id)
	_roles.erase(peer_id)
	food_run.release_peer(peer_id)
	food_carry.release_peer(peer_id)
	drains.release_peer(peer_id)
	combat.remove_peer(peer_id)
	var token := players.get_node_or_null(str(peer_id))
	# MultiplayerSpawner delivers the host's despawn to clients. Deleting the
	# client copy here races that packet when another player disconnects.
	if token != null and Net.is_host:
		token.queue_free()

	if Net.is_host:
		if not _has_ready_cockroach():
			_reset_to_waiting()
		else:
			_publish_snapshot()


func _assign_role(peer_id: int, requested_role: String = "") -> void:
	if requested_role == ROLE_COCKROACH or requested_role == ROLE_EXTERMINATOR:
		_roles[peer_id] = requested_role
	else:
		_roles[peer_id] = ROLE_EXTERMINATOR if peer_id == 1 else ROLE_COCKROACH


func _spawn_token(peer_id: int) -> void:
	if player_scene == null or players.has_node(str(peer_id)):
		return
	var token := player_scene.instantiate()
	# The node name carries the peer id across the wire, which is how each
	# client works out which token is its own.
	token.name = str(peer_id)
	token.set_multiplayer_authority(peer_id)
	token.position = DinerLayout.point(Vector3(players.get_child_count() * 2.5 - 3.0, 0.8, 0.0))
	players.add_child(token, true)
	combat.register_peer(peer_id, token.position)
	_apply_role_to_token(peer_id)
	# SpawnVisibility defaults to private. Existing scene-ready clients can see
	# this token immediately; a joining client is revealed all tokens when its
	# readiness RPC arrives.
	for ready_peer_id: int in _ready_peers:
		if ready_peer_id != 1:
			token.call("set_spawn_visible_to", ready_peer_id, true)


@rpc("any_peer", "call_remote", "reliable")
func _report_world_ready(requested_role: String = "") -> void:
	if not Net.is_host:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not GameState.players.has(peer_id) or _ready_peers.has(peer_id):
		return
	_assign_role(peer_id, requested_role)
	_ready_peers[peer_id] = true
	for token: Node in players.get_children():
		token.call("set_spawn_visible_to", peer_id, true)

	if _match_phase == MatchPhase.WAITING and _has_ready_cockroach():
		_start_round()
	else:
		# Existing clients also need the joining player's validated role override.
		_publish_snapshot()
	food_run.send_snapshot(peer_id)
	serving_cart.send_snapshot(peer_id)
	combat.publish(peer_id)
	kitchen_hazards.send_snapshot(peer_id)
	ovens.send_snapshot(peer_id)
	storage.send_snapshot(peer_id)
	drains.send_snapshot(peer_id)
	gas_weapon.send_snapshot(peer_id)
	shotgun_ammo.send_snapshot(peer_id)
	food_supply.send_snapshot(peer_id)
	food_carry.send_snapshot(peer_id)


func _has_ready_cockroach() -> bool:
	for peer_id: int in _ready_peers:
		if _roles.get(peer_id, "") == ROLE_COCKROACH:
			return true
	return false


func _start_round() -> void:
	if not _valid_home_layout(): return
	_match_phase = MatchPhase.RUNNING
	_food_delivered = 0
	_round_time_left = prototype_round_duration
	_timer_sync_left = 0.0
	food_run.reset_food()
	serving_cart.reset_cart()
	combat.reset_round()
	kitchen_hazards.reset_hazards()
	ovens.reset_ovens()
	storage.reset_storage()
	drains.reset_round()
	gas_weapon.reset_weapon()
	shotgun_ammo.reset_round()
	food_carry.reset_round()
	food_supply.reset_supply()
	_publish_snapshot()


func _reset_to_waiting() -> void:
	_match_phase = MatchPhase.WAITING
	_food_delivered = 0
	_round_time_left = 0.0
	food_run.reset_food()
	serving_cart.reset_cart()
	combat.reset_round()
	kitchen_hazards.reset_hazards()
	ovens.reset_ovens()
	storage.reset_storage()
	drains.reset_round()
	gas_weapon.reset_weapon()
	shotgun_ammo.reset_round()
	food_carry.reset_round()
	food_supply.reset_supply()
	_publish_snapshot()


func _finish_round(result: MatchPhase) -> void:
	if not Net.is_host or _match_phase != MatchPhase.RUNNING:
		return
	_match_phase = result
	_round_time_left = maxf(_round_time_left, 0.0)
	_publish_snapshot()


func accept_food_delivery(servings: int) -> void:
	if not Net.is_host or _match_phase != MatchPhase.RUNNING or servings <= 0:
		return
	_food_delivered += servings
	if _food_delivered >= prototype_food_quota:
		_finish_round(MatchPhase.ROACHES_WIN)
	else:
		_publish_snapshot()


func get_ready_peer_ids() -> Array:
	return _ready_peers.keys()


func is_peer_ready(peer_id: int) -> bool:
	return _ready_peers.has(peer_id)


func can_peer_act(peer_id: int) -> bool:
	return not combat.is_ghost(peer_id)


func _publish_snapshot() -> void:
	if not Net.is_host:
		return
	_match_revision += 1
	var snapshot := {
		"revision": _match_revision,
		"timer_tick": _timer_tick,
		"phase": _match_phase,
		"roles": _roles.duplicate(),
		"ready_peers": _ready_peers.keys(),
		"food_delivered": _food_delivered,
		"food_quota": prototype_food_quota,
		"time_left": _round_time_left,
		"clock_paused": _clock_paused,
	}
	_receive_match_snapshot(snapshot)
	# A match revision also gates timer packets, so every ready peer must receive
	# it. A targeted snapshot would leave the others rejecting future ticks.
	for peer_id: int in _ready_peers:
		if peer_id != 1:
			_receive_match_snapshot.rpc_id(peer_id, snapshot)


@rpc("authority", "call_remote", "reliable")
func _receive_match_snapshot(snapshot: Dictionary) -> void:
	var revision := int(snapshot.get("revision", -1))
	if revision <= _received_match_revision:
		return
	_received_match_revision = revision
	_last_timer_tick = int(snapshot.get("timer_tick", -1))
	_match_phase = int(snapshot.get("phase", MatchPhase.WAITING)) as MatchPhase
	_food_delivered = int(snapshot.get("food_delivered", 0))
	prototype_food_quota = int(snapshot.get("food_quota", prototype_food_quota))
	_round_time_left = float(snapshot.get("time_left", 0.0))
	_clock_paused = bool(snapshot.get("clock_paused", false))

	_roles.clear()
	var received_roles: Dictionary = snapshot.get("roles", {})
	for peer_id: Variant in received_roles:
		_roles[int(peer_id)] = str(received_roles[peer_id])
	# Clients also query readiness for interaction prompts. Roles alone include
	# connecting peers, so mirror the host's completed scene handshakes explicitly.
	if not Net.is_host:
		_ready_peers.clear()
		for peer_id: int in snapshot.get("ready_peers", []):
			_ready_peers[peer_id] = true

	_apply_roles_to_tokens()
	_refresh_roster()
	_refresh_match_hud()


func _publish_timer() -> void:
	_timer_tick += 1
	_receive_timer(_match_revision, _timer_tick, _round_time_left)
	for peer_id: int in _ready_peers:
		if peer_id != 1:
			_receive_timer.rpc_id(peer_id, _match_revision, _timer_tick, _round_time_left)


@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_timer(revision: int, tick: int, time_left: float) -> void:
	# Reliable phase/reset snapshots and ordered timer packets are independent
	# streams. A timer may update only the exact match state it was sent for.
	if revision != _received_match_revision or tick <= _last_timer_tick:
		return
	if _match_phase != MatchPhase.RUNNING or _clock_paused or not is_finite(time_left) or time_left < 0.0:
		return
	_last_timer_tick = tick
	_round_time_left = time_left
	_refresh_match_hud()


func _apply_roles_to_tokens() -> void:
	for peer_id: int in _roles:
		_apply_role_to_token(peer_id)


func _apply_role_to_token(peer_id: int) -> void:
	var token := players.get_node_or_null(str(peer_id))
	if token != null and token.has_method("configure_role"):
		token.call("configure_role", _roles[peer_id])


func _refresh_roster() -> void:
	var connection_role := "HOST" if Net.is_host else "CLIENT"
	roster_label.text = "%s  ·  %d PLAYER%s" % [connection_role, GameState.players.size(), "" if GameState.players.size() == 1 else "S"]


func _refresh_match_hud() -> void:
	round_label.modulate = Color(1.0, 0.59, 0.32) if _match_phase == MatchPhase.RUNNING and _round_time_left <= 20.0 else Color.WHITE
	objective_label.text = "FOOD RETURNED  %d / %d servings" % [_food_delivered, prototype_food_quota]
	match _match_phase:
		MatchPhase.WAITING:
			round_label.text = "MAP NEEDS VALID RETURN POINTS" if not home_returns.layout_errors().is_empty() else "WAITING FOR A COCKROACH"
		MatchPhase.RUNNING:
			round_label.text = "%s  •  %s" % ["CLOCK HELD" if _clock_paused else "ROUND LIVE", _format_time(_round_time_left)]
		MatchPhase.ROACHES_WIN:
			round_label.text = "COCKROACHES WIN — QUOTA DELIVERED"
		MatchPhase.EXTERMINATOR_WIN:
			round_label.text = "EXTERMINATOR WINS — TIME EXPIRED"

	carry_label.visible = false


func _format_time(seconds_left: float) -> String:
	var whole_seconds := ceili(maxf(seconds_left, 0.0))
	return "%d:%02d" % [floori(float(whole_seconds) / 60.0), whole_seconds % 60]


## Read-only match queries keep tests and future HUD pieces out of controller
## internals while the first-playable rules are still changing quickly.
func get_match_phase() -> int:
	return _match_phase


func get_role_for_peer(peer_id: int) -> String:
	return _roles.get(peer_id, "")


func is_peer_carrying_food(peer_id: int) -> bool:
	return not food_run.get_cargo_ids(peer_id).is_empty() or (food_carry != null and not food_carry.held(peer_id).is_empty())


func get_food_delivered() -> int:
	return _food_delivered


func get_food_quota() -> int:
	return prototype_food_quota


func get_round_time_left() -> float:
	return _round_time_left


func is_round_clock_paused() -> bool:
	return _clock_paused


## Test controls are local host calls, never RPCs. The lab prepares both owners
## while waiting, then starts after the background client acknowledges its reset.
func prepare_solo_round(roles: Dictionary) -> bool:
	if not Net.is_host or not Net.is_solo_test():
		return false
	for peer_id: int in _ready_peers:
		_assign_role(peer_id, str(roles.get(peer_id, _roles.get(peer_id, ""))))
	_apply_roles_to_tokens()
	_clock_paused = true
	_reset_to_waiting()
	return true


func start_solo_round(clock_paused: bool) -> bool:
	if not _valid_home_layout(): return false
	if not Net.is_host or not Net.is_solo_test() or not _has_ready_cockroach():
		return false
	_match_phase = MatchPhase.RUNNING
	_round_time_left = prototype_round_duration
	_timer_sync_left = 0.0
	_clock_paused = clock_paused
	_publish_snapshot()
	return true


func set_solo_clock_paused(paused: bool) -> void:
	if not Net.is_host or not Net.is_solo_test() or _match_phase != MatchPhase.RUNNING:
		return
	_clock_paused = paused
	_publish_snapshot()


func add_solo_time(seconds: float) -> void:
	if not Net.is_host or not Net.is_solo_test() or _match_phase != MatchPhase.RUNNING or not is_finite(seconds):
		return
	_round_time_left = clampf(_round_time_left + seconds, 0.0, 600.0)
	if _round_time_left <= 0.0:
		_finish_round(MatchPhase.EXTERMINATOR_WIN)
	else:
		_publish_snapshot()


func _on_leave_pressed() -> void:
	process_mode = Node.PROCESS_MODE_DISABLED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Net.leave()
	get_tree().change_scene_to_file(menu_scene_path)

func _valid_home_layout() -> bool:
	var errors: Array = home_returns.layout_errors()
	for message: String in errors: push_warning(message)
	return errors.is_empty()
