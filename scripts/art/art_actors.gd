class_name ArtActors
extends RefCounted

const ARCHETYPES: Array[StringName] = [&"cutpurse", &"levy_spearman", &"deserter_raider", &"hollow_keeper", &"captain_rusk", &"mara_venn", &"oswin_pike", &"tamsin_reed", &"sister_elian", &"hobb_fenwick", &"ada_vey", &"wren_kest"]

static func make(id: StringName) -> Node3D:
	var node := ArtMesh.root(String(id))
	node.set_meta("archetype", id)
	var armored: bool = id in [&"levy_spearman", &"deserter_raider", &"captain_rusk", &"ada_vey"]
	var stone: bool = id == &"hollow_keeper"
	var cloth: String = _cloth(id)
	var metal: String = "stone" if stone else "iron"
	var skin: String = "stone" if stone else ("skin_dark" if id in [&"oswin_pike", &"wren_kest"] else "skin")
	# Torso narrows into the belt; shoulder breadth remains visibly human.
	ArtMesh.prism(node, "Torso", PackedVector2Array([Vector2(-0.18, 0), Vector2(0.18, 0), Vector2(0.25, 0.42), Vector2(0.16, 0.50), Vector2(-0.16, 0.50), Vector2(-0.25, 0.42)]), 0.30, Vector3(0, 0.91, 0), metal if armored or stone else cloth)
	ArtMesh.prism(node, "TunicSkirt", PackedVector2Array([Vector2(-0.26, 0), Vector2(0.26, 0), Vector2(0.18, 0.25), Vector2(-0.18, 0.25)]), 0.32, Vector3(0, 0.73, 0), cloth)
	ArtMesh.box(node, "Belt", Vector3(0.40, 0.063, 0.33), Vector3(0, 0.95, 0), "timber")
	ArtMesh.box(node, "Buckle", Vector3(0.065, 0.065, 0.025), Vector3(0, 0.951, -0.18), "ochre")
	if armored:
		ArtMesh.prism(node, "Surcoat", PackedVector2Array([Vector2(-0.10, 0), Vector2(0.10, 0), Vector2(0.14, 0.51), Vector2(-0.14, 0.51)]), 0.02, Vector3(0, 0.80, -0.169), cloth)
		ArtMesh.box(node, "Collar", Vector3(0.30, 0.07, 0.34), Vector3(0, 1.41, 0), "dark_iron")
		if id in [&"captain_rusk", &"ada_vey"]:
			ArtMesh.box(node, "RankPale", Vector3(0.03, 0.29, 0.01), Vector3(0, 1.11, -0.184), "warm")
	if id in [&"sister_elian", &"hollow_keeper"]:
		ArtMesh.cylinder(node, "Robe", 0.30, 0.21, 0.72, Vector3(0, 0.58, 0.02), cloth, 8)
	for side: int in [-1, 1]:
		var prefix: String = "Left" if side < 0 else "Right"
		var leg := ArtMesh.pivot(node, prefix + "Leg", Vector3(side * 0.12, 0.83, 0))
		ArtMesh.cylinder(leg, "Thigh", 0.084, 0.096, 0.34, Vector3(0, -0.15, 0), cloth, 6)
		ArtMesh.sphere(leg, "Knee", 0.093, Vector3(0, -0.36, -0.015), metal if armored or stone else "wood")
		ArtMesh.cylinder(leg, "Greave", 0.073, 0.090, 0.31, Vector3(0, -0.55, 0), metal if armored or stone else "timber", 6)
		ArtMesh.prism(leg, "Boot", PackedVector2Array([Vector2(-0.09, -0.82), Vector2(0.09, -0.82), Vector2(0.085, -0.66), Vector2(-0.085, -0.66)]), 0.32, Vector3(0, 0, -0.07), "stone" if stone else "timber")
		ArtMesh.box(leg, "BootSole", Vector3(0.19, 0.032, 0.34), Vector3(0, -0.805, -0.07), "peat")
		var arm := ArtMesh.pivot(node, prefix + "Arm", Vector3(side * 0.29, 1.34, 0))
		arm.rotation.z = side * 0.07
		ArtMesh.cylinder(arm, "UpperArm", 0.07, 0.086, 0.27, Vector3(0, -0.12, 0), cloth, 6)
		if armored or stone:
			var shoulder := ArtMesh.sphere(arm, "Pauldron", 0.14, Vector3(0, 0.025, 0), metal)
			shoulder.scale = Vector3(1, 0.80, 1.16)
			ArtMesh.box(arm, "ShoulderTrim", Vector3(0.24, 0.032, 0.25), Vector3(0, -0.02, 0), "dark_iron")
		var elbow := ArtMesh.pivot(arm, "Elbow", Vector3(0, -0.28, 0))
		ArtMesh.sphere(elbow, "ElbowJoint", 0.068, Vector3.ZERO, cloth)
		ArtMesh.cylinder(elbow, "Vambrace", 0.063, 0.076, 0.24, Vector3(0, -0.12, -0.018), metal if armored or stone else "wood", 6)
		ArtMesh.box(elbow, "Gauntlet" if armored else "Hand", Vector3(0.115, 0.13, 0.12), Vector3(0, -0.28, -0.025), metal if armored else skin)
		var grip := ArtMesh.pivot(elbow, "Grip", Vector3(0, -0.29, -0.03))
		if side > 0:
			var weapon: StringName = _weapon(id)
			if weapon != &"":
				var held := ArtGear.make(weapon)
				held.rotation.x = -PI / 2
				grip.add_child(held)
		elif id in [&"deserter_raider", &"captain_rusk", &"ada_vey"]:
			var shield := ArtGear.make(&"kite_shield" if id == &"captain_rusk" else &"wooden_buckler")
			shield.position = Vector3(0, 0.05, -0.13)
			grip.add_child(shield)
	var head := ArtMesh.pivot(node, "Head", Vector3(0, 1.52, 0))
	ArtMesh.cylinder(head, "Neck", 0.065, 0.065, 0.12, Vector3(0, -0.05, 0), skin)
	var face := ArtMesh.sphere(head, "Face", 0.155, Vector3(0, 0.115, 0), skin)
	face.scale = Vector3(0.87, 1.2, 0.92)
	ArtMesh.box(head, "Nose", Vector3(0.045, 0.065, 0.06), Vector3(0, 0.11, -0.139), skin)
	for x: float in [-0.055, 0.055]:
		ArtMesh.box(head, "Eye", Vector3(0.032, 0.021, 0.01), Vector3(x, 0.155, -0.136), "peat")
	if armored:
		_helmet(head, id)
	elif id in [&"cutpurse", &"sister_elian", &"hollow_keeper", &"wren_kest"]:
		ArtMesh.cylinder(head, "HoodCrown", 0.18, 0.115, 0.13, Vector3(0, 0.29, 0.02), cloth, 6)
		for x: float in [-0.145, 0.145]:
			ArtMesh.box(head, "HoodDrape", Vector3(0.073, 0.35, 0.26), Vector3(x, 0.11, 0.025), cloth)
		ArtMesh.box(head, "HoodBack", Vector3(0.29, 0.29, 0.07), Vector3(0, 0.14, 0.14), cloth)
	else:
		ArtMesh.cylinder(head, "Hair", 0.16, 0.13, 0.12, Vector3(0, 0.26, 0.02), "fog" if id == &"hobb_fenwick" else "timber", 7)
		if id == &"hobb_fenwick":
			ArtMesh.cylinder(head, "HatBrim", 0.23, 0.23, 0.035, Vector3(0, 0.29, 0), "reed")
			ArtMesh.cylinder(head, "HatCrown", 0.15, 0.10, 0.12, Vector3(0, 0.35, 0), "reed")
	if id == &"oswin_pike":
		ArtMesh.box(node, "SmithApron", Vector3(0.35, 0.55, 0.025), Vector3(0, 1.03, -0.18), "wood")
	if id in [&"tamsin_reed", &"mara_venn"]:
		ArtMesh.box(node, "Apron", Vector3(0.31, 0.39, 0.021), Vector3(0, 0.93, -0.18), "parchment")
	if id == &"hollow_keeper":
		ArtMesh.box(head, "BurialMask", Vector3(0.20, 0.18, 0.045), Vector3(0, 0.12, -0.16), "fog")
		for x: float in [-0.055, 0.055]:
			ArtMesh.box(head, "CarvedEye", Vector3(0.034, 0.018, 0.012), Vector3(x, 0.15, -0.188), "peat")
		ArtMesh.box(node, "CarvedOath", Vector3(0.045, 0.24, 0.022), Vector3(0, 1.15, -0.17), "parchment")
	if id == &"captain_rusk":
		node.scale = Vector3.ONE * 1.055
	return node

