# Game Design

Die vollständige Vision steht im Master-Prompt (Koop-Hero-Defense, 1–4 Spieler, ca. 45 Minuten, 20 Wellen + dreiphasiger Boss, Rollen Tank/Support/Magier/Schurke, beteiligungsbasierte Wirtschaft). Dieses Dokument beschreibt, was davon **umgesetzt** ist, und hält Designentscheidungen fest.

## Welt und Ton

Eine verfallene Festungshalle; untote Horden strömen durch drei Tore auf einen leuchtenden Kristallkern zu. Stil: Low-Poly mit klaren Silhouetten (KayKit), kräftige Lesbarkeitsfarben: Held = Cyan, Gegner/Gefahr = Rot, Kern = Hellblau → Rot im kritischen Zustand.

## Arena (umgesetzt)

- 64 × 64 m, Mauerring, Kern im Zentrum.
- Drei Tore mit Spawnpfaden: **Nord** (0), **West** (1), **Ost** (2). Jeder Pfad hat einen Knick, damit die Gegner aus unterschiedlichen Winkeln kommen. Die Laufwege sind als dunkle Bodenstreifen markiert.
- Vier Säulen zwischen den Pfaden als Orientierung und kleine Hindernisse, Deko in den Ecken.
- Heldenstart und Wiederbelebung südlich des Kerns. Der Bereich südlich des Kerns ist für Shop/Upgrades reserviert (Phase 3), damit keine langen Laufwege entstehen.

## Helden (umgesetzt, noch ohne Fähigkeiten)

| Held | Archetyp | Spielweise | Angriff |
|---|---|---|---|
| **Guardian** | Stärke | Tank: viel Leben und Rüstung, bindet Gegner durch Nähe | Schwert, Nahkampf 2,2 m |
| **Shadow** | Beweglichkeit | Schurke: höchster Einzelziel-Schaden, schnell, Krits (Start 14 %) | Doppeldolche, Nahkampf 1,9 m |
| **Arcanist** | Intelligenz | Magier: Fernkampf, magischer Schaden, verlangsamt (20 %, 1 s) | Magisches Geschoss, 9 m |

Gemeinsam für alle:
- Automatischer Angriff auf Gegner in Reichweite, wenn der Held steht.
- Bewegen bricht einen laufenden Schlag ab (bewusste Entscheidung zwischen Positionieren und Schaden).
- Tod → 6 s Wartezeit → Wiederbelebung am Startpunkt mit vollen LP. Der Tod des Helden beendet die Runde nicht.

**Builds:** Die Archetypen geben Startwerte, Wachstum und Hauptattribut vor, schränken aber nichts ein. Jeder Held kann jedes Attribut kaufen, z. B. ein Arcanist mit Stärke für mehr Leben oder ein Guardian mit Intelligenz für spätere Support-Fähigkeiten. Der Soft Cap (40 Punkte) verhindert, dass ein einzelnes Attribut alles dominiert.

## Progression (umgesetzt)

- **XP** gibt es für besiegte Gegner (alle beteiligten Helden und alle lebenden Helden in 16 m Umkreis erhalten die vollen XP, es wird nicht aufgeteilt) und für jede abgeschlossene Welle. Wer weit weg und unbeteiligt ist, bekommt keine Kill-XP.
- **Levelaufstieg:** Banner, goldener Lichtring, Attribute wachsen, gewonnene Leben und Mana werden aufgefüllt. Der Hinweis „Attribute verbessern [C]“ pulsiert, sobald ein Kauf möglich ist.
- **Gold** für Kills nach Schadensanteil, dazu der Wellenbonus. Ausgeben im Charakterfenster (C) für Attributpunkte. Fähigkeiten, Ausrüstung und Shop folgen in Phase 3.

## Status-Effekte (umgesetzt)

