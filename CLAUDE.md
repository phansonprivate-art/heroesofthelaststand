# Heroes of the Last Stand – Anleitung für Claude

Koop-Hero-Defense (1–4 Spieler) in **Godot 4.4.1 / GDScript**. Helden verteidigen einen Kristallkern gegen Wellen von Untoten. Entwickelt nach einem Master-Prompt in Phasen 0–7. Der Spieler (Projektinhaber) schreibt Deutsch, Antworten und Projektdokumente auf Deutsch.

## Stand (2026-10-29)
- **Phasen 0–4 fertig**: Arena, 3 Helden (Guardian/Shadow/Arcanist), Fähigkeiten, Shop/Inventar/Team-Gold, beteiligungsbasierte Belohnungen, Telemetrie, 10 Wellen, Elite, Mini-Boss, Endboss Morvath (3 Phasen).
- **Alle drei Helden neu mit realistischen Proportionen** (Krieger in blau-goldener Platte, Assassine mit Kapuze/roter Maske, Magier mit Robe/Bart/Kristallstab), alle KayKit-Animationen laufen weiter. Modelle je ~80 000 Flächen – Bildrate im echten Spiel noch nicht geprüft.
- **Glutdrache** (`assets/models/enemies_custom/EmberDrake.glb`, eigenes Skelett, 9 Animationen) ist fertig, aber **noch nicht im Spiel** (kein Gegner-Eintrag, keine Welle) – Rolle entscheidet der Spieler.
- Davor: Upgrade-Vorschau im Shop (alt → neu), Balancing Iron Maelstrom schwächer / Shadow früh stärker (nicht gegengespielt, Schätzwerte).
- **Nächste Phase: 5 (Mehrspieler)** – erst beginnen, wenn der Spieler es sagt.
- Laufender Verlauf aller Entscheidungen: `docs/DEVELOPMENT_LOG.md` (vor größeren Änderungen lesen).
- Obsidian-MOC (Kurzstatus, siehe projektübergreifende Regel in `../CLAUDE.md`): `Projects/Gaming-HeroesOfTheLastStand/MOC - Gaming (Heroes of the Last Stand).md`.

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
- **Stilrichtung (2026-10-29):** Helden mit realistischen Proportionen wie im Konzeptbild des Spielers (seit 2026-10-29 alle drei Helden umgesetzt). Vorlagen dienen nur als Stilvorbild – eigene Formen, keine Kopien (z. B. eigener Sonnenstern statt Löwenwappen).
- Standardangriffe Krieger: Hieb, Diagonalhieb, **Stich** (der KayKit-Querhieb sah mit langen Proportionen wie ein Kopfstoß aus).
- Bei langen Aufgaben **nach jeder Phase einen Stand mit Vorschaubild** geben, dann weitermachen.

## Werkzeuge und Pfade
- Godot: `C:\Users\phant\Godot\Godot_v4.4.1-stable_win64.exe` (Konsole: `..._console.exe`), nicht im PATH.
- Blender 5.2: `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`, nur headless (`--background --python script.py -- args`).
- GitHub (**öffentlich**): https://github.com/phansonprivate-art/heroesofthelaststand, Zweig `main`. Commit/Push nur auf Wunsch des Spielers; Autor ist die noreply-Adresse (lokale git-Konfiguration), keine private E-Mail. `.godot/` wird nicht hochgeladen.
- Spiel starten: `Spiel starten.cmd` (Projektordner) oder Desktop-Verknüpfung „Heroes of the Last Stand“.
- Fähigkeiten-Vorschau mit Effekten: `tools/skill_showcase.cmd` (`-- --skill=<id>`). Modell-Viewer Helden: `tools/model_viewer.cmd`. Drachen-Viewer: `tools/dragon_viewer.cmd` (G = Größenvergleich, `-- --shots=<ordner>` für Bilder).
- Tests: `bash tools/run_tests.sh` (Filter: `TEST_ONLY=<teil des Testnamens>`); schlägt auch bei SCRIPT ERROR fehl. Aktuell 97 Tests, alle grün. Der Läufer zeigt Meldungen nur bei Fehlern; Texte zur Sichtprüfung kurz per `print` im Test ausgeben und danach wieder entfernen. Python ist nicht installiert (für Skripte bash/perl oder das Edit-Werkzeug nutzen).
- Neue Assets vor `-s`-Skripten importieren: `godot --headless --path . --import`.
- Bildschirmfotos/Sichtprüfung: temporäre Szene `tools/_tmp_*.tscn` (nicht headless, echtes Rendering) und danach löschen; Bilder in den Scratchpad legen.

