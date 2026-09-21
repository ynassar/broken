class_name CharacterRig
extends Node3D
## Procedurally animated low-poly character built from Godot primitives.
##
## No AnimationPlayer: every frame a target pose (per-joint quaternion + position
## offset) is computed from the current state and blended toward with an
## exponential ease, so state changes cross-fade automatically.
##
## Joints (all Node3D pivots):  Hips > Torso > Head
##                              Torso > ArmL/ArmR (shoulder) > ElbowL/ElbowR > HandL/HandR > GripL/GripR
##                              Hips  > LegL/LegR (hip)      > KneeL/KneeR
## See README.md for the public API.

signal attack_hit                      ## Emitted at the impact frame of an `attack`.
signal state_changed(new_state: String)
signal one_shot_finished(state: String)  ## `attack` or `hit` finished and the rig returned to its base state.

const STATES: PackedStringArray = ["idle", "walk", "run", "attack", "hit", "eat", "dead", "stunned"]
const ONE_SHOTS: PackedStringArray = ["attack", "hit"]
const ATTACK_DURATION := 0.4
const ATTACK_HIT_TIME := 0.2
const HIT_DURATION := 0.3
const DEATH_FALL_TIME := 0.7
const UPPER_ARM_LEN := 0.25
const FOREARM_LEN := 0.25   ## elbow pivot -> hand centre
const DEFAULT_WALK_SPEED := 2.0
const DEFAULT_RUN_SPEED := 6.0

const ANIM_NODES: PackedStringArray = [
	"Hips", "Torso", "Head", "ArmL", "ArmR", "ElbowL", "ElbowR", "LegL", "LegR", "KneeL", "KneeR",
]
## Which mesh nodes each colour slot paints. Shins are moved to `skin` when long_pants is false.
const COLOR_GROUPS := {
	"skin": ["Skull", "Nose", "HandL", "HandR", "MaskSlot"],
	"shirt": ["Chest", "UpperArmL", "UpperArmR", "ForearmL", "ForearmR", "Hood"],
	"pants": ["Pelvis", "ThighL", "ThighR"],
	"hat": ["CapCrown", "CapBrim", "ChefBand", "ChefTop", "Headband"],
	"accent": ["FootL", "FootR", "Apron"],
}
const ACCESSORY_NODES := {
	"show_chef_hat": ["ChefBand", "ChefTop"],
	"show_apron": ["Apron"],
	"show_ski_mask": ["SkiMask", "MaskSlot"],
	"show_knife": ["Knife"],
	"show_camera": ["Camera"],
	"show_cap": ["CapCrown", "CapBrim"],
	"show_sunglasses": ["GlassL", "GlassR", "GlassBridge"],
	"show_headband": ["Headband"],
	"show_hood": ["Hood"],
}

@export_group("Colours")
@export var skin_color := Color(0.96, 0.78, 0.6):
	set(v):
		skin_color = v
		_apply_colors()
@export var shirt_color := Color(0.2, 0.55, 0.85):
	set(v):
		shirt_color = v
		_apply_colors()
@export var pants_color := Color(0.2, 0.22, 0.3):
	set(v):
		pants_color = v
		_apply_colors()
@export var hat_color := Color(0.85, 0.2, 0.2):
	set(v):
		hat_color = v
		_apply_colors()
@export var accent_color := Color(0.95, 0.95, 0.95):
	set(v):
		accent_color = v
		_apply_colors()
## False = shorts: shins use skin colour.
@export var long_pants := true:
	set(v):
		long_pants = v
		_apply_colors()

@export_group("Accessories")
@export var show_chef_hat := false:
	set(v):
		show_chef_hat = v
		_apply_accessories()
@export var show_apron := false:
	set(v):
		show_apron = v
		_apply_accessories()
@export var show_ski_mask := false:
	set(v):
		show_ski_mask = v
		_apply_accessories()
@export var show_knife := false:
	set(v):
		show_knife = v
		_apply_accessories()
@export var show_camera := false:
	set(v):
		show_camera = v
		_apply_accessories()
@export var show_cap := false:
	set(v):
		show_cap = v
		_apply_accessories()
