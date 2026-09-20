## A restaurant storefront with a challenge. Owner spawns from here when hostile.
class_name Restaurant
extends Node3D

@export var challenge_id: String = ""
const SIGN_Y := 3.75
const SIGN_Z := 4.13
var challenge: Dictionary = {}
var door: Area3D
var sign: Label3D
var owner_spawn: Vector3:
	get: return global_position + global_transform.basis.z * 4.6

func setup() -> void:
	challenge = Data.get_challenge(challenge_id)
	add_to_group("restaurant")
	var model_path := "res://assets/models/storefront.glb"
	if ResourceLoader.exists(model_path):
		var inst: Node3D = load(model_path).instantiate()
		add_child(inst)
	else:
		CityBlock._box(self, Vector3(0, 2.25, 0), Vector3(10, 4.5, 8), CityBlock._mat("store", Color(0.95, 0.6, 0.35)))
		CityBlock._box(self, Vector3(0, 3.4, 4.05), Vector3(6, 1.2, 0.2), CityBlock._mat("signboard", Color(0.2, 0.15, 0.1)))
	sign = Label3D.new()
	sign.text = str(challenge.get("restaurant", "Restaurant")).to_upper()
	sign.pixel_size = 0.01
	# Fit to a ~5.6 m wide sign board: approx glyph width = 0.62 * font_size * pixel_size
	sign.font_size = clampi(int(5.4 / (maxi(1, sign.text.length()) * 0.62 * sign.pixel_size)), 20, 72)
	sign.outline_size = 8
	sign.modulate = Color(1, 0.95, 0.7)
	sign.position = Vector3(0, SIGN_Y, SIGN_Z)
	add_child(sign)
	door = $Door
	door.set_meta("kind", "restaurant")
	door.set_meta("restaurant", self)
	door.set_meta("prompt", "E: %s" % challenge.get("name", "Challenge"))
	door.add_to_group("interactable")
	_refresh_state()
	Events.challenge_finished.connect(func(c, _w, _s): if c.get("id", "") == challenge_id: _refresh_state())

func _refresh_state() -> void:
	if GameState.is_completed(challenge_id):
		sign.modulate = Color(0.6, 1.0, 0.6)
		door.set_meta("prompt", "E: %s (COMPLETED)" % challenge.get("name", "Challenge"))

func door_world() -> Vector3:
	return global_position + global_transform.basis.z * 7.2
