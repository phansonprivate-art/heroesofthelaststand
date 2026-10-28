class_name UiTheme
extends RefCounted
## Gemeinsame Farben, Stile und Bausteine der Oberfläche, damit alle Fenster gleich aussehen.

const BG := Color(0.06, 0.08, 0.12, 0.86)
const BG_SOLID := Color(0.08, 0.1, 0.15, 0.97)
const BORDER := Color(0.85, 0.68, 0.32, 0.5)
const TEXT := Color(0.94, 0.95, 0.97)
const MUTED := Color(0.64, 0.68, 0.76)
const ACCENT := Color(0.93, 0.74, 0.32)
const HP := Color(0.36, 0.8, 0.42)
const CORE := Color(0.36, 0.78, 1.0)
const DANGER := Color(0.93, 0.3, 0.27)


static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("normal", "Button", _button_box(Color(0.14, 0.17, 0.24), BORDER))
	t.set_stylebox("hover", "Button", _button_box(Color(0.2, 0.24, 0.33), ACCENT))
	t.set_stylebox("pressed", "Button", _button_box(Color(0.1, 0.12, 0.17), ACCENT))
	t.set_stylebox("focus", "Button", _button_box(Color(0.2, 0.24, 0.33), ACCENT))
	t.set_stylebox("disabled", "Button", _button_box(Color(0.1, 0.11, 0.14), Color(0.3, 0.3, 0.35)))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", MUTED)
	t.set_font_size("font_size", "Button", 20)
	return t