@export var show_sunglasses := false:
	set(v):
		show_sunglasses = v
		_apply_accessories()
@export var show_headband := false:
	set(v):
		show_headband = v
		_apply_accessories()
@export var show_hood := false:
	set(v):
		show_hood = v
		_apply_accessories()

@export_group("Face")
## Eyebrow tilt in radians. Positive = angry (inner ends down), negative = worried.
@export_range(-0.8, 0.8) var brow_angle := 0.0:
	set(v):
		brow_angle = v
		_apply_face()
## Extra eyebrow height in metres (positive = raised / surprised).
@export_range(-0.05, 0.05) var brow_height := 0.0:
	set(v):
		brow_height = v
		_apply_face()

@export_group("Animation")
## When false the rig only moves when you call advance(delta) yourself (deterministic previews / tests).
@export var auto_advance := true
## Horizontal speed in m/s; scales the walk/run cycle rate. <= 0 uses a sensible default per state.
@export var move_speed := 0.0
## Global playback speed multiplier.
@export var time_scale := 1.0

var state: String = "idle":
	get:
		return _state

var _state := "idle"
var _base_state := "idle"       ## state to return to after a one-shot
var _state_t := 0.0             ## seconds in current state
var _one_shot_t := 0.0
var _hit_emitted := false
var _t := 0.0                   ## global animation clock
var _phase := 0.0               ## locomotion cycle phase (radians)
var _built := false

var _nodes := {}                ## name -> Node3D
var _rest := {}                 ## name -> rest position
var _q := {}                    ## name -> current Quaternion
var _p := {}                    ## name -> current position offset
var _tq := {}                   ## targets
var _tp := {}
var _mouth_open := 0.0
var _mouth_target := 0.0
var _brow_anim := 0.0
var _brow_anim_target := 0.0
var _blend_rate := 12.0

var _materials := {}            ## slot -> StandardMaterial3D (unique per instance)
var _mouth: Node3D
var _brow_l: Node3D
var _brow_r: Node3D
var _mouth_rest := Vector3.ZERO
var _brow_rest_l := Vector3.ZERO
var _brow_rest_r := Vector3.ZERO


func _ready() -> void:
	for n in ANIM_NODES:
		var node := get_node_or_null("%" + n) as Node3D
		if node == null:
			push_error("CharacterRig: missing joint node %s" % n)
			continue
		_nodes[n] = node
		_rest[n] = node.position
		_q[n] = Quaternion.IDENTITY
		_p[n] = Vector3.ZERO
		_tq[n] = Quaternion.IDENTITY
		_tp[n] = Vector3.ZERO
	_mouth = get_node_or_null("%Mouth") as Node3D
	_brow_l = get_node_or_null("%BrowL") as Node3D
	_brow_r = get_node_or_null("%BrowR") as Node3D
	if _mouth:
		_mouth_rest = _mouth.position
	if _brow_l and _brow_r:
		_brow_rest_l = _brow_l.position
		_brow_rest_r = _brow_r.position
	_built = true
	_apply_colors()
	_apply_accessories()
	_apply_face()
	# Snap straight into the initial pose instead of blending from T-pose.
	_compute_targets()
	_snap_to_targets()
	_apply_pose()


func _process(delta: float) -> void:
	if auto_advance:
		advance(delta)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Switch animation state. One-shots (`attack`, `hit`) play once then return to
## the previous looping state. Calling set_state("attack") again restarts it.
func set_state(new_state: String) -> void:
	if not STATES.has(new_state):
		push_warning("CharacterRig: unknown state '%s'" % new_state)
		return
	var is_one_shot := ONE_SHOTS.has(new_state)
	if new_state == _state and not is_one_shot:
		return
	if is_one_shot:
		_one_shot_t = 0.0
		_hit_emitted = false
	else:
		_base_state = new_state
	_state = new_state
	_state_t = 0.0
	state_changed.emit(new_state)


func get_state() -> String:
	return _state


## Horizontal movement speed (m/s). Scales walk/run cycle rate.
func set_move_speed(v: float) -> void:
	move_speed = maxf(v, 0.0)


