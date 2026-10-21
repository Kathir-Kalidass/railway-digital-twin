class_name BlockSignalMast
extends Node3D

@export var block_id: String = ""
@export var line_id: String = "UP"

var _current_aspect: String = "GREEN"
var _red_mesh: MeshInstance3D
var _yellow_mesh: MeshInstance3D
var _green_mesh: MeshInstance3D

var _mat_red_on: StandardMaterial3D
var _mat_red_off: StandardMaterial3D
var _mat_yellow_on: StandardMaterial3D
var _mat_yellow_off: StandardMaterial3D
var _mat_green_on: StandardMaterial3D
var _mat_green_off: StandardMaterial3D


func _ready() -> void:
	_setup_materials()
	_build_mesh()
	set_aspect(_current_aspect)


func _setup_materials() -> void:
	_mat_red_on = StandardMaterial3D.new()
	_mat_red_on.albedo_color = Color(1.0, 0.1, 0.1)
	_mat_red_on.emission_enabled = true
	_mat_red_on.emission = Color(1.0, 0.05, 0.05)
	_mat_red_on.emission_energy_multiplier = 4.0

	_mat_red_off = StandardMaterial3D.new()
	_mat_red_off.albedo_color = Color(0.25, 0.05, 0.05)

	_mat_yellow_on = StandardMaterial3D.new()
	_mat_yellow_on.albedo_color = Color(1.0, 0.75, 0.1)
	_mat_yellow_on.emission_enabled = true
	_mat_yellow_on.emission = Color(1.0, 0.7, 0.05)
	_mat_yellow_on.emission_energy_multiplier = 4.0

	_mat_yellow_off = StandardMaterial3D.new()
	_mat_yellow_off.albedo_color = Color(0.25, 0.2, 0.05)

	_mat_green_on = StandardMaterial3D.new()
	_mat_green_on.albedo_color = Color(0.1, 0.95, 0.2)
	_mat_green_on.emission_enabled = true
	_mat_green_on.emission = Color(0.1, 0.9, 0.15)
	_mat_green_on.emission_energy_multiplier = 4.0

	_mat_green_off = StandardMaterial3D.new()
	_mat_green_off.albedo_color = Color(0.05, 0.22, 0.08)


func _build_mesh() -> void:
	# Mast post
	var post := MeshInstance3D.new()
	post.name = "MastPost"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.07
	cyl.bottom_radius = 0.09
	cyl.height = 3.6
	post.mesh = cyl
	post.position = Vector3(0.0, 1.8, 0.0)

	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.2, 0.22, 0.25)
	post_mat.metallic = 0.6
	post.material_override = post_mat
	add_child(post)

	# Signal head backing box
	var head := MeshInstance3D.new()
	head.name = "SignalHead"
	var box := BoxMesh.new()
	box.size = Vector3(0.36, 0.88, 0.2)
	head.mesh = box
	head.position = Vector3(0.0, 3.2, 0.0)

	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.08, 0.08, 0.1)
	head_mat.metallic = 0.2
	head.material_override = head_mat
	add_child(head)

	# 3 Lenses: RED (top), YELLOW (mid), GREEN (bottom)
	_red_mesh = _create_lens("LensRed", Vector3(0.0, 3.48, 0.11))
	_yellow_mesh = _create_lens("LensYellow", Vector3(0.0, 3.20, 0.11))
	_green_mesh = _create_lens("LensGreen", Vector3(0.0, 2.92, 0.11))

	# Block ID Label
	var label := Label3D.new()
	label.name = "BlockLabel"
	label.text = block_id
	label.font_size = 28
	label.position = Vector3(0.0, 2.5, 0.1)
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	label.modulate = Color(0.9, 0.95, 1.0)
	add_child(label)


func _create_lens(lens_name: String, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = lens_name
	var sphere := SphereMesh.new()
	sphere.radius = 0.065
	sphere.height = 0.13
	mi.mesh = sphere
	mi.position = pos
	add_child(mi)
	return mi


func set_aspect(aspect: String) -> void:
	var norm := aspect.strip_edges().to_upper()
	if norm == "CAUTION":
		norm = "YELLOW"
	elif norm == "STOP":
		norm = "RED"
	elif norm != "RED" and norm != "YELLOW" and norm != "GREEN":
		norm = "GREEN"

	_current_aspect = norm

	if not is_instance_valid(_red_mesh):
		return

	match _current_aspect:
		"RED":
			_red_mesh.material_override = _mat_red_on
			_yellow_mesh.material_override = _mat_yellow_off
			_green_mesh.material_override = _mat_green_off
		"YELLOW":
			_red_mesh.material_override = _mat_red_off
			_yellow_mesh.material_override = _mat_yellow_on
			_green_mesh.material_override = _mat_green_off
		"GREEN":
			_red_mesh.material_override = _mat_red_off
			_yellow_mesh.material_override = _mat_yellow_off
			_green_mesh.material_override = _mat_green_on


func get_aspect() -> String:
	return _current_aspect


func is_lamp_active(color_name: String) -> bool:
	match color_name.to_upper():
		"RED":
			return _current_aspect == "RED"
		"YELLOW":
			return _current_aspect == "YELLOW"
		"GREEN":
			return _current_aspect == "GREEN"
	return false