static func _cloth(id: StringName) -> String:
	match id:
		&"levy_spearman", &"captain_rusk", &"mara_venn": return "rust"
		&"hollow_keeper", &"sister_elian": return "slate"
		&"wren_kest", &"hobb_fenwick": return "reed"
		&"ada_vey": return "moss"
		&"deserter_raider", &"oswin_pike": return "wood"
		&"tamsin_reed": return "ochre"
	return "timber"

static func _weapon(id: StringName) -> StringName:
	match id:
		&"cutpurse": return &"rusted_sword"
		&"levy_spearman": return &"spear"
		&"deserter_raider", &"wren_kest": return &"falchion"
		&"hollow_keeper": return &"keeper_mace"
		&"captain_rusk": return &"watchblade"
		&"ada_vey": return &"arming_sword"
		&"oswin_pike": return &"smith_hammer"
	return &""

static func _helmet(head: Node3D, id: StringName) -> void:
	ArtMesh.cylinder(head, "HelmetDome", 0.18, 0.10, 0.15, Vector3(0, 0.29, 0), "iron", 8)
	ArtMesh.cylinder(head, "HelmetBand", 0.19, 0.19, 0.043, Vector3(0, 0.225, 0), "dark_iron", 8)
	for x: float in [-0.145, 0.145]:
		ArtMesh.box(head, "CheekGuard", Vector3(0.05, 0.19, 0.15), Vector3(x, 0.105, -0.025), "iron")
	if id == &"captain_rusk":
		ArtMesh.box(head, "Visor", Vector3(0.27, 0.10, 0.07), Vector3(0, 0.13, -0.145), "iron")
		ArtMesh.box(head, "EyeSlit", Vector3(0.19, 0.018, 0.009), Vector3(0, 0.155, -0.184), "peat")
		ArtMesh.prism(head, "RussetCrest", PackedVector2Array([Vector2(-0.025, 0), Vector2(0.025, 0), Vector2(0.025, 0.18), Vector2(-0.025, 0.16)]), 0.24, Vector3(0, 0.36, 0), "rust")
	else:
		ArtMesh.box(head, "NasalGuard", Vector3(0.037, 0.20, 0.035), Vector3(0, 0.15, -0.16), "iron")