## Yaw the rig root so it faces `dir` (XZ only). Godot forward is -Z.
func face_direction(dir: Vector3) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.000001:
		return
	rotation.y = atan2(-dir.x, -dir.z)


## Recolour several slots at once. Keys: skin, shirt, pants, hat, accent
## (the `_color` suffix is also accepted), plus optional `long_pants`.
func set_colors(colors: Dictionary) -> void:
	for key in colors:
		var k := String(key).trim_suffix("_color")
		var v = colors[key]
		match k:
			"skin": skin_color = v
			"shirt": shirt_color = v
			"pants": pants_color = v
			"hat": hat_color = v
			"accent": accent_color = v
			"long_pants": long_pants = bool(v)
			_: push_warning("CharacterRig.set_colors: unknown slot '%s'" % key)


func get_colors() -> Dictionary:
	return {
		"skin": skin_color, "shirt": shirt_color, "pants": pants_color,
		"hat": hat_color, "accent": accent_color, "long_pants": long_pants,
	}


## Toggle several accessories at once, e.g. {"show_cap": true, "show_knife": false}.
## Keys may omit the `show_` prefix.
func set_accessories(flags: Dictionary) -> void:
	for key in flags:
		var k := String(key)
		if not k.begins_with("show_"):
			k = "show_" + k
		if ACCESSORY_NODES.has(k):
			set(k, bool(flags[key]))
		else:
			push_warning("CharacterRig.set_accessories: unknown accessory '%s'" % key)


## Node3D inside the right (or left) hand; parent held items here.
func get_hand_node(right: bool = true) -> Node3D:
	return get_node_or_null("%GripR" if right else "%GripL") as Node3D


## Node3D above the head for name labels / speech bubbles.
func get_label_anchor() -> Node3D:
	return get_node_or_null("%LabelAnchor") as Node3D


func get_head_node() -> Node3D:
	return _nodes.get("Head")


func get_camera_node() -> Node3D:
	return get_node_or_null("%Camera") as Node3D


## Advance the animation by `delta` seconds. Called automatically from _process
## unless `auto_advance` is false.
func advance(delta: float) -> void:
	if not _built:
		return
	delta *= time_scale
	_t += delta
	_state_t += delta
	if ONE_SHOTS.has(_state):
		_one_shot_t += delta
		if _state == "attack" and not _hit_emitted and _one_shot_t >= ATTACK_HIT_TIME:
			_hit_emitted = true
			attack_hit.emit()
		var dur := ATTACK_DURATION if _state == "attack" else HIT_DURATION
		if _one_shot_t >= dur:
			var finished := _state
			_state = _base_state
			_state_t = 0.0
			one_shot_finished.emit(finished)
			state_changed.emit(_state)
	_advance_phase(delta)
	_compute_targets()
	_blend(delta)
	_apply_pose()


# ---------------------------------------------------------------------------
# Pose computation
# ---------------------------------------------------------------------------

func _advance_phase(delta: float) -> void:
	var hz := 0.0
	if _state == "walk":
		var s := move_speed if move_speed > 0.01 else DEFAULT_WALK_SPEED
		hz = clampf(s * 0.45, 0.7, 2.2)
	elif _state == "run":
		var s := move_speed if move_speed > 0.01 else DEFAULT_RUN_SPEED
		hz = clampf(s * 0.27, 1.3, 2.8)
	elif _state == "attack" or _state == "hit":
		hz = 0.0
	else:
		# decay toward a neutral phase so limbs settle when idle
		_phase = lerpf(_phase, roundf(_phase / TAU) * TAU, minf(1.0, delta * 4.0))
	_phase += delta * TAU * hz


func _rot(n: String, euler: Vector3) -> void:
	_tq[n] = Quaternion.from_euler(euler)


func _pos(n: String, offset: Vector3) -> void:
	_tp[n] = offset


func _compute_targets() -> void:
	for n in _nodes:
		_tq[n] = Quaternion.IDENTITY
		_tp[n] = Vector3.ZERO
	_mouth_target = 0.0
	_brow_anim_target = 0.0
	_blend_rate = 12.0
	match _state:
		"idle": _pose_idle()
		"walk": _pose_locomotion(false)
		"run": _pose_locomotion(true)
		"attack": _pose_attack()
		"hit": _pose_hit()
		"eat": _pose_eat()
		"dead": _pose_dead()
		"stunned": _pose_stunned()


