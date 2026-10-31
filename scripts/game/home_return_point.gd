@tool
extends Area3D
## Map-owned reusable entrance. Scoring stays in the host's food controllers.
@export var display_name := "Bug home"
const DELIVERY_RADIUS := 0.09
const DELIVERY_HEIGHT := 0.03

func _enter_tree() -> void:
	add_to_group("bug_return_points")

func contains_position(at: Vector3, excludes: Array[RID] = []) -> bool:
	var local := to_local(at)
	if absf(local.y) > DELIVERY_HEIGHT or Vector2(local.x, local.z).length() > DELIVERY_RADIUS: return false
	# A thin wall or closed prop between food and entrance cannot bank it.
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.012, global_position + Vector3.UP * 0.012, 1, excludes)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func celebrate() -> void:
	# Kept as a presentation hook for the existing shared delivery feedback.
	pass
