extends Node3D
## Map-owned links keep reusable appliances independent of map coordinates.
@export_node_path("Node3D") var sink_path: NodePath
@export_node_path("Node3D") var outside_path: NodePath

func _ready() -> void:
	add_to_group("drain_routes")

func endpoint(outside: bool) -> Node3D:
	return get_node_or_null(outside_path if outside else sink_path) as Node3D
