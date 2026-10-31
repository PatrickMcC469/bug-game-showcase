extends Node3D
## Cosmetic cockroach rig: generated UV shells, annulated appendages and
## two-bone leg IK. Motion is observed locally on every peer; this script never
## reads input, owns a camera, moves a player, or publishes network state.

@export_range(0.05, 0.3) var leg_swing := 0.23
@export var leg_lift := 0.095
@export var body_bob := 0.012
@export var body_bank := 0.105
@export var body_pitch := 0.045
@export var response_speed := 13.0

@onready var shell_accent: MeshInstance3D = %ShellAccent
@onready var body_root: Node3D = %BodyRoot
@onready var antenna_left: Node3D = %AntennaLeft
@onready var antenna_right: Node3D = %AntennaRight
@onready var antenna_left_mid: Node3D = $BodyRoot/AntennaLeft/Joint1
@onready var antenna_left_tip: Node3D = $BodyRoot/AntennaLeft/Joint1/Joint2
@onready var antenna_right_mid: Node3D = $BodyRoot/AntennaRight/Joint1
@onready var antenna_right_tip: Node3D = $BodyRoot/AntennaRight/Joint1/Joint2
@onready var elytron_left: MeshInstance3D = $BodyRoot/ElytronLeft
@onready var elytron_right: MeshInstance3D = $BodyRoot/ElytronRight
@onready var head: MeshInstance3D = $BodyRoot/Head
@onready var cercus_left: Node3D = $BodyRoot/CercusLeft
@onready var cercus_right: Node3D = $BodyRoot/CercusRight

var motion_speed := 0.0
var is_dashing := false
var _activity := 0.0
var _cycle := 0.0
var _elapsed := 0.0
var _turn_rate := 0.0
var _last_facing_yaw := 0.0
var _body_rest_position := Vector3.ZERO
var _body_rest_rotation := Vector3.ZERO
var _antenna_left_rest := Vector3.ZERO
var _antenna_right_rest := Vector3.ZERO
var _antenna_joint_rest_yaws: PackedFloat32Array = []
var _elytron_left_rest := Vector3.ZERO
var _elytron_right_rest := Vector3.ZERO
var _head_rest_yaw := 0.0
var _cercus_left_rest_yaw := 0.0
var _cercus_right_rest_yaw := 0.0
var _legs: Array[Dictionary] = []
var _mouthparts: Array[Dictionary] = []
var _dash_blend := 0.0
var _antenna_materials: Array[ShaderMaterial] = []


func _ready() -> void:
	_body_rest_position = body_root.position
	_body_rest_rotation = body_root.rotation
	_antenna_left_rest = antenna_left.rotation
	_antenna_right_rest = antenna_right.rotation
	_antenna_joint_rest_yaws = PackedFloat32Array([
		antenna_left_mid.rotation.y,
		antenna_left_tip.rotation.y,
		antenna_right_mid.rotation.y,
		antenna_right_tip.rotation.y,
	])
	_elytron_left_rest = elytron_left.rotation
	_elytron_right_rest = elytron_right.rotation
	_head_rest_yaw = head.rotation.y
	_cercus_left_rest_yaw = cercus_left.rotation.y
	_cercus_right_rest_yaw = cercus_right.rotation.y
	_last_facing_yaw = rotation.y
	for antenna: Node3D in [antenna_left, antenna_right]:
		var mesh := antenna.get_node("Segment1") as MeshInstance3D
		# Each avatar has its own flex clock; shared resource mutation would make
		# every peer's antenna follow whichever avatar was processed last.
		var material := mesh.material_override.duplicate() as ShaderMaterial
		mesh.material_override = material
		_antenna_materials.append(material)

	var leg_names: Array[String] = [
		"LegLeftFront", "LegRightFront", "LegLeftMiddle",
		"LegRightMiddle", "LegLeftRear", "LegRightRear",
	]
	for index: int in leg_names.size():
		var leg := get_node(leg_names[index]) as Node3D
		var femur := leg.get_node("Femur") as Node3D
		var tibia := femur.get_node("Tibia") as Node3D
		var tarsus := tibia.get_node("Tarsus") as Node3D
		_legs.append({
			"hip": leg,
			"femur": femur,
			"tibia": tibia,
			"tarsus": tarsus,
			"side": -1.0 if "Left" in leg_names[index] else 1.0,
			"phase": 0.0 if index in [0, 3, 4] else PI,
			"rest_foot": leg.position + Basis(Vector3.UP, leg.rotation.y) * Vector3(
				(-1.0 if "Left" in leg_names[index] else 1.0) * 0.85,
				0.035 - leg.position.y, 0.0),
		})

	for part_name: String in ["MandibleLeft", "MandibleRight", "PalpLeft", "PalpRight"]:
		var part := body_root.get_node(part_name) as Node3D
		_mouthparts.append({"node": part, "rest": part.rotation})


