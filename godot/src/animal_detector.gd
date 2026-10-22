class_name AnimalDetector
extends RefCounted

## Abstract base class for animal detectors.
## Takes a snapshot of train/camera state and environment, returns detections.


func detect(_snapshot: Dictionary) -> Array[Dictionary]:
	return []
