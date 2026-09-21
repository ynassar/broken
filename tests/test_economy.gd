extends TestBase

func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r

func test_win_pays_more_than_loss() -> void:
	var c := {"total_weight_lbs": 4.5, "meal_price_usd": 25, "cash_prize": 0}
	var w := Economy.video_result(c, true, false, 1000, 1.0, _rng(1))
	var l := Economy.video_result(c, false, false, 1000, 1.0, _rng(1))
	ok(w["money"] > l["money"], "win earns more")
	eq(l["meal_cost"], 25, "loss pays meal")
	eq(w["meal_cost"], 0, "win is free")
	ok(l["net_money"] < w["net_money"], "net")

func test_broll_and_quality_scale() -> void:
	var c := {"total_weight_lbs": 2.0}
	var a := Economy.base_views(500, 2.0, 1.0, true, false)
	var b := Economy.base_views(500, 2.0, 1.0, true, true)
	near(b / a, Economy.BROLL_MULT, 0.001, "b-roll mult")
	var q := Economy.base_views(500, 2.0, 1.5, true, false)
	near(q / a, 1.5, 0.001, "quality mult")

func test_viral_is_rare_but_happens() -> void:
	var c := {"total_weight_lbs": 3.0}
	var virals := 0
	for i in 2000:
		if Economy.video_result(c, true, false, 100, 1.0, _rng(i))["viral"]:
			virals += 1
	ok(virals > 80 and virals < 220, "viral rate ~7%% (got %d/2000)" % virals)

func test_starting_economy_progression() -> void:
	# A new channel (120 subs) beating the first LA challenge should earn enough to afford a fork within ~3 wins.
	var c: Dictionary = Data.challenges[0]
	var total := 0
	for i in 3:
		var r := Economy.video_result(c, true, false, 120 + i * 20, 1.0, _rng(100 + i))
		if not r["viral"]:
			total += r["net_money"]
	ok(total >= 30 and total <= 120, "three early wins earn a modest amount (%d)" % total)

func test_loot_and_fares() -> void:
	ok(Economy.hostile_loot(1.5, _rng(3)) > Economy.hostile_loot(1.0, _rng(3)), "b-roll owners drop more")
	eq(Economy.uber_fare(0.0), 4, "base fare")
	eq(Economy.uber_fare(500.0), 14, "fare scales with distance")
