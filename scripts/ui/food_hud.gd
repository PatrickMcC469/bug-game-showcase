extends Control
## Food-specific prompts and feedback. Queries public match APIs; never scores.
const Catalog := preload("res://scripts/game/food_catalog.gd")
var _world: Node
var _run: Node
var _stack_label: Label
var _load_label: Label
var _stability_label: Label
var _prompt: Label
var _compass: Label
var _toast: Label
var _help: Label
var _result: Label
var _stress_bar: ProgressBar
var _unload_bar: ProgressBar
var _quota_bar: ProgressBar
var _stack_panel: PanelContainer
var _toast_left := 0.0
var _refresh_left := 0.0
var _stack_on_right := false

func setup(world: Node, run: Node) -> void:
	_world = world
	_run = run
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	run.feedback.connect(_on_feedback)
	resized.connect(_layout_hud)
	_layout_hud()

func _panel(at: Vector2, dimensions: Vector2, anchor: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	panel.anchor_left = anchor.x
	panel.anchor_right = anchor.x
	panel.anchor_top = anchor.y
	panel.anchor_bottom = anchor.y
	panel.offset_left = at.x
	panel.offset_top = at.y
	panel.offset_right = at.x + dimensions.x
	panel.offset_bottom = at.y + dimensions.y
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.07, 0.065, 0.92)
	style.border_color = Color(0.60, 0.53, 0.33, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _text(parent: Node, size_value: int, color: Color = Color(0.94, 0.93, 0.85)) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size_value)
	label.modulate = color
	parent.add_child(label)
	return label

func _bar(parent: Node, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0.0, 7.0)
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.17, 0.15)
	bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	return bar

func _build() -> void:
	_stack_panel = _panel(Vector2(22.0, -215.0), Vector2(250.0, 165.0), Vector2(0.0, 1.0))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	_stack_panel.add_child(column)
	_text(column, 16, Color(0.79, 0.67, 0.4)).text = "CARRIED FOOD  /  1 SLOT"
	_stack_label = _text(column, 18)
	_load_label = _text(column, 16, Color(0.78, 0.81, 0.75))
	_stability_label = _text(column, 16, Color(0.70, 0.78, 0.68))
	_stress_bar = _bar(column, Color(0.95, 0.57, 0.22))
	var center := VBoxContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.anchor_left = 0.5
	center.anchor_right = 0.5
	center.anchor_top = 1.0
	center.anchor_bottom = 1.0
	center.offset_left = -300.0
	center.offset_right = 300.0
	center.offset_top = -110.0
	center.offset_bottom = -40.0
	_prompt = _text(center, 18)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_unload_bar = _bar(center, Color(0.63, 0.82, 0.48))
	_unload_bar.visible = false
	_compass = _text(self, 16, Color(0.84, 0.77, 0.56))
	_compass.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_compass.position.y = 106.0
	_help = _text(self, 16, Color(0.92, 0.94, 0.90))
	_help.text = "E grab / catch   ·   Q drop   ·   R toss   ·   RMB aim   ·   F squeeze fry   ·   Shift sprint   ·   Space dash   ·   C climb / let go   ·   G cart   ·   Esc mouse"
	_help.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var help_background := StyleBoxFlat.new()
	help_background.bg_color = Color(0.055, 0.07, 0.065, 0.92)
	help_background.set_content_margin_all(8)
	_help.add_theme_stylebox_override("normal", help_background)
	_toast = _text(self, 20, Color(1.0, 0.82, 0.43))
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.position.y = 145.0
	var quota_container := Control.new()
	quota_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(quota_container)
	quota_container.anchor_left = 0.5
	quota_container.anchor_right = 0.5
	quota_container.offset_left = -172.0
	quota_container.offset_right = 172.0
	quota_container.offset_top = 93.0
	quota_container.offset_bottom = 99.0
	_quota_bar = _bar(quota_container, Color(0.75, 0.68, 0.40))
	_quota_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result = _text(self, 28)
	var result_background := StyleBoxFlat.new()
	result_background.bg_color = Color(0.055, 0.07, 0.065)
	result_background.set_content_margin_all(16)
	_result.add_theme_stylebox_override("normal", result_background)
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

