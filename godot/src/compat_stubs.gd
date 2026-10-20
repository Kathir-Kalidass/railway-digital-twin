extends Node

# Compatibility stubs for Libre-TrainSim editor/debug autoloads that were
# pruned during the Godot 4 port (jean28518.jTools: jSettings, jEssentials,
# jSaveManager; zylann.debug_draw: DebugDraw; basil.debug_labels: DebugLabel).
# Registered under those autoload names so ported scripts resolve. No-ops.

func set_fullscreen(_value = null) -> void:
	pass

func get_pzb(_a = null):
	return null

func get_sifa(_a = null):
	return null

func call_delayed(_a = null, _b = null, _c = null, _d = null, _e = null) -> void:
	pass

func remove_duplicates(a = null):
	return a if a != null else []

func get_setting(_a = null, _b = null):
	return _b

func draw_box(_a = null, _b = null, _c = null) -> void:
	pass

func draw_line_(_a = null, _b = null, _c = null) -> void:
	pass

func set_text(_a = null, _b = null) -> void:
	pass

func new(_a = null, _b = null, _c = null, _d = null):
	return Node.new()
