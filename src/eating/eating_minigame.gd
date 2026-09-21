## 3D eating minigame: a restaurant table with clickable food pieces, driven by EatingSim.
## Instance, call start(challenge, options), listen for `finished(stats)`.
class_name EatingMinigame
extends Node3D

signal finished(stats: Dictionary)

const FOOD_LAYER := 16      # physics layer 5
const TABLE_H := 0.76

var sim := EatingSim.new()
var challenge: Dictionary = {}
var pieces_nodes: Array = []        # StaticBody3D per piece
var pieces_initial: Array[float] = []
var camera: Camera3D
var hud: CanvasLayer
var _fullness_bar: ProgressBar
var _time_label: Label
var _progress_bar: ProgressBar
var _pace_label: Label
var _phase_label: Label
var _msg_label: Label
var _cons_labels: Dictionary = {}
var _hover_index := -1
var _hover_mat: StandardMaterial3D
var _result_panel: PanelContainer
var _active := false
var _player_rig: Node3D
var _title: Label
var _stats_label: Label
var _pending_stats: Dictionary = {}

func _ready() -> void:
	_build_room()
	_build_hud()
	hud.visible = false
	set_process(false)

# ---------------------------------------------------------------- setup

func start(p_challenge: Dictionary, options: Dictionary = {}) -> void:
	challenge = p_challenge
	var layout := PlateLayout.build(challenge)
	var grams: Array = []
	for pc in layout:
		grams.append(pc["grams"])
	var opts := options.duplicate()
	opts["pieces"] = grams
	sim.setup(challenge, GameState.eating_profile(), opts)
	_spawn_pieces(layout)
	_title.text = "%s  •  %s" % [challenge.get("name", "Challenge"), challenge.get("restaurant", "")]
	_result_panel.visible = false
	_msg_label.text = ""
	_refresh_consumables()
	hud.visible = true
	camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_active = true
	set_process(true)
	if _player_rig and _player_rig.has_method("set_state"):
		_player_rig.set_state("eat")
	Events.challenge_started.emit(challenge)

func stop() -> void:
	_active = false
	set_process(false)
	hud.visible = false
	_clear_pieces()

func _spawn_pieces(layout: Array) -> void:
	_clear_pieces()
	var container_model := "plate"
	var ft := str(challenge.get("food_type", "solid"))
	if ft in ["soup", "noodles"] or challenge.get("cuisine", "") in ["ramen", "pho"]:
		container_model = "bowl"
	_set_container(container_model)
	var cab := _mesh_aabb(_container)
	_base_y = maxf(0.015, cab.end.y - (0.035 if container_model == "bowl" else 0.005))
	var base_y := TABLE_H + _base_y
	for i in layout.size():
		var pc: Dictionary = layout[i]
		var body := StaticBody3D.new()
		body.collision_layer = FOOD_LAYER
		body.collision_mask = 0
		body.set_meta("index", i)
		var mesh := _food_mesh(pc["model"])
		body.add_child(mesh)
		var cs := CollisionShape3D.new()
		var aabb := _mesh_aabb(mesh)
		var box := BoxShape3D.new()
		box.size = Vector3(maxf(aabb.size.x, 0.04), maxf(aabb.size.y, 0.03), maxf(aabb.size.z, 0.04))
		cs.shape = box
		cs.position = aabb.get_center()
		body.add_child(cs)
		$Plate.add_child(body)
		body.position = pc["pos"] + Vector3(0, base_y - TABLE_H, 0)
		body.rotation.y = pc["rot"]
		body.scale = Vector3.ONE * pc["scale"]
		pieces_nodes.append(body)
		pieces_initial.append(float(pc["grams"]))

func _clear_pieces() -> void:
	for n in pieces_nodes:
		n.queue_free()
	pieces_nodes.clear()
	pieces_initial.clear()
	_hover_index = -1

var _container: Node3D
func _set_container(model: String) -> void:
	if _container:
		_container.queue_free()
	_container = _load_model(model)
	if _container == null:
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.15 if model == "plate" else 0.12
		cyl.bottom_radius = 0.13 if model == "plate" else 0.07
		cyl.height = 0.02 if model == "plate" else 0.09
		mi.mesh = cyl
		mi.position.y = cyl.height / 2
		mi.material_override = CityBlock._mat("plate_ph", Color(0.95, 0.95, 0.92))
		_container = mi
	$Plate.add_child(_container)
	_container.position = Vector3.ZERO

