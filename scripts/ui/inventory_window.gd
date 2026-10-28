class_name InventoryWindow
extends PanelContainer
## Inventar (I): sechs Ausrüstungsslots, Tasche, zwei Verbrauchsslots. Ablegen, Anlegen/Tauschen,
## Verkaufen (zum festen Rückkaufanteil) und Benutzen.

var _match: MatchController
var _list: VBoxContainer
var _feedback: Label
var _feedback_tween: Tween


func _ready() -> void:
	visible = false
	add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.BG_SOLID))
	UiTheme.place(self, Control.PRESET_TOP_RIGHT, -24, 140, -24, 140, Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END)
	custom_minimum_size = Vector2(520, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := UiTheme.label("Inventar", 26, UiTheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_button := Button.new()
	close_button.text = "✕"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	head.add_child(close_button)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	box.add_child(_list)
	_feedback = UiTheme.label("", 15, UiTheme.HP)
	_feedback.modulate.a = 0.0
	box.add_child(_feedback)


func bind(m: MatchController) -> void:
	_match = m
	m.local_hero.inventory.changed.connect(refresh)
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
	for c in _list.get_children():
		c.queue_free()
	var hero := _match.local_hero
	var inv := hero.inventory
	var ratio := _match.shop.sell_ratio
	_list.add_child(UiTheme.label("Ausrüstung", 17, UiTheme.TEXT))
	for slot in Inventory.EQUIP_SLOTS:
		var id: String = inv.equipment.get(slot, "")
		if id == "":
			_line("%s: –" % Inventory.SLOT_NAMES[slot], "", [])
			continue
		var def := GameData.item(id)
		_line("%s: %s" % [Inventory.SLOT_NAMES[slot], def.name], UiTheme.format_stats(def.stats), [
			["Ablegen", func() -> void: _show(_match.request_unequip(slot))],
			["Verkaufen · %d" % int(def.price * ratio), func() -> void: _show(_match.request_sell(slot))],
		])
	_list.add_child(UiTheme.label("Tasche (%d/%d)" % [inv.bag.size(), inv.bag_size], 17, UiTheme.TEXT))
	if inv.bag.is_empty():
		_list.add_child(UiTheme.label("leer", 14, UiTheme.MUTED))
	for i in inv.bag.size():
		var def := GameData.item(inv.bag[i])
		_line("%s (%s)" % [def.name, Inventory.SLOT_NAMES[def.slot]], UiTheme.format_stats(def.stats), [
			["Anlegen", func() -> void: _show(_match.request_equip_from_bag(i))],
			["Verkaufen · %d" % int(def.price * ratio), func() -> void: _show(_match.request_sell("", i))],
		])
	_list.add_child(UiTheme.label("Verbrauch", 17, UiTheme.TEXT))
	for i in inv.consumables.size():
		var c: Dictionary = inv.consumables[i]
		if c.is_empty():
			_line("[%d] –" % (i + 1), "", [])
		else:
			var def := GameData.item(c.id)
			_line("[%d] %s ×%d" % [i + 1, def.name, c.count], def.description, [["Benutzen", func() -> void: _show(_match.request_use_consumable(i))]])


func _line(title: String, details: String, buttons: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_list.add_child(row)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)
	texts.add_child(UiTheme.label(title, 15, UiTheme.TEXT))
	if details != "":
		texts.add_child(UiTheme.label(details, 12, UiTheme.MUTED))
	for spec in buttons:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(spec[1])
		row.add_child(b)


func _show(result: Dictionary) -> void:
	_feedback.text = result.message
	_feedback.add_theme_color_override("font_color", UiTheme.HP if result.ok else UiTheme.DANGER)
	if _feedback_tween != null:
		_feedback_tween.kill()
	_feedback.modulate.a = 1.0
	_feedback_tween = create_tween()
	_feedback_tween.tween_interval(2.5)
	_feedback_tween.tween_property(_feedback, "modulate:a", 0.0, 0.6)
	refresh()
