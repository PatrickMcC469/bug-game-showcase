@tool
extends Node3D
## Static, reusable route. Local +Z is the approach; -Z leads onto the surface.
## Place the origin at floor height, immediately outside the platform edge.
@export_range(0.2, 3.0, 0.01) var height := 1.08:
	set(value):
		height = clampf(value, 0.2, 3.0)
		if is_node_ready(): configure_visuals()
@export var destination_name := "Worktop"
const REACH := 0.16

func _ready() -> void:
	add_to_group("roach_climb_spots")
	configure_visuals()

func configure_visuals() -> void:
	var strip := get_node_or_null("GripStrip") as MeshInstance3D
	if strip == null: return
	strip.mesh = strip.mesh.duplicate()
	(strip.mesh as BoxMesh).size = Vector3(0.038, height, 0.008)
	strip.position = Vector3(0, height * 0.5, 0.04075)
	$TopGripCap.position = Vector3(0, height + 0.004, 0)
	$TopMark.position = Vector3(0, height + 0.002, -0.11)

func route_points(descending: bool = false) -> PackedVector3Array:
	var local := PackedVector3Array([
		Vector3(0, 0.001, 0.12), Vector3(0, 0.055, 0.09),
		Vector3(0, 0.095, 0.045), Vector3(0, height + 0.035, 0.045),
		Vector3(0, height + 0.030, -0.06), Vector3(0, height + 0.01, -0.13),
		Vector3(0, height + 0.001, -0.16)])
	for i: int in local.size(): local[i] = to_global(local[i])
	if descending: local.reverse()
	return local

func route_normals(descending: bool = false) -> PackedVector3Array:
	var normals := PackedVector3Array([Vector3.UP, Vector3(0, 0.8, 0.6),
		Vector3.BACK, Vector3.BACK, Vector3(0, 0.8, 0.6), Vector3.UP, Vector3.UP])
	for i: int in normals.size(): normals[i] = (global_basis.orthonormalized() * normals[i]).normalized()
	if descending: normals.reverse()
	return normals

func endpoint(descending: bool) -> Vector3:
	return to_global(Vector3(0, height + 0.001, -0.16) if descending else Vector3(0, 0.001, 0.12))