func _food_mesh(model: String) -> Node3D:
	var n := _load_model(model)
	if n:
		return n
	# Placeholder: coloured blob sized for the plate
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.035; sm.height = 0.05
	mi.mesh = sm
	mi.position.y = 0.025
	var c := Color(0.85, 0.55, 0.3)
	mi.material_override = CityBlock._mat("food_ph_" + model, c)
	return mi

func _load_model(model: String) -> Node3D:
	var path := "res://assets/models/%s.glb" % model
	if ResourceLoader.exists(path):
		return load(path).instantiate()
	return null

func _mesh_aabb(n: Node3D) -> AABB:
	var aabb := AABB()
	var first := true
	if n is MeshInstance3D:
		aabb = n.transform * (n as MeshInstance3D).get_aabb()
		first = false
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (m as MeshInstance3D).get_aabb()
		# transform relative to n
		var xf: Transform3D = n.global_transform.affine_inverse() * (m as Node3D).global_transform if n.is_inside_tree() else (m as Node3D).transform
		b = xf * b
		if first:
			aabb = b; first = false
		else:
			aabb = aabb.merge(b)
	if first:
		aabb = AABB(Vector3(-0.03, 0, -0.03), Vector3(0.06, 0.05, 0.06))
	return aabb

# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	if not _active:
		return
	sim.tick(delta)
	_update_pieces()
	_update_hud()
	_update_hand(delta)
	_update_hover()
	if sim.is_over():
		_on_over()

func _unhandled_input(event: InputEvent) -> void:
	if not _active or sim.is_over():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var idx := _piece_under_mouse(event.position)
		if idx >= 0:
			sim.pick_up(idx)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("consumable_1"):
		use_consumable("water")
	elif event.is_action_pressed("consumable_2"):
		use_consumable("soda")
	elif event.is_action_pressed("consumable_3"):
		use_consumable("tums")
	elif event.is_action_pressed("pause"):
		_give_up()

func use_consumable(id: String) -> bool:
	if not GameState.has_item(id):
		Events.toast.emit("No %s left" % Data.items.get(id, {}).get("name", id))
		return false
	if sim.use_consumable(id):
		GameState.consume_item(id)
		_refresh_consumables()
		Events.toast.emit("Used %s" % Data.items[id]["name"])
		return true
	return false

func _piece_under_mouse(pos: Vector2) -> int:
	var from := camera.project_ray_origin(pos)
	var dir := camera.project_ray_normal(pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 5.0, FOOD_LAYER)
	q.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return -1
	var c = hit["collider"]
	if c and c.has_meta("index"):
		return int(c.get_meta("index"))
	return -1

func _update_hover() -> void:
	var idx := _piece_under_mouse(get_viewport().get_mouse_position())
	if idx != _hover_index:
		_set_highlight(_hover_index, false)
		_hover_index = idx
		_set_highlight(_hover_index, true)

func _set_highlight(idx: int, on: bool) -> void:
	if idx < 0 or idx >= pieces_nodes.size():
		return
	var body: Node3D = pieces_nodes[idx]
	for m in body.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if on:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(1.25, 1.2, 1.0)
			mat.emission_enabled = true
			mat.emission = Color(0.35, 0.3, 0.1)
			mat.next_pass = null
			mi.material_overlay = mat
		else:
			mi.material_overlay = null

func _update_pieces() -> void:
	for i in pieces_nodes.size():
		var body: Node3D = pieces_nodes[i]
		var g: float = sim.pieces[i]
		var init: float = pieces_initial[i]
		if g <= 0.0:
			if body.visible:
				body.visible = false
				body.collision_layer = 0
			continue
		var f := clampf(g / init, 0.0, 1.0)
		var s := lerpf(0.4, 1.0, f)
		var base_scale := 1.0
		body.scale = Vector3.ONE * s * base_scale

