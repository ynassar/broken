## Minimal assertion helpers for headless tests.
class_name TestBase
extends RefCounted

var failures: Array[String] = []
var passed: int = 0
var current: String = ""

func ok(cond: bool, msg: String = "") -> void:
	if cond:
		passed += 1
	else:
		failures.append("%s: %s" % [current, msg])

func eq(a, b, msg: String = "") -> void:
	ok(a == b, "%s expected %s got %s" % [msg, str(b), str(a)])

func near(a: float, b: float, tol: float, msg: String = "") -> void:
	ok(absf(a - b) <= tol, "%s expected %s±%s got %s" % [msg, str(b), str(tol), str(a)])

func run_all() -> void:
	for m in get_method_list():
		var n: String = m["name"]
		if n.begins_with("test_"):
			current = n
			call(n)
