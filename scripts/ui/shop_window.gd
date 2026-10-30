class_name ShopWindow
extends PanelContainer
## Shop (B): Fähigkeiten, Attribute, Ausrüstung, Verbrauch, Team. Zeigt Kosten, Goldbestände,
## Voraussetzungen und den Grund, warum etwas (noch) nicht kaufbar ist. Kauft über MatchController.

const TABS := ["Fähigkeiten", "Attribute", "Ausrüstung", "Verbrauch", "Team"]

var _match: MatchController
var _tabs: TabContainer
var _lists: Array[VBoxContainer] = []
var _gold: Label
var _team_gold: Label
var _feedback: Label
var _feedback_tween: Tween


func _ready() -> void:
	visible = false
	add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.BG_SOLID))
	UiTheme.place(self, Control.PRESET_CENTER, -470, -330, 470, 330)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	box.add_child(head)
	var title := UiTheme.label("Shop", 28, UiTheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_gold = UiTheme.label("", 18, Color(1.0, 0.82, 0.3))
	head.add_child(_gold)
	_team_gold = UiTheme.label("", 18, Color(0.55, 0.85, 1.0))
	head.add_child(_team_gold)
	var close_button := Button.new()
	close_button.text = "✕"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	head.add_child(close_button)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.tab_changed.connect(func(_t: int) -> void: refresh())
	box.add_child(_tabs)
	for t in TABS:
		var scroll := ScrollContainer.new()
		scroll.name = t
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_tabs.add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 6)
		scroll.add_child(list)
		_lists.append(list)
	_feedback = UiTheme.label("", 16, UiTheme.HP)
	_feedback.modulate.a = 0.0
	box.add_child(_feedback)


func bind(m: MatchController) -> void:
	_match = m
	m.gold.balance_changed.connect(func(_p: int, _b: int) -> void: refresh())
	m.local_hero.stats_changed.connect(func(_h: Hero) -> void: refresh())
	m.local_hero.abilities.changed.connect(refresh)


func open(tab := -1) -> void:
	visible = true
	if tab >= 0:
		_tabs.current_tab = tab
	Audio.play("ui_open")
	refresh()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func close() -> void:
	if visible:
		Audio.play("ui_close")
	visible = false


func refresh() -> void:
	if _match == null or not visible:
		return
	var hero := _match.local_hero
	_gold.text = "%s Gold" % UiTheme.format_int(_match.gold.balance(hero.peer_id))
	_team_gold.text = "Team: %s Gold" % UiTheme.format_int(_match.gold.team_balance())
	var list := _lists[_tabs.current_tab]
	for c in list.get_children():
		c.queue_free()
	match _tabs.current_tab:
		0: _fill_abilities(list, hero)
		1: _fill_attributes(list, hero)
		2: _fill_items(list, hero, false)
		3: _fill_items(list, hero, true)
		4: _fill_team(list, hero)


func show_result(result: Dictionary) -> void:
	_feedback.text = result.message
	_feedback.add_theme_color_override("font_color", UiTheme.HP if result.ok else UiTheme.DANGER)
	if _feedback_tween != null:
		_feedback_tween.kill()
	_feedback.modulate.a = 1.0
	_feedback_tween = create_tween()
	_feedback_tween.tween_interval(3.0)
	_feedback_tween.tween_property(_feedback, "modulate:a", 0.0, 0.6)
	refresh()


# --- Reiter ------------------------------------------------------------------

func _fill_abilities(list: VBoxContainer, hero: Hero) -> void:
	list.add_child(UiTheme.label("Fähigkeiten des %s. Ihre Wirkung wächst mit deinen Attributen (Skalierung im Text). R ist dem Ultimate vorbehalten (ab Stufe 5, eines pro Held)." % hero.data.name, 14, UiTheme.MUTED))
	var caster := hero.abilities
	for id in GameData.skill_order:
		var def := GameData.skill(id)
		if not (hero.hero_id in def.heroes):
			continue   # nur die Fähigkeiten der eigenen Klasse
		var lvl := caster.level_of(id)
		var title := "%s%s   ·   Stufe %d/3" % [def.name, "  (Ultimate)" if def.ultimate else "", lvl]
		var details: String
		if lvl == 0:
			details = "%s\nStufe 1: %s" % [def.description, UiTheme.format_skill_level(id, 1, hero)]
		elif lvl < GameData.MAX_SKILL_LEVEL:
			var scaling := UiTheme.scaling_text(id, hero)
			details = "%s\nVerbesserung Stufe %d → %d:  %s%s" % [def.description, lvl, lvl + 1, UiTheme.format_skill_upgrade(id, lvl, lvl + 1, hero),
				"\n" + scaling if scaling != "" else ""]
		else:
			details = "%s\nStufe %d (max.): %s" % [def.description, lvl, UiTheme.format_skill_level(id, lvl, hero)]
		var cost := caster.cost_for(id)
		var reason := caster.check_learn(id)
		if reason == "" and not _match.gold.can_afford(hero.peer_id, cost):
			reason = "Nicht genug Gold (%d fehlen)." % (cost - _match.gold.balance(hero.peer_id))
		var label := "Max." if lvl >= 3 else ("%s · %d" % ["Lernen" if lvl == 0 else "Verbessern", cost])
		var row := _row(list, title, details, def.color, label, reason, func() -> void: show_result(_match.request_learn_ability(id)))
		if lvl > 0 and not def.ultimate:
			var slot_row := HBoxContainer.new()
			slot_row.add_theme_constant_override("separation", 4)
			slot_row.add_child(UiTheme.label("Slot:", 13, UiTheme.MUTED))
			for s in AbilityCaster.NORMAL_SLOTS:
				var b := Button.new()
				b.text = AbilityCaster.SLOT_KEYS[s]
				b.focus_mode = Control.FOCUS_NONE
				b.toggle_mode = true
				b.button_pressed = caster.slots[s] == id
				b.add_theme_font_size_override("font_size", 13)
				b.pressed.connect(func() -> void: show_result(_match.request_equip_ability(id, s)))
				slot_row.add_child(b)
			row.add_child(slot_row)


