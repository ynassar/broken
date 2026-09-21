# Contact-sheet renderer for generated assets.
#
#   cd <project> && xvfb-run -a -s "-screen 0 1600x900x24" \
#       ~/.local/bin/godot --path . --rendering-driver opengl3 --resolution 1600x900 \
#       -s tools/gen_assets/preview.gd [-- --sheet=assets|food|props|interior|all]
#
# Lays every .glb of a sheet out on a grid, lights it with a sun + sky, looks
# down at 35 degrees and saves qa/<sheet>_preview.png after a few frames.
extends SceneTree

const MODEL_DIR := "res://assets/models/"
const FRAMES_BEFORE_SAVE := 6

# sheet name -> [glb name filter, grid spacing (m), output png]
var SHEETS := {
	"assets": {"spacing": 16.0, "out": "qa/assets_preview.png", "cols": 8, "zoom": 1.15},
	"props": {"spacing": 7.0, "out": "qa/props_preview.png", "cols": 5, "zoom": 1.1},
	"interior": {"spacing": 1.6, "out": "qa/interior_preview.png", "cols": 3, "zoom": 1.4},
	"food": {"spacing": 0.45, "out": "qa/food_preview.png", "cols": 6, "zoom": 1.2},
	# ad-hoc close-up: -- --sheet=closeup --only=a,b,c --spacing=0.3
	"closeup": {"spacing": 1.0, "out": "qa/closeup_preview.png", "cols": 3, "zoom": 1.3},
}
var _only: Array = []
var _pitch := 35.0
const PROPS := ["street_lamp", "palm_tree", "bench", "trash_can", "hydrant", "car_sedan",
	"food_truck", "bus_stop", "hospital_sign", "billboard"]
const INTERIOR := ["table", "chair", "plate", "bowl", "tray"]

var _queue: Array = []
var _frame := 0
var _current := ""
var _scene_root: Node3D


func _initialize() -> void:
	var which := "all"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sheet="):
			which = a.substr(8)
		elif a.begins_with("--only="):
			_only = a.substr(7).split(",")
		elif a.begins_with("--spacing="):
			SHEETS["closeup"]["spacing"] = float(a.substr(10))
		elif a.begins_with("--cols="):
			SHEETS["closeup"]["cols"] = int(a.substr(7))
		elif a.begins_with("--pitch="):
			_pitch = float(a.substr(8))
	if which == "all":
		_queue = ["assets", "props", "interior", "food"]
	else:
		_queue = [which]
	get_root().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_root().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	get_root().size = Vector2i(1600, 900)
	_next_sheet()


func _files_for(sheet: String) -> Array:
	var all: Array = []
	var d := DirAccess.open(MODEL_DIR)
	if d:
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			if f.ends_with(".glb") and not f.begins_with("_"):
				all.append(f.get_basename())
			f = d.get_next()
	all.sort()
	var out: Array = []
	for n in all:
		var is_food: bool = n.begins_with("food_") and n != "food_truck"
		match sheet:
			"food":
				if is_food: out.append(n)
			"props":
				if n in PROPS: out.append(n)
			"interior":
				if n in INTERIOR: out.append(n)
			"assets":
				if not is_food: out.append(n)
			"closeup":
				if n in _only: out.append(n)
	return out


func _load_model(name: String) -> Node3D:
	var path := MODEL_DIR + name + ".glb"
	var res = load(path)
	if res is PackedScene:
		return res.instantiate()
	# fallback: parse the glb directly (no import step)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) == OK:
		return doc.generate_scene(state)
	push_error("preview: could not load " + path)
	return Node3D.new()


func _next_sheet() -> void:
	if _scene_root:
		_scene_root.queue_free()
		_scene_root = null
	if _queue.is_empty():
		quit()
		return
	_current = _queue.pop_front()
	var cfg: Dictionary = SHEETS[_current]
	var files := _files_for(_current)
	_scene_root = Node3D.new()
	get_root().add_child(_scene_root)

	# environment
	var env := Environment.new()
	var sky := Sky.new()
	var skymat := ProceduralSkyMaterial.new()
	skymat.sky_top_color = Color(0.25, 0.5, 0.95)
	skymat.sky_horizon_color = Color(0.75, 0.85, 0.95)
	skymat.ground_bottom_color = Color(0.3, 0.3, 0.3)
	skymat.ground_horizon_color = Color(0.7, 0.75, 0.8)
	sky.sky_material = skymat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.8)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	_scene_root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 400.0
	_scene_root.add_child(sun)

	# grid
	var spacing: float = cfg["spacing"]
	var cols: int = cfg["cols"]
	var n := files.size()
	var rows := int(ceil(float(max(n, 1)) / cols))
	var w := (cols - 1) * spacing
	var dpt := (rows - 1) * spacing

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w + spacing * 3, dpt + spacing * 3)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.46, 0.4)
	ground.material_override = gm
	ground.position = Vector3(w / 2, -0.01, dpt / 2)
	_scene_root.add_child(ground)

	var i := 0
	for name in files:
		var node := _load_model(name)
		var x := (i % cols) * spacing
		var z := (i / cols) * spacing
		node.position = Vector3(x, 0, z)
		_scene_root.add_child(node)
		var lbl := Label3D.new()
		lbl.text = name
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.pixel_size = spacing * 0.0011
		lbl.font_size = 64
		lbl.outline_size = 16
		lbl.modulate = Color(1, 1, 1)
		lbl.position = Vector3(x, spacing * 0.02, z + spacing * 0.45)
		lbl.no_depth_test = true
		_scene_root.add_child(lbl)
		i += 1

	# camera looking down 35 deg at the centre of the grid
	var cam := Camera3D.new()
	cam.fov = 40.0
	var centre := Vector3(w / 2, spacing * 0.22, dpt / 2 - spacing * 0.1)
	var extent: float = max(w + spacing * 1.1, (dpt + spacing * 1.2) * 1.25)
	var dist: float = extent / (2.0 * tan(deg_to_rad(cam.fov) / 2.0) * (1600.0 / 900.0)) * cfg["zoom"]
	var pitch := deg_to_rad(_pitch)
	cam.far = 2000.0
	_scene_root.add_child(cam)
	cam.look_at_from_position(centre + Vector3(0, sin(pitch) * dist, cos(pitch) * dist), centre, Vector3.UP)
	cam.current = true
	_frame = 0
	print("preview: sheet %s with %d models" % [_current, n])


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == FRAMES_BEFORE_SAVE:
		var cfg: Dictionary = SHEETS[_current]
		var img := get_root().get_texture().get_image()
		var out: String = ProjectSettings.globalize_path("res://" + cfg["out"])
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		var err := img.save_png(out)
		print("preview: saved %s (%s)" % [out, error_string(err)])
		_next_sheet()
	return false
