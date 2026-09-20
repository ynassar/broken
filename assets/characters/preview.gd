extends Node3D
## QA preview: every character in every state, side by side. Saves
## qa/characters_preview.png after 1 s of (deterministic) simulation and
## qa/characters_preview_2.png 0.4 s later, then quits.
##
## Run: xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 assets/characters/preview.tscn

const CHARACTERS := [
	"res://assets/characters/player.tscn",
	"res://assets/characters/chef_owner.tscn",
	"res://assets/characters/rival_creator.tscn",
]
const STATES := ["idle", "walk", "run", "attack", "eat", "hit", "dead", "stunned"]
const COL_SPACING := 1.7
const ROW_SPACING := 2.4
const ROW_STAGGER := 0.6
const STEP := 1.0 / 60.0
const CAPTURE_1 := 1.0
const CAPTURE_2 := 1.4

var _rigs: Array[CharacterRig] = []
var _sim_t := 0.0
var _captured := 0
var _busy := false
var _characters: Array = CHARACTERS
var _out_prefix := "res://qa/characters_preview"


func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	# Optional user args (after `--`): --only=<row index> renders one character close up,
	# --out=<path prefix> changes where the PNGs go.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_characters = [CHARACTERS[int(arg.get_slice("=", 1))]]
		elif arg.begins_with("--out="):
			_out_prefix = arg.get_slice("=", 1)
	_build_world()
	var width := (STATES.size() - 1) * COL_SPACING
	for row in _characters.size():
		var scene: PackedScene = load(_characters[row])
		# stagger deeper rows sideways so they show between the front row
		var stagger := ROW_STAGGER * (row if row % 2 == 1 else -row)
		for col in STATES.size():
			var rig := scene.instantiate() as CharacterRig
			rig.auto_advance = false
			# camera looks along +Z, so screen-left is world +X: put column 0 at +X
			rig.position = Vector3(width * 0.5 - col * COL_SPACING + stagger, 0, row * ROW_SPACING)
			add_child(rig)
			rig.set_meta("state", STATES[col])
			rig.set_state(STATES[col])
			_rigs.append(rig)
			if row == 0:
				var label := Label3D.new()
				label.text = STATES[col]
				label.font_size = 64
				label.pixel_size = 0.004
				label.position = rig.position + Vector3(0, 2.75, -0.5)
				label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				add_child(label)


func _build_world() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.6, 0.95)
	sky_mat.sky_horizon_color = Color(0.8, 0.88, 0.95)
	sky_mat.ground_bottom_color = Color(0.3, 0.32, 0.3)
	sky_mat.ground_horizon_color = Color(0.7, 0.75, 0.7)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.42, 0.28)
	ground.material_override = gm
	add_child(ground)
	# characters face -Z, so the camera sits on the -Z side looking back at them
	var cam := Camera3D.new()
	if _characters.size() == 1:
		cam.position = Vector3(0, 1.65, -8.8)   # eye height close-up
		cam.rotation_degrees = Vector3(-4, 180, 0)
	else:
		cam.position = Vector3(0, 2.1, -9.2)
		cam.rotation_degrees = Vector3(-9, 180, 0)
	cam.fov = 50
	add_child(cam)
	cam.current = true


func _process(_delta: float) -> void:
	if _busy or _captured >= 2:
		return
	_sim_t += STEP
	# re-trigger one-shots so the captures land mid-swing / mid-flinch
	if _is_step(0.8) or _is_step(1.25):
		for rig in _rigs:
			var s: String = rig.get_meta("state")
			if s == "attack" or s == "hit":
				rig.set_state(s)
	for rig in _rigs:
		rig.advance(STEP)
	if _captured == 0 and _sim_t >= CAPTURE_1:
		_capture(_out_prefix + ".png")
	elif _captured == 1 and _sim_t >= CAPTURE_2:
		_capture(_out_prefix + "_2.png")


func _is_step(t: float) -> bool:
	return _sim_t >= t and _sim_t - STEP < t


func _capture(path: String) -> void:
	_busy = true
	_captured += 1
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var err := img.save_png(path)
	print("saved %s (%s) sim_t=%.2f" % [path, error_string(err), _sim_t])
	_busy = false
	if _captured >= 2:
		get_tree().quit()
