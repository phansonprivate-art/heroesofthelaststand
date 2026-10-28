# Heroes of the Last Stand – Anleitung für Claude

Koop-Hero-Defense (1–4 Spieler) in **Godot 4.4.1 / GDScript**. Helden verteidigen einen Kristallkern gegen Wellen von Untoten. Entwickelt nach einem Master-Prompt in Phasen 0–7. Der Spieler (Projektinhaber) schreibt Deutsch, Antworten und Projektdokumente auf Deutsch.

## Stand (2026-10-28)
- **Phasen 0–4 fertig**: Arena, 3 Helden (Guardian/Shadow/Arcanist), Fähigkeiten, Shop/Inventar/Team-Gold, beteiligungsbasierte Belohnungen, Telemetrie, 10 Wellen, Elite, Mini-Boss, Endboss Morvath (3 Phasen).
- Zuletzt: Upgrade-Vorschau (Shop zeigt bei Fähigkeiten „Stufe X → Y“ mit alt → neu, Attribute zeigen „+1 bringt …“), Balancing Iron Maelstrom schwächer / Shadow früh stärker (nicht gegengespielt, Schätzwerte).
- **Nächste Phase: 5 (Mehrspieler)** – erst beginnen, wenn der Spieler es sagt.
- Laufender Verlauf aller Entscheidungen: `docs/DEVELOPMENT_LOG.md` (vor größeren Änderungen lesen).

## Unverhandelbare Regeln
- **Nichts erfinden**: keine erfundenen Dateien, Testergebnisse oder Prüfungen. „Getestet“ nur sagen, wenn der Test wirklich lief. Was nicht geprüft wurde (z. B. Klang nach Gehör), ausdrücklich sagen.
- **Keine Warcraft-III- (oder andere fremde) Inhalte/Namen.** Fremde Spiele dienen nur als Stil-/Mechanik-Vorbild; eigene Namen, eigene Effekte.
- Jede Änderung im `docs/DEVELOPMENT_LOG.md` festhalten; Designänderungen in `docs/GAME_DESIGN.md`.

## Entscheidungen des Spielers (gelten weiter)
- Steuerung LoL-artig: Maus bewegen/angreifen, A+Klick Angriffsbewegung, S Stopp, Fähigkeiten Q W E R D F (R = Ultimate ab Heldenstufe 5), Y Kamera fixieren, Leertaste zentrieren. Kein WASD.
- Fähigkeiten sind klassengebunden: mindestens 4 normale + Ultimates je Klasse (Guardian hat 5: Iron Maelstrom ist auf Wunsch eine normale Fähigkeit). Normale Slots: Q W E D F.
- **Neue Figuren/Gegner/Bosse selbst in Blender entwerfen** (eigene Modelle auf dem KayKit-Skelett), keine fertigen Pack-Modelle für neue Figuren.
- Effekte, Fähigkeits-Animationen im Stil klassischer Fantasy-Strategiespiele, Texturen/Animationen aus Blender.
- Zwischen den Wellen lange Einkaufszeit (30–50 s, N startet sofort); Ultimates ab Heldenstufe 5.
- Klänge: ElevenLabs über das verbundene Konto des Spielers ist erlaubt, **vor größeren Mengen Kosten (Credits) nennen und fragen** (je Variante ca. 17 Credits, bisher 2 Varianten je Klang).
- Die eigenen Blender-Heldenmodelle (`assets/models/heroes_custom/`) sind seit 2026-10-28 im Spiel aktiv (`data/heroes/heroes.json`).
- Listen von Fähigkeiten (Shop, Vorschau, Viewer): normale zuerst, **Ultimates ganz unten** (`GameData.skill_order`).
- Beim Verbessern muss sichtbar sein, **was sich ändert** (alt → neu). Neue Werte-Schlüssel in `UiTheme.SKILL_VALUE_NAMES` eintragen, sonst erscheinen sie nicht in Shop und Vorschau.
- Der Shadow soll im frühen Spiel nicht hinterherhinken; Guardian-Fähigkeiten nicht überstark machen.

