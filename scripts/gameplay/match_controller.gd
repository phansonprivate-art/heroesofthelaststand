class_name MatchController
extends Node3D
## Verdrahtet eine Runde: Arena, Kern, Held(en), Gegner, Wellen und UI.
## Entscheidet über Sieg und Niederlage. Enthält selbst möglichst wenig Spiellogik.

signal finished(victory: bool)

enum Phase { RUNNING, VICTORY, DEFEAT }

const HERO_SCENE := preload("res://scenes/heroes/hero.tscn")
const CLONE_BAR_SHADER := preload("res://assets/effects/health_bar.gdshader")

var arena: GameMap   ## gewählte Karte (data/maps/maps.json), in _ready geladen
@onready var core: DefenseCore = $Core
@onready var combat: CombatService = $Combat
@onready var spawner: EnemySpawner = $EnemySpawner
@onready var wave_manager: WaveManager = $WaveManager
@onready var gold: GoldService = $Gold
@onready var rewards: RewardService = $Rewards
@onready var upgrades: UpgradeService = $Upgrades
@onready var shop: ShopService = $Shop
@onready var telemetry: TelemetryService = $Telemetry
@onready var match_audio: MatchAudio = $MatchAudio
@onready var projectiles_root: Node3D = $Projectiles
@onready var heroes_root: Node3D = $Heroes
@onready var enemies_root: Node3D = $Enemies
@onready var floating_text: FloatingText = $FloatingText
@onready var vfx: VfxLayer = $Vfx
@onready var camera_rig: CameraRig = $CameraRig
@onready var hero_input: HeroInput = $HeroInput
@onready var hud: Hud = $HUD
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var game_over: GameOverScreen = $GameOver

## Für Tests: eigene Wellen statt der aus data/waves (vor dem Hinzufügen zum Baum setzen).
var waves_override: Array = []
var phase := Phase.RUNNING
var local_hero: Hero
var heroes: Array[Hero] = []
var clones: Array[Hero] = []     ## Doppelgänger (eigene Einheiten, zählen nicht als Helden der Runde)
var _clone_count := 0
var fountain: RecoveryFountain   ## Brunnen der Erholung hinter dem Kern
var elapsed := 0.0


func _ready() -> void:
	var map_def := GameData.map(Session.map_id)
	arena = (load(String(map_def.scene)) as PackedScene).instantiate()
	arena.definition = map_def
	arena.name = "Arena"
	add_child(arena)
	move_child(arena, 0)
	core.position = map_def.core
	camera_rig.bounds = arena.camera_bounds()
	core.setup(float(GameData.setting("core", "max_hp", 10000)), float(GameData.setting("core", "critical_ratio", 0.25)))
	core.destroyed.connect(_on_core_destroyed)
	core.health.damaged.connect(func(_i: DamageInfo) -> void: camera_rig.shake(0.35))

	spawner.container = enemies_root
	spawner.world = self
	spawner.paths = arena.get_spawn_paths()
	spawner.path_variants = arena.get_path_variants()
	spawner.core = core
	spawner.combat = combat
	spawner.hp_multiplier = GameData.enemy_hp_multiplier(Session.player_count)
	spawner.separation_radius = float(GameData.setting("enemies", "separation_radius", 1.1))
	spawner.hp_growth_per_wave = float(GameData.setting("waves", "enemy_hp_growth_per_wave", 0.0))
	spawner.damage_growth_per_wave = float(GameData.setting("waves", "enemy_damage_growth_per_wave", 0.0))

	gold.unlimited = Session.test_mode and Session.test_unlimited_gold
	upgrades.gold = gold
	shop.gold = gold
	shop.core = core
	rewards.gold = gold
	rewards.player_count = Session.player_count
	rewards.bind(combat, spawner, wave_manager)

	local_hero = _spawn_hero(Session.hero_id, 1)
	camera_rig.target = local_hero
	camera_rig.focus = local_hero.global_position
	hero_input.hero = local_hero
	hero_input.main_hero = local_hero
	hero_input.camera_rig = camera_rig
	hero_input.enemies = spawner

	wave_manager.waves = waves_override if not waves_override.is_empty() else GameData.waves
	wave_manager.spawner = spawner
	wave_manager.all_waves_completed.connect(_on_all_waves_completed)
	wave_manager.wave_started.connect(func(n: int, _w: Dictionary) -> void:
		spawner.wave_number = n
		core.on_wave_started())

	floating_text.bind(combat, rewards, local_hero.peer_id)
	hud.bind(self)
	pause_menu.bind(self)
	game_over.bind(self)
	telemetry.bind(self, Session.telemetry_directory(), Session.telemetry_enabled())
	match_audio.bind(self)
	vfx.bind(self)
	fountain = RecoveryFountain.new()
	fountain.name = "Fountain"
	add_child(fountain)
	var fountain_config: Dictionary = GameData.balance.get("fountain", {}).duplicate()
	if map_def.has("fountain"):   # jede Karte bestimmt die Lage selbst
		fountain_config.position = [map_def.fountain.x, map_def.fountain.y, map_def.fountain.z]
	if map_def.has("fountain_radius"):
		fountain_config.radius = map_def.fountain_radius
	fountain.setup(fountain_config, heroes, vfx)
	arena.bind_match(self)
	wave_manager.start(Session.test_wave - 1 if Session.test_mode else 0)   # Testmodus: gewählte Welle


