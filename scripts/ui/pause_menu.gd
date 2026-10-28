class_name PauseMenu
extends CanvasLayer
## Pausemenü (Esc). Hält den SceneTree an; läuft selbst mit PROCESS_MODE_ALWAYS.

const CONTROLS := """Rechtsklick: laufen / Gegner angreifen (halten: folgen)
Q W E R D F: Fähigkeiten (R = Ultimate) · 1 2: Tränke & Runen
A + Linksklick: Angriffsbewegung · S: Stopp
B: Shop · I: Inventar · C: Charakter · Tab (halten): Team
Y: Kamera lösen · Leertaste: zentrieren · Mausrad: Zoom
N: nächste Welle sofort · Esc: Fenster schließen / Pause"""

var _match: MatchController
var _resume_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	visible = false
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.build_theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.BG_SOLID))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(320, 0)
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(UiTheme.label("Pause", 32, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	_resume_button = _button(box, "Weiterspielen", close)
	_button(box, "Runde neu starten", func() -> void: Session.restart_match())
	_button(box, "Hauptmenü", func() -> void: Session.return_to_menu())
	_button(box, "Spiel beenden", func() -> void: get_tree().quit())
	box.add_child(HSeparator.new())
	box.add_child(UiTheme.label("Steuerung", 18, UiTheme.ACCENT))
	box.add_child(UiTheme.label(CONTROLS, 14, UiTheme.MUTED))


func bind(m: MatchController) -> void:
	_match = m


func open() -> void:
	visible = true
	get_tree().paused = true
	_resume_button.grab_focus()


func close() -> void:
	visible = false
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	parent.add_child(b)
	return b