func _process(delta: float) -> void:
	if delta <= 0.0:
		return

	_elapsed += delta
	for index: int in _antenna_materials.size():
		_antenna_materials[index].set_shader_parameter("antenna_phase", _elapsed + index * 1.7)
	var yaw_delta := wrapf(rotation.y - _last_facing_yaw, -PI, PI)
	var observed_turn_rate := clampf(yaw_delta / delta, -8.0, 8.0)
	_turn_rate = lerpf(_turn_rate, observed_turn_rate, 1.0 - exp(-18.0 * delta))
	_last_facing_yaw = rotation.y
	var target_activity := clampf(motion_speed / 5.5, 0.0, 1.65)
	var response := 1.0 - exp(-response_speed * delta)
	_activity = lerpf(_activity, target_activity, response)
	var movement_blend := clampf(_activity, 0.0, 1.0)
	# Advance by observed travel so slow movement does not run a full-speed gait.
	_cycle += delta * maxf(_activity * 5.5, 0.0) / (maxf(leg_swing, 0.05) * 2.0) * PI
	for leg_data: Dictionary in _legs:
		_pose_leg(leg_data, movement_blend)

	_dash_blend = lerpf(_dash_blend, 1.0 if is_dashing else 0.0, response)
	var dash_crouch := 0.026 * _dash_blend
	var gait_bob := absf(sin(_cycle * 2.0)) * body_bob * movement_blend
	body_root.position.y = lerpf(
		body_root.position.y,
		_body_rest_position.y + gait_bob - dash_crouch + sin(_elapsed * 1.9) * 0.0008 * (1.0 - movement_blend),
		response,
	)
	body_root.rotation.x = lerpf(
		body_root.rotation.x,
		_body_rest_rotation.x - body_pitch * clampf(_activity, 0.0, 1.0),
		response,
	)
	body_root.rotation.z = lerpf(
		body_root.rotation.z,
		_body_rest_rotation.z + clampf(_turn_rate * 0.018, -body_bank, body_bank),
		response,
	)

	# Separate probing envelopes include pauses between scans. Continuous matched
	# sine waves made the feelers look motorized, especially on an idle roach.
	var left_probe := pow(0.5 + 0.5 * sin(_elapsed * 1.07), 4.0)
	var right_probe := pow(0.5 + 0.5 * sin(_elapsed * 0.83 + 2.1), 4.0)
	var probe_gain := 1.0 - movement_blend * 0.55
	antenna_left.rotation.y = _antenna_left_rest.y \
		+ sin(_elapsed * 2.7) * (0.035 + left_probe * 0.22) * probe_gain - _activity * 0.026 - _turn_rate * 0.004
	antenna_right.rotation.y = _antenna_right_rest.y \
		- sin(_elapsed * 2.3 + 0.8) * (0.035 + right_probe * 0.23) * probe_gain + _activity * 0.026 - _turn_rate * 0.004
	antenna_left.rotation.x = _antenna_left_rest.x + sin(_elapsed * 2.1) * 0.018 - left_probe * 0.055 * probe_gain
	antenna_right.rotation.x = _antenna_right_rest.x + sin(_elapsed * 1.9 + 1.4) * 0.018 - right_probe * 0.055 * probe_gain
	antenna_left_mid.rotation.y = _antenna_joint_rest_yaws[0] \
		+ sin(_elapsed * 2.7 - 0.5) * (0.035 + left_probe * 0.075) - _turn_rate * 0.002
	antenna_left_tip.rotation.y = _antenna_joint_rest_yaws[1] \
		+ sin(_elapsed * 2.7 - 1.1) * (0.025 + left_probe * 0.055) - _turn_rate * 0.001
	antenna_right_mid.rotation.y = _antenna_joint_rest_yaws[2] \
		- sin(_elapsed * 2.3 + 0.3) * (0.035 + right_probe * 0.075) - _turn_rate * 0.002
	antenna_right_tip.rotation.y = _antenna_joint_rest_yaws[3] \
		- sin(_elapsed * 2.3 - 0.3) * (0.025 + right_probe * 0.055) - _turn_rate * 0.001

	# Small mouthpart exploration at rest; head stays seated under its shield.
	for index: int in _mouthparts.size():
		var part := _mouthparts[index]["node"] as Node3D
		var rest: Vector3 = _mouthparts[index]["rest"]
		part.rotation = rest + Vector3(0.0, sin(_elapsed * 4.2 + index) * 0.055 * (1.0 - movement_blend), 0.0)
	head.rotation.y = _head_rest_yaw + sin(_cycle) * 0.01 * movement_blend
	cercus_left.rotation.y = _cercus_left_rest_yaw + sin(_elapsed * 3.2) * 0.022
	cercus_right.rotation.y = _cercus_right_rest_yaw - sin(_elapsed * 2.9 + 0.5) * 0.022
	var shell_flex := sin(_cycle * 2.0) * 0.008 * movement_blend
	elytron_left.rotation.z = _elytron_left_rest.z - shell_flex
	elytron_right.rotation.z = _elytron_right_rest.z + shell_flex


