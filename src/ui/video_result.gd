## Post-challenge "video uploaded" screen.
class_name VideoResult
extends CanvasLayer

signal closed()

func open(challenge: Dictionary, r: Dictionary) -> void:
	layer = 6
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel())
	panel.custom_minimum_size = Vector2(560, 0)
	add_child(UITheme.centered(panel))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var title := "VIDEO POSTED" if r["won"] else "VIDEO POSTED (L)"
	v.add_child(UITheme.label(title, 28, Color(1, 0.3, 0.3)))
	var vt := "\"I tried the %s at %s%s\"" % [challenge.get("name", ""), challenge.get("restaurant", ""), " (VIRAL)" if r["viral"] else ""]
	var vl := UITheme.label(vt, 16, Color(0.9, 0.9, 0.9))
	vl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vl.custom_minimum_size.x = 520
	v.add_child(vl)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 30)
	v.add_child(g)
	_row(g, "Views", HUD._fmt(int(r["views"])) + ("  🔥 VIRAL ×8" if r["viral"] else ""))
	_row(g, "New subscribers", "+%s" % HUD._fmt(int(r["subs"])))
	_row(g, "Ad revenue", "+$%d" % int(r["money"]))
	if int(r["prize"]) > 0:
		_row(g, "Challenge prize", "+$%d" % int(r["prize"]))
	if int(r["meal_cost"]) > 0:
		_row(g, "Meal bill", "-$%d" % int(r["meal_cost"]))
	if r["broll"]:
		_row(g, "B-roll bonus", "+30% views")
	_row(g, "Production quality", "×%.2f" % GameState.production_quality())
	v.add_child(HSeparator.new())
	v.add_child(UITheme.label("Net: %s$%d" % ["+" if int(r["net_money"]) >= 0 else "-", absi(int(r["net_money"]))], 22, Color(0.6, 1, 0.6) if int(r["net_money"]) >= 0 else Color(1, 0.6, 0.6)))
	if r["won"]:
		v.add_child(UITheme.label("The owner is furious about the free meal. Watch your back.", 14, Color(1, 0.7, 0.5)))
	var b := UITheme.button("Continue", func(): closed.emit(); queue_free(), 200)
	v.add_child(UITheme.centered(b))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _row(g: GridContainer, k: String, val: String) -> void:
	g.add_child(UITheme.label(k, 15, Color(0.7, 0.7, 0.7)))
	g.add_child(UITheme.label(val, 15))
