extends Node3D
class_name TrackBuilder

@export var length := 200.0
@export var radius := 150.0
@export var gauge := 1.435
@export var sleep_spacing := 0.6

func _ready() -> void:
	build()

func build() -> void:
	var rails := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.mesh = CylinderMesh.new()
	mm.mesh.radius = 0.05
	mm.mesh.height = 0.5
	mm.instance_count = 400
	rails.multimesh = mm
	for i in range(400):
		var d := i * length / 400.0
		var angle := d / radius if radius > 0 else 0
		var pos := Vector3(sin(angle)*radius, 0.25, cos(angle)*radius - radius)
		var t := Transform3D(Basis(Vector3.UP, -angle), pos)
		mm.set_instance_transform(i, t)
	add_child(rails)
