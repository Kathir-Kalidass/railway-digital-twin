extends Node3D
class_name BridgeReal

@export var use_lts_bridge := true

func _ready() -> void:
	build()

func build() -> void:
	if use_lts_bridge:
		var paths := ["res://Resources/Objects/street_bridge_1_30m.obj", "res://Resources/Objects/highway_bridge_1_30m.obj", "res://Resources/Objects/highway_bridge_1_50m.obj"]
		for p in paths:
			if ResourceLoader.exists(p):
				var mesh := load(p)
				var mi := MeshInstance3D.new()
				mi.mesh = mesh
				mi.scale = Vector3(1.5, 1.2, 1.5)
				mi.transform.origin.y = 6.0
				add_child(mi)
				return
	var deck := CSGBox3D.new()
	deck.size = Vector3(10, 0.6, 40)
	deck.transform.origin.y = 6.0
	add_child(deck)
