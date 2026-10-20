extends Node3D
class_name WildlifeUnderpass

@export var tunnel_w := 6.0
@export var tunnel_h := 4.0
@export var tunnel_l := 20.0

func _ready() -> void:
	build()

func build() -> void:
	var t := CSGBox3D.new()
	t.size = Vector3(tunnel_w, tunnel_h, tunnel_l)
	t.transform.origin.y = tunnel_h/2 - 0.5
	add_child(t)
