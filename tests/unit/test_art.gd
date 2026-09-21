extends RefCounted

func run(t: SceneTree) -> void:
	for archetype: StringName in ArtActors.ARCHETYPES:
		var model := VisualFactory.actor(archetype)
		t.check(_meshes(model) > 20, String(archetype) + " is an articulated assembled actor")
		t.check(_has_no_collision(model), String(archetype) + " art has no gameplay collision")
		for pivot: String in ["Head", "LeftArm", "RightArm", "LeftLeg", "RightLeg"]:
			t.check(model.has_node(pivot), String(archetype) + " exposes " + pivot)
		for state: StringName in [&"idle", &"walk", &"windup", &"attack", &"block", &"stagger", &"death", &"phase_two", &"thrust", &"sweep"]:
			VisualFactory.pose(model, state, 0.5)
			t.check(model.transform.is_finite(), String(archetype) + " finite " + String(state) + " pose")
		VisualFactory.pose(model, &"idle", 0)
		t.check(model.rotation == Vector3.ZERO, "idle clears actor death/stagger rotation")
		_check_saved(t, "actors", archetype)
		model.free()
	var items: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/items/items.json"))
	for item: Dictionary in items:
		t.check(ResourceLoader.exists(String(item.icon_path)), String(item.id) + " has a loadable native icon")
		var model := VisualFactory.gear(StringName(item.id))
		t.check(_meshes(model) > 0, String(item.id) + " has a visible model")
		t.check(_has_no_collision(model), String(item.id) + " is collision-free art")
		for pose: StringName in [&"idle", &"light", &"heavy", &"guard", &"parry_recoil", &"healing"]:
			VisualFactory.pose_gear(model, pose, 0.5)
			t.check(model.transform.is_finite(), String(item.id) + " finite first-person pose")
		_check_saved(t, "gear", StringName(item.id))
		model.free()
	for family: StringName in ArtBuildings.FAMILIES:
		var model := VisualFactory.building(family)
		t.check(_meshes(model) > 0 and _meshes(model) <= 15, String(family) + " has bounded batched geometry")
		t.check(_has_no_collision(model), String(family) + " is collision-free architecture")
		t.check(_all_materials(model), String(family) + " has materials on every surface")
		_check_saved(t, "buildings", family)
		model.free()
	for kind: StringName in ArtProps.KINDS:
		var model := VisualFactory.prop(kind)
		t.check(_meshes(model) > 0 and _meshes(model) <= 15, String(kind) + " has bounded batched geometry")
		t.check(_has_no_collision(model), String(kind) + " is collision-free decoration")
		t.check(_all_materials(model), String(kind) + " has materials on every surface")
		_check_saved(t, "props", kind)
		if "chest" in String(kind) or kind == &"badge_locker":
			t.check(model.has_node("Lid"), String(kind) + " preserves movable Lid pivot")
		model.free()
	for key: String in ArtMesh.PALETTE:
		t.check(ArtMesh.material(key).roughness >= 0.6, key + " avoids glossy plastic")
	for texture: String in ["stone", "timber", "linen", "parchment", "palette"]:
		var loaded: Texture2D = load("res://assets/textures/" + texture + ".png")
		t.check(loaded.get_width() == 128 and loaded.get_height() == 128, texture + " has original 128px source")

func _check_saved(t: SceneTree, category: String, id: StringName) -> void:
	var resource: PackedScene = load("res://assets/models/%s/%s.tscn" % [category, id])
	t.check(resource != null, String(id) + " reusable scene loads")
	if resource != null:
		var model := resource.instantiate()
		t.check(_meshes(model) > 0 and _all_materials(model), String(id) + " saved scene preserves visual resources")
		model.free()

func _all_materials(node: Node) -> bool:
	if node is MeshInstance3D and (node as MeshInstance3D).material_override == null:
		return false
	for child: Node in node.get_children():
		if not _all_materials(child):
			return false
	return true

func _meshes(node: Node) -> int:
	var total: int = 1 if node is MeshInstance3D else 0
	for child: Node in node.get_children():
		total += _meshes(child)
	return total

func _has_no_collision(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D:
		return false
	for child: Node in node.get_children():
		if not _has_no_collision(child):
			return false
	return true
