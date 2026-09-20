## Pure eating-challenge simulation. No nodes, no rendering; deterministic given inputs.
## The minigame scene drives this with tick(delta) and player actions, and reads state to render.
class_name EatingSim
extends RefCounted

enum Phase { IDLE, PICKING, CHEWING }
enum Result { NONE, WON, TIMEOUT, VOMITED, QUIT }

## In-game seconds per real second. A "30 minute" challenge lasts 180 real seconds.
const TIME_SCALE := 10.0
## Base stomach capacity in grams: eating this much at a calm pace fills the bar to 100.
const BASE_CAPACITY_G := 2000.0
const BASE_PICKUP_TIME := 0.8      # seconds to pick up a bite (bare hands)
const BASE_CHEW_RATE := 30.0       # grams chewed per second
const COMFORT_RATE := 12.0         # g/s: eating faster than this multiplies fullness gain
const PACE_WINDOW := 12.0          # seconds of history used for pace
const PACE_MAX_MULT := 2.2         # fullness gain multiplier at extreme pace
const PAUSE_SETTLE_TIME := 3.0     # first N seconds of a pause: fullness settles (drops)
const SETTLE_RATE := 1.6           # fullness per second lost while settling
const BLOAT_RATE := 0.9            # fullness per second gained after pausing too long
const VOMIT_OVERSHOOT := 3.0       # chewing past max by this much → vomit

const BARE_HANDS_BITE := {
	"solid": 45.0, "pieces": 40.0, "noodles": 15.0, "soup": 8.0,
	"pizza": 50.0, "sandwich": 50.0, "rice": 20.0, "other": 30.0,
}
## Grams per clickable piece by food type (generates the plate layout).
const PIECE_GRAMS := {
	"solid": 130.0, "pieces": 90.0, "noodles": 120.0, "soup": 180.0,
	"pizza": 220.0, "sandwich": 250.0, "rice": 150.0, "other": 160.0,
}

# ---- configuration (set by setup)
var challenge: Dictionary = {}
var food_type: String = "solid"
var total_grams: float = 0.0
var time_limit: float = 0.0            # real seconds
var pickup_time: float = BASE_PICKUP_TIME
var chew_rate: float = BASE_CHEW_RATE
var bite_grams: float = 45.0
var max_fullness: float = 100.0
var gain_per_gram: float = 100.0 / BASE_CAPACITY_G
var fill_mult: float = 1.0              # hot sauce etc.

# ---- live state
var phase: Phase = Phase.IDLE
var result: Result = Result.NONE
var pieces: Array[float] = []           # grams remaining per piece
var eaten_grams: float = 0.0
var fullness: float = 0.0
var time_left: float = 0.0
var elapsed: float = 0.0
var phase_timer: float = 0.0
var idle_time: float = 0.0
var current_piece: int = -1
var bite_in_mouth: float = 0.0          # grams still to chew this bite
var chew_boost: float = 1.0
var chew_boost_left: float = 0.0
var soda_uses: int = 0
var max_soda_uses: int = 3
var bites_taken: int = 0
var vomit_warning: bool = false
var _history: Array = []                # [time, grams] pairs for pace

## profile: from GameState.eating_profile(); consumables_at_start: e.g. {"hot_sauce": true}
func setup(p_challenge: Dictionary, profile: Dictionary = {}, options: Dictionary = {}) -> void:
	challenge = p_challenge
	food_type = str(challenge.get("food_type", "solid"))
	if not BARE_HANDS_BITE.has(food_type):
		food_type = "other"
	total_grams = float(challenge.get("grams", 1000))
	time_limit = float(challenge.get("time_limit_min", 30)) * 60.0 / TIME_SCALE
	time_left = time_limit
	elapsed = 0.0

	pickup_time = BASE_PICKUP_TIME * float(profile.get("pickup_time_mult", 1.0))
	chew_rate = BASE_CHEW_RATE * float(profile.get("chew_rate_mult", 1.0))
	var capacity := BASE_CAPACITY_G * float(profile.get("capacity_mult", 1.0))
	gain_per_gram = 100.0 / capacity
	max_fullness = 100.0
	if profile.get("has_sweatpants", false):
		max_fullness += 10.0
	var utensil: Dictionary = profile.get("utensil", {})
	bite_grams = BARE_HANDS_BITE[food_type]
	if utensil.has("bite_grams"):
		bite_grams = float(utensil["bite_grams"].get(food_type, bite_grams))
	fill_mult = 1.0
	if options.get("hot_sauce", false):
		chew_rate *= 1.25
		fill_mult *= 1.15
	if options.get("tums", false):
		max_fullness += 15.0

	# Build plate: N pieces of roughly PIECE_GRAMS, last one takes the remainder.
	pieces.clear()
	var per := float(PIECE_GRAMS[food_type])
	var n := maxi(1, int(round(total_grams / per)))
	var each := total_grams / n
	for i in n:
		pieces.append(each)

	phase = Phase.IDLE
	result = Result.NONE
	eaten_grams = 0.0
	fullness = 0.0
	phase_timer = 0.0
	idle_time = 0.0
	current_piece = -1
	bite_in_mouth = 0.0
	chew_boost = 1.0
	chew_boost_left = 0.0
	soda_uses = 0
	bites_taken = 0
	vomit_warning = false
	_history.clear()