func _process(delta: float) -> void:
	if _run == null:
		return
	_toast_left = maxf(_toast_left - delta, 0.0)
	_toast.modulate.a = minf(_toast_left * 2.0, 1.0)
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = 0.06
	var peer_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0
	var is_roach: bool = _world.get_role_for_peer(peer_id) == "cockroach"
	_refresh_help()
	var ids: Array = _run.get_cargo_ids(peer_id)
	var foods: Array = _run.get_food_records()
	var lines: Array[String] = []
	var value := 0
	for index: int in 1:
		if index < ids.size():
			var food := Catalog.info(foods[ids[index]]["kind"])
			value += int(food["value"])
			lines.append("%d   %s   +%d" % [index + 1, food["short"], food["value"]])
		else:
			lines.append("%d   —" % (index + 1))
	_stack_label.text = "\n".join(lines)
	var weight: float = _run.get_cargo_weight(peer_id)
	var stress: float = _run.get_stress(peer_id)
	_load_label.text = "%d servings aboard  ·  %d%% pace" % [value, roundi(Catalog.speed_scale(weight) * 100.0)]
	_stress_bar.value = stress
	_stability_label.text = "STEADY" if stress < 0.35 else ("WOBBLY · ease off the corners" if stress < 0.7 else "ABOUT TO SPILL · slow down!")
	_stability_label.modulate = Color(1.0, 0.60, 0.24) if stress > 0.7 else Color(0.78, 0.82, 0.71)
	var phase: int = _world.get_match_phase()
	_stack_panel.visible = is_roach and _world.can_peer_act(peer_id) and phase not in [2, 3]
	_quota_bar.value = float(_world.get_food_delivered()) / maxf(_world.get_food_quota(), 1.0)
	var candidate: int = _run.find_candidate(peer_id)
	_unload_bar.visible = false
	if not _world.can_peer_act(peer_id):
		_prompt.text = "GHOST ROACH · Keep exploring. You will respawn automatically."
	elif not is_roach:
		_prompt.text = "Stop the bugs from returning food."
	elif phase == 0:
		_prompt.text = "Waiting for the food run to begin…"
	elif not ids.is_empty() and _run.is_at_home(peer_id):
		_prompt.text = "STOP TO RETURN  ·  Unloading your food"
		_unload_bar.visible = true
		_unload_bar.value = _run.get_unload_progress(peer_id)
	elif not ids.is_empty() and Input.is_action_pressed("food_aim"):
		_prompt.text = "[R] SEND IT  ·  Green circle = home"
	elif candidate >= 0 and ids.size() < 1:
		var food := Catalog.info(foods[candidate]["kind"])
		_prompt.text = "[E] %s %s  ·  +%d" % ["CATCH" if int(foods[candidate]["state"]) == 2 else "GRAB", food["name"], food["value"]]
	elif stress > 0.7:
		_prompt.text = "STACK'S GOING!  Ease off or drop the top snack."
	elif ids.size() == 3:
		_prompt.text = "ABSOLUTELY REASONABLE HAUL.  Take it home."
	elif not ids.is_empty():
		_prompt.text = "Hold RMB to aim  ·  [R] TOSS  ·  [Q] DROP"
	else:
		_prompt.text = "Search tables, containers and ovens for food."
	if phase == 1 and _world.serving_cart.can_reach_handle(peer_id):
		_prompt.text = "[G] ROLL SERVING CART" if not _world.serving_cart.is_moving() else "CART MOVING · KEEP THE AISLE CLEAR"
	if phase <= 1:
		var stove: String = _world.kitchen_hazards.find_control(peer_id)
		if not stove.is_empty():
			_prompt.text = "[H] TURN %s STOVE · Flames and fryer oil kill bugs" % ("OFF" if _world.kitchen_hazards.is_on(stove) else "ON")
		var oven: String = _world.ovens.find_control(peer_id)
		if not oven.is_empty():
			var state: Dictionary = _world.ovens.get_state(oven)
			var oven_prompt: String
			if is_roach:
				oven_prompt = "[K] SHUT OFF OVEN · Heat hurts inside" if state.hot else "OVEN OFF · Safe to explore inside"
			else:
				oven_prompt = "[J] %s OVEN · [K] HEAT %s%s" % ["CLOSE" if state.open else "OPEN", "OFF" if state.hot else "ON", " · DOOR BLOCKED" if state.blocked else ""]
			_prompt.text = _prompt.text + "\n" + oven_prompt if not stove.is_empty() else oven_prompt
		var storage_id: String = _world.storage.find_control(peer_id)
		if not storage_id.is_empty():
			var storage_state: Dictionary = _world.storage.get_state(storage_id)
			_prompt.text = "[B] %s %s%s" % ["CLOSE" if storage_state.open else "OPEN", _world.storage.get_display_name(storage_id).to_upper(), " · BLOCKED — CLEAR THE DOOR" if storage_state.blocked else ""]
		if _world.gas_weapon.can_dock(peer_id): _prompt.text = _world.gas_weapon.dock_prompt(peer_id)
		if _world.gas_weapon.can_dock(peer_id) and not _world.gas_weapon.is_selected(peer_id):
			_prompt.text += " · " + _world.shotgun_ammo.prompt(peer_id)
	if _world.get("food_carry") != null and phase == 1 and is_roach:
		var carried: Dictionary = _world.food_carry.held(peer_id)
		var effect: Dictionary = _world.food_carry.status(peer_id)
		if not carried.is_empty():
			var profile: Resource = load("res://assets/food/" + str(carried.type) + ".tres")
			_stack_label.text = profile.display_name
			_load_label.text = "2 servings · Q drops food"
			_stability_label.text = "Cold %.1f / 15s" % effect.get("cold", 0.0) if carried.type == "frozen_food" else ("F squeezes grease · %.1fs" % effect.get("grease", 0.0) if carried.type == "french_fry" else profile.effect_description)
			_stability_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_stress_bar.value = float(effect.get("cold", 0.0)) / 15.0
			_prompt.text = "[Q] DROP · [F] SQUEEZE GREASE" if carried.type == "french_fry" else "[Q] DROP FOOD"
			if _run.is_at_home(peer_id): _prompt.text = "STOP TO RETURN · Unloading food"
		elif _world.food_carry.candidate(peer_id) >= 0:
			_prompt.text = "[E] PICK UP FOOD"
		if float(effect.get("frozen", 0.0)) > 0:
			_prompt.text = "FROZEN · Thawing %.1fs" % effect.frozen
			_stability_label.text = "Food dropped. Wait to thaw before picking it up."
	_prompt.modulate = Color(1.0, 0.55, 0.25) if stress > 0.7 else Color(0.94, 0.93, 0.85)
	_result.visible = phase in [2, 3]
	if _result.visible:
		var stats: Dictionary = _run.get_stats()
		_result.text = ("FOOD RETURNED!" if phase == 2 else "DINNER CANCELLED.") + "\n%d servings · %d air mails · %d catches · %d spills" % [_world.get_food_delivered(), stats["airmail"], stats["catches"], stats["spills"]]
		_result.position = (size - _result.size) * 0.5
		_prompt.text = "Leave to plan the next raid."
	var token := _world.players.get_node_or_null(str(peer_id)) as Node3D
	if token != null:
		var home: Area3D = _world.home_returns.nearest(token.global_position)
		if home == null:
			_compass.text = "NO RETURN POINTS"
			return
		var to_home: Vector3 = home.global_position - token.global_position
		var relative: Vector3 = token.camera_rig.global_basis.inverse() * to_home
		var bearing := "AHEAD" if relative.z < -absf(relative.x) else ("BEHIND" if relative.z > absf(relative.x) else ("LEFT" if relative.x < 0.0 else "RIGHT"))
		_compass.text = "%s · %s · %dm" % [home.display_name.to_upper(), bearing, roundi(Vector2(to_home.x, to_home.z).length())]
		var alternate: Area3D
		for point: Area3D in _world.home_returns.points:
			if point != home and (alternate == null or token.global_position.distance_squared_to(point.global_position) < token.global_position.distance_squared_to(alternate.global_position)): alternate = point
		if alternate != null:
			var offset: Vector3 = alternate.global_position - token.global_position
			var direction: Vector3 = token.camera_rig.global_basis.inverse() * offset
			var heading := "AHEAD" if direction.z < -absf(direction.x) else ("BEHIND" if direction.z > absf(direction.x) else ("LEFT" if direction.x < 0 else "RIGHT"))
			_compass.text += "   |   %s · %s · %dm" % [alternate.display_name.to_upper(), heading, roundi(Vector2(offset.x, offset.z).length())]
		_compass.position.x = (size.x - _compass.size.x) * 0.5
	_toast.position.x = (size.x - _toast.size.x) * 0.5