func _pose_idle() -> void:
	var t := _t
	var breathe := sin(t * 2.2)
	_pos("Hips", Vector3(0, 0.012 * breathe, 0))
	_rot("Torso", Vector3(0.02 * breathe, 0, 0))
	_rot("Head", Vector3(-0.03 + 0.03 * sin(t * 1.3), 0.08 * sin(t * 0.7), 0))
	_rot("ArmL", Vector3(0.06 * sin(t * 2.2 + 1.0), 0, -0.14 - 0.02 * breathe))
	_rot("ArmR", Vector3(0.06 * sin(t * 2.2 + 2.0), 0, 0.14 + 0.02 * breathe))
	_rot("ElbowL", Vector3(0.18, 0, 0))
	_rot("ElbowR", Vector3(0.18, 0, 0))
	_rot("LegL", Vector3(0, 0, -0.03))
	_rot("LegR", Vector3(0, 0, 0.03))


func _pose_locomotion(running: bool) -> void:
	var p := _phase
	var leg_amp := 0.95 if running else 0.55
	var knee_amp := 1.5 if running else 0.9
	var arm_amp := 0.85 if running else 0.45
	var bob := 0.045 if running else 0.02
	var lean := -0.28 if running else -0.06
	var sl := sin(p)
	var sr := sin(p + PI)
	_rot("LegL", Vector3(leg_amp * sl, 0, -0.03))
	_rot("LegR", Vector3(leg_amp * sr, 0, 0.03))
	# knee bends during the swing-through (leg passing under the body)
	_rot("KneeL", Vector3(-knee_amp * maxf(0.0, cos(p - 0.35)) - (0.25 if running else 0.05), 0, 0))
	_rot("KneeR", Vector3(-knee_amp * maxf(0.0, cos(p + PI - 0.35)) - (0.25 if running else 0.05), 0, 0))
	_rot("ArmL", Vector3(arm_amp * sr, 0, -0.14))
	_rot("ArmR", Vector3(arm_amp * sl, 0, 0.14))
	var elbow := 1.3 if running else 0.35
	_rot("ElbowL", Vector3(elbow + 0.2 * maxf(0.0, sr), 0, 0))
	_rot("ElbowR", Vector3(elbow + 0.2 * maxf(0.0, sl), 0, 0))
	_pos("Hips", Vector3(0, bob * cos(2.0 * p) - (0.03 if running else 0.0), 0))
	_rot("Hips", Vector3(0, 0.1 * sl, 0.04 * sl))
	_rot("Torso", Vector3(lean, -0.14 * sl, -0.03 * sl))
	_rot("Head", Vector3(-lean * 0.7 + 0.02 * cos(2.0 * p), 0.06 * sl, 0))


func _pose_attack() -> void:
	_blend_rate = 30.0
	var u := clampf(_one_shot_t / ATTACK_DURATION, 0.0, 1.0)
	var arm_x: float
	var elbow: float
	var twist: float
	var lunge: float
	if u < 0.3:
		var k := u / 0.3
		arm_x = lerpf(0.0, -1.0, k)
		elbow = lerpf(0.3, 1.7, k)
		twist = lerpf(0.0, -0.4, k)
		lunge = 0.0
	elif u < 0.55:
		var k := (u - 0.3) / 0.25
		var e := 1.0 - pow(1.0 - k, 3.0)
		arm_x = lerpf(-1.0, 1.75, e)
		elbow = lerpf(1.7, 0.15, e)
		twist = lerpf(-0.4, 0.45, e)
		lunge = -0.1 * e
	else:
		var k := (u - 0.55) / 0.45
		var e := k * k
		arm_x = lerpf(1.75, 0.1, e)
		elbow = lerpf(0.15, 0.3, e)
		twist = lerpf(0.45, 0.0, e)
		lunge = -0.1 * (1.0 - e)
	_rot("ArmR", Vector3(arm_x, 0, 0.05))
	_rot("ElbowR", Vector3(elbow, 0, 0))
	_rot("ArmL", Vector3(0.5, 0, -0.3))
	_rot("ElbowL", Vector3(1.6, 0, 0))
	_rot("Torso", Vector3(-0.15, twist, 0))
	_rot("Hips", Vector3(0, twist * 0.4, 0))
	_pos("Hips", Vector3(0, -0.04, lunge))
	_rot("Head", Vector3(0.1, -twist * 0.6, 0))
	_rot("LegL", Vector3(0.35, 0, -0.08))
	_rot("LegR", Vector3(-0.3, 0, 0.08))
	_rot("KneeL", Vector3(-0.35, 0, 0))
	_rot("KneeR", Vector3(-0.15, 0, 0))
	_brow_anim_target = 0.35
	_mouth_target = 0.4 if u > 0.3 and u < 0.7 else 0.0


