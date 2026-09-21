## Procedural city block generator + walkability grid (AStarGrid2D) for NPC pathing.
## Layout: BLOCKS_X x BLOCKS_Z square blocks separated by roads. Each block has lots around
## its perimeter; lots hold buildings, restaurants, or points of interest.
class_name CityBlock
extends Node3D

const BLOCK := 36.0          # block side (m)
const ROAD := 12.0           # road width incl. sidewalks (m)
const SIDEWALK := 2.5
const LOT := 12.0
const CELL := 2.0            # walkability grid cell (m)

@export var blocks_x: int = 3
@export var blocks_z: int = 3
@export var seed: int = 7

var grid: AStarGrid2D
var restaurants: Array = []          # Restaurant nodes
var pois: Dictionary = {}            # "hospital" -> Node3D etc.
var spawn_points: Array[Vector3] = []   # sidewalk points for NPC roaming
var size_x: float
var size_z: float
var _rng := RandomNumberGenerator.new()
var _models: Dictionary = {}

const RestaurantScene := preload("res://src/world/restaurant.tscn")

func _ready() -> void:
	pass

## challenge_ids: which challenges get a storefront (placed on lots in order).
func generate(challenge_ids: Array) -> void:
	_rng.seed = seed
	size_x = blocks_x * BLOCK + (blocks_x + 1) * ROAD
	size_z = blocks_z * BLOCK + (blocks_z + 1) * ROAD
	_build_ground()
	var lots := _collect_lots()
	# Reserve special lots: hospital in the centre block, shop nearby.
	var special := _assign_special_lots(lots)
	var ci := 0
	for lot in lots:
		if special.has(lot["key"]):
			_place_poi(lot, special[lot["key"]])
		elif ci < challenge_ids.size() and lot["kind"] == "front":
			_place_restaurant(lot, challenge_ids[ci])
			ci += 1
		else:
			_place_building(lot)
	_build_props()
	_build_grid()

# ---------------------------------------------------------------- ground / roads

func _build_ground() -> void:
	# Base plane (asphalt), sidewalks raised per block.
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size_x + 40, size_z + 40)
	ground.mesh = pm
	ground.material_override = _mat("asphalt", Color(0.16, 0.16, 0.17))
	ground.position = Vector3(size_x / 2, 0, size_z / 2)
	add_child(ground)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size_x + 40, 1, size_z + 40)
	cs.shape = box
	cs.position = Vector3(size_x / 2, -0.5, size_z / 2)
	body.add_child(cs)
	add_child(body)
	# Sidewalk slabs around each block.
	for bx in blocks_x:
		for bz in blocks_z:
			var o := _block_origin(bx, bz)
			var slab := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(BLOCK + 2 * SIDEWALK, 0.15, BLOCK + 2 * SIDEWALK)
			slab.mesh = bm
			slab.material_override = _mat("concrete", Color(0.66, 0.65, 0.62))
			slab.position = Vector3(o.x + BLOCK / 2, 0.075, o.z + BLOCK / 2)
			add_child(slab)
	# Lane markings (thin quads) down each road centre.
	for i in blocks_x + 1:
		var x := i * (BLOCK + ROAD) + ROAD / 2
		_lane(Vector3(x, 0.01, size_z / 2), Vector3(0.2, 0.02, size_z), true)
	for j in blocks_z + 1:
		var z := j * (BLOCK + ROAD) + ROAD / 2
		_lane(Vector3(size_x / 2, 0.01, z), Vector3(size_x, 0.02, 0.2), false)

func _lane(pos: Vector3, size: Vector3, vertical: bool) -> void:
	var count := int((size.z if vertical else size.x) / 4.0)
	for k in count:
		if k % 2 == 1:
			continue
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.2, 0.02, 2.4) if vertical else Vector3(2.4, 0.02, 0.2)
		m.mesh = bm
		m.material_override = _mat("paint", Color(0.95, 0.85, 0.3))
		var start := pos - (Vector3(0, 0, size.z / 2) if vertical else Vector3(size.x / 2, 0, 0))
		m.position = start + (Vector3(0, 0, k * 4.0 + 2.0) if vertical else Vector3(k * 4.0 + 2.0, 0, 0))
		add_child(m)

func _block_origin(bx: int, bz: int) -> Vector3:
	return Vector3(ROAD + bx * (BLOCK + ROAD), 0, ROAD + bz * (BLOCK + ROAD))

# ---------------------------------------------------------------- lots

