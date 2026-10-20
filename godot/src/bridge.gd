extends Node3D
class_name Bridge

@export var span := 40.0
@export var height := 6.0
@export var road_width := 8.0

func _ready() -> void:
	build()

func build() -> void:
	var deck := CSGBox3D.new()
	deck.size = Vector3(road_width, 0.5, span)
	deck.transform.origin.y = height
	add_child(deck)
