extends SceneTree

func _initialize() -> void:
	var a := Assert.new()
	var roots := ["res://addons/lts_runtime", "res://src"]
	var checked := 0
	for root in roots:
		for path in _gd_files(root):
			var script: GDScript = load(path)
			a.ok(script != null, "loads " + path)
			checked += 1
	a.ok(checked > 0, "found scripts to check")
	quit(a.report("test_parse"))

func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		var full := dir_path.path_join(f)
		if d.current_is_dir():
			out.append_array(_gd_files(full))
		elif f.ends_with(".gd"):
			out.append(full)
		f = d.get_next()
	return out
