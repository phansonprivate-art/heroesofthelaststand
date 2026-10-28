class_name MainMenu
extends Control
## Startmenü: Held wählen, Einzelspiel starten, beenden.

var _selected_hero := ""
var _cards: Dictionary = {}     ## hero_id -> Button
var _detail: Label


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

	var start := Button.new()
	start.text = "Einzelspiel starten"
	start.add_theme_font_size_override("font_size", 24)
	start.pressed.connect(func() -> void: Session.start_singleplayer(_selected_hero))
	box.add_child(start)
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


func select_hero(id: String) -> void:
	_select(id)


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
