class_name ArtProps
extends RefCounted

const KINDS: Array[StringName] = [&"oak", &"pine", &"reeds", &"rock", &"cart", &"chest", &"medicine_chest", &"ledger_chest", &"badge_locker", &"seal_chest", &"writ_table", &"reed_chime", &"stone_chime", &"flame_chime", &"shrine", &"banner_crown", &"banner_valley", &"banner_free", &"sign", &"toll_notice", &"corpse_loot", &"barrel", &"crate", &"well", &"lantern", &"door", &"bed", &"bench", &"sack", &"candle"]

static func make(kind: StringName) -> Node3D:
	var node := ArtMesh.root(String(kind))
	node.set_meta("prop_kind", kind)
	match kind:
		&"oak", &"pine", &"reeds", &"rock": _nature(node, kind)
		&"chest", &"medicine_chest", &"ledger_chest", &"badge_locker", &"seal_chest": _chest(node, kind)
		&"reed_chime", &"stone_chime", &"flame_chime": _chime(node, kind)
		&"banner_crown", &"banner_valley", &"banner_free": _banner(node, kind)
		&"shrine": _shrine(node)
		&"writ_table":
			_table(node)
			var writ := ArtGear.make(&"orra_charter")
			writ.rotation.x = -PI / 2
			writ.position = Vector3(-0.3, 0.87, 0.05)
			node.add_child(writ)
			var seal := ArtGear.make(&"rookwatch_seal")
			seal.rotation.x = -PI / 2
			seal.position = Vector3(0.33, 0.88, -0.05)
			node.add_child(seal)
			ArtMesh.cylinder(node, "InkPot", 0.045, 0.035, 0.075, Vector3(0.4, 0.92, 0.19), "peat")
		&"sign", &"toll_notice":
			ArtMesh.box(node, "Post", Vector3(0.13, 1.7, 0.13), Vector3(0, 0.85, 0), "timber")
			ArtMesh.prism(node, "CarvedBoard", PackedVector2Array([Vector2(-0.65, -0.17), Vector2(0.43, -0.17), Vector2(0.65, 0), Vector2(0.43, 0.17), Vector2(-0.65, 0.17)]), 0.075, Vector3(0, 1.43, 0), "wood")
			if kind == &"toll_notice":
				var paper := ArtGear.make(&"toll_receipt")
				paper.position = Vector3(0, 1.1, -0.06)
				node.add_child(paper)
			else:
				for index: int in 3:
					ArtMesh.box(node, "RoadMark", Vector3(0.11, 0.027, 0.008), Vector3(-0.3 + index * 0.16, 1.43, -0.043), "parchment")
		&"corpse_loot":
			ArtMesh.sphere(node, "LeatherPurse", 0.18, Vector3(0, 0.12, 0), "wood").scale = Vector3(1, 0.68, 0.8)
			ArtMesh.cylinder(node, "GatheredNeck", 0.08, 0.04, 0.10, Vector3(0, 0.26, 0), "timber", 6)
			ArtMesh.cylinder(node, "Crown", 0.047, 0.047, 0.015, Vector3(0.17, 0.02, -0.09), "ochre", 8)
		&"barrel":
			ArtMesh.cylinder(node, "OakStaves", 0.29, 0.27, 0.76, Vector3(0, 0.38, 0), "wood", 10)
			for y: float in [0.10, 0.37, 0.65]:
				ArtMesh.cylinder(node, "Hoop", 0.299, 0.299, 0.04, Vector3(0, y, 0), "dark_iron", 10)
			ArtMesh.cylinder(node, "Lid", 0.265, 0.265, 0.03, Vector3(0, 0.775, 0), "timber", 10)
		&"crate":
			ArtMesh.box(node, "Boards", Vector3(0.65, 0.57, 0.55), Vector3(0, 0.29, 0), "wood")
			for x: float in [-0.25, 0.25]:
				ArtMesh.box(node, "Brace", Vector3(0.075, 0.61, 0.60), Vector3(x, 0.3, 0), "timber")
			ArtMesh.beam(node, "Diagonal", Vector3(-0.29, 0.05, -0.29), Vector3(0.29, 0.55, -0.29), 0.08, 0.04, "timber")
		&"well":
			for index: int in 10:
				var angle: float = index * TAU / 10
				var stone := ArtMesh.box(node, "WellCoping", Vector3(0.45, 0.72, 0.35), Vector3(sin(angle) * 0.65, 0.36, cos(angle) * 0.65), "stone")
				stone.rotation.y = angle
			for x: float in [-0.95, 0.95]:
				ArtMesh.box(node, "TimberUpright", Vector3(0.18, 2.3, 0.18), Vector3(x, 1.15, 0), "timber")
			ArtMesh.box(node, "WellBeam", Vector3(2.35, 0.20, 0.20), Vector3(0, 2.25, 0), "wood")
			ArtMesh.cylinder(node, "Rope", 0.014, 0.014, 1.6, Vector3(0, 1.37, 0), "linen", 6)
		&"lantern": _lantern(node)
		&"door":
			ArtMesh.box(node, "OakDoor", Vector3(1.25, 2.2, 0.12), Vector3(0, 1.1, 0), "wood")
			for x: float in [-0.4, -0.2, 0, 0.2, 0.4]:
				ArtMesh.box(node, "PlankJoin", Vector3(0.012, 2.15, 0.01), Vector3(x, 1.1, -0.065), "timber")
			for y: float in [0.4, 1.65]:
				ArtMesh.box(node, "StrapHinge", Vector3(0.87, 0.075, 0.04), Vector3(-0.12, y, -0.075), "dark_iron")
			ArtMesh.sphere(node, "Handle", 0.055, Vector3(0.44, 1.02, -0.11), "ochre")
		&"bed":
			ArtMesh.box(node, "BedFrame", Vector3(1.0, 0.25, 2), Vector3(0, 0.22, 0), "timber")
			ArtMesh.box(node, "Ticking", Vector3(0.95, 0.13, 1.94), Vector3(0, 0.4, 0), "linen")
			ArtMesh.box(node, "Blanket", Vector3(0.97, 0.14, 1.28), Vector3(0, 0.45, 0.28), "rust")
			ArtMesh.box(node, "Pillow", Vector3(0.65, 0.11, 0.37), Vector3(0, 0.52, -0.68), "parchment")
		&"bench": _table(node, true)
		&"sack":
			ArtMesh.sphere(node, "GrainSack", 0.32, Vector3(0, 0.35, 0), "linen").scale = Vector3(0.8, 1.15, 0.8)
			ArtMesh.cylinder(node, "TiedMouth", 0.12, 0.07, 0.15, Vector3(0, 0.74, 0), "timber", 6)
		&"candle": node.add_child(ArtGear.make(&"votive_candle"))
		&"cart": _cart(node)
		_:
			push_error("Unknown prop art: " + String(kind))
	return node

