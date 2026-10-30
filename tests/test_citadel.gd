extends RefCounted
## Zitadelle des Lichts (Issue #4) nach dem Konzeptbild: Kartendaten (Grundriss in Bildpixeln), Aufbau in einer
## echten Runde, mittlere Lane mit Nord- und Südbogen, Torhaus als Sperre für Gegner, schießende Türme, Bauwerke
## als Gegnerziel, Schrein-Schub mit Ladezeit, freie Wege, Minimap und Spieluhr.

const MATCH_SCENE := preload("res://scenes/main/match.tscn")


func _start(t) -> MatchController:
	Session.map_id = "citadel"
	Session.hero_id = "guardian"
	var m: MatchController = MATCH_SCENE.instantiate()
	m.waves_override = [GameData.normalize_wave({"prepare_seconds": 0, "groups": [
		{"enemy": "grunt", "count": 1, "path": 0, "delay": 600}]}, 1)]   # Nachzügler: Runde endet nicht
	t.root.add_child(m)
	await t.frames(30)
	m.local_hero.set_physics_process(false)   # Held steht abseits in der Zitadelle und mischt nicht mit
	m.local_hero.global_position = Vector3(52, 0, -8)
	return m


func _end(t, m: MatchController) -> void:
	Session.map_id = "arena"
	m.queue_free()
	await t.frames(2)


func _map(m: MatchController) -> CitadelMap:
	return m.arena as CitadelMap


## Türme und Torhaus schießen nicht (Tests über Laufwege und Gegnerziele bleiben reproduzierbar).
func _silence(m: MatchController) -> void:
	for s in _map(m).structures:
		s.attack_damage = 0.0


## Abstand zum Rand der nächsten gepflasterten Straße (negativ = auf der Straße).
func _road_edge_dist(map: CitadelMap, p: Vector2) -> float:
	var best := INF
	for r in map.roads:
		if r.kind != 0:
			continue
		var pts: PackedVector2Array = r.points
		for i in pts.size() - 1:
			best = minf(best, Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1]).distance_to(p) - float(r.width) * 0.5)
	return best


func test_citadel_map_data(t) -> void:
	t.check(GameData.map_order.has("arena") and GameData.map_order.has("citadel"), "beide Karten im Menü wählbar")
	var def := GameData.map("citadel")
	t.check(ResourceLoader.exists(String(def.scene)), "Szene der Zitadelle vorhanden")
	var layout: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(def.layout)))
	t.check(layout is Dictionary, "Grundriss lesbar")
	var origin := Vector2(float(layout.px_origin[0]), float(layout.px_origin[1]))
	var px_scale := float(layout.px_scale)
	var walls := PackedVector2Array()   # Mauerring in Bildpixeln
	for p in layout.citadel.polygon:
		walls.append(Vector2(float(p[0]), float(p[1])))
	var bounds := PackedVector2Array()
	for p in layout.bounds:
		bounds.append(Vector2(float(p[0]), float(p[1])))
	t.eq(layout.lanes.size(), 3, "drei Lanes")
	for lane in layout.lanes:
		var pts: Array = lane.points
		var first := Vector2(float(pts[0][0]), float(pts[0][1]))
		var last := Vector2(float(pts[pts.size() - 1][0]), float(pts[pts.size() - 1][1]))
		t.check(first.x < float(layout.abyss_x) and Geometry2D.is_point_in_polygon(first, bounds),
			"Lane %s beginnt am Portal %s im Abgrund, innerhalb der Kartengrenze" % [lane.name, lane.portal])
		t.check(Geometry2D.is_point_in_polygon(last, walls), "Lane %s endet in der Zitadelle" % lane.name)
	t.check(layout.lanes[1].points.has("RING"), "mittlere Lane läuft um den Krater")
	var core_px := Vector2(float(layout.citadel.core[0]), float(layout.citadel.core[1]))
	var core := Vector2(def.core.x, def.core.z)
	t.check(core.distance_to((core_px - origin) * px_scale) < 0.05, "Kern aus maps.json liegt auf dem Kern im Grundriss")
	var fountain_px := Vector2(def.fountain.x, def.fountain.z) / px_scale + origin
	t.check(Geometry2D.is_point_in_polygon(fountain_px, walls) and fountain_px.x > core_px.x + 40.0,
		"Brunnen hinten in der Zitadelle, abgewandt vom Tor")
	t.check(def.has("fountain_radius") and float(def.fountain_radius) < 4.0, "kleinerer Brunnenkreis passt in den Hof")
	t.eq(layout.towers.size(), 4, "vier Türme wie im Bild (zwei Fort-Türme oben, einer hinter dem Fluss, einer unten)")
	t.eq(layout.shrines.size(), 3, "drei Schreine")
	t.eq(layout.barracks.size(), 2, "zwei Kasernen")
	t.eq(layout.camps.size(), 2, "zwei Lagerlichtungen im Dschungel")
	t.eq(layout.ruins.size(), 2, "zwei Ruinen")
	t.check(layout.pads.size() >= 4, "vier Startpunkte für vier Spieler")
	var forest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/citadel_forest.json"))
	t.check(forest is Dictionary and forest.rows.size() * int(forest.cell) == 768 and String(forest.rows[0]).length() * int(forest.cell) == 1408,
		"Waldraster deckt das ganze Konzeptbild ab")
	var structures: Dictionary = GameData.balance.get("map_structures", {})
	t.check(structures.has("tower") and structures.has("gate") and structures.has("shrine"), "Bauwerkswerte in game.json")


