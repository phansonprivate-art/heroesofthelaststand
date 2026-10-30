class_name MainMenu
extends Control
## Startmenü: Held und Karte wählen, Einzelspiel starten, beenden.

var _selected_hero := ""
var _cards: Dictionary = {}     ## hero_id -> Button
var _detail: Label
var _map_buttons: Dictionary = {}   ## map_id -> Button
var _map_detail: Label


func _ready() -> void:
	theme = UiTheme.build_theme()
	_selected_hero = Session.hero_id

	var bg := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.09, 0.11, 0.17))
	grad.set_color(1, Color(0.02, 0.03, 0.05))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.35)
	tex.fill_to = Vector2(1.1, 1.1)
	bg.texture = tex
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(760, 0)
	center.add_child(box)

	box.add_child(UiTheme.label("HEROES OF THE", 30, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var title := UiTheme.label("LAST STAND", 72, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_constant_override("outline_size", 12)
	box.add_child(title)
	box.add_child(UiTheme.label("Verteidigt den Kern gegen die Wellen der Untoten.", 18, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	box.add_child(spacer)
	box.add_child(UiTheme.label("Wähle deinen Helden", 16, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	for id in GameData.hero_order:
		var card := _hero_card(GameData.hero(id))
		row.add_child(card)
		_cards[id] = card

	var detail_panel := PanelContainer.new()
	box.add_child(detail_panel)
	_detail = UiTheme.label("", 15, UiTheme.TEXT)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_panel.add_child(_detail)

	box.add_child(UiTheme.label("Wähle die Karte", 16, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var map_row := HBoxContainer.new()
	map_row.add_theme_constant_override("separation", 14)
	map_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(map_row)
	for mid in GameData.map_order:
		var map_def := GameData.map(mid)
		var b := Button.new()
		b.text = map_def.name
		b.tooltip_text = map_def.description
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(240, 44)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_select_map.bind(mid))
		map_row.add_child(b)
		_map_buttons[mid] = b
	_map_detail = UiTheme.label("", 14, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_map_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_map_detail)
	_select_map(Session.map_id if GameData.maps.has(Session.map_id) else (GameData.map_order[0] if not GameData.map_order.is_empty() else ""))

	var start := Button.new()
	start.text = "Einzelspiel starten"
	start.add_theme_font_size_override("font_size", 24)
	start.pressed.connect(func() -> void: Session.start_singleplayer(_selected_hero))
	box.add_child(start)
	box.add_child(_build_test_mode_row())
	var quit := Button.new()
	quit.text = "Beenden"
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)
	start.grab_focus()

	if GameData.hero_order.is_empty():
		_detail.text = "Kein Held verfügbar – Daten prüfen."
		start.disabled = true
	elif not GameData.heroes.has(_selected_hero):
		_selected_hero = GameData.hero_order[0]
	_select(_selected_hero)

	if not GameData.errors.is_empty():
		var err := UiTheme.label("Datenfehler:\n" + "\n".join(GameData.errors), 14, UiTheme.DANGER)
		err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(err)

	var footer := UiTheme.label("Prototyp 0.3  ·  3D-Modelle: KayKit von Kay Lousberg (CC0)", 13, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	UiTheme.place(footer, Control.PRESET_CENTER_BOTTOM, -300, -40, 300, -14)
	add_child(footer)


## Testmodus (Issue #11): Stufe und Startwelle wählen, Gold unbegrenzt an/aus, mit dem gewählten Helden und der Karte starten.
func _build_test_mode_row() -> Control:
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(row)
	row.add_child(UiTheme.label("Testmodus", 16, UiTheme.ACCENT))
	row.add_child(UiTheme.label("Stufe", 15, UiTheme.TEXT))
	var level := SpinBox.new()
	level.min_value = 1
	level.max_value = int(GameData.attribute_rules.get("levels", {}).get("max_level", 20))
	level.value = Session.test_level if Session.test_mode else level.max_value
	level.rounded = true
	level.custom_minimum_size = Vector2(90, 0)
	level.tooltip_text = "Der Held startet direkt auf dieser Stufe (bis zur Höchststufe)."
	row.add_child(level)
	row.add_child(UiTheme.label("Welle", 15, UiTheme.TEXT))
	var wave := SpinBox.new()
	wave.min_value = 1
	wave.max_value = maxi(1, GameData.waves.size())
	wave.value = Session.test_wave if Session.test_mode else 1
	wave.rounded = true
	wave.custom_minimum_size = Vector2(90, 0)
	wave.tooltip_text = "Die Runde beginnt direkt mit dieser Welle (z. B. 8 = Eisdrache, 9 = Feuerdrache, 10 = Morvath)."
	row.add_child(wave)
	var unlimited := CheckBox.new()
	unlimited.text = "Gold unbegrenzt"
	unlimited.button_pressed = Session.test_unlimited_gold
	unlimited.tooltip_text = "Start mit maximalem Gold. Unbegrenzt: Kaufen zieht kein Gold ab."
	row.add_child(unlimited)
	var start := Button.new()
	start.text = "Testmodus starten"
	start.tooltip_text = "Eigene Testrunde: keine Telemetrie, der normale Spielstand bleibt unberührt."
	start.pressed.connect(func() -> void:
		Session.start_test(_selected_hero, _spin_value(level), unlimited.button_pressed, _spin_value(wave)))
	row.add_child(start)
	return panel


## Wert einer SpinBox; eine eingetippte Zahl zählt auch ohne Enter (sonst wird sie erst beim Verlassen übernommen).
func _spin_value(spin: SpinBox) -> int:
	var typed := spin.get_line_edit().text.strip_edges()
	var v := int(typed) if typed.is_valid_int() else int(spin.value)
	return clampi(v, int(spin.min_value), int(spin.max_value))


func select_hero(id: String) -> void:
	_select(id)


func _select_map(id: String) -> void:
	if not GameData.maps.has(id):
		return
	Session.map_id = id
	for mid in _map_buttons:
		(_map_buttons[mid] as Button).button_pressed = mid == id
	_map_detail.text = GameData.map(id).description


func _select(id: String) -> void:
	if not GameData.heroes.has(id):
		return
	_selected_hero = id
	for hid in _cards:
		var card: Button = _cards[hid]
		var color: Color = GameData.hero(hid).color
		var selected: bool = hid == id
		card.add_theme_stylebox_override("normal", UiTheme.panel(Color(color.darkened(0.75), 0.95) if selected else UiTheme.BG, color if selected else UiTheme.BORDER))
		card.add_theme_stylebox_override("hover", UiTheme.panel(Color(color.darkened(0.65), 0.95), color))
		card.modulate = Color.WHITE if selected else Color(1, 1, 1, 0.75)
	var hero := GameData.hero(id)
	var s := StatBlock.create(hero, GameData.attribute_rules)
	_detail.text = "%s\n\nStufe 1:  Leben %d  ·  Mana %d  ·  Angriff %.0f %s  ·  %.2f Angriffe/s  ·  Reichweite %.1f m  ·  Krit %.0f %%  ·  Rüstung %.1f" % [
		hero.description, s.max_hp(), s.max_mana(), s.attack_damage(), "magisch" if hero.damage_type == "magic" else "physisch",
		1.0 / s.attack_interval(), s.attack_range(), s.crit_chance() * 100.0, s.armor()]


func _hero_card(hero: Dictionary) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(240, 120)
	card.focus_mode = Control.FOCUS_NONE
	card.pressed.connect(_select.bind(String(hero.id)))
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16
	box.offset_top = 12
	box.offset_right = -16
	box.offset_bottom = -12
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	box.add_child(UiTheme.label(hero.name, 26, hero.color))
	box.add_child(UiTheme.label(hero.archetype, 15, UiTheme.MUTED))
	var role := UiTheme.label(hero.role, 14, UiTheme.TEXT)
	role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(role)
	return card