- **Verlangsamung:** verringert das Lauftempo; gleiche Effekte stapeln nicht (die stärkere Wirkung und die längere Dauer gelten), höchstens 70 %. Verlangsamte Gegner schimmern blau.
- **Betäubung:** keine Bewegung, keine Angriffe, ein laufender Schlag wird abgebrochen. Betäubte Gegner schimmern gelb.
- **Kontrollresistenz** (`cc_resist`, für Bosse in Phase 4) verkürzt die Dauer.

## Gegner (umgesetzt)

| Typ | Interne ID | Rolle | Besonderheit |
|---|---|---|---|
| Knochenläufer | `grunt` | Standard | – |
| Schattenhuscher | `runner` | schnell, schwach | hoher Kernschaden pro LP, gefährlich beim Durchbruch |
| Grabkoloss | `brute` | langsam, zäh | sehr hoher Kernschaden |
| Knochenseher | `seer` | Fernkämpfer | schießt aus 7 m magische Geschosse, bleibt auf Abstand |
| Grabritter | `grave_knight` | Elite | **Bodenschlag:** roter Warnkreis (1 s, steht still), dann Schaden und Verlangsamung im Kreis |
| Abgrund-Hexer | `abyss_hexer` | Elite (ab Welle 7) | Fernkämpfer (6 m, violette Zauberkugeln); **Staffschlag:** reißt den Stab hoch und stößt ihn auf den Boden (1 s Ankündigung mit Warnkreis, 4,5 m, Schaden und Verlangsamung). Modell aus Tripo auf dem KayKit-Skelett, eigene Animation `Staff_Slam` |
| Eisdrache | `ice_drake` | Mini-Boss mit Bossphasen (Welle 8) | Issue #9, siehe unten. Modell: Tripo-Drache auf dem Skelett des Glutdrachen (`FrostDrake.glb`) |
| Knochenkoloss | `colossus` | Mini-Boss (Welle 5 und 9) | sehr zäh, Kontrollresistenz 60 %, großer Bodenschlag |
| Morvath, der Totenbeschwörer | `morvath` | Endboss (Welle 10) | drei Phasen, siehe unten |

Die vier neuen Figuren sind eigene Blender-Modelle (`tools/blender_build_enemies.py`) auf dem KayKit-Skelett.

