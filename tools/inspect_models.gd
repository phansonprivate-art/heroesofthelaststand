extends SceneTree
## Hilfswerkzeug: untersucht KayKit-2.0-Figuren und Animationsbibliotheken (Struktur, Animationen, Längen).
##   godot --headless --path . -s res://tools/inspect_models.gd

func _tree(n: Node, depth := 0) -> void:
	if depth > 4:
		return
	print("  ".repeat(depth + 1), n.name, " <", n.get_class(), ">")
	for c in n.get_children():
		if not (c is MeshInstance3D) or depth < 3:
			_tree(c, depth + 1)


func _initialize() -> void:
	var knight: Node = (load("res://assets/models/kaykit2/heroes/Knight.glb") as PackedScene).instantiate()
	print("== Knight 2.0 Struktur")
	_tree(knight)
	var meshes := knight.find_children("*", "MeshInstance3D", true, false).map(func(m): return m.name)
	print("  Meshes: ", meshes)
	var players := knight.find_children("*", "AnimationPlayer", true, false)
	print("  AnimationPlayer: ", players.size(), " ", players.map(func(p): return p.get_animation_list().size()))
	var sk: Skeleton3D = knight.find_children("*", "Skeleton3D", true, false)[0]
	var bones := []
	for i in sk.get_bone_count():
		bones.append(sk.get_bone_name(i))
	print("  Knochen: ", bones)
	knight.free()
	for f in DirAccess.get_files_at("res://assets/models/kaykit2/animations/"):
		if not f.ends_with(".glb"):
			continue
		var inst: Node = (load("res://assets/models/kaykit2/animations/" + f) as PackedScene).instantiate()
		var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
		var names := []
		for n in ap.get_animation_list():
			names.append("%s(%.2f)" % [n, ap.get_animation(n).length])
		print("== ", f, " [", names.size(), "] root=", ap.root_node, " track0=", ap.get_animation(ap.get_animation_list()[0]).track_get_path(0))
		print("   ", ", ".join(names))
		inst.free()
	quit()
