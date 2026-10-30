class_name Hud
extends CanvasLayer
## Haupt-HUD: Kernzustand, Welle, verbleibende Gegner, eigener Held (Stufe, XP, LP, Mana, Gold),
## Ankündigungen und das Charakterfenster (C).
## Zeigt nur Werte an, die es im Spiel tatsächlich gibt; neue Anzeigen kommen mit ihren Systemen.

const STATUS_NAMES := {"slow": "Verlangsamt", "stun": "Betäubt", "poison": "Vergiftet", "taunt": "Verspottet",
	"damage_reduction": "Geschützt", "haste": "Eile", "swift": "Schnell", "crit_bonus": "Kritisch", "armor_bonus": "Gepanzert",
	"untargetable": "Unverwundbar", "channel": "Kanalisiert", "whirl": "Wirbelt", "sanctuary": "Am Brunnen – Erholung, kein Kampf"}
const XP_COLOR := Color(0.72, 0.5, 1.0)

var _match: MatchController
var _root: Control
var _core_bar: ProgressBar
var _core_label: Label
var _wave_title: Label
var _wave_status: Label
var _wave_button: Button
var _hero_name: Label
var _xp_bar: ProgressBar
var _xp_label: Label
var _xp_box: Control
var _xp_tween: Tween
var _hero_bar: ProgressBar
var _hero_label: Label
var _mana_bar: ProgressBar
var _mana_label: Label
var _gold_label: Label
var _team_gold_label: Label
var _upgrade_affordable := false
var _upgrade_hint: Button
var _status_label: Label
var _respawn_label: Label
var _banner: Label
var _banner_sub: Label
var _banner_tween: Tween
var _critical_overlay: ColorRect
var _critical_time := 0.0
var _character_window: CharacterWindow
var _shop: ShopWindow
var _inventory: InventoryWindow
var _team: TeamOverview
var _ability_bar: AbilityBar
var _hint_label: Label
var _hint_tween: Tween
var _boss_box: Control
var _boss_name: Label
var _boss_bar: ProgressBar
var _boss_label: Label
var _boss: Enemy
var _minimap: Minimap


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.build_theme()
	add_child(_root)
	_build_critical_overlay()
	_build_top()
	_build_hero_panel()
	_build_banner()
	_build_hint()
	_minimap = Minimap.new()
	_minimap.name = "Minimap"
	_root.add_child(_minimap)
	_ability_bar = AbilityBar.new()
	_root.add_child(_ability_bar)
	_hint_label = UiTheme.label("", 17, UiTheme.DANGER, HORIZONTAL_ALIGNMENT_CENTER)
	UiTheme.place(_hint_label, Control.PRESET_CENTER_BOTTOM, -300, -128, 300, -104)
	_hint_label.modulate.a = 0.0
	_root.add_child(_hint_label)
	_character_window = CharacterWindow.new()
	_root.add_child(_character_window)
	_inventory = InventoryWindow.new()
	_root.add_child(_inventory)
	_shop = ShopWindow.new()
	_root.add_child(_shop)
	_team = TeamOverview.new()
	_root.add_child(_team)


func bind(m: MatchController) -> void:
	_match = m
	m.core.health.changed.connect(_on_core_changed)
	m.core.critical_changed.connect(_on_core_critical)
	_on_core_changed(m.core.health.hp, m.core.health.max_hp)
	m.wave_manager.wave_announced.connect(_on_wave_announced)
	m.wave_manager.wave_started.connect(_on_wave_started)
	m.wave_manager.wave_completed.connect(_on_wave_completed)
	m.spawner.enemy_spawned.connect(_on_enemy_spawned)
	m.camera_rig.lock_changed.connect(func(locked: bool) -> void:
		show_banner("Kamera fixiert" if locked else "Kamera gelöst", "" if locked else "Mauszeiger an den Bildschirmrand: verschieben  ·  Leertaste: zentrieren", UiTheme.TEXT, 1.2))
	var hero := m.local_hero
	_hero_name.text = "%s  ·  %s" % [hero.data.name, hero.data.role]
	_hero_name.add_theme_color_override("font_color", hero.data.color)
	hero.health.changed.connect(_on_hero_changed)
	hero.mana_changed.connect(_on_mana_changed)
	hero.stats_changed.connect(func(_h: Hero) -> void: _refresh_progress())
	hero.leveled_up.connect(_on_level_up)
	hero.status.effects_changed.connect(_refresh_status)
	hero.died.connect(func(_h: Hero) -> void: show_banner("Du bist gefallen", "Wiederbelebung am Kern …", UiTheme.DANGER))
	m.rewards.xp_awarded.connect(_on_xp_awarded)
	m.gold.balance_changed.connect(func(peer: int, _b: int) -> void:
		if peer == hero.peer_id or peer == GoldService.TEAM_PEER:
			_refresh_progress())
	_on_hero_changed(hero.health.hp, hero.health.max_hp)
	_on_mana_changed(hero.mana, hero.stats.max_mana())
	_refresh_progress()
	_minimap.bind(m)
	_character_window.bind(m)
	_ability_bar.bind(m)
	_ability_bar.shop_requested.connect(func(tab: int) -> void: _shop.open(tab))
	_shop.bind(m)
	_inventory.bind(m)
	_team.bind(m)
	m.local_hero.abilities.cast_failed.connect(func(_h: Hero, _id: String, reason: String) -> void: show_hint(reason))


