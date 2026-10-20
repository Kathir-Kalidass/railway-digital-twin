class_name WorldObject
extends Node3D


func _ready() -> void:
	var root_singleton := get_node_or_null("/root/Root")
	if root_singleton == null:
		push_error("The LTS Root autoload is required for world-origin updates.")
		return
	root_singleton.connect("world_origin_shifted", Callable(self, "_on_world_origin_shifted"))


func _on_world_origin_shifted(delta: Vector3):
	position += delta
	self.update()


# overwrite this in child classes
func update():
	pass
