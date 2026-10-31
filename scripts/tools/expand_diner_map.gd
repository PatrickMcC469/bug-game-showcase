extends SceneTree
## Apply the room expansion to the packed kitchen without rebuilding its art.
func _initialize() -> void:
	_build.call_deferred()

func _build() -> void:
	var path := "res://scenes/game/maps/diner_kitchen.tscn"
	var map := load(path).instantiate() as Node3D
	root.add_child(map)
	preload("res://scripts/tools/diner_makeover.gd").new().apply(map)
	var scene := PackedScene.new()
	var error := scene.pack(map)
	if error == OK: error = ResourceSaver.save(scene, path)
	print("DINER EXPANSION: %s" % ("PASS" if error == OK else error_string(error)))
	map.free()
	quit(0 if error == OK else 1)
