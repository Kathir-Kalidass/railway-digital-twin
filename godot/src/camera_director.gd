extends Node
class_name CameraDirector

@export var cameras: Array[Camera3D] = []
var index := 0

func next() -> void:
	for c in cameras:
		if c: c.current = false
	index = (index + 1) % max(1, cameras.size())
	if cameras[index]: cameras[index].current = true