func test_citadel_builds_in_match(t) -> void:
	var m := await _start(t)
	var map := _map(m)
	t.check(map != null, "Runde lädt die Zitadellenkarte")
	t.eq(map.get_spawn_paths().size(), 3, "drei Gegnerwege")
	t.eq(map.bridges.size(), 3, "jede Lane quert den Fluss über eine Brücke")
	t.eq(map.structures.size(), 5, "vier Türme und das Torhaus")
	t.eq(m.spawner.structures.size(), 5, "Gegner kennen die Bauwerke")
	t.eq(map.shrines.size(), 3, "drei Schreine")
	t.check(map.gatehouse != null and map.gatehouse.half_length > 0.0, "Torhaus vorhanden")
	t.check(map.gatehouse.global_position.x < m.core.global_position.x - 8.0, "Torhaus auf der Westseite, zu den Lanes")
	t.check(m.core.global_position.distance_to(map.citadel_center()) < 0.5, "Kern in der Zitadelle")
	var f := Vector2(m.fountain.global_position.x, m.fountain.global_position.z)
	t.check(Geometry2D.is_point_in_polygon(f, map.citadel_polygon) and f.x > m.core.global_position.x, "Brunnen hinter dem Kern im Hof")
	t.check(absf(m.fountain.radius - 3.2) < 0.01, "Brunnenkreis der Karte übernommen (%.1f m)" % m.fountain.radius)
	t.check(Vector2(m.camera_rig.bounds.size).length() > 100.0, "Kamera darf über die große Karte fahren")
	for i in 4:
		var pad := map.hero_spawn_point(i)
		var p := Vector2(pad.x, pad.z)
		t.check(not Geometry2D.is_point_in_polygon(p, map.citadel_polygon) and pad.distance_to(map.gatehouse.global_position) < 16.0,
			"Startpunkt %d vor der Zitadelle beim Tor, wie im Bild" % (i + 1))
	# mittlere Lane: Hauptweg über den Nordbogen, Variante über den Südbogen; Gegner wechseln ab
	var variants: Array = map.get_path_variants().get(1, [])
	t.eq(variants.size(), 2, "mittlere Lane hat zwei Wege um den Krater")
	if variants.size() == 2:
		var north_z := INF
		var south_z := -INF
		for q in variants[0]:
			north_z = minf(north_z, q.z)
		for q in variants[1]:
			south_z = maxf(south_z, q.z)
		t.check(north_z < -9.0 and south_z > 9.0, "Nordbogen (z %.1f) und Südbogen (z %.1f)" % [north_z, south_z])
	var a := m.spawner.spawn("grunt", 1)
	var b := m.spawner.spawn("grunt", 1)
	t.check(a._path != b._path, "zwei Gegner der Mitte nehmen verschiedene Bögen")
	await _end(t, m)


