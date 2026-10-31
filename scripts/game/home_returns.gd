extends Node
## Map-local return queries and placement rules; no client scoring intents.
const MIN_FOOD_DISTANCE := 4.0
const MIN_HOME_DISTANCE := 8.0
var world: Node3D
var points: Array[Area3D] = []

func setup(owner_world: Node3D) -> void:
	world = owner_world
	for node: Node in world.get_node("DinerKitchen").find_children("*", "Area3D", true, false):
		if node.is_in_group("bug_return_points"): points.append(node)
	points.sort_custom(func(a: Node, b: Node) -> bool: return str(a.get_path()) < str(b.get_path()))

func nearest(at: Vector3) -> Area3D:
	var best: Area3D
	var distance := INF
	for point: Area3D in points:
		var next := at.distance_squared_to(point.global_position)
		if next < distance:
			distance = next
			best = point
	return best

func at_position(at: Vector3) -> Area3D:
	var excludes: Array[RID] = []
	for token: CharacterBody3D in world.players.get_children(): excludes.append(token.get_rid())
	for point: Area3D in points:
		if point.contains_position(at, excludes): return point
	return null

func allows_food_spawn(at: Vector3) -> bool:
	for point: Area3D in points:
		if _distance(at, point.global_position) < MIN_FOOD_DISTANCE: return false
	return true

func layout_errors() -> Array[String]:
	var errors: Array[String] = []
	if points.size() < 2: errors.append("Map needs at least two home_return_point instances.")
	for index: int in points.size():
		var point := points[index]
		if not point.global_basis.get_scale().is_equal_approx(Vector3.ONE): errors.append("Return point must stay at unit scale: " + str(point.get_path()))
		for other: int in range(index):
			if _distance(point.global_position, points[other].global_position) < MIN_HOME_DISTANCE:
				errors.append("Return entrances must be at least 8m apart: " + str(point.get_path()))
	for marker: Node in world.find_children("*", "Marker3D", true, false):
		if marker.is_in_group("food_spawn_spots") and not allows_food_spawn(marker.global_position):
			errors.append("Food spawn is within 4m of a home: " + str(marker.get_path()))
	for at: Vector3 in world.food_run.get_spawn_positions():
		if not allows_food_spawn(at): errors.append("Legacy food spawn is within 4m of a home: " + str(at))
	return errors

func _distance(a: Vector3, b: Vector3) -> float:
	# Horizontal distance also rejects a food table directly above a return spot.
	return Vector2(a.x - b.x, a.z - b.z).length()