func _process(delta: float) -> void:
	if _match == null:
		return
	_update_wave_status()
	var hero := _match.local_hero
	_respawn_label.visible = not hero.is_alive()
	if not hero.is_alive():
		_respawn_label.text = "Wiederbelebung in %d s" % ceili(hero.respawn_left)
	if _match.core.critical and _match.core.is_alive():
		_critical_time += delta
		_critical_overlay.color.a = 0.10 + 0.08 * sin(_critical_time * 6.0)
	else:
		_critical_overlay.color.a = 0.0
	if _upgrade_affordable:
		_upgrade_hint.modulate.a = 0.75 + 0.25 * sin(Time.get_ticks_msec() / 180.0)


func _unhandled_input(event: InputEvent) -> void:
	if _match == null or _match.phase != MatchController.Phase.RUNNING:
		return
	if event.is_action_pressed("open_character"):
		_character_window.toggle()
	elif event.is_action_pressed("open_shop"):
		_shop.toggle()
	elif event.is_action_pressed("open_inventory"):
		_inventory.toggle()
	elif event.is_action_pressed("team_overview"):
		_team.visible = true
	elif event.is_action_released("team_overview"):
		_team.visible = false
	elif event.is_action_pressed("pause") and _any_window_open():
		close_windows()   # Esc schließt zuerst offene Fenster, erst dann öffnet sich die Pause
	else:
		return
	get_viewport().set_input_as_handled()


## Kurze Meldung über der Fähigkeitsleiste (z. B. warum eine Fähigkeit nicht wirkt).
func show_hint(text: String) -> void:
	_hint_label.text = text
	if _hint_tween != null:
		_hint_tween.kill()
	_hint_label.modulate.a = 1.0
	_hint_tween = create_tween()
	_hint_tween.tween_interval(1.4)
	_hint_tween.tween_property(_hint_label, "modulate:a", 0.0, 0.4)


func _any_window_open() -> bool:
	return _character_window.visible or _shop.visible or _inventory.visible


func close_windows() -> void:
	_character_window.close()
	_shop.close()
	_inventory.close()
	_team.visible = false


func show_banner(title: String, sub := "", color := UiTheme.ACCENT, seconds := 2.6) -> void:
	_banner.text = title
	_banner.add_theme_color_override("font_color", color)
	_banner_sub.text = sub
	if _banner_tween != null:
		_banner_tween.kill()
	_banner.modulate.a = 0.0
	_banner_sub.modulate.a = 0.0
	_banner_tween = create_tween().set_parallel(true)
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.25)
	_banner_tween.tween_property(_banner_sub, "modulate:a", 1.0, 0.25)
	_banner_tween.chain().tween_interval(seconds)
	_banner_tween.chain().tween_property(_banner, "modulate:a", 0.0, 0.5)
	_banner_tween.parallel().tween_property(_banner_sub, "modulate:a", 0.0, 0.5)


