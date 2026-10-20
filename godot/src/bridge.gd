extends Node3D
class_name Bridge

@export var span := 40.0
@export var height := 6.0
@export var road_width := 8.0

const LTS_BRIDGES := [
	"res://Resources/Objects/street_bridge_1_30m.obj",
	"res://Resources/Objects/highway_bridge_1_30m.obj",
]

func _ready() -> void:
	build()

func build() -> void:
	for path in LTS_BRIDGES:
		if not ResourceLoader.exists(path):
			continue
		var mesh := load(path) as Mesh
		if mesh == null:
			continue
		var model := MeshInstance3D.new()
		model.name = "LTSBridge"
		model.mesh = mesh
		model.scale = Vector3(road_width / 8.0, 1.0, span / 30.0)
		model.position.y = height
		add_child(model)
		return
	# Procedural fallback when the optional Libre-TrainSim assets are absent.
	var deck := CSGBox3D.new()
	deck.name = "ProceduralDeck"
	deck.size = Vector3(road_width, 0.5, span)
	deck.transform.origin.y = height
	add_child(deck)
