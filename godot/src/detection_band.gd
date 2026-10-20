extends Area3D
class_name DetectionBand

@export var publisher_path: NodePath
@export var species := "deer"
@export var zone := "zone1"

var _publisher: WildlifePublisher
var _collision: CollisionShape3D

func _ready() -> void:
	_publisher = get_node_or_null(publisher_path)
	_collision = CollisionShape3D.new()
	_collision.shape = BoxShape3D.new()
	_collision.shape.size = Vector3(10, 5, 20)
	add_child(_collision)
	body_entered.connect(_on_enter)

func _on_enter(body: Node) -> void:
	if _publisher:
		var name_lower = body.name.to_lower()
		if name_lower.find(species.to_lower()) >= 0:
			_publisher.report(species, 1, true)
