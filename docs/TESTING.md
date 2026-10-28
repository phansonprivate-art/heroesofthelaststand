# Tests

## Ausführen

```bash
bash tools/run_tests.sh
```

Das Skript importiert das Projekt, startet `tests/run_tests.gd` headless mit `--fixed-fps 60` (die Simulation läuft so schnell wie möglich, ein Physik-Schritt pro Frame) und schlägt fehl, wenn

- ein Test fehlschlägt **oder**
- irgendwo `SCRIPT ERROR` bzw. `Parse Error` ausgegeben wird.

Der zweite Punkt ist wichtig: Godot bricht eine Testfunktion bei einem Laufzeitfehler still ab. Ohne diese Prüfung würde sie als „ok“ zählen. Genau das ist bei der Entwicklung einmal passiert, deshalb gibt es die Prüfung.

Nur bestimmte Tests: `TEST_ONLY=hero bash tools/run_tests.sh`

## Testumfang (Stand Phase 1)

| Datei | Prüft |
|---|---|
| `test_data.gd` | Daten fehlerfrei; Kern 10.000 LP; alle Modelle vorhanden; jede referenzierte Animation existiert im Modell; ungültige Wellen werden verworfen und gemeldet; alle Aktionen (inkl. Q–Y, B, I, C, Tab, Esc) belegt |
| `test_health.gd` | LP nie negativ; `died` genau einmal; kein Schaden an Toten; Heilung nur effektiv (keine Überheilung); Wiederbelebung; 0/negativer Schaden wird ignoriert |
| `test_waves.gd` | Vorbereitung ohne Spawns; Spawn-Zeitpunkte; Pfade aus den Daten; Abschluss erst, wenn alle besiegt sind; Wellenanzeige; jede Welle genau einmal abgeschlossen; Ende genau einmal; Überspringen der Vorbereitung; `stop()` beendet das Spawnen |
| `test_stats.gd` | Kostenformel `round(100 · 1.16^n)` (100/116/135, streng steigend); Soft Cap halbiert die Wirkung ab 40; Attribute wirken auf Leben, Schaden, Angriffstempo, Krit, Mana, Fähigkeitsstärke; Obergrenzen (Krit 50 %, Angriffstempo, Lauftempo, Rüstung); Rollenprofile (Guardian zäh, Shadow höchster DPS, Arcanist Fernkampf/Magie); Levelaufstieg, Wachstum, Höchststufe, kein Überlauf; XP-Kurve; Krit-Quote und Krit-Schaden |
| `test_economy.gd` | Startgold; kein negativer Kontostand; kein Abzug bei Fehlschlag; doppelte Referenzen (Belohnung, Kauf) abgelehnt; Transaktionsprotokoll mit IDs und Summen nach Grund; Aufteilung nach Anteilen mit exakter Summe |
| `test_combat.gd` | Rüstung/Magieresistenz/wahrer Schaden; negative Rüstung ohne Bonus; Verlangsamung stapelt nicht und ist gedeckelt; Betäubung; Kontrollresistenz |
| `test_heroes.gd` | Alle drei Helden besiegen Gegner; Arcanist feuert Geschosse aus der Distanz und verlangsamt; Kill bringt Gold und XP; **auch ein einzelner tödlicher Treffer bringt Gold**; Wellenbonus genau einmal, kein Kill-Gold ohne Beteiligung; Attribut-Käufe inkl. Kostenfolge, Fehlschlag mit Begründung ohne Abzug, unbekanntes Attribut; Levelaufstieg im Spiel; Gegner skalieren mit der Welle; Gold nur für Beteiligte |
| `test_telemetry.gd` | CSV-Speicher mit Sonderzeichen; echte Runde wird vollständig erfasst (Runde, Welle, Gold nach Quelle, Ausgaben, Krits, Gegnerstatistik, alle Buchungen inkl. Startgold, Helden-Endstand); keine Doppelzeilen; Abbruch als `aborted`; abgeschaltet schreibt nichts |
| `test_audio.gd` | Alle Ereignisse, Dateien und Busse vorhanden; Mindestabstand, Höchstzahl, stumm; Spielereignisse (Treffer, Krit, Tod, Gold, Kerntreffer, Kauf) lösen die richtigen Sounds aus |
| `test_abilities.gd` | Daten (9 normale + 4 Ultimates, Kosten 250–350, Ultimates 90–120 s); Lernen, Slots, R nur Ultimate, Ultimate ab Stufe 10, nur eines; kein Lernen ohne Gold; Mana, Abklingzeit, Betäubung blockiert, Abklingzeit pausiert; Shield Bash (Schaden + Betäubung); Taunt (Zielwechsel, bleibt, Gegner läuft zum Tank); Barriere absorbiert; Shadow Strike springt; Gift stapelt max. 3 und tickt; Feuerball trifft mehrere; Frost Nova verlangsamt; Starfall schadet erst nach der Vorwarnung; Heilung nie über fehlende LP; Segen stapelt nicht und reduziert korrekt; Bastion nie unverwundbar; Shadow Dance; Sanctuary teamweit; Zielfähigkeit außer Reichweite: hinlaufen und wirken |
| `test_shop.gd` | Gegenstände vorhanden; Kauf, Anlegen, Wertebonus, Fehlschlag ohne Abzug, Verkauf 50 %; Tasche und Tausch; Verbrauch stapelt, Slot-Grenze, Benutzen heilt; Team-Gold getrennt, Spende, kein stiller Abzug, Kern-Upgrades wirken (LP, Regeneration, Barriere), Höchststufe |
| `test_rewards.gd` | kein Gold für Überheilung oder ungenutzte Schilde; Taunt ohne Wirkung zählt nicht; wiederholte Kontrolle nimmt ab und ist gedeckelt; Rollenbonus 0–100, Support-Gold gedeckelt, AFK ohne Wellenbelohnung; Kill-Gold skaliert mit Spielerzahl, Gegner nur einmal abgerechnet; **Rollenvergleich: Tank, Support, Magier, Schurke 300–450 Gold je Welle, Abstand ≤ 15 %** |
| `test_match.gd` | Hauptmenü lädt; Runde baut sich vollständig auf (Held, Kern, 3 Pfade, Deko); Held bewegt sich per Richtung und Klickziel; Gegner erscheinen und laufen zum Kern; Gegner beschädigen den Kern; Held besiegt einen Gegner → Kill gezählt → Welle genau einmal abgeschlossen → Sieg; angegriffener Gegner wendet sich dem Helden zu, verletzt ihn und kehrt außerhalb der Reichweite zum Kern zurück; Heldentod und Wiederbelebung am Startpunkt; Kern fällt → Niederlage, Wellen gestoppt, Eingabe gesperrt, LP nicht negativ; Pause hält die Simulation an |

