extends Node3D
class_name TrackBuilder

@export var length := 200.0
@export var radius := 150.0
@export var gauge := 1.435
@export var sleep_spacing := 0.6

func _ready() -> void:
	build()

func build() -> void:
	var rail := CSGBank.new()
	rail.operation = CSGShape3D.OPERATION_UNION
	var r1 := CSGBox3D.new()
	r1.size = Vector3(0.07, 0.12, length)
	r1.transform.origin.x = -gauge/2
	var r2 := CSGBox3D.new()
	r2.size = Vector3(0.07, 0.12, length)
	r2.transform.origin.x = gauge/2
	add_child(r1)
	add_child(r2)
	add_child(rail)
