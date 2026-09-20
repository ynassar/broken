## Third-person player controller: movement, camera, melee, interaction, health.
class_name Player
extends CharacterBody3D

signal interacted(area: Area3D)
signal attacked()

const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.5
const ACCEL := 14.0
const MOUSE_SENS := 0.0025
const FIST_DAMAGE := 10.0
const FIST_COOLDOWN := 0.5

@onready var pivot: Node3D = $CameraPivot
@onready var spring: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var hit_area: Area3D = $Visual/HitArea
@onready var interact_zone: Area3D = $InteractZone
@onready var visual_root: Node3D = $Visual

var rig: Node3D = null
var control_enabled := true
var max_health := 100.0
var health := 100.0
var dead := false
var attack_cd := 0.0
var yaw := 0.0
var pitch := -0.35
var _current_prompt := ""
var _last_move_dir := Vector3.FORWARD
var _external_move := Vector2.ZERO   # for QA scripting

func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4
	_load_visual()
	refresh_stats()
	pivot.rotation.y = yaw
	spring.rotation.x = pitch

func _load_visual() -> void:
	var path := "res://assets/characters/player.tscn"
	if ResourceLoader.exists(path):
		rig = load(path).instantiate()
		visual_root.add_child(rig)
	else:
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.35; cm.height = 1.8
		mi.mesh = cm
		mi.position.y = 0.9
		mi.material_override = CityBlock._mat("player_ph", Color(0.2, 0.6, 0.9))
		visual_root.add_child(mi)

func refresh_stats() -> void:
	max_health = 100.0 + 15.0 * GameState.skill_level("tough_guy")
	health = minf(health, max_health)
	if health <= 0.0 and not dead:
		health = max_health
	Events.player_health_changed.emit(health, max_health)

func set_control_enabled(v: bool) -> void:
	control_enabled = v
	if v:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		velocity = Vector3.ZERO
		_set_anim("idle")

func _unhandled_input(event: InputEvent) -> void:
	if not control_enabled or dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * MOUSE_SENS
		pitch = clampf(pitch - event.relative.y * MOUSE_SENS, -1.2, 0.5)
		pivot.rotation.y = yaw
		spring.rotation.x = pitch
	if event.is_action_pressed("toggle_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("interact"):
		var a := nearest_interactable()
		if a:
			interacted.emit(a)
	if event.is_action_pressed("attack") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		try_attack()

func _physics_process(delta: float) -> void:
	attack_cd = maxf(0.0, attack_cd - delta)
	if dead:
		return
	var input := Vector2.ZERO
	if control_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if _external_move != Vector2.ZERO:
		input = _external_move
	var cam_basis := pivot.global_transform.basis
	var dir := (cam_basis.x * input.x + cam_basis.z * input.y)
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
	var sprint := control_enabled and Input.is_action_pressed("sprint")
	var speed := SPRINT_SPEED if sprint else WALK_SPEED
	var target := dir * speed
	velocity.x = move_toward(velocity.x, target.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCEL * delta)
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	if dir != Vector3.ZERO:
		_last_move_dir = dir
		var target_yaw := atan2(-dir.x, -dir.z)
		visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_yaw, 12.0 * delta)
		_set_anim("run" if sprint else "walk")
		_set_speed(speed / WALK_SPEED)
	else:
		_set_anim("idle")
	_update_prompt()

func _update_prompt() -> void:
	var a := nearest_interactable()
	var p := ""
	if a and control_enabled:
		p = str(a.get_meta("prompt", "E: Interact"))
	if p != _current_prompt:
		_current_prompt = p
		Events.prompt_changed.emit(p)

func nearest_interactable() -> Area3D:
	var best: Area3D = null
	var best_d := INF
	for a in interact_zone.get_overlapping_areas():
		if not a.is_in_group("interactable"):
			continue
		var d := global_position.distance_to(a.global_position)
		if d < best_d:
			best_d = d
			best = a
	return best

# ---------------------------------------------------------------- combat

func attack_damage() -> float:
	var w: Dictionary = Data.items.get(GameState.weapon, {})
	if w.has("damage"):
		return float(w["damage"])
	return FIST_DAMAGE + 4.0 * GameState.skill_level("haymaker")

func attack_cooldown() -> float:
	var w: Dictionary = Data.items.get(GameState.weapon, {})
	return float(w.get("attack_cooldown", FIST_COOLDOWN))

func try_attack() -> bool:
	if attack_cd > 0.0 or dead:
		return false
	attack_cd = attack_cooldown()
	_set_anim("attack")
	attacked.emit()
	# Face the camera forward direction when swinging
	var fwd := -pivot.global_transform.basis.z
	fwd.y = 0
	if fwd.length() > 0.01:
		visual_root.rotation.y = atan2(-fwd.x, -fwd.z)
	var dmg := attack_damage()
	var hit_any := false
	for b in hit_area.get_overlapping_bodies():
		if b.is_in_group("hostile") and b.has_method("take_damage"):
			b.take_damage(dmg, self)
			hit_any = true
	return hit_any

func take_damage(amount: float, _from: Node = null) -> void:
	if dead:
		return
	health = maxf(0.0, health - amount)
	Events.player_health_changed.emit(health, max_health)
	_set_anim("hit")
	if health <= 0.0:
		die()

func die() -> void:
	if dead:
		return
	dead = true
	velocity = Vector3.ZERO
	_set_anim("dead")
	Events.player_died.emit()

func revive_at(pos: Vector3) -> void:
	dead = false
	global_position = pos
	health = max_health
	Events.player_health_changed.emit(health, max_health)
	_set_anim("idle")

func heal_full() -> void:
	health = max_health
	Events.player_health_changed.emit(health, max_health)

# ---------------------------------------------------------------- visuals

var _anim := ""
func _set_anim(s: String) -> void:
	if s == _anim and s != "attack" and s != "hit":
		return
	_anim = s
	if rig and rig.has_method("set_state"):
		rig.set_state(s)

func _set_speed(v: float) -> void:
	if rig and rig.has_method("set_move_speed"):
		rig.set_move_speed(v)

func set_yaw(v: float) -> void:
	yaw = v
	pivot.rotation.y = yaw
	visual_root.rotation.y = yaw

## QA/scripting: move as if the stick were held (Vector2.ZERO to release).
func script_move(v: Vector2) -> void:
	_external_move = v

func facing() -> Vector3:
	return _last_move_dir
