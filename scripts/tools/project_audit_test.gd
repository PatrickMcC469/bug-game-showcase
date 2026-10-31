extends SceneTree
## Load every first-party script and scene, including tools outside the main path.
var failures: Array[String] = []
var scripts_checked := 0
var scenes_checked := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_scan("res://scripts")
	_scan("res://scenes")
	# Check the tracked configuration rather than a developer's local overrides.
	var config := ConfigFile.new()
	if config.load("res://project.godot") != OK:
		failures.append("project.godot failed to load")
	else:
		for key: String in config.get_section_keys("autoload"):
			var path := str(config.get_value("autoload", key)).trim_prefix("*")
			if path.begins_with("res://addons/") or not ResourceLoader.exists(path):
				failures.append("autoload depends on an ignored/missing resource: " + path)
	print("PROJECT AUDIT: loaded %d scripts and %d scenes" % [scripts_checked, scenes_checked])
	for failure: String in failures: printerr("PROJECT AUDIT FAIL: " + failure)
	print("PROJECT AUDIT TEST: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _scan(folder: String) -> void:
	for filename: String in DirAccess.get_files_at(folder):
		var path := folder.path_join(filename)
		if filename.ends_with(".gd"):
			var script := load(path) as GDScript
			if script == null or not script.can_instantiate(): failures.append("script failed to parse: " + path)
			scripts_checked += 1
		elif filename.ends_with(".tscn"):
			var scene := load(path) as PackedScene
			if scene == null or not scene.can_instantiate():
				failures.append("scene failed to load: " + path)
			else:
				var instance := scene.instantiate()
				if instance == null: failures.append("scene failed to instantiate: " + path)
				else: instance.free()
			scenes_checked += 1
	for dirname: String in DirAccess.get_directories_at(folder):
		_scan(folder.path_join(dirname))
