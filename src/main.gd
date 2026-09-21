## Root scene: builds the world, wires systems, and runs the game flow
## (explore → challenge → video → hostile owners → death/respawn).
extends Node3D

const DEMO_CHALLENGES := ["la_001_orochon_ramen_special_2_spicy_ramen_challenge", "la_002_bubbaque_s_bbq_and_burgers_bubba_s_challenge",
	"la_003_oh_my_burger_omb_challenge", "la_009_saigon_brothers_4_lb_pho_challenge",
	"la_012_el_tepeyac_cafe_manuel_s_special_burrito_challenge", "la_023_fat_sal_s_deli_big_fat_fatty_challenge"]
const HOSTILE_RESPAWN_S := 90.0

const PlayerScene := preload("res://src/player/player.tscn")
const NPCScene := preload("res://src/npc/owner_npc.tscn")

var city: CityBlock
var player: Player
var hud: HUD
var minigame: EatingMinigame
var hostiles: Dictionary = {}          # owner_id -> OwnerNPC
var respawn_timers: Dictionary = {}    # owner_id -> seconds left
var in_menu := false
var qa_mode := false
var _rng := RandomNumberGenerator.new()
var _last_hit_by := ""

func _ready() -> void:
	_rng.randomize()
	qa_mode = "--qa" in OS.get_cmdline_user_args()
	if qa_mode:
		GameState.reset()
	_build_environment()
	city = CityBlock.new()
	city.name = "City"
	add_child(city)
	city.generate(DEMO_CHALLENGES)
	player = PlayerScene.instantiate()
	add_child(player)
	player.global_position = city.player_start() + Vector3(0, 0.2, 0)
	player.set_yaw(-PI * 0.75)   # look diagonally into the city
	player.interacted.connect(_on_interact)
	hud = HUD.new()
	add_child(hud)
	minigame = EatingMinigame.new()
	minigame.name = "EatingMinigame"
	minigame.position = Vector3(0, -300, 0)
	add_child(minigame)
	minigame.finished.connect(_on_challenge_finished)
	Events.player_died.connect(_on_player_died)
	Events.owner_became_hostile.connect(func(_id): hud.refresh_hunters())
	for id in GameState.hostiles:
		_spawn_hostile(id, false)
	_update_objective()
	player.set_control_enabled(true)
	if qa_mode:
		var runner: Node = load("res://tools/qa_runner.gd").new()
		runner.name = "QARunner"
		add_child(runner)

func _process(delta: float) -> void:
	for id in respawn_timers.keys():
		respawn_timers[id] -= delta
		if respawn_timers[id] <= 0.0:
			respawn_timers.erase(id)
			_spawn_hostile(id, false)

func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.35, 0.6, 0.95)
	sm.sky_horizon_color = Color(0.85, 0.85, 0.9)
	sm.ground_bottom_color = Color(0.3, 0.3, 0.3)
	sm.ground_horizon_color = Color(0.8, 0.8, 0.85)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color(0.8, 0.85, 0.95)
	e.fog_density = 0.004
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.light_energy = 1.3
	sun.light_color = Color(1, 0.96, 0.88)
	sun.shadow_enabled = not OS.has_feature("web")
	sun.directional_shadow_max_distance = 120
	add_child(sun)
	if OS.has_feature("web"):
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		e.fog_enabled = false

# ---------------------------------------------------------------- interactions

func _on_interact(area: Area3D) -> void:
	if in_menu:
		return
	match str(area.get_meta("kind", "")):
		"restaurant":
			_open_challenge(area.get_meta("restaurant"))
		"shop":
			_open_shop()
		"hospital":
			_use_hospital()

func _open_challenge(r: Restaurant) -> void:
	in_menu = true
	player.set_control_enabled(false)
	var dlg := ChallengeDialog.new()
	add_child(dlg)
	dlg.open(r.challenge)
	dlg.start_requested.connect(func(c, opts): _start_challenge(r, c, opts))
	dlg.closed.connect(_close_menu)

func _open_shop() -> void:
	in_menu = true
	player.set_control_enabled(false)
	var s := Shop.new()
	add_child(s)
	s.open()
	s.closed.connect(func(): GameState.save_game(); _close_menu())

func _use_hospital() -> void:
	if player.health < player.max_health:
		if GameState.spend(20):
			player.heal_full()
			Events.toast.emit("Patched up. -$20")
		else:
			Events.toast.emit("Can't afford treatment ($20)")
	else:
		Events.toast.emit("You're fine. Safe zone.")

func _close_menu() -> void:
	in_menu = false
	player.set_control_enabled(true)

# ---------------------------------------------------------------- challenge flow

var _current_restaurant: Restaurant
var _current_options: Dictionary = {}