func _pose_hit() -> void:
	_blend_rate = 28.0
	var u := clampf(_one_shot_t / HIT_DURATION, 0.0, 1.0)
	var f := sin(u * PI)
	_rot("Torso", Vector3(0.4 * f, 0, 0.1 * f))
	_rot("Head", Vector3(0.45 * f, 0, -0.15 * f))
	_pos("Hips", Vector3(0, -0.03 * f, 0.12 * f))
	_rot("Hips", Vector3(0.1 * f, 0, 0))
	_rot("ArmL", Vector3(0.7 * f, 0, -0.6 * f - 0.1))
	_rot("ArmR", Vector3(0.7 * f, 0, 0.6 * f + 0.1))
	_rot("ElbowL", Vector3(0.8 * f + 0.2, 0, 0))
	_rot("ElbowR", Vector3(0.8 * f + 0.2, 0, 0))
	_rot("LegL", Vector3(-0.15 * f, 0, -0.1))
	_rot("LegR", Vector3(0.25 * f, 0, 0.1))
	_rot("KneeL", Vector3(-0.3 * f, 0, 0))
	_rot("KneeR", Vector3(-0.4 * f, 0, 0))
	_mouth_target = 0.8 * f
	_brow_anim_target = -0.3 * f


func _pose_eat() -> void:
	var t := _state_t
	# seated: hips drop to chair height, thighs horizontal, shins hanging
	_pos("Hips", Vector3(0, -0.4, 0))
	_rot("LegL", Vector3(1.45, 0, -0.12))
	_rot("LegR", Vector3(1.45, 0, 0.12))
	_rot("KneeL", Vector3(-1.5, 0, 0))
	_rot("KneeR", Vector3(-1.5, 0, 0))
	_rot("Torso", Vector3(-0.1, 0, 0))
	# alternate hands: each 1.6 s cycle, right hand first half, left second half
	const CYCLE := 1.6
	var cyc := fmod(t, CYCLE) / CYCLE
	var raise_r := _bite_curve(cyc * 2.0)
	var raise_l := _bite_curve((cyc - 0.5) * 2.0)
	var near_mouth := maxf(raise_r, raise_l)
	var chew := 0.5 + 0.5 * sin(t * 12.0)
	# mouth opens wide for the bite, chews in between
	_mouth_target = maxf(near_mouth * 0.9, 0.35 * chew * (1.0 - near_mouth))
	var head_e := Vector3(-0.28 - 0.06 * near_mouth + 0.03 * chew, 0.0, 0.0)
	_rot("Head", head_e)
	var head_q := Quaternion.from_euler(head_e)
	var mouth_target: Vector3 = _rest["Head"] + head_q * (_mouth_rest + Vector3(0, -0.03, -0.11))
	var rest_r := Vector3(0.24, -0.02, -0.34)
	var rest_l := Vector3(-0.24, -0.02, -0.34)
	var arc := Vector3(0, 0.05, -0.1)
	var target_r := rest_r.lerp(mouth_target + Vector3(0.02, 0, 0), raise_r) + arc * sin(raise_r * PI)
	var target_l := rest_l.lerp(mouth_target + Vector3(-0.02, 0, 0), raise_l) + arc * sin(raise_l * PI)
	_solve_arm_ik("ArmR", "ElbowR", target_r, Vector3(1.0, -0.5, 0.35))
	_solve_arm_ik("ArmL", "ElbowL", target_l, Vector3(-1.0, -0.5, 0.35))