func _pose_leg(leg_data: Dictionary, movement_blend: float) -> void:
	var hip := leg_data["hip"] as Node3D
	var femur := leg_data["femur"] as Node3D
	var tibia := leg_data["tibia"] as Node3D
	var tarsus := leg_data["tarsus"] as Node3D
	var side: float = leg_data["side"]
	var phase := fposmod(_cycle + float(leg_data["phase"]), TAU) / TAU
	var swing := phase < 0.5
	var progress := phase * 2.0 if swing else (phase - 0.5) * 2.0
	var foot: Vector3 = leg_data["rest_foot"]
	# Swing travels forward above the ground; stance sweeps backward at ground
	# level. Opposite tripods share timing, but both sides travel the same way.
	var sweep := lerpf(leg_swing, -leg_swing, smoothstep(0.0, 1.0, progress)) if swing else lerpf(-leg_swing, leg_swing, progress)
	foot.z += sweep * movement_blend
	foot.y += sin(progress * PI) * leg_lift * movement_blend if swing else 0.0
	foot.z += clampf(_turn_rate * side * 0.012, -0.07, 0.07) * movement_blend
	var offset := foot - hip.position
	hip.rotation.y = atan2(-offset.z * side, offset.x * side)
	var ankle_x := Vector2(offset.x, offset.z).length() - absf(femur.position.x) - 0.31
	var distance := clampf(Vector2(ankle_x, offset.y).length(), 0.061, 0.699)
	var knee := -acos(clampf((distance * distance - 0.32 * 0.32 - 0.38 * 0.38) / (2.0 * 0.32 * 0.38), -1.0, 1.0))
	var upper := atan2(offset.y, ankle_x) - atan2(0.38 * sin(knee), 0.32 + 0.38 * cos(knee))
	femur.rotation.z = side * upper
	tibia.rotation.z = side * knee
	tarsus.rotation.z = -side * (upper + knee)


func set_peer_color(color: Color) -> void:
	# Peer identity remains a natural variation in the dorsal chitin instead of
	# an emissive game marker. Duplicate materials so one player's tint cannot
	# mutate the shared scene resource used by every other player.
	var tint := color.darkened(0.62)
	for shell: MeshInstance3D in [shell_accent, elytron_left, elytron_right]:
		var material := shell.material_override.duplicate() as Material
		if material is ShaderMaterial:
			var shader_material := material as ShaderMaterial
			var base: Color = shader_material.get_shader_parameter("base_color")
			var secondary: Color = shader_material.get_shader_parameter("secondary_color")
			shader_material.set_shader_parameter("base_color", base.lerp(tint, 0.08))
			shader_material.set_shader_parameter(
				"secondary_color", secondary.lerp(tint, 0.06)
			)
		else:
			var standard_material := material as StandardMaterial3D
			standard_material.albedo_color = standard_material.albedo_color.lerp(tint, 0.12)
			standard_material.emission_enabled = false
		shell.material_override = material