## Each block: 3 lots on the N edge (facing -Z), 3 on S (facing +Z), 1 on E, 1 on W.
func _collect_lots() -> Array:
	var lots := []
	for bx in blocks_x:
		for bz in blocks_z:
			var o := _block_origin(bx, bz)
			for i in 3:
				var cx := o.x + LOT / 2 + i * LOT
				lots.append(_lot("%d_%d_n%d" % [bx, bz, i], Vector3(cx, 0, o.z + LOT / 2), Vector3(0, 0, -1), bx, bz, "front"))
				lots.append(_lot("%d_%d_s%d" % [bx, bz, i], Vector3(cx, 0, o.z + BLOCK - LOT / 2), Vector3(0, 0, 1), bx, bz, "front"))
			lots.append(_lot("%d_%d_w" % [bx, bz], Vector3(o.x + LOT / 2, 0, o.z + BLOCK / 2), Vector3(-1, 0, 0), bx, bz, "front"))
			lots.append(_lot("%d_%d_e" % [bx, bz], Vector3(o.x + BLOCK - LOT / 2, 0, o.z + BLOCK / 2), Vector3(1, 0, 0), bx, bz, "front"))
	# Shuffle deterministically so restaurants spread out, but keep a stable order.
	var order := []
	for l in lots:
		order.append(l)
	for i in range(order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = order[i]; order[i] = order[j]; order[j] = t
	return order

func _lot(key: String, center: Vector3, facing: Vector3, bx: int, bz: int, kind: String) -> Dictionary:
	return {"key": key, "center": center, "facing": facing, "bx": bx, "bz": bz, "kind": kind}

func _assign_special_lots(lots: Array) -> Dictionary:
	var special := {}
	var cbx := blocks_x / 2
	var cbz := blocks_z / 2
	special["%d_%d_s1" % [cbx, cbz]] = "hospital"
	special["%d_%d_n1" % [cbx, cbz]] = "shop"
	return special

# ---------------------------------------------------------------- placement

func _place_restaurant(lot: Dictionary, challenge_id: String) -> void:
	var r := RestaurantScene.instantiate()
	r.challenge_id = challenge_id
	add_child(r)
	r.position = lot["center"]
	r.look_at_from_position(lot["center"], lot["center"] + lot["facing"], Vector3.UP)
	# look_at makes -Z face the target; our storefront faces +Z, so flip.
	r.rotate_y(PI)
	r.setup()
	_add_lot_collision(lot, 4.5)
	restaurants.append(r)

func _place_poi(lot: Dictionary, kind: String) -> void:
	var node := Node3D.new()
	node.name = kind
	add_child(node)
	node.position = lot["center"]
	var color := Color(0.9, 0.2, 0.2) if kind == "hospital" else Color(0.2, 0.5, 0.9)
	var h := 6.0 if kind == "hospital" else 4.5
	_box(node, Vector3(0, h / 2, 0), Vector3(LOT - 1, h, LOT - 1), _mat(kind, Color(0.92, 0.92, 0.95)))
	_box(node, Vector3(0, h + 0.6, 0) + lot["facing"] * (LOT / 2 - 0.5), Vector3(6, 1.2, 0.3) if absf(lot["facing"].z) > 0.5 else Vector3(0.3, 1.2, 6), _mat(kind + "_sign", color))
	var label := Label3D.new()
	label.text = "HOSPITAL" if kind == "hospital" else "PROGRESSION STORE"
	label.font_size = 96
	label.pixel_size = 0.01
	label.modulate = Color.WHITE
	label.outline_size = 12
	label.position = Vector3(0, h + 0.6, 0) + lot["facing"] * (LOT / 2 - 0.3)
	label.look_at_from_position(label.position, label.position - lot["facing"], Vector3.UP)
	label.rotate_y(PI)
	node.add_child(label)
	# Interaction marker at the door
	var door := Area3D.new()
	door.collision_layer = 8
	door.collision_mask = 0
	door.add_to_group("interactable")
	door.set_meta("kind", kind)
	door.set_meta("prompt", "E: Enter Hospital" if kind == "hospital" else "E: Enter Progression Store")
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 2.5
	cs.shape = s
	door.add_child(cs)
	node.add_child(door)
	door.position = lot["facing"] * (LOT / 2 + 1.5)
	node.set_meta("door_world", node.position + lot["facing"] * (LOT / 2 + 3.0))
	_add_lot_collision(lot, h)
	pois[kind] = node

func _place_building(lot: Dictionary) -> void:
	var floors := _rng.randi_range(2, 6)
	var h := floors * 3.2
	var variant := _rng.randi_range(0, 3)
	var node := Node3D.new()
	add_child(node)
	node.position = lot["center"]
	node.look_at_from_position(lot["center"], lot["center"] + lot["facing"], Vector3.UP)
	node.rotate_y(PI)
	var model := _model("building_%s" % ["a", "b", "c", "d"][variant])
	if model:
		var inst: Node3D = model.instantiate()
		node.add_child(inst)
		# generated buildings are 12x12 footprint with own height; collision uses the lot box
		h = _model_height(inst, h)
	else:
		var palette := [Color(0.85, 0.75, 0.6), Color(0.6, 0.35, 0.3), Color(0.55, 0.7, 0.8), Color(0.9, 0.85, 0.7)]
		_box(node, Vector3(0, h / 2, 0), Vector3(LOT - 0.5, h, LOT - 0.5), _mat("bld%d" % variant, palette[variant]))
	_add_lot_collision(lot, h)

func _model_height(inst: Node3D, fallback: float) -> float:
	var aabb := AABB()
	var first := true
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (m as MeshInstance3D).get_aabb()
		b = (m as Node3D).transform * b
		if first:
			aabb = b; first = false
		else:
			aabb = aabb.merge(b)
	return aabb.end.y if not first else fallback

func _add_lot_collision(lot: Dictionary, h: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(LOT - 0.2, h, LOT - 0.2)
	cs.shape = box
	cs.position = Vector3(0, h / 2, 0)
	body.add_child(cs)
	add_child(body)
	body.position = lot["center"]

func _build_props() -> void:
	# Palm trees + lamps along sidewalks at block corners and mid-edges.
	var lamp := _model("street_lamp")
	var palm := _model("palm_tree")
	for bx in blocks_x:
		for bz in blocks_z:
			var o := _block_origin(bx, bz)
			var corners := [Vector3(o.x - 1.2, 0, o.z - 1.2), Vector3(o.x + BLOCK + 1.2, 0, o.z - 1.2),
				Vector3(o.x - 1.2, 0, o.z + BLOCK + 1.2), Vector3(o.x + BLOCK + 1.2, 0, o.z + BLOCK + 1.2)]
			for i in corners.size():
				var scene := lamp if i % 2 == 0 else palm
				if scene:
					var p: Node3D = scene.instantiate()
					add_child(p)
					p.position = corners[i]
					p.position.y = 0.15
					var body := StaticBody3D.new()
					body.collision_layer = 1
					var cs := CollisionShape3D.new()
					var cyl := CylinderShape3D.new()
					cyl.radius = 0.25 if i % 2 == 0 else 0.35
					cyl.height = 3.0
					cs.shape = cyl
					cs.position.y = 1.5
					body.add_child(cs)
					p.add_child(body)
			# Roaming points: sidewalk mid-edges
			spawn_points.append(Vector3(o.x + BLOCK / 2, 0, o.z - 1.2))
			spawn_points.append(Vector3(o.x + BLOCK / 2, 0, o.z + BLOCK + 1.2))
			spawn_points.append(Vector3(o.x - 1.2, 0, o.z + BLOCK / 2))
			spawn_points.append(Vector3(o.x + BLOCK + 1.2, 0, o.z + BLOCK / 2))

# ---------------------------------------------------------------- walkability grid

func _build_grid() -> void:
	grid = AStarGrid2D.new()
	grid.region = Rect2i(0, 0, int(size_x / CELL), int(size_z / CELL))
	grid.cell_size = Vector2(CELL, CELL)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	# Block the lot area of every block (interior is unreachable anyway).
	for bx in blocks_x:
		for bz in blocks_z:
			var o := _block_origin(bx, bz)
			var x0 := int((o.x - 0.5) / CELL)
			var z0 := int((o.z - 0.5) / CELL)
			var x1 := int((o.x + BLOCK + 0.5) / CELL)
			var z1 := int((o.z + BLOCK + 0.5) / CELL)
			for x in range(x0, x1 + 1):
				for z in range(z0, z1 + 1):
					if grid.is_in_boundsv(Vector2i(x, z)):
						grid.set_point_solid(Vector2i(x, z), true)

func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(p.x / CELL), 0, grid.region.size.x - 1), clampi(int(p.z / CELL), 0, grid.region.size.y - 1))