## Mini-Boss und Endboss: Ankündigung, Bossleiste mit Phase, Phasenwechsel und Sieg als Banner.
func _on_enemy_spawned(e: Enemy) -> void:
	var category := String(e.data.get("category", "normal"))
	if category != "boss" and category != "miniboss":
		return
	if category == "miniboss" and _boss != null and is_instance_valid(_boss) and _boss.is_alive() and _boss.brain != null:
		show_banner(String(e.data.name), "Ein Mini-Boss verstärkt den Endboss!", UiTheme.DANGER, 2.5)
		return   # die Leiste bleibt beim Endboss
	_boss = e
	var title: String = e.brain.title() if e.brain != null else String(e.data.name)
	_boss_name.text = title
	_boss_box.visible = true
	_on_boss_health(e, e.health.hp, e.health.max_hp)
	e.health.changed.connect(func(current: float, maximum: float) -> void: _on_boss_health(e, current, maximum))
	e.died.connect(func(dead: Enemy, _i: DamageInfo) -> void:
		if dead == _boss:
			_boss_box.visible = false
			_boss = null)
	if e.brain != null:
		show_banner(title, "Der Endkampf beginnt – achtet auf die Warnkreise am Boden!", UiTheme.DANGER, 3.5)
		e.brain.phase_changed.connect(func(_p: int, text: String, sub: String) -> void:
			show_banner(text, sub, UiTheme.DANGER, 3.0)
			_on_boss_health(e, e.health.hp, e.health.max_hp))
		e.brain.defeated.connect(func() -> void: show_banner("%s ist gefallen!" % title, "", UiTheme.ACCENT, 3.0))
	else:
		show_banner(title, "Ein Mini-Boss betritt die Arena – weicht seinen Bodenschlägen aus!", UiTheme.DANGER, 3.0)


func _on_boss_health(e: Enemy, current: float, maximum: float) -> void:
	if e != _boss:
		return
	_boss_bar.max_value = maximum
	_boss_bar.value = current
	var phase_text := "  ·  Phase %d / 3" % e.brain.phase if e.brain != null else ""
	_boss_label.text = "%s / %s%s" % [UiTheme.format_int(current), UiTheme.format_int(maximum), phase_text]


func clear_banner() -> void:
	if _banner_tween != null:
		_banner_tween.kill()
	_banner.modulate.a = 0.0
	_banner_sub.modulate.a = 0.0
	close_windows()


func _update_wave_status() -> void:
	var wm := _match.wave_manager
	var wave := wm.current_wave()
	_wave_title.text = "Welle %d / %d  ·  %s" % [wm.current_wave_number(), wm.total_waves(), wave.get("name", "")]
	_wave_button.visible = wm.state == WaveManager.State.PREPARING
	match wm.state:
		WaveManager.State.PREPARING:
			_wave_status.text = "Beginnt in %d s  ·  %s" % [ceili(wm.prepare_left), WaveManager.describe(wave)]
		WaveManager.State.SPAWNING, WaveManager.State.CLEARING:
			var alive := _match.spawner.alive_count()
			var pending := wm.remaining_to_spawn()
			_wave_status.text = "Gegner: %d" % alive + ("  (+%d unterwegs)" % pending if pending > 0 else "")
		WaveManager.State.FINISHED:
			_wave_status.text = "Alle Wellen abgewehrt" if _match.core.is_alive() else "Der Kern ist gefallen"
		_:
			_wave_status.text = ""


func _refresh_progress() -> void:
	var hero := _match.local_hero
	var stats := hero.stats
	_xp_bar.max_value = 1.0
	_xp_bar.value = stats.xp_ratio()
	if stats.xp_to_next() > 0:
		_xp_label.text = "Stufe %d   ·   %d / %d XP" % [stats.level, stats.xp, stats.xp_to_next()]
	else:
		_xp_label.text = "Stufe %d   ·   Höchststufe" % stats.level
	var balance := _match.gold.balance(hero.peer_id)
	_gold_label.text = "%s Gold" % UiTheme.format_int(balance)
	_team_gold_label.text = "Team-Gold %s" % UiTheme.format_int(_match.gold.team_balance())
	var affordable := false
	for a in StatBlock.ATTRIBUTES:
		if balance >= stats.upgrade_cost(a):
			affordable = true
	# Ein Knopf: "Charakter", der golden pulsiert, sobald ein Attribut-Kauf möglich ist
	_upgrade_affordable = affordable
	_upgrade_hint.text = "Verbessern [C]" if affordable else "Charakter [C]"
	_upgrade_hint.add_theme_color_override("font_color", UiTheme.ACCENT if affordable else UiTheme.TEXT)
	if not affordable:
		_upgrade_hint.modulate.a = 1.0
	_on_mana_changed(hero.mana, stats.max_mana())