**Nahkampf gegen Helden (Issue #3, 2026-10-29):** Diener und andere Nahkampfgegner lassen sich nicht mehr risikofrei auskiten.
- **Gegenseitige Reichweite:** Ein Nahkampfgegner erreicht einen Nahkampfhelden mindestens aus dessen eigener Schlagweite – wer treffen kann, kann auch getroffen werden.
- **Zurückschlagen trotz Zusammenzucken:** Das kurze Zucken bei Treffern hält den Gegner nur an, der Gegenschlag geht vor.
- **Schnelle Reaktion:** Wechselt ein Gegner vom Kern auf einen Helden, ist er nach spätestens 0,15 s schlagbereit, statt die volle Pause eines Kernschlags abzuwarten. Im Dauerkampf gilt das normale Angriffsintervall.
- **Auskiten bleibt möglich:** Wer die Reichweite verlässt, bevor der Schlag einschlägt (Ausholzeit des Gegners), wird nicht getroffen. Gegen Fernkampfhelden ändert sich nichts.

**Endboss Morvath (drei Phasen nach Lebenspunkten, `data.boss`):**
1. **ab 100 %:** Fernkampfgeschosse; beschwört alle 14 s vier Skelette, deren Beschwörungskreise 1,2 s vorher am Boden erscheinen.
2. **unter 66 % – Seelenfeuer:** zusätzlich grüne Kreise unter bis zu drei Helden; nach 1,5 s Explosion. Wer ausweicht, bleibt heil.
3. **unter 33 % – Raserei und Todeswelle:** 50 % schnellere Angriffe, 30 % schneller; alle 11 s wächst ein violetter Ring (9 m) um den Boss, nach 2,2 s Schaden im ganzen Kreis.

**Eisdrache (Issue #9, drei Phasen, `data.boss`):**
- **Kampfart:** schießt aus 8 m Eisgeschosse; steht ein Held dicht am Körper, schlägt er mit Klaue und Biss zu.
- **Elemente:** immun gegen Eis (kein Schaden, keine Verlangsamung oder Betäubung durch Frost Nova und Gletscherspalt), +50 % Schaden durch Feuer (Fireball) und Gift (Giftstapel). Sehr hohe Rüstung (65).
- **Unterkühlung (passiv):** Jeder Treffer bremst Lauf- und Angriffstempo des Helden um 20 % für 2 s.
- **Eisfeuer-Odem (ab Phase 1):** Kegel (9 m, 70°) erscheint 1 s vorher am Boden, währenddessen sammelt sich Magie im Maul. Dann fliegen Eiszapfen aus dem Maul, Stacheln laufen nach vorn (22 m/s) und brechen um das Ziel als großer Eiscluster aus. Wer bei der Ankündigung im Kegel stand, nimmt Frostschaden, sobald die Stacheln ihn erreichen, und wird verlangsamt (60 %, Angriffe 40 %).
- **Arktischer Schrei (ab Phase 1, alle 18 s):** Helden in 14 m 4 s lang 40 % langsamer (Laufen und Angriff); Gegner in 14 m 6 s lang +25 Rüstung und Magieresistenz.
- **Schneesturm (ab Phase 2, unter 60 %):** Kreis (4 m) an einem Helden, 1 s Warnung, dann 5 s Sturm: Schaden alle 0,5 s, jeder Takt ein Stapel Erfrierung, bei 6 Stapeln 1,5 s eingefroren.
- **Phase 3 (unter 30 %):** 30 % schnellere Angriffe, 20 % schneller.

Phasenwechsel und Auftritt werden als Banner angekündigt; die Bossleiste oben zeigt Lebenspunkte und Phase. Stirbt Morvath, zerfallen seine Beschwörungen. Betäubung unterbricht Bodenschläge (Bosse sind dagegen zu 75 % resistent).

**Verhalten (Zustandsautomat):**
1. *SPAWNING* – steigt aus dem Boden (Animation), bewegt sich noch nicht.
2. *ADVANCE* – folgt den Wegpunkten seines Pfads, ab 9 m vor dem Kern direkt darauf zu.
3. *ATTACK* – greift das aktuelle Ziel an, sobald es in Reichweite ist.
4. *DEAD* – Zerfall-Animation, nach 2,5 s entfernt.

**Zielwahl (nach Priorität):**
1. Ein Held, der den Gegner getroffen hat (4 s lang, mit jedem Treffer erneuert), solange er im `aggro_leash` bleibt.
2. Ein Held, der in den `aggro_radius` des Gegners kommt. Der Gegner verfolgt ihn, bis er den `aggro_leash` verlässt.
3. Sonst der Kern.

Helden ziehen Gegner also schon durch ihre Nähe auf sich. Das ist die Grundlage der Tank-Rolle. Der Leash verhindert, dass ein Gegner endlos weggezogen wird. Schattenhuscher haben einen kleinen Radius und brechen eher zum Kern durch. Taunt (Phase 3) erhält Vorrang vor allem.

## Wellen (umgesetzt: 10 Wellen mit Mini-Boss und Endboss)

- Ablauf: **Ankündigung + Vorbereitung** (Countdown, Vorschau der Gegner) → **Spawnen** (zeitgesteuerte Gruppen je Pfad) → **Aufräumen** (bis alle besiegt sind) → nächste Welle.
- „Jetzt starten“ (N) überspringt die Vorbereitung.
- Nach der letzten Welle: Sieg, sofern der Kern steht. Die letzte Welle ist der Endboss: Sein Fall beendet die Runde.
- Definiert in `data/waves/waves.json` (Phase 6 erweitert auf 20):
  1. Die Vorhut
  2. Flinke Schatten
  3. Schwere Schritte
  4. Die Seher
  5. Der Koloss erwacht (Mini-Boss)
  6. Grabritter
  7. Dreifacher Ansturm
  8. Der Eisdrache (Mini-Boss mit Bossphasen)
  9. Die letzte Flut (Mini-Boss)
  10. Morvath, der Totenbeschwörer (Endboss)

## Zitadelle des Lichts (Phase A umgesetzt, Issue #4)

Zweite Karte, im Hauptmenü wählbar (die Arena bleibt). **Nach dem Konzeptbild des Spielers aufgebaut** (Wunsch des Spielers: „genauso wie in der Abbildung“). Der Grundriss in `data/maps/citadel_layout.json` steht in Pixeln dieses Bildes (1408 × 768) und wird mit 0,11 m je Pixel umgerechnet. Die Karte ist damit rund 128 × 73 m begehbar.
- **Abgrund (Westen):**
  - dunkles, rötliches Vulkangestein mit Glutrissen und zwei Lavabecken;
  - schwarze Felsnadeln, violette Kristalle oben links, tote Bäume;
  - drei Portale: **Abgrundriss** (oben, violett), **Düsterholz-Bau** (Mitte, violett), **Glutentor** (unten, orange).
- **Lanes:**
  - Drei gepflasterte Straßen mit heller Steinkante führen nach Osten.
  - Die **mittlere Lane teilt sich vor dem Krater des Dschungelbosses** in einen Nord- und einen Südbogen (Ringstraße) und vereint sich davor wieder. Gegner der Mitte nehmen abwechselnd einen der beiden Bögen.
  - Alle drei queren den Fluss über je eine Steinbrücke und laufen dann zum Torhaus.
  - Die Wellen nutzen dieselben Pfadnummern wie in der Arena (0 oben, 1 Mitte, 2 unten).
- **Dschungel:**
  - zwei Waldblöcke zwischen den Lanes, jeweils mit einer Lagerlichtung (für neutrale Lager, spätere Phase) und Ruinen;
  - Erdpfade wie im Bild;
  - dunkler Wald im Norden und Süden;
  - die Waldverteilung ist aus dem Bild gemessen (`data/maps/citadel_forest.json`).
- **Mitte:** Krater des Dschungelbosses (Boss folgt später), umgeben von der Ringstraße.
- **Bauten:**
  - zwei Kasernen (Diener folgen später), Händlerposten (nur Kulisse; Shop bleibt auf B), drei Schreine;
  - Steinwälle: einer nördlich der oberen Lane, zwei am Ring, einer an der unteren Lane, Mauern östlich des Flusses.
- **Türme** (wie im Bild):
  - zwei Fort-Türme an der oberen Lane, einer hinter dem Fluss oben, einer an der unteren Lane;
  - schießen Glutgeschosse auf den nächsten Gegner im Umkreis von 9 m;
  - Gegner greifen sie an, sobald sie in ihren Aggro-Radius kommen;
  - Abschüsse nur durch Türme geben kein Gold.
- **Zitadelle (Osten, auf einer Klippe über den Wolken):**
  - sechseckiger Mauerring mit vier Ecktürmen und Feuerschalen;
  - Kern in der Mitte, **Brunnen der Erholung hinten** (Wirkkreis hier 3,2 m);
  - einziger Zugang ist das Torhaus mit zwei Tortürmen im Westen.
- **Heldenpunkte:** vor der Zitadelle links oben und links unten, wie im Bild (blaue Scheiben mit Schwert). Die ersten vier sind die Start- und Wiedereinstiegspunkte.
- **Torhaus:**
  - Das Fallgitter hält nur Gegner auf, Helden gehen hindurch.
  - Gegner müssen es erst zerstören (3.500 Leben); es schießt selbst.
  - Fällt es, ist der Weg zum Kern frei.
- **Schreine:**
  - einmaliger Schub **+20 % Leben und Mana** für einen verletzten Helden, danach **90 s Ladezeit**;
  - bewusst schwächer als der Brunnen (Wunsch des Spielers).
- **Rand:**
  - Berge im Norden, aus denen der Fluss kommt;
  - im Osten fällt das Plateau als Felswand ab, darunter Himmel und Wolken.
- **Gefallene Bauwerke** bleiben für die Runde zerstört.
- **Minimap** oben rechts (auch in der Arena) mit Spieluhr; ein Klick schwenkt die Kamera.
- **Später (weitere Phasen):** neutrale Lager und Dschungelboss, Kasernen mit eigenen Dienern, Heldenleiste.

## Kern (umgesetzt)

10.000 LP. Rückmeldung bei Treffern: Kristall blitzt, Kamera wackelt leicht, Schadenszahl. Unter 25 % gilt er als **kritisch**: roter Balken, pulsierender roter Bildschirmrand, Warnbanner. Bei 0 LP: Niederlage, Gegner jubeln.

## Brunnen der Erholung (umgesetzt, Issue #2)

Am hinteren (südlichen) Arenarand, **25,5 m vom Kern** und abseits aller Gegnerwege – bewusst weit weg (Wunsch des Spielers): Wer sich heilt, fehlt rund 9 s Laufweg plus Heilzeit an der Basis. Aussehen: achteckiges Steinbecken mit leuchtendem Wasser und einem schwebenden Kristall (eigenes Blender-Modell). Ein drehender Runenkreis am Boden zeigt den **Wirkkreis (4 m)**.
- **Erholung:** Helden im Kreis erhalten **1 %** ihres maximalen Lebens und Manas pro Sekunde zusätzlich zur eigenen Regeneration (auf Wunsch des Spielers deutlich unter den ursprünglichen 2,5 %). Volle Heilung dauert rund 100 s – länger als jede Einkaufspause; eine Hilfe, kein Ersatz für Tränke oder Heiler. Betreten und Verlassen verstärkt nichts, gefallene Helden werden weder geheilt noch belebt.
- **Kein Kampf:** Im Kreis ist nur Bewegung möglich (Wunsch des Spielers): keine Angriffe, keine Zauber, kein automatisches Anvisieren. Ein Schlag im Ausholen trifft nicht, der Klingenwirbel macht keinen Schaden. Zauber werden mit „Am Brunnen der Erholung wird nicht gekämpft.“ abgelehnt. Beim Verlassen ist der Held sofort wieder kampfbereit.
- **Rückmeldung:** Lichtfunken steigen aus dem Wasser, ein blaues Licht pulsiert, erholende Helden funkeln; das HUD zeigt den Zustand „Am Brunnen – Erholung, kein Kampf“.
- Werte in `data/balance/game.json` → `fountain` (Lage, Radius, Raten). Gegner sind nicht betroffen.

## Steuerung (entschieden am 2026-10-27)

Die Vorgabe "WASD-Bewegung" und "Fähigkeiten auf Q W E R T Y" belegte W doppelt. **Entscheidung des Spielers: MOBA-Steuerung** (vertraut aus League of Legends):

- Bewegen und Angreifen mit der Maus (Rechtsklick), Angriffsbewegung mit A + Linksklick, Stopp mit S
- Sechs Fähigkeitsslots auf **Q W E R D F**. R ist der Ultimate-Slot (ab Level 10). D und F sind die beiden zusätzlichen Slots, die bei LoL den Beschwörerzaubern entsprechen.
- Kamera mit Y fixierbar oder lösbar; gelöst wird sie am Bildschirmrand verschoben, die Leertaste zentriert
- WASD entfällt. Die Kamera bleibt nach Norden ausgerichtet.

Die Belegung steht zentral in `scripts/core/input_setup.gd`. Ein Test stellt sicher, dass keine Taste doppelt belegt ist.

## Fähigkeiten (umgesetzt)

**Seit 2026-10-27 hat jede Klasse eigene Fähigkeiten** (Wunsch des Spielers): Guardian – Shield Bash, Taunt, Guardian Blessing, Arcane Barrier, Bastion; Shadow – Shadow Strike, Poison Mark, Fan of Knives, Smoke Bomb, Shadow Dance; Arcanist – Fireball, Frost Nova, Chain Lightning, Healing Pulse, Starfall oder Sanctuary. Die Wirkung skaliert stark mit dem Hauptattribut. Alle Fähigkeiten haben 3 Stufen. Die Stufen verbessern nicht nur Schaden, sondern auch Reichweite, Dauer, Kontrolle, Abklingzeit, Stapel oder fügen Spezialeffekte hinzu.

| Fähigkeit | Ziel | Wirkung | Stufe 3 |
|---|---|---|---|
| Shield Bash | Gegner | Schaden + Betäubung (Bosse verkürzt) | 1,5 s Betäubung, mehr Reichweite |
| Taunt | Umkreis | Gegner müssen den Tank angreifen | + Rüstung während Taunt |
| Arcane Barrier | Verbündeter/selbst | Schild, skaliert mit Int und Str | größerer Schild, mehr Reichweite |
| Shadow Strike | Gegner | Sprung zum Ziel, hoher Schaden | immer kritisch |
| Poison Mark | Gegner | Gift über Zeit, ignoriert Rüstung | bis 3 Stapel |
| Fireball | Punkt | Explosion, Rand halber Schaden | größerer Radius |
| Frost Nova | Umkreis | Schaden + Verlangsamung | 60 % Verlangsamung |
| Healing Pulse | Umkreis | Heilung (nur effektiv) | größerer Radius |
| Guardian Blessing | Umkreis | Schadensreduktion, stapelt nicht | + Angriffstempo |
| **Bastion** (Ultimate) | selbst + Umkreis | 50–60 % weniger Schaden, Verbündete 20–30 %, kurzer Taunt | |
| **Shadow Dance** (Ultimate) | selbst | Tempo, Angriffstempo, Krit | |
| **Starfall** (Ultimate) | Gebiet | 8–12 Einschläge mit Vorwarnung | |
| **Sanctuary** (Ultimate, Blessing-Variante) | ganzes Team | Schadensreduktion + Heilung | |

Ultimates: ab Heldenstufe 5, Abklingzeit 90–120 s, nur eines pro Held (bewusste Wahl), immer auf R. Die Schadensreduktion ist auf 75 % gedeckelt; niemand wird unverwundbar.

## Shop, Ausrüstung, Team (umgesetzt)

- **Shop (B)** ist überall erreichbar, damit es keine langen Laufwege gibt. Reiter: Fähigkeiten, Attribute, Ausrüstung, Verbrauch, Team. Nicht kaufbare Einträge zeigen den Grund.
- **Ausrüstung:** Iron Blade, Arcane Focus (Waffe), Guardian Plate (Rüstung), Warden Helm, Shadow Boots, Ring of Haste, Healing Amulet. Kein Gegenstand ist für alle Builds überlegen; jeder bedient eine Richtung.
- **Verbrauch** (Tasten 1/2, je bis 3 Stück): Phoenix Potion (50 % Leben), Protection Rune (4 s 30 % weniger Schaden).
- **Inventar (I):** Ablegen, Anlegen/Tauschen aus der Tasche, Verkaufen für 50 %.
- **Team-Gold:** 100 + 40 je Spieler pro Welle, dazu freiwillige Spenden. Ausgeben für Verstärkter Kern (+1.000 LP), Kernregeneration (4/8/12 LP/s), Schutzbarriere (500/1.000/1.500 Schild je Welle). Je 3 Stufen. Türme sind noch nicht umgesetzt.
