extends Node
## Presentation and owner movement consequences of a host-owned combat snapshot.
var health := 100
var ghost := false
var ghost_left := 0.0
var _last_respawn := -1
var _last_hit := -1
var _flash_left := 0.0
var _materials: Dictionary = {}
var _ghost_material: StandardMaterial3D
var _label: Label
var _hurt: ColorRect
@onready var token: CharacterBody3D = get_parent()

func _ready() -> void:
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_material.albedo_color = Color(0.30, 0.88, 1.0, 0.32)
	_ghost_material.emission_enabled = true
	_ghost_material.emission = Color(0.13, 0.6, 0.9)
	for node: Node in token.cockroach_model.find_children("*", "MeshInstance3D", true, false):
		_materials[node] = node.material_override
	if token.is_multiplayer_authority() and DisplayServer.get_name() != "headless":
		var canvas := CanvasLayer.new()
		token.add_child(canvas)
		_hurt = ColorRect.new()
		_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		canvas.add_child(_hurt)
		_hurt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_label = Label.new()
		canvas.add_child(_label)
		_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_label.offset_left = -275
		_label.offset_top = 85
		_label.offset_right = -25
		_label.offset_bottom = 140
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_label.add_theme_font_size_override("font_size", 18)

func apply_state(state: Dictionary) -> void:
	health = int(state.health)
	ghost_left = float(state.ghost_left)
	var is_roach: bool = token.player_role == "cockroach"
	var next_ghost := is_roach and health <= 0
	if next_ghost != ghost:
		ghost = next_ghost
		for mesh: MeshInstance3D in _materials:
			mesh.material_override = _ghost_material if ghost else _materials[mesh]
	var serial := int(state.respawn_serial)
	if serial != _last_respawn:
		if serial > 0 and token.is_multiplayer_authority():
			token.respawn_from_combat(state.respawn_position)
		_last_respawn = serial
	var hit := int(state.hit_serial)
	if hit != _last_hit:
		if _last_hit >= 0 and is_roach: _flash_left = 0.3
		_last_hit = hit

func _process(delta: float) -> void:
	_flash_left = maxf(0, _flash_left - delta)
	if _label == null: return
	_label.visible = token.player_role == "cockroach"
	_label.text = "GHOST ROACH · %ds\nRespawning automatically" % ceili(ghost_left) if ghost else "HEALTH  %d / 100" % health
	_label.modulate = Color(0.4, 0.9, 1.0) if ghost else Color(1, 0.8, 0.5) if health < 50 else Color.WHITE
	_hurt.color = Color(0.7, 0.12, 0.08, _flash_left * 0.6)
