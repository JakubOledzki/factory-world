extends SceneTree
## CI check: loads every script and scene so GDScript errors fail the build.
## Run: godot --headless --script res://tools/check_scripts.gd


func _initialize() -> void:
	var failed := 0
	for path in _files("res://", ["gd", "tscn"]):
		var resource: Resource = load(path)
		if resource == null or not resource.can_instantiate():
			printerr("Failed to load %s" % path)
			failed += 1
	print("Checked scripts and scenes, %d failed." % failed)
	quit(1 if failed > 0 else 0)


func _files(dir: String, extensions: Array) -> Array[String]:
	var found: Array[String] = []
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			found.append_array(_files(dir.path_join(sub), extensions))
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() in extensions:
			found.append(dir.path_join(file))
	return found
