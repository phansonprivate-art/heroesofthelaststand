# Architektur

## Grundprinzipien

1. **Simulation und Darstellung getrennt.** `Hero`, `Enemy`, `DefenseCore`, `WaveManager` enthalten die Spiellogik. Modelle, Animationen, Schadenszahlen, Lebensbalken und HUD hängen nur an Signalen bzw. lesen Zustand.
2. **Befehle statt direkter Eingabe.** Der Held kennt keine Tasten. `HeroInput` übersetzt Maus/Tastatur in `command_move_direction`, `command_move_to`, `command_attack`, `command_stop`. In Phase 5 kommen dieselben Befehle per RPC vom Client.
3. **Ein Weg für Schaden.** Jeder Schaden läuft über `CombatService.deal_damage()`. Dort werden später Rüstung, Schilde, Beteiligung (Gold/XP) und Replikation angebunden.
4. **Datengetrieben.** Helden, Gegner, Wellen und Balancing stehen in `data/*.json` und werden von `GameData` geladen und geprüft. Fehlerhafte Einträge werden verworfen und gemeldet, nicht stillschweigend übernommen.
5. **Autorität vorbereitet.** Kritische Stellen (`CombatService`, `EnemySpawner.spawn`, `WaveManager._process`) prüfen `multiplayer.is_server()`. Im Einzelspiel ist das immer wahr.

## Autoloads (nur echte globale Dienste)

| Autoload | Aufgabe |
|---|---|
| `GameData` | Lädt und validiert alle JSON-Definitionen, liefert `hero(id)`, `enemy(id)`, `waves`, `setting(section, key)` |
| `Session` | Registriert die Tastenbelegung, hält die Auswahl zwischen Menü und Runde (Held, Spielerzahl), wechselt Szenen |

## Szenenbaum einer Runde (`scenes/main/match.tscn`)

```
Match (MatchController)        verdrahtet alles, entscheidet Sieg/Niederlage
├── Arena (Arena)              Boden, SpawnPaths (Marker3D), HeroSpawn, Decor (Code-generiert)
├── Core (DefenseCore)         StaticBody, HealthComponent, Kristall + Licht
├── Combat (CombatService)     einziger Weg für Schaden, Signal damage_applied
├── EnemySpawner               erzeugt Gegner, Liste lebender Gegner, räumliches Raster
├── WaveManager                Vorbereitung → Spawnen → Aufräumen → nächste Welle
├── Gold (GoldService)         Kontostände, Transaktionsprotokoll, Schutz vor Doppelbuchungen
├── Rewards (RewardService)    Beteiligung erfassen, Gold/XP für Kills und Wellen verteilen
├── Upgrades (UpgradeService)  Attribut-Käufe gegen Gold
├── Heroes                     Hero-Instanzen (scenes/heroes/hero.tscn)
├── Enemies                    Enemy-Instanzen (scenes/enemies/enemy.tscn)
├── Projectiles                Geschosse der Fernkampfhelden
├── FloatingText               Schadenszahlen (hört auf Combat)
├── CameraRig                  lokale Kamera, nie synchronisiert
├── HeroInput                  lokale Eingabe → Befehle, Ziel-/Klickmarkierungen
├── HUD (Hud)                  CanvasLayer
├── PauseMenu                  CanvasLayer, PROCESS_MODE_ALWAYS
└── GameOver (GameOverScreen)  CanvasLayer, PROCESS_MODE_ALWAYS
```

Die Reihenfolge ist Absicht: `EnemySpawner` baut sein Raster im Physik-Schritt **vor** den Gegnern auf.

## Datenfluss eines Treffers

```
HeroInput ──command_attack──▶ Hero (Zielverfolgung, Windup)
                                 │ Trefferzeitpunkt
                                 ▼
                          CombatService.deal_damage()
                                 │ DamageInfo
                                 ▼
                          HealthComponent.apply_damage()
                ┌────────────────┼──────────────────┐
             damaged           changed             died (genau einmal)
                │                 │                   │
     Enemy: Aggro + Flash   Lebensbalken/HUD    Enemy: Tod → Spawner.enemy_killed
                                                       → WaveManager prüft Abschluss
```

## Komponenten

