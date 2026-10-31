extends RefCounted
## Preload a probe before a short-lived state begins; release its real network
## join only after that state is active. Each child uses its unique log path.

const ARGUMENT_PREFIX := "--late-join-gate="


static func wait_for_release(tree: SceneTree) -> bool:
	var path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(ARGUMENT_PREFIX):
			path = argument.trim_prefix(ARGUMENT_PREFIX)
	if path.is_empty():
		return true
	var ready := FileAccess.open(path + ".ready", FileAccess.WRITE)
	if ready == null:
		return false
	ready.store_string("ready")
	ready.close()
	var deadline := Time.get_ticks_msec() + 60000
	while not FileAccess.file_exists(path + ".join") and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	return FileAccess.file_exists(path + ".join")


static func is_ready(path: String) -> bool:
	return FileAccess.file_exists(path + ".ready")


static func release(path: String) -> bool:
	var start := FileAccess.open(path + ".join", FileAccess.WRITE)
	if start == null:
		return false
	start.store_string("join")
	start.close()
	return true


static func cleanup(path: String) -> void:
	if path.is_empty():
		return
	DirAccess.remove_absolute(path + ".ready")
	DirAccess.remove_absolute(path + ".join")
