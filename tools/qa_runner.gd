## Scripted QA playthrough. Run: xvfb-run -a godot --path . --rendering-driver opengl3 -- --qa
## Drives the game through every core beat and saves screenshots to qa/.
extends Node

var main: Node3D
var shots: Array[String] = []
var log_lines: Array[String] = []

func _ready() -> void:
	main = get_parent()
	movie_mode = "--movie" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://qa"))
	_run()

func _log(s: String) -> void:
	print("[QA] ", s)
	log_lines.append(s)

var movie_mode := false
func _shot(name: String) -> void:
	if movie_mode:
		await _wait(1.2)
	await RenderingServer.frame_post_draw
	var img := main.get_viewport().get_texture().get_image()
	var path := "res://qa/%s.png" % name
	img.save_png(path)
	shots.append(path)
	_log("screenshot " + path)

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _run() -> void:
	var player: Player = main.player
	var city: CityBlock = main.city
	await _wait(0.5)
	_log("world: %d restaurants, %d pois, grid %s" % [city.restaurants.size(), city.pois.size(), str(city.grid.region.size)])
	await _shot("01_start")
	# Walk forward a bit
	player.script_move(Vector2(0, -1))
	await _wait(2.0)
	player.script_move(Vector2.ZERO)
	await _wait(0.3)
	await _shot("02_walking")
	# Teleport to first restaurant door and open dialog
	var r: Restaurant = city.restaurants[0]
	player.global_position = r.door_world() + Vector3(0, 0.2, 0)
	await _wait(0.5)
	_log("prompt at door: '%s'" % r.door.get_meta("prompt"))
	var a := player.nearest_interactable()
	assert(a != null, "restaurant door should be interactable")
	main._on_interact(a)
	await _wait(0.3)
	await _shot("03_challenge_dialog")
	var dlg: ChallengeDialog = main.find_child("*", true, false) if false else null
	for c in main.get_children():
		if c is ChallengeDialog:
			dlg = c
	assert(dlg != null, "dialog open")
	dlg.force_broll(true)
	dlg._on_start()
	await _wait(0.5)
	await _shot("04_eating_start")
	var mg: EatingMinigame = main.minigame
	# Eat like a reckless player for a while
	if movie_mode:
		Engine.time_scale = 4.0
	var t := 0.0
	while not mg.sim.is_over() and t < 8.0:
		if mg.sim.phase == EatingSim.Phase.IDLE:
			var i := mg.sim.next_piece()
			if i >= 0: mg.sim.pick_up(i)
		await get_tree().process_frame
		t += get_process_delta_time()
	await _shot("05_eating_mid")
	_log("mid-eat: fullness %.1f, eaten %.0f/%.0f, pace x%.2f" % [mg.sim.fullness, mg.sim.eaten_grams, mg.sim.total_grams, mg.sim.pace_multiplier()])
	# Finish with pacing
	while not mg.sim.is_over():
		if mg.sim.phase == EatingSim.Phase.IDLE:
			if mg.sim.fullness < 85.0:
				var i := mg.sim.next_piece()
				if i >= 0: mg.sim.pick_up(i)
		await get_tree().process_frame
	_log("eat result: %s" % str(mg.sim.result))
	Engine.time_scale = 1.0
	await _wait(0.2)
	await _shot("06_eating_result")
	mg._on_continue()
	await _wait(0.4)
	await _shot("07_video_result")
	_log("money $%d subs %d hostiles %s" % [GameState.money, GameState.subscribers, str(GameState.hostiles)])
	for c in main.get_children():
		if c is VideoResult:
			c.closed.emit(); c.queue_free()
	await _wait(0.8)
	await _shot("08_owner_hostile")
	var npc: OwnerNPC = main.hostiles.get(r.challenge_id)
	assert(npc != null, "owner spawned")
	_log("npc state %d hp %.0f/%.0f" % [npc.state, npc.health, npc.max_health])
	# Fight: face the npc and punch until dead
	var swings := 0
	while is_instance_valid(npc) and npc.state != OwnerNPC.State.DEAD and swings < 60:
		var to := npc.global_position - player.global_position
		to.y = 0
		if to.length() > 1.2:
			player.global_position = npc.global_position - to.normalized() * 1.0
		player.pivot.rotation.y = atan2(-to.x, -to.z)
		player.attack_cd = 0.0
		player.try_attack()
		swings += 1
		if swings == 3:
			player.global_position = npc.global_position - to.normalized() * 1.4
			await _wait(0.1)
			await _shot("09_combat")
		await _wait(0.25)
	_log("combat: swings %d, npc dead=%s, player hp %.0f, money $%d" % [swings, str(not is_instance_valid(npc) or npc.state == OwnerNPC.State.DEAD), player.health, GameState.money])
	await _shot("10_owner_ko")
	# Shop
	player.global_position = city.pois["shop"].get_meta("door_world") + Vector3(0, 0.2, 0)
	await _wait(0.4)
	var sa := player.nearest_interactable()
	assert(sa != null and sa.get_meta("kind") == "shop", "shop door interactable")
	main._on_interact(sa)
	await _wait(0.3)
	await _shot("11_shop")
	for c in main.get_children():
		if c is Shop:
			c.closed.emit(); c.queue_free()
	await _wait(0.2)
	# Death: take lethal damage
	player.take_damage(9999.0)
	await _wait(2.0)
	await _shot("12_death")
	for c in main.get_children():
		if c is DeathScreen:
			c.closed.emit(); c.queue_free()
	await _wait(0.5)
	_log("after death: pos %s money $%d inv %s" % [str(player.global_position), GameState.money, str(GameState.inventory)])
	await _shot("13_hospital_respawn")
	var f := FileAccess.open("res://qa/qa_log.txt", FileAccess.WRITE)
	f.store_string("\n".join(log_lines))
	f.close()
	_log("DONE")
	get_tree().quit(0)
