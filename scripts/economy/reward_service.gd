class_name RewardService
extends Node
## Beteiligung am Kampf erfassen und Gold/XP verteilen. Läuft autoritativ auf dem Host.
##
## Kill-Gold eines Gegners wird nach Anteilen aufgeteilt (nicht nach letztem Treffer):
##   Schaden/Max-LP  +  Kontrolle (max. control_cap)  +  abgefangener Schaden (max. tank_cap)
##   +  Taunt-Bonus, wenn der Gegner durch Taunt wirklich das Ziel gewechselt hat
## Je Welle und Spieler:
##   Support-Gold  = (effektive Heilung + absorbierter Schild + verhinderter Schaden) × Satz, gedeckelt
##   Rollenbonus   = 0–100 nach Leistung (Support, Tanken, Kontrolle, Schaden) – nicht nach gewählter Rolle
##   Wellenbonus   = fest, genau einmal je Welle
## Anti-Exploit: keine Überheilung, nur absorbierte Schilde, Kontrolle nur mit neuer Wirkdauer und
## abnehmend bei Wiederholung am selben Ziel, Taunt nur mit Wirkung, kein Gold ohne Beteiligung,
## AFK-Spieler (kein Befehl seit afk_seconds) erhalten keine Wellenbelohnungen.
## Die Abrechnung (add_*/settle_*) arbeitet nur mit IDs und ist ohne Szene testbar.

signal gold_awarded(peer_id: int, amount: int, world_pos: Vector3)
signal xp_awarded(peer_id: int, amount: int)
signal wave_rewards(peer_id: int, wave_number: int, summary: Dictionary)

var gold: GoldService
var heroes: Array[Hero] = []
var player_count := 1

var wave_bonus_gold := 150
var wave_xp_base := 40
var wave_xp_per_wave := 10
var xp_share_radius := 16.0
var gold_per_extra_player := 1.0
var support_gold_per_point := 0.25
var support_gold_cap := 150
var role_bonus_max := 100
var role_bonus_full_score := 500.0
var afk_seconds := 60.0
var team_gold_per_wave := 100
var team_gold_per_player := 40
var control_weight := {"stun": 0.25, "taunt": 0.2, "slow": 0.08}
var control_cap := 0.5
var taunt_switch_bonus := 0.3
var tank_cap := 0.4
var tank_scale := 0.5
var repeat_factor := 0.5
## Gewichte des Rollenbonus: Leistung zählt, egal welche Rolle (Support-Punkte, abgefangener Schaden, Kontrolle, Schaden)
var role_weights := {"support": 1.0, "tank": 0.5, "control": 200.0, "damage": 0.2}

var _contrib: Dictionary = {}       ## enemy uid -> {peer -> {damage, control, tank, taunt}}
var _control_count: Dictionary = {} ## "peer|uid|kind" -> bisherige Anwendungen
var _wave: Dictionary = {}          ## peer -> Leistung der laufenden Welle
var _rewarded: Dictionary = {}      ## "kill:<uid>" / "wave:<n>" -> true


func _ready() -> void:
	var r := func(key: String, fallback: Variant) -> Variant: return GameData.setting("rewards", key, fallback)
	wave_bonus_gold = int(r.call("wave_bonus_gold", 150))
	wave_xp_base = int(r.call("wave_xp_base", 40))
	wave_xp_per_wave = int(r.call("wave_xp_per_wave", 10))
	xp_share_radius = float(r.call("xp_share_radius", 16.0))
	gold_per_extra_player = float(r.call("gold_per_extra_player", 1.0))
	support_gold_per_point = float(r.call("support_gold_per_point", 0.25))
	support_gold_cap = int(r.call("support_gold_cap", 150))
	role_bonus_max = int(r.call("role_bonus_max", 100))
	role_bonus_full_score = float(r.call("role_bonus_full_score", 500.0))
	afk_seconds = float(r.call("afk_seconds", 60.0))
	team_gold_per_wave = int(r.call("team_gold_per_wave", 100))
	team_gold_per_player = int(r.call("team_gold_per_player", 40))
	var c: Dictionary = GameData.balance.get("contribution", {})
	control_weight = c.get("control_weight", control_weight)
	control_cap = float(c.get("control_cap", control_cap))
	taunt_switch_bonus = float(c.get("taunt_switch_bonus", taunt_switch_bonus))
	tank_cap = float(c.get("tank_cap", tank_cap))
	tank_scale = float(c.get("tank_scale", tank_scale))
	repeat_factor = float(c.get("repeat_factor", repeat_factor))
	role_weights = c.get("role_weights", role_weights)


