## Progression store: items + skills.
class_name Shop
extends CanvasLayer

signal closed()

var _list: VBoxContainer
var _money: Label

func open() -> void:
	layer = 6
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel())
	panel.custom_minimum_size = Vector2(760, 520)
	add_child(UITheme.centered(panel))
	var v := VBoxContainer.new()
	panel.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	var t := UITheme.label("PROGRESSION STORE", 26, Color(0.5, 0.8, 1))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	_money = UITheme.label("$%d" % GameState.money, 22, Color(0.6, 1, 0.6))
	h.add_child(_money)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 400
	v.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_rebuild()
	v.add_child(UITheme.centered(UITheme.button("Leave", func(): closed.emit(); queue_free(), 160)))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	_money.text = "$%d" % GameState.money
	_list.add_child(UITheme.label("— Skills —", 18, Color(1, 0.85, 0.4)))
	for id in Data.skills.keys():
		var s: Dictionary = Data.skills[id]
		var lvl := GameState.skill_level(id)
		var maxed := lvl >= int(s.get("max_level", 5))
		var price := GameState.skill_price(id)
		_entry("%s  (Lv %d/%d)" % [s["name"], lvl, s.get("max_level", 5)], str(s["desc"]), "MAX" if maxed else "$%d" % price,
			(not maxed) and GameState.can_afford(price), func(): GameState.buy_skill(id); _rebuild())
	_list.add_child(UITheme.label("— Items —", 18, Color(1, 0.85, 0.4)))
	for id in Data.items.keys():
		var it: Dictionary = Data.items[id]
		var price := int(it.get("price", 0))
		if price <= 0:
			continue
		var owned := GameState.item_count(id)
		var gear: bool = it.get("kind", "") == "gear"
		var can: bool = GameState.can_afford(price) and not (gear and owned > 0)
		var label := "%s%s" % [it["name"], ("  (owned)" if gear and owned > 0 else ("  ×%d" % owned if owned > 0 else ""))]
		_entry(label, str(it.get("desc", "")), "$%d" % price, can, func(): GameState.buy_item(id); _rebuild())

func _entry(name: String, desc: String, price: String, enabled: bool, cb: Callable) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	_list.add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UITheme.label(name, 15))
	var d := UITheme.label(desc, 12, Color(0.7, 0.7, 0.7))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD
	d.custom_minimum_size.x = 480
	v.add_child(d)
	var b := UITheme.button(price, cb, 110)
	b.disabled = not enabled
	h.add_child(b)