static func _nature(node: Node3D, kind: StringName) -> void:
	match kind:
		&"oak":
			ArtMesh.cylinder(node, "Trunk", 0.34, 0.17, 3.4, Vector3(0, 1.7, 0), "timber", 7)
			for branch: Vector3 in [Vector3(-1.2, 3.3, 0.2), Vector3(0.8, 3.5, 0.6), Vector3(0.1, 3.8, -0.9)]:
				ArtMesh.beam(node, "Branch", Vector3(0, 1.9, 0), branch, 0.22, 0.2, "wood")
			for crown: Vector3 in [Vector3(-1.2, 3.8, 0), Vector3(1, 4.2, 0.4), Vector3(0, 4.6, -0.7), Vector3(0, 3.7, 1)]:
				ArtMesh.sphere(node, "LeafCrown", 1.55, crown, "moss" if crown.x < 0 else "reed").scale.y = 0.8
		&"pine":
			ArtMesh.cylinder(node, "Trunk", 0.22, 0.10, 4.5, Vector3(0, 2.25, 0), "timber", 6)
			for index: int in 4:
				ArtMesh.cylinder(node, "NeedleTier", 1.5 - index * 0.29, 0.08, 1.8, Vector3(0, 2.2 + index * 0.9, 0), "moss" if index % 2 == 0 else "slate", 7)
		&"reeds":
			for index: int in 7:
				var x: float = sin(index * 2.3) * 0.28
				var z: float = cos(index * 1.8) * 0.25
				var h: float = 0.6 + (index % 3) * 0.17
				ArtMesh.beam(node, "ReedStem", Vector3(x, 0, z), Vector3(x + 0.1, h, z), 0.018, 0.024, "reed")
				ArtMesh.cylinder(node, "SeedHead", 0.035, 0.022, 0.16, Vector3(x + 0.1, h, z), "rust", 5)
		&"rock":
			var rock := ArtMesh.sphere(node, "WeatheredBoulder", 1, Vector3(0, 0.5, 0), "stone")
			rock.scale = Vector3(1.35, 0.7, 0.91)
			rock.rotation.y = 0.4
			ArtMesh.sphere(node, "LichenFacet", 0.49, Vector3(-0.4, 0.95, 0.1), "moss").scale = Vector3(1, 0.3, 1)

