## In-world HUD: money, subs, health, hunters, prompt, toasts.
class_name HUD
extends CanvasLayer

var money_label: Label
var subs_label: Label
var health_bar: ProgressBar
var hunters_label: Label
var prompt_label: Label
var toast_box: VBoxContainer
var objective_label: Label
var alert_label: Label

func _ready() -> void:
	layer = 3
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var tl := PanelContainer.new()
	tl.position = Vector2(16, 12)
	tl.add_theme_stylebox_override("panel", UITheme.panel(Color(0, 0, 0, 0.55)))
	root.add_child(tl)
	var v := VBoxContainer.new()
	tl.add_child(v)
	money_label = UITheme.label("$0", 22, Color(0.6, 1, 0.6))
	subs_label = UITheme.label("0 subs", 16, Color(1, 0.5, 0.5))
	v.add_child(money_label)
	v.add_child(subs_label)
	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(200, 18)
	health_bar.show_percentage = false
	health_bar.add_theme_stylebox_override("fill", UITheme.panel(Color(0.85, 0.2, 0.2), 4))
	health_bar.add_theme_stylebox_override("background", UITheme.panel(Color(0.2, 0.2, 0.2), 4))
	v.add_child(health_bar)
	hunters_label = UITheme.label("Hunters: 0", 14, Color(1, 0.8, 0.5))
	v.add_child(hunters_label)

	var tr := PanelContainer.new()
	tr.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tr.offset_left = -360; tr.offset_right = -16; tr.offset_top = 12
	tr.add_theme_stylebox_override("panel", UITheme.panel(Color(0, 0, 0, 0.55)))
	root.add_child(tr)
	objective_label = UITheme.label("", 14)
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	tr.add_child(objective_label)

	prompt_label = UITheme.label("", 20)
	prompt_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.offset_top = -80; prompt_label.offset_bottom = -50
	prompt_label.offset_left = -300; prompt_label.offset_right = 300
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(prompt_label)

	alert_label = UITheme.label("", 26, Color(1, 0.35, 0.3))
	alert_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	alert_label.offset_top = 70; alert_label.offset_left = -300; alert_label.offset_right = 300
	alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(alert_label)

	toast_box = VBoxContainer.new()
	toast_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	toast_box.offset_left = -380; toast_box.offset_right = -16; toast_box.offset_top = -200; toast_box.offset_bottom = -16
	toast_box.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(toast_box)

	Events.money_changed.connect(func(m): money_label.text = "$%d" % m)
	Events.subscribers_changed.connect(func(s): subs_label.text = "%s subs" % _fmt(s))
	Events.player_health_changed.connect(func(hp, mx): health_bar.max_value = mx; health_bar.value = hp)
	Events.prompt_changed.connect(func(t): prompt_label.text = t)
	Events.toast.connect(show_toast)
	Events.owner_became_hostile.connect(func(_id): refresh_hunters())
	Events.hostile_spotted_player.connect(func(id): set_alert("%s spotted you!" % _owner_name(id)))
	Events.hostile_lost_player.connect(func(_id): set_alert(""))
	Events.hostile_defeated.connect(func(id, loot): set_alert(""); show_toast("Knocked out %s  +$%d" % [_owner_name(id), loot]))
	refresh_all()

func refresh_all() -> void:
	money_label.text = "$%d" % GameState.money
	subs_label.text = "%s subs" % _fmt(GameState.subscribers)
	refresh_hunters()

func refresh_hunters() -> void:
	hunters_label.text = "Hunters: %d" % GameState.hostiles.size()

func set_objective(t: String) -> void:
	objective_label.text = t

func set_alert(t: String) -> void:
	alert_label.text = t

func show_toast(text: String) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.panel(Color(0.1, 0.1, 0.15, 0.85), 6))
	var l := UITheme.label(text, 15)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size.x = 320
	p.add_child(l)
	toast_box.add_child(p)
	var tw := create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)

static func _fmt(n: int) -> String:
	if n >= 1000000:
		return "%.2fM" % (n / 1000000.0)
	if n >= 1000:
		return "%.1fK" % (n / 1000.0)
	return str(n)

static func _owner_name(id: String) -> String:
	return str(Data.get_challenge(id).get("owner_name", "Owner"))