func bind(combat: CombatService, spawner: EnemySpawner, waves: WaveManager) -> void:
	combat.damage_applied.connect(_on_damage_applied)
	combat.damage_prevented.connect(_on_damage_prevented)
	spawner.enemy_killed.connect(_on_enemy_killed)
	waves.wave_completed.connect(_on_wave_completed)


func track_hero(hero: Hero) -> void:
	heroes.append(hero)
	hero.health.healed.connect(func(amount: float, source: Node) -> void:
		if source is Hero and is_instance_valid(source):
			add_support((source as Hero).peer_id, "heal", amount))
	hero.health.shield_absorbed.connect(func(amount: float, source: Node) -> void:
		if source is Hero and is_instance_valid(source):
			add_support((source as Hero).peer_id, "shield", amount))


## Kontrolle durch eine Fähigkeit melden (AbilityEffects). gain = tatsächlich neue Wirkdauer.
func record_control(hero: Hero, enemy: Enemy, kind: String, gain_seconds: float, magnitude := 1.0, switched := false) -> void:
	if hero == null or enemy == null:
		return
	add_control(enemy.uid, hero.peer_id, kind, gain_seconds, magnitude, switched)


# --- Abrechnung (nur IDs, ohne Szene testbar) -------------------------------------

func gold_multiplier() -> float:
	return 1.0 + gold_per_extra_player * maxi(0, player_count - 1)


func add_damage(uid: int, peer: int, amount: float) -> void:
	if amount > 0.0:
		_entry(uid, peer).damage += amount
		_wave_entry(peer).damage += amount


func add_tank(uid: int, peer: int, amount: float) -> void:
	if amount > 0.0:
		_entry(uid, peer).tank += amount
		_wave_entry(peer).tank += amount


## Gibt die gutgeschriebenen Kontrollpunkte zurück (0 bei wirkungsloser oder zu oft wiederholter Kontrolle).
func add_control(uid: int, peer: int, kind: String, gain_seconds: float, magnitude := 1.0, switched := false) -> float:
	if gain_seconds <= 0.0:
		return 0.0
	if kind == "taunt" and not switched:
		return 0.0   # Taunt ohne Zielwechsel hat keine nachweisbare Wirkung
	var key := "%d|%d|%s" % [peer, uid, kind]
	var n: int = _control_count.get(key, 0)
	_control_count[key] = n + 1
	var points := gain_seconds * float(control_weight.get(kind, 0.0)) * (magnitude if kind == "slow" else 1.0) * pow(repeat_factor, n)
	var e := _entry(uid, peer)
	var granted := minf(points, maxf(0.0, control_cap - e.control))
	e.control += granted
	if kind == "taunt" and switched and e.taunt == 0.0:
		e.taunt = taunt_switch_bonus
	_wave_entry(peer).control += granted
	return granted


func add_support(peer: int, kind: String, amount: float) -> void:
	if amount > 0.0:
		_wave_entry(peer)[kind] += amount


## Anteile aller Beteiligten an einem Gegner.
func shares_for(uid: int, max_hp: float) -> Dictionary:
	var result := {}
	for peer in _contrib.get(uid, {}):
		var e: Dictionary = _contrib[uid][peer]
		var share: float = minf(1.0, e.damage / maxf(1.0, max_hp)) + e.control \
			+ minf(tank_cap, e.tank / maxf(1.0, max_hp * tank_scale)) + e.taunt
		if share > 0.0:
			result[peer] = share
	return result


## Teilt das Gold eines besiegten Gegners auf (bucht nicht). Gibt peer -> Gold zurück.
func settle_kill(uid: int, gold_value: int, max_hp: float) -> Dictionary:
	var split := split_by_share(roundi(gold_value * gold_multiplier()), shares_for(uid, max_hp))
	_contrib.erase(uid)
	return split


## Wellenauszahlung eines Spielers (bucht nicht).
func wave_payout(peer: int, active: bool) -> Dictionary:
	var w := _wave_entry(peer)
	var support_points: float = w.heal + w.shield + w.prevented
	var score: float = support_points * float(role_weights.support) + w.tank * float(role_weights.tank)  + w.control * float(role_weights.control) + w.damage * float(role_weights.damage)
	var summary := {
		"active": active, "heal": w.heal, "shield": w.shield, "prevented": w.prevented, "control": w.control,
		"tank": w.tank, "damage": w.damage, "role_score": score,
		"support_gold": mini(support_gold_cap, roundi(support_points * support_gold_per_point)) if active else 0,
		"role_bonus": clampi(roundi(role_bonus_max * score / role_bonus_full_score), 0, role_bonus_max) if active else 0,
		"wave_bonus": wave_bonus_gold if active else 0,
	}
	return summary


