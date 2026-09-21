## Loads static data: challenges, items, skills, regions.
extends Node

var challenges: Array = []          # Array[Dictionary]
var challenges_by_id: Dictionary = {}
var items: Dictionary = {}          # id -> item def
var skills: Dictionary = {}         # id -> skill def
var regions: Array = []

func _ready() -> void:
	load_all()

func load_all() -> void:
	challenges = _load_json_array("res://data/challenges/la.json")
	challenges_by_id.clear()
	for c in challenges:
		challenges_by_id[c["id"]] = c
	items = _load_json_dict("res://data/items.json")
	skills = _load_json_dict("res://data/skills.json")
	regions = _load_json_array("res://data/regions.json")

func get_challenge(id: String) -> Dictionary:
	return challenges_by_id.get(id, {})

func _load_json_array(path: String) -> Array:
	var v = _load_json(path)
	return v if v is Array else []

func _load_json_dict(path: String) -> Dictionary:
	var v = _load_json(path)
	return v if v is Dictionary else {}

func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_warning("Data file missing: %s" % path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	var txt := f.get_as_text()
	f.close()
	var json := JSON.new()
	var err := json.parse(txt)
	if err != OK:
		push_error("JSON parse error in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data
