extends SceneTree


class RecordingBridge:
	extends MQTTBridge

	var sent: Array[Dictionary] = []

	func publish(topic: String, payload: Variant, retain: bool = false, qos: int = 0) -> bool:
		sent.append({"topic": topic, "payload": payload})
		return true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var container := Node.new()
	root.add_child(container)
	var bridge := RecordingBridge.new()
	bridge.name = "Bridge"
	bridge.connect_on_ready = false
	container.add_child(bridge)
	var publisher := WildlifePublisher.new()
	publisher.name = "Publisher"
	publisher.bridge_path = NodePath("../Bridge")
	publisher.zone = "zone2"
	container.add_child(publisher)
	var detection_script := load("res://src/detection_band.gd") as GDScript
	var detection := detection_script.new() as DetectionBand
	detection.publisher_path = NodePath("../Publisher")
	detection.species = "deer"
	container.add_child(detection)

	var a := Assert.new()
	a.ok(publisher.bridge == bridge, "resolves the configured MQTT bridge")
	a.ok(detection.has_method("_on_area_entered"), "loads wildlife entry handler")
	a.ok(detection.area_entered.is_connected(Callable(detection, "_on_area_entered")), "connects wildlife entry signal")
	publisher.report("deer", 2, false)
	publisher.report("deer", 2, false)
	a.eq(bridge.sent.size(), 1, "debounces unchanged wildlife observations")
	var animal := Area3D.new()
	animal.add_to_group("wildlife")
	animal.set_meta("species", "deer")
	detection.area_entered.emit(animal)
	a.eq(bridge.sent.size(), 2, "publishes matching wildlife entering the detection band")
	detection.area_exited.emit(animal)
	a.eq(bridge.sent.size(), 3, "publishes when wildlife leaves the detection band")
	if not bridge.sent.is_empty():
		a.eq(bridge.sent[0]["topic"], "railway/zone2/wildlife", "publishes the zone wildlife topic")
		a.eq(bridge.sent[0]["payload"]["species"], "deer", "includes the species")
		a.eq(bridge.sent[0]["payload"]["count"], 2, "includes the count")
	publisher.report("deer", 1, true)
	a.eq(bridge.sent.size(), 4, "publishes renewed wildlife after the zone clears")
	publisher.report("deer", 2, true)
	a.eq(bridge.sent.size(), 5, "publishes changed observations")

	animal.free()
	container.queue_free()
	call_deferred("_finish", a)


func _finish(assertions: Assert) -> void:
	await process_frame
	quit(assertions.report("test_wildlife_publisher"))