func _refresh_status() -> void:
	var names: PackedStringArray = []
	for id in _match.local_hero.status.active_ids():
		names.append(STATUS_NAMES.get(id, id))
	_status_label.text = "  ·  ".join(names)
	_status_label.visible = not names.is_empty()


func _on_core_changed(current: float, maximum: float) -> void:
	_core_bar.max_value = maximum
	_core_bar.value = current
	_core_label.text = "KERN   %s / %s" % [UiTheme.format_int(current), UiTheme.format_int(maximum)]


func _on_core_critical(is_critical: bool) -> void:
	var fill := _core_bar.get_theme_stylebox("fill") as StyleBoxFlat
	fill.bg_color = UiTheme.DANGER if is_critical else UiTheme.CORE
	if is_critical:
		show_banner("Der Kern ist in Gefahr!", "Verteidigt ihn!", UiTheme.DANGER)


func _on_hero_changed(current: float, maximum: float) -> void:
	_hero_bar.max_value = maximum
	_hero_bar.value = current
	_hero_label.text = "%s / %s" % [UiTheme.format_int(current), UiTheme.format_int(maximum)]


func _on_mana_changed(current: float, maximum: float) -> void:
	_mana_bar.max_value = maximum
	_mana_bar.value = current
	_mana_label.text = "%s / %s" % [UiTheme.format_int(current), UiTheme.format_int(maximum)]


## XP-Gewinn: Leiste kurz aufleuchten lassen und "+12 XP" über dem Helden zeigen.
func _on_xp_awarded(peer_id: int, amount: int) -> void:
	var hero := _match.local_hero
	if peer_id != hero.peer_id or amount <= 0:
		return
	_match.floating_text.spawn_text("+%d XP" % amount, hero.global_position + Vector3(0.6, 2.6, 0), XP_COLOR.lightened(0.2), 36)
	if _xp_tween != null:
		_xp_tween.kill()
	_xp_box.modulate = Color(1.6, 1.4, 1.9)
	_xp_tween = create_tween()
	_xp_tween.tween_property(_xp_box, "modulate", Color.WHITE, 0.5)


func _on_level_up(_hero: Hero, level: int) -> void:
	show_banner("Stufe %d erreicht!" % level, "Attribute gestiegen  ·  mit Gold weiter verbessern: [C]", UiTheme.ACCENT, 2.0)
	_match.floating_text.spawn_burst(_match.local_hero.global_position, UiTheme.ACCENT)


func _on_wave_announced(number: int, wave: Dictionary, seconds: float) -> void:
	if number == 1 and _match.local_hero.abilities.levels.is_empty():
		show_banner("Welle 1: %s" % wave.name, "Tipp: B öffnet den Shop – lerne deine erste Fähigkeit (300 Gold), sie landet auf Q", UiTheme.ACCENT, 6.0)
		return
	show_banner("Welle %d: %s" % [number, wave.name], "Beginnt in %d Sekunden  ·  %s" % [ceili(seconds), WaveManager.describe(wave)])


func _on_wave_started(number: int, _wave: Dictionary) -> void:
	show_banner("Welle %d beginnt!" % number, "Die Tore öffnen sich", UiTheme.DANGER, 1.6)


func _on_wave_completed(number: int) -> void:
	show_banner("Welle %d abgewehrt" % number, "+%d Gold Wellenbonus" % _match.rewards.wave_bonus_gold, UiTheme.HP, 2.0)


# --- Aufbau ---------------------------------------------------------------

