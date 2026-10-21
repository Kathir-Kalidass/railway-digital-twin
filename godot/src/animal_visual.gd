class_name AnimalVisual
extends Node3D

## Procedural gait for the Blender-built animal meshes. Every limb is a separate
## GLB node whose origin is the joint, so a simple sine swing reads as walking.

@export var walk_amplitude := 0.42
@export var gait_speed := 2.1

var _legs: Array[Node3D] = []
var _rest_rotation: Array[Vector3] = []
var _trunk: Node3D
var _head: Node3D
var _head_rest := Vector3.ZERO
var _last_position := Vector3.ZERO
var _phase := 0.0

func _ready() -> void:
	_last_position = global_position
	for leg_name in ["LegFL", "LegFR", "LegBL", "LegBR"]:
		var leg := find_child(leg_name, true, false) as Node3D
		if leg:
			_legs.append(leg)
			_rest_rotation.append(leg.rotation)
	_trunk = find_child("Trunk", true, false) as Node3D
	_head = find_child("Head", true, false) as Node3D
	if _head:
		_head_rest = _head.rotation
	_drop_to_ground()


func _process(delta: float) -> void:
	var speed := global_position.distance_to(_last_position) / maxf(delta, 0.001)
	_last_position = global_position
	if speed > 20.0:
		speed = 0.0
	_phase += delta * (gait_speed + minf(speed, 3.0) * 1.4)
	var amount := clampf(speed, 0.0, 2.0) * 0.8
	var swing := sin(_phase) * walk_amplitude * amount
	for index in _legs.size():
		var sign_value := 1.0 if index in [0, 3] else -1.0
		_legs[index].rotation = _rest_rotation[index] + Vector3(swing * sign_value, 0.0, 0.0)
	if _head:
		_head.rotation.x = _head_rest.x + sin(_phase * 0.5) * 0.03 * amount
	if _trunk:
		_trunk.rotation.z = sin(_phase * 0.4) * 0.06
		_trunk.rotation.x = sin(_phase * 0.7 + 0.5) * 0.04


func _drop_to_ground() -> void:
	var box := _local_bounds()
	if box.size == Vector3.ZERO:
		return
	position.y -= box.position.y


func _local_bounds() -> AABB:
	var result := AABB()
	var found := false
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var relative := global_transform.affine_inverse() * mesh_instance.global_transform
		var box := mesh_instance.get_aabb()
		for index in 8:
			var point := relative * box.get_endpoint(index)
			if not found:
				result = AABB(point, Vector3.ZERO)
				found = true
			else:
				result = result.expand(point)
	return result
