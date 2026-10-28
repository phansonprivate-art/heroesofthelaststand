class_name GameOverScreen
extends CanvasLayer
## Sieg- oder Niederlagebildschirm mit Rundenstatistik.

var _match: MatchController
var _title: Label
var _subtitle: Label
var _stats: Label
var _panel: PanelContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 9
	visible = false
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.build_theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.BG_SOLID))
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(440, 0)
	box.add_theme_constant_override("separation", 12)
	_panel.add_child(box)
	_title = UiTheme.label("", 44, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_subtitle = UiTheme.label("", 18, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_stats = UiTheme.label("", 18, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_title)
	box.add_child(_subtitle)
	box.add_child(HSeparator.new())
	box.add_child(_stats)
	var again := Button.new()
	again.text = "Neue Runde"
	again.pressed.connect(func() -> void: Session.restart_match())
	box.add_child(again)
	var menu := Button.new()
	menu.text = "Hauptmenü"
	menu.pressed.connect(func() -> void: Session.return_to_menu())
	box.add_child(menu)


func bind(m: MatchController) -> void:
	_match = m


func show_result(victory: bool, stats: Dictionary) -> void:
	_title.text = "Sieg!" if victory else "Niederlage"
	_title.add_theme_color_override("font_color", UiTheme.HP if victory else UiTheme.DANGER)
	_subtitle.text = "Der Kern hat standgehalten." if victory else "Der Kern ist gefallen."
	var seconds := int(stats.seconds)
	_stats.text = "Wellen abgewehrt: %d / %d\nBesiegte Gegner: %d\nKern: %s / %s\nDauer: %d:%02d" % [
		stats.waves_completed, stats.waves_total, stats.kills,
		UiTheme.format_int(stats.core_hp), UiTheme.format_int(stats.core_max), seconds / 60, seconds % 60]
	visible = true
	_panel.modulate.a = 0.0
	create_tween().tween_property(_panel, "modulate:a", 1.0, 0.6).set_delay(0.8)
