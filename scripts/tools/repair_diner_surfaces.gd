extends SceneTree

func _initialize() -> void:
	_repair.call_deferred()

func _repair() -> void:
	var path := "res://scenes/game/maps/diner_kitchen.tscn"
	var map := load(path).instantiate() as Node3D
	root.add_child(map)
	preload("res://scripts/tools/diner_surface_cleanup.gd").new().apply(map)
	var scene := PackedScene.new()
	var result := scene.pack(map)
	if result == OK: result = ResourceSaver.save(scene, path)
	map.free()
	print("DINER SURFACES: ", "PASS" if result == OK else error_string(result))
	quit(0 if result == OK else 1)
