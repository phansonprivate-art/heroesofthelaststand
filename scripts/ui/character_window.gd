class_name CharacterWindow
extends PanelContainer
## Charakterfenster (C): Attribute mit Kaufmöglichkeit, abgeleitete Werte, Gold und Kaufrückmeldung.
## Kauft nicht selbst, sondern fragt beim MatchController an (später RPC an den Host).

const ATTR_EFFECTS := {
	"str": "Leben, LP-Regeneration, phys. Schaden, Rüstung",
	"agi": "Angriffstempo, kritische Treffer, Lauftempo, Rüstung",
	"int": "Mana, Mana-Regeneration, magischer Schaden, Fähigkeits- und Heilungsstärke",
}

var _match: MatchController
var _title: Label
var _gold: Label
var _feedback: Label
var _attr_value: Dictionary = {}    ## attr -> Label
var _attr_button: Dictionary = {}   ## attr -> Button
var _attr_effect: Dictionary = {}   ## attr -> Label (Vorschau „+1 bringt …“)
var _derived: Label
var _feedback_tween: Tween


func _ready() -> void:
	visible = false
	add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.BG_SOLID))
	UiTheme.place(self, Control.PRESET_TOP_LEFT, 24, 140, 24, 140, Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_END)
	custom_minimum_size = Vector2(560, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	_title = UiTheme.label("", 26, UiTheme.ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close_button := Button.new()
	close_button.text = "✕"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	head.add_child(close_button)

	_gold = UiTheme.label("", 18, Color(1.0, 0.82, 0.3))
	box.add_child(_gold)
	box.add_child(HSeparator.new())

	for a in StatBlock.ATTRIBUTES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		box.add_child(row)
		var texts := VBoxContainer.new()
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(texts)
		var value := UiTheme.label("", 19, UiTheme.TEXT)
		texts.add_child(value)
		var effect := UiTheme.label(ATTR_EFFECTS[a], 13, UiTheme.MUTED)
		effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		texts.add_child(effect)
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(150, 0)
		button.pressed.connect(_on_buy.bind(a))
		row.add_child(button)
		_attr_value[a] = value
		_attr_effect[a] = effect
		_attr_button[a] = button

	_feedback = UiTheme.label("", 16, UiTheme.HP)
	_feedback.modulate.a = 0.0
	box.add_child(_feedback)
	box.add_child(HSeparator.new())
	_derived = UiTheme.label("", 15, UiTheme.TEXT)
	box.add_child(_derived)


func bind(m: MatchController) -> void:
	_match = m
	m.local_hero.stats_changed.connect(func(_h: Hero) -> void: refresh())
	m.gold.balance_changed.connect(func(_p: int, _b: int) -> void: refresh())


func toggle() -> void:
	if visible:
		close()
	else:
		visible = true
		Audio.play("ui_open")
		refresh()


func close() -> void:
	if visible:
		Audio.play("ui_close")
	visible = false


func refresh() -> void:
	if _match == null or not visible:
		return
	var hero := _match.local_hero
	var s := hero.stats
	var balance := _match.gold.balance(hero.peer_id)
	_title.text = "%s  –  Stufe %d" % [hero.data.name, s.level]
	_gold.text = "%s Gold" % UiTheme.format_int(balance)
	for a in StatBlock.ATTRIBUTES:
		var main_mark := "  ★" if a == hero.data.main_attribute else ""
		var bought: int = s.bought[a]
		var bought_text := "  (+%d gekauft)" % bought if bought > 0 else ""
		(_attr_value[a] as Label).text = "%s%s:  %.0f%s" % [GameData.ATTRIBUTE_NAMES[a], main_mark, s.attribute(a), bought_text]
		var cost := s.upgrade_cost(a)
		(_attr_effect[a] as Label).text = "%s\n%s" % [ATTR_EFFECTS[a], UiTheme.format_attribute_upgrade(hero, a)]
		var button: Button = _attr_button[a]
		button.text = "+1   ·   %s Gold" % UiTheme.format_int(cost)
		button.disabled = balance < cost
		var cap_note := "\nÜber dem Soft Cap von %d Punkten wirkt jeder weitere Punkt nur halb." % int(s.rules.upgrade.soft_cap) if s.is_beyond_soft_cap(a) else ""
		button.tooltip_text = ("Nicht genug Gold (%d fehlen)." % (cost - balance) if balance < cost else "Kaufen") + cap_note
	var reduction := 1.0 - _match.combat.armor_constant / (_match.combat.armor_constant + s.armor())
	var mr_reduction := 1.0 - _match.combat.armor_constant / (_match.combat.armor_constant + s.magic_resist())
	_derived.text = "\n".join([
		"Leben  %s   (+%.1f/s)" % [UiTheme.format_int(s.max_hp()), s.hp_regen()],
		"Mana  %s   (+%.1f/s)" % [UiTheme.format_int(s.max_mana()), s.mana_regen()],
		"Angriff  %.0f %s   ·   %.2f Angriffe/s   ·   Reichweite %.1f m" % [s.attack_damage(), "magisch" if hero.data.damage_type == "magic" else "physisch", 1.0 / s.attack_interval(), s.attack_range()],
		"Krit-Chance  %.1f %%   (×%.2f)" % [s.crit_chance() * 100.0, s.crit_multiplier()],
		"Rüstung  %.1f  (−%.0f %% phys.)   ·   Magieresistenz  %.1f  (−%.0f %% mag.)" % [s.armor(), reduction * 100.0, s.magic_resist(), mr_reduction * 100.0],
		"Lauftempo  %.2f m/s   ·   Fähigkeitsstärke  %.0f %%   ·   Heilungsstärke  %.0f %%" % [s.move_speed(), s.ability_power() * 100.0, s.heal_power() * 100.0],
		"XP  %s" % ("%d / %d" % [s.xp, s.xp_to_next()] if s.xp_to_next() > 0 else "Höchststufe"),
	])


func _on_buy(attribute: String) -> void:
	var result := _match.request_attribute_upgrade(attribute)
	_feedback.text = result.message
	_feedback.add_theme_color_override("font_color", UiTheme.HP if result.ok else UiTheme.DANGER)
	if _feedback_tween != null:
		_feedback_tween.kill()
	_feedback.modulate.a = 1.0
	_feedback_tween = create_tween()
	_feedback_tween.tween_interval(2.5)
	_feedback_tween.tween_property(_feedback, "modulate:a", 0.0, 0.6)
	refresh()
