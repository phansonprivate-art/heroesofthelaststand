# Netzwerk

**Stand: Es gibt noch keinen Mehrspielermodus.** Koop folgt in Phase 5. Dieses Dokument beschreibt das geplante Modell und was bereits darauf vorbereitet ist.

## Geplantes Modell

- **Host-autoritativ** mit Godots High-Level-Multiplayer (`ENetMultiplayerPeer`). Ein Spieler hostet, bis zu drei treten bei.
- **Private Lobbys ohne Matchmaking.** Beitritt über eine Host-Adresse; der „Einladungscode“ wird eine kodierte Adresse plus Port sein.
- **Netzwerkbedingungen:** Im LAN funktioniert das direkt. Über das Internet braucht der Host eine Portweiterleitung (UDP) oder ein VPN-artiges Overlay (z. B. ZeroTier/Tailscale). Ein Relay- oder NAT-Traversal-Dienst ist nicht Teil des MVP und wird nicht vorgetäuscht. Falls nötig, wird er als externe Abhängigkeit dokumentiert.
- **Keine Host-Migration im MVP.** Verlässt der Host die Runde, endet sie für alle.

## Verteilung der Verantwortung

| Host entscheidet | Client sendet |
|---|---|
| Gegner-Spawns und -Zustände, Treffer und Schaden, Kern-LP, Gold, XP, Käufe, Wellenfortschritt, Bossphasen, Spielende | Bewegungsrichtung, Klickziele, Angriffsziele, Fähigkeits- und Kaufwünsche |

Clients legen nie selbst Belohnungen oder Schadensresultate fest. Rein visuelle Effekte (Schadenszahlen, Partikel, Kamera) werden lokal aus replizierten Ereignissen erzeugt, nicht einzeln übertragen.

## Bereits vorbereitet (Phase 1–2)

- `CombatService.deal_damage`, `EnemySpawner.spawn` und `WaveManager._process` laufen nur, wenn `multiplayer.is_server()` wahr ist.
- Der Held wird ausschließlich über Befehle gesteuert (`command_*`). `HeroInput` sendet Befehle nur bei Klicks; gehaltene Rechtsklick-Bewegung wird auf alle 0,12 s gedrosselt. Das ist die Grundlage für sparsame RPCs.
- Kamera, Zielmarkierungen und HUD sind rein lokal.
- Jeder Held hat eine `peer_id`.
- `WaveManager` merkt sich abgeschlossene Wellen, sodass ein Abschluss nicht doppelt ausgelöst wird (Grundlage für den Schutz vor Doppelbelohnung).
- Alle Käufe, Fähigkeiten und Verbrauchsgegenstände laufen über `MatchController.request_*` (Phase 3); Shop und Gold prüfen die Host-Autorität.
- `GoldService`, `RewardService` und `UpgradeService` buchen nur auf dem Host; Kaufwünsche laufen bereits über eine Anfrage-Methode (`MatchController.request_attribute_upgrade`), die in Phase 5 zum RPC wird. Jede Buchung hat eine eindeutige Referenz, sodass wiederholte Nachrichten nicht doppelt buchen.

## Offene Punkte für Phase 5

- Lobby-UI (Host/Beitreten/Heldenwahl/Bereit)
- Replikation: `MultiplayerSpawner` für Helden/Gegner, `MultiplayerSynchronizer` für Position, Rotation, LP und Animationszustand
- Wiederverbindung: Spielerzustand am Host je Spieler-ID halten, beim Neubeitritt zuordnen
- Validierung von Client-Befehlen (Reichweite, Abklingzeiten, Gold) am Host
- Automatisierte Tests mit zwei lokalen Instanzen; wo das nicht geht, ein reproduzierbarer manueller Ablauf
