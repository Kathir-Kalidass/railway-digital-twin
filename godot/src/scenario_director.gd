extends Node
class_name ScenarioDirector

@export var bridge_path: NodePath
@export var wildlife_behaviour_path: NodePath
@export var camera_director_path: NodePath
@export var atmosphere_path: NodePath
@export var fleet_path: NodePath = NodePath("../FleetController")
@export var zone := "zone1"
@export var cinematic_seconds := 8.0

var running := false


func run_reel() -> void:
	if running:
		return
	running = true
	var wildlife := get_node_or_null(wildlife_behaviour_path) as WildlifeBehaviour
	if wildlife:
		wildlife.trigger_crossing("deer")
	var camera := get_node_or_null(camera_director_path) as CameraDirector
	if camera:
		camera.set_mode("drone")
	var atmosphere := get_node_or_null(atmosphere_path) as Atmosphere
	if atmosphere:
		atmosphere.set_daynight(0.25)

	await get_tree().create_timer(cinematic_seconds).timeout

	if is_instance_valid(camera):
		camera.set_mode("follow")
	if is_instance_valid(atmosphere):
		atmosphere.set_daynight(0.75)
	running = false


func run_safety_scenario() -> void:
	if running:
		return
	running = true
	var bridge := get_node_or_null(bridge_path) as MQTTBridge
	if bridge == null:
		running = false
		return
	for signal_aspect in ["GREEN", "YELLOW", "RED"]:
		bridge.message_received.emit("railway/%s/signal" % zone, {"signal": signal_aspect})
		await get_tree().create_timer(1.2).timeout
	bridge.message_received.emit("railway/%s/signal" % zone, {"signal": "GREEN"})
	running = false


func run_meet_scenario(step_sec: float = 1.0) -> void:
	if running:
		return
	running = true
	var camera := get_node_or_null(camera_director_path) as CameraDirector
	if camera:
		camera.set_mode("station")

	var fleet := get_node_or_null(fleet_path) as FleetController
	if fleet:
		fleet.apply_state({
			"trains": [
				{
					"id": "T1",
					"line": "UP",
					"block": "UP-B2",
					"offsetM": 20.0,
					"travelSign": 1,
					"speedKmh": 0.0,
					"targetSpeedKmh": 0.0
				},
				{
					"id": "T3",
					"line": "DOWN",
					"block": "DOWN-B2",
					"offsetM": 20.0,
					"travelSign": -1,
					"speedKmh": 0.0,
					"targetSpeedKmh": 0.0
				}
			]
		})

		await get_tree().create_timer(step_sec).timeout

		fleet.apply_state({
			"trains": [
				{
					"id": "T1",
					"line": "UP",
					"block": "UP-B2",
					"offsetM": 20.0,
					"travelSign": 1,
					"speedKmh": 0.0,
					"targetSpeedKmh": 0.0
				},
				{
					"id": "T3",
					"line": "DOWN",
					"block": "DOWN-B3",
					"offsetM": 10.0,
					"travelSign": -1,
					"speedKmh": 45.0,
					"targetSpeedKmh": 45.0
				}
			]
		})

		await get_tree().create_timer(step_sec).timeout

		fleet.transition_train_line("T1", "DOWN", step_sec)

		await get_tree().create_timer(step_sec).timeout

		fleet.apply_state({
			"trains": [
				{
					"id": "T1",
					"line": "DOWN",
					"block": "DOWN-B2",
					"offsetM": 40.0,
					"travelSign": 1,
					"speedKmh": 45.0,
					"targetSpeedKmh": 45.0
				},
				{
					"id": "T3",
					"line": "DOWN",
					"block": "DOWN-B4",
					"offsetM": 10.0,
					"travelSign": -1,
					"speedKmh": 45.0,
					"targetSpeedKmh": 45.0
				}
			]
		})

	if is_instance_valid(camera):
		camera.set_mode("follow")
	running = false

