extends SceneTree

func _initialize() -> void:
	var a := Assert.new()
	var math_script: GDScript = load("res://Data/Scripts/Singletons/Math.gd")
	var math = math_script.new()
	a.eq(math.speed_to_kmh(math.kmh_to_speed(72.0)), 72.0, "speed unit conversion")
	a.eq(math.get_next_pos(0.0, Vector3.ZERO, 0.0, 5.0), Vector3(5.0, 0.0, 0.0), "straight rail position")
	a.eq(math.sort_signals({"name": ["late", "early"], "position": [20.0, 10.0]}), ["early", "late"], "sort forward signals")
	a.eq(math.sort_signals({"name": ["late", "early"], "position": [20.0, 10.0]}, false), ["late", "early"], "sort reverse signals")
	a.eq(math.time_to_string([9, 5, 2]), "09:05:02", "format time")

	var input_script: GDScript = load("res://Data/Scripts/Singletons/input_helper.gd")
	var input_helper = input_script.new()
	a.eq(input_helper._get_xbox_button_name(JOY_BUTTON_A), "A", "Godot 4 controller button")
	a.eq(input_helper._get_xbox_axis_name(JOY_AXIS_LEFT_X), "Left Stick Horizontal", "Godot 4 controller axis")

	var root_script: GDScript = load("res://Data/Scripts/Singletons/Root.gd")
	var root = root_script.new()
	var files: Array[String] = []
	root.crawl_directory(files, "res://Data/Scripts/Enums", ["gd"])
	a.ok(not files.is_empty(), "Root scans project paths")
	math.free()
	input_helper.free()
	root.free()
	quit(a.report("test_port_helpers"))
