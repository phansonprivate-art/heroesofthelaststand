extends SceneTree
## Balancing-Hilfe: druckt die Kennwerte aller Helden auf Stufe 1, 10 und 15 (ohne gekaufte Punkte).
##   godot --headless --path . -s res://tools/stat_table.gd

func _initialize() -> void:
	await process_frame
	var gd = root.get_node("GameData")
	var stat_block = load("res://scripts/heroes/stat_block.gd")
	print("| Held | Stufe | Leben | Mana | Schaden | Angriffe/s | DPS* | Krit | Rüstung | MR | Tempo |")
	print("|---|---|---|---|---|---|---|---|---|---|---|")
	for id in gd.hero_order:
		for lvl in [1, 10, 15]:
			var s = stat_block.create(gd.hero(id), gd.attribute_rules)
			s.level = lvl
			var aps: float = 1.0 / s.attack_interval()
			var dps: float = s.attack_damage() * (1.0 + s.crit_chance() * (s.crit_multiplier() - 1.0)) * aps
			print("| %s | %d | %d | %d | %.0f | %.2f | %.0f | %.0f %% | %.1f | %.1f | %.2f |" % [gd.hero(id).name, lvl, s.max_hp(), s.max_mana(), s.attack_damage(), aps, dps, s.crit_chance() * 100.0, s.armor(), s.magic_resist(), s.move_speed()])
	quit()
