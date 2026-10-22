class_name TracksideSensorHut
extends Node3D

## Individual trackside sensor hut monitoring wildlife across a 75m radius.
## Houses trackside IoT electronics, status indicator, and MQTT reporting.

@export var sensor_id := "UP-S0"
@export var line := "UP"
@export var boundary_distance_m := 0.0
@export var coverage_radius_m := 75.0
@export var line_length_m := 0.0

var bridge: MQTTBridge
var _detecting := false
var _last_observation: Dictionary = {}
var _lamp_mesh: MeshInstance3D
var _seq := 0


func _ready() -> void:
	_build_visuals()


func _build_visuals() -> void:
	# 1. Concrete equipment hut
	var hut := MeshInstance3D.new()
	hut.name = "HutBody"
	var hut_mesh := BoxMesh.new()
	hut_mesh.size = Vector3(1.8, 1.6, 1.4)
	hut.mesh = hut_mesh
	var hut_mat := StandardMaterial3D.new()
	hut_mat.albedo_color = Color(0.48, 0.5, 0.52)
	hut_mat.roughness = 0.8
	hut.material_override = hut_mat
	hut.position = Vector3(0.0, 0.8, 0.0)
	add_child(hut)

	# 2. Sensor mast / post
	var mast := MeshInstance3D.new()
	mast.name = "Mast"
	var mast_mesh := CylinderMesh.new()
	mast_mesh.top_radius = 0.08
	mast_mesh.bottom_radius = 0.08
	mast_mesh.height = 3.2
	mast.mesh = mast_mesh
	var mast_mat := StandardMaterial3D.new()
	mast_mat.albedo_color = Color(0.25, 0.26, 0.28)
	mast_mat.metallic = 0.6
	mast.material_override = mast_mat
	mast.position = Vector3(0.0, 2.4, 0.0)
	add_child(mast)

	# 3. Solar panel / antenna
	var antenna := MeshInstance3D.new()
	antenna.name = "Antenna"
	var ant_mesh := BoxMesh.new()
	ant_mesh.size = Vector3(0.4, 0.04, 0.4)
	antenna.mesh = ant_mesh
	var ant_mat := StandardMaterial3D.new()
	ant_mat.albedo_color = Color(0.12, 0.15, 0.22)
	antenna.material_override = ant_mat
	antenna.position = Vector3(0.0, 4.0, 0.0)
	antenna.rotation_degrees = Vector3(25.0, 0.0, 0.0)
	add_child(antenna)

	# 4. Status lamp (GREEN=clear, RED=detecting)
	_lamp_mesh = MeshInstance3D.new()
	_lamp_mesh.name = "Lamp"
	var lamp_sphere := SphereMesh.new()
	lamp_sphere.radius = 0.16
	lamp_sphere.height = 0.32
	_lamp_mesh.mesh = lamp_sphere
	_lamp_mesh.position = Vector3(0.0, 3.8, 0.18)
	add_child(_lamp_mesh)
	_set_lamp_color(Color.GREEN)


func _set_lamp_color(col: Color) -> void:
	if not is_instance_valid(_lamp_mesh):
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.0
	_lamp_mesh.material_override = mat


func physical_to_operational(physical_m: float) -> float:
	if line_length_m <= 0.0:
		return physical_m
	if line == "DOWN":
		return fposmod(line_length_m - physical_m, line_length_m)
	return fposmod(physical_m, line_length_m)


func _operational_distance(track_distance_m: float) -> float:
	return physical_to_operational(track_distance_m)


func scan_animals(animals: Array) -> void:
	var covered: Array[Dictionary] = []
	for node in animals:
		var n3d := node as Node3D
		if n3d == null or not n3d.visible:
			continue
		var dist := (n3d.global_position - global_position).length()
		if dist <= coverage_radius_m:
			var species := str(n3d.get_meta("species", "deer")) if n3d.has_meta("species") else "deer"
			var track_d := float(n3d.get_meta("track_distance_m", boundary_distance_m)) if n3d.has_meta("track_distance_m") else boundary_distance_m
			covered.append({
				"node": n3d,
				"dist": dist,
				"species": species,
				"track_distance_m": track_d,
			})

	if not covered.is_empty():
		var nearest: Dictionary = covered[0]
		var was_detecting := _detecting
		_detecting = true
		_set_lamp_color(Color.RED)

		_seq += 1
		var obs := {
			"eventId": "trackside-%s-%d-%d" % [sensor_id, int(Time.get_unix_time_from_system()), _seq],
			"source": "trackside",
			"line": line,
			"distanceM": _operational_distance(float(nearest.get("track_distance_m", boundary_distance_m))),
			"wildlifeDetected": true,
			"species": str(nearest.get("species", "deer")),
			"count": covered.size(),
			"onTrack": true,
			"sensorId": sensor_id,
			"timestamp": Time.get_unix_time_from_system(),
		}
		_last_observation = obs
		if not was_detecting:
			_publish(obs)
	else:
		if _detecting:
			_detecting = false
			_set_lamp_color(Color.GREEN)
			_seq += 1
			var clear_obs := {
				"eventId": "trackside-%s-%d-%d" % [sensor_id, int(Time.get_unix_time_from_system()), _seq],
				"source": "trackside",
				"line": line,
				"distanceM": _operational_distance(boundary_distance_m),
				"wildlifeDetected": false,
				"species": "deer",
				"count": 0,
				"onTrack": false,
				"sensorId": sensor_id,
				"timestamp": Time.get_unix_time_from_system(),
			}
			_last_observation = clear_obs
			_publish(clear_obs)


func _publish(payload: Dictionary) -> void:
	if is_instance_valid(bridge) and bridge.is_broker_connected():
		bridge.publish("railway/wildlife", payload)


func is_detecting() -> bool:
	return _detecting


func get_last_observation() -> Dictionary:
	return _last_observation
