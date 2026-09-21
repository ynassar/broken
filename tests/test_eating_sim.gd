extends TestBase

func _challenge(grams: int, food_type := "solid", minutes := 30) -> Dictionary:
	return {"id": "t", "grams": grams, "food_type": food_type, "time_limit_min": minutes}

## Drive the sim like a player who eats continuously (clicks whenever idle).
func _play_continuous(sim: EatingSim, dt := 1.0 / 60.0, max_s := 600.0) -> void:
	var t := 0.0
	while not sim.is_over() and t < max_s:
		if sim.phase == EatingSim.Phase.IDLE:
			var i := sim.next_piece()
			if i >= 0:
				sim.pick_up(i)
		sim.tick(dt)
		t += dt

## Eats but pauses `pause_s` whenever fullness passes `threshold`.
func _play_paced(sim: EatingSim, threshold: float, pause_s: float, dt := 1.0 / 60.0, max_s := 900.0) -> void:
	var t := 0.0
	var pausing := 0.0
	while not sim.is_over() and t < max_s:
		if pausing > 0.0:
			pausing -= dt
		elif sim.phase == EatingSim.Phase.IDLE:
			if sim.fullness >= threshold:
				pausing = pause_s
			else:
				var i := sim.next_piece()
				if i >= 0:
					sim.pick_up(i)
		sim.tick(dt)
		t += dt

func test_setup_builds_pieces() -> void:
	var sim := EatingSim.new()
	sim.setup(_challenge(1000, "solid"))
	eq(sim.pieces.size(), 8, "1000g solid → 8 pieces")
	near(sim.remaining_grams(), 1000.0, 0.01, "total grams preserved")
	near(sim.time_left, 180.0, 0.01, "30 min → 180 real seconds")
	eq(sim.clock_seconds(), 1800, "clock shows 30:00")

func test_small_challenge_won_continuous() -> void:
	var sim := EatingSim.new()
	sim.setup(_challenge(900, "solid", 30))
	_play_continuous(sim)
	eq(sim.result, EatingSim.Result.WON, "900g burger is winnable eating nonstop")
	ok(sim.fullness < 100.0, "did not max out fullness")
	ok(sim.elapsed < 90.0, "finished in reasonable time (%.1fs)" % sim.elapsed)

func test_big_challenge_vomits_when_reckless() -> void:
	var sim := EatingSim.new()
	sim.setup(_challenge(2600, "solid", 45))
	_play_continuous(sim)
	eq(sim.result, EatingSim.Result.VOMITED, "2.6kg nonstop → vomit")

func test_big_challenge_winnable_with_pacing() -> void:
	var sim := EatingSim.new()
	sim.setup(_challenge(2400, "solid", 45))
	_play_paced(sim, 88.0, 2.5)
	eq(sim.result, EatingSim.Result.WON, "2.4kg with short pauses → win (got %s, eaten %.0f, t=%.0f)" % [sim.result, sim.eaten_grams, sim.elapsed])

func test_pause_settles_then_bloats() -> void:
	var sim := EatingSim.new()
	sim.setup(_challenge(1000))
	sim.fullness = 50.0
	for i in 120: sim.tick(1.0 / 60.0)   # 2 s idle
	near(sim.fullness, 50.0 - 2.0 * EatingSim.SETTLE_RATE, 0.05, "settles during short pause")
	for i in 120: sim.tick(1.0 / 60.0)   # 4 s idle: 1 more s settling, 1 s bloating
	var expected := 50.0 - 3.0 * EatingSim.SETTLE_RATE + 1.0 * EatingSim.BLOAT_RATE
	near(sim.fullness, expected, 0.1, "bloats after settle window")

func test_pace_multiplier_increases_when_fast() -> void:
	var sim := EatingSim.new()
	sim.setup(_challenge(1000))
	eq(sim.pace_multiplier(), 1.0, "calm at start")
	sim._history = [[0.0, 300.0]]  # 300g in window → 25 g/s
	ok(sim.pace_multiplier() > 1.5, "fast pace multiplies fullness gain")

func test_vomit_when_picking_up_at_max() -> void:
	var sim := EatingSim.new()
	sim.setup(_challenge(1000))
	sim.fullness = sim.max_fullness
	sim.pick_up(0)
	eq(sim.result, EatingSim.Result.VOMITED, "eating at max fullness → vomit")

func test_timeout() -> void:
	var sim := EatingSim.new()
	sim.setup(_challenge(5000, "solid", 1))   # 6 real seconds
	_play_continuous(sim)
	eq(sim.result, EatingSim.Result.TIMEOUT, "ran out of time")

func test_consumables() -> void:
	var sim := EatingSim.new()
	sim.setup(_challenge(1000))
	sim.fullness = 60.0
	ok(sim.use_consumable("soda"), "soda 1")
	near(sim.fullness, 48.0, 0.01, "soda -12")
	sim.use_consumable("soda"); sim.use_consumable("soda")
	ok(not sim.use_consumable("soda"), "soda limited to 3")
	ok(sim.use_consumable("water"), "water")
	near(sim.chew_boost, 1.4, 0.01, "water boosts chew")
	sim.tick(9.0)
	near(sim.chew_boost, 1.0, 0.01, "water boost expires")
	var mf := sim.max_fullness
	sim.use_consumable("tums")
	near(sim.max_fullness, mf + 15.0, 0.01, "tums raises max")

func test_profile_modifiers() -> void:
	var sim := EatingSim.new()
	sim.setup(_challenge(1000, "noodles"), {"pickup_time_mult": 0.8, "chew_rate_mult": 1.3, "capacity_mult": 1.16, "has_sweatpants": true,
		"utensil": {"bite_grams": {"noodles": 55}}})
	near(sim.pickup_time, 0.64, 0.001, "quick hands")
	near(sim.chew_rate, 39.0, 0.001, "iron jaw")
	near(sim.bite_grams, 55.0, 0.001, "chopsticks noodle bite")
	near(sim.max_fullness, 110.0, 0.001, "sweatpants")
	near(sim.gain_per_gram, 100.0 / 2320.0, 0.00001, "big stomach")

func test_utensil_speeds_noodles() -> void:
	var bare := EatingSim.new()
	bare.setup(_challenge(1000, "noodles", 30))
	_play_continuous(bare)
	var sticks := EatingSim.new()
	sticks.setup(_challenge(1000, "noodles", 30), {"utensil": {"bite_grams": {"noodles": 55}}})
	_play_continuous(sticks)
	eq(bare.result, EatingSim.Result.WON, "bare hands ramen winnable")
	eq(sticks.result, EatingSim.Result.WON, "chopsticks ramen winnable")
	ok(sticks.elapsed < bare.elapsed * 0.6, "chopsticks much faster (%.0f vs %.0f)" % [sticks.elapsed, bare.elapsed])

func test_dataset_difficulty_curve() -> void:
	# Easiest LA challenge must be winnable with bare hands nonstop; hardest must not be.
	var data: Array = Data.challenges
	ok(data.size() >= 20, "LA dataset loaded (%d)" % data.size())
	var first := EatingSim.new()
	first.setup(data[0])
	_play_continuous(first)
	eq(first.result, EatingSim.Result.WON, "challenge 1 winnable bare-handed nonstop")
	var last := EatingSim.new()
	last.setup(data[data.size() - 1])
	_play_continuous(last)
	ok(last.result != EatingSim.Result.WON, "last challenge not winnable with no upgrades")