func reset_wave() -> void:
	_wave.clear()


func wave_stats(peer: int) -> Dictionary:
	return _wave_entry(peer).duplicate()


## Teilt `total` nach Anteilen auf (größter Rest), sodass die Summe exakt `total` ergibt.
static func split_by_share(total: int, shares: Dictionary) -> Dictionary:
	var result := {}
	var sum := 0.0
	for k in shares:
		sum += maxf(0.0, float(shares[k]))
	if total <= 0 or sum <= 0.0:
		return result
	var remainders := []
	var assigned := 0
	for k in shares:
		var exact := total * maxf(0.0, float(shares[k])) / sum
		result[k] = int(floor(exact))
		assigned += result[k]
		remainders.append([exact - floor(exact), k])
	remainders.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var i := 0
	while assigned < total:
		result[remainders[i % remainders.size()][1]] += 1
		assigned += 1
		i += 1
	return result


# --- Signale aus dem Spiel ----------------------------------------------------

func _on_damage_applied(target: Node3D, info: DamageInfo) -> void:
	var source := info.source if info.source_is_valid() else null
	# Der tödliche Treffer wird in _on_enemy_killed verbucht: `died` feuert vor `damage_applied`.
	if target is Enemy and (target as Enemy).is_alive() and source is Hero:
		add_damage((target as Enemy).uid, (source as Hero).peer_id, info.final_amount)
	elif target is Hero and source is Enemy:
		add_tank((source as Enemy).uid, (target as Hero).peer_id, info.final_amount + info.absorbed)


func _on_damage_prevented(target: Node3D, source: Node, amount: float) -> void:
	# Nur Schutz für andere bzw. das Team zählt; eigene Rune ist keine Support-Leistung (source = null)
	if source is Hero and is_instance_valid(source) and target is Hero:
		add_support((source as Hero).peer_id, "prevented", amount)


func _on_enemy_killed(enemy: Enemy, killing_blow: DamageInfo) -> void:
	var key := "kill:%d" % enemy.uid
	if _rewarded.has(key):
		return
	_rewarded[key] = true
	if killing_blow != null and killing_blow.source_is_valid() and killing_blow.source is Hero:
		add_damage(enemy.uid, (killing_blow.source as Hero).peer_id, killing_blow.final_amount)
	var shares := shares_for(enemy.uid, enemy.health.max_hp)
	var split := settle_kill(enemy.uid, int(enemy.data.gold), enemy.health.max_hp)
	var pos := enemy.global_position
	for peer in split:
		if split[peer] > 0 and gold.grant(peer, split[peer], "kill", key):
			gold_awarded.emit(peer, split[peer], pos)
	var xp := int(enemy.data.xp)
	for hero in heroes:
		if not is_instance_valid(hero) or not hero.is_alive():
			continue
		var near := Vector2(hero.global_position.x - pos.x, hero.global_position.z - pos.z).length() <= xp_share_radius
		if shares.has(hero.peer_id) or near:
			hero.gain_xp(xp)
			xp_awarded.emit(hero.peer_id, xp)


func _on_wave_completed(wave_number: int) -> void:
	var key := "wave:%d" % wave_number
	if _rewarded.has(key):
		return
	_rewarded[key] = true
	var xp := wave_xp_base + wave_xp_per_wave * wave_number
	for hero in heroes:
		if not is_instance_valid(hero):
			continue
		var active := hero.idle_time < afk_seconds
		var s := wave_payout(hero.peer_id, active)
		for part in [["wave_bonus", "wave_bonus"], ["support_gold", "support"], ["role_bonus", "role_bonus"]]:
			var amount: int = s[part[0]]
			if amount > 0 and gold.grant(hero.peer_id, amount, part[1], key):
				gold_awarded.emit(hero.peer_id, amount, hero.global_position)
		hero.gain_xp(xp)
		xp_awarded.emit(hero.peer_id, xp)
		wave_rewards.emit(hero.peer_id, wave_number, s)
	gold.grant_team(team_gold_per_wave + team_gold_per_player * heroes.size(), "wave_team", key)
	reset_wave()


func _entry(uid: int, peer: int) -> Dictionary:
	if not _contrib.has(uid):
		_contrib[uid] = {}
	if not _contrib[uid].has(peer):
		_contrib[uid][peer] = {"damage": 0.0, "control": 0.0, "tank": 0.0, "taunt": 0.0}
	return _contrib[uid][peer]


func _wave_entry(peer: int) -> Dictionary:
	if not _wave.has(peer):
		_wave[peer] = {"damage": 0.0, "heal": 0.0, "shield": 0.0, "prevented": 0.0, "control": 0.0, "tank": 0.0}
	return _wave[peer]
