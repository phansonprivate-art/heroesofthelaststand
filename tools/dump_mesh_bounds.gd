extends SceneTree
## Misst die Bounding-Boxen aller Meshes (Körperteile + Ausrüstung) im Skelett-Raum in Ruhehaltung,
## damit neu gebaute Körper so dimensioniert werden, dass Helm/Hut/Cape weiterhin passen.
##   godot --headless --path . -s res://tools/dump_mesh_bounds.gd -- <glb-pfad> [<glb-pfad> ...]

func _initialize() -> void:
	var paths := OS.get_cmdline_user_args()
	if paths.is_empty():
		paths = PackedStringArray(["res://assets/models/heroes/Knight.glb", "res://assets/models/heroes/Rogue_Hooded.glb", "res://assets/models/heroes/Mage.glb"])
	for path in paths:
		var model: Node3D = (load(path) as PackedScene).instantiate()
		root.add_child(model)
		var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
		sk.reset_bone_poses()
		await process_frame
		await process_frame
		print("=== ", path, " ===")
		var inv := sk.global_transform.affine_inverse()
		for m: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			var box := (inv * m.global_transform) * m.get_aabb()
			var c := box.get_center()
			print("  %-20s center=(%.3f, %.3f, %.3f) size=(%.3f, %.3f, %.3f)  y:[%.3f .. %.3f] z:[%.3f .. %.3f]" % [m.name, c.x, c.y, c.z, box.size.x, box.size.y, box.size.z, box.position.y, box.end.y, box.position.z, box.end.z])
		model.queue_free()
	quit()
