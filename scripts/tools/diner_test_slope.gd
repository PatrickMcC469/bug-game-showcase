extends RefCounted
## Test-only support for late-join slope replication, independent of map ramps.
## Placed above the playable map in both smoke-test processes; never shipped
## as geometry in the diner scene or instantiated by normal game code.
static func add_to(world: Node3D) -> void:
	var start := Vector3(-6, 0.001, -3.1) * 0.45
	var end := Vector3(-6, 2.4, -8.6) * 0.45
	var body := StaticBody3D.new()
	body.name = "SmokeSlopeFixture"
	body.position = (start + end) * 0.5 - Vector3.UP * (0.045 * 0.45) + Vector3.UP * 10.0
	body.rotation.x = atan2(2.399, 5.5)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 0.09 * 0.45, start.distance_to(end) + 0.12 * 0.45)
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body)
