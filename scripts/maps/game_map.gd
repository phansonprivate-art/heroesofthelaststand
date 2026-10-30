class_name GameMap
extends Node3D
## Gemeinsame Schnittstelle aller Karten (Arena, Zitadelle des Lichts): Gegnerwege, Heldenstart, Kameragrenzen
## und Bauwerke. Welche Karte eine Runde lädt, steht in data/maps/maps.json und wird im Menü gewählt.

## Kartendefinition aus GameData (vor dem Einhängen gesetzt).
var definition: Dictionary = {}


## Wegpunkte aller Gegnerwege (Index wie "path" in den Wellendaten).
func get_spawn_paths() -> Array[PackedVector3Array]:
	return []


## Wegvarianten je Pfadnummer (z. B. zwei Bögen um ein Hindernis); der Spawner wechselt sie ab. Leer = nur der Hauptweg.
func get_path_variants() -> Dictionary:
	return {}


## Start- und Wiedereinstiegspunkt eines Helden (index = Spielernummer ab 0).
func hero_spawn_point(_index := 0) -> Vector3:
	return Vector3.ZERO


## Bereich, in dem sich der Kamerafokus bewegen darf (x/z).
func camera_bounds() -> Rect2:
	return Rect2(-26, -26, 52, 52)


## Kampfbauwerke der Karte (Türme, Torhaus) – nach dem Verdrahten der Runde aufgerufen.
func bind_match(_match: Node) -> void:
	pass


## Ausschnitt (x/z), den die Minimap zeigt.
func minimap_extent() -> Rect2:
	return camera_bounds().grow(6.0)
