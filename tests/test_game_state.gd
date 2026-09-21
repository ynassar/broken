extends TestBase

func test_buy_and_death() -> void:
	GameState.reset()
	GameState.money = 1000
	ok(GameState.buy_item("fork"), "buy fork")
	eq(GameState.utensil, "fork", "fork equipped")
	ok(GameState.buy_item("bat"), "buy bat")
	ok(GameState.buy_item("soda"), "buy soda")
	ok(GameState.buy_item("soda"), "buy soda x2")
	eq(GameState.item_count("soda"), 2, "two sodas")
	ok(not GameState.buy_item("fork"), "cannot buy gear twice")
	eq(GameState.money, 1000 - 40 - 200 - 30, "money deducted")
	GameState.apply_death(150)
	eq(GameState.item_count("soda"), 0, "consumables lost")
	eq(GameState.weapon, "", "weapon lost")
	eq(GameState.utensil, "fork", "fork kept (keep_on_death)")
	eq(GameState.money, 1000 - 40 - 200 - 30 - 150, "hospital bill paid")

func test_skills_and_profile() -> void:
	GameState.reset()
	GameState.money = 10000
	ok(GameState.buy_skill("quick_hands"), "skill 1")
	ok(GameState.buy_skill("quick_hands"), "skill 2")
	eq(GameState.skill_level("quick_hands"), 2, "level 2")
	eq(GameState.skill_price("quick_hands"), 360, "price scales")
	var p := GameState.eating_profile()
	near(p["pickup_time_mult"], 0.8, 0.001, "profile pickup")
	GameState.apply_death(100)
	eq(GameState.skill_level("quick_hands"), 2, "skills survive death")

func test_hostiles_and_broll() -> void:
	GameState.reset()
	GameState.record_challenge("la_001", true, true, 100.0)
	GameState.record_challenge("la_002", false, false, 100.0)
	eq(GameState.hostiles.size(), 1, "only wins create hostiles")
	near(GameState.hostile_health_mult("la_001"), 1.5, 0.001, "b-roll owner 150%")
	near(GameState.hostile_health_mult("la_002"), 1.0, 0.001, "default 100%")
	ok(GameState.is_completed("la_001"), "completed")
	ok(not GameState.is_completed("la_002"), "loss not completed")

func test_save_roundtrip() -> void:
	GameState.reset()
	GameState.money = 4321
	GameState.add_item("water", 3)
	var d := GameState.to_dict()
	GameState.reset()
	GameState.from_dict(d)
	eq(GameState.money, 4321, "money")
	eq(GameState.item_count("water"), 3, "items")
