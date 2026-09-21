## Hostile restaurant owner (or rival creator). Roams the city, chases on sight, melee attacks.
class_name OwnerNPC
extends CharacterBody3D

signal died(npc: OwnerNPC)

enum State { ROAM, CHASE, ATTACK, LOST, STUNNED, DEAD }

const ROAM_SPEED := 2.6
const CHASE_SPEED := 6.4
const DETECT_RANGE := 24.0
const CLOSE_RANGE := 4.0            # detected regardless of facing
const FOV_DEG := 150.0
const ATTACK_RANGE := 1.8
const ATTACK_COOLDOWN := 1.1
const BASE_DAMAGE := 8.0
const EVADE_TIME := 6.0             # seconds out of LOS to lose the player
const REPATH_INTERVAL := 0.5

var owner_id: String = ""
var display_name: String = "Owner"
var trait_id: String = "standard"
var max_health := 100.0
var health := 100.0
var state: State = State.ROAM
var city: CityBlock
var player: Player
var rig: Node3D
var damage := BASE_DAMAGE

var _path := PackedVector3Array()
var _path_i := 0
var _repath_t := 0.0
var _lost_t := 0.0
var _attack_t := 0.0
var _stun_t := 0.0
var _roam_target := Vector3.ZERO
var _label: Label3D
var _last_seen := Vector3.ZERO
var _rng := RandomNumberGenerator.new()

@onready var visual_root: Node3D = $Visual

func _ready() -> void:
	add_to_group("hostile")
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	_rng.randomize()
	_load_visual()
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 40
	_label.pixel_size = 0.0045
	_label.outline_size = 8
	_label.position = Vector3(0, 2.25, 0)
	_label.no_depth_test = true
	add_child(_label)
	_refresh_label()
	_pick_roam_target()

func setup(p_owner_id: String, p_name: String, health_mult: float, p_trait: String, p_city: CityBlock, p_player: Player) -> void:
	owner_id = p_owner_id
	display_name = p_name
	trait_id = p_trait
	max_health = 100.0 * health_mult
	health = max_health
	city = p_city
	player = p_player
	match trait_id:
		"ski_mask": damage = BASE_DAMAGE * 1.5
		"knife": damage = BASE_DAMAGE * 1.8
		_: damage = BASE_DAMAGE

func _load_visual() -> void:
	var path := "res://assets/characters/chef_owner.tscn"
	if ResourceLoader.exists(path):
		rig = load(path).instantiate()
		visual_root.add_child(rig)
		if rig.has_method("set_colors"):
			var h := float(_rng.randf())
			rig.set_colors({"shirt_color": Color.from_hsv(h, 0.55, 0.85), "pants_color": Color.from_hsv(fmod(h + 0.4, 1.0), 0.4, 0.4)})
	else:
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.38; cm.height = 1.8
		mi.mesh = cm
		mi.position.y = 0.9
		mi.material_override = CityBlock._mat("npc_ph", Color(0.9, 0.25, 0.2))
		visual_root.add_child(mi)

func _refresh_label() -> void:
	if _label:
		_label.text = "%s\n%d/%d" % [display_name, int(ceil(health)), int(max_health)]
		_label.modulate = Color(1, 0.4, 0.3) if state in [State.CHASE, State.ATTACK] else Color(1, 0.9, 0.6)

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if state == State.STUNNED:
		_stun_t -= delta
		if _stun_t <= 0.0:
			state = State.CHASE
		_apply_gravity(delta)
		move_and_slide()
		return
	_attack_t = maxf(0.0, _attack_t - delta)
	var sees := _can_see_player()
	match state:
		State.ROAM:
			if sees:
				_enter_chase()
			else:
				_follow_path(ROAM_SPEED, delta)
				if _path_done():
					_pick_roam_target()
		State.CHASE, State.LOST:
			if sees:
				_last_seen = player.global_position
				_lost_t = 0.0
				state = State.CHASE
			else:
				_lost_t += delta
				if state == State.CHASE:
					state = State.LOST
				if _lost_t >= EVADE_TIME:
					state = State.ROAM
					Events.hostile_lost_player.emit(owner_id)
					_pick_roam_target()
					_refresh_label()
					return
			var d := global_position.distance_to(player.global_position)
			if sees and d <= ATTACK_RANGE and not player.dead:
				state = State.ATTACK
			else:
				_repath_t -= delta
				if _repath_t <= 0.0:
					_repath_t = REPATH_INTERVAL
					_set_path(_last_seen)
				# Direct steering when close and visible (paths are coarse)
				if sees and d < 6.0:
					_move_direct(player.global_position, CHASE_SPEED, delta)
				else:
					_follow_path(CHASE_SPEED, delta)
		State.ATTACK:
			var d := global_position.distance_to(player.global_position)
			velocity.x = 0; velocity.z = 0
			_face(player.global_position, delta)
			if player.dead:
				state = State.ROAM
				_pick_roam_target()
			elif d > ATTACK_RANGE * 1.3:
				state = State.CHASE
			elif _attack_t <= 0.0:
				_attack_t = ATTACK_COOLDOWN
				_anim("attack")
				player.take_damage(damage, self)
			_apply_gravity(delta)
			move_and_slide()
	_refresh_label()

