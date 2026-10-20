extends Area3D
class_name DetectionBand

@export var publisher_path: NodePath
@export var species := "deer"
@export var zone := "zone1"

var _publisher: WildlifePublisher
var _collision: CollisionShape3D
var _active_animals: Dictionary[int, Area3D] = {}

func _ready() -> void:
	_publisher = get_node_or_null(publisher_path)
	_collision = CollisionShape3D.new()
	_collision.shape = BoxShape3D.new()
	_collision.shape.size = Vector3(10, 5, 20)
	add_child(_collision)
	body_entered.connect(_on_enter)
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)

func _on_enter(body: Node) -> void:
	if _publisher:
		var name_lower = body.name.to_lower()
		if name_lower.find(species.to_lower()) >= 0:
			_publisher.report(species, 1, true)

func _on_area_entered(area: Area3D) -> void:
	if not area.is_in_group("wildlife") or str(area.get_meta("species", "")) != species:
		return
	_active_animals[area.get_instance_id()] = area
	_publish_observation()

func _on_area_exited(area: Area3D) -> void:
	_active_animals.erase(area.get_instance_id())
	_publish_observation()

func _publish_observation() -> void:
	if _publisher:
		_publisher.report(species, _active_animals.size(), not _active_animals.is_empty())
