extends Area3D
class_name DetectionBand

@export var publisher_path: NodePath
@export var species := "deer"
@export var zone := "zone1"

var _publisher: WildlifePublisher

func _ready() -> void:
	_publisher = get_node_or_null(publisher_path)
	body_entered.connect(_on_enter)

func _on_enter(body: Node) -> void:
	if _publisher and body.name.find(species) >= 0 or body.get_class().find("MeshInstance3D") >= 0:
		_publisher.report(species, 1, true)