func _start_challenge(r: Restaurant, c: Dictionary, opts: Dictionary) -> void:
	_current_restaurant = r
	_current_options = opts
	player.visible = false
	hud.visible = false
	minigame.start(c, opts)

func _on_challenge_finished(stats: Dictionary) -> void:
	var c := minigame.challenge
	var won: bool = stats["won"]
	var broll: bool = _current_options.get("broll", false)
	var r := Economy.video_result(c, won, broll, GameState.subscribers, GameState.production_quality(), _rng)
	GameState.add_money(r["net_money"])
	GameState.add_subscribers(r["subs"])
	GameState.videos_posted += 1
	GameState.record_challenge(c["id"], won, broll, stats["time_used"])
	Events.challenge_finished.emit(c, won, stats)
	Events.video_posted.emit(r)
	minigame.stop()
	hud.visible = true
	player.visible = true
	player.camera.current = true
	player.global_position = _current_restaurant.door_world() + Vector3(0, 0.2, 0)
	var vr := VideoResult.new()
	add_child(vr)
	vr.open(c, r)
	vr.closed.connect(func():
		if won:
			_spawn_hostile(c["id"], true)
		GameState.save_game()
		_update_objective()
		_close_menu())

func _update_objective() -> void:
	var done := 0
	for id in DEMO_CHALLENGES:
		if GameState.is_completed(id):
			done += 1
	hud.set_objective("Demo: %d/%d challenges done. Find restaurants (E at the door). Hunters: %d. Shop + Hospital in the centre block." % [done, DEMO_CHALLENGES.size(), GameState.hostiles.size()])

# ---------------------------------------------------------------- hostiles

func _spawn_hostile(owner_id: String, fresh: bool) -> OwnerNPC:
	if hostiles.has(owner_id) and is_instance_valid(hostiles[owner_id]):
		return hostiles[owner_id]
	var c := Data.get_challenge(owner_id)
	var npc: OwnerNPC = NPCScene.instantiate()
	add_child(npc)
	var region := _region_for(c.get("region", "us_west"))
	npc.setup(owner_id, str(c.get("owner_name", "Owner")), GameState.hostile_health_mult(owner_id), str(region.get("npc_trait", "standard")), city, player)
	var pos := city.random_roam_point()
	var r := _restaurant_for(owner_id)
	if fresh and r:
		pos = r.owner_spawn
	elif r and _rng.randf() < 0.5:
		pos = r.owner_spawn
	npc.global_position = pos + Vector3(0, 0.2, 0)
	npc.died.connect(_on_hostile_died)
	hostiles[owner_id] = npc
	if fresh:
		npc.call_deferred("_enter_chase")
		Events.toast.emit("%s storms out of the kitchen!" % npc.display_name)
	return npc

func _on_hostile_died(npc: OwnerNPC) -> void:
	hostiles.erase(npc.owner_id)
	respawn_timers[npc.owner_id] = HOSTILE_RESPAWN_S
	GameState.save_game()

func _restaurant_for(owner_id: String) -> Restaurant:
	for r in city.restaurants:
		if r.challenge_id == owner_id:
			return r
	return null

func _region_for(id: String) -> Dictionary:
	for r in Data.regions:
		if r.get("id", "") == id:
			return r
	return {}

# ---------------------------------------------------------------- death

func _on_player_died() -> void:
	in_menu = true
	player.set_control_enabled(false)
	var killer := ""
	var line := ""
	for id in hostiles.keys():
		var n: OwnerNPC = hostiles[id]
		if is_instance_valid(n) and n.state == OwnerNPC.State.ATTACK:
			killer = id
			line = _defeat_line(n)
			break
	var region := _region_for(GameState.current_region)
	var bill := Economy.hospital_bill(region)
	var lost: Array = []
	for id in GameState.inventory.keys():
		var def: Dictionary = Data.items.get(id, {})
		if not def.get("keep_on_death", false):
			lost.append(str(def.get("name", id)))
	await get_tree().create_timer(1.5).timeout
	var ds := DeathScreen.new()
	add_child(ds)
	ds.open(bill, line, lost)
	GameState.apply_death(bill)
	ds.closed.connect(func():
		player.revive_at(city.hospital_spawn() + Vector3(0, 0.2, 0))
		for id in hostiles.keys():
			var n: OwnerNPC = hostiles[id]
			if is_instance_valid(n) and n.state != OwnerNPC.State.DEAD:
				n.state = OwnerNPC.State.ROAM
				n._pick_roam_target()
		GameState.save_game()
		_update_objective()
		_close_menu())

func _defeat_line(n: OwnerNPC) -> String:
	match n.trait_id:
		"snowball": return "Sorry."
		"aussie": return "Get wrecked, cunt." if GameState.profanity_enabled else "Get wrecked, mate."
		_: return "That's for the free meal, %s." % ["buddy", "pal", "champ"][_rng.randi_range(0, 2)]
