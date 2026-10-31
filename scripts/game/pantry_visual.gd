extends Area3D
## A shallow tin pantry and a warm welcome light, with no gameplay collision.
const RoachScale := preload("res://scripts/game/roach_scale.gd")
var _ring: MeshInstance3D
var _pulse := 0.0

func _ready() -> void:
	scale = Vector3.ONE * RoachScale.GEOMETRY
	var tray := %PantryTray as MeshInstance3D
	tray.scale.y = 0.1
	tray.position.y = 0.015
	_ring = %PantryRing as MeshInstance3D
	var marker := _ring.material_override.duplicate() as StandardMaterial3D
	marker.emission_enabled = false
	marker.albedo_color = Color(0.75, 0.60, 0.25)
	_ring.material_override = marker
	_ring.position.y = 0.10
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.34, 0.38, 0.36)
	metal.metallic = 0.8
	metal.roughness = 0.33
	for index: int in 3:
		var edge := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 2.61
		torus.outer_radius = 2.72
		torus.rings = 64
		torus.ring_segments = 8
		edge.mesh = torus
		edge.material_override = metal
		edge.position.y = 0.04 + index * 0.03
		add_child(edge)
	var label := %PantryLabel as Label3D
	label.hide()
	var light := OmniLight3D.new()
	light.position.y = 2.0
	light.light_color = Color(1.0, 0.75, 0.42)
	light.light_energy = 1.0
	light.omni_range = 6.0
	add_child(light)

func celebrate() -> void:
	_pulse = 1.0

func _process(delta: float) -> void:
	_pulse = maxf(_pulse - delta * 1.5, 0.0)
	if _ring != null:
		_ring.scale = Vector3.ONE * (1.0 + sin(_pulse * PI) * 0.08)