static func panel(bg := BG, border := BORDER, radius := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


static func label(text: String, size := 18, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Balken mit Text darüber ("850 / 900"). Gibt [Container, ProgressBar, Label] zurück.
static func bar(fill: Color, width := 320.0, height := 22.0) -> Array:
	var box := Control.new()
	box.custom_minimum_size = Vector2(width, height)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.set_anchors_preset(Control.PRESET_FULL_RECT)
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.04, 0.06, 0.9)
	bg.set_corner_radius_all(5)
	bg.border_color = Color(0, 0, 0, 0.8)
	bg.set_border_width_all(1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(5)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fg)
	box.add_child(pb)
	var l := label("", int(height * 0.7), TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(l)
	return [box, pb, l]


const STAT_NAMES := {
	"attack_damage": "Angriff", "armor": "Rüstung", "max_hp": "Leben", "magic_resist": "Magieresistenz",
	"move_speed": "Tempo", "str": "Stärke", "agi": "Beweglichkeit", "int": "Intelligenz", "attack_speed": "Angriffstempo",
	"max_mana": "Mana", "ability_power": "Fähigkeitsstärke", "heal_power": "Heilungsstärke", "hp_regen": "LP/s",
}
const PERCENT_STATS := ["attack_speed", "ability_power", "heal_power"]

## Bezeichnungen der Fähigkeitswerte; "%" = als Prozent anzeigen, "s" = Sekunden, "m" = Meter.
const SKILL_VALUE_NAMES := {
	"mana": ["Mana", ""], "cooldown": ["Abklingzeit", "s"],
	"damage": ["Schaden", ""], "stun": ["Betäubung", "s"], "radius": ["Radius", "m"], "duration": ["Dauer", "s"],
	"shield": ["Schild", ""], "dps": ["Schaden/s je Stapel", ""], "max_stacks": ["max. Stapel", ""], "slow": ["Verlangsamung", "%"],
	"heal": ["Heilung", ""], "reduction": ["Schadensreduktion", "%"], "haste": ["Angriffstempo", "%"], "armor": ["Rüstung", ""],
	"self_reduction": ["eigene Schadensreduktion", "%"], "ally_reduction": ["Verbündete", "%"], "taunt": ["Spott", "s"],
	"move": ["Lauftempo", "%"], "crit": ["Krit-Chance", "%"], "impacts": ["Einschläge", ""], "impact_radius": ["Einschlagradius", "m"],
	"always_crit": ["immer kritisch", "bool"], "range": ["Reichweite", "m"],
}
## Werte, die mit Attributen/Fähigkeitsstärke skalieren (werden für den Helden ausgerechnet angezeigt)
const SCALED_SKILL_VALUES := ["damage", "shield", "dps", "heal"]


## "Angriff +14 · Tempo +0.6"
static func format_stats(stats: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key in stats:
		var v := float(stats[key])
		if key in PERCENT_STATS:
			parts.append("%s +%d %%" % [STAT_NAMES.get(key, key), roundi(v * 100.0)])
		else:
			parts.append("%s +%s" % [STAT_NAMES.get(key, key), str(snappedf(v, 0.1))])
	return "  ·  ".join(parts)


## Werte einer Fähigkeitsstufe als Text, skalierende Werte für den Helden ausgerechnet.
static func format_skill_level(id: String, level: int, hero: Hero) -> String:
	var parts: PackedStringArray = []
	for key in _skill_keys(id, level, level):
		var value := _skill_value_text(id, level, key, hero)
		if value != "":
			parts.append(SKILL_VALUE_NAMES[key][0] if SKILL_VALUE_NAMES[key][1] == "bool" else "%s %s" % [SKILL_VALUE_NAMES[key][0], value])
	var text := "  ·  ".join(parts)
	var scaling := scaling_text(id, hero)
	return text + ("\n" + scaling if scaling != "" else "")


## Was eine Verbesserung bringt – nur die geänderten Werte, z. B. "Schaden 40 → 55  ·  Abklingzeit 6 s → 5 s".
static func format_skill_upgrade(id: String, from_level: int, to_level: int, hero: Hero) -> String:
	var parts: PackedStringArray = []
	for key in _skill_keys(id, from_level, to_level):
		var before := _skill_value_text(id, from_level, key, hero)
		var after := _skill_value_text(id, to_level, key, hero)
		if before == after:
			continue
		var name: String = SKILL_VALUE_NAMES[key][0]
		if SKILL_VALUE_NAMES[key][1] == "bool":
			parts.append(("neu: %s" if after != "" else "entfällt: %s") % name)
		elif before == "":
			parts.append("neu: %s %s" % [name, after])
		else:
			parts.append("%s %s → %s" % [name, before, after])
	return "  ·  ".join(parts) if not parts.is_empty() else "keine Wertänderung"


## Anzeigbare Werte zweier Stufen in fester Reihenfolge: Mana, Abklingzeit, dann wie in den Daten.
static func _skill_keys(id: String, level_a: int, level_b: int) -> PackedStringArray:
	var keys: PackedStringArray = ["mana", "cooldown"]
	for level in [level_a, level_b]:
		for key in GameData.skill(id).levels[clampi(level, 1, 3) - 1]:
			if SKILL_VALUE_NAMES.has(key) and not keys.has(key):
				keys.append(key)
	return keys


## Ein Wert einer Stufe als Text mit Einheit ("" = auf dieser Stufe nicht vorhanden).
static func _skill_value_text(id: String, level: int, key: String, hero: Hero) -> String:
	var lv: Dictionary = GameData.skill(id).levels[clampi(level, 1, 3) - 1]
	if not lv.has(key):
		return ""
	var v := float(lv[key])
	if key in GameData.skill(id).get("scaled_keys", SCALED_SKILL_VALUES) and hero != null:
		v = AbilityEffects.power(id, level, key, hero)
	match SKILL_VALUE_NAMES[key][1]:
		"%": return "%d %%" % roundi(v * 100.0)
		"bool": return "ja" if v > 0.0 else ""
		"": return "%d" % roundi(v)
		_: return "%s %s" % [_trim_number(snappedf(v, 0.1)), SKILL_VALUE_NAMES[key][1]]


## Was +1 gekaufter Attributpunkt konkret bringt (abgeleitete Werte und gelernte Fähigkeiten).
static func format_attribute_upgrade(hero: Hero, a: String) -> String:
	var s := hero.stats
	var p := s.preview_with_point(a)
	var rows := [
		[GameData.ATTRIBUTE_NAMES[a], s.attribute(a), p.attribute(a), 1.0, ""],
		["Leben", s.max_hp(), p.max_hp(), 1.0, ""],
		["LP-Reg.", s.hp_regen(), p.hp_regen(), 1.0, "/s"],
		["Mana", s.max_mana(), p.max_mana(), 1.0, ""],
		["Mana-Reg.", s.mana_regen(), p.mana_regen(), 1.0, "/s"],
		["Angriff", s.attack_damage(), p.attack_damage(), 1.0, ""],
		["Angriffstempo", s.attack_speed_bonus(), p.attack_speed_bonus(), 100.0, " %"],
		["Krit", s.crit_chance(), p.crit_chance(), 100.0, " %"],
		["Lauftempo", s.move_speed(), p.move_speed(), 1.0, " m/s"],
		["Rüstung", s.armor(), p.armor(), 1.0, ""],
		["Magieresistenz", s.magic_resist(), p.magic_resist(), 1.0, ""],
		["Fähigkeitsstärke", s.ability_power(), p.ability_power(), 100.0, " %"],
		["Heilungsstärke", s.heal_power(), p.heal_power(), 100.0, " %"],
	]
	var parts: PackedStringArray = []
	for r in rows:
		var delta: float = (float(r[2]) - float(r[1])) * float(r[3])
		if absf(delta) >= 0.005:
			parts.append("%s +%s%s" % [r[0], _trim_number(delta), r[4]])
	var skills: PackedStringArray = []
	for id in GameData.skill_order:
		var lvl := hero.abilities.level_of(id)
		if lvl <= 0:
			continue
		for key in GameData.skill(id).get("scaled_keys", []):
			var delta := AbilityEffects.power_for_stats(id, lvl, key, p) - AbilityEffects.power_for_stats(id, lvl, key, s)
			if delta >= 0.05:
				skills.append("%s +%s %s" % [GameData.skill(id).name, _trim_number(delta), SKILL_VALUE_NAMES.get(key, [key])[0]])
				break
	var text := "+1 bringt: " + "  ·  ".join(parts)
	return text + ("\nFähigkeiten: " + "  ·  ".join(skills) if not skills.is_empty() else "")


## 0.12 -> "0.12", 1.50 -> "1.5", 20.0 -> "20"
static func _trim_number(v: float) -> String:
	var t := "%.2f" % v
	return t.rstrip("0").rstrip(".")


## "Skalierung: 1,6 × Intelligenz (+40)" – zeigt, wie stark Attribute die Fähigkeit verbessern.
static func scaling_text(id: String, hero: Hero) -> String:
	var scaling: Dictionary = GameData.skill(id).get("scaling", {})
	if scaling.is_empty():
		return ""
	var parts: PackedStringArray = []
	for attr in scaling:
		var f := float(scaling[attr])
		var bonus := f * hero.stats.attribute(attr) if hero != null else 0.0
		var shown := ("%.1f" % f).replace(".", ",") if f >= 0.1 else ("%.3f" % f).replace(".", ",")
		parts.append("%s × %s (%s)" % [shown, GameData.ATTRIBUTE_NAMES[attr], ("+%d %%" % roundi(bonus * 100.0)) if f < 0.1 else ("+%d" % roundi(bonus))])
	return "Skalierung: " + "  ·  ".join(parts)


## Setzt Anker und Abstände in einem Schritt (Abstände relativ zu den Ankern).
static func place(c: Control, preset: Control.LayoutPreset, left: float, top: float, right: float, bottom: float,
		grow_h := Control.GROW_DIRECTION_BOTH, grow_v := Control.GROW_DIRECTION_END) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = left
	c.offset_top = top
	c.offset_right = right
	c.offset_bottom = bottom
	c.grow_horizontal = grow_h
	c.grow_vertical = grow_v


## Ganze Zahl mit Tausenderpunkt, z. B. 10.000
static func format_int(value: float) -> String:
	var s := str(int(roundf(value)))
	var negative := s.begins_with("-")
	if negative:
		s = s.substr(1)
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if negative else "") + s + out


static func _button_box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := panel(bg, border, 8)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s
