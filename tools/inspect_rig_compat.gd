extends SceneTree
## Hilfswerkzeug: vergleicht das Skelett der KayKit-1.0-Figuren mit dem Rig_Medium der Animationsbibliothek 1.1.
##   godot --headless --path . -s res://tools/inspect_rig_compat.gd

func _initialize() -> void:
	var old: Node = (load("res://assets/models/heroes/Knight.glb") as PackedScene).instantiate()
	var sk: Skeleton3D = old.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = old.find_children("*", "AnimationPlayer", true, false)[0]
	print("1.0 Skelett-Pfad (relativ zum AnimationPlayer-Root): ", ap.get_node(ap.root_node).get_path_to(sk))
	var bones := []
	for i in sk.get_bone_count():
		bones.append(sk.get_bone_name(i))
	print("1.0 Knochen (", bones.size(), "): ", bones)
	print("1.0 Beispielspur: ", ap.get_animation("Idle").track_get_path(0))
	var lib_scene: Node = (load("res://assets/models/kaykit2/animations/Rig_Medium_CombatMelee.glb") as PackedScene).instantiate()
	var lib_sk: Skeleton3D = lib_scene.find_children("*", "Skeleton3D", true, false)[0]
	var lib_bones := []
	for i in lib_sk.get_bone_count():
		lib_bones.append(lib_sk.get_bone_name(i))
	var missing := lib_bones.filter(func(b): return not (b in bones))
	print("Knochen der Bibliothek, die im 1.0-Skelett fehlen: ", missing)
	# Ruhehaltung vergleichen (gleiche Rest-Pose = Animationen übertragbar)
	var diff := 0.0
	for b in lib_bones:
		var i := sk.find_bone(b)
		var j := lib_sk.find_bone(b)
		if i >= 0 and j >= 0:
			diff = maxf(diff, sk.get_bone_rest(i).origin.distance_to(lib_sk.get_bone_rest(j).origin))
	print("größte Abweichung der Knochen-Ruheposition: %.4f" % diff)
	old.free()
	lib_scene.free()
	quit()
