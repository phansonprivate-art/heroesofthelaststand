# Entwicklungsprotokoll

## 2026-10-27 – Phase 0: Analyse und Plan

**Bestand:**
- `C:\Claude\Gaming\` enthielt nur das ältere, eigenständige Projekt `zombiesurvival/afterlight` (Godot 4.4, Koop-Aufbau-Survival). Es wurde nicht verändert. Übernommen wurden bewährte Muster: zentrale Tastenbelegung, JSON-Daten mit Validierung, Testläufer, Screenshot-Werkzeug.
- Godot 4.4.1 stable ist unter `C:\Users\phant\Godot\` installiert (nicht im PATH).
- Assets: KayKit Adventurers, Skeletons und Dungeon Remastered (CC0) aus github.com/KayKit-Game-Assets. Nur glTF/GLB und Texturen übernommen, FBX/OBJ/Beispielszenen weggelassen.
- Modellanalyse: Charaktere ≈ 2,2 m hoch, blicken nach +Z, enthalten 76–95 Animationen. An den Heldenmodellen hängen alle Waffen gleichzeitig (werden per Daten ausgeblendet). Skelette haben keine Waffen.

**Plan:** neues Projekt `heroes-of-the-last-stand/` mit der Struktur aus dem Master-Prompt. Phase 1 als vertikaler Schnitt mit Platzhalter-Blockout-Boden, aber echten Modellen für Figuren und Deko.

## 2026-10-27 – Phase 1: Spielbarer Kernprototyp

**Umgesetzt:** Hauptmenü, Arena, Kamera, Guardian, drei Gegnertypen, Kern, drei Testwellen, HUD, Schadenszahlen, Pause, Sieg/Niederlage, 24 Tests, Dokumentation. Details: [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md).

**Gefundene und behobene Probleme:**
- *Ladezyklus:* `enemy.tscn` → `enemy.gd` → `enemy_spawner.gd` → `preload(enemy.tscn)`. Lösung: Szene im Spawner erst zur Laufzeit laden.
- *Stille Testabbrüche:* Laufzeitfehler beendeten Testfunktionen, ohne dass sie fehlschlugen. Lösung: `tools/run_tests.sh` wertet jede `SCRIPT ERROR`-Ausgabe als Fehlschlag; Szenentests prüfen den vollständigen Aufbau als Vorbedingung.
- *Eingabe überschrieb fremde Befehle:* `HeroInput` setzte jeden Frame die Bewegungsrichtung, auch auf Null. Lösung: nur Änderungen senden (auch Vorbereitung für sparsame Netzwerkbefehle).
- *Screenshot-Werkzeug hing:* Mit `-s` werden typisierte Spielklassen vor den Autoloads kompiliert. Lösung: keine Typangaben im Werkzeug, außerdem ein Watchdog, der das Fenster spätestens nach 3 Minuten schließt.
- *Sichtprüfung:* Das Warnbanner schien durch den Endbildschirm; Schadenszahlen zeigten bei tödlichen Treffern nur den Rest-LP-Wert; Pfadstreifen waren zu dominant. Alles korrigiert.

**Bekannte Einschränkungen:**
- Nur ein Held (Guardian) ohne Attribute, Level oder Fähigkeiten
- Gold und XP sind in den Gegnerdaten definiert, werden aber noch nicht vergeben
- Keine Körperblockade zwischen Held und Gegnern
- Kein Audio
- Keine Einstellungen
- Kein Mehrspieler
- Skelette ohne Waffen (die passenden Modelle liegen bereit)
- Das Wellenende ist Sieg; Boss folgt in Phase 4

## 2026-10-27 – Steuerung auf MOBA-Stil umgestellt

Wunsch des Spielers: Steuerung wie in League of Legends.
- WASD entfernt. Bewegen und Angreifen per Rechtsklick, neu sind die Angriffsbewegung (A + Linksklick, mit Fadenkreuz-Cursor) und Stopp (S).
- Fähigkeitsslots jetzt **Q W E R D F**. Damit ist der W-Konflikt gelöst.
- Kamera: Y fixiert oder löst sie. Gelöst verschiebt sie sich am Bildschirmrand, die Leertaste zentriert sie, solange sie gedrückt ist.
- Neue Tests: Angriffsbewegung (greift unterwegs an und läuft danach weiter), Stopp, keine doppelt belegte Taste, Fähigkeiten im Q-W-E-R-D-F-Layout. Ergebnis: 27/27 bestanden.

## 2026-10-27 – Nähe-Aggro der Gegner

Rückmeldung des Spielers: Gegner liefen weiter zum Kern, statt den Helden anzugreifen. Neu: Jeder Gegnertyp hat einen `aggro_radius`. Kommt ein Held hinein, wird er angegriffen und verfolgt, bis er den `aggro_leash` verlässt. Gesucht wird alle 0,25 s statt jeden Frame. Neuer Test `test_enemy_aggros_hero_in_range`. Ergebnis: 28/28 bestanden.


## 2026-10-27 – Phase 2: Helden, Attribute und Kampf

**Umgesetzt:**
- **Drei Helden** mit Heldenauswahl im Hauptmenü: Guardian (Stärke), Shadow (Beweglichkeit, Doppeldolche, Krits), Arcanist (Intelligenz, zielsuchende magische Geschosse aus 9 m, 20 % Verlangsamung pro Treffer).
- **`StatBlock`** (reine Logik): Attribute = Basis + Wachstum je Stufe + gekaufte Punkte (Soft Cap 40, darüber halbe Wirkung) + Boni. Daraus Leben, Regeneration, Mana, Angriffsschaden, Angriffstempo, Krit, Rüstung, Magieresistenz, Lauftempo, Fähigkeits- und Heilungsstärke, alle mit Obergrenzen aus `data/balance/attributes.json`.
- **Kampfberechnung:** Rüstung bzw. Magieresistenz (Schaden × 50/(50+Wert)), wahrer Schaden, Krits (×1,75). Krits erscheinen groß in Orange mit „!“, magischer Schaden in Lila.
- **Status-Effekte:** Verlangsamung und Betäubung als Komponente, ohne Stapeln, mit Kontrollresistenz. Wirken auf Helden und Gegner; sichtbar als farbiger Schimmer.
- **Level 1–20 und XP:** Kill-XP für Beteiligte und Helden in 16 m, Wellen-XP für alle. Beim Levelaufstieg erscheinen Banner und Lichtring, gewonnene LP und Mana werden aufgefüllt.
- **Gold (aus Phase 3 vorgezogen):** `GoldService` mit Startgold 500, Protokoll und Schutz vor Doppelbuchungen. `RewardService` teilt Kill-Gold nach Schadensanteil auf und vergibt den Wellenbonus von 150 genau einmal.
- **Attribut-Käufe** `round(100 · 1.16^n)` über den `UpgradeService`; im Charakterfenster (C) mit Kosten, Begründung bei Fehlschlag und Hinweis auf den Soft Cap.
- **Schwierigkeit pro Welle:** +8 % Gegner-LP und +5 % Gegnerschaden je Welle.
- **HUD:** Stufe, XP-Balken, Leben, Mana, Gold, aktive Status-Effekte und ein pulsierender Hinweis, sobald ein Attribut-Kauf möglich ist.
- **Neue Werkzeuge:** `tools/stat_table.gd` (Heldenwerte je Stufe als Tabelle); das Screenshot-Werkzeug nimmt den Helden als Argument.
- **Tests:** 53 (vorher 28), alle bestanden.

**Gefundener und behobener Fehler:** Ein Gegner, der mit einem einzigen Treffer starb, brachte kein Gold. `died` feuert innerhalb von `apply_damage` und damit vor `damage_applied`, sodass der tödliche Treffer nie als Beteiligung erfasst wurde. Der Kill-Handler wertet ihn jetzt direkt aus. Ein eigener Test sichert das ab.

**Bekannte Einschränkungen:**
- Mana wird angezeigt und regeneriert, aber erst ab Phase 3 (Fähigkeiten) verbraucht.
- Belohnungen berücksichtigen bisher nur Schaden. Heilung, Schilde, Kontrolle, Rollenbonus und AFK-Erkennung kommen in Phase 3.
- Kein Team-Gold, kein Shop, keine Ausrüstung (Phase 3).
- Siehe auch den Beobachtungspunkt in [TESTING.md](TESTING.md#letzter-lauf).

**Nächster Schritt – Phase 3:**
1. Fähigkeitssystem: datengetriebene Definitionen mit drei Stufen, sechs Slots (Q W E R D F), Abklingzeiten, Manakosten, Fähigkeitsleiste im HUD
2. Erste Fähigkeiten laut Vorgabe: Shield Bash, Taunt, Arcane Barrier, Shadow Strike, Poison Mark, Fireball, Frost Nova, Healing Pulse, Guardian Blessing
3. Ultimates ab Stufe 10 (Bastion, Shadow Dance, Starfall) mit 90–120 s Abklingzeit
4. Shop (B) mit Kategorien, Ausrüstung (6 Slots + 2 Verbrauchsslots), Inventar (I)
5. Team-Gold und Kern-Upgrades
6. Beteiligung durch Heilung, absorbierte Schilde und wirksame Kontrolle; Rollenbonus; AFK-Erkennung; Balancing-Tests mit verschiedenen Rollen

## 2026-10-27 – Telemetrie (Balancing-Daten) und Audio

**Telemetrie:** Wunsch des Spielers, alle Werte für das Balancing in eine Datenbank zu schreiben.
- Geplant war SQLite über das Addon godot-sqlite (MIT; v4.5 ist die letzte Version für Godot 4.4). Die Einbindung der nativen DLLs wurde von der Sicherheitsprüfung nicht freigegeben und ist **nicht** im Projekt.
- Umgesetzt stattdessen ein `TelemetryService` mit CSV-Speicher. Sechs Tabellen mit festem Schema: Runden, Welle × Spieler, Welle × Gegnertyp, Gold-Transaktionen, Levelaufstiege, Helden-Endstand. Gemessen wird in Spielzeit (Pause zählt nicht), abgebrochene Runden werden gespeichert. Auswertung mit `tools/telemetry_report.gd`; die CSVs lassen sich direkt in SQLite oder Excel importieren.
- Die Tests fanden drei Fehler, alle behoben: eine doppelte Wellenzeile am Rundenende, fehlendes Startgold (gebucht, bevor die Telemetrie angeschlossen war) und Echtzeit statt Spielzeit.

**Audio:** 75 CC0-Sounds von Kenney (Treffer, Klingen, Magie, Knochen, Gold, Level-up, Jingles, UI), zentraler `AudioService` mit Pools, Mindestabstand und Höchstzahl je Ereignis, Bussen, automatischem Button-Klick. `MatchAudio` übersetzt Spielsignale in Sounds. Die Auswahl erfolgte nach Dateiname und Länge, **nicht nach Gehör**. Sie lässt sich in `data/audio/sounds.json` austauschen.
- Headless-Artefakt behoben: Der Dummy-Audiotreiber gibt abgespielte Instanzen nie frei. Deshalb spielt der Dienst headless nicht wirklich ab und verfolgt laufende Sounds über ihre Länge.

**Tests:** 60, alle bestanden.

**Offen:** Sounds anhören und bei Bedarf austauschen (besonders die Jingles); Lautstärkeregler (Phase 7); SQLite-Speicherziel, falls freigegeben; keine Musik (nur Jingles).

## 2026-10-27 – Nahkampf-Sounds überarbeitet

Rückmeldung des Spielers: Die Nahkampfangriffe klangen nicht gut. Vorher spielten Stoffrascheln beim Ausholen und ein blecherner Plattenklang beim Treffer.
- Neue Quelle: **RPG Sound Pack von artisticdude** (OpenGameArt, CC0) mit echten Schwert-Wuschs, Klingengeräuschen und Zaubersounds.
- Ausholen: Schwert-Wusch. Treffer Guardian: schwerer, dumpfer Schlag. Treffer Shadow: Messerschnitt. Krit: sehr schwerer Schlag plus helles Klingen-Klirren. Arcanist-Zauber: magischer Klang statt Sci-Fi-Phaser.
- Neu im Audio-Dienst: **Schichten** (`layers`). Treffer bekommen zusätzlich ein leises Knochenknacken, weil die Gegner Skelette sind.
- Auch diese Auswahl ist nicht angehört; die Zuordnung steht in `data/audio/sounds.json`.

## 2026-10-27 – Phase 3: Fähigkeiten, Gold, Shop

**Umgesetzt:**
- **13 Fähigkeiten** mit je 3 Stufen, datengetrieben (`data/skills/skills.json`). Jeder Held kann jede Fähigkeit lernen (hybride Builds). Ultimates ab Stufe 10, nur eines pro Held, nur auf R.
- **Fähigkeitsleiste** Q W E R D F mit Abklingzeit-Abdeckung, Stufen-Punkten, Mana-Kosten und Tooltips mit den für den Helden ausgerechneten Werten. Schnellwirken am Mauszeiger; Zielfähigkeiten außerhalb der Reichweite lassen den Helden erst hinlaufen.
- **Status-Effekte erweitert:** Gift (Stapel, Schaden über Zeit), Taunt (Zielpriorität), Schadensreduktion, Eile, Tempo, Krit- und Rüstungsbonus. **Schilde** in den Lebenspunkten.
- **Shop (B), Inventar (I), Teamübersicht (Tab)**. 9 Gegenstände, Verkaufen, Verbrauch auf 1/2.
- **Team-Gold** als eigenes Konto, Spenden, drei Kern-Upgrades mit je 3 Stufen.
- **Belohnungen neu:** Anteile aus Schaden, Kontrolle, Tanken und Taunt-Wirkung; Support-Gold für effektive Heilung, Schilde und verhinderten Schaden; Rollenbonus 0–100 nach Leistung; AFK-Erkennung; Kill-Gold skaliert mit der Spielerzahl.
- **Balancing-Test für Rollen**, mit dem kalibriert wurde: vorher 67 % Abstand zwischen Tank und Schurke, nachher 11,6 %.
- **Telemetrie Schema 2:** neue Spalten und die Tabelle `wave_abilities`. Alte CSVs werden bei Schemawechsel automatisch umbenannt, nicht vermischt.
- **Sounds** für jede Fähigkeit, Explosionen und Fehlversuche (weitere Kenney-CC0-Sounds).
- **UI-Aufräumen:** Steuerungshilfe ins Pausemenü verschoben, Heldenpanel verschlankt, Status-Effekte mit deutschen Namen.
- **Tests:** 82 (vorher 60), alle bestanden.

**Gefunden und behoben (durch Tests und Screenshots):**
- Rollen-Ungleichgewicht in der Belohnungslogik (siehe oben).
- Fehler in eigenen Tests: Groß-/Kleinschreibung einer Meldung, noch fliegendes Geschoss beim Messen, belegte Sound-Höchstzahl aus einem vorherigen Test.
- Heldenpanel überlappte die neue Fähigkeitsleiste; Steuerungshilfe überdeckte den Kernbalken.
- Ein früherer Pfad in der Doku war durch Steuerzeichen zerstört und wurde repariert.

**Bekannte Einschränkungen:**
- Keine Verteidigungstürme (optional laut Vorgabe; Team-Gold fließt vorerst in Kern-Upgrades).
- Elite- und Bossgegner fehlen noch (Phase 4); ihr Einfluss auf Belohnungen ist vorbereitet, aber nicht gewichtet.
- Fähigkeitssymbole sind Buchstabenkürzel, keine Grafiken.
- Shop überall nutzbar (bewusst, keine Laufwege).
- Der Rollenvergleich beruht auf einer Simulation mit angenommenem Verhalten; echte Daten kommen aus der Telemetrie.

**Nächster Schritt – Phase 4:** weitere Gegnertypen (Fernkämpfer, Elite mit Zusatzfähigkeit, Mini-Boss), zehn vollständige Wellen, finaler Boss mit drei Phasen und klaren Vorwarnungen, Sieg-/Niederlage-Ablauf mit Bosskampf.

## 2026-10-27 – Rückmeldung: Fernkampf-Aggro und Shop-Zugang

- **Fehler behoben:** Der Arcanist zog aus maximaler Reichweite (9 m) keine Aggro. Ein getroffener Gegner verfolgte den Angreifer nur innerhalb seines `aggro_leash` (5–8 m) und vergaß ihn deshalb sofort. Jetzt wird ein Angreifer bis zur Trefferdistanz + 4 m verfolgt. Test `test_ranged_attacker_gets_aggro`.
- **Shop auffindbar gemacht:** Knopf „Shop [B]“ an der Fähigkeitsleiste; Klick auf einen Fähigkeits- oder Verbrauchsslot öffnet den passenden Shop-Reiter; zu Beginn von Welle 1 erscheint ein Tipp, solange noch keine Fähigkeit gelernt ist. Test `test_shop_opens_with_b_and_slot_click` prüft auch die Taste B.
- Fähigkeitsleiste leicht nach rechts versetzt, damit sie das Heldenpanel nicht überdeckt. Tests: 84, alle bestanden.

## 2026-10-27 – Klassenfähigkeiten, Attribut-Skalierung, Animationen und Effekte

Wünsche des Spielers: Fähigkeiten nur für die eigene Klasse, Skalierung mit Attributen, deutlich bessere Animationen.

- **Fähigkeiten je Klasse** (`heroes` in `skills.json`, geprüft beim Lernen und gefiltert im Shop). Damit gilt die Vorgabe „jeder Held kann jede Fähigkeit lernen“ nicht mehr; hybride Builds entstehen weiter über Attribute und Ausrüstung.
  - Guardian: Shield Bash, Taunt, Guardian Blessing, Arcane Barrier · Ultimate Bastion
  - Shadow: Shadow Strike, Poison Mark, **Fan of Knives** (neu), **Smoke Bomb** (neu) · Ultimate Shadow Dance
  - Arcanist: Fireball, Frost Nova, **Chain Lightning** (neu), Healing Pulse · Ultimate Starfall oder Sanctuary
- **Stärkere Attribut-Skalierung:** Grundwerte gesenkt, Skalierung mit dem Hauptattribut erhöht (z. B. Fireball 1,6 × Int, Shadow Strike 2,0 × Agi, Arcane Barrier 3,0 × Str). Taunt-Rüstung und Segen-Reduktion skalieren ebenfalls (`scaled_keys`). Shop und Tooltips zeigen „Skalierung: 1,6 × Intelligenz (+40)“.
- **Effekte (`VfxLayer`):** Partikel-Explosionen, Bodenringe mit konstanter Breite, Frost-/Rauchflächen, Lichtsäulen, Blitzbögen, Rauchwolken, Meteore mit Schweif, Geschoss-Schweife. Dazu Staub beim Erscheinen, Knochensplitter beim Tod, Funken bei Krits, Kristallsplitter bei Kerntreffern. Höchstens 70 gleichzeitig, alles räumt sich selbst auf und pausiert.
- **Animationen:** eigene Körperanimation je Fähigkeit (z. B. Block_Attack, Cheer, 2H_Melee_Attack_Spinning, Throw, Spellcast_Raise), die nicht sofort überschrieben wird; Lauf-/Gehtempo passend zur Geschwindigkeit (verlangsamte Gegner bewegen sich sichtbar träger); Gegner zucken bei spürbaren Treffern kurz zusammen (0,2 s); Leichen versinken im Boden.
- Starfall: erster Einschlag immer genau auf dem Zielpunkt (vorher konnte ein gezielter Starfall die Gegner am Ziel komplett verfehlen).
- Tests: 86, alle bestanden (neu: Klassenbindung, neue Fähigkeiten, Skalierung mit Attributen und Stufe).
- Einschränkung: Die Effekte sind aus Grundformen und Partikeln gebaut, nicht aus handgemachten Texturen; die Animationen stammen aus dem KayKit-Rig (keine eigenen Animationen).

## 2026-10-27 – Effekte und Animationen im Stil klassischer Fantasy-Strategiespiele

Frage des Spielers: Gibt es Animationen ähnlich wie in Warcraft 3? Originalinhalte von Warcraft 3 sind urheberrechtlich geschützt und laut Vorgabe ausgeschlossen. Nachgebaut wurde deshalb der **Stil** mit freien CC0-Assets:

- **KayKit Character Animations 1.1** (Kay Lousberg, CC0, aus einem Spiegel der „Complete KayKit Collection v6“ mit Originallizenz): Die Bibliothek nutzt dasselbe Skelett wie unsere Figuren (alle Knochen vorhanden, Ruhepositionen identisch), daher werden ihre Animationen zur Laufzeit dazugeladen und nur der Skelettpfad umgeschrieben (`CharacterVisual.add_animation_libraries`, erreichbar als `kk/<Name>`). Genutzt: Sprung-Hieb (Shield Bash, Shadow Strike), Beschwörung (Starfall, Sanctuary), Schildhaltung (Bastion). Ehrliche Einordnung: Der Großteil dieser Bibliothek entspricht den Bewegungen, die die Figuren schon hatten.
- Ebenfalls übernommen (für Phase 4 und später): KayKit Adventurers 2.0 und Skeletons 1.1 mit **Necromancer** und **Skeleton Golem** sowie den Helden Druid, Ranger, Engineer und Barbarian (`assets/models/kaykit2/`).
- **Kenney Particle Pack** (CC0): 31 Texturen (Sterne, Funken, Flammen, Rauch, Runen- und Magiekreise, Lichtstrahlen, Schlagbögen, Wirbel, Brandflecken) in `assets/effects/particles/`.
- `VfxLayer` neu: texturierte Partikel, Bodenzeichen (Runenkreise, Brandflecken, Frostfläche), Lichtstrahlen, Schlagbögen, Meteore mit Flammenschweif. **Zustände an Einheiten:** kreisende Sterne bei Betäubung, Frostflocken bei Verlangsamung, Giftblasen, rotes Leuchten bei Spott, goldenes Funkeln bei Schutz. **Heldenschimmer** unter den Füßen in Heldenfarbe. Treffer-Funken bei Schlägen, Seelenlicht beim Tod der Skelette.
- Fähigkeiten neu gestaltet: Taunt als Donnerschlag mit Staubwelle; Segen und Heilung als heiliges Licht mit Strahl, Sternen und Runenkreis; Fireball mit Flammenschweif, Feuerexplosion und Brandfleck; Frost Nova mit Eissplittern und Kältenebel; Starfall mit großem Magiekreis; Klingenangriffe mit Schlagbögen.
- Fehler beim Bearbeiten: Eine Perl-Ersetzung (`$1[…]` wird als Array-Zugriff gelesen) hatte vier Fähigkeitseinträge beschädigt. Sie wurden wiederhergestellt und per JSON-Prüfung kontrolliert.
- Tests: 87, alle bestanden (neu: jede Fähigkeits-Animation existiert auf dem Modell ihrer Klasse).

## 2026-10-28 – Eigene Heldenmodelle aus Blender (noch nicht im Spiel aktiv)

Wunsch des Spielers: die Figuren selbst in Blender bauen. Entschieden: eigene Modelle für Guardian, Shadow und Arcanist auf **exakt demselben Skelett** wie bisher, damit alle Animationen unverändert funktionieren. Auf Wunsch des Spielers sind sie **noch nicht in `heroes.json` eingetragen**; das Spiel nutzt weiter die KayKit-Modelle, bis er die neuen im Viewer begutachtet hat.

- **Bauweise:** `tools/blender_build_heroes.py` (Blender 5.2, headless, ein Held pro Prozess). Es importiert das bisherige KayKit-GLB (liefert Skelett, alle 76 Animationen und die Handwaffen), löscht Körper, Helm/Hut und Cape und baut neue Teile aus Grundkörpern mit abgerundeten Kanten. Jedes Teil hängt starr an genau einem Knochen und wird zu zwei Meshes (Körper, Kopf) zusammengefasst. Ausgabe: `assets/models/heroes_custom/`.
- **Aussehen** (Chibi-Proportionen wie die übrigen Figuren der Welt):
  - Guardian: Plattenpanzer, Helmschale mit Nasenschutz und Kamm, Schulterplatten, blauer Umhang
  - Shadow: gerundete Kapuze mit Zipfel, Maske, leuchtend lila Augen, Kreuzgurt, kurzer Umhang
  - Arcanist: Robe mit orangem Saum, Glockenärmel, weißer Bart und Haar, Spitzhut mit geknickter Spitze
  - Klassenfarben wie in der Oberfläche
- **Behalten:** Schwert, Schild, Dolche, Stab und Buch sind weiterhin die KayKit-Modelle.
- **Prüfung** (`tools/verify_custom_models.gd`):
  - Kern-Knochen vollständig, Ruhehaltung identisch (0,00000 Abweichung)
  - alle 76 Animationen mit originaler Länge vorhanden
  - keine Animationsspur ohne Zielknochen
  - alle Handwaffen vorhanden
  - Sichtprüfung per Viewer-Screenshots von vorn, hinten, seitlich und in Lauf-, Angriffs-, Fähigkeits- und Todesposen
- **Unterwegs behobene Fehler:**
  - Blender rechnet mit Z oben, das Spiel mit Y oben. Teile lagen anfangs um 90° gekippt; jetzt wird im Spielraum entworfen und umgerechnet.
  - Animationen wurden mit 24 statt 30 fps exportiert und dadurch minimal kürzer; die Szene wird jetzt auf 30 fps gestellt.
  - Erste Köpfe waren zu klein, Hut und Helm schwebten darüber.
- **Modell-Viewer:** `tools/model_viewer.tscn`, Start per Doppelklick auf `tools/model_viewer.cmd` oder im Editor mit F6. Zeigt neue und alte Modelle zum Vergleich und alle im Spiel genutzten Animationen samt Verwendung, auch alle drei nebeneinander.
- Tests: 87, alle bestanden (Spielcode unverändert).
- Offen: Eintrag der neuen Modelle in `heroes.json` nach Freigabe durch den Spieler.

## 2026-10-28 – Passendere Fähigkeits-Animationen

Vorher teilten sich 16 Fähigkeiten 9 Körperanimationen. Innerhalb einer Klasse gab es Doppelungen: Giftmal und Rauchbombe (beide Wurf), Feuerball und Kettenblitz (beide Stoß). Shadow Dance nutzte die Jubel-Animation. Der Spieler hat sich für passendere vorhandene Animationen entschieden.

- **Neue Zuordnung** (`anim` in `skills.json`), ausgewählt anhand von Bildstreifen auf den neuen Modellen:
  - Schildstoß → `Block_Attack`: echter Schildschlag statt Sprunghieb, damit auch keine Doppelung mehr mit Shadow Strike
  - Giftmal → `1H_Ranged_Shoot`: Dolch auf das Ziel richten, das „Markieren“
  - Shadow Dance → `Dodge_Forward`: geduckter Vorwärtssprint statt Jubeln
  - Frost Nova → `2H_Melee_Attack_Chop`: Stab in den Boden rammen
  - Kettenblitz → `2H_Melee_Attack_Stab`: Stab beidhändig auf das Ziel stoßen
- **Bewusst nicht geändert:**
  - Arkane Barriere wird auf einen Verbündeten in bis zu 11 m Entfernung gewirkt. Die Handbewegung zum Ziel passt besser als eine Abwehrhaltung.
  - Rauchbombe wird bis zu 11 m weit geworfen und behält den Wurf.
- **Neu: Startpunkt** (drittes Element in `anim`, Anteil 0–0,9): Die Wirkung tritt beim Wirken sofort ein, der Aufprall liegt in diesen Animationen aber spät. Deshalb beginnen Schildstoß bei 20 %, Frost Nova bei 35 % und Kettenblitz bei 40 %. Der Aufprall fällt so etwa 0,2 s nach dem Effektbeginn. `CharacterVisual.play_action` hat dafür einen optionalen Parameter. Der Modell-Viewer berücksichtigt ihn und fotografiert im Bildmodus jetzt jede Fähigkeit.
- Gameplay unverändert: Die Animation ist rein optisch, Schaden und Effekte kommen weiterhin sofort.
- Tests: 87, alle bestanden. Neu ist die Prüfung, dass Animationen mit Startpunkt auch dort beginnen; per Gegenprobe kontrolliert, dass sie greift. `verify_custom_models.gd` prüft zusätzlich alle Fähigkeits-Animationen auf den neuen Modellen.
- Weiterhin geteilt: Starfall und Sanctuary nutzen dieselbe Beschwörung, der Arcanist wählt aber nur eine der beiden Ultimates. Für Zauber hat KayKit nur etwa fünf verschiedene Wirkbewegungen, mehr Vielfalt bräuchte eigene Animationen.
- Modell-Viewer: Taste **F** springt zur nächsten Fähigkeits-Animation und läuft der Reihe nach durch alle drei Helden. `-- --skill=<id>` startet direkt bei einer Fähigkeit. Die Infozeile zeigt zusätzlich den Startpunkt. Mit einer temporären Prüfszene kontrolliert: Start bei Shield Bash, alle 16 Fähigkeiten nacheinander mit Rücksprung zum Anfang, F aus der Reihenansicht. Danach wieder gelöscht.

## 2026-10-28 – Fähigkeiten-Vorschau mit Effekten

Rückmeldung des Spielers: Im Modell-Viewer sieht man nur die Körperbewegung, nicht, was die Fähigkeit bewirkt. Neues Werkzeug `tools/skill_showcase.tscn`, Start per Doppelklick auf `tools/skill_showcase.cmd`.

- **Echte Runde statt Nachbau:** Die Vorschau lädt `match.tscn` und wirkt über `AbilityCaster.request_cast` wie im Spiel. Effekte, Schadenszahlen, Zustände und Klänge kommen aus dem Spielcode, nichts ist doppelt programmiert.
- **Aufstellung:** freie Fläche südlich des Kerns. Wer wirkt, steht in der Mitte, die beiden anderen Helden stehen als Verbündete dahinter, davor fünf Trainingspuppen (Brute, Grunts, Runner).
  - Helden sind angehalten, laufen also nicht und greifen nicht automatisch an.
  - Puppen sind echte Gegner mit eigener Kopie der Werte: Lauftempo und Angriffsreichweite 0, 2000 LP. Treffer-Zucken, Färbung bei Betäubung, Verlangsamung, Spott und Gift sowie Lebensbalken funktionieren dadurch wie im Spiel.
- **Ablauf:** Die Fähigkeit wird alle 4 s neu gewirkt, auf Stufe 1–3 (↑/↓). F geht der Reihe nach durch alle 16 Fähigkeiten aller Helden. Vor jeder Vorführung wird alles zurückgesetzt: Plätze, LP, Zustände, Schilde und laufende Geschosse bzw. Sternenregen. Tab baut die Runde mit den alten bzw. neuen Modellen neu auf; das ändert nur die Daten im Speicher, nicht `heroes.json`.
- **Zielwahl:** Nahkampf trifft die vorderste Puppe. Fernkampf trifft die hinterste in Reichweite, damit Sprung, Blitz und Geschoss eine sichtbare Strecke haben. Vor dem hinteren Paar bleibt Platz, damit Shadow Strike nicht in einer anderen Puppe landet.
- **Geprüft** mit einer temporären Prüfszene, danach wieder gelöscht:
  - alle 16 Fähigkeiten ohne Fehlermeldung
  - erwartete Treffer: Fan of Knives 3 (Radius 4), Frost Nova 3 (Radius 5), Chain Lightning 3 Sprünge, Fireball 5, Shield Bash 1, Shadow Strike 1
  - Heldentreffer immer 0, Helden am Ende mit vollen LP
  - Tab wechselt auf die KayKit-Modelle
  - Bildschirmfotos aller Fähigkeiten nach 0,12, 0,35 und 1,1 s gesichtet
  - Dabei gefunden und behoben: Reste des Sternenregens und der Schild der Arkanen Barriere ragten in die nächste Vorführung.
- **Grenzen:** Die Puppen bewegen sich nicht. Verlangsamung und Spott zeigen sich deshalb nur als Färbung, nicht als langsameres Laufen bzw. Umdrehen zum Guardian.

## 2026-10-28 – Feuerball neu: Effekt und Wurf-Animation aus Blender

Wunsch des Spielers: Fähigkeiten in Blender gestalten, „ähnlich wie in Warcraft“, mit einem Bild als Stilvorlage: großer Feuerball mit langem Flammenschweif. Umgesetzt wurde zunächst der Feuerball als Muster. Alles ist neu erstellt; aus der Vorlage wurde nichts übernommen.

- **Feuer-Bildfolgen aus Blender** (`tools/blender_fire_flipbooks.py`, Cycles auf der Grafikkarte, ca. 2 Minuten):
  - Je 8 x 8 Bilder: `fire_loop.png` (wallende Feuerkugel, nahtlos wiederholbar) und `fire_explosion.png` (wächst, kühlt ab, zerfällt).
  - Prozedural statt Simulation: leuchtendes Volumen, die Form ergibt sich aus Rauschen plus Kugelabfall, die Farbe aus einem Temperaturverlauf.
  - Außerhalb des Feuers ist das Bild exakt schwarz, damit im Spiel kein Rahmen sichtbar wird.
- **Neue Bausteine im `VfxLayer`:**
  - `attach_fire`: brennende Kugel mit Glut-Hof.
  - `fire_trail` / `end_trail`: Flammenschweif, der in der Welt stehen bleibt und verglüht, auch nach dem Einschlag.
  - `fire_explosion`: zwei Hauptexplosionen und Nebenexplosionen, getönt, mit Lichtblitz.
  - Alle sind additiv und weich an Boden und Figuren.
- **`FireballProjectile`:** Zündung an der Hand, Feuerkugel mit Schweif und Funken, flackerndes Licht, große Explosion. Schaden, Tempo und Ablauf sind unverändert.
- **Wurf-Animation aus Blender** (`tools/blender_hero_animations.py`, Ausgabe `assets/models/heroes_custom/anims/Spell_Animations.glb`):
  - `Fireball_Cast`: Die Posen sind im Skript beschrieben, ausgehend von der Stehpose. Der Oberkörper dreht zurück, die linke Hand sammelt an der Hüfte. Dann folgt der Stoß nach vorn mit offener Handfläche, während der Stabarm gegenschwingt. Danach sinkt der Arm zurück.
  - Die Beine bleiben in der Stehpose, die Füße rutschen nicht.
  - Der Wurf liegt bei 0,13 s, weil der Feuerball sofort startet.
  - Im Spiel heißt sie `kk/Fireball_Cast`: Der Arcanist lädt die Bibliothek über `anim_libraries`, die Animation funktioniert auf altem und neuem Modell.
- **Zwei Eigenheiten von Godot 4.4 gefunden** (per Testszenen nachgewiesen, Varianten nebeneinander):
  1. Partikel mit `BILLBOARD_PARTICLES` ignorieren ihre Größe, solange `billboard_keep_scale` aus ist; alle sind dann 1 m groß. Für die Feuer-Bildfolgen ist es eingeschaltet. Die bisherigen Effekte zeigen deshalb alle etwa 1 m große Partikel. Sie wurden so per Bildschirmfoto abgestimmt und bleiben vorerst unverändert.
  2. `CPUParticles3D` lässt das Teilchen mit Startzeit 0 im ersten Durchlauf aus. Einzelne Teilchen und `explosiveness = 1.0` erscheinen daher nie. Explosionen nutzen deshalb mehrere Teilchen bei 0,95.
- **Geprüft:**
  - Bildfolgen von Flug, Schweif und Explosion (weiter Schuss, Schuss in die Gruppe)
  - Posen der Wurf-Animation von vorn und seitlich
  - Ablauf im Zusammenhang in der Fähigkeiten-Vorschau
  - Tests: 87, alle bestanden; `verify_custom_models.gd`: ALLES OK, inklusive der neuen Animation auf allen Modellen

## 2026-10-28 – Neue Effekte für alle Fähigkeiten (Blender)

Wunsch des Spielers: der Stil des neuen Feuerballs für alle Fähigkeiten.

- **Neue Effekt-Texturen aus Blender** (`tools/blender_effect_textures.py`, prozedural, alles selbst erstellt):
  - Rauchwolke und Energiestoß als Bildfolgen (8 x 8)
  - Druckwellen-Ring, Runenkreis, Lichtsäule, Funkeln und 8 Blitzformen als Einzelbilder; Linien mit weichem Schein (nachträglich weichgezeichnet)
  - 6 Eiskristall-Modelle (`assets/models/effects/ice_shards.glb`)
- **Neue Bausteine im `VfxLayer`:** `energy_burst`, `smoke_cloud` (deckend gemischt, anhaltende Wolken spielen langsamer ab), `shockwave`, `sparkles`, `ice_shards`, `knife_fan` (Messer-Modell des Schattens).
  - `lightning` nutzt jetzt die Blitz-Textur: zwei Lagen, flackert.
  - `meteor` fällt als Feuerkugel mit Flammenschweif und Feuerexplosion.
  - Aufstiegs-Effekt mit Lichtsäule, Runenkreis und Funkeln.
- **Partikelgrößen repariert:** `billboard_keep_scale` ist für alle Partikel eingeschaltet; die eingestellten Größen gelten jetzt. Treffer-, Zustands- und Todes-Effekte wurden darauf neu abgestimmt.
- **Je Fähigkeit** (Spiellogik unverändert, nur Darstellung):
  - Guardian:
    - Schildstoß: goldener Stoß und Druckwelle
    - Spott: zwei rote Druckwellen und Staub
    - Segen: Lichtsäulen, Runenkreis und Funken
    - Arkane Barriere: Blitz-Verbindung, Runenkreis
    - Bastion: breite Lichtsäule, großer Runenkreis, zwei Druckwellen
  - Shadow:
    - Shadow Strike: Schattenrauch, violetter Streif
    - Giftmal: Giftstreif, Giftwolke
    - Messerfächer: 12 fliegende Messer
    - Rauchbombe: dichte Rauchwolke für die ganze Dauer
    - Schattentanz: Rauch, Runenkreis, Funken
  - Arcanist:
    - Frost Nova: Eiskristalle brechen aus dem Boden, dazu Kältenebel
    - Kettenblitz: texturierte Blitze
    - Heilpuls und Sanctuary: grüne Lichtsäulen, Runenkreise
    - Starfall: Feuer-Meteore
- **Sanctuary** hat eine eigene Blender-Animation (`kk/Sanctuary_Cast`: Arme im V zum Himmel) und teilt sich keine Bewegung mehr mit Starfall. Beim Feuerball-Wurf war die Vorwärtsneigung vertauscht; das ist korrigiert.
- **Geprüft** mit einer temporären Prüfszene in der Fähigkeiten-Vorschau:
  - alle 16 Fähigkeiten ohne Fehler, Treffer wie erwartet
  - Bildschirmfotos nach 0,15, 0,45 und 1,0 s gesichtet
  - nach 6 s keine Effekte, Knoten oder Geschosse übrig
  - Gefunden und behoben: Das Messer-Mesh wurde nicht gefunden (gleichnamiger Knochen-Anhänger); Skalierung auf 0 erzeugte Fehler. Rauchbombe und Giftwolke waren zu dünn.
  - 87 Tests bestanden, `verify_custom_models.gd` ALLES OK.

## 2026-10-28 – Neues Ultimate: Blade Dance (Shadow)

Wunsch des Spielers, mit einer eigenen Spezifikation („Phantom-Tanz / Blade Dance“, angelehnt an die Mechanik eines bekannten MOBA-Ultimates). Umgesetzt mit eigenem Namen, eigenen Effekten und ohne fremde Inhalte; es ist eine Alternative zu Shadow Dance, man lernt nur eines der beiden.

- **Ablauf** (`scripts/skills/blade_dance.gd`):
  - Ziel ist ein Gegner (Reichweite 6 / 6,5 / 7 m); 6 / 7 / 8 Sprünge in 0,5 / 0,55 / 0,6 s, der erste sofort.
  - Sprungpunkte liegen auf einem Kreis von 1,8 m um das Ziel, je 135° versetzt: kreuz und quer, alle acht 45°-Richtungen.
  - Jeder Sprung: eigener Krit-Wurf (Krit-Buffs zählen mit), Schaden = Basis × Fähigkeitsstärke + 1,2 × Beweglichkeit, Treffereffekt des Helden. Ist Poison Mark gelernt, kommt je Sprung ein Giftstapel dazu. Lebensraub oder Rüstungsreduzierung gibt es im Spiel bisher nicht.
  - Stirbt das Ziel, gehen die restlichen Sprünge auf den nächsten Gegner (bis 6 m), sonst endet der Tanz.
  - Am Ende steht der Held neben dem Ziel und greift es weiter an.
- **Neuer Zustand `untargetable`:** kein Schaden (CombatService), Gegner wählen den Helden nicht als Ziel und lassen ihn los; der Held läuft und greift solange nicht selbst an und schimmert violett.
- **Effekte:** violetter Blitzstreif je Sprung, Schattenrauch am Absprung, Schlagbogen, Funken, goldener Stoß bei Krit, zum Schluss Energiestoß und Druckwelle. Eigener Klang beim Wirken.
- **Tests:** neu `test_blade_dance`:
  - genau so viele Treffer wie Sprünge, Dauer etwa 0,5 s
  - währenddessen unverwundbar und nicht anvisierbar, danach wieder normal
  - Ende neben dem Ziel; Zielwechsel, wenn das Ziel stirbt
  - 88 Tests, alle bestanden. In der Fähigkeiten-Vorschau per Bildfolge gesichtet.

## 2026-10-28 – Neues Ultimate: Dagger Cyclone (Shadow)

Wunsch des Spielers: ein Ultimate angelehnt an die Mechanik eines bekannten MOBA-Ultimates (Messerwirbel auf der Stelle). Rückfrage: Blade Dance aufwerten oder neues Ultimate? Entscheidung: neues Ultimate. Eigener Name, eigene Effekte; dritte Wahl neben Shadow Dance und Blade Dance (eines pro Held).

- **Ablauf** (`scripts/skills/dagger_cyclone.gd`):
  - 2,5 s Wirbel auf der Stelle; alle 0,2 s je ein Messer auf die bis zu 3 nächsten Gegner im Radius (5,5 / 6 / 6,5 m)
  - Schaden je Messer: 16 / 24 / 32 + 0,45 × Beweglichkeit; Treffereffekt des Helden, Giftstapel bei gelerntem Poison Mark
  - Kanalisiert (neuer Zustand `channel`): Ein Bewegungsbefehl, Betäubung oder Tod beenden den Wirbel; solange steht der Held und greift nicht automatisch an.
- **Effekte:** neues `VfxLayer.thrown_knife` (Messer-Modell mit Glanzpunkt und Leuchtspur, dreht sich im Flug), pulsierende Druckwellen, Klingenbögen, Energiestoß beim Start. Eigener Klang beim Wirken.
- **Tests:** neu `test_dagger_cyclone`:
  - Die drei nächsten Gegner bekommen jede Welle ein Messer, der vierte und einer außerhalb des Radius nicht.
  - Der Held bleibt stehen; ein Bewegungsbefehl bricht ab, danach fliegen keine Messer mehr.
  - 89 Tests, alle bestanden.
  - Die Messer waren bei voller Geschwindigkeit auf Bildschirmfotos nicht zu sehen; per Zeitlupe gesichtet, danach Glanzpunkt und Spur verstärkt.

## 2026-10-28 – Neues Ultimate: Iron Maelstrom (Guardian)

Wunsch des Spielers als Konzept „Wirbelsturm (Tank AOE Spin)“. Eigener Name und eigene Effekte. Umgesetzt als Ultimate-Alternative zu Bastion: Ein dritter normaler Skill hätte die Regel „4 normale Fähigkeiten je Klasse“ gebrochen, und die letzten Wünsche waren ebenfalls Ultimates.

- **Ablauf** (`scripts/skills/iron_maelstrom.gd`):
  - 3 s Wirbel; der Held bleibt frei beweglich (neuer Zustand `whirl`: Laufen ja, normale Angriffe nein, Lauf-Animation überschreibt die Drehung nicht).
  - Alle 0,25 s Treffer auf jeden Gegner im Radius 3 / 3,3 / 3,6 m; Schaden 10 / 15 / 20 + 0,35 × Stärke je Treffer.
  - Der nächste Gegner erhält +50 % (Rüstungsreduzierung gibt es im Spiel bisher nicht).
  - Jeder Treffer würfelt einzeln auf Krit: eigene Krit-Chance der Fähigkeit 15 / 20 / 25 % plus die des Helden (der Guardian hat sonst 0 %).
  - Schutz: 20 / 25 / 30 % weniger Schaden für die Dauer. Betäubung oder Tod beenden den Wirbel.
- **Effekte:** neues `VfxLayer.blade_vortex`. Drehender Wirbelring am Boden zeigt den Radius, drei Klingenbögen in Hüfthöhe drehen gegenläufig; beides läuft mit dem Helden mit. Metallfunken je Treffer; bei Krit heller Stoß, großer Funkenflug und Schnitt. Druckwelle zu Beginn und am Ende, eigener Klang.
- **Tests:** neu `test_iron_maelstrom`:
  - Gegner im Radius bekommen etwa 12 Treffer, keine zusätzlichen normalen Angriffe; außerhalb des Radius keiner.
  - Der nächste Gegner nimmt deutlich mehr Schaden; einzelne, nicht alle Treffer kritisch (feste Zufallszahl).
  - Schutz aktiv; der Held läuft während des Wirbels.
  - 90 Tests, alle bestanden. In der Vorschau gesichtet, auch im Laufen; nach dem Ende bleiben keine Wirbel-Knoten am Helden.

## 2026-10-28 – Kriegsschrei für Iron Maelstrom

Wunsch des Spielers: ein Kriegsschrei beim Wirbeln. Entscheidungen des Spielers: Stimme mit ElevenLabs erzeugen, und zwar ein wortloses Brüllen.

- **Ton:** vier Varianten mit ElevenLabs (Soundeffekte, `eleven_text_to_sound_v2`) über das verbundene Konto des Spielers erzeugt; 4 × ca. 17 Credits. Dateien `assets/audio/voice/warcry_1-4.mp3` (1–3 s); Herkunft in `assets/licenses/ElevenLabs_generated_warcry_SOURCE.txt`.
  - Neues Ereignis `warcry` in `sounds.json`, beim Wirken als Ebene von `cast_iron_maelstrom`; zufällige Variante je Wirken.
  - Die Auswahl und Lautstärke sind nicht nach Gehör geprüft, nur Format und Länge.
- **Bild:** zusätzlich ein goldener Energiestoß in Kopfhöhe und eine weite goldene Druckwelle beim Start.
- 90 Tests bestanden (`test_config_valid` prüft, dass alle Tondateien vorhanden sind).

## 2026-10-28 – Neues Ultimate: Glacial Rift (Arcanist)

Wunsch des Spielers als Konzept „Eisstachel-Pfad (Eis-Skillshot / Line-AoE)“. Eigener Name, eigene Effekte. Umgesetzt als dritte Ultimate-Wahl des Arcanist (neben Starfall und Sanctuary), damit die Regel „4 normale Fähigkeiten je Klasse“ bleibt.

- **Ablauf** (`scripts/skills/glacial_rift.gd`):
  - Ziel ist eine Richtung (Mauszeiger). Eine Front aus Eisstacheln läuft mit 26 m/s vom Helden nach vorn; alle 1,1 m bricht eine Gruppe aus dem Boden. Reichweite 11 / 12 / 13 m, Bahnbreite 1,8 m.
  - Jeder Gegner in der Bahn wird genau einmal getroffen: Magieschaden 60 / 95 / 130 + 0,9 × Intelligenz, 0,75 / 0,85 / 1,0 s hochgeschleudert (Betäubung, die Figur fliegt sichtbar hoch und landet), danach 50–60 % verlangsamt.
  - Die Stacheln bleiben 1,5 / 1,8 / 2,0 s als Hindernis stehen (Kollision wie Mauern) und zersplittern dann.
- **Effekte:**
  - `VfxLayer.line_indicator`: Ziel-Pfeil am Boden, beim Wirken (das Spiel nutzt Schnellwirken, es gibt keinen vorherigen Zielmodus).
  - `VfxLayer.ice_eruption`: aufgerissener Boden, wegfliegende Gesteinsbrocken, drei große Eiskristalle (Blender-Modelle) im Winkel von etwa 60° nach vorn-oben, beim Zersplittern Eisfunken und Frostnebel.
  - Stoß-Animation `kk/Ranged_Magic_Shoot`; Glas-Klänge beim Wirken und je Ausbruch.
- **Tests:** neu `test_glacial_rift`:
  - Der nahe Gegner wird zuerst getroffen, der ferne erst später (Welle, kein Sofortschaden).
  - Hochschleudern und Verlangsamung wirken; das Eis steht als Hindernis und verschwindet wieder.
  - Gegner neben der Bahn und hinter ihrem Ende bleiben unberührt; niemand wird doppelt getroffen.
  - 91 Tests, alle bestanden. In der Vorschau gesichtet; 5 s nach dem Wirken sind alle Effekte aufgeräumt.

## 2026-10-28 – Glacial Rift: kürzer und neue Klänge

Rückmeldung des Spielers: Der Strahl ist zu lang; er wünscht gute Klänge über ElevenLabs.

- Reichweite von 11 / 12 / 13 m auf 7 / 8 / 9 m verkürzt (Zielpfeil und Eisbahn).
- Neue Klänge mit ElevenLabs (Soundeffekte, über das Konto des Spielers; 8 × ca. 17 Credits):
  - je 4 Varianten „Eiskristalle brechen aus dem Boden“ (`ice_erupt`, beim Wirken) und „Eis zersplittert“ (`ice_shatter`, einmal mitten auf der Bahn, wenn das Eis zerfällt)
  - Dateien in `assets/audio/ice/`; Herkunft in `assets/licenses/ElevenLabs_generated_ice_SOURCE.txt`
  - Die bisherigen Glas-Klänge je Stachelgruppe sind entfernt, damit sie den neuen Klang nicht überlagern.
  - Lautstärke und Auswahl nicht nach Gehör geprüft.
- Test an die kürzere Bahn angepasst; 91 Tests bestanden.

## 2026-10-28 – Neue Klänge für alle Fähigkeiten (ElevenLabs)

Wunsch des Spielers: die ElevenLabs-Klänge wie bei Glacial Rift für alle Fähigkeiten, 2 Varianten je Klang.

- 21 Klänge × 2 Varianten = 42 Dateien in `assets/audio/skills/`, über das ElevenLabs-Konto des Spielers erzeugt (Soundeffekte, ca. 700 Credits). Herkunft in `assets/licenses/ElevenLabs_generated_skills_SOURCE.txt`.
- Neu vertont:
  - Wirken aller 19 übrigen Fähigkeiten: Guardian 6, Shadow 7, Arcanist 6
  - Einschläge von Fireball und Starfall
  - Glacial Rift und der Kriegsschrei hatten schon eigene Klänge.
- `sounds.json`: Die Ereignisse zeigen auf die neuen Dateien, je Wirken zufällig eine Variante.
  - Alte Zusatzebenen (z. B. Klingenklang, Schild-Summen) sind entfernt, damit nichts doppelt klingt; Iron Maelstrom behält den Kriegsschrei.
  - Lautstärke einheitlich −4 dB, die oft wiederholten Starfall-Einschläge −9 dB.
- Nicht nach Gehör geprüft (nur Format, Vollständigkeit, keine Duplikate). 91 Tests bestanden; `test_config_valid` prüft, dass alle Dateien existieren.

## 2026-10-28 – Phase 4: neue Gegner, Mini-Boss, Endboss, zehn Wellen

Der Spieler hat Phase 4 gestartet und festgelegt, dass neue Figuren künftig in Blender entworfen werden.

- **Neue Gegnertypen** (`data/enemies/enemies.json`):
  - Knochenseher (`seer`, Fernkämpfer)
  - Grabritter (`grave_knight`, Elite mit Bodenschlag)
  - Knochenkoloss (`colossus`, Mini-Boss)
  - Morvath (`morvath`, Endboss)
  - Neue Datenfelder: `projectile` (Fernkampf), `ability` (Zusatzfähigkeit, bisher `stomp`), `boss` (Phasen, Fähigkeiten, Texte).
- **Gegnerlogik** (`enemy.gd`):
  - Fernkampf über `Projectile` (Schaden beim Einschlag)
  - Bodenschlag mit Ankündigung: roter Warnkreis, der Gegner steht still, danach Schaden und Verlangsamung im Kreis; Betäubung bricht ihn ab
  - Raserei-Faktoren für Angriffs- und Lauftempo
- **Endboss** (`scripts/enemies/boss_brain.gd`): drei Phasen bei 66 % und 33 %.
  - Beschwören (Kreise erscheinen vorher), Seelenfeuer (Kreise unter Helden, dann Explosion), Raserei und Todeswelle (wachsender Ring, dann Schaden).
  - Beschwörungen zerfallen beim Tod des Bosses.
  - Neu: `EnemySpawner.spawn_at` (Gegner ohne Wegpunkte direkt zum Kern); der Spawner kennt die Spielwelt für Effekte.
- **HUD:** Bossleiste mit Lebenspunkten und Phase; Banner bei Auftritt, Phasenwechsel und Sieg. Der Endboss behält die Leiste, auch wenn ein Mini-Boss dazukommt.
- **Zehn Wellen:** Mini-Boss in Welle 5 und 9, Endboss in Welle 10; der Sieg folgt aus dem Fall des Bosses.
- **Eigene Blender-Modelle** (`tools/blender_build_enemies.py`, Ausgabe `assets/models/enemies_custom/`):
  - Gemeinsamer Knochenkörper plus eigene Ausstattung je Figur: Kapuzenrobe mit Leuchtstab; rostige Rüstung mit Hörnerhelm, Schwert und Schild; Knochenriese mit Dornen und Keule; Lich mit Krone, offener Robe, Seelenlicht und Schädelstab.
  - Grundlage ist das KayKit-Skelett „Skeleton_Warrior“ mit 95 Animationen.
  - Der Baukasten der Helden wird importiert (`blender_build_heroes.py` baut beim Import nichts mehr).
  - Waffenrichtung: wird aus der Stehanimation der Figur berechnet, damit Waffen beim Stehen aufrecht in der Hand liegen. Die erste Annahme „nach vorn“ ließ sie zur Seite abstehen.
- **Klänge:** Bodenschlag und Bossfähigkeiten vorerst mit vorhandenen Kenney-Klängen.
- **Tests:** neu `test_bosses.gd`, 5 Tests:
  - Daten und zehn Wellen
  - Seher schießt aus Distanz
  - Bodenschlag nur nach der Warnung und nur im Kreis
  - Bossphasen, Beschwörung, Seelenfeuer (wer ausweicht, bleibt heil), Todeswelle, Zerfall der Beschwörungen
  - Sieg nach dem Fall des Bosses
  - 96 Tests, alle bestanden.
- **Gesichtet:** Modelle per Bildschirmfoto (vorn, hinten, Angriff, Nahaufnahmen) und ein Bosskampf in einer echten Runde (Warnkreise, Banner, Bossleiste).
- **Offen:** Balancing der neuen Werte mit echten Spieldaten; eigene ElevenLabs-Klänge für Boss und Bodenschlag.

## 2026-10-28 – Mehr Einkaufszeit, Ultimates ab Stufe 5

Wünsche des Spielers:
- **Mehr Zeit zum Einkaufen:** Die Vorbereitungszeit zwischen den Wellen ist auf 30–50 s verlängert, vorher 12–25 s. Vor den Mini-Bossen gibt es 45 s, vor dem Endboss 50 s. Mit „Jetzt starten“ (N) beginnt die Welle weiterhin sofort.
- **Ultimates ab Heldenstufe 5** statt 10 (`AbilityCaster.ULT_HERO_LEVEL`). Texte in Shop, Fähigkeitsleiste, Daten und Doku sind angepasst, der Test prüft Stufe 5.

## 2026-10-28 – Eigene Heldenmodelle im Spiel aktiv

Auf Wunsch des Spielers verweist `data/heroes/heroes.json` jetzt auf die Blender-Modelle Guardian, Shadow und Arcanist in `assets/models/heroes_custom/` statt auf die KayKit-Originale. `verify_custom_models.gd`: ALLES OK, 96 Tests bestanden. Zurück auf KayKit geht es, indem man die drei `model`-Pfade wieder auf `assets/models/heroes/` setzt.

## 2026-10-28 – Iron Maelstrom wird normale Fähigkeit

Wunsch des Spielers: Der Klingenwirbel des Guardian ist eine Standardfähigkeit statt eines Ultimates.
- `kind` normal, Kosten 320 / 380 / 520 Gold, Abklingzeit 16 / 14 / 12 s, Mana 60 / 65 / 70. Die Wirkung ist unverändert.
- Der Guardian hat damit 5 normale Fähigkeiten. Das passt in die 5 normalen Slots (Q W E D F). Die Regel „4 normale je Klasse“ ist für diesen Fall aufgehoben, der Test prüft jetzt mindestens 4.
- 96 Tests bestanden.

## 2026-10-28 – Ultimates ganz unten

`GameData.skill_order` sortiert jetzt normale Fähigkeiten zuerst und Ultimates ans Ende, sonst bleibt die Reihenfolge der Datei. Das gilt für Shop, Fähigkeiten-Vorschau und Modell-Viewer, der dafür jetzt auch `skill_order` nutzt. 96 Tests bestanden.

## 2026-10-28 – Balancing: Iron Maelstrom schwächer, Shadow am Anfang stärker

Rückmeldung des Spielers: Der Klingenwirbel ist zu stark, der Shadow (Assassine) hat es in den ersten Wellen viel schwerer.
- **Iron Maelstrom:** Schaden je Treffer 10/15/20 → 6/10/14; Schutz 20/25/30 % → 10/15/20 %; Dauer 3 → 2,5/2,5/3 s; Radius 3,0/3,3/3,6 → 2,8/3,0/3,3 m; Bonus auf den nächsten Gegner +50 % → +30 %; Abklingzeit 16/14/12 → 20/18/16 s; Mana 60/65/70 → 70/75/80.
- **Shadow, Stufe 1** (frühes Spiel):
  - Shadow Strike: Schaden 25 → 40, Abklingzeit 7 → 6 s, Mana 35 → 30
  - Poison Mark: 5 → 8 Schaden/s, Mana 30 → 25
  - Fan of Knives: Schaden 20 → 30, Abklingzeit 9 → 8 s, Mana 40 → 35
- Test zählt beim Wirbel nur noch Treffer während des Wirbels (danach greift der Held normal an). 96 Tests bestanden. Nicht gegengespielt; die Werte sind Schätzungen.

## 2026-10-28 – Upgrade-Vorschau: Was verbessert sich?

Wunsch des Spielers: Beim Verbessern soll man sehen, was sich ändert.
- **Fähigkeiten (Shop):** Beim Verbessern zeigt der Shop „Verbesserung Stufe X → Y“ und listet nur die geänderten Werte als alt → neu, z. B. „Mana 50 → 55 · Abklingzeit 6 s → 5.5 s · Schaden 78 → 115 · Radius 2.5 m → 3 m“. Skalierende Werte sind für den eigenen Helden ausgerechnet, also mit Attributen. Vor dem Lernen steht die volle Stufe 1, auf Stufe 3 die vollen Werte. Neu: `UiTheme.format_skill_upgrade`.
- **Attribute (Shop und Charakterfenster C):** „+1 bringt: …“ zeigt die genauen Zugewinne, z. B. „Leben +20 · LP-Reg. +0.1/s · Rüstung +0.12“, zusätzlich „Fähigkeiten: <Name> +N Schaden“ für gelernte, skalierende Fähigkeiten (diese Zeile ist von keinem Test abgedeckt). Über dem Soft Cap sind die Werte automatisch halbiert. Neu: `StatBlock.preview_with_point` (Kopie, verändert nichts) und `AbilityEffects.power_for_stats`.
- Neuer Test `test_upgrade_preview_texts`. Er prüft, dass die Werte mit der echten Wirkung übereinstimmen und die Vorschau nichts verändert. 97 Tests bestanden.

## 2026-10-29 – Glutdrache in Blender gebaut

Wunsch des Spielers: einen Drachen in Blender „so gut wie möglich“ bauen. Die Vorlage war ein Konzeptbild, das der Spieler mitgebracht hat, und diente nur als Stilvorbild. Name, Form und Details sind eigene Entwürfe. Das Modell ist komplett per Skript gebaut: `tools/blender_build_dragon.py`, eigenes Skelett, keine Pack-Modelle.
- **Phasen** (jede mit `--stage <name> --preview <ordner>` einzeln prüfbar):
  1. Körper: Metaball-Ketten plus ein Kopf aus Querschnitten (Loft), per Voxel-Remesh zu einem geschlossenen Mesh vereint.
  2. Details: Unterkiefer, Zähne, Hörner, Rückenstacheln (per Raycast auf die Oberfläche gesetzt), Schwanzklinge, Krallen, leuchtende Augen.
  3. Flügel: Finger- und Armknochen, Flughaut als Gitter je Feld, mit eingebuchteter Hinterkante und Gewichten aus den Nachbarknochen.
  4. Skelett: 42 Knochen; der Rumpf ist automatisch gewichtet, wobei Flügel- und Kieferknochen ausgeschlossen sind; alle Teile sitzen starr am Knochen.
  5. Texturen: prozedurale Schuppen, Bauchplatten und Glut, gebacken zu Farbe (mit Umgebungsverdeckung), Normal-Map und Leuchten. Horn-Farbverläufe und Flughaut-Adern werden direkt per numpy gemalt.
  6. Animationen: Idle, Walk, Attack_Bite, Attack_Claw, Fire_Breath, Roar, Hit, Death, Fly.
  7. Export nach `assets/models/enemies_custom/EmberDrake.glb` (10,7 MB).
- **Godot-Prüfung:** Import geprüft: 42 Knochen, 9 Animationen, Materialien mit Textur, Normal-Map, Leuchten und doppelseitiger Flughaut. Bildschirmfotos im echten Rendering bestätigen Ausrichtung und Texturen. Der Drache schaut wie die KayKit-Modelle nach +Z; `CharacterVisual` dreht ihn wie alle Figuren.
- **Hinweis zum Import ohne Fenster:** Godot meldet dabei „Parameter "t" is null“ aus dem Ersatz-Renderer (`texture_storage.h`). Im echten Rendering sind die Texturen vorhanden.
- **Neues Werkzeug:** `tools/dragon_viewer.cmd` zeigt alle Animationen, mit Taste G für den Größenvergleich mit dem Guardian. Für Bildschirmfotos: `-- --shots=<ordner>`.
- **Noch nicht im Spiel:** Der Drache hat keinen Eintrag in `enemies.json` und kommt in keiner Welle vor. Ob er als Boss oder Mini-Boss mit Feuerodem kommt, entscheidet der Spieler.
- Der Körper hat ~56 000 Dreiecke, das ist viel für eine Figur. Falls die Bildrate leidet: `target_faces` in `stage_body` senken.
- 97 Tests bestanden (Spielcode unverändert).

## 2026-10-29 – Neuer Assassine (Shadow) mit realistischen Proportionen

Wunsch des Spielers: den Assassinen so bauen wie im Konzeptbild. Seine Entscheidung: realistische Proportionen, Ersatz für das Shadow-Modell, Guardian und Arcanist bleiben vorerst gedrungen. Bauplan: `tools/blender_build_assassin.py`; er nutzt den Baukasten aus `blender_build_dragon.py`.
- **Skelett:** Das KayKit-Rogue-Skelett wird nur in den Knochenabständen gestreckt (`OFFSET_SCALE`), alle Drehachsen bleiben. Ergebnis: Hüftgelenk 0,97, Knie 0,52, Schultern 1,60, Kopfgelenk 1,74, Gesamthöhe 1,94 (etwa 7,5 Köpfe).
- **Animationen:** Die 76 eingebauten KayKit-Animationen bleiben erhalten. Ihre Positionsschlüssel skaliert das Skript mit der Streckung (`scale_action_locations`), sonst schwebt der Körper etwa im Tod über dem Boden. Für die Zusatz-Bibliotheken rechnet `CharacterVisual._retarget_positions` die Positionsspuren zur Laufzeit um: Ziel = Ruhepose + (Wert − Quell-Ruhepose) × Längenverhältnis. Bei gleichem Skelett, also bei Guardian und Arcanist, ändert sich nichts. Der Bibliotheks-Zwischenspeicher gilt jetzt je Modell.
- **Körper und Ausrüstung:** Körper aus Metaballs, automatisch gewichtet. Rüstungsteile entstehen als abgehobene Schalen aus Hautbereichen; sie übernehmen die Gewichte 1:1, ihre Ränder sind geglättet, der Saum ist eine eigene Fläche.
  - Kopf: Kapuze mit Überwurf (aus Metaballs, Gesichtsöffnung ausgeschnitten), rote Maske, Sturmhaube mit glühenden Augen.
  - Rumpf: Brustpanzer, Schulterplatten in drei Lagen, Kreuzgurt, Schärpe, Gürtel.
  - Arme: Armschienen mit Stacheln.
  - Beine: Lendentücher vorn und hinten, Beinriemen als Ringe entlang der Beinkontur, Knieschützer, Stiefel.
  - Dolche: zwei gebogene Dolche in der Griffachse der alten KayKit-Messer.
- **Texturen:** Ein Mesh mit einem Material. Gebacken sind Farbe (Lederkorn, Stoffkörnung, Saumrille, Umgebungsverdeckung), Normal-Map, Rauheit/Metall (ORM) und Leuchten. Werkstoffnummern werden im Shader hart umgeschaltet, weil gemischte Nummern falsche Werkstoffe ergaben (leuchtende Kapuzenränder).
- **Einbau:** `assets/models/heroes_custom/Shadow.glb` (13,2 MB, ~76 000 Flächen) ist überschrieben; das alte Modell liegt im Git-Verlauf (Commit 0cc9b6b). In `heroes.json`: `model_scale` 0,9 → 1,05, `hidden_parts` leer.
- **Geprüft:**
  - Bildschirmfotos aus dem Modell-Viewer zeigen Stehen, Laufen, Tod und alle Fähigkeiten, darunter Sprunghieb und Doppelklingen-Angriffe aus der Zusatz-Bibliothek.
  - `verify_custom_models.gd`: ALLES OK. Die fehlende KayKit-Ausrüstung ist beim Shadow jetzt als `own_weapons` erlaubt.
  - 97 Tests bestanden.
- **Nicht geprüft:** Das Spiel selbst mit dem neuen Modell habe ich nicht gespielt. Die KayKit-Bewegungen sind für gedrungene Figuren gemacht und wirken auf langen Beinen breitbeinig.

## 2026-10-29 – Krieger und Magier im realistischen Stil, gemeinsamer Bauplan

Wunsch des Spielers: Krieger (Guardian) und Magier (Arcanist) wie den Assassinen nachziehen.
- **Gemeinsamer Bauplan:** `tools/blender_build_assassin.py` heißt jetzt `tools/blender_build_realistic_heroes.py` und baut alle drei Helden (`--hero shadow|guardian|arcanist`). Skelett, Körper, Schalen, Backen und Export teilen sie sich; die Ausrüstung ist je Held eigen (`outfit_<held>`). Je Held lassen sich Streckwerte (`offset`, Krieger: breitere Schultern) und Körperbau (`body`: torso/limbs) einstellen.
- **Werkstoffe:** jetzt 16 statt 9 – neu sind Gold, blauer Plattenstahl, blauer Stoff, Bart, blaues Augenleuchten, Kristall und Holz. Rauheit, Metall und Leuchtfarbe sind je Werkstoff festgelegt. Die Werkstoffnummern gelten je Fläche (`regions_per_face`), weil gemischte Nummern durch fremde Werkstoffe laufen: zwischen Haut und blauem Stoff leuchtete ein Punkt rot.
- **Krieger:**
  - Rüstung: blau-goldene Plattenrüstung, Brustpanzer, zwei Bauchreifen, Halsberge, Schulterplatten in drei Lagen.
  - Arme: Ober- und Unterarmschienen, Ellbogenkacheln, Stahlhandschuhe.
  - Beine: Beintaschen, Oberschenkelplatten, Kniekacheln, Beinschienen, Stahlschuhe.
  - Darüber: blauer Wappenrock mit Goldsaum, Umhang.
  - Kopf: Topfhelm mit T-Sehschlitz, Goldkamm und Goldrändern.
  - Waffen: Langschwert (Klinge 0,77 m) und Dreiecksschild mit eigenem achtstrahligem Sonnenstern.
- **Magier:**
  - Robe und Kopf: blaue Kapuzenrobe mit Goldsaum und hängendem Kapuzenzipfel, Glockenärmel (weiten sich zum Handgelenk), langer Robenrock mit Goldsaum und goldenem Mittelstreifen. Der Rock hängt zwischen den Beinen: Gewichte gemischt aus Becken, Ober- und Unterschenkeln.
  - Gesicht: weißer Bart mit Schnurrbart, buschige Brauen, kräftige Nase, blau glühende Augen.
  - Zubehör: goldener Gürtel mit Kordel, Ledertasche.
  - Stab: knorriger Holzstab mit Goldbändern und einer Gabel, die einen leuchtenden Kristall hält.
- **Waffen:** Eigene Waffen werden im Rahmen der Original-KayKit-Waffe gebaut (`weapon_frames`/`weapon_axes`, Maße mit Objekt-Skalierung). Der Schild richtet seine Oberseite nach der Stehanimation aus.
- **Behobener Fehler:** Der glTF-Import hängt eine Animation an das Skelett. Die Waffen wurden daher in einer Animationspose statt in der Ruhepose vermessen. Jetzt wird vor dem Vermessen die Ruhepose gesetzt. Deshalb liegen auch die Dolche des Assassinen jetzt wie die Original-Messer in der Hand; er ist neu exportiert.
- **Einbau:** `Guardian.glb` (13,1 MB, ~87 000 Flächen) und `Arcanist.glb` (13,2 MB, ~82 000 Flächen) sind überschrieben, die alten Modelle liegen im Git-Verlauf (Commit 0cc9b6b). In `heroes.json` gilt für alle drei `model_scale` 1,05 und `hidden_parts` ist leer. `verify_custom_models.gd` erlaubt bei allen drei eigene Waffen (`own_weapons`).
- **Geprüft:**
  - `verify_custom_models.gd`: ALLES OK (je 76 Animationen, alle 20 Fähigkeits-Animationen vorhanden).
  - 97 Tests bestanden.
  - Bildschirmfotos aus dem Modell-Viewer: alle drei nebeneinander, Stehen, Laufen, Tod und jede Fähigkeit.
- **Auffällig, aber gewollt:** Der Magier hält den Stab in der KayKit-Stehpose waagerecht nach vorn; so sind auch die Zauber-Animationen ausgelegt.
- **Nicht geprüft:** Im echten Spiel gespielt habe ich keinen der drei. Mit ~80 000 Flächen pro Held sind die Modelle schwer; bei Bedarf `target_faces` und die Schalen verringern.

## 2026-10-29 – Krieger: Angriff 3 sah aus wie ein Kopfstoß

Rückmeldung des Spielers: Beim dritten Standardangriff stößt der Krieger mit dem Kopf statt mit dem Schwert.
- **Ursache 1:** `1H_Melee_Attack_Slice_Horizontal` schwingt das Schwert zur Seite und hält es dort, während Oberkörper und Kopf nach vorn kippen. Mit den langen realistischen Proportionen liest sich das von oben als Kopfstoß. Die Phasenbilder schräg von oben haben das bestätigt.
- **Ursache 2:** Der Stahl war voll metallisch. In Godot spiegelt er nur den dunklen Hintergrund, die Klinge wirkte schwarz und war kaum zu sehen.
- **Änderungen:**
  - Angriff 3 ist jetzt `1H_Melee_Attack_Stab`; der Vorstoß liegt bei 0,35 s nach Tempoanpassung, genau beim Treffermoment.
  - Stahl ist heller und nur halb metallisch (Rauheit 0,3); die Schwertklinge ist breiter. Krieger und Assassine sind neu exportiert.
- **Behobener Fehler im Spielcode:** `CharacterVisual.animation_length()` und `play()` würfelten bei mehreren Varianten getrennt. Das Tempo konnte deshalb für eine andere Animation berechnet sein als die gespielte. Jetzt wird die gemessene Variante gespielt (`_next_pick`); das gilt für Helden und Gegner.
- 97 Tests bestanden, `verify_custom_models.gd`: ALLES OK. Im echten Spiel nicht gespielt.

## 2026-10-29 – Brunnen der Erholung (GitHub-Issue #2)

Wunsch aus Issue #2: ein Brunnen hinter der Basis, der Helden in der Nähe langsam Leben und Mana regeneriert. Dazu der Spieler: „im Radius vom Brunnen kann man sich nur bewegen aber nicht angreifen oder casten“. Der im Issue verlinkte Brunnen aus einem anderen Spiel diente nur als Mechanik-Vorbild; Name, Modell und Effekte sind eigen.
- **Spiellogik:** `scripts/gameplay/recovery_fountain.gd` (`RecoveryFountain`), angelegt von `MatchController` (`fountain`).
  - Lage, Radius und Raten: `data/balance/game.json` → `fountain` (Lage (0, 0, 11) hinter dem Kern, Radius 4 m, je 2,5 % Leben und Mana pro Sekunde).
  - Heilung ohne Quelle: Sie zählt wie die eigene Regeneration nicht als belohnbare Heilung.
  - Der Brunnen rechnet vor den Helden (`process_physics_priority = -10`), damit der Zustand schon im Bild des Betretens gilt.
- **Kein Kampf im Kreis:** neuer Zustand `StatusEffects.SANCTUARY`, laufend erneuert und beim Verlassen sofort entfernt. Er sperrt:
  - den Angriffsstart und das automatische Anvisieren (`Hero`), einen laufenden Schlag beim Auflösen,
  - Zauber (`AbilityCaster.check_cast`, wirkt auch für Zauber aus der Warteschlange),
  - die Treffer des Klingenwirbels (`IronMaelstrom._tick`).
- **Modell:** `tools/blender_build_fountain.py` → `assets/models/environment_custom/RecoveryFountain.glb`. Achteckiges Steinbecken, Säule mit oberer Schale; die Steintextur ist gebacken (Quader, Körnung, Umgebungsverdeckung). Wasser und Runenband leuchten; der Kristall ist das Objekt „Crystal“, das Spiel dreht ihn und lässt ihn schweben.
- **Effekte:** Runenkreis am Boden in Größe des Wirkkreises (dreht langsam), schwacher Schimmer der Fläche, aufsteigende Lichtfunken, pulsierendes blaues Licht, Funken an erholenden Helden. Dafür hat `VfxLayer` neue Helfer für dauerhafte Effekte: `make_particles`, `make_flat_material`, `make_curve`. Der Brunnen ist ein fester Körper (Helden laufen um das Becken).
- **HUD:** Deutsche Namen für die Zustände „sanctuary“, „whirl“, „channel“ und „untargetable“; die letzten drei wurden bisher roh angezeigt.
- **Tests:** neue Datei `tests/test_fountain.gd` mit 5 Tests:
  - Lage hinter dem Kern und abseits der Wege,
  - Regeneration nur im Kreis, nachgemessen gegen die Spielzeit,
  - kein Stapeln durch Rein und Raus,
  - kein Kampf im Kreis, aber sofort wieder kampfbereit draußen,
  - keine Heilung Gefallener.
  - Drei Tests in `test_abilities.gd` und einer in `test_bosses.gd` nutzten den ruhigen Platz hinter dem Kern (z = 12–14). Er liegt jetzt im Brunnen, deshalb sind diese Prüfplätze nach z = 20–26 verlegt.
- **Geprüft:**
  - 102 Tests bestanden.
  - Bildschirmfoto aus einer echten Runde: Brunnen, Runenkreis, abgelehnter Zauber mit Hinweis im HUD, steigende Leben- und Manawerte.
- **Nicht geprüft:** Die Raten sind nicht gegengespielt. Einen eigenen Klang hat der Brunnen nicht.

## 2026-10-29 – Brunnen weiter weg, Heilung deutlich schwächer

Rückmeldung des Spielers: Der Brunnen muss deutlich weiter weg, damit Spieler wirklich zwischen Heilen und Basisverteidigung abwägen müssen. Außerdem ist die Heilung zu stark.
- **Lage:** (0, 0, 11) → (0, 0, 25,5), also an den Südrand vor die Mauer, 25,5 m vom Kern. Bei 5,6–6,2 m/s Lauftempo sind das rund 4–4,5 s pro Weg. Der Test prüft jetzt mindestens 20 m Abstand zum Kern.
- **Raten:** Leben und Mana 2,5 % → 1 % pro Sekunde; eine volle Heilung dauert ~100 s, länger als jede Einkaufspause (30–50 s).
- Die vorher wegen des Brunnens verlegten Prüfplätze in `test_abilities.gd` und `test_bosses.gd` sind wieder an ihren ursprünglichen Stellen (z = 12–18), die jetzt frei sind.
- 102 Tests bestanden. Bildschirmfoto aus einer echten Runde zeigt den Brunnen am Südrand ohne Überschneidungen. Nicht gegengespielt.

## 2026-10-29 – Diener lassen sich nicht mehr risikofrei auskiten (GitHub-Issue #3)

Fehlerbericht #3: Ein Nahkämpfer kann einen Diener angreifen und sofort weglaufen, ohne dass der Diener seine Angriffsanimation ausführt.
- **Ursachen im Code (`scripts/enemies/enemy.gd`):**
  1. **Reichweiten ungleich:** Nahkampfhelden treffen aus größerer Entfernung als Diener. Guardian bis 2,65 m Mittenabstand, Knochenläufer erst ab 2,1 m; der Diener musste also erst herantreten.
  2. **Zusammenzucken:** Jeder spürbare Treffer ließ den Gegner 0,2 s erstarren, und in dieser Zeit griff er gar nicht an. Bei Dienern ist das praktisch jeder Heldenschlag.
  3. **Angriffspause:** Hatte der Diener gerade auf den Kern geschlagen, wartete er die volle Pause ab (bis 2 s), bevor er sich gegen den Helden wehrte.
- **Änderungen:**
  - `_attack_reach()`: Gegen Nahkampfhelden ist die Schlagweite mindestens die Reichweite des Helden + 0,1 m. Fernkampfgegner und Fernkampfhelden sind unverändert.
  - Zusammenzucken hält nur noch an; der Gegenschlag geht vor.
  - `RETALIATE_DELAY` (0,15 s) gilt beim Wechsel vom Kern auf einen Helden, nur dort; im Dauerkampf bleibt das Angriffsintervall.
- **Tests:** neue Datei `tests/test_kiting.gd` mit 5 Tests:
  - gegenseitige Reichweite ohne Herantreten,
  - Zuschlagen-und-Weglaufen kassiert den Gegenschlag,
  - Auskiten ohne Zuschlagen bleibt möglich,
  - Fernkampfhelden unverändert,
  - kein schnelleres Schlagen im Dauerkampf.
  - Gegen den alten Code schlagen die beiden Kerntests fehl (Diener trat 0,48 m heran; kein Gegenschlag); mit der Änderung bestehen sie.
- 107 Tests bestanden.
- **Nicht geprüft:**
  - Ob Treffermoment (`attack_hit_delay`) und Schlagbild der Gegner-Animationen genau zusammenfallen, habe ich nicht Bild für Bild nachgemessen.
  - Im echten Spiel nicht angespielt.

## 2026-10-29 – Zweite Karte „Zitadelle des Lichts“, Phase A (GitHub-Issue #4)

Wunsch des Spielers (Issue #4 mit Kartenskizze): eine große Hero-Defense-Karte. Entscheidungen des Spielers:
- **zusätzlich zur Arena**, im Menü wählbar;
- **erst Karte und Bauten** (Phase A); neutrale Lager, Dschungelboss, Kasernen mit eigenen Dienern und Heldenleiste folgen später;
- **Brunnen hinten in der Zitadelle**; die Schreine am Fluss geben stattdessen einen schwächeren einmaligen Schub mit langer Ladezeit.

- **Kartenwahl:**
  - Neue Basisklasse `GameMap` (`scripts/maps/game_map.gd`): Gegnerwege, Heldenstart, Kameragrenzen, Minimap-Ausschnitt, `bind_match`.
  - Die Arena erbt davon; `match.tscn` enthält keine feste Arena mehr. `MatchController` lädt die Karte aus `data/maps/maps.json` (`Session.map_id`). Kern- und Brunnenlage kommen je Karte von dort.
  - Die Kamera hat Grenzen je Karte (`CameraRig.bounds`).
  - Im Hauptmenü gibt es die Zeile „Wähle die Karte“.
- **Grundriss** `data/maps/citadel_layout.json`:
  - 132 × 76 m; im Westen der Abgrund mit drei Portalen (Abgrundriss, Düsterholz-Bau, Glutentor);
  - drei Lanes, ein Fluss mit drei Brücken;
  - die Zitadelle im Osten (Achteck, Radius 14 m) mit Kern, Brunnen und vier Start-Plattformen;
  - 3 Wachtürme, 2 Schreine, das Händlerhaus, Lagerplätze und der Krater für spätere Phasen.
- **Aufbau** `scripts/maps/citadel_map.gd`, alles aus dem Grundriss:
  - **Boden:** analytischer Shader (`assets/effects/citadel_ground.gdshader`): Wiese, gepflasterte Lanes, Flussufer, Vulkangestein mit Glutrissen, gefliester Platz, Erd-Lichtungen. Der einfache sin-Zufall erzeugte eckige Flecken und ist durch einen robusten Hash ersetzt.
  - **Fluss:** Wasserband mit Strömung (`citadel_water.gdshader`); Sperren nur außerhalb der Brücken.
  - **Mauerring:** aus KayKit-Mauerteilen mit eigenen Ecktürmen.
  - **Portale:** Wirbel-Shader (`citadel_portal.gdshader`).
  - **Natur:**
    - Klippenring am Rand, Wälder und Felsen (tote Bäume und Glutkristalle im Abgrund);
    - mit festem Zufall verteilt, als MultiMesh gezeichnet;
    - Lanes, Fluss, Bauten und Lager bleiben frei; Stämme und Felsen haben Kollision.
- **14 eigene Blender-Modelle** (`tools/blender_build_citadel_props.py` → `assets/models/environment_custom/`):
  - Brücke, Zitadellenturm, Torhaus mit Fallgitter, Wachturm, Portalbogen, Start-Plattform, Schrein, Händlerhaus;
  - Nadel-, Laub- und toter Baum, Fels, Klippe, Abgrund-Kristalle.
  - Steinteile tragen die gebackene Quadertextur aus dem Brunnen-Bauplan.
- **Bauwerke** (`scripts/maps/map_structure.gd`, Werte in `game.json` → `map_structures`):
  - **Wachtürme:** 1.800 Leben, Rüstung 4; schießen alle 1,1 s 34 magischen Schaden auf den nächsten Gegner im Umkreis von 9 m.
  - **Torhaus:** 3.500 Leben, Rüstung 6, schießt 20 Schaden pro Sekunde. Das Fallgitter liegt auf der Kollisionsebene 16, die nur Gegner aufhält (Gegnermaske 9 → 25); Helden gehen durch.
  - **Gegner als Angreifer:** Sie greifen ein Bauwerk an, wenn es in ihren Aggro-Radius kommt. Rangfolge: Held vor Bauwerk vor Kern; der Schaden ist `structure_damage`. Gemessen wird ab der Oberfläche, beim Torhaus ab der Mauerlinie (`surface_distance`).
  - **Gefallene Bauwerke:**
    - Ein Turm sackt in sich zusammen.
    - Beim Torhaus bricht das Fallgitter ein, und die Sperre ist weg.
    - Bauwerke bleiben für die Runde zerstört.
  - **Kein Gold für Turm-Abschüsse:** Gegner, die nur ein Turm getötet hat, geben kein Gold. Das ist die bestehende Beteiligungsregel.
- **Schreine** (`scripts/maps/map_shrine.gd`):
  - Ein verletzter Held oder einer mit fehlendem Mana bekommt beim Berühren einmalig +20 % Leben und +20 % Mana. Danach lädt der Schrein 90 s nach; der Kristall sinkt und wächst beim Laden wieder.
  - Ein voller Held verbraucht ihn nicht.
- **HUD:** Minimap oben rechts (`scripts/ui/minimap.gd`):
  - zeigt Grundriss, Bauwerke, Kern, Brunnen, Helden, Gegner und den Kameraausschnitt;
  - ein Klick schwenkt die Kamera dorthin (`CameraRig.jump_to`);
  - darüber die Spieluhr (mm:ss).
  - Die Minimap gibt es auch in der Arena.
- **Fehler unterwegs:**
  - Die ausgesparte Torseite des Mauerrings war die Südwestseite statt der Westseite (`k == 7` statt 0). Jetzt `GATE_FACE := 0`.
  - Ein Wegpunkt der mittleren Lane liegt genau auf dem Fluss, deshalb entstand die Brücke viermal. Der neue Test fand das; Doppelte werden jetzt verworfen.
- **Tests:** neue Datei `tests/test_citadel.gd` mit 7 Tests:
  - Kartendaten;
  - Aufbau in einer echten Runde;
  - Torhaus als Sperre (Gegenprobe: ohne Sperrebene läuft der Gegner bis x 42 durch, der Test schlägt dann fehl);
  - Wachtürme schießen nur in Reichweite und werden angegriffen;
  - Schrein-Schub und Ladezeit;
  - Hindernisse nicht auf Lanes, und Gegner aller drei Lanes queren den Fluss;
  - Minimap und Spieluhr.
- **Geprüft:**
  - 114 Tests bestanden.
  - Bildschirmfotos aus echten Runden: Übersicht, Nahansicht, Spielkamera mit Minimap, Kampf an Turm und Tor, Arena mit Minimap.
- **Nicht geprüft:**
  - nicht angespielt, Wellen- und Bauwerkswerte nicht gegengespielt;
  - Bildrate auf der großen Karte nicht gemessen.
  - Die Laufwege sind hier ~110 m lang (Arena ~30 m); ob die Wellenabstände dazu passen, ist offen.

## 2026-10-30 – Zitadelle des Lichts nach dem Konzeptbild neu aufgebaut (Issue #4)

Wunsch des Spielers: „Mach die Map genauso wie in der Abbildung, die ich dir geschickt habe“ (Konzeptbild aus Issue #4). Das Bild liegt nicht im Repository; im Issue steht nur ein toter relativer Link. Ich habe es aus dem Gesprächsverlauf entnommen.
- **Grundriss in Bildpixeln:**
  - `data/maps/citadel_layout.json` speichert alle Punkte als Pixel des Bildes (1408 × 768). `CitadelMap.to_world` rechnet mit `px_origin` (760, 397) und `px_scale` 0,11 m/px um.
  - Abgelesen an 2×-Vergrößerungen dreier Bildausschnitte: Portale, Lanes, Ringstraße, Fluss, Brücken, Zitadelle (Sechseck), Torhaus mit zwei Tortürmen, Heldenpunkte vor der Zitadelle, vier Türme, zwei Kasernen, Händlerposten, drei Schreine, Mauern, Ruinen, Lager, Krater, Berge, Abgrund-Felsen.
- **Mittlere Lane mit zwei Bögen:**
  - Sie teilt sich vor dem Krater in einen Nord- und einen Südbogen (`"RING"` im Grundriss).
  - Neu: `GameMap.get_path_variants()`; `EnemySpawner.path_variants` wechselt die Varianten je Gegner ab.
- **Waldverteilung aus dem Bild gemessen** (`data/maps/citadel_forest.json`):
  - Farbklassifikation in 8×8-px-Zellen (dunkel, grünlich, unruhig = Wald; sehr dunkel = dichter Wald), mit Mehrheitsfilter.
  - Minimap, Titel und Seitenleisten des Bildes sind ausgeblendet.
  - Kontrolliert über ein Overlay auf dem Bild.
  - Die Streuung nutzt das Raster als Dichte; der Boden-Shader dunkelt den Waldboden danach ab.
- **Schwebende Insel:**
  - Der Boden ist ein Vieleck (Plateau-Umriss), darunter eine eingezogene Felswand (`citadel_cliff.gdshader`).
  - Im Osten Himmel mit Wolkenfeldern (`citadel_cloud.gdshader`).
  - Die begehbare Grenze folgt einem eigenen Vieleck.
- **Boden-Shader neu:**
  - Straßen und Pfade als Strecken mit Breite und Art (Pflaster mit Steinkante / Erdpfad);
  - Krater, Lavabecken, sechseckiger Hof;
  - Waldraster als Textur.
  - Die Farben habe ich aus den sRGB-Werten des Bildes in lineare Werte umgerechnet. Vorher wirkten Straßen und Hof fast weiß.
  - Nebel ausprobiert und wieder entfernt: Er machte die Draufsicht milchig.
- **Neue oder geänderte Blender-Modelle** (`tools/blender_build_citadel_props.py`, jetzt 21):
  - neu: Kaserne, Ruinen, Berg, Basaltnadeln, violette Kristalle, Steinmauer, Zitadellenmauer;
  - geändert: Torhaus (zwei quadratische Tortürme), Turm (Glut statt blauer Kristall, wie die orange leuchtenden Türme im Bild), Heldenpunkt (blaue Scheibe mit Schwert), dunkleres Laub.
  - Turmgeschosse sind jetzt orange (`game.json`).
- **Mechanik angepasst:**
  - 4 Türme und das Torhaus;
  - 3 Schreine;
  - Kasernen mit Kollision (Diener folgen später);
  - Mauern mit Kollision;
  - Heldenstart an den ersten vier Heldenpunkten vor dem Tor.
  - Der Brunnen steht hinten im Hof mit eigenem Wirkkreis 3,2 m (`maps.json` → `fountain_radius`, neu in `GameData` und `MatchController`).
- **Minimap:** zeigt Himmel und Plateau, Abgrund, Fluss, alle Straßen samt Ring, Pfade, Mauern, Krater und das Sechseck.
- **Fehler unterwegs:**
  - Ein Mauerstummel lag nach meinen ersten Koordinaten direkt auf der unteren Lane, und die obere Ostmauer ließ nur wenige Zentimeter Platz. Beides habe ich am Bildausschnitt korrigiert.
  - Der untere Turm stand genau im Aggro-Radius der Läufer (3,0 m) und ist 0,4 m nach Süden gerückt.
  - Mein erster Perl-Ersatz für das Torhaus löschte die alte Funktion, ohne die neue einzusetzen (leere Variable). Ich habe die neue Fassung danach eingesetzt.
- **Tests** (`tests/test_citadel.gd`, 7 Tests, umgeschrieben):
  - Grundriss in Bildpixeln (Lanes vom Portal bis in die Zitadelle, Kern deckungsgleich mit `maps.json`, Brunnen hinten im Hof, Anzahl der Bauten wie im Bild, Waldraster deckt das Bild ab);
  - Aufbau in der Runde (5 Bauwerke, 3 Schreine, 3 Brücken, Heldenpunkte vor dem Tor, Nord- und Südbogen, zwei Gegner der Mitte nehmen verschiedene Bögen);
  - Torsperre (Gegenprobe ohne Sperrebene: der Gegner läuft bis x 44,6 durch, der Test schlägt fehl);
  - Türme, Schreine;
  - kein Hindernis auf Straßen oder Ring;
  - Läufer aller Wege queren den Fluss (Mitte über beide Bögen);
  - Minimap.
- **Geprüft:**
  - 114 Tests bestanden.
  - Draufsicht deckungsgleich zum Konzeptbild gerendert und untereinander verglichen; dazu Nahansichten von Zitadelle, Krater und Abgrund und die Spielkamera mit Minimap.
- **Nicht geprüft:**
  - nicht angespielt, Bildrate auf der Karte mit mehreren hundert Bäumen nicht gemessen;
  - Stil: Die Karte ist Low-Poly, das Bild gemalt. Grundriss, Farben und Bauten folgen dem Bild, die Malerei selbst nicht.

## 2026-10-30 – Abgrund-Hexer aus Tripo-Modell (noch nicht im Spiel)

Der Spieler hat eine Figur aus Tripo erzeugt (`daemon_hexer.glb`, nach eigenem Entwurf, ohne Vorlage aus fremden Spielen) und wollte sie im Spiel haben. Vorgänger-Entwurf mit grünem Teufelsfeuer wurde verworfen (zu nah an Warcraft).
- **Tripo-Modell geprüft:** 10.660 Dreiecke, Textur 2k, kein Skelett; die Texturnähte machten aus einem Netz 1.872 Teile (verschweißt: 29, davon 9 sinnvolle). Das Modell hält einen Stab in der Hand.
- **Umbau** (`tools/blender_build_hexer.py`, 5 Phasen: mesh, skeleton, weights, staff, export):
  - **mesh:** Nähte verschweißen, Stab, Krone und Splitter abtrennen, auf 2,1 m skalieren und spiegeln (die Stab-Hand wird die rechte, dort sitzt der Handslot), Mitte aus Beinen und Hufen.
  - **skeleton:** KayKit-Skelett (Rig_Medium aus `Mage.glb`) auf die Gelenke des Modells gesetzt; Gelenke an Rasterbildern abgelesen und automatisch zur Mitte der Glieder gezogen.
  - **weights:**
    - Die Gewichte werden in der Haltung des Modells berechnet (Arme hängen bzw. sind gebeugt) mit einem Hilfsskelett.
    - Dann kommen die Arme in T-Pose (wie die KayKit-Ruhepose) und das Netz an das Spielskelett.
    - 467 lose Punkte ohne Wärmegewicht gingen an den nächsten Knochen.
    - Die Hüftspuren der Animationen sind mit der Hüfthöhe skaliert.
  - **staff:** Der Stab hängt als eigenes Netz an `handslot.r`, die Faust ist um 90° gedreht, damit der Stab wie bei KayKit in der Ruhepose nach vorn zeigt. Der Stab neigt sich nach der Drehung 23,6° gegen die Faustachse; das fällt nur auf, wenn man sehr nah hinsieht.
  - **Eigene Animationen:** `Hexer_Idle` (Stab aufgesetzt, 2 s) und `Staff_Slam` (1,5 s: Stab hochreißen, auf den Boden stoßen, Rückfedern; der Schlag liegt bei Bild 27 von 45, also bei 60 % der Länge, so wie `_update_ability` es für Bodenschläge erwartet). Gebaut über Zielpunkte, Rumpfneigung, Zwei-Knochen-IK für Beine und rechten Arm.
  - **export:** `assets/models/enemies_custom/AbyssHexer.glb`, 4,9 MB, 78 Animationen (76 KayKit + 2 eigene), Tripo-Textur als JPEG.
- **Viewer:** `tools/hexer_viewer.cmd` (Doppelklick): ←/→ Animation, Maus drehen, Mausrad Zoom, Leertaste Pause.
- **Geprüft:** In Blender Idle, Gehen, Laufen, Zauber, Tod und alle Schlüsselbilder des Staffschlags; in Godot Standbilder im Viewer (Idle, Staffschlag, Zauber). Keine Tests, nicht im Spiel.
- **Nicht geprüft:** Tod und Treffer-Animation im Viewer nicht angesehen. Die Verformung an Achseln und Rüstung in schnellen Bewegungen ist nur an Standbildern beurteilt. Staffschlag nicht mit Schockwelle im Spiel.
- **Offen:** Gegner-Eintrag (`enemies.json`), Rolle in den Wellen und eine Schockwelle zum Staffschlag. Warten auf die Entscheidung des Spielers.

## 2026-10-30 – Abgrund-Hexer im Spiel

Wunsch des Spielers: den Hexer im Spiel sehen.
- **Gegner `abyss_hexer`** (`data/enemies/enemies.json`): Elite, 650 LP, Rüstung 12, Magieresistenz 25, Fernkampf (6 m, violette Geschosse), Fähigkeit „Bodenschlag“ mit der Animation `Staff_Slam`. Er steht in **Welle 7** (Pfad 1, 12 s nach Wellenstart). Werte sind Schätzwerte.
- **Fehler gefunden und behoben** (`scripts/enemies/enemy.gd`): Ein Treffer ließ den Gegner mitten in der Ankündigung eines Bodenschlags „zucken“ und überschrieb die Animation, im Spiel sah man den Staffschlag deshalb nicht. Jetzt zuckt ein Gegner während der Ankündigung nicht; das gilt auch für Grabritter und Knochenkoloss.
- **Showcase** `tools/hexer_showcase.cmd`: startet eine echte Runde, in der sofort ein Hexer erscheint (auch `-- --map=citadel`, `-- --hero=arcanist`). Mit `-- --shots=<ordner>` macht er Bilder.
- **Geprüft:**
  - 114 Tests bestanden;
  - in der echten Runde Bilder von Zaubern, Warnkreis, hochgerissenem Stab, Aufprall mit Schockwelle und Schaden am Helden (52).
- **Nicht geprüft:**
  - Treffer- und Tod-Animation des Hexers im Spiel;
  - Wellen- und Gegnerwerte nicht gegengespielt;
  - Hexer auf der Zitadellenkarte nicht angesehen;
  - Bildrate mit mehreren Hexern nicht gemessen.

## 2026-10-30 – Live-Verbindung zu Blender (Blender Lab MCP)

Wunsch des Spielers: Claude direkt mit einem offenen Blender verbinden.
- **Erweiterung:** die offizielle „MCP“ von Blender Lab (Version 1.0.3, aus *Get Extensions*). Sie öffnet auf `localhost:9876` einen Socket; Anfragen sind JSON mit einem Nullbyte am Ende: `{"type": "execute", "code": "...", "strict_json": false}`. Online-Zugriff muss in *Preferences → System → Network* an sein, sonst startet sie nicht. „Auto Start“ startet den Server nach 1 s.
- **Anbindung:** `tools/blender_live.js` (Node): `node tools/blender_live.js "<Python-Code>"` führt Code im offenen Blender aus und gibt `print`-Ausgaben zurück. Ein MCP-Server ist dafür nicht nötig.
- **Erster Versuch (verworfen):** `mcp-for-blender` (Drittanbieter) mit Add-on `mcp_for_blender.py` in `scripts/addons`. Es lief als zweiter Server auf demselben Port (Windows erlaubt das wegen `SO_REUSEADDR`) und fing meine Verbindungen ab, ohne zu antworten. Add-on gelöscht, Claude-Eintrag `blender` entfernt.
- **Geprüft:** Befehl ausgeführt (Blender 5.2.3 antwortet), Objekt angelegt und wieder gelöscht, Bild aus dem offenen Blender gerendert und angesehen.
- **Nicht geprüft:** Ob das Modellieren damit leichter fällt (erst beim ersten echten Modell). Die Erweiterung führt beliebigen Python-Code aus: nur mit geöffnetem Blender nutzen.

## 2026-10-30 – Frostdrache aus Tripo (erstes Modell über Live-Blender)

Wunsch des Spielers: das Tripo-Modell `blue dragon.glb` einbauen und animieren.
- **Skript** `tools/blender_build_frostdrake.py`: Phasen mesh, skeleton, weights, export (`--stage`, `--preview <ordner>`, `--src`, `--out`). Läuft headless und live im offenen Blender (eigene Szene „Frostdrache“, die Szene des Spielers bleibt unberührt).
  - **mesh:** Nähte verschweißen (0,0015), auf 3,0 skaliert, Front bleibt -Y.
  - **skeleton:** Hilfsskelett an den Gelenken des Modells (Tabellen `BODY`, `TAIL`, `SIDE`, gespiegelt).
  - **weights:** Gewichte in der Haltung des Modells, dann jedes Glied in die Ruhehaltung des Glutdrachen gedreht und als neue Ruhe übernommen. Das fertige Skelett hat die Knochenausrichtung des Glutdrachen mit den Längen des Hilfsskeletts; Positionsspuren werden umskaliert. 41 Gewichtsgruppen, 18 Punkte ohne Gewicht nachgefüllt.
  - **export:** `assets/models/enemies_custom/FrostDrake.glb`, 2,5 MB, 9 Animationen des Glutdrachen, Textur als JPEG.
- **Viewer:** `tools/dragon_viewer.gd` kann mit `-- --frost` den Frostdrachen zeigen; `tools/frost_viewer.cmd` startet ihn per Doppelklick.
- **Geprüft:** In Blender Skelett und Posen (Idle, Walk, Biss, Feuerodem, Brüllen, Fliegen, Tod); in Godot Viewer-Bilder derselben Posen und von der Seite, mit Guardian zum Größenvergleich. Keine Tests.
- **Nicht geprüft:** Prankenhieb und Treffer, Animationen in Bewegung, Flügelhaut und Schultern aus der Nähe. Nicht im Spiel (kein Gegner-Eintrag, keine Welle). Tripo-Lizenz nicht geprüft.

## 2026-10-30 – Eisdrache als Boss (Issue #9)

Vorgabe: Issue #9 (Eisdrache: Hybrid, Eis-Immunität, Feuer- und Giftschwäche, Unterkühlung, Eisfeuer-Odem, Schneesturm, Arktischer Schrei). Das Modell war schon fertig (Frostdrache).
- **Elemente:** `DamageInfo.element`, `CombatService.deal_damage(..., element)`; `Enemy.element_multiplier()` aus `data.elements`. Fireball = Feuer, Frost Nova und Gletscherspalt = Eis (bei Immunität auch keine Verlangsamung, Betäubung oder Anheben), Giftstapel = Gift.
- **Neue Zustände:** `chill` (Angriffstempo-Malus, wirkt in `Hero.current_attack_interval`) und `frostbite` (Stapel bis zum Einfrieren).
- **Gegner:** Hybrid über `data.melee` (Nahkampf, wenn ein Held am Körper steht), `data.on_hit` (Unterkühlung), `body_radius`, `bar_height`, `projectile.forward`. `ARMOR_BONUS` erhöht jetzt Rüstung und Magieresistenz von Gegnern.
- **BossBrain:** Fähigkeiten nur, wenn sie in den Daten stehen; neu `frost_breath` (Kegel mit Bodenwarnung), `blizzard` (Sturmzonen mit Takt), `frost_roar` (Helden bremsen, Gegner panzern); `color` und `phase_anim` je Boss.
- **Effekte:** `VfxLayer.cone_indicator`, `frost_breath`, `blizzard`.
- **Daten:** `ice_drake` (Mini-Boss mit drei Phasen), Welle 8 heißt jetzt „Der Eisdrache“ (ersetzt einen Grabritter). Alle Werte Schätzwerte.
- **Showcase:** `tools/hexer_showcase.gd` nimmt `-- --enemy=<id>`; `tools/ice_drake_showcase.cmd`. Bildzeiten zählen jetzt Spielsekunden statt Uhrzeit (Speichern eines Bildes hielt das Spiel an, Bilder kamen zu früh).
- **Geprüft:**
  - 121 Tests bestanden, davon 7 neue in `tests/test_ice_drake.gd` (Daten, Elemente und Frost Nova, Unterkühlung, Wechsel Fern-/Nahkampf, Odem nur im Kegel, Schneesturm friert ein, Schrei panzert Gegner und bremst Helden);
  - in einer echten Runde Bilder von Eisgeschossen, Odem-Warnung und -Strahl, Schrei, Schneesturm und Einfrieren.
- **Nicht geprüft:**
  - Werte nicht gegengespielt (Welle 8 kann zu schwer sein);
  - Zitadellenkarte nicht angesehen;
  - die Hexer-Bildzeiten des Showcase sind nach der Umstellung auf Spielsekunden nicht neu geprüft;
  - Mehrspieler nicht geprüft.

## 2026-10-30 – Eisangriff in acht Schritten (Eisdrache und Glacial Rift)

Vorgabe des Spielers: acht Schritte für den Eisangriff (Aufladen, Stacheln aus dem Maul, Wachsen zum Ziel, seitliches Auffächern, Boden reißt mit Brocken, großer Abschluss mit Blitz und Kamerastoß, Schmelzen und Zersplittern, Frost in der Luft); dasselbe für den Magier, „nur statt aus dem Mund aus dem Boden“.
- **VfxLayer:** `ice_charge`, `ice_spike_path`, `_spike`, `_icicle`, `ice_impact`, `frost_linger`, `_ground_cracks` (prozedurale leuchtende Risse). `frost_breath` und `ice_eruption` entfernt (ersetzt).
- **Eisdrache:** Aufladen im Maul während der 1-s-Warnung; Zapfen fliegen aus dem Maul, der Einschlag sitzt dort, wo der Held bei der Ankündigung stand. Schaden kommt jetzt, wenn die Stacheln den Helden erreichen (vorher sofort).
- **Glacial Rift (Arcanist):** 0,3 s Aufladen an der Hand, erst dann läuft die Stachelfront (Spielwirkung: Treffer 0,3 s später). Getroffene bekommen Risse und Brocken (höchstens 6), am Ende der Bahn der große Abschluss.
- **Behoben:** Das Aufladeglühen wuchs nicht, weil Billboard-Materialien ohne `billboard_keep_scale` die Skalierung ignorieren.
- **Werkzeug:** `tools/skill_showcase.gd` kann jetzt Bilder machen (`--shots`, `--times`, `--level`).
- **Geprüft:**
  - 121 Tests bestanden (Glacial-Rift- und Odem-Test an das neue Timing angepasst, prüfen jetzt auch „noch kein Treffer“ davor);
  - Bildfolgen beider Angriffe im Spiel angesehen: alle acht Schritte sichtbar.
- **Nicht geprüft:** Bildrate bei vielen gleichzeitigen Eisangriffen; Glacial Rift auf Stufe 1 und 2 nicht angesehen; der große Abschluss des Rifts lag in der Showcase-Kamera am Bildrand.

## 2026-10-30 – Feuerdrache als Boss (Issue #8)

Wünsche des Spielers: Feuerdrache aus Issue #8; Design „in ein schimmerndes Rot“, dafür den Eisdrachen nehmen und umbauen. Ich habe vorgeschlagen: Farbe plus Effekte im Spiel, Form unverändert; der Spieler hat zugestimmt („ok dann mach weiter“).
- **Modell:** `tools/blender_recolor_drake.py` färbt `FrostDrake.glb` zu `FireDrake.glb` um (dunkelrote Schuppen, orange-goldene Zacken mit Leuchttextur, leichter Glanz). Drei Durchgänge nach Bildern: erst bräunlich mit weiß ausgebranntem Leuchten, dann zu orange, jetzt dunkelrot mit glühenden Zacken.
- **Neue Animation `Tail_Swipe`** (1,5 s): Kopie von Idle, Rumpf dreht in den Schlag, der Schwanz peitscht mit Verzögerung herum, Kopf dreht gegen.
- **Schimmern im Spiel:** `CharacterVisual.pulse_glow` (Leuchten pulsiert, Daten `glow_pulse`), aufsteigende Glutfunken (`aura_fx: "embers"`).
- **Kampf:** neue Zustände `burn` (Schaden über Zeit, jetzt auch an Helden; `dot_handler` bekommt das Element), `armor_shred` (Rüstung und MR der Helden runter), `empower` (Gegner mehr Schaden). Geschosse mit `splash` und `element`. BossBrain: `fireball`, `meteor_shower`, Gebrüll als ein Ablauf für `frost_roar` und `fire_roar`. `charge_up` (früher `ice_charge`) mit Farbe, `fire_bolt`, Brennen als Zustandseffekt am Helden.
- **Daten:** `fire_drake` (Mini-Boss mit drei Phasen) in Welle 9 statt des Knochenkolosses. Alle Werte Schätzwerte.
- **Werkzeuge:** Drachen-Viewer mit `--model=`, zeigt nur vorhandene Animationen, Bilder von oben; `tools/fire_drake_showcase.cmd`.
- **Geprüft:**
  - 127 Tests bestanden, davon 6 neue in `tests/test_fire_drake.gd` (Daten und Animationen, Elemente, Feuerpest und Flächenschaden, schwerer Feuerball, Meteorschauer, Drachengebrüll);
  - Viewer-Bilder (Farbe, Schwanzschlag von oben) und eine Bildfolge aus einer echten Runde: Feuerbälle mit Brand, Aufladen, Warnkreis, Flug, Explosion, Gebrüll, Meteorschauer.
- **Nicht geprüft:**
  - Werte nicht gegengespielt (Welle 9 mit Feuerdrache statt Koloss);
  - das Pulsieren und die Glutfunken nur auf Standbildern;
  - beim Meteorschauer hebt der Drache mit der Flug-Animation ab und landet abrupt – wirkt auf einem Bild unruhig;
  - Zitadellenkarte und Mehrspieler nicht geprüft.

## 2026-10-30 – Testmodus (Issue #11)

Vorgabe: Issue #11 (Testmodus mit frei wählbarem Level und maximalem Gold, optional unbegrenzt, unabhängig vom normalen Spiel).
- **Menü:** neue Zeile unter „Einzelspiel starten“: Stufe (SpinBox bis Höchststufe 20), „Gold unbegrenzt“, „Testmodus starten“.
- **Session:** `test_mode`, `test_level`, `test_unlimited_gold`, `start_test()`; `start_singleplayer()` schaltet den Testmodus ab. Im Testmodus ist die Telemetrie aus (es gibt keinen anderen gespeicherten Spielstand).
- **Runde:** Startgold aus `game.json` → `test_mode.gold` (999.999); `_apply_test_level` hebt den Helden über XP auf die Stufe, füllt Leben und Mana; `GoldService.unlimited` bucht Käufe, ohne abzuziehen. HUD-Hinweis „TESTMODUS“ oben links.
- **Behoben:** Glacial Rift löschte sich, bevor das Hochschleudern der Getroffenen endete (seit dem Aufladen sichtbar als Tween-Fehler im Test). Jetzt wird es erst danach entfernt.
- **Werkzeug:** `tools/ui_shot.gd` macht Bilder beliebiger Szenen (Menü, HUD), auch im Testmodus.
- **Geprüft:** 131 Tests bestanden, davon 4 neue in `tests/test_test_mode.gd` (Stufe und Gold, Höchststufe mit unbegrenztem Gold, begrenztes Gold, normales Spiel unverändert); Bilder von Menü und HUD im Testmodus.
- **Nachbesserung nach Rückmeldung des Spielers** („der Testmodus scheint nicht richtig zu funktionieren“):
  - Team-Verbesserungen (Kern) waren nicht kaufbar, weil das Team-Gold bei 0 lag. Jetzt bekommt auch das Team 999.999 Gold.
  - Eine eingetippte Stufe zählt jetzt auch ohne Enter.
  - Neuer Test `test_everything_buyable` (Fähigkeit bis Stufe 3, Ultimate, Attribut, Gegenstand, Team-Verbesserung); `tools/ui_shot.gd` kann im Menü tippen und Knöpfe drücken (`--type`, `--press`). Über den echten Menüknopf geprüft: Stufe 10 eingetippt, Runde startet auf Stufe 10 mit 999.999 Gold und 999.999 Team-Gold.
- **Startwelle** (Klarstellung des Spieler: „ich komme nicht in den Level, was ich auswähle, also Welle“): zweites Zahlenfeld „Welle“ im Menü; `WaveManager.start(first_index)`, `Session.test_wave`; HUD zeigt „ab Welle X“. Test `test_start_wave`; über den echten Menüknopf geprüft: Stufe 15, Welle 8 → Runde beginnt mit „Welle 8/10 · Der Eisdrache“. 133 Tests bestanden.
- **Nicht geprüft:** Fähigkeiten im Testmodus von Hand im Shop-Fenster gekauft und gewirkt; Testmodus auf der Zitadelle; Belohnungen für übersprungene Wellen gibt es keine (Absicht, nicht gegengespielt).

## 2026-10-30 – Attribut-Skalierung der Fähigkeiten verbessert

Rückmeldung des Spielers: „Das Scaling der Skills ist miserabel mit den Attributen.“ Nachgerechnet: 20 gekaufte Punkte kosteten 11.541 Gold und brachten nur +14–16 % Fähigkeitsschaden; bei Guardian und Shadow kam die Fähigkeitsstärke nur aus Intelligenz.
- **Neu:** jeder Kauf +2 Punkte, Kosten `100 · 1.08^n` (20 Käufe 4.578 Gold), Soft Cap ab 30 Käufen; Fähigkeitsstärke aus dem Hauptattribut (1 % je Punkt) für alle Helden. Ergebnis Stufe 20 mit 20 Käufen: +33–37 % (Tabelle in BALANCING.md).
- **Erst verworfen:** Hauptattribut *zusätzlich* zu Intelligenz – dann hätte der Guardian 208 % Fähigkeitsstärke gehabt, mehr als der Arcanist (186 %).
- Anzeige: „+2 · Preis“ im Charakterfenster und Shop, Vorschau „+2 bringt …“, Meldung „Stärke +2 für … Gold“.
- **Geprüft:** 134 Tests bestanden; neue Prüfung `test_skills_scale_with_bought_main_attribute` (alle drei Helden ≥ +25 % bei 20 Käufen); Tests mit festen alten Preisen lesen jetzt die Regeln. Bild des Charakterfensters im Testmodus.
- **Nicht geprüft:** nicht gegengespielt; Guardian und Shadow sind auch ohne Käufe stärker (+15–18 % Fähigkeitsschaden auf Stufe 20); Belohnungs-Kalibrierung (Rollen-Gold) lief grün, aber nur in der Simulation.

## 2026-10-30 – Tripo-Figuren als Helden-Modelle (Zauberer, Assassine)

Wunsch des Spielers: „übernimm die restlichen Charakter-Modelle ins Spiel“ (Ordner `Downloads/character`).
- **Geprüft vor der Übernahme:** Vorlagen Zauberer, Assassine, Krieger sind eigene Entwürfe (Stil wie bekannte Spiele, keine fremden Figuren oder Namen). Mit Modell: nur `Zauberer.glb` und `assassin character 3d model.glb`. Krieger und dreiköpfiger Höllenhund sind nur Bilder. `demon_schamane.glb` bleibt draußen (Warcraft-Vorlage), `daemon_hexer.glb` ist schon der Abgrund-Hexer, `Dragon.glb` war der erste Drachenversuch (durch den Frostdrachen ersetzt).
- **Skript** `tools/blender_build_tripo_hero.py`: allgemeine Fassung des Hexer-Ablaufs mit Konfiguration je Figur. Zauberer: Stab über seine Achse erkannt (die umgreifende Hand bleibt am Körper), Rumpf um 21 cm zur Mitte gerückt (der weite Umhang verschob die Mitte). Assassine: Klingen (448 Punkte) ganz an die Hände gehängt, sonst ziehen die Oberschenkel sie mit.
- **Ergebnis:** `ArcanistTripo.glb` (4,8 MB) und `ShadowTripo.glb` (4,7 MB) mit allen 76 KayKit-Animationen; `heroes.json`, Modell-Viewer und Fähigkeiten-Showcase zeigen sie. Die alten Blender-Modelle bleiben als Dateien liegen; der Guardian bleibt, bis es ein Krieger-Modell gibt.
- **Geprüft:** 134 Tests bestanden; Skelett- und Posenbilder (Stehen, Laufen, Zaubern, Doppelklingen-Hieb, Tod) in Blender; im Spiel Fireball und Fan of Knives mit Guardian zum Größenvergleich.
- **Nicht geprüft:** alle übrigen Fähigkeiten und Animationen; der lange Stab liegt im Stehen und Zaubern waagerecht (wie beim KayKit-Original mit kurzem Stab, wirkt aber ungewohnt); der Umhang des Zauberers beim Laufen nur auf einem Standbild; Bildrate.
- **Nachtrag Krieger** (Spieler: „hier ist der Krieger jetzt drinnen“, `fantasy knight 3d model.glb`): Eintrag `krieger` mit Waffe `held` – Schwert und Schild über Bereiche ganz an die jeweilige Hand (Schild-Bereich zuerst zu groß: er erfasste Kniepanzer, die als Splitter mitflogen; enger gefasst 188 → 90 Punkte). `GuardianTripo.glb` (4,8 MB) ist jetzt das Modell des Guardian. Geprüft: Posenbilder und im Spiel Shield Bash und Iron Maelstrom; 134 Tests bestanden. **Grenze des Modells:** Unter dem Wappenrock fehlt ein vollständiger Oberschenkel; hebt der Krieger beim Laufen das Knie, sieht man kurz in die offene Beinschiene.

## 2026-10-30 – Endboss Morvath im neuen Stil

Wunsch des Spielers: „tausche den Level-10-Hexer-Boss mit dem neuen Stil aus“.
- **Modell:** `MorvathHexer.glb` = Abgrund-Hexer (Tripo) mit grünem statt violettem Leuchten (`tools/blender_recolor_drake.py --shift 0.68 0.92 0.33`: nur gesättigte Violett-Töne gedreht, Knochen und Rüstung unverändert). `model_scale` 1,45 (~3 m), damit er sich vom Hexer-Elite in Welle 7 abhebt. Grün passt zu Seelenfeuer und Beschwörungskreisen.
- **Animationen:** Dem Hexer fehlen Taunt, Spellcast_Summon und die Skelett-Varianten. Beschwörung, Phasenwechsel und Auftritt jetzt mit `Staff_Slam` (neu: `boss.summon.anim`, `boss.phase_anim`), Stehen `Hexer_Idle`, Laufen `Walking_A`, Tod `Death_A`, Jubel `Spellcast_Long`. Der Boss-Test prüft jetzt alle Animationen, die die Daten nennen.
- **Showcase:** `--enemy=morvath` mit eigenen Bildzeiten; Phase 2 wird für das Seelenfeuer erzwungen.
- **Geprüft:** 134 Tests bestanden; Bildfolge aus einer echten Runde (Auftritt mit Stabstoß, Beschwörungskreise, Skelette, Seelenfeuer).
- **Nicht geprüft:** Phase 3 (Todeswelle, Raserei) und der Tod im Spiel nicht angesehen; das alte Modell `Morvath.glb` bleibt als Datei liegen.