var _last_phase := EatingSim.Phase.IDLE
func _update_hand(_delta: float) -> void:
	# When a bite is taken, a copy of the piece flies to the mouth (just below the camera) and shrinks.
	if sim.phase == EatingSim.Phase.CHEWING and _last_phase == EatingSim.Phase.PICKING:
		_spawn_bite_proxy(sim.current_piece)
	if sim.phase == EatingSim.Phase.PICKING and sim.current_piece >= 0 and sim.current_piece < pieces_nodes.size():
		var body: Node3D = pieces_nodes[sim.current_piece]
		body.position.y = _piece_base_y() + 0.02 * sin(sim.elapsed * 30.0)
	elif _last_phase == EatingSim.Phase.PICKING and sim.current_piece >= 0 and sim.current_piece < pieces_nodes.size():
		pieces_nodes[sim.current_piece].position.y = _piece_base_y()
	_last_phase = sim.phase

func _spawn_bite_proxy(idx: int) -> void:
	if idx < 0 or idx >= pieces_nodes.size():
		return
	var src: Node3D = pieces_nodes[idx]
	var proxy := Node3D.new()
	for m in src.find_children("*", "MeshInstance3D", true, false):
		var mi := MeshInstance3D.new()
		mi.mesh = (m as MeshInstance3D).mesh
		mi.transform = src.global_transform.affine_inverse() * (m as Node3D).global_transform
		proxy.add_child(mi)
	add_child(proxy)
	proxy.global_transform = src.global_transform
	proxy.scale = src.scale * 0.6
	var mouth := camera.global_position + camera.global_transform.basis.z * -0.12 + Vector3(0, -0.10, 0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(proxy, "global_position", mouth, 0.3).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(proxy, "scale", Vector3.ONE * 0.01, 0.3).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(proxy.queue_free)

var _base_y := 0.02
func _piece_base_y() -> float:
	return _base_y

func _update_hud() -> void:
	_fullness_bar.max_value = sim.max_fullness
	_fullness_bar.value = sim.fullness
	var s := sim.clock_seconds()
	_time_label.text = "%02d:%02d" % [s / 60, s % 60]
	_time_label.modulate = Color(1, 0.4, 0.3) if s < 60 else Color.WHITE
	_progress_bar.value = sim.progress() * 100.0
	_progress_bar.get_node("Label").text = "%.2f / %.2f lb" % [sim.eaten_grams / 453.6, sim.total_grams / 453.6]
	var pm := sim.pace_multiplier()
	_pace_label.text = "Pace ×%.2f" % pm
	_pace_label.modulate = Color(0.5, 1, 0.5) if pm < 1.15 else (Color(1, 0.85, 0.3) if pm < 1.6 else Color(1, 0.4, 0.3))
	match sim.phase:
		EatingSim.Phase.IDLE:
			if sim.vomit_warning:
				_phase_label.text = "FULL! Pause to settle or use Soda (2)"
				_phase_label.modulate = Color(1, 0.3, 0.3)
			elif sim.idle_time > EatingSim.PAUSE_SETTLE_TIME:
				_phase_label.text = "Bloating... keep eating"
				_phase_label.modulate = Color(1, 0.7, 0.3)
			else:
				_phase_label.text = "Click food to eat"
				_phase_label.modulate = Color.WHITE
		EatingSim.Phase.PICKING:
			_phase_label.text = "Picking up..."
			_phase_label.modulate = Color(0.8, 0.9, 1)
		EatingSim.Phase.CHEWING:
			_phase_label.text = "Chewing %d g" % int(sim.bite_in_mouth)
			_phase_label.modulate = Color(0.9, 1, 0.8)
	var style := _fullness_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if style:
		var f := sim.fullness / sim.max_fullness
		style.bg_color = Color(0.3, 0.8, 0.4).lerp(Color(0.95, 0.25, 0.2), clampf((f - 0.5) * 2.0, 0.0, 1.0))

func _refresh_consumables() -> void:
	for id in _cons_labels.keys():
		var n := GameState.item_count(id)
		var def: Dictionary = Data.items.get(id, {})
		var key: String = {"water": "1", "soda": "2", "tums": "3"}[id]
		_cons_labels[id].text = "[%s] %s ×%d" % [key, def.get("name", id), n]
		_cons_labels[id].modulate = Color.WHITE if n > 0 else Color(0.6, 0.6, 0.6)

func _on_over() -> void:
	_active = false
	set_process(false)
	var st := sim.stats()
	_pending_stats = st
	var msg := ""
	match sim.result:
		EatingSim.Result.WON: msg = "CHALLENGE COMPLETE!\nThe meal is free. The owner is NOT happy."
		EatingSim.Result.VOMITED: msg = "YOU THREW UP.\nDisqualified. You pay for the meal."
		EatingSim.Result.TIMEOUT: msg = "TIME'S UP.\nYou pay for the meal."
		EatingSim.Result.QUIT: msg = "You gave up.\nYou pay for the meal."
	_msg_label.text = msg
	_stats_label.text = "Ate %.2f of %.2f lb in %d:%02d  •  %d bites" % [st["eaten_grams"] / 453.6, st["total_grams"] / 453.6, int(st["time_used"] * EatingSim.TIME_SCALE) / 60, int(st["time_used"] * EatingSim.TIME_SCALE) % 60, st["bites"]]
	_result_panel.visible = true
	if _player_rig and _player_rig.has_method("set_state"):
		_player_rig.set_state("idle")

func _give_up() -> void:
	sim.quit()

func _on_continue() -> void:
	_result_panel.visible = false
	finished.emit(_pending_stats)

# ---------------------------------------------------------------- room + hud construction

func _build_room() -> void:
	var floor := CityBlock._box(self, Vector3(0, -0.05, 0), Vector3(8, 0.1, 8), _tex_mat("checker_floor", Color(0.8, 0.75, 0.65)))
	CityBlock._box(self, Vector3(0, 1.5, -4), Vector3(8, 3.0, 0.1), CityBlock._mat("room_wall", Color(0.93, 0.85, 0.7)))
	CityBlock._box(self, Vector3(-4, 1.5, 0), Vector3(0.1, 3.0, 8), CityBlock._mat("room_wall", Color(0.93, 0.85, 0.7)))
	CityBlock._box(self, Vector3(4, 1.5, 0), Vector3(0.1, 3.0, 8), CityBlock._mat("room_wall2", Color(0.85, 0.5, 0.35)))
	CityBlock._box(self, Vector3(0, 3.0, 0), Vector3(8, 0.1, 8), CityBlock._mat("room_ceil", Color(0.95, 0.95, 0.95)))
	# kitchen window on the back wall
	CityBlock._box(self, Vector3(0, 1.7, -3.94), Vector3(2.4, 1.0, 0.05), CityBlock._mat("kitchen_win", Color(0.55, 0.7, 0.75)))
	# Table
	var table := _load_model("table")
	if table:
		add_child(table)
	else:
		CityBlock._box(self, Vector3(0, TABLE_H - 0.02, 0), Vector3(1.2, 0.04, 0.8), _tex_mat("wood", Color(0.55, 0.35, 0.2)))
		for dx in [-0.55, 0.55]:
			for dz in [-0.35, 0.35]:
				CityBlock._box(self, Vector3(dx, (TABLE_H - 0.04) / 2, dz), Vector3(0.06, TABLE_H - 0.04, 0.06), CityBlock._mat("table_leg", Color(0.3, 0.2, 0.12)))
	var plate := Node3D.new()
	plate.name = "Plate"
	plate.position = Vector3(0, TABLE_H, 0)
	add_child(plate)
	# Lights
	var light := OmniLight3D.new()
	light.position = Vector3(0, 2.6, 0.5)
	light.light_energy = 0.75
	light.omni_range = 7.0
	light.shadow_enabled = not OS.has_feature("web")
	add_child(light)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-2, 2.0, 2)
	fill.light_energy = 0.3
	fill.omni_range = 8.0
	add_child(fill)
	# Camera: seated player looking down at the plate
	camera = Camera3D.new()
	camera.position = Vector3(0, TABLE_H + 0.58, 0.46)
	camera.look_at_from_position(camera.position, Vector3(0, TABLE_H + 0.03, -0.02), Vector3.UP)
	camera.fov = 50
	add_child(camera)
	# Rival/owner watching from behind the counter (optional decor): player rig seated across? Skip.
	var rig_path := "res://assets/characters/chef_owner.tscn"
	if ResourceLoader.exists(rig_path):
		var chef: Node3D = load(rig_path).instantiate()
		chef.position = Vector3(1.6, 0, -3.0)
		chef.rotation.y = PI
		add_child(chef)
		if chef.has_method("set_state"):
			chef.set_state("idle")