func cell_to_world(c: Vector2i) -> Vector3:
	return Vector3(c.x * CELL + CELL / 2, 0, c.y * CELL + CELL / 2)

## Path in world space; returns [] if unreachable. Snaps solid endpoints to nearest free cell.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var a := _nearest_free(world_to_cell(from))
	var b := _nearest_free(world_to_cell(to))
	var pts := grid.get_point_path(a, b)
	var out := PackedVector3Array()
	for p in pts:
		out.append(Vector3(p.x + CELL / 2, 0, p.y + CELL / 2))
	return out

func _nearest_free(c: Vector2i) -> Vector2i:
	if not grid.is_point_solid(c):
		return c
	for r in range(1, 8):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var q := c + Vector2i(dx, dz)
				if grid.is_in_boundsv(q) and not grid.is_point_solid(q):
					return q
	return c

func random_roam_point() -> Vector3:
	return spawn_points[_rng.randi_range(0, spawn_points.size() - 1)]

func player_start() -> Vector3:
	return Vector3(ROAD / 2, 0, ROAD / 2)

func hospital_spawn() -> Vector3:
	if pois.has("hospital"):
		return pois["hospital"].get_meta("door_world")
	return player_start()

# ---------------------------------------------------------------- helpers

func _model(name: String) -> PackedScene:
	if _models.has(name):
		return _models[name]
	var path := "res://assets/models/%s.glb" % name
	var scene: PackedScene = null
	if ResourceLoader.exists(path):
		scene = load(path)
	_models[name] = scene
	return scene

static var _mats: Dictionary = {}
static func _mat(key: String, color: Color) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	_mats[key] = m
	return m

static func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi
