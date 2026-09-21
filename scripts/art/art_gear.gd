class_name ArtGear
extends RefCounted

static func make(id: StringName) -> Node3D:
	var node := ArtMesh.root(String(id))
	node.set_meta("item_id", id)
	match id:
		&"rusted_sword", &"arming_sword", &"falchion", &"watchblade", &"spear", &"keeper_mace":
			_weapon(node, id)
		&"wooden_buckler", &"kite_shield":
			_shield(node, id)
		&"patched_coat", &"leather_jack", &"mail_coat":
			_coat(node, id)
		&"bandage":
			ArtMesh.cylinder(node, "LinenRoll", 0.09, 0.09, 0.16, Vector3(0, 0.08, 0), "parchment")
			for y: float in [0.025, 0.075, 0.125]:
				ArtMesh.cylinder(node, "Winding", 0.094, 0.094, 0.012, Vector3(0, y, 0), "linen")
		&"bread":
			var loaf := ArtMesh.sphere(node, "Crust", 0.15, Vector3(0, 0.09, 0), "ochre")
			loaf.scale = Vector3(1, 0.65, 1.6)
			for z: float in [-0.09, 0.0, 0.09]:
				ArtMesh.box(node, "ScoredCrust", Vector3(0.13, 0.012, 0.025), Vector3(0, 0.183, z), "warm")
		&"tonic", &"cart_medicine", &"camp_medicine":
			ArtMesh.cylinder(node, "ClayBottle", 0.085, 0.07, 0.18, Vector3(0, 0.10, 0), "reed" if id == &"tonic" else "rust")
			ArtMesh.cylinder(node, "Neck", 0.035, 0.035, 0.06, Vector3(0, 0.22, 0), "wood")
			ArtMesh.box(node, "Label", Vector3(0.10, 0.09, 0.006), Vector3(0, 0.11, -0.079), "parchment")
			ArtMesh.box(node, "LabelMark", Vector3(0.045, 0.018, 0.008), Vector3(0, 0.11, -0.084), "rust")
		&"toll_receipt", &"orra_charter":
			ArtMesh.box(node, "Parchment", Vector3(0.28, 0.38, 0.016), Vector3(0, 0.19, 0), "parchment")
			for row: int in 5:
				ArtMesh.box(node, "Writing", Vector3(0.16 if row % 2 == 0 else 0.19, 0.007, 0.004), Vector3(0, 0.29 - row * 0.035, -0.011), "wood")
			var seal := ArtMesh.cylinder(node, "WaxSeal", 0.033, 0.033, 0.012, Vector3(0.06, 0.06, -0.02), "rust")
			seal.rotation.x = PI / 2
		&"grain_ledger":
			ArtMesh.box(node, "Binding", Vector3(0.3, 0.4, 0.075), Vector3(0, 0.2, 0), "rust")
			ArtMesh.box(node, "Pages", Vector3(0.27, 0.36, 0.064), Vector3(0.01, 0.2, 0), "parchment")
			ArtMesh.box(node, "Strap", Vector3(0.31, 0.035, 0.083), Vector3(0, 0.2, 0), "ochre")
		&"rookwatch_seal", &"ada_badge", &"hobb_ring":
			var ring := TorusMesh.new()
			ring.inner_radius = 0.055 if id == &"hobb_ring" else 0.075
			ring.outer_radius = 0.074 if id == &"hobb_ring" else 0.11
			ring.rings = 12
			ring.ring_segments = 6
			var mesh := ArtMesh.mesh(node, "ForgedRing", ring, Vector3(0, 0.11, 0), "ochre")
			mesh.rotation.x = PI / 2
			if id != &"hobb_ring":
				ArtMesh.prism(node, "RookEmblem", PackedVector2Array([Vector2(-0.055, 0), Vector2(0.055, 0), Vector2(0.045, 0.12), Vector2(0, 0.08), Vector2(-0.045, 0.12)]), 0.025, Vector3(0, 0.075, 0), "iron")
		&"smith_hammer":
			ArtMesh.cylinder(node, "Handle", 0.025, 0.025, 0.45, Vector3(0, 0.2, 0), "wood")
			ArtMesh.box(node, "HammerHead", Vector3(0.24, 0.12, 0.11), Vector3(0, 0.44, 0), "dark_iron")
		&"ferry_blankets":
			for index: int in 3:
				ArtMesh.box(node, "FoldedBlanket", Vector3(0.4, 0.075, 0.3), Vector3(0, 0.04 + index * 0.078, 0), "rust" if index == 1 else "linen")
			ArtMesh.box(node, "Twine", Vector3(0.035, 0.25, 0.31), Vector3(0, 0.12, 0), "timber")
		&"votive_candle":
			ArtMesh.cylinder(node, "Wax", 0.046, 0.042, 0.2, Vector3(0, 0.1, 0), "parchment")
			ArtMesh.cylinder(node, "Flame", 0.028, 0, 0.08, Vector3(0, 0.24, 0), "flame", 5)
		_:
			push_error("Unknown gear art: " + String(id))
	return node

static func _weapon(node: Node3D, id: StringName) -> void:
	var long_shaft: bool = id == &"spear"
	var shaft_height: float = 1.8 if long_shaft else 0.22
	ArtMesh.cylinder(node, "Grip", 0.026, 0.026, shaft_height, Vector3(0, 0.65 if long_shaft else 0, 0), "wood", 8)
	if id == &"keeper_mace":
		ArtMesh.cylinder(node, "Shaft", 0.035, 0.035, 0.75, Vector3(0, 0.3, 0), "dark_iron")
		ArtMesh.cylinder(node, "StoneHead", 0.15, 0.10, 0.26, Vector3(0, 0.75, 0), "stone", 6)
		return
	var blade_base: float = 1.55 if long_shaft else 0.16
	var blade_length: float = 0.42 if long_shaft else 0.88
	var blade_width: float = 0.07 if long_shaft else 0.055
	if id == &"falchion":
		ArtMesh.prism(node, "CurvedBlade", PackedVector2Array([Vector2(-0.05, 0), Vector2(0.055, 0), Vector2(0.14, 0.64), Vector2(0.08, 0.92), Vector2(-0.02, 0.76)]), 0.025, Vector3(0, blade_base, 0), "iron")
	else:
		ArtMesh.prism(node, "Blade", PackedVector2Array([Vector2(-blade_width, 0), Vector2(blade_width, 0), Vector2(blade_width * 0.7, blade_length * 0.78), Vector2(0, blade_length), Vector2(-blade_width * 0.7, blade_length * 0.78)]), 0.022, Vector3(0, blade_base, 0), "fog" if id == &"watchblade" else "iron")
		ArtMesh.box(node, "Fuller", Vector3(0.012, blade_length * 0.61, 0.024), Vector3(0, blade_base + blade_length * 0.35, 0), "rust" if id == &"rusted_sword" else "dark_iron")
	if not long_shaft:
		ArtMesh.box(node, "Crossguard", Vector3(0.30 if id == &"watchblade" else 0.24, 0.045, 0.06), Vector3(0, 0.135, 0), "ochre" if id == &"watchblade" else "dark_iron")
		ArtMesh.sphere(node, "Pommel", 0.05, Vector3(0, -0.145, 0), "ochre" if id == &"watchblade" else "dark_iron")
		for y: float in [-0.07, -0.025, 0.025, 0.07]:
			ArtMesh.cylinder(node, "GripWrap", 0.029, 0.029, 0.012, Vector3(0, y, 0), "timber")

static func _shield(node: Node3D, id: StringName) -> void:
	if id == &"wooden_buckler":
		var rim := ArtMesh.cylinder(node, "IronRim", 0.30, 0.30, 0.065, Vector3.ZERO, "dark_iron", 12)
		rim.rotation.x = PI / 2
		var face := ArtMesh.cylinder(node, "OakFace", 0.273, 0.273, 0.075, Vector3(0, 0, -0.013), "wood", 12)
		face.rotation.x = PI / 2
		for x: float in [-0.14, 0, 0.14]:
			ArtMesh.box(node, "PlankJoin", Vector3(0.012, 0.46, 0.01), Vector3(x, 0, -0.054), "timber")
		ArtMesh.sphere(node, "ShieldBoss", 0.09, Vector3(0, 0, -0.07), "iron").scale.z = 0.6
	else:
		var outline := PackedVector2Array([Vector2(-0.28, 0.36), Vector2(0, 0.45), Vector2(0.28, 0.36), Vector2(0.26, -0.14), Vector2(0, -0.62), Vector2(-0.26, -0.14)])
		ArtMesh.prism(node, "IronRim", outline, 0.075, Vector3.ZERO, "iron")
		ArtMesh.prism(node, "PaintedFace", outline, 0.022, Vector3(0, 0, -0.05), "rust").scale = Vector3(0.9, 0.92, 1)
		ArtMesh.box(node, "HeraldicPale", Vector3(0.067, 0.64, 0.02), Vector3(0, 0.045, -0.068), "parchment")
		ArtMesh.box(node, "HeraldicBar", Vector3(0.39, 0.065, 0.02), Vector3(0, 0.18, -0.07), "parchment")

static func _coat(node: Node3D, id: StringName) -> void:
	var color := "linen" if id == &"patched_coat" else ("wood" if id == &"leather_jack" else "dark_iron")
	ArtMesh.prism(node, "Coat", PackedVector2Array([Vector2(-0.24, 0), Vector2(0.24, 0), Vector2(0.20, 0.53), Vector2(0.11, 0.59), Vector2(-0.11, 0.59), Vector2(-0.20, 0.53)]), 0.24, Vector3.ZERO, color)
	ArtMesh.box(node, "Belt", Vector3(0.47, 0.052, 0.26), Vector3(0, 0.15, 0), "timber")
	if id == &"mail_coat":
		for y: int in 6:
			for x: int in 6:
				ArtMesh.box(node, "RivetedMail", Vector3(0.045, 0.018, 0.012), Vector3(-0.17 + x * 0.065, 0.23 + y * 0.045, -0.126), "iron")
	elif id == &"patched_coat":
		ArtMesh.box(node, "SewnPatch", Vector3(0.09, 0.11, 0.008), Vector3(0.1, 0.33, -0.126), "rust")
