class_name TeamOverview
extends PanelContainer
## Teamübersicht (Tab gedrückt halten): Spieler, Held, Stufe, Leben, Gold, Beiträge der laufenden Welle, Team-Gold.

var _match: MatchController
var _body: Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.BG_SOLID))
	UiTheme.place(self, Control.PRESET_CENTER, -420, -170, 420, -170, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	box.add_child(UiTheme.label("Team", 24, UiTheme.ACCENT))
	_body = UiTheme.label("", 15, UiTheme.TEXT)
	box.add_child(_body)


func bind(m: MatchController) -> void:
	_match = m


func _process(_delta: float) -> void:
	if not visible or _match == null:
		return
	var lines: PackedStringArray = ["Team-Gold: %s" % UiTheme.format_int(_match.gold.team_balance()), ""]
	for hero in _match.heroes:
		if not is_instance_valid(hero):
			continue
		var w := _match.rewards.wave_stats(hero.peer_id)
		lines.append("Spieler %d  ·  %s (%s)  ·  Stufe %d  ·  Leben %s/%s  ·  %s Gold%s" % [hero.peer_id, hero.data.name, hero.data.archetype,
			hero.stats.level, UiTheme.format_int(hero.health.hp), UiTheme.format_int(hero.health.max_hp),
			UiTheme.format_int(_match.gold.balance(hero.peer_id)), "  ·  AFK" if hero.idle_time >= _match.rewards.afk_seconds else ""])
		lines.append("    Diese Welle:  Schaden %d  ·  Heilung %d  ·  Schild %d  ·  verhindert %d  ·  Kontrolle %.1f  ·  abgefangen %d" % [
			w.damage, w.heal, w.shield, w.prevented, w.control, w.tank])
	_body.text = "\n".join(lines)
