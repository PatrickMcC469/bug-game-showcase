extends RefCounted
## Pure host-side shot queries. Clients never submit victims or damage amounts.
const RANGE := 18.0
const PELLET_COUNT := 12
const SPREAD := 0.05235988 # Three degrees, provisional playtest tuning.
const CLOSE_DAMAGE := 60
const FAR_DAMAGE := 20

static func pellet_directions(direction: Vector3, seed_value: int) -> Array[Vector3]:
	var forward := direction.normalized()
	var up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var right := forward.cross(up).normalized()
	up = right.cross(forward).normalized()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var phase := rng.randf() * TAU
	var result: Array[Vector3] = [forward]
	for index: int in range(1, PELLET_COUNT):
		var radius := sqrt(float(index) / (PELLET_COUNT - 1)) * tan(SPREAD)
		var angle := phase + index * 2.39996323
		result.append((forward + radius * (right * cos(angle) + up * sin(angle))).normalized())
	return result

static func damage_at(distance: float) -> int:
	return roundi(lerpf(CLOSE_DAMAGE, FAR_DAMAGE, clampf((distance - 3.0) / 12.0, 0, 1)))

static func trace(space: PhysicsDirectSpaceState3D, chest: Vector3, grip: Vector3,
		direction: Vector3, exclude: Array[RID], mask: int, seed_value: int) -> Dictionary:
	var muzzle := grip + direction.normalized() * 0.625
	# Test the entire protruding weapon first: a muzzle through a thin wall must
	# never allow pellets to start on the other side of that wall.
	var barrel_query := PhysicsRayQueryParameters3D.create(chest, muzzle, mask, exclude)
	barrel_query.hit_from_inside = true
	var barrel := space.intersect_ray(barrel_query)
	var ends := PackedVector3Array()
	var hits: Array[Dictionary] = []
	if not barrel.is_empty() and not barrel.collider is CharacterBody3D:
		ends.append(barrel.position)
		return {"origin": chest, "ends": ends, "hits": hits, "blocked": true}
	# Trace from the receiver when a character is closer than the muzzle. The
	# cover probe must not make a close target immune or let the barrel skip it.
	if not barrel.is_empty(): muzzle = chest
	for pellet: Vector3 in pellet_directions(direction, seed_value):
		var end := muzzle + pellet * RANGE
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(muzzle, end, mask, exclude))
		if not hit.is_empty():
			end = hit.position
			hits.append({"collider": hit.collider, "position": end,
				"damage": damage_at(muzzle.distance_to(end))})
		ends.append(end)
	return {"origin": muzzle, "ends": ends, "hits": hits, "blocked": false}