## 0..1 bump: rise, hold at mouth, fall, rest. x outside 0..1 -> 0.
func _bite_curve(x: float) -> float:
	if x < 0.0 or x >= 1.0:
		return 0.0
	if x < 0.3:
		return smoothstep(0.0, 1.0, x / 0.3)
	if x < 0.55:
		return 1.0
	if x < 0.85:
		return 1.0 - smoothstep(0.0, 1.0, (x - 0.55) / 0.3)
	return 0.0


func _pose_dead() -> void:
	_blend_rate = 22.0
	var u := clampf(_state_t / DEATH_FALL_TIME, 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	e = e * e  # accelerate like gravity
	# fall backwards: pivot at hips; body ends up lying with the face up
	_rot("Hips", Vector3(lerpf(0.0, PI * 0.5, e), 0, 0))
	_pos("Hips", Vector3(0, lerpf(0.0, -0.69, e), lerpf(0.0, 0.1, e)))
	_rot("Torso", Vector3(0.05, 0, 0.06))
	_rot("Head", Vector3(-0.2 * e, 0.25 * e, 0.15 * e))
	_rot("ArmL", Vector3(-0.3 * e, 0, -0.9 * e - 0.1))
	_rot("ArmR", Vector3(-0.2 * e, 0, 0.6 * e + 0.1))
	_rot("ElbowL", Vector3(0.5 * e, 0, 0))
	_rot("ElbowR", Vector3(0.9 * e, 0, 0))
	_rot("LegL", Vector3(-0.15 * e, 0, -0.2 * e))
	_rot("LegR", Vector3(0.1 * e, 0, 0.12 * e))
	_rot("KneeL", Vector3(-0.35 * e, 0, 0))
	_rot("KneeR", Vector3(-0.1 * e, 0, 0))
	_mouth_target = 0.6 * e
	_brow_anim_target = -0.35 * e


func _pose_stunned() -> void:
	var t := _t
	_rot("Hips", Vector3(0.08 * sin(t * 3.7), 0, 0.12 * sin(t * 5.0)))
	_pos("Hips", Vector3(0, -0.08, 0))
	_rot("Torso", Vector3(0.05, 0.15 * sin(t * 2.5), 0.1 * sin(t * 5.0 + 0.5)))
	_rot("Head", Vector3(0.1, 0.35 * sin(t * 2.5), 0.28 * sin(t * 5.0 + 1.0)))
	_rot("ArmL", Vector3(0.25 * sin(t * 4.0), 0, -1.2 - 0.2 * sin(t * 5.0)))
	_rot("ArmR", Vector3(0.25 * sin(t * 4.0 + 1.5), 0, 1.2 + 0.2 * sin(t * 5.0)))
	_rot("ElbowL", Vector3(0.6, 0, 0))
	_rot("ElbowR", Vector3(0.6, 0, 0))
	_rot("LegL", Vector3(0.05, 0, -0.2))
	_rot("LegR", Vector3(0.05, 0, 0.2))
	_rot("KneeL", Vector3(-0.45, 0, 0))
	_rot("KneeR", Vector3(-0.45, 0, 0))
	_mouth_target = 0.5
	_brow_anim_target = 0.15 * sin(t * 5.0)


## Two-bone IK for an arm. `target` is the wanted hand centre in Torso space;
## `pole` says which way the elbow should point.
func _solve_arm_ik(arm: String, elbow: String, target: Vector3, pole: Vector3) -> void:
	var shoulder: Vector3 = _rest[arm]
	var to_target := target - shoulder
	var d := clampf(to_target.length(), 0.05, UPPER_ARM_LEN + FOREARM_LEN - 0.005)
	var dir := to_target.normalized()
	var l1 := UPPER_ARM_LEN
	var l2 := FOREARM_LEN
	var cos_elbow := (l1 * l1 + l2 * l2 - d * d) / (2.0 * l1 * l2)
	var bend := PI - acos(clampf(cos_elbow, -1.0, 1.0))
	var cos_a := (l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d)
	var a := acos(clampf(cos_a, -1.0, 1.0))
	var pp := pole - dir * pole.dot(dir)
	if pp.length_squared() < 0.000001:
		pp = Vector3.RIGHT
	pp = pp.normalized()
	var u := (dir * cos(a) + pp * sin(a)).normalized()          # upper arm direction
	var f := (dir * d - u * l1).normalized()                     # forearm direction
	var w := f - u * f.dot(u)
	if w.length_squared() < 0.000001:
		w = -pp
	w = w.normalized()
	var y_axis := -u
	var z_axis := -w
	var x_axis := y_axis.cross(z_axis).normalized()
	_tq[arm] = Basis(x_axis, y_axis, z_axis).get_rotation_quaternion()
	_tq[elbow] = Quaternion(Vector3.RIGHT, bend)


# ---------------------------------------------------------------------------
# Blending / applying
# ---------------------------------------------------------------------------

func _blend(delta: float) -> void:
	var k := 1.0 - exp(-delta * _blend_rate)
	for n in _nodes:
		_q[n] = (_q[n] as Quaternion).slerp(_tq[n], k).normalized()
		_p[n] = (_p[n] as Vector3).lerp(_tp[n], k)
	_mouth_open = lerpf(_mouth_open, _mouth_target, k)
	_brow_anim = lerpf(_brow_anim, _brow_anim_target, k)


func _snap_to_targets() -> void:
	for n in _nodes:
		_q[n] = _tq[n]
		_p[n] = _tp[n]
	_mouth_open = _mouth_target
	_brow_anim = _brow_anim_target


func _apply_pose() -> void:
	for n in _nodes:
		var node: Node3D = _nodes[n]
		node.quaternion = _q[n]
		node.position = _rest[n] + _p[n]
	if _mouth:
		_mouth.scale = Vector3(1.0 + 0.2 * _mouth_open, 1.0 + 3.5 * _mouth_open, 1.0)
		_mouth.position = _mouth_rest + Vector3(0, -0.035 * _mouth_open, 0)
	_apply_face()


func _apply_face() -> void:
	if not _built:
		return
	if _brow_l == null or _brow_r == null:
		return
	var angle := brow_angle + _brow_anim
	_brow_l.rotation = Vector3(0, 0, -angle)
	_brow_r.rotation = Vector3(0, 0, angle)
	# angry brows sit lower, worried brows sit higher
	var lift := brow_height - 0.015 * angle
	_brow_l.position = _brow_rest_l + Vector3(0, lift, 0)
	_brow_r.position = _brow_rest_r + Vector3(0, lift, 0)


func _apply_colors() -> void:
	if not _built:
		return
	var slots := {
		"skin": skin_color, "shirt": shirt_color, "pants": pants_color,
		"hat": hat_color, "accent": accent_color,
	}
	for slot in slots:
		var m: StandardMaterial3D = _materials.get(slot)
		if m == null:
			m = StandardMaterial3D.new()
			m.roughness = 0.9
			_materials[slot] = m
		m.albedo_color = slots[slot]
		for n in COLOR_GROUPS[slot]:
			_paint(n, m)
	var shin_mat: StandardMaterial3D = _materials["pants"] if long_pants else _materials["skin"]
	_paint("ShinL", shin_mat)
	_paint("ShinR", shin_mat)


func _paint(n: String, m: Material) -> void:
	var mi := get_node_or_null("%" + n) as MeshInstance3D
	if mi:
		mi.material_override = m


func _apply_accessories() -> void:
	if not _built:
		return
	for flag in ACCESSORY_NODES:
		var on: bool = get(flag)
		for n in ACCESSORY_NODES[flag]:
			var node := get_node_or_null("%" + n) as Node3D
			if node:
				node.visible = on
	# the ski mask hides the nose and brows (they would poke through)
	var nose := get_node_or_null("%Nose") as Node3D
	if nose:
		nose.visible = not show_ski_mask
	for n in ["BrowL", "BrowR"]:
		var b := get_node_or_null("%" + n) as Node3D
		if b:
			b.visible = not show_ski_mask
