## Headless test runner. Run: godot --headless --path . tests/run.tscn
extends Node

const SUITES := [
	preload("res://tests/test_eating_sim.gd"),
	preload("res://tests/test_economy.gd"),
	preload("res://tests/test_game_state.gd"),
]

func _ready() -> void:
	var total_pass := 0
	var all_fail: Array[String] = []
	for s in SUITES:
		var t: TestBase = s.new()
		t.run_all()
		total_pass += t.passed
		all_fail.append_array(t.failures)
		print("%s: %d passed, %d failed" % [s.resource_path.get_file(), t.passed, t.failures.size()])
	for f in all_fail:
		print("  FAIL ", f)
	print("TOTAL: %d passed, %d failed" % [total_pass, all_fail.size()])
	get_tree().quit(1 if all_fail.size() > 0 else 0)