func _fill_attributes(list: VBoxContainer, hero: Hero) -> void:
	var s := hero.stats
	for a in StatBlock.ATTRIBUTES:
		var cost := s.upgrade_cost(a)
		var reason := "" if _match.gold.can_afford(hero.peer_id, cost) else "Nicht genug Gold (%d fehlen)." % (cost - _match.gold.balance(hero.peer_id))
		var note := "  ·  über dem Soft Cap: halbe Wirkung" if s.is_beyond_soft_cap(a) else ""
		_row(list, "%s: %.0f  (+%d gekauft)" % [GameData.ATTRIBUTE_NAMES[a], s.attribute(a), s.bought[a]], UiTheme.format_attribute_upgrade(hero, a) + note,
			UiTheme.TEXT, "+%d · %d" % [s.points_per_buy(), cost], reason, func() -> void: show_result(_match.request_attribute_upgrade(a)))


func _fill_items(list: VBoxContainer, hero: Hero, consumables: bool) -> void:
	for id in GameData.item_order:
		var def := GameData.item(id)
		if (def.slot == "consumable") != consumables:
			continue
		var reason := hero.inventory.check_add(id)
		if reason == "" and not _match.gold.can_afford(hero.peer_id, def.price):
			reason = "Nicht genug Gold (%d fehlen)." % (def.price - _match.gold.balance(hero.peer_id))
		var slot_name: String = Inventory.SLOT_NAMES.get(def.slot, "Verbrauch (Taste 1/2, bis %d Stück)" % def.max_stack)
		var stats: String = UiTheme.format_stats(def.stats) if not def.stats.is_empty() else String(def.description)
		var equipped := " – angelegt" if hero.inventory.equipment.get(def.slot, "") == id else ""
		_row(list, "%s   ·   %s%s" % [def.name, slot_name, equipped], "%s\n%s" % [def.description, stats], UiTheme.TEXT,
			"Kaufen · %d" % def.price, reason, func() -> void: show_result(_match.request_buy_item(id)))


func _fill_team(list: VBoxContainer, hero: Hero) -> void:
	list.add_child(UiTheme.label("Team-Gold kommt aus jeder abgeschlossenen Welle und aus freiwilligen Spenden – nie automatisch aus deinem Gold.", 14, UiTheme.MUTED))
	for u in GameData.team_upgrades:
		var lvl := _match.shop.team_level(u.id)
		var maxed: bool = lvl >= u.costs.size()
		var cost := _match.shop.team_cost(u.id)
		var reason := "" if maxed or _match.gold.team_balance() >= cost else "Nicht genug Team-Gold (%d fehlen)." % (cost - _match.gold.team_balance())
		_row(list, "%s   ·   Stufe %d/%d" % [u.name, lvl, u.costs.size()], u.description, Color(0.55, 0.85, 1.0),
			"Max." if maxed else "Team · %d" % cost, reason, func() -> void: show_result(_match.request_team_upgrade(u.id)))
	var donate := HBoxContainer.new()
	donate.add_theme_constant_override("separation", 8)
	donate.add_child(UiTheme.label("Spenden:", 16, UiTheme.TEXT))
	for amount in [50, 100, 250]:
		var b := Button.new()
		b.text = "%d Gold" % amount
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = not _match.gold.can_afford(hero.peer_id, amount)
		b.pressed.connect(func() -> void: show_result(_match.request_donate(amount)))
		donate.add_child(b)
	list.add_child(donate)


## Eine Zeile: Titel, Details, Kaufknopf (deaktiviert mit Begründung als Tooltip und Text).
func _row(list: VBoxContainer, title: String, details: String, color: Color, button_text: String, reason: String, action: Callable) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.1, 0.12, 0.17, 0.9), Color(0.3, 0.32, 0.4, 0.6), 8))
	list.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)
	texts.add_child(UiTheme.label(title, 17, color))
	var d := UiTheme.label(details, 13, UiTheme.MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(d)
	if reason != "" and button_text != "Max.":
		texts.add_child(UiTheme.label(reason, 13, UiTheme.DANGER))
	var b := Button.new()
	b.text = button_text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(170, 0)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.disabled = reason != "" or button_text == "Max."
	b.tooltip_text = reason
	b.pressed.connect(action)
	row.add_child(b)
	return texts
