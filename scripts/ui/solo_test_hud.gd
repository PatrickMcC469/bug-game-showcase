extends CanvasLayer
## A compact developer panel; gameplay presentation stays in the normal HUD.
var _lab: Node
var _panel: PanelContainer
var _status: Label
var _instruction: Label
var _scenario: OptionButton
var _reset: Button
var _clock: Button
var _bot: Button
var _add_time: Button
var _role: Button
var _refresh_left := 0.0


func setup(lab: Node) -> void:
	_lab = lab
	layer = 20
	_panel = PanelContainer.new()
	_panel.position = Vector2(18, 126)
	_panel.custom_minimum_size.x = 372
	_panel.theme = Theme.new()
	_panel.theme.default_font_size = 16
	add_child(_panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.06, 0.065, 0.96)
	style.border_color = Color(0.40, 0.64, 0.59, 0.8)
	style.set_border_width_all(1)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	column.custom_minimum_size.x = 344
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	_label(column, lab.get_lab_title() + "\nF1 hide/show · Esc releases the mouse", 18)
	_scenario = OptionButton.new()
	_scenario.name = "Scenario"
	for title: String in lab.get_scenario_titles():
		_scenario.add_item(title)
	_scenario.add_theme_font_size_override("font_size", 16)
	_scenario.custom_minimum_size.y = 36
	_scenario.item_selected.connect(lab.select_scenario)
	column.add_child(_scenario)
	if lab.has_method("switch_character"):
		_role = _button(column, "Switch character [F2]", lab.switch_character)
		_button(column, "Partner: food / roll cart [F3]", lab.partner_action)
		_button(column, "Defeat bug / test respawn [F4]", lab.defeat_bug)
		_button(column, "Expire round", lab.expire_round)
	_instruction = _label(column, "", 16)
	_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_instruction.custom_minimum_size = Vector2(344, 48)
	_status = _label(column, "Starting scripted opponent…", 16)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(344, 40)
	_status.modulate = Color(0.71, 0.91, 0.8)
	var first_row := HBoxContainer.new()
	column.add_child(first_row)
	_reset = _button(first_row, "Reset [F5]", lab.reset_scenario)
	_clock = _button(first_row, "Clock: held [F6]", lab.toggle_clock)
	_clock.tooltip_text = "Only the round clock stops. Movement, hazards and ghost respawns continue."
	var second_row := HBoxContainer.new()
	column.add_child(second_row)
	_bot = _button(second_row, "Pause bot [F7]", lab.toggle_bot)
	_bot.tooltip_text = "Pause scripted walking or the shot countdown. Existing physics and ghost respawns continue."
	_add_time = _button(second_row, "+30 seconds [F8]", lab.add_time)
	_button(column, "Return to menu", lab.leave_lab)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _label(parent: Node, words: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = words
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _button(parent: Node, words: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = words
	button.custom_minimum_size = Vector2(164, 36)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _layout() -> void:
	_panel.position.y = 126 if get_viewport().get_visible_rect().size.y >= 600 else 12
	_panel.size = Vector2(388, minf(640, get_viewport().get_visible_rect().size.y - _panel.position.y - 180))


func toggle_panel() -> void:
	_panel.visible = not _panel.visible


func _process(delta: float) -> void:
	if _lab == null:
		return
	_refresh_left -= delta
	if _refresh_left > 0:
		return
	_refresh_left = 0.1
	_status.text = _lab.get_status()
	_scenario.select(_lab.scenario)
	_scenario.disabled = not _lab.session_ready
	_instruction.text = _lab.get_instruction()
	if _role != null:
		_role.disabled = not _lab.session_ready
		_role.text = "Play as %s [F2]" % ("exterminator" if _lab.play_as_roach else "cockroach")
	_clock.text = "Run clock [F6]" if _lab.clock_paused else "Hold clock [F6]"
	_bot.text = "Resume bot [F7]" if _lab.bot_paused else "Pause bot [F7]"
	_reset.disabled = not _lab.session_ready and _lab.error_message.is_empty()
	_reset.text = "Retry connection" if not _lab.error_message.is_empty() else "Reset [F5]"
	_clock.disabled = not _lab.session_ready
	_bot.disabled = not _lab.session_ready
	_add_time.disabled = not _lab.session_ready
