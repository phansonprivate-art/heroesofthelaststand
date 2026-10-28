extends SceneTree
## Hilfswerkzeug: Länge aller Jingles und Sounds (zur Auswahl passender Klänge).
##   godot --headless --path . -s res://tools/audio_lengths.gd

func _initialize() -> void:
	for dir in ["res://assets/audio/jingles/", "res://assets/audio/sfx/", "res://assets/audio/battle/"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".ogg") or f.ends_with(".wav"):
				var s: AudioStream = load(dir + f)
				print("%-32s %.2f s" % [f, s.get_length()])
	quit()