func test_citadel_gate_blocks_until_destroyed(t) -> void:
	var m := await _start(t)
	_silence(m)
	var gate := _map(m).gatehouse
	var e := m.spawner.spawn_at("grunt", gate.global_position + Vector3(-4.0, 0, 0.5))
	# erst ohne Kenntnis des Torhauses: der Gegner will zum Kern und muss an der Sperre hängen bleiben
	m.spawner.structures.erase(gate)
	await t.frames(240)
	t.check(e.target == m.core, "Gegner läuft auf den Kern zu")
	t.check(e.global_position.x < gate.global_position.x - 0.5, "Gegner kommt nicht durch das Fallgitter (x %.1f, Tor %.1f)" % [e.global_position.x, gate.global_position.x])
	m.spawner.structures.append(gate)
	await t.frames(240)
	t.check(e.target == gate, "Gegner greift das Torhaus an")
	t.check(gate.health.hp < gate.health.max_hp, "Torhaus nimmt Schaden (%.0f / %.0f)" % [gate.health.hp, gate.health.max_hp])
	m.combat.deal_damage(null, gate, 1.0e7, DamageInfo.Type.TRUE)
	t.check(not gate.is_alive(), "Torhaus gefallen")
	var through: bool = await t.wait_until(func() -> bool: return e.global_position.x > gate.global_position.x + 3.0, 600)
	t.check(through, "nach dem Fall laufen Gegner durch das Tor (x %.1f)" % e.global_position.x)
	t.check(e.target == m.core, "danach ist der Kern das Ziel")
	# Helden gehen jederzeit durch das Tor: ihre Kollisionsmaske kennt die Sperrebene nicht
	t.eq(m.local_hero.collision_mask & CitadelMap.ENEMY_BARRIER_LAYER, 0, "Helden ignorieren die Torsperre")
	var probe: Enemy = m.spawner.alive_enemies()[0]
	t.check(probe.collision_mask & CitadelMap.ENEMY_BARRIER_LAYER != 0, "Gegner stoßen an die Torsperre")
	await _end(t, m)


func test_citadel_towers_shoot_and_get_attacked(t) -> void:
	var m := await _start(t)
	var map := _map(m)
	var tower: MapStructure = null
	for s in map.structures:
		if s.kind == "tower":
			tower = s
			break
	var near := m.spawner.spawn_at("brute", tower.global_position + Vector3(0, 0, tower.attack_range - 2.0))
	var far := m.spawner.spawn_at("brute", tower.global_position + Vector3(0, 0, -(tower.attack_range + 4.0)))
	near.set_physics_process(false)
	far.set_physics_process(false)
	var near_hp := near.health.hp
	var far_hp := far.health.hp
	await t.frames(150)
	t.check(near.health.hp < near_hp, "Turm trifft Gegner in Reichweite (%.0f → %.0f)" % [near_hp, near.health.hp])
	t.eq(far.health.hp, far_hp, "außer Reichweite kein Schuss")
	# Gegner greifen einen Turm in ihrem Aggro-Radius an (Schaden wie gegen den Kern)
	_silence(m)
	near.global_position = tower.global_position + Vector3(0, 0, tower.radius + 1.0)
	near.set_physics_process(true)
	var hit: bool = await t.wait_until(func() -> bool: return tower.health.hp < tower.health.max_hp, 400)
	t.check(hit, "Gegner schlägt auf den Turm ein")
	t.check(near.target == tower, "Ziel ist der Turm, nicht der Kern")
	m.combat.deal_damage(null, tower, 1.0e7, DamageInfo.Type.TRUE)
	t.check(not tower.is_alive(), "Turm gefallen")
	t.check(m.spawner.nearest_structure(near.global_position, 50.0) != tower, "gefallener Turm ist kein Ziel mehr")
	await t.frames(30)
	t.check(near.target != tower, "Gegner zieht weiter")
	await _end(t, m)


