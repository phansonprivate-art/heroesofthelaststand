class_name AbilityBar
extends PanelContainer
## Fähigkeitsleiste unten in der Mitte: Q W E R D F mit Abklingzeit, Stufe, Mana-Kosten,
## dazu die zwei Verbrauchsslots (1, 2). Ultimate-Slot (R) golden umrandet und bis Stufe 5 gesperrt.

## Klick auf einen Slot oder den Shop-Knopf: Shop öffnen (Reiter 0 = Fähigkeiten, 3 = Verbrauch)
signal shop_requested(tab: int)

const SLOT_SIZE := Vector2(68, 68)

var _match: MatchController
var _slots: Array[Dictionary] = []      ## je Slot: {panel, icon, key, pips, mana, shade, cd}
var _items: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Leicht nach rechts versetzt, damit das Heldenpanel links unten frei bleibt
	UiTheme.place(self, Control.PRESET_CENTER_BOTTOM, 90, -16, 90, -16, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	for i in AbilityCaster.SLOT_KEYS.size():
		if i == AbilityCaster.ULT_SLOT + 1:
			row.add_child(_spacer(6))
		_slots.append(_make_slot(row, AbilityCaster.SLOT_KEYS[i], i == AbilityCaster.ULT_SLOT, SLOT_SIZE, 0))
		if i == AbilityCaster.ULT_SLOT - 1:
			row.add_child(_spacer(6))
	row.add_child(_spacer(14))
	for i in 2:
		_items.append(_make_slot(row, str(i + 1), false, Vector2(52, 52), 3))
	row.add_child(_spacer(10))
	var shop := Button.new()
	shop.text = "Shop [B]"
	shop.focus_mode = Control.FOCUS_NONE
	shop.custom_minimum_size = Vector2(110, 0)
	shop.add_theme_font_size_override("font_size", 16)
	shop.add_theme_color_override("font_color", UiTheme.ACCENT)
	shop.tooltip_text = "Fähigkeiten lernen, Attribute, Ausrüstung, Tränke, Team-Upgrades"
	shop.pressed.connect(func() -> void: shop_requested.emit(0))
	row.add_child(shop)


func bind(m: MatchController) -> void:
	_match = m


func _process(_delta: float) -> void:
	if _match == null or _match.local_hero == null:
		return
	var hero := _match.local_hero
	var caster := hero.abilities
	for i in _slots.size():
		var s := _slots[i]
		var id: String = caster.slots[i]
		var def := GameData.skill(id)
		if def.is_empty():
			var locked := i == AbilityCaster.ULT_SLOT and hero.stats.level < AbilityCaster.ULT_HERO_LEVEL
			s.icon.text = "Stufe\n10" if locked else "–"
			s.icon.add_theme_font_size_override("font_size", 13 if locked else 24)
			s.icon.add_theme_color_override("font_color", UiTheme.MUTED)
			s.pips.text = ""
			s.mana.text = ""
			s.shade.visible = false
			s.cd.text = ""
			s.panel.tooltip_text = "Ultimate ab Heldenstufe %d – " % AbilityCaster.ULT_HERO_LEVEL + "im Shop (B) wählen." if i == AbilityCaster.ULT_SLOT else "Leer – klicken oder B: Fähigkeiten im Shop lernen."
			continue
		var lvl := caster.level_of(id)
		s.icon.text = def.icon
		s.icon.add_theme_font_size_override("font_size", 24)
		s.icon.add_theme_color_override("font_color", def.color)
		s.pips.text = "●".repeat(lvl) + "○".repeat(GameData.MAX_SKILL_LEVEL - lvl)
		var cost := caster.mana_cost(id)
		s.mana.text = str(int(cost))
		var cd := caster.cooldown_left(id)
		var max_cd := float(GameData.skill_value(id, lvl, "cooldown", 1.0))
		s.shade.visible = cd > 0.0 or hero.mana < cost or not hero.is_alive()
		s.shade.color = Color(0, 0, 0, 0.6) if cd > 0.0 else Color(0.1, 0.2, 0.6, 0.45)
		s.shade.anchor_top = 1.0 - (cd / max_cd if cd > 0.0 else 1.0)
		s.cd.text = str(ceili(cd)) if cd > 0.0 else ""
		s.icon.modulate.a = 0.3 if cd > 0.0 else 1.0
		s.panel.tooltip_text = "%s (Stufe %d)%s\n%s\n%s" % [def.name, lvl, "  ·  Ultimate" if def.ultimate else "", def.description,
			UiTheme.format_skill_level(id, lvl, hero)]
	for i in _items.size():
		var s := _items[i]
		var c: Dictionary = hero.inventory.consumables[i] if i < hero.inventory.consumables.size() else {}
		if c.is_empty():
			s.icon.text = "–"
			s.icon.add_theme_color_override("font_color", UiTheme.MUTED)
			s.pips.text = ""
			s.panel.tooltip_text = "Verbrauchsslot %d – Tränke und Runen im Shop (B)." % (i + 1)
		else:
			var def := GameData.item(c.id)
			s.icon.text = "".join(PackedStringArray(Array(def.name.split(" ")).map(func(w: String) -> String: return w.substr(0, 1))))
			s.icon.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6) if c.id == "phoenix_potion" else Color(0.7, 0.85, 1.0))
			s.pips.text = "×%d" % c.count
			s.panel.tooltip_text = "%s (%d)\n%s" % [def.name, c.count, def.description]


func _make_slot(parent: Control, key: String, ultimate: bool, size := SLOT_SIZE, shop_tab := 0) -> Dictionary:
	var panel := PanelContainer.new()
	panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			shop_requested.emit(shop_tab))
	panel.custom_minimum_size = size
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.07, 0.09, 0.13, 0.92), UiTheme.ACCENT if ultimate else UiTheme.BORDER, 8))
	parent.add_child(panel)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(root)
	var icon := UiTheme.label("–", 24, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(icon)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.visible = false
	root.add_child(shade)
	var cd := UiTheme.label("", 26, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	cd.set_anchors_preset(Control.PRESET_FULL_RECT)
	cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(cd)
	var key_label := UiTheme.label(key, 13, UiTheme.ACCENT if ultimate else UiTheme.MUTED)
	key_label.position = Vector2(-10, -8)
	root.add_child(key_label)
	var pips := UiTheme.label("", 10, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	pips.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	pips.offset_top = -14
	pips.offset_bottom = 4
	root.add_child(pips)
	var mana := UiTheme.label("", 11, Color(0.5, 0.7, 1.0), HORIZONTAL_ALIGNMENT_RIGHT)
	mana.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mana.offset_left = -30
	mana.offset_right = 8
	mana.offset_top = -8
	root.add_child(mana)
	return {"panel": panel, "icon": icon, "key": key_label, "pips": pips, "mana": mana, "shade": shade, "cd": cd}


func _spacer(width: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
