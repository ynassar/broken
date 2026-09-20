## Turns a challenge into clickable plate pieces: which model, how many grams, and where.
class_name PlateLayout
extends RefCounted

## Returns Array of {"model": String, "grams": float, "pos": Vector3, "rot": float, "scale": float}
static func build(challenge: Dictionary) -> Array:
	var total := float(challenge.get("grams", 1000))
	var cuisine := str(challenge.get("cuisine", "other"))
	var ft := str(challenge.get("food_type", "solid"))
	var out := []
	match cuisine:
		"burger":
			out.append(_p("food_burger", total * 0.62, Vector3(-0.06, 0, 0.0), 0.0, 1.0))
			_ring(out, "food_fries", total * 0.38, 4, Vector3(0.11, 0, 0.0), 0.06, 0.7)
		"burrito":
			var n := clampi(int(round(total / 230.0)), 4, 12)
			_line(out, "food_burrito_chunk", total, n, 0.055)
		"pizza":
			var n := clampi(int(round(total / 250.0)), 6, 16)
			_radial(out, "food_pizza_slice", total, n, 0.0, 1.0)
		"ramen", "pho", "noodles":
			out.append(_p("food_broth", total * 0.3, Vector3(0, 0.0, 0), 0.0, 1.0))
			var n := clampi(int(round(total * 0.7 / 120.0)), 4, 14)
			_ring(out, "food_noodle_clump", total * 0.7, n, Vector3.ZERO, 0.075, 0.85)
		"hotdog":
			var n := clampi(int(round(total * 0.7 / 180.0)), 3, 8)
			_line(out, "food_hotdog", total * 0.7, n, 0.075)
			_ring(out, "food_fries", total * 0.3, 3, Vector3(0, 0, 0.12), 0.05, 0.6)
		"sandwich":
			var n := clampi(int(round(total / 300.0)), 6, 16)
			_line(out, "food_sandwich_section", total, n, 0.06)
		"breakfast":
			if "omelet" in str(challenge.get("name", "")).to_lower():
				_radial(out, "food_egg_omelet_slice", total * 0.7, 8, 0.0, 1.0)
				_ring(out, "food_fries", total * 0.3, 3, Vector3(0, 0, 0.13), 0.05, 0.6)
			else:
				_ring(out, "food_pancake_stack", total, 3, Vector3.ZERO, 0.09, 1.0)
		"dessert":
			out.append(_p("food_milkshake", total * 0.6, Vector3(0, 0, 0), 0.0, 1.0))
			_ring(out, "food_dumpling", total * 0.4, 5, Vector3.ZERO, 0.12, 0.8)   # doughnuts stand-in
		"wings":
			_grid(out, "food_wing", total, clampi(int(round(total / 90.0)), 6, 24), 0.05)
		"taco":
			_grid(out, "food_taco", total, clampi(int(round(total / 120.0)), 4, 16), 0.07)
		"sushi":
			_grid(out, "food_sushi", total, clampi(int(round(total / 45.0)), 8, 30), 0.045)
		"steak":
			_ring(out, "food_steak", total, clampi(int(round(total / 450.0)), 1, 4), Vector3.ZERO, 0.1, 1.0)
		_:
			match ft:
				"noodles": _ring(out, "food_noodle_clump", total, 8, Vector3.ZERO, 0.075, 0.85)
				"soup": out.append(_p("food_broth", total, Vector3.ZERO, 0.0, 1.0))
				"rice": _ring(out, "food_rice_mound", total, 4, Vector3.ZERO, 0.07, 0.9)
				"pieces": _grid(out, "food_dumpling", total, clampi(int(round(total / 90.0)), 6, 20), 0.05)
				_: _grid(out, "food_burrito_chunk", total, clampi(int(round(total / 150.0)), 4, 16), 0.06)
	return out

static func _p(model: String, grams: float, pos: Vector3, rot: float, scale: float) -> Dictionary:
	return {"model": model, "grams": grams, "pos": pos, "rot": rot, "scale": scale}

static func _line(out: Array, model: String, total: float, n: int, spacing: float) -> void:
	var each := total / n
	var w := (n - 1) * spacing
	for i in n:
		out.append(_p(model, each, Vector3(-w / 2 + i * spacing, 0, 0), 0.0, 1.0))

static func _ring(out: Array, model: String, total: float, n: int, center: Vector3, radius: float, scale: float) -> void:
	var each := total / n
	for i in n:
		var a := TAU * i / n
		out.append(_p(model, each, center + Vector3(cos(a) * radius, 0, sin(a) * radius), -a, scale))

static func _radial(out: Array, model: String, total: float, n: int, radius: float, scale: float) -> void:
	# Slices pointing outward from the centre (pizza).
	var each := total / n
	for i in n:
		var a := TAU * i / n
		out.append(_p(model, each, Vector3(cos(a) * radius, 0, sin(a) * radius), -a + PI / 2, scale))

static func _grid(out: Array, model: String, total: float, n: int, spacing: float) -> void:
	var each := total / n
	var cols := int(ceil(sqrt(n)))
	var rows := int(ceil(float(n) / cols))
	var w := (cols - 1) * spacing
	var h := (rows - 1) * spacing
	for i in n:
		var c := i % cols
		var r := i / cols
		out.append(_p(model, each, Vector3(-w / 2 + c * spacing, 0, -h / 2 + r * spacing), 0.0, 1.0))