func _process(delta: float) -> void:
	if phase == Phase.RUNNING:
		elapsed += delta


func _unhandled_input(event: InputEvent) -> void:
	if phase != Phase.RUNNING:
		return
	if event.is_action_pressed("pause"):
		pause_menu.open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("call_wave"):
		wave_manager.skip_preparation()


func _spawn_hero(hero_id: String, peer_id: int) -> Hero:
	var def := GameData.hero(hero_id)
	if def.is_empty():
		push_error("Held '%s' unbekannt, nutze Standardheld" % hero_id)
		def = GameData.hero(GameData.hero_order[0])
	var hero: Hero = HERO_SCENE.instantiate()
	hero.peer_id = peer_id
	hero.name = "Hero_%d" % peer_id
	heroes_root.add_child(hero)
	hero.setup(def, combat, spawner, arena.hero_spawn_point(peer_id - 1), float(GameData.setting("heroes", "respawn_seconds", 6.0)))
	hero.projectile_root = projectiles_root
	hero.world = self
	hero.inventory = Inventory.new(int(GameData.setting("rewards", "bag_size", 6)), int(GameData.setting("rewards", "consumable_slots", 2)))
	heroes.append(hero)
	spawner.heroes.append(hero)
	rewards.track_hero(hero)
	if telemetry.store != null:
		telemetry.track_hero(hero)
		match_audio.track_hero(hero)
		vfx.track_hero(hero)
	var start_gold := int(GameData.setting("test_mode", "gold", 999999)) if Session.test_mode else int(GameData.setting("rewards", "start_gold", 500))
	gold.register_player(peer_id, start_gold)
	if Session.test_mode:
		_apply_test_level(hero)
		if gold.team_balance() < start_gold:   # auch Team-Verbesserungen (Kern) sollen kaufbar sein
			gold.grant_team(start_gold - gold.team_balance(), "test_mode", "test_mode:team")
	return hero


## Doppelgänger eines Helden (Issue #10): gleiche Figur, Stufe, gekaufte Punkte und Ausrüstungswerte, eigener
## Lebensbalken mit den aktuellen Leben des Helden beim Wirken, weniger Schaden und mehr erlittener Schaden. Gegner greifen ihn an
## (spawner.heroes); Gold und Erfahrung für seine Treffer gehen an den Helden (gleiche Spieler-ID).
func spawn_clone(owner: Hero, pos: Vector3, duration: float, damage_share: float, damage_taken: float, hp_share: float) -> Hero:
	var clone: Hero = HERO_SCENE.instantiate()
	_clone_count += 1
	clone.peer_id = owner.peer_id
	clone.name = "Clone_%d" % _clone_count
	heroes_root.add_child(clone)
	clone.setup(owner.data, combat, spawner, pos, 0.0)
	clone.global_position = pos
	clone.projectile_root = projectiles_root
	clone.world = self
	clone.clone_owner = owner
	clone.clone_left = duration
	clone.outgoing_multiplier = damage_share
	clone.damage_taken_multiplier = damage_taken
	clone.stats.level = owner.stats.level
	clone.stats.bought = owner.stats.bought.duplicate()
	clone.inventory = owner.inventory          # nur lesend: Ausrüstungswerte gelten auch für die Kopie
	clone.apply_equipment()
	# Leben wie der Held im Moment des Wirkens (Wunsch des Spielers): gleiches Maximum, gleicher Stand
	clone.health.setup(maxf(1.0, owner.health.max_hp))
	clone.health.hp = clampf(owner.health.hp * hp_share, 1.0, clone.health.max_hp)
	clone.health.changed.emit(clone.health.hp, clone.health.max_hp)
	clone.mana = 0.0
	clone._on_status_changed()   # schattenhafte Färbung und violetter Ring (Hero.CLONE_TINT / CLONE_RING)
	_add_clone_health_bar(clone)
	clones.append(clone)
	spawner.heroes.append(clone)
	vfx.smoke_cloud(pos + Vector3(0, 0.8, 0), Color(0.18, 0.1, 0.28, 0.85), 0.8, 0.0, 10, 0.8)
	return clone