| Datei | Verantwortung |
|---|---|
| `scripts/gameplay/health_component.gd` | LP; nie negativ; `died` genau einmal; Heilung liefert nur effektiven Anteil (Grundlage für "kein Gold für Überheilung") |
| `scripts/gameplay/damage_info.gd` | Schadensvorgang: angefragt, tatsächlich, Typ, Verursacher |
| `scripts/gameplay/character_visual.gd` | Modell laden, Teile ausblenden, logische Animationen ("idle", "run", "attack" …), Trefferblitz, Platzhalter bei fehlendem Modell |
| `scripts/heroes/hero.gd` | Bewegung, Auto-Angriff, Zielverfolgung, Windup (Bewegen bricht Schlag ab), Tod/Respawn |
| `scripts/enemies/enemy.gd` | Zustandsautomat SPAWNING → ADVANCE ↔ ATTACK → DEAD; Ziel Kern, kurzzeitig angreifender Held |
| `scripts/enemies/enemy_spawner.gd` | Spawn, Lebend-Liste, `nearest_enemy`, `enemies_in_radius`, Abstoßung über 2-m-Raster |
| `scripts/waves/wave_manager.gd` | Wellenablauf, Spawn-Warteschlange, Abschluss höchstens einmal je Welle, pausierbar |
| `scripts/gameplay/arena.gd` | Spawnpfade aus Markern, Mauerring/Tore/Deko aus KayKit-Teilen |
| `scripts/heroes/stat_block.gd` | **Reine Logik:** Attribute (Basis + Wachstum je Stufe + gekaufte Punkte mit Soft Cap + Boni), alle abgeleiteten Werte mit Obergrenzen, Upgrade-Kosten, Level/XP. Ohne Szene testbar. |
| `scripts/gameplay/status_effects.gd` | Verlangsamung/Betäubung; gleiche Effekte stapeln nicht (Dauer erneuert, stärkere Wirkung gilt); `cc_resist` verkürzt Kontrolle |
| `scripts/gameplay/projectile.gd` | Zielsuchendes Geschoss; Schaden beim Abschuss ausgewürfelt, beim Einschlag über `Hero.hit_target` zugefügt |
| `scripts/economy/gold_service.gd` | Persönliches Gold; kein Minus; Referenz je Spieler nur einmal buchbar; Protokoll mit fortlaufender ID |
| `scripts/economy/reward_service.gd` | Schadensanteile je Gegner (`uid`) → Kill-Gold nach Anteil (größter Rest), XP für Beteiligte und Helden in 16 m; Wellenbonus genau einmal |
| `scripts/economy/upgrade_service.gd` | Prüft und bucht Attribut-Käufe; Referenz `attr:<a>:<n>` schützt vor Doppelkäufen |
| `scripts/telemetry/telemetry_service.gd` | Sammelt Balancing-Daten der Runde (je Welle und Spieler, je Gegnertyp, alle Gold-Buchungen, Levelaufstiege, Helden-Endstand) in **Spielzeit**; schreibt am Wellen- und Rundenende; Abbruch → `aborted` |
| `scripts/telemetry/telemetry_store.gd` | Schreibt/liest CSV-Tabellen mit festem Schema (`TABLES`, `SCHEMA_VERSION`). Austauschbar gegen ein anderes Speicherziel (z. B. SQLite) |
| `scripts/core/audio_service.gd` | Autoload `Audio`: Ereignisse aus `data/audio/sounds.json`, Player-Pools (24 räumlich, 10 flach), Mindestabstand und Höchstzahl je Ereignis, Busse SFX/UI/Music, Klick für jeden Button; headless ohne echte Wiedergabe |
| `scripts/gameplay/match_audio.gd` | Hört auf Spielsignale (Schaden, Tod, Spawn, Gold, Wellen, Käufe, Rundenende) und löst Sounds aus. Die Simulation kennt kein Audio |
| `scripts/ui/character_window.gd` | Charakterfenster: fragt Käufe über `MatchController.request_attribute_upgrade` an |
| `scripts/ui/*` | HUD, Menüs; gemeinsamer Stil in `ui_theme.gd` |

## Physik-Ebenen

| Ebene | Bit | Inhalt | Kollidiert mit |
|---|---|---|---|
| 1 | 1 | Welt (Boden, Mauern, Säulen) | – |
| 2 | 2 | Helden | Welt, Kern |
| 3 | 4 | Gegner | Welt, Kern |
| 4 | 8 | Kern | – |

Helden und Gegner kollidieren bewusst nicht miteinander (siehe Entscheidungen). Gegner halten über das Raster Abstand zueinander.

## Entscheidungen