func is_over() -> bool:
	return result != Result.NONE

func remaining_grams() -> float:
	var s := 0.0
	for g in pieces:
		s += g
	return s

func progress() -> float:
	return clampf(eaten_grams / maxf(1.0, total_grams), 0.0, 1.0)

## Displayed clock in in-game seconds (e.g. "29:40").
func clock_seconds() -> int:
	return int(ceil(time_left * TIME_SCALE))

## Fullness gain rate multiplier from recent pace (1.0 calm .. PACE_MAX_MULT frantic).
func pace_multiplier() -> float:
	var g := 0.0
	for h in _history:
		g += h[1]
	var rate := g / PACE_WINDOW
	var over := maxf(0.0, (rate - COMFORT_RATE) / COMFORT_RATE)
	return minf(PACE_MAX_MULT, 1.0 + 0.6 * over)

## Current pace in grams / second over the window (for HUD).
func pace_rate() -> float:
	var g := 0.0
	for h in _history:
		g += h[1]
	return g / PACE_WINDOW

# ---------------------------------------------------------------- actions

## Player clicked piece `index`. Returns true if a pickup started.
func pick_up(index: int) -> bool:
	if is_over() or phase != Phase.IDLE:
		return false
	if index < 0 or index >= pieces.size() or pieces[index] <= 0.0:
		return false
	if fullness >= max_fullness:
		_finish(Result.VOMITED)
		return false
	current_piece = index
	phase = Phase.PICKING
	phase_timer = pickup_time
	idle_time = 0.0
	return true

## Index of the first non-empty piece, or -1 (used by AI/tests).
func next_piece() -> int:
	for i in pieces.size():
		if pieces[i] > 0.0:
			return i
	return -1

func use_consumable(item_id: String) -> bool:
	if is_over():
		return false
	match item_id:
		"water":
			chew_boost = 1.4
			chew_boost_left = 8.0
			fullness = minf(max_fullness, fullness + 4.0)
			return true
		"soda":
			if soda_uses >= max_soda_uses:
				return false
			soda_uses += 1
			fullness = maxf(0.0, fullness - 12.0)
			vomit_warning = fullness >= max_fullness
			return true
		"tums":
			max_fullness += 15.0
			vomit_warning = fullness >= max_fullness
			return true
	return false

func quit() -> void:
	if not is_over():
		_finish(Result.QUIT)

# ---------------------------------------------------------------- simulation

func tick(delta: float) -> void:
	if is_over():
		return
	elapsed += delta
	time_left -= delta
	if chew_boost_left > 0.0:
		chew_boost_left -= delta
		if chew_boost_left <= 0.0:
			chew_boost = 1.0
	_trim_history()

	match phase:
		Phase.IDLE:
			idle_time += delta
			if idle_time <= PAUSE_SETTLE_TIME:
				fullness = maxf(0.0, fullness - SETTLE_RATE * delta)
			else:
				fullness = minf(max_fullness, fullness + BLOAT_RATE * delta)
		Phase.PICKING:
			phase_timer -= delta
			if phase_timer <= 0.0:
				var take := minf(bite_grams, pieces[current_piece])
				pieces[current_piece] -= take
				bite_in_mouth = take
				bites_taken += 1
				phase = Phase.CHEWING
		Phase.CHEWING:
			var rate := chew_rate * chew_boost
			var chewed := minf(bite_in_mouth, rate * delta)
			bite_in_mouth -= chewed
			eaten_grams += chewed
			_history.append([elapsed, chewed])
			fullness += chewed * gain_per_gram * fill_mult * pace_multiplier()
			if fullness > max_fullness + VOMIT_OVERSHOOT:
				_finish(Result.VOMITED)
				return
			fullness = minf(fullness, max_fullness)
			if bite_in_mouth <= 0.0001:
				bite_in_mouth = 0.0
				phase = Phase.IDLE
				idle_time = 0.0
				if remaining_grams() <= 0.01:
					_finish(Result.WON)
					return
	vomit_warning = fullness >= max_fullness - 0.001
	if time_left <= 0.0:
		time_left = 0.0
		_finish(Result.TIMEOUT)

func _trim_history() -> void:
	while _history.size() > 0 and _history[0][0] < elapsed - PACE_WINDOW:
		_history.pop_front()

func _finish(r: Result) -> void:
	result = r
	phase = Phase.IDLE

func stats() -> Dictionary:
	return {
		"result": result, "won": result == Result.WON,
		"eaten_grams": eaten_grams, "total_grams": total_grams,
		"time_used": elapsed, "time_limit": time_limit,
		"bites": bites_taken, "peak_fullness": fullness,
	}