func _tex_mat(tex: String, fallback: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var path := "res://assets/textures/%s.png" % tex
	if ResourceLoader.exists(path):
		m.albedo_texture = load(path)
		m.uv1_scale = Vector3(4, 4, 4)
	else:
		m.albedo_color = fallback
	m.roughness = 0.9
	return m

func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.layer = 5
	add_child(hud)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)

	# Top bar: title + timer + progress
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16; top.offset_right = -16; top.offset_top = 12
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_stylebox_override("panel", _panel_style(Color(0, 0, 0, 0.55)))
	root.add_child(top)
	var topv := VBoxContainer.new()
	topv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(topv)
	var toph := HBoxContainer.new()
	topv.add_child(toph)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toph.add_child(_title)
	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", 34)
	toph.add_child(_time_label)
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(0, 26)
	_progress_bar.show_percentage = false
	_progress_bar.add_theme_stylebox_override("fill", _panel_style(Color(0.95, 0.65, 0.2)))
	_progress_bar.add_theme_stylebox_override("background", _panel_style(Color(0.15, 0.15, 0.15, 0.8)))
	var pl := Label.new()
	pl.name = "Label"
	pl.set_anchors_preset(Control.PRESET_FULL_RECT)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_progress_bar.add_child(pl)
	topv.add_child(_progress_bar)

	# Left: fullness meter (vertical)
	var left := PanelContainer.new()
	left.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	left.offset_left = 16; left.offset_top = -200; left.offset_bottom = 200; left.offset_right = 140
	left.add_theme_stylebox_override("panel", _panel_style(Color(0, 0, 0, 0.55)))
	root.add_child(left)
	var lv := VBoxContainer.new()
	left.add_child(lv)
	var fl := Label.new()
	fl.text = "FULLNESS"
	fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(fl)
	_fullness_bar = ProgressBar.new()
	_fullness_bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	_fullness_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_fullness_bar.show_percentage = false
	_fullness_bar.add_theme_stylebox_override("fill", _panel_style(Color(0.3, 0.8, 0.4)))
	_fullness_bar.add_theme_stylebox_override("background", _panel_style(Color(0.15, 0.15, 0.15, 0.8)))
	lv.add_child(_fullness_bar)
	_pace_label = Label.new()
	_pace_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(_pace_label)

	# Bottom: phase text + consumables
	var bottom := PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 16; bottom.offset_right = -16; bottom.offset_bottom = -12; bottom.offset_top = -86
	bottom.add_theme_stylebox_override("panel", _panel_style(Color(0, 0, 0, 0.55)))
	root.add_child(bottom)
	var bv := VBoxContainer.new()
	bottom.add_child(bv)
	_phase_label = Label.new()
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.add_theme_font_size_override("font_size", 22)
	bv.add_child(_phase_label)
	var bh := HBoxContainer.new()
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	bh.add_theme_constant_override("separation", 30)
	bv.add_child(bh)
	for id in ["water", "soda", "tums"]:
		var l := Label.new()
		bh.add_child(l)
		_cons_labels[id] = l
	var quit := Button.new()
	quit.text = "Give up (Esc)"
	quit.pressed.connect(_give_up)
	bh.add_child(quit)

	# Result panel
	_result_panel = PanelContainer.new()
	_result_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_result_panel.offset_left = -260; _result_panel.offset_right = 260; _result_panel.offset_top = -120; _result_panel.offset_bottom = 120
	_result_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.05, 0.05, 0.08, 0.92)))
	_result_panel.visible = false
	root.add_child(_result_panel)
	var rv := VBoxContainer.new()
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	_result_panel.add_child(rv)
	_msg_label = Label.new()
	_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_label.add_theme_font_size_override("font_size", 26)
	rv.add_child(_msg_label)
	_stats_label = Label.new()
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(_stats_label)
	var cont := Button.new()
	cont.text = "Post the video"
	cont.custom_minimum_size = Vector2(200, 40)
	cont.pressed.connect(_on_continue)
	var cc := CenterContainer.new()
	cc.add_child(cont)
	rv.add_child(cc)

static func _panel_style(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.corner_radius_top_left = 8; s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8; s.corner_radius_bottom_right = 8
	s.content_margin_left = 12; s.content_margin_right = 12
	s.content_margin_top = 8; s.content_margin_bottom = 8
	return s