## Werkzeuge und Pfade
- Godot: `C:\Users\phant\Godot\Godot_v4.4.1-stable_win64.exe` (Konsole: `..._console.exe`), nicht im PATH.
- Blender 5.2: `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`, nur headless (`--background --python script.py -- args`).
- GitHub (**öffentlich**): https://github.com/phansonprivate-art/heroesofthelaststand, Zweig `main`. Commit/Push nur auf Wunsch des Spielers; Autor ist die noreply-Adresse (lokale git-Konfiguration), keine private E-Mail. `.godot/` wird nicht hochgeladen.
- Spiel starten: `Spiel starten.cmd` (Projektordner) oder Desktop-Verknüpfung „Heroes of the Last Stand“.
- Fähigkeiten-Vorschau mit Effekten: `tools/skill_showcase.cmd` (`-- --skill=<id>`). Modell-Viewer Helden: `tools/model_viewer.cmd`.
- Tests: `bash tools/run_tests.sh` (Filter: `TEST_ONLY=<teil des Testnamens>`); schlägt auch bei SCRIPT ERROR fehl. Aktuell 97 Tests, alle grün. Der Läufer zeigt Meldungen nur bei Fehlern; Texte zur Sichtprüfung kurz per `print` im Test ausgeben und danach wieder entfernen. Python ist nicht installiert (für Skripte bash/perl oder das Edit-Werkzeug nutzen).
- Neue Assets vor `-s`-Skripten importieren: `godot --headless --path . --import`.
- Bildschirmfotos/Sichtprüfung: temporäre Szene `tools/_tmp_*.tscn` (nicht headless, echtes Rendering) und danach löschen; Bilder in den Scratchpad legen.

## Blender-Pipelines (alles prozedural per Skript)
- `tools/blender_build_heroes.py` – Heldenmodelle (Baukasten `Rig`: Teile starr an Knochen, Spielraum Y-oben → Blender Z-oben).
- `tools/blender_build_enemies.py` – Gegnermodelle auf `Skeleton_Warrior`-Rig (95 Animationen). Waffenachse aus der Stehanimation berechnen (`hand_axis`).
- `tools/blender_hero_animations.py` – eigene Animationen (`kk/Fireball_Cast`, `kk/Sanctuary_Cast`).
- `tools/blender_fire_flipbooks.py`, `tools/blender_effect_textures.py` – Effekt-Texturen (8×8-Bildfolgen, Runenkreis, Blitze, Eiskristalle).
- Stolpersteine: Szene vor Import auf 30 fps stellen; eine Figur je Blender-Prozess; Chibi-Proportionen (Kopf ~0,85–1 Einheit).

## Godot-Stolpersteine
- In `-s`-Skripten keine Spielklassen typisieren (werden vor Autoloads kompiliert).
- `BILLBOARD_PARTICLES` braucht `billboard_keep_scale = true`, sonst ist jedes Partikel 1 m groß.
- `CPUParticles3D` zeigt ein Teilchen mit Startzeit 0 im ersten Durchlauf nicht: nie `amount = 1` oder `explosiveness = 1.0` für Einmal-Effekte.
- GDScript: bei Variant-Werten Typ angeben (`var x: float = ...`), sonst Parse-Fehler „Cannot infer the type“.
- JSON-Daten mit dem Edit-Werkzeug ändern (perl/sed haben früher Einträge zerstört); danach mit `perl -MJSON::PP` validieren.

## Architektur (Kurzfassung)
- Daten in `data/` (Helden, Fähigkeiten, Gegner, Wellen, Sounds, Balance), geladen über Autoload `GameData`.
- `MatchController` verdrahtet eine Runde; `CombatService` (Schaden), `StatusEffects` (Zustände inkl. `untargetable`, `channel`, `whirl`), `AbilityEffects` (Wirkung je Fähigkeit), `VfxLayer` (alle Effekte), `BossBrain` (Endboss), `Hud` (inkl. Bossleiste).
- UI-Texte zu Werten in `UiTheme`: `format_skill_level` (eine Stufe), `format_skill_upgrade` (nur geänderte Werte alt → neu), `format_attribute_upgrade` (nutzt `StatBlock.preview_with_point`, eine Kopie, die nichts verändert), `scaling_text`. Fähigkeitswerte für den Helden immer über `AbilityEffects.power` / `power_for_stats`.
- Mehr: `docs/ARCHITECTURE.md`, `docs/GAME_DESIGN.md`, `docs/BALANCING.md`, `docs/TESTING.md`.
