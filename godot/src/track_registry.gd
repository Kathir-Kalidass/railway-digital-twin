class_name TrackRegistry
extends Node3D

## Lazily resolves the UP (outer) and DOWN (inner) rails for the double-track
## world. Resolution is on demand so node order in the scene does not matter.

@export var up_path: NodePath
@export var down_path: NodePath


func track(line_id: String) -> LTSTrack:
	var path := NodePath()
	if line_id == "UP":
		path = up_path
	elif line_id == "DOWN":
		path = down_path
	return get_node_or_null(path) as LTSTrack


func tracks() -> Array[LTSTrack]:
	var result: Array[LTSTrack] = []
	for id in ["UP", "DOWN"]:
		var found := track(id)
		if found != null:
			result.append(found)
	return result


func line_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for id in ["UP", "DOWN"]:
		if track(id) != null:
			result.append(id)
	return result


func length_m(line_id: String) -> float:
	var found := track(line_id)
	return found.length if found != null else 0.0


func first() -> LTSTrack:
	for id in ["UP", "DOWN"]:
		var found := track(id)
		if found != null:
			return found
	return null
