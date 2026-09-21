class_name DeathScreen
extends CanvasLayer

signal closed()

func open(bill: int, killer_line: String, lost_items: Array) -> void:
	layer = 7
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel(Color(0.2, 0.02, 0.02, 0.95)))
	panel.custom_minimum_size = Vector2(520, 0)
	add_child(UITheme.centered(panel))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(UITheme.label("YOU GOT WRECKED", 30, Color(1, 0.3, 0.3)))
	if killer_line != "":
		v.add_child(UITheme.label("\"%s\"" % killer_line, 16, Color(1, 0.8, 0.8)))
	v.add_child(UITheme.label("Hospital bill: -$%d" % bill, 18))
	if lost_items.size() > 0:
		var l := UITheme.label("Lost: " + ", ".join(lost_items), 14, Color(0.9, 0.7, 0.7))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.custom_minimum_size.x = 480
		v.add_child(l)
	v.add_child(UITheme.label("You wake up at the hospital.", 14, Color(0.8, 0.8, 0.8)))
	v.add_child(UITheme.centered(UITheme.button("Wake up", func(): closed.emit(); queue_free(), 180)))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