func test_citadel_shrine_burst_and_cooldown(t) -> void:
	var m := await _start(t)
	var map := _map(m)
	var shrine := map.shrines[0]
	var hero := m.local_hero
	hero.set_physics_process(true)
	var max_hp := hero.health.max_hp
	var max_mana := hero.stats.max_mana()
	hero.health.hp = max_hp * 0.4
	hero.mana = max_mana * 0.2
	hero.global_position = shrine.global_position + Vector3(1.5, 0, 0)
	await t.frames(3)
	t.check(not shrine.is_ready(), "Schrein ist verbraucht")
	var gained := hero.health.hp / max_hp - 0.4
	t.check(gained >= shrine.hp_ratio - 0.01 and gained < shrine.hp_ratio + 0.03, "Schub: +%.0f %% Leben" % (gained * 100.0))
	t.check(hero.mana >= max_mana * (0.2 + shrine.mana_ratio) - 1.0, "Schub: Mana aufgefüllt (%.0f)" % hero.mana)
	t.check(shrine.hp_ratio <= 0.3 and shrine.cooldown >= 60.0, "schwächer als der Brunnen auf Dauer: einmalig, lange Ladezeit")
	var hp_after := hero.health.hp
	hero.global_position = shrine.global_position + Vector3(6.0, 0, 0)
	await t.frames(2)
	hero.global_position = shrine.global_position + Vector3(1.5, 0, 0)
	await t.frames(10)
	t.check(hero.health.hp - hp_after < max_hp * 0.02, "kein zweiter Schub während der Ladezeit")
	t.check(shrine.cooldown_left() > shrine.cooldown - 2.0, "Ladezeit läuft (%.0f s)" % shrine.cooldown_left())
	# ein voller Held verbraucht den anderen Schrein nicht
	var other := map.shrines[1]
	hero.health.hp = max_hp
	hero.mana = max_mana
	hero.global_position = other.global_position + Vector3(1.5, 0, 0)
	await t.frames(5)
	t.check(other.is_ready(), "voller Held lässt den Schrein geladen")
	await _end(t, m)


func test_citadel_paths_stay_walkable(t) -> void:
	var m := await _start(t)
	_silence(m)
	var map := _map(m)
	var block := map.get_node_or_null("SceneryBlock")
	t.check(block != null and block.get_child_count() > 100, "dichte Wälder wie im Bild (%d Hindernisse)" % (block.get_child_count() if block else 0))
	var worst := INF
	for shape in block.get_children():
		worst = minf(worst, _road_edge_dist(map, Vector2(shape.position.x, shape.position.z)))
	t.check(worst > 1.0, "kein Baum oder Fels auf einer Straße oder dem Ring (nächster %.1f m vom Rand)" % worst)
	# je Lane ein schneller Gegner vom Portal, die Mitte zweimal (Nord- und Südbogen): alle kommen über den Fluss
	var runners: Array[Enemy] = []
	for i in [0, 1, 2, 1]:
		runners.append(m.spawner.spawn("runner", i))
	var river_x := 16.0
	var crossed: bool = await t.wait_until(func() -> bool:
		for r in runners:
			if r.global_position.x < river_x:
				return false
		return true, 1800)
	var xs := []
	for r in runners:
		xs.append("%.0f" % r.global_position.x)
	t.check(crossed, "Gegner aller Wege queren den Fluss (x: %s)" % ", ".join(xs))
	await _end(t, m)


func test_citadel_minimap_and_clock(t) -> void:
	t.eq(Minimap.format_clock(0.0), "00:00", "Spieluhr startet bei 00:00")
	t.eq(Minimap.format_clock(754.9), "12:34", "Minuten und Sekunden")
	t.eq(Minimap.format_clock(3725.0), "1:02:05", "ab einer Stunde mit Stunden")
	var m := await _start(t)
	var mini := m.hud.find_child("Minimap", true, false) as Minimap
	t.check(mini != null, "Minimap im HUD")
	var ext := _map(m).extent()
	t.check(absf(mini.size.x / mini.size.y - ext.size.x / ext.size.y) < 0.02, "Minimap im Seitenverhältnis der Karte")
	var p := Vector3(12.0, 0.0, -7.0)
	t.check(mini.to_world(mini.to_map(p)).distance_to(p) < 0.01, "Umrechnung Karte ↔ Minimap stimmt")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = mini.to_map(Vector3(0.0, 0.0, 0.0))
	mini._gui_input(click)
	t.check(not m.camera_rig.locked, "Klick auf die Minimap löst die Kamera vom Helden")
	t.check(Vector2(m.camera_rig.focus.x, m.camera_rig.focus.z).length() < 0.5, "Kamera schwenkt zum angeklickten Punkt")
	m.elapsed = 75.0
	await t.frames(2)
	t.check(mini._clock.text.begins_with("01:1"), "Spieluhr zeigt die Rundenzeit (%s)" % mini._clock.text)
	await _end(t, m)
