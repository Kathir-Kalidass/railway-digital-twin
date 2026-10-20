extends SceneTree

const REQUIRED_SCRIPTS := [
	"res://addons/godot-mqtt/mqtt.gd",
	"res://src/compat_stubs.gd",
	"res://Data/Scripts/Singletons/Math.gd",
	"res://Data/Scripts/Singletons/Root.gd",
	"res://Data/Scripts/chunk.gd",
]

func _initialize() -> void:
	var a := Assert.new()
	for path in REQUIRED_SCRIPTS:
		var script: GDScript = load(path)
		a.ok(script != null and script.can_instantiate(), "parses " + path)
	quit(a.report("test_parse"))