## Lebensbalken über dem Doppelgänger (wie bei Gegnern, aber violett), damit man sieht, wie lange er noch hält.
func _add_clone_health_bar(clone: Hero) -> void:
	var bar := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 0.12)
	bar.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = CLONE_BAR_SHADER
	mat.render_priority = 3
	mat.set_shader_parameter("fill_color", Color(0.68, 0.42, 1.0))
	bar.material_override = mat
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.name = "CloneHealthBar"
	clone.add_child(bar)
	bar.position.y = 2.2 * float(clone.data.get("model_scale", 1.0)) + 0.35
	bar.set_instance_shader_parameter("fill", 1.0)
	clone.health.changed.connect(func(current: float, maximum: float) -> void:
		if is_instance_valid(bar):
			bar.set_instance_shader_parameter("fill", current / maxf(1.0, maximum)))


func remove_clone(clone: Hero) -> void:
	clones.erase(clone)
	spawner.heroes.erase(clone)
	for e in spawner.alive_enemies():   # wer die Kopie verfolgt hat, macht mit seinem Weg weiter
		e.forget(clone)
	if hero_input.hero == clone:
		hero_input.select(local_hero)


## Testmodus: Held direkt auf die gewählte Stufe heben (über XP, damit Werte und Freischaltungen wie im Spiel folgen).
func _apply_test_level(hero: Hero) -> void:
	var target := clampi(Session.test_level, 1, hero.stats.max_level())
	while hero.stats.level < target and hero.stats.xp_to_next() > 0:
		hero.gain_xp(hero.stats.xp_to_next() - hero.stats.xp)
	hero.health.heal(hero.health.max_hp)
	hero.mana = hero.stats.max_mana()


## Kaufwunsch des lokalen Spielers (UI). In Phase 5 wird daraus ein RPC an den Host.
func request_attribute_upgrade(attribute: String) -> Dictionary:
	return upgrades.request_attribute(local_hero, attribute)


func request_learn_ability(ability_id: String) -> Dictionary:
	return shop.learn_ability(local_hero, ability_id)


func request_equip_ability(ability_id: String, slot: int) -> Dictionary:
	var reason := local_hero.abilities.equip(ability_id, slot)
	return {"ok": reason == "", "message": reason if reason != "" else "%s auf %s gelegt." % [GameData.skill(ability_id).name, AbilityCaster.SLOT_KEYS[slot]]}


func request_cast(slot: int, target_unit: Node3D, point: Vector3) -> bool:
	return local_hero.abilities.request_cast(slot, target_unit, point)


func request_buy_item(item_id: String) -> Dictionary:
	return shop.buy_item(local_hero, item_id)


func request_sell(slot: String, bag_index := -1) -> Dictionary:
	return shop.sell(local_hero, slot, bag_index)


func request_equip_from_bag(bag_index: int) -> Dictionary:
	return shop.equip_from_bag(local_hero, bag_index)


func request_unequip(slot: String) -> Dictionary:
	return shop.unequip(local_hero, slot)


func request_use_consumable(slot_index: int) -> Dictionary:
	return shop.use_consumable(local_hero, slot_index)


func request_team_upgrade(upgrade_id: String) -> Dictionary:
	return shop.buy_team_upgrade(local_hero, upgrade_id)


func request_donate(amount: int) -> Dictionary:
	return shop.donate(local_hero, amount)


func stats() -> Dictionary:
	var completed := 0
	for n in range(1, wave_manager.total_waves() + 1):
		if wave_manager.is_wave_completed(n):
			completed += 1
	return {
		"waves_completed": completed,
		"waves_total": wave_manager.total_waves(),
		"kills": spawner.killed_total,
		"core_hp": core.health.hp,
		"core_max": core.health.max_hp,
		"seconds": elapsed,
	}


func _on_core_destroyed() -> void:
	_end(Phase.DEFEAT)


func _on_all_waves_completed() -> void:
	if core.is_alive():
		_end(Phase.VICTORY)


func _end(result: Phase) -> void:
	if phase != Phase.RUNNING:
		return
	phase = result
	wave_manager.stop()
	hero_input.input_enabled = false
	for h in heroes:
		h.freeze(result == Phase.VICTORY)
	if result == Phase.DEFEAT:
		spawner.celebrate_all()
	pause_menu.close()
	hud.clear_banner()
	telemetry.finish("victory" if result == Phase.VICTORY else "defeat")
	game_over.show_result(result == Phase.VICTORY, stats())
	finished.emit(result == Phase.VICTORY)