static func _chest(node: Node3D, kind: StringName) -> void:
	var tall: bool = kind == &"badge_locker"
	var height: float = 1.4 if tall else 0.52
	var paint: String = "medicine_blue" if kind == &"medicine_chest" else "wood"
	ArtMesh.box(node, "OakBox", Vector3(0.95, height, 0.65), Vector3(0, height / 2, 0), paint)
	for x: float in [-0.37, 0.37]:
		ArtMesh.box(node, "IronBinding", Vector3(0.055, height + 0.02, 0.68), Vector3(x, height / 2, 0), "dark_iron")
	var lid := ArtMesh.pivot(node, "Lid", Vector3(0, height, 0.32))
	ArtMesh.prism(lid, "CurvedLid", PackedVector2Array([Vector2(-0.49, 0), Vector2(0.49, 0), Vector2(0.36, 0.16), Vector2(-0.36, 0.16)]), 0.68, Vector3(0, 0, -0.32), paint)
	ArtMesh.box(node, "Latch", Vector3(0.075, 0.14, 0.04), Vector3(0, height - 0.04, -0.35), "ochre")
	if kind != &"chest":
		ArtMesh.box(node, "PaintedPlaque", Vector3(0.32, 0.23, 0.015), Vector3(0, height * 0.5, -0.34), "rust" if kind == &"seal_chest" else "parchment")
		if kind == &"medicine_chest":
			ArtMesh.box(node, "MedicineMark", Vector3(0.18, 0.04, 0.02), Vector3(0, height * 0.5, -0.36), "rust")
			ArtMesh.box(node, "MedicineStem", Vector3(0.04, 0.16, 0.02), Vector3(0, height * 0.5, -0.36), "rust")
		else:
			ArtMesh.prism(node, "Emblem", PackedVector2Array([Vector2(-0.08, 0), Vector2(0.08, 0), Vector2(0.06, 0.13), Vector2(0, 0.09), Vector2(-0.06, 0.13)]), 0.018, Vector3(0, height * 0.5 - 0.06, -0.36), "ochre" if kind == &"seal_chest" else "ink")

static func _chime(node: Node3D, kind: StringName) -> void:
	ArtMesh.box(node, "StoneFoot", Vector3(0.8, 0.15, 0.6), Vector3(0, 0.075, 0), "stone")
	for x: float in [-0.3, 0.3]:
		ArtMesh.box(node, "ChimePost", Vector3(0.065, 1.8, 0.07), Vector3(x, 0.97, 0), "timber")
	ArtMesh.box(node, "Crossbeam", Vector3(0.82, 0.08, 0.10), Vector3(0, 1.86, 0), "wood")
	var color: String = "reed" if kind == &"reed_chime" else ("fog" if kind == &"stone_chime" else "rust")
	for index: int in 3:
		var length: float = 0.6 + index * 0.13
		ArtMesh.cylinder(node, "HangingChime", 0.055, 0.065, length, Vector3(-0.18 + index * 0.18, 1.62 - length / 2, 0), color, 6)
		ArtMesh.cylinder(node, "Cord", 0.008, 0.008, 0.22, Vector3(-0.18 + index * 0.18, 1.74, 0), "linen", 4)
	ArtMesh.box(node, "SymbolTablet", Vector3(0.24, 0.22, 0.035), Vector3(0, 0.45, -0.04), color)
	var symbol: String = "I" if kind == &"reed_chime" else ("II" if kind == &"stone_chime" else "III")
	for index: int in symbol.length():
		ArtMesh.box(node, "CarvedStroke", Vector3(0.018, 0.12, 0.006), Vector3((index - (symbol.length() - 1) / 2.0) * 0.05, 0.45, -0.061), "parchment" if kind != &"stone_chime" else "ink")

static func _banner(node: Node3D, kind: StringName) -> void:
	ArtMesh.cylinder(node, "Pole", 0.04, 0.032, 3.2, Vector3(0, 1.6, 0), "timber", 6)
	ArtMesh.box(node, "Crossbar", Vector3(1.1, 0.055, 0.055), Vector3(0, 2.9, 0), "ochre")
	var color: String = "rust" if kind == &"banner_crown" else ("reed" if kind == &"banner_valley" else "parchment")
	ArtMesh.prism(node, "BannerCloth", PackedVector2Array([Vector2(-0.45, 0), Vector2(0, -0.18), Vector2(0.45, 0), Vector2(0.45, 1.35), Vector2(-0.45, 1.35)]), 0.018, Vector3(0, 1.55, 0), color)
	if kind == &"banner_free":
		ArtMesh.beam(node, "OpenRoadLeft", Vector3(-0.16, 1.7, -0.02), Vector3(-0.06, 2.6, -0.02), 0.035, 0.008, "reed")
		ArtMesh.beam(node, "OpenRoadRight", Vector3(0.16, 1.7, -0.02), Vector3(0.06, 2.6, -0.02), 0.035, 0.008, "reed")
	else:
		ArtMesh.prism(node, "Heraldry", PackedVector2Array([Vector2(-0.2, 0), Vector2(0.2, 0), Vector2(0.2, 0.31), Vector2(0.09, 0.19), Vector2(0, 0.35), Vector2(-0.09, 0.19), Vector2(-0.2, 0.31)]), 0.008, Vector3(0, 2.15, -0.02), "parchment")

static func _shrine(node: Node3D) -> void:
	ArtMesh.box(node, "ShrineStep", Vector3(1.5, 0.18, 1.25), Vector3(0, 0.09, 0), "stone")
	ArtMesh.box(node, "Altar", Vector3(1, 0.72, 0.65), Vector3(0, 0.54, 0.15), "slate")
	ArtMesh.prism(node, "OathStone", PackedVector2Array([Vector2(-0.38, 0), Vector2(0.38, 0), Vector2(0.38, 0.9), Vector2(0, 1.25), Vector2(-0.38, 0.9)]), 0.2, Vector3(0, 0.9, 0.28), "stone")
	ArtMesh.box(node, "OathMark", Vector3(0.045, 0.55, 0.018), Vector3(0, 1.5, 0.17), "parchment")
	ArtMesh.box(node, "OathCrossbar", Vector3(0.34, 0.045, 0.018), Vector3(0, 1.65, 0.17), "parchment")
	for x: float in [-0.38, 0.38]:
		var candle := ArtGear.make(&"votive_candle")
		candle.position = Vector3(x, 0.91, -0.02)
		node.add_child(candle)

static func _table(node: Node3D, bench: bool = false) -> void:
	var h: float = 0.46 if bench else 0.85
	ArtMesh.box(node, "PlankTop", Vector3(1.5, 0.09, 0.45 if bench else 0.82), Vector3(0, h, 0), "wood")
	for x: float in [-0.61, 0.61]:
		ArtMesh.box(node, "Trestle", Vector3(0.12, h, 0.55 if not bench else 0.36), Vector3(x, h / 2, 0), "timber")
	ArtMesh.box(node, "Stretcher", Vector3(1.3, 0.09, 0.09), Vector3(0, h * 0.3, 0), "timber")

static func _lantern(node: Node3D) -> void:
	ArtMesh.cylinder(node, "CageFoot", 0.14, 0.14, 0.05, Vector3(0, 0.025, 0), "dark_iron", 6)
	ArtMesh.cylinder(node, "WaxLight", 0.06, 0.04, 0.20, Vector3(0, 0.15, 0), "flame", 5)
	for x: float in [-0.09, 0.09]:
		for z: float in [-0.09, 0.09]:
			ArtMesh.box(node, "CageBar", Vector3(0.016, 0.33, 0.016), Vector3(x, 0.18, z), "dark_iron")
	ArtMesh.cylinder(node, "RainCap", 0.17, 0.045, 0.11, Vector3(0, 0.39, 0), "dark_iron", 6)

static func _cart(node: Node3D) -> void:
	ArtMesh.box(node, "CartBed", Vector3(1.5, 0.13, 2.2), Vector3(0, 0.65, 0), "wood")
	for x: float in [-0.76, 0.76]:
		for y: float in [0.83, 1.02]:
			ArtMesh.box(node, "SideRail", Vector3(0.08, 0.12, 2.25), Vector3(x, y, 0), "wood")
		ArtMesh.beam(node, "CartShaft", Vector3(x, 0.6, -0.6), Vector3(x * 0.8, 0.5, -2.65), 0.09, 0.09, "timber")
	for x: float in [-0.94, 0.94]:
		var wheel := ArtMesh.cylinder(node, "Wheel", 0.55, 0.55, 0.12, Vector3(x, 0.55, 0.25), "timber", 12)
		wheel.rotation.z = PI / 2
		var hub := ArtMesh.cylinder(node, "WheelHub", 0.12, 0.12, 0.18, Vector3(x, 0.55, 0.25), "iron", 8)
		hub.rotation.z = PI / 2
		for angle: float in [0, PI / 3, PI * 2 / 3]:
			var spoke := ArtMesh.box(node, "WheelSpoke", Vector3(0.14, 0.95, 0.06), Vector3(x, 0.55, 0.25), "wood")
			spoke.rotation.x = angle