- **JSON statt `.tres` für Inhalte:** von Hand und mit Werkzeugen gut editierbar, diff-freundlich, zentral validiert. Nachteil: keine Inspector-Bearbeitung. Ein späterer Wechsel auf Resources ist möglich, weil nur `GameData` das Format kennt.
- **Wegpunkte statt NavMesh:** Die Arena ist offen; drei Wegpunktketten plus Abstoßung reichen und sind deterministisch und billig. Ab 9 m vor dem Kern laufen Gegner direkt darauf zu.
- **Keine Kollision Held ↔ Gegner (vorerst):** vermeidet Verkeilen und Ruckeln. Körperblockade als Tank-Mechanik wird in Phase 2 gezielt entworfen.
- **Kamera:** feste Blickrichtung nach Norden, damit alle drei Tore ohne Drehen erreichbar sind. Q/E bleiben dadurch für Fähigkeiten frei.
- **Arena-Deko per Code:** hält `arena.tscn` klein. Gameplay-relevante Punkte (Spawnpfade, Heldenstart) bleiben als Marker in der Szene und sind im Editor verschiebbar.
- **Gegnerszene nicht per `preload` im Spawner:** `enemy.gd` referenziert `EnemySpawner`; ein `preload` erzeugte einen Ladezyklus.
- **Tödlicher Treffer und Beteiligung:** `HealthComponent.died` feuert *innerhalb* von `apply_damage`, also vor `CombatService.damage_applied`. Der `RewardService` verbucht den tödlichen Treffer deshalb im Kill-Handler (aus der mitgelieferten `DamageInfo`) und ignoriert danach Treffer auf tote Ziele.
- **Gold schon in Phase 2:** Attribut-Käufe brauchen Gold. Der `GoldService` wurde deshalb aus Phase 3 vorgezogen, vollständig mit Protokoll und Duplikatschutz. Die Belohnungslogik ist bewusst noch einfach (nur Schadensanteil); Phase 3 erweitert den `RewardService`, nicht den `GoldService`.
- **Telemetrie als CSV statt SQLite (vorerst):** Das SQLite-Addon (godot-sqlite, MIT) bringt native DLLs mit; deren Einbindung wurde nicht freigegeben. CSV braucht keinen fremden Code und lässt sich verlustfrei in jede Datenbank importieren. Ein SQLite-Speicherziel kann später `TelemetryStore.write_rows()` ersetzen, ohne die Erfassung zu ändern. Tests und Werkzeuge schreiben über `Session.telemetry_directory_override` in eigene Ordner.
- **Audio nur über Signale:** Gameplay-Code ruft `Audio` nicht auf; `MatchAudio` übersetzt Signale in Sounds. Ausnahme: UI-Fenster (Öffnen/Schließen).
- **Gegner-IDs:** Jeder Gegner bekommt vom Spawner eine fortlaufende `uid`. Belohnungsreferenzen (`kill:<uid>`) hängen daran statt an Godot-Instanz-IDs, damit sie später auch über das Netzwerk eindeutig sind.

## Erweiterungspunkte

- **Phase 3:** Fähigkeiten nutzen `StatBlock.ability_power()`/`heal_power()`, `StatusEffects` (Frost Nova, Shield Bash) und `CombatService`. Der `RewardService` erfasst zusätzlich effektive Heilung (`HealthComponent.heal` liefert schon nur den effektiven Anteil), absorbierte Schilde und Kontrolle. Ausrüstung schreibt in `StatBlock.bonus`. Taunt setzt in `Enemy._choose_target()` mit höchster Priorität an.
- **Phase 5:** `HeroInput` sendet Befehle per RPC an den Host; Host simuliert, `MultiplayerSynchronizer` repliziert Positionen und LP.

## Phase 3: Fähigkeiten, Shop, Inventar, Team-Gold

| Datei | Verantwortung |
|---|---|
| `scripts/skills/ability_caster.gd` | Komponente am Helden (`Abilities`): gelernte Stufen, Slots Q W E R D F (R nur Ultimate), Abklingzeiten (pausierbar), Mana, Zielwahl wie „Quick Cast“; Zielfähigkeiten außer Reichweite → Held läuft hin (`chase_point`, zählt nicht als Spielerbefehl) und wirkt dann |
| `scripts/skills/ability_effects.gd` | Wirkung jeder Fähigkeit (statisch, nach ID). Werte nur aus `data/skills/skills.json`; Wirkwert = Basis × Fähigkeitsstärke + Σ Skalierung × Attribut |
| `scripts/skills/fireball_projectile.gd`, `starfall_storm.gd` | Zeitlich ablaufende Effekte; Starfall markiert jede Einschlagstelle 0,6 s vorher |
| `scripts/items/inventory.gd` | 6 Ausrüstungsslots, Tasche, 2 Verbrauchsslots mit Stapeln; Boni → `StatBlock.bonus` |
| `scripts/economy/shop_service.gd` | Fähigkeiten, Gegenstände, Verkaufen, Verbrauch, Team-Upgrades, Spenden; erst prüfen, dann zahlen, dann gutschreiben |
| `scripts/gameplay/status_effects.gd` | erweitert: Gift (stapelbar, Schaden über Zeit), Taunt (mit Quelle), Schadensreduktion (max. 75 %), Eile, Tempo, Krit-, Rüstungsbonus; `last_gain` = tatsächlich neue Wirkdauer |
| `scripts/gameplay/health_component.gd` | erweitert: Schilde (älteste zuerst, Ablauf), `shield_absorbed` je Quelle |
| `scripts/economy/reward_service.gd` | neu aufgebaut: Abrechnung mit IDs (`add_damage/add_tank/add_control/add_support`, `settle_kill`, `wave_payout`), Signale nur als Adapter – ohne Szene simulierbar |
| `scripts/ui/ability_bar.gd`, `shop_window.gd`, `inventory_window.gd`, `team_overview.gd` | Oberfläche; kauft und wirkt nur über `MatchController.request_*` |

**Anfragen statt Direktzugriff:** Die UI ruft `MatchController.request_learn_ability/…buy_item/…cast/…team_upgrade` usw. auf. In Phase 5 werden genau diese Methoden zu RPCs an den Host.

**Team-Gold** ist ein eigenes Konto im `GoldService` (`TEAM_PEER = 0`). Es wird aus Wellen und ausdrücklichen Spenden gespeist, nie aus persönlichem Gold. Kern-Upgrades setzt `DefenseCore.apply_upgrade` um; die Barriere wird bei jedem Wellenstart erneuert.
