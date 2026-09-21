## Pre-challenge dialog: info, B-roll request (RNG), consumable prep, start/leave.
class_name ChallengeDialog
extends CanvasLayer

signal start_requested(challenge: Dictionary, options: Dictionary)
signal closed()

var challenge: Dictionary = {}
var broll_asked := false
var broll_success := false
var options := {}
var _broll_btn: Button
var _broll_label: Label
var _sauce_check: CheckBox
var _tums_check: CheckBox
var _panel: PanelContainer
var _start_btn: Button
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	layer = 6
	_rng.randomize()

func open(c: Dictionary) -> void:
	challenge = c
	broll_asked = false
	broll_success = false
	options = {}
	for ch in get_children():
		ch.queue_free()
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UITheme.panel())
	_panel.custom_minimum_size = Vector2(620, 0)
	add_child(UITheme.centered(_panel))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)
	v.add_child(UITheme.label(str(c.get("name", "")), 26, Color(1, 0.85, 0.4)))
	v.add_child(UITheme.label("%s — %s" % [c.get("restaurant", ""), c.get("city", "")], 15, Color(0.8, 0.8, 0.8)))
	var d := UITheme.label(str(c.get("description", "")), 15)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD
	d.custom_minimum_size.x = 580
	v.add_child(d)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	v.add_child(grid)
	_row(grid, "Weight", "%.2f lb (%d g)" % [c.get("total_weight_lbs", 0), c.get("grams", 0)])
	_row(grid, "Time limit", "%d min" % int(c.get("time_limit_min", 0)))
	_row(grid, "If you lose", "Pay $%d for the meal" % int(c.get("meal_price_usd", 0)))
	_row(grid, "If you win", str(c.get("prize", "free meal")) + (" + $%d cash" % int(c.get("cash_prize", 0)) if int(c.get("cash_prize", 0)) > 0 else ""))
	_row(grid, "Owner", str(c.get("owner_name", "")))
	if GameState.is_completed(c.get("id", "")):
		v.add_child(UITheme.label("Already completed. You can do it again for the video, but the owner already hates you.", 13, Color(0.6, 1, 0.6)))
	v.add_child(HSeparator.new())

	# B-roll
	var bh := HBoxContainer.new()
	v.add_child(bh)
	var chance := Economy.broll_chance(GameState.eating_profile()["broll_bonus"])
	_broll_btn = UITheme.button("Ask to film the kitchen (B-roll)  %d%%" % int(chance * 100), _on_broll, 320)
	bh.add_child(_broll_btn)
	_broll_label = UITheme.label("Success: +30% views. Owner gets 150% health if you win.", 13, Color(0.75, 0.75, 0.75))
	_broll_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_broll_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(_broll_label)

	# Prep consumables
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 20)
	v.add_child(ph)
	_sauce_check = CheckBox.new()
	_sauce_check.text = "Add Hot Sauce (×%d)  chew +25%%, fill +15%%" % GameState.item_count("hot_sauce")
	_sauce_check.disabled = not GameState.has_item("hot_sauce")
	ph.add_child(_sauce_check)
	_tums_check = CheckBox.new()
	_tums_check.text = "Take Tums (×%d)  capacity +15" % GameState.item_count("tums")
	_tums_check.disabled = not GameState.has_item("tums")
	ph.add_child(_tums_check)
	var prof := GameState.eating_profile()
	var ut: Dictionary = prof["utensil"]
	v.add_child(UITheme.label("Utensil: %s   •   Skills: hands %d, jaw %d, stomach %d" % [ut.get("name", "Bare hands"), GameState.skill_level("quick_hands"), GameState.skill_level("iron_jaw"), GameState.skill_level("big_stomach")], 13, Color(0.7, 0.8, 1)))

	var bb := HBoxContainer.new()
	bb.alignment = BoxContainer.ALIGNMENT_CENTER
	bb.add_theme_constant_override("separation", 16)
	v.add_child(bb)
	_start_btn = UITheme.button("Start challenge", _on_start, 200)
	bb.add_child(_start_btn)
	bb.add_child(UITheme.button("Leave", _on_leave, 120))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _row(grid: GridContainer, k: String, v: String) -> void:
	grid.add_child(UITheme.label(k, 14, Color(0.7, 0.7, 0.7)))
	grid.add_child(UITheme.label(v, 14))

func _on_broll() -> void:
	if broll_asked:
		return
	broll_asked = true
	var chance := Economy.broll_chance(GameState.eating_profile()["broll_bonus"])
	broll_success = _rng.randf() < chance
	_broll_btn.disabled = true
	if broll_success:
		_broll_btn.text = "Owner said YES"
		_broll_label.text = "Professional kitchen B-roll secured. +30% views. The owner will be tougher (150% health) if you win."
		_broll_label.modulate = Color(0.6, 1, 0.6)
	else:
		_broll_btn.text = "Owner said NO"
		_broll_label.text = "\"No cameras in my kitchen.\" No effect."
		_broll_label.modulate = Color(1, 0.7, 0.6)

## For QA scripts: force a B-roll outcome.
func force_broll(success: bool) -> void:
	broll_asked = true
	broll_success = success
	_broll_btn.disabled = true

func _on_start() -> void:
	options = {"broll": broll_success, "hot_sauce": _sauce_check.button_pressed, "tums": _tums_check.button_pressed}
	if options["hot_sauce"]:
		GameState.consume_item("hot_sauce")
	if options["tums"]:
		GameState.consume_item("tums")
	start_requested.emit(challenge, options)
	queue_free()

func _on_leave() -> void:
	closed.emit()
	queue_free()
