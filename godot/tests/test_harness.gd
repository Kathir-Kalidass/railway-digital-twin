class_name Assert
extends RefCounted

var _failures: Array[String] = []

func ok(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append("ok failed: " + msg)

func eq(a, b, msg: String) -> void:
	if a != b:
		_failures.append("eq failed: %s (got %s, want %s)" % [msg, str(a), str(b)])

func report(name: String) -> int:
	if _failures.is_empty():
		print("PASS ", name)
		return 0
	for f in _failures:
		print("FAIL ", name, ": ", f)
	return 1
