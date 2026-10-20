extends Node
class_name ScenarioDirector

@export var bridge_path: NodePath
@export var spawner_path: NodePath

func run_reel() -> void:
	var sp = get_node_or_null(spawner_path)
	var bh = get_node_or_null(spawner_path.get_parent().get_path() + "/WildlifeBehaviour") if spawner_path else null
	if sp and sp.get_parent().has_method("trigger_crossing"):
		pass
	elif sp:
		var beh = sp.get_parent().get_node_or_null("WildlifeBehaviour")
		if beh and beh.has_method("trigger_crossing"):
			beh.trigger_crossing("deer")
