extends SceneTree
## Prueft die neu gebauten Helden-Modelle: Skelett-Kompatibilitaet (gleiche Kern-Knochen wie das
## Original), vorhandene Animationen, und ob die alte Ausruestung (Schwert/Cape/Hut ...) erhalten blieb.
##   godot --headless --path . -s res://tools/verify_custom_models.gd

const CASES := [
	{"id": "guardian", "custom": "res://assets/models/heroes_custom/Guardian.glb", "original": "res://assets/models/heroes/Knight.glb", "old_body": ["Knight_Body", "Knight_Head", "Knight_ArmLeft", "Knight_ArmRight", "Knight_LegLeft", "Knight_LegRight", "Knight_Helmet", "Knight_Cape"], "own_weapons": true},
	{"id": "shadow", "custom": "res://assets/models/heroes_custom/Shadow.glb", "original": "res://assets/models/heroes/Rogue_Hooded.glb", "old_body": ["Rogue_Body", "Rogue_Head_Hooded", "Rogue_ArmLeft", "Rogue_ArmRight", "Rogue_LegLeft", "Rogue_LegRight", "Rogue_Cape"], "own_weapons": true},
	{"id": "arcanist", "custom": "res://assets/models/heroes_custom/Arcanist.glb", "original": "res://assets/models/heroes/Mage.glb", "old_body": ["Mage_Body", "Mage_Head", "Mage_ArmLeft", "Mage_ArmRight", "Mage_LegLeft", "Mage_LegRight", "Mage_Hat", "Mage_Cape"], "own_weapons": true},
]
const CORE_BONES := ["root", "hips", "spine", "chest", "head", "upperarm.l", "lowerarm.l", "hand.l", "upperarm.r", "lowerarm.r", "hand.r", "upperleg.l", "lowerleg.l", "foot.l", "toes.l", "upperleg.r", "lowerleg.r", "foot.r", "toes.r"]


func _initialize() -> void:
	var all_ok := true
	for c in CASES:
		print("\n=== ", c.id, " ===")
		if not ResourceLoader.exists(c.custom):
			print("  FEHLER: Datei fehlt: ", c.custom)
			all_ok = false
			continue
		var custom: Node = (load(c.custom) as PackedScene).instantiate()
		var original: Node = (load(c.original) as PackedScene).instantiate()

		var sk_c: Skeleton3D = custom.find_children("*", "Skeleton3D", true, false)[0]
		var sk_o: Skeleton3D = original.find_children("*", "Skeleton3D", true, false)[0]
		var missing := []
		for b in CORE_BONES:
			if sk_c.find_bone(b) < 0:
				missing.append(b)
		print("  Knochen neu=", sk_c.get_bone_count(), " original=", sk_o.get_bone_count(), " fehlende Kern-Knochen=", missing)
		if not missing.is_empty():
			all_ok = false

		var max_diff := 0.0
		for b in CORE_BONES:
			var i := sk_c.find_bone(b)
			var j := sk_o.find_bone(b)
			if i >= 0 and j >= 0:
				max_diff = maxf(max_diff, sk_c.get_bone_rest(i).origin.distance_to(sk_o.get_bone_rest(j).origin))
		print("  größte Ruhepose-Abweichung Kern-Knochen: %.5f" % max_diff)

		var ap_c: AnimationPlayer = custom.find_children("*", "AnimationPlayer", true, false)[0]
		var ap_o: AnimationPlayer = original.find_children("*", "AnimationPlayer", true, false)[0]
		var anims_c := ap_c.get_animation_list()
		var anims_o := ap_o.get_animation_list()
		var missing_anims := []
		for a in anims_o:
			if not (a in anims_c):
				missing_anims.append(a)
		print("  Animationen neu=", anims_c.size(), " original=", anims_o.size(), " im Original vorhanden aber im neuen Modell fehlend=", missing_anims)
		if not missing_anims.is_empty():
			all_ok = false
		for a in ["Idle", "Running_A"]:
			if anims_c.has(a):
				print("    Länge '", a, "': neu=%.3f" % ap_c.get_animation(a).length, " original=%.3f" % ap_o.get_animation(a).length)
		# Spuren, deren Zielknochen es im neuen Skelett nicht mehr gibt (z. B. entfernte Cape-/Hut-Anhänger)
		var dangling := {}
		for a in anims_c:
			var anim := ap_c.get_animation(a)
			for t in anim.get_track_count():
				var bone := String(anim.track_get_path(t).get_concatenated_subnames())
				if bone != "" and sk_c.find_bone(bone) < 0:
					dangling[bone] = int(dangling.get(bone, 0)) + 1
		print("  Animationsspuren ohne Zielknochen: ", dangling if not dangling.is_empty() else "keine")
		if not dangling.is_empty():
			all_ok = false

		# Jede Fähigkeits-Animation der Klasse muss auf dem neuen Modell abspielbar sein (inkl. kk-Bibliothek)
		var hero_def: Dictionary = {}
		for h in JSON.parse_string(FileAccess.get_file_as_string("res://data/heroes/heroes.json")).heroes:
			if h.id == c.id:
				hero_def = h
		var visual: Node3D = load("res://scripts/gameplay/character_visual.gd").new()
		visual.setup(c.custom, hero_def.hidden_parts, 1.0, hero_def.anims)
		visual.add_animation_libraries(hero_def.anim_libraries)
		var skill_anims := []
		var missing_skill := []
		for s in JSON.parse_string(FileAccess.get_file_as_string("res://data/skills/skills.json")).skills:
			if c.id in s.heroes:
				skill_anims.append(s.anim[0])
				if not visual.anim_player.has_animation(s.anim[0]):
					missing_skill.append("%s (%s)" % [s.id, s.anim[0]])
		print("  Fähigkeits-Animationen geprüft: ", skill_anims.size(), ", fehlend: ", missing_skill if not missing_skill.is_empty() else "keine")
		if not missing_skill.is_empty():
			all_ok = false
		visual.free()

		var names_c := []
		for m: MeshInstance3D in custom.find_children("*", "MeshInstance3D", true, false):
			names_c.append(String(m.name))
		var names_o := []
		for m: MeshInstance3D in original.find_children("*", "MeshInstance3D", true, false):
			names_o.append(String(m.name))
		var equip_o := names_o.filter(func(n): return not (n in c.old_body))
		var equip_missing := equip_o.filter(func(n): return not (n in names_c))
		print("  Ausrüstungs-Meshes original=", equip_o, " davon im neuen Modell fehlend=", equip_missing)
		# realistische Helden (gestrecktes Skelett, eigene Waffen) ersetzen die KayKit-Ausrüstung bewusst
		if not equip_missing.is_empty() and not c.get("own_weapons", false):
			all_ok = false
		print("  Neue Körperteile (", names_c.filter(func(n): return not (n in names_o)).size(), "): ", names_c.filter(func(n): return not (n in names_o)))

		custom.free()
		original.free()

	print("\n", "ALLES OK" if all_ok else "ES GIBT PROBLEME – siehe oben")
	quit()
