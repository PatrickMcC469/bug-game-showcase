extends SceneTree
## Reapply only the current art pass, preserving gameplay fixtures and resource IDs.
func _initialize() -> void:
	_build.call_deferred()

func _build() -> void:
	var path := "res://scenes/game/maps/diner_kitchen.tscn"
	var map := load(path).instantiate() as Node3D
	root.add_child(map)
	load("res://scripts/tools/diner_atmosphere.gd").new().dress_map(map)
	var packed := PackedScene.new()
	var error := packed.pack(map)
	if error == OK: error = ResourceSaver.save(packed, path)
	print("DINER DRESS: %s" % ("PASS" if error == OK else error_string(error)))
	map.free()
	quit(0 if error == OK else 1)
