# Balancing

Alle Werte stehen in `data/` und sind ohne Codeänderung anpassbar. Die Zahlen hier zeigen den Stand nach Phase 2. Es sind **Startwerte**, noch nicht ausbalanciert. Mit `godot --headless --path . -s res://tools/stat_table.gd` lassen sich die Heldentabellen jederzeit neu erzeugen.

## Global (`data/balance/game.json`)

| Wert | Stand | Bedeutung |
|---|---|---|
| `core.max_hp` | 10.000 | Kern-LP (Vorgabe) |
| `core.critical_ratio` | 0,25 | ab hier Warnzustand |
| `heroes.respawn_seconds` | 6 | Wartezeit nach Heldentod |
| `waves.default_prepare_seconds` | 12 | Vorbereitung, wenn eine Welle nichts angibt |
| `waves.enemy_hp_growth_per_wave` | 0,08 | Gegner-LP × (1 + 0,08 · (Welle − 1)) |
| `waves.enemy_damage_growth_per_wave` | 0,05 | Gegnerschaden × (1 + 0,05 · (Welle − 1)) |
| `enemies.threat_seconds` | 4 | so lange bleibt ein Gegner auf einen angreifenden Helden fixiert |
| `player_scaling.enemy_hp_per_extra_player` | 0,6 | Gegner-LP × (1 + 0,6 · (Spieler − 1)) |
| `rewards.start_gold` | 500 | Startgold je Spieler (Vorgabe) |
| `rewards.wave_bonus_gold` | 150 | je Spieler und abgeschlossener Welle (Vorgabe) |
| `rewards.wave_xp_base` / `wave_xp_per_wave` | 40 / 10 | Wellen-XP = 40 + 10 · Welle |
| `rewards.xp_share_radius` | 16 m | XP für Helden in dieser Nähe zum besiegten Gegner |
| `fountain.position` / `radius` | (0, 0, 25,5) / 4 m | Brunnen der Erholung am Südrand, 25,5 m vom Kern (Heilen kostet Zeit an der Basis) |
| `fountain.hp_per_second` / `mana_per_second` | 0,01 / 0,01 | Anteil von max. Leben/Mana pro Sekunde im Wirkkreis (von 0,025 gesenkt; Volle Heilung ~100 s; nicht gegengespielt) |
| `map_structures.tower` | 1.800 LP, Rüstung 4, 34 Schaden / 1,1 s, 9 m | Turm der Zitadelle, 4 Stück wie im Konzeptbild (magischer Glutschuss auf den nächsten Gegner; nicht gegengespielt) |
| `maps.json` → `citadel.fountain_radius` | 3,2 m | Brunnenkreis der Zitadelle (kleinerer Hof als die Arena; Raten wie `fountain`) |
| `map_structures.gate` | 3.500 LP, Rüstung 6, 20 Schaden / 1,0 s, 10 m | Torhaus: hält Gegner auf, bis es fällt |
| `map_structures.shrine` | +20 % Leben/Mana, 90 s Ladezeit, 2,2 m | Schrein am Fluss: einmaliger Schub für einen verletzten Helden |

**Spielerskalierung:** bewusst nicht linear. Bei 4 Spielern haben Gegner das 2,8-Fache der LP statt des 4-Fachen. **Wellenskalierung:** Neben der Zusammensetzung steigen LP und Schaden je Welle leicht, in Welle 10 um +72 % LP und +45 % Schaden.

## Attribute (`data/balance/attributes.json`)

| je Punkt | Wirkung |
|---|---|
| **Stärke** | +20 Leben, +0,1 LP/s, +0,4 physischer Angriffsschaden, +0,12 Rüstung |
| **Beweglichkeit** | +1,5 % Angriffstempo, +0,15 % Krit-Chance, +0,02 m/s Lauftempo, +0,08 Rüstung |
| **Intelligenz** | +12 Mana, +0,05 Mana/s, +1 % Fähigkeitsstärke, +1 % Heilungsstärke, +0,5 magischer Angriffsschaden, +0,1 Magieresistenz |
| **Hauptattribut** (★) | zusätzlich +0,8 Angriffsschaden je Punkt |

**Obergrenzen:** Krit-Chance 50 % · Angriffstempo-Bonus +150 % · Lauftempo 8,5 m/s · Rüstung und Magieresistenz je 200 · Verlangsamung 70 %. Krit-Multiplikator ×1,75.

**Rüstung/Magieresistenz:** Schaden × 50 / (50 + Wert). 50 Rüstung halbieren physischen Schaden, 150 lassen 25 % übrig. Rüstung wirkt nicht gegen Magie und umgekehrt.