## Blender-Pipelines (alles prozedural per Skript)
- `tools/blender_build_heroes.py` – Heldenmodelle (Baukasten `Rig`: Teile starr an Knochen, Spielraum Y-oben → Blender Z-oben).
- `tools/blender_build_enemies.py` – Gegnermodelle auf `Skeleton_Warrior`-Rig (95 Animationen). Waffenachse aus der Stehanimation berechnen (`hand_axis`).
- `tools/blender_hero_animations.py` – eigene Animationen (`kk/Fireball_Cast`, `kk/Sanctuary_Cast`).
- `tools/blender_fire_flipbooks.py`, `tools/blender_effect_textures.py` – Effekt-Texturen (8×8-Bildfolgen, Runenkreis, Blitze, Eiskristalle).
- `tools/blender_build_dragon.py` – Glutdrache mit **eigenem Skelett** (42 Knochen), in 7 Phasen: body, details, wings, rig, texture, anim, export. `-- --stage <phase> --preview <ordner>` baut bis zur Phase und rendert Vorschaubilder (ab `anim` ein Übersichtsbild aller Animationen). Methoden: Metaball-Ketten + Kopf-Loft → Voxel-Remesh; Röhren-Baukasten `Parts.tube` für Hörner/Krallen/Zähne mit Knochengruppe je Teil; Flughaut-Gitter mit gemischten Gewichten; Texturen per Cycles gebacken (Farbe+AO, Normal, Leuchten). Alle Entwurfskoordinaten laufen durch `place()`. Ganzer Lauf ~45 s.
- `tools/blender_build_realistic_heroes.py` – alle drei Helden (`--hero shadow|guardian|arcanist`) mit **realistischen Proportionen auf dem gestreckten KayKit-Skelett**. Phasen: skeleton, body, outfit, texture, export (`--stage`, `--preview`, `--out`). Ausrüstung je Held in `outfit_<held>`, Streckwerte/Körperbau je Held in `HEROES`. Waffen im Rahmen der Original-KayKit-Waffe (`weapon_axes`; vorher Ruhepose setzen, der Import hängt eine Animation an!). Werkstoffnummern je Fläche (`regions_per_face`), nie über Dreiecke mischen. Strecken nur über Knochenabstände (`OFFSET_SCALE`, Drehachsen bleiben), Positionsschlüssel der Aktionen mitskalieren (`scale_action_locations`). Ausrüstung als Schalen aus Hautbereichen (`shell`: Gewichte 1:1, geglättete Ränder, Saum) plus Röhren/Ringe; Werkstoffe je Punkt (`reg`/`treg`/`trim`) → ein Material, gebacken (Farbe+AO, Normal, ORM, Leuchten). Ganzer Lauf ~40 s je Held. Neue realistische Helden als weiteren Eintrag in `HEROES` bauen; `CharacterVisual._retarget_positions` rechnet die Zusatz-Animationen automatisch um.
- Stolpersteine: Szene vor Import auf 30 fps stellen; eine Figur je Blender-Prozess; Chibi-Proportionen (Kopf ~0,85–1 Einheit). Modelle schauen nach Blender −Y (= glTF +Z); `CharacterVisual` dreht sie in Godot um 180°, ein Viewer muss sie deshalb über `CharacterVisual` laden. Bei automatischen Gewichten Knochen außerhalb des Körpers (Flügel) und eigene Teile (Kiefer) vorher auf `use_deform = False` setzen.

## Godot-Stolpersteine
- In `-s`-Skripten keine Spielklassen typisieren (werden vor Autoloads kompiliert).
- `BILLBOARD_PARTICLES` braucht `billboard_keep_scale = true`, sonst ist jedes Partikel 1 m groß.
- `CPUParticles3D` zeigt ein Teilchen mit Startzeit 0 im ersten Durchlauf nicht: nie `amount = 1` oder `explosiveness = 1.0` für Einmal-Effekte.
- GDScript: bei Variant-Werten Typ angeben (`var x: float = ...`), sonst Parse-Fehler „Cannot infer the type“.
- JSON-Daten mit dem Edit-Werkzeug ändern (perl/sed haben früher Einträge zerstört); danach mit `perl -MJSON::PP` validieren.
- Voll metallischer heller Stahl spiegelt nur den dunklen Hintergrund und wirkt **schwarz** (kein Himmel/Reflexionsprobe): Stahl höchstens ~0,55 metallisch.
- Godot entpackt eingebettete GLB-Texturen als `<Modell>_<Bild>.png` neben die GLB; diese werden mit eingecheckt (wie bisher).
- Kopfzeilen-Prüfungen (`--headless -s`) berechnen keine Posen und kennen keine echten Texturen („Parameter "t" is null“ ist dort harmlos) – Sichtprüfung immer mit echtem Rendering.

## Architektur (Kurzfassung)
- Daten in `data/` (Helden, Fähigkeiten, Gegner, Wellen, Sounds, Balance), geladen über Autoload `GameData`.
- `MatchController` verdrahtet eine Runde; `CombatService` (Schaden), `StatusEffects` (Zustände inkl. `untargetable`, `channel`, `whirl`), `AbilityEffects` (Wirkung je Fähigkeit), `VfxLayer` (alle Effekte), `BossBrain` (Endboss), `Hud` (inkl. Bossleiste).
- `CharacterVisual`: lädt Modelle (dreht sie um 180°), hängt Zusatz-Animationen als Bibliothek „kk“ an und rechnet deren Positionsspuren auf gestreckte Skelette um (`_retarget_positions`, Zwischenspeicher je Modell). Bei mehreren Varianten (Angriffe) spielt `play()` die Variante, deren Länge vorher `animation_length()` geliefert hat (`_next_pick`).
- UI-Texte zu Werten in `UiTheme`: `format_skill_level` (eine Stufe), `format_skill_upgrade` (nur geänderte Werte alt → neu), `format_attribute_upgrade` (nutzt `StatBlock.preview_with_point`, eine Kopie, die nichts verändert), `scaling_text`. Fähigkeitswerte für den Helden immer über `AbilityEffects.power` / `power_for_stats`.
- Mehr: `docs/ARCHITECTURE.md`, `docs/GAME_DESIGN.md`, `docs/BALANCING.md`, `docs/TESTING.md`.
