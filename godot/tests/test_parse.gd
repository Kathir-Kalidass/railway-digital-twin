extends SceneTree

const REQUIRED_SCRIPTS := [
	"res://addons/godot-mqtt/mqtt.gd",
	"res://src/compat_stubs.gd",
	"res://src/mqtt_bridge.gd",
	"res://src/train_reconciler.gd",
	"res://src/wildlife_publisher.gd",
	"res://src/detection_band.gd",
	"res://src/wildlife_spawner.gd",
	"res://src/wildlife_behaviour.gd",
	"res://src/wildlife_safety.gd",
	"res://src/esp32_integration.gd",
	"res://src/level_crossing.gd",
	"res://src/railway_bridge.gd",
	"res://src/ltstrack.gd",
	"res://src/track_registry.gd",
	"res://src/block_signal_mast.gd",
	"res://src/signal_director.gd",
	"res://src/fleet_controller.gd",
	"res://src/ltstrain.gd",
	"res://src/lts_world.gd",
	"res://Data/Scripts/Singletons/Math.gd",
	"res://Data/Scripts/Singletons/Root.gd",
	"res://Data/Scripts/Singletons/input_helper.gd",
	"res://Data/Scripts/world_object.gd",
	"res://Data/Scripts/Rail.gd",
	"res://Data/Scripts/chunk.gd",
]

func _initialize() -> void:
	var a := Assert.new()
	for path in REQUIRED_SCRIPTS:
		var script: GDScript = load(path)
		a.ok(script != null and script.can_instantiate(), "loads " + path)
		if script == null or not script.can_instantiate():
			continue
		var instance = script.new()
		a.ok(instance != null, "instantiates " + path)
		if instance is Node:
			instance.free()
	quit(a.report("test_parse"))