func _enter_chase() -> void:
	state = State.CHASE
	_last_seen = player.global_position
	_lost_t = 0.0
	_repath_t = 0.0
	Events.hostile_spotted_player.emit(owner_id)

func _can_see_player() -> bool:
	if player == null or player.dead:
		return false
	var to := player.global_position - global_position
	var d := to.length()
	if d > DETECT_RANGE:
		return false
	if d > CLOSE_RANGE and state == State.ROAM:
		var fwd := -visual_root.global_transform.basis.z
		var ang := rad_to_deg(fwd.angle_to(Vector3(to.x, 0, to.z).normalized()))
		if ang > FOV_DEG / 2.0:
			return false
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.6, 0), player.global_position + Vector3(0, 1.4, 0), 1)
	var hit := space.intersect_ray(q)
	return hit.is_empty()

# ---------------------------------------------------------------- movement

func _pick_roam_target() -> void:
	if city == null:
		return
	_roam_target = city.random_roam_point()
	_set_path(_roam_target)

func _set_path(target: Vector3) -> void:
	if city == null:
		_path = PackedVector3Array([target])
	else:
		_path = city.find_path(global_position, target)
	_path_i = 0
	# skip the first point if it's behind us / at our feet
	if _path.size() > 1 and global_position.distance_to(_path[0]) < 1.0:
		_path_i = 1

func _path_done() -> bool:
	return _path_i >= _path.size()

func _follow_path(speed: float, delta: float) -> void:
	if _path_done():
		velocity.x = 0; velocity.z = 0
		_anim("idle")
		_apply_gravity(delta)
		move_and_slide()
		return
	var target := _path[_path_i]
	var flat := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	if flat.length() < 0.8:
		_path_i += 1
		return
	_move_direct(target, speed, delta)

func _move_direct(target: Vector3, speed: float, delta: float) -> void:
	var flat := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	var dir := flat.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_apply_gravity(delta)
	move_and_slide()
	_face(target, delta)
	_anim("run" if speed > 4.0 else "walk")
	if rig and rig.has_method("set_move_speed"):
		rig.set_move_speed(speed / 5.0)

func _face(target: Vector3, delta: float) -> void:
	var flat := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	if flat.length() > 0.05:
		var ty := atan2(-flat.x, -flat.z)
		visual_root.rotation.y = lerp_angle(visual_root.rotation.y, ty, 10.0 * delta)

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = 0.0

# ---------------------------------------------------------------- damage

func take_damage(amount: float, from: Node = null) -> void:
	if state == State.DEAD:
		return
	health = maxf(0.0, health - amount)
	_anim("hit")
	if state == State.ROAM and from == player:
		_enter_chase()
	if health <= 0.0:
		_die()
	_refresh_label()

func stun(seconds: float) -> void:
	if state == State.DEAD:
		return
	state = State.STUNNED
	_stun_t = seconds
	_anim("stunned")

func _die() -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 1
	_anim("dead")
	var loot := Economy.hostile_loot(max_health / 100.0, _rng)
	GameState.add_money(loot)
	Events.hostile_defeated.emit(owner_id, loot)
	died.emit(self)
	_label.text = "%s\nKO  +$%d" % [display_name, loot]
	await get_tree().create_timer(3.0).timeout
	queue_free()

var _cur_anim := ""
func _anim(s: String) -> void:
	if s == _cur_anim and s != "attack" and s != "hit":
		return
	_cur_anim = s
	if rig and rig.has_method("set_state"):
		rig.set_state(s)

func is_engaged() -> bool:
	return state in [State.CHASE, State.ATTACK, State.LOST]
