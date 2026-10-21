extends Node3D
class_name RailwayBridge

## Short railway bridge centred on the loop/river crossing. The deck follows
## the track pose; piers descend into the river channel.

@export var track_path: NodePath
@export var distance_fraction := 0.25
@export var span_m := 44.0
@export var width_m := 6.0

func _ready() -> void:
	_place()
	_build()


func _place() -> void:
	var track := get_node_or_null(track_path) as LTSTrack
	if track == null:
		return
	global_transform = track.get_global_transform_at_distance(track.length * distance_fraction)


func get_bridge_pose() -> Transform3D:
	return global_transform


func _build() -> void:
	var concrete := _material(Color(0.44, 0.45, 0.44), 0.92)
	var steel := _material(Color(0.25, 0.28, 0.3), 0.42, 0.58)
	var rail := _material(Color(0.2, 0.22, 0.23), 0.55, 0.35)

	var deck := MeshInstance3D.new()
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(span_m, 0.42, width_m)
	deck.mesh = deck_mesh
	deck.material_override = concrete
	deck.position = Vector3(0.0, -0.5, 0.0)
	add_child(deck)

	for side in [-1.0, 1.0]:
		var girder := MeshInstance3D.new()
		var girder_mesh := BoxMesh.new()
		girder_mesh.size = Vector3(span_m, 0.62, 0.26)
		girder.mesh = girder_mesh
		girder.material_override = steel
		girder.position = Vector3(0.0, -0.85, side * (width_m * 0.5 - 0.14))
		add_child(girder)

		for rail_y in [0.42, 0.78]:
			var railing := MeshInstance3D.new()
			var railing_mesh := BoxMesh.new()
			railing_mesh.size = Vector3(span_m, 0.06, 0.08)
			railing.mesh = railing_mesh
			railing.material_override = rail
			railing.position = Vector3(0.0, rail_y, side * (width_m * 0.5 - 0.2))
			add_child(railing)

	for x in [-span_m * 0.3, span_m * 0.3]:
		for z in [-width_m * 0.32, width_m * 0.32]:
			var pier := MeshInstance3D.new()
			var pier_mesh := BoxMesh.new()
			pier_mesh.size = Vector3(0.75, 3.8, 0.75)
			pier.mesh = pier_mesh
			pier.material_override = concrete
			pier.position = Vector3(x, -2.7, z)
			add_child(pier)


func _material(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	result.metallic = metallic
	return result