**Attribut-Käufe:** Kosten = `round(100 · 1.16^n)` mit n = bereits gekaufte Punkte *dieses* Attributs, also 100, 116, 135, 156, 181 … Punkt 10 kostet 380, Punkt 20 kostet 1.678. **Soft Cap:** Ab 40 gekauften Punkten wirkt jeder weitere nur halb. Kauf und Wirkung bleiben möglich, aber ein einzelnes Attribut dominiert nicht.

## Helden (`data/heroes/heroes.json`)

Werte ohne gekaufte Punkte. *DPS inkl. durchschnittlicher Krits, vor Rüstung des Ziels.

| Held | Stufe | Leben | Mana | Schaden | Angriffe/s | DPS* | Krit | Rüstung | MR | Tempo |
|---|---|---|---|---|---|---|---|---|---|---|
| Guardian | 1 | 940 | 220 | 44 | 1.18 | 53 | 2 % | 7.6 | 11.0 | 6.04 |
| Guardian | 10 | 1480 | 328 | 77 | 1.34 | 106 | 3 % | 11.7 | 11.9 | 6.26 |
| Guardian | 15 | 1780 | 388 | 95 | 1.43 | 140 | 4 % | 14.0 | 12.4 | 6.38 |
| Shadow | 1 | 680 | 220 | 39 | 1.70 | 73 | 14 % | 5.6 | 9.0 | 6.68 |
| Shadow | 10 | 968 | 328 | 66 | 2.21 | 165 | 18 % | 9.5 | 9.9 | 7.22 |
| Shadow | 15 | 1128 | 388 | 81 | 2.49 | 233 | 20 % | 11.6 | 10.4 | 7.52 |
| Arcanist | 1 | 600 | 450 | 41 | 0.91 | 37 | 2 % | 3.3 | 17.5 | 5.84 |
| Arcanist | 10 | 780 | 795 | 78 | 1.03 | 83 | 3 % | 5.2 | 20.4 | 6.06 |
| Arcanist | 15 | 880 | 987 | 99 | 1.10 | 112 | 4 % | 6.3 | 22.0 | 6.18 |

Der Arcanist hat den niedrigsten Grundangriff. Ausgeglichen wird das durch 9 m Reichweite, magischen Schaden (ignoriert Rüstung, z. B. beim Grabkoloss mit 15 Rüstung) und 20 % Verlangsamung pro Treffer. Seine eigentliche Stärke kommt in Phase 3 mit Flächenfähigkeiten, die mit Intelligenz skalieren.

## Level und XP

XP bis zur nächsten Stufe: 80, 120, 160, 210, 260, 320, 380, 450, 520, 600, 680, 770, 860, 960, danach in 100er-Schritten bis Stufe 20. **Bis Stufe 15: 6.370 XP.** Bei etwa 500 Gegnern über 20 Wellen (Ø 13 XP) plus Wellen-XP (≈ 2.900) ergibt das Stufe 15–16 am Rundenende. Das passt zur Vorgabe und wird in Phase 6 mit echten Wellen nachjustiert.

Pro Stufe wachsen die Attribute laut `growth` des Helden; gewonnene Max-LP und Mana werden sofort gutgeschrieben.

## Gegner (`data/enemies/enemies.json`)

| | LP | Tempo | Schaden (Held) | Kernschaden | Intervall | Rüstung | MR | Gold | XP |
|---|---|---|---|---|---|---|---|---|---|
| Knochenläufer | 120 | 3,2 | 14 | 20 | 1,4 s | 0 | 0 | 10 | 12 |
| Schattenhuscher | 70 | 5,6 | 8 | 30 | 1,0 s | 0 | 5 | 9 | 10 |
| Grabkoloss | 480 | 2,3 | 32 | 90 | 2,0 s | 15 | 0 | 15 | 30 |
| Abgrund-Hexer | 650 | 2,7 | 24 (magisch, 6 m) | 45 | 1,9 s | 12 | 25 | 45 | 75 |
| Eisdrache | 5200 | 2,1 | 45 (magisch, 8 m) / 75 (Nahkampf) | 220 | 1,9 s | 65 | 30 | 600 | 900 |

| Aggro | Radius (greift Helden in der Nähe an) | Leash (gibt Verfolgung auf) |
|---|---|---|
| Knochenläufer | 5,0 m | 8,0 m |
| Schattenhuscher | 3,0 m | 5,0 m |
| Grabkoloss | 4,5 m | 7,5 m |

## Gold (Stand Phase 2 – erweitert in Phase 3, siehe unten)

- **Kill-Gold** wird nach Anteil am verursachten Schaden aufgeteilt, nicht nach letztem Treffer. Die Summe bleibt exakt, Rundungsreste gehen an die größten Anteile. Ohne Heldenbeteiligung gibt es kein Gold.
- **Wellenbonus** 150 je Held, genau einmal pro Welle.
- **Erste Testwelle** (10 Knochenläufer, Einzelspieler): 500 Start + 100 Kills + 150 Bonus = 750 Gold, also etwa 5 Attributpunkte.

