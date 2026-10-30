class_name MatchController
extends Node3D
## Verdrahtet eine Runde: Arena, Kern, Held(en), Gegner, Wellen und UI.
## Entscheidet über Sieg und Niederlage. Enthält selbst möglichst wenig Spiellogik.

signal finished(victory: bool)

enum Phase { RUNNING, VICTORY, DEFEAT }

const HERO_SCENE := preload("res://scenes/heroes/hero.tscn")

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
	wave_manager.start()


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
	gold.register_player(peer_id, int(GameData.setting("rewards", "start_gold", 500)))
	return hero


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