func _build_top() -> void:
	var top := VBoxContainer.new()
	UiTheme.place(top, Control.PRESET_CENTER_TOP, -280, 14, 280, 14)
	top.add_theme_constant_override("separation", 6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(top)

	var core_parts := UiTheme.bar(UiTheme.CORE, 560, 26)
	_core_bar = core_parts[1]
	_core_label = core_parts[2]
	# eigenes Füll-StyleBox, damit die Farbe bei kritischem Zustand umschalten kann
	_core_bar.add_theme_stylebox_override("fill", (_core_bar.get_theme_stylebox("fill") as StyleBoxFlat).duplicate())
	top.add_child(core_parts[0])

	var wave_panel := PanelContainer.new()
	wave_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(wave_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wave_panel.add_child(row)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	_wave_title = UiTheme.label("", 20, UiTheme.ACCENT)
	_wave_status = UiTheme.label("", 16, UiTheme.MUTED)
	_wave_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(_wave_title)
	texts.add_child(_wave_status)
	_wave_button = Button.new()
	_wave_button.text = "Jetzt starten [N]"
	_wave_button.focus_mode = Control.FOCUS_NONE
	_wave_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_wave_button.pressed.connect(func() -> void: _match.wave_manager.skip_preparation())
	row.add_child(_wave_button)

	# Bossleiste: nur sichtbar, solange ein Mini-Boss oder der Endboss lebt
	var boss_box := VBoxContainer.new()
	boss_box.add_theme_constant_override("separation", 2)
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_box.visible = false
	top.add_child(boss_box)
	_boss_box = boss_box
	_boss_name = UiTheme.label("", 20, UiTheme.DANGER, HORIZONTAL_ALIGNMENT_CENTER)
	_boss_name.add_theme_constant_override("outline_size", 6)
	boss_box.add_child(_boss_name)
	var boss_parts := UiTheme.bar(Color(0.62, 0.22, 0.85), 560, 22)
	_boss_bar = boss_parts[1]
	_boss_label = boss_parts[2]
	boss_box.add_child(boss_parts[0])


func _build_hero_panel() -> void:
	var panel := PanelContainer.new()
	UiTheme.place(panel, Control.PRESET_BOTTOM_LEFT, 18, -18, 18, -18, Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BEGIN)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	_hero_name = UiTheme.label("", 18, UiTheme.ACCENT)
	_hero_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_hero_name)

	var xp_parts := UiTheme.bar(XP_COLOR, 400, 20)
	_xp_bar = xp_parts[1]
	_xp_label = xp_parts[2]
	_xp_box = xp_parts[0]
	box.add_child(_xp_box)
	var hp_parts := UiTheme.bar(UiTheme.HP, 400, 24)
	_hero_bar = hp_parts[1]
	_hero_label = hp_parts[2]
	box.add_child(hp_parts[0])
	var mana_parts := UiTheme.bar(Color(0.3, 0.55, 1.0), 400, 16)
	_mana_bar = mana_parts[1]
	_mana_label = mana_parts[2]
	box.add_child(mana_parts[0])

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	box.add_child(foot)
	_gold_label = UiTheme.label("", 18, Color(1.0, 0.82, 0.3))
	_gold_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_gold_label)
	_upgrade_hint = Button.new()
	_upgrade_hint.text = "Verbessern [C]"
	_upgrade_hint.focus_mode = Control.FOCUS_NONE
	_upgrade_hint.add_theme_font_size_override("font_size", 15)
	_upgrade_hint.add_theme_color_override("font_color", UiTheme.ACCENT)
	_upgrade_hint.pressed.connect(func() -> void: _character_window.toggle())
	foot.add_child(_upgrade_hint)

	_team_gold_label = UiTheme.label("", 14, Color(0.55, 0.85, 1.0))
	box.add_child(_team_gold_label)
	_status_label = UiTheme.label("", 15, Color(0.55, 0.8, 1.0))
	_status_label.visible = false
	box.add_child(_status_label)
	_respawn_label = UiTheme.label("", 16, UiTheme.DANGER)
	_respawn_label.visible = false
	box.add_child(_respawn_label)


func _build_banner() -> void:
	var box := VBoxContainer.new()
	UiTheme.place(box, Control.PRESET_CENTER, -500, -230, 500, -230)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	_banner = UiTheme.label("", 44, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_banner.add_theme_constant_override("outline_size", 10)
	_banner_sub = UiTheme.label("", 20, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_banner.modulate.a = 0.0
	_banner_sub.modulate.a = 0.0
	box.add_child(_banner)
	box.add_child(_banner_sub)


func _build_hint() -> void:
	# Kurz halten: die vollständige Steuerung steht im Pausemenü
	var hint := UiTheme.label("B: Shop  ·  Esc: Pause & Steuerung", 13, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	UiTheme.place(hint, Control.PRESET_TOP_RIGHT, -18, 12, -18, 12, Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END)
	_root.add_child(hint)


func _build_critical_overlay() -> void:
	_critical_overlay = ColorRect.new()
	_critical_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_critical_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
	float d = distance(UV, vec2(0.5));
	COLOR = vec4(COLOR.rgb, COLOR.a * smoothstep(0.35, 0.75, d) * 3.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_critical_overlay.material = mat
	_critical_overlay.color = Color(UiTheme.DANGER, 0.0)
	_root.add_child(_critical_overlay)