## Letzter Lauf

**2026-10-27, Godot 4.4.1, Windows 11, nach Phase 3: 86 bestanden, 0 fehlgeschlagen, keine Skriptfehler (Stand nach Klassenfähigkeiten und Effekten).**

Tests schreiben Telemetrie nach `user://telemetry_test` (wird bei jedem Lauf geleert), nicht in die echten Daten. Audio wird headless nicht wirklich abgespielt (Dummy-Treiber), die Logik aber vollständig geprüft. **Die Klangauswahl selbst ist nicht geprüft** – sie wurde nach Dateinamen getroffen und muss angehört werden.

Sichtprüfung nach Phase 2 mit Screenshots von Arcanist und Shadow: Heldenauswahl, Kampf (Geschosse, magischer Schaden, Krits, „+Gold“), Levelaufstieg, Charakterfenster. In einem von vier gerenderten Läufen stand der Held still, obwohl er einen Bewegungsbefehl hatte. Das ließ sich in drei Wiederholungen (headless und gerendert, mit Zustandsprotokoll) nicht nachstellen. Vermutlich hat das Testfenster beim Öffnen ein echtes Mausereignis erhalten. Bleibt als Beobachtungspunkt offen.

## Sichtprüfung

```bash
godot --path . --fixed-fps 60 -s res://tools/screenshot.gd -- <ausgabeordner> [guardian|shadow|arcanist]
```

Das Werkzeug öffnet ein Fenster (echtes Rendering, nicht headless) und speichert Bilder von Hauptmenü, Arena, Übersicht, Kampf, kritischem Kern und Niederlage. Nach spätestens 3 Minuten schließt es sich selbst. Referenzbilder: `docs/screenshots/`.

**Heldenmodelle:** `tools/model_viewer.cmd` (Doppelklick) oder `tools/model_viewer.tscn` im Editor mit F6 öffnet den Modell-Viewer. Taste F springt von Fähigkeit zu Fähigkeit, `-- --skill=<id>` startet direkt bei einer. Mit `godot --path . res://tools/model_viewer.tscn -- --shots=<ordner>` speichert er Bilder aller Helden und Posen. `godot --headless --path . -s res://tools/verify_custom_models.gd` prüft die eigenen Modelle gegen die Originale: Skelett, Animationen und Ausrüstung.

**Fähigkeiten mit Effekten:** `tools/skill_showcase.cmd` (Doppelklick) zeigt jede Fähigkeit in einer echten Runde mit allen Effekten, Schadenszahlen, Zuständen und Klängen. Wer wirkt, steht in der Mitte, die beiden anderen Helden dienen als Verbündete, dazu kommen fünf Trainingspuppen. Die Puppen stehen still, greifen nicht an und werden vor jeder Vorführung aufgefüllt. Die Fähigkeit wird alle 4 s neu gewirkt. `-- --skill=<id>` startet bei einer Fähigkeit, `-- --original` mit den KayKit-Modellen.

## Manuelle Prüfliste (bei Änderungen an Steuerung/Gefühl)

1. Hauptmenü → „Einzelspiel starten“
2. Rechtsklick auf den Boden: läuft hin; Rechtsklick halten: folgt dem Mauszeiger; A + Linksklick: Fadenkreuz, Angriffsbewegung; S: bleibt stehen; Y: Kamera lösen, Randscrollen, Leertaste zentriert
3. Mauszeiger über einem Gegner: gelber Ring; Klick: roter Zielring, Held läuft hin und schlägt zu
4. N: Welle startet sofort; Gegnerzahl im HUD stimmt
5. Esc: Pause (Countdown steht), Esc oder „Weiterspielen“: weiter
6. Kern unter 25 %: roter Rand und Warnbanner
7. Sieg nach Welle 3 bzw. Niederlage bei 0 Kern-LP; „Neue Runde“ und „Hauptmenü“ funktionieren

## Noch nicht abgedeckt

- Maus-Eingabe selbst (`HeroInput`) ist nur manuell geprüft; die Tests rufen die Befehle direkt auf.
- Performance-Szenario mit vielen Gegnern (geplant für Phase 4/6)
- Netzwerk-Tests (Phase 5)