func _on_feedback(message: String, kind: String, at: Vector3) -> void:
	var peer_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0
	var local := _world.players.get_node_or_null(str(peer_id)) as Node3D
	if kind in ["grab", "drop", "throw"] and local != null and local.global_position.distance_to(at) > 6.0:
		return
	_toast.text = message
	_toast_left = 3.1


func set_stack_on_right(enabled: bool) -> void:
	_stack_on_right = enabled
	_layout_hud()


func _layout_hud() -> void:
	if _stack_panel == null:
		return
	var compact := size.x < 1000.0
	_stack_panel.anchor_top = 0.0 if compact else 1.0
	_stack_panel.anchor_bottom = _stack_panel.anchor_top
	_stack_panel.anchor_left = 1.0 if _stack_on_right else 0.0
	_stack_panel.anchor_right = _stack_panel.anchor_left
	_stack_panel.offset_left = -346.0 if _stack_on_right else 18.0
	_stack_panel.offset_right = -18.0 if _stack_on_right else 346.0
	_stack_panel.offset_top = 146.0 if compact else -300.0
	_stack_panel.offset_bottom = 366.0 if compact else -80.0
	_stack_label.add_theme_font_size_override("font_size", 18)
	(_stack_panel.get_child(0) as VBoxContainer).add_theme_constant_override("separation", 4 if compact else 8)
	_result.add_theme_font_size_override("font_size", 20 if compact else 28)
	var prompt_column := _prompt.get_parent() as VBoxContainer
	prompt_column.offset_top = -156.0
	prompt_column.offset_bottom = -80.0
	_help.anchor_left = 0.0
	_help.anchor_right = 1.0
	_help.offset_left = 18.0
	_help.offset_right = -18.0
	_help.offset_top = -68.0
	_help.offset_bottom = -12.0
	_toast.position.y = 126.0 if compact else 145.0
	_toast.add_theme_font_size_override("font_size", 16 if compact else 20)
	_refresh_help()

func _refresh_help() -> void:
	if _world == null or _help == null: return
	var peer_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0
	if not _world.can_peer_act(peer_id):
		_help.text = "WASD move   ·   Shift sprint   ·   Space dash   ·   C climb / let go   ·   Esc mouse"
	elif _world.get_role_for_peer(peer_id) == "exterminator":
		_help.text = "WASD move · LMB fire · T swap / R reload at truck · G cart · Esc mouse"
	else:
		_help.text = "E grab · Q drop · R toss · RMB aim · F fry grease   |   Shift sprint · Space dash · C climb / let go · G cart" if size.x<1000 else "E grab / catch   ·   Q drop   ·   R toss   ·   RMB aim   ·   F squeeze fry   ·   Shift sprint   ·   Space dash   ·   C climb / let go   ·   G cart   ·   Esc mouse"