## Geplant

- Phase 4/6: Elite- und Bossbeiträge (Schaden gegen gefährliche Ziele) im Rollenbonus gezielt gewichten; Balancing mit echten Telemetriedaten statt Simulation

## Fähigkeiten und Gegenstände (Phase 3)

- **Kosten Fähigkeiten:** normale 300 / 350 / 500 (Lernen / Stufe 2 / Stufe 3). Die Vorgabe „erste Fähigkeit 250–350“ ist erfüllt; mit 500 Startgold ist sie sofort kaufbar. Ultimates 900 / 1.100 / 1.400.
- **Wirkwert** = Basis × Fähigkeitsstärke (1 + 1 % je Int) + Σ Skalierung × Attribut, z. B. Shield Bash +0,8 × Str, Fireball +1,0 × Int, Arcane Barrier +2 × Int + 1 × Str.
- **Gegenstände:** 350–600 Gold, Verbrauch 120–150. Verkauf zu 50 %.
- **Team-Upgrades:** 300–1.000 Team-Gold je Stufe, je 3 Stufen.

## Belohnungen (Phase 3, kalibriert)

Werte in `data/balance/game.json` (`rewards`, `contribution`).

| Baustein | Regel |
|---|---|
| Kill-Gold | Gegner-Gold × (1 + 0,3 · (Spieler − 1)), aufgeteilt nach Anteilen |
| Anteil Schaden | verursachter Schaden / Max-LP (max. 1) |
| Anteil Kontrolle | neue Wirkdauer × Gewicht (Betäubung 0,15, Taunt 0,08, Verlangsamung 0,05 × Stärke), Wiederholung am selben Ziel × 0,5, max. 0,3 je Gegner |
| Anteil Tanken | abgefangener Schaden / (Max-LP × 0,5), max. 0,2 |
| Taunt-Bonus | +0,1, nur wenn der Gegner wirklich das Ziel wechselte; Taunt ohne Wechsel zählt gar nicht |
| Support-Gold | (effektive Heilung + absorbierter Schild + verhinderter Schaden) × 0,25, max. 150 je Welle |
| Rollenbonus | 0–100 nach Leistungspunkten: Support × 1 + Tanken × 0,5 + Kontrolle × 200 + Schaden × 0,3; 600 Punkte = 100 Gold |
| Wellenbonus | 150 je aktivem Spieler |
| Team-Gold | 100 + 40 je Spieler je Welle |
| AFK | kein Spielerbefehl seit 60 s → keine Wellen-, Support- und Rollenbelohnung |

**Kalibrierung:** Der Test `test_rewards.gd::test_roles_earn_comparable_gold` simuliert eine 4-Spieler-Welle (24 Knochenläufer, 4 Grabkolosse) mit typischem Verhalten je Rolle. Ausgangswerte ergaben Tank 725 · Support 486 · Magier 540 · Schurke 435 Gold (67 % Abstand). Nach Anpassung der Gewichte und Aufnahme von Schaden in den Rollenbonus: **Tank 428 · Support 444 · Magier 436 · Schurke 398** – alle im Zielkorridor 300–450, Abstand 11,6 % (Vorgabe ≤ 15 %). Die Simulation beruht auf Annahmen über typisches Verhalten; echte Werte liefert die Telemetrie.

**Eisdrache** (`ice_drake`, Mini-Boss, Welle 8 Pfad 2, 10 s nach Wellenstart; ersetzt dort einen Grabritter, Vorbereitung 45 s statt 40 s): Kontrollresistenz 60 %, Körperradius 1,5 m. Elemente Eis ×0, Feuer ×1,5, Gift ×1,5. Unterkühlung 20 %/20 % für 2 s. Odem 90 Schaden, Abklingzeit 9/8/6,5 s, erster nach 4 s. Schneesturm 14 Schaden je 0,5 s, Abklingzeit 12/12/9 s, Einfrieren bei 6 Stapeln für 1,5 s. Schrei alle 18 s, erster nach 8 s, +25 Rüstung/MR für Gegner. Phasen bei 60 % und 30 %. Alle Werte Schätzwerte, nicht gegengespielt.

**Abgrund-Hexer** (`abyss_hexer`, Elite, Welle 7 Pfad 1, 12 s nach Wellenstart): Staffschlag 60 Schaden, 4,5 m, 45 % Verlangsamung 2,5 s, 1 s Ankündigung, 9 s Abklingzeit, erster Schlag nach 3 s. Alle Werte Schätzwerte, nicht gegengespielt.
