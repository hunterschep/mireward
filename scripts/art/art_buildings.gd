class_name ArtBuildings
extends RefCounted
## Original modular architecture. Visuals only; world construction owns collision.

const FAMILIES: Array[StringName] = [&"cottage", &"inn", &"forge", &"road_gate", &"wall", &"keep", &"monastery_arch", &"monastery_tower", &"crypt_room", &"undercroft_room", &"bridge", &"ferry", &"ruined_watchtower", &"tent", &"kiln"]

static func make(family: StringName) -> Node3D:
	var node := ArtMesh.root(String(family))
	match family:
		&"cottage", &"inn", &"forge": _house(node, family)
		&"road_gate": _gate(node)
		&"wall": _wall(node)
		&"keep": _keep(node)
		&"monastery_arch": _arch(node, 3.0, 3.4, 0.75)
		&"monastery_tower": _tower(node, false)
		&"ruined_watchtower": _tower(node, true)
		&"crypt_room", &"undercroft_room": _room(node, family == &"crypt_room")
		&"bridge", &"ferry": _crossing(node, family == &"ferry")
		&"tent": _tent(node)
		&"kiln": _kiln(node)
		_: push_error("Unknown building family: " + String(family))
	return node

static func _shell(node: Node3D, width: float, depth: float, height: float, color: String, door: float = 1.6) -> void:
	ArtMesh.box(node, "Floor", Vector3(width, 0.12, depth), Vector3(0, 0.06, 0), "stone")
	for side: float in [-1.0, 1.0]:
		ArtMesh.box(node, "SideWall", Vector3(0.28, height, depth), Vector3(side * (width - 0.28) / 2, height / 2, 0), color)
		var flank := (width - door) / 2
		ArtMesh.box(node, "DoorFlank", Vector3(flank, height, 0.3), Vector3(side * (width + door) / 4, height / 2, -depth / 2), color)
		ArtMesh.box(node, "DoorPost", Vector3(0.17, 2.7, 0.4), Vector3(side * (door + 0.17) / 2, 1.35, -depth / 2), "timber")
	ArtMesh.box(node, "DoorHead", Vector3(door, height - 2.5, 0.3), Vector3(0, (height + 2.5) / 2, -depth / 2), color)
	ArtMesh.box(node, "DoorLintel", Vector3(door + 0.4, 0.2, 0.44), Vector3(0, 2.6, -depth / 2), "timber")
	ArtMesh.box(node, "RearWall", Vector3(width, height, 0.3), Vector3(0, height / 2, depth / 2), color)

static func _roof(node: Node3D, width: float, depth: float, eave: float, color: String, rise: float = 1.75) -> void:
	var run := width / 2 + 0.4
	var slope := Vector2(run, rise).length()
	for side: float in [-1.0, 1.0]:
		for tile: int in 7:
			var tint := color if tile % 4 != 1 else "slate"
			var panel := ArtMesh.box(node, "RoofCourse", Vector3(slope, 0.17, (depth + 1.0) / 7 + 0.05), Vector3(side * run / 2, eave + rise / 2 + float(tile % 2) * 0.025, (tile - 3) * (depth + 1.0) / 7), tint)
			panel.rotation.z = -side * atan2(rise, run)
		for end: float in [-1.0, 1.0]:
			ArtMesh.beam(node, "Bargeboard", Vector3(side * run, eave, end * (depth + 1.05) / 2), Vector3(0, eave + rise, end * (depth + 1.05) / 2), 0.18, 0.18, "timber")
	ArtMesh.box(node, "RidgeCap", Vector3(0.24, 0.19, depth + 1.2), Vector3(0, eave + rise + 0.07, 0), "moss")
	for end: float in [-1.0, 1.0]:
		ArtMesh.prism(node, "Gable", PackedVector2Array([Vector2(-width / 2, 0), Vector2(width / 2, 0), Vector2(0, rise - 0.1)]), 0.16, Vector3(0, eave, end * depth / 2), "linen")

static func _masonry(node: Node3D, width: float, depth: float, levels: int) -> void:
	for level: int in levels:
		for side: float in [-1.0, 1.0]:
			var z := -depth / 2 + 0.2 + float(level % 2) * 0.12
			ArtMesh.box(node, "CornerQuoin", Vector3(0.58, 0.27, 0.48), Vector3(side * (width / 2 - 0.12), 0.3 + level * 0.52, z), "stone" if level % 3 else "slate")
	for side: float in [-1.0, 1.0]:
		ArtMesh.box(node, "Foundation", Vector3(0.42, 0.28, depth), Vector3(side * (width - 0.25) / 2, 0.2, 0), "slate")

static func _house(node: Node3D, family: StringName) -> void:
	var inn := family == &"inn"
	var forge := family == &"forge"
	var width := 6.6 if inn else 5.8
	var depth := 7.6 if inn else 5.4
	var height := 4.5 if inn else 3.0
	_shell(node, width, depth, height, "linen")
	_roof(node, width, depth, height, "moss" if inn else "rust")
	_masonry(node, width, depth, 5)
	for side: float in [-1.0, 1.0]:
		for z: float in [-depth / 2, depth / 2]:
			ArtMesh.beam(node, "Upright", Vector3(side * (width / 2 - 0.16), 0.3, z - 0.17), Vector3(side * (width / 2 - 0.1), height, z - 0.17), 0.18, 0.2, "timber")
		ArtMesh.box(node, "WindowRecess", Vector3(0.92, 0.88, 0.07), Vector3(side * 1.9, 1.9, -depth / 2 - 0.17), "timber")
		ArtMesh.box(node, "WindowGlow", Vector3(0.7, 0.65, 0.08), Vector3(side * 1.9, 1.9, -depth / 2 - 0.21), "warm")
		ArtMesh.box(node, "WindowMullion", Vector3(0.07, 0.77, 0.1), Vector3(side * 1.9, 1.9, -depth / 2 - 0.26), "timber")
		ArtMesh.box(node, "Sill", Vector3(1.1, 0.12, 0.4), Vector3(side * 1.9, 1.44, -depth / 2 - 0.15), "wood")
	ArtMesh.box(node, "WallPlate", Vector3(width, 0.2, depth + 0.12), Vector3(0, height - 0.12, 0), "timber")
	if inn:
		ArtMesh.box(node, "StoreyBeam", Vector3(width, 0.18, 0.4), Vector3(0, 3.08, -depth / 2), "timber")
		for side: float in [-1.0, 1.0]:
			ArtMesh.beam(node, "WallBrace", Vector3(side * 0.3, 3.18, -depth / 2 - 0.18), Vector3(side * 2.9, 4.25, -depth / 2 - 0.18), 0.13, 0.1, "timber")
		var wheel := ArtMesh.pivot(node, "Waterwheel", Vector3(width / 2 + 0.55, 1.65, 0.6))
		for spoke: int in 10:
			var angle := spoke * TAU / 10
			var tip := Vector3(0, cos(angle) * 1.5, sin(angle) * 1.5)
			ArtMesh.beam(wheel, "WheelSpoke", Vector3.ZERO, tip, 0.13, 0.13, "timber")
			var paddle := ArtMesh.box(wheel, "Paddle", Vector3(0.9, 0.2, 0.75), tip, "wood")
			paddle.rotation.x = angle
		ArtMesh.beam(wheel, "Axle", Vector3(-0.8, 0, 0), Vector3(0.7, 0, 0), 0.24, 0.24, "iron")
	if forge:
		ArtMesh.box(node, "ForgeHearth", Vector3(1.8, 0.65, 1.5), Vector3(1.7, 0.325, 1.6), "slate")
		ArtMesh.box(node, "CoalBed", Vector3(1.4, 0.14, 1.1), Vector3(1.7, 0.72, 1.6), "ink")
		ArtMesh.box(node, "Embers", Vector3(0.72, 0.08, 0.55), Vector3(1.7, 0.82, 1.6), "flame")
		ArtMesh.cylinder(node, "SmokeHood", 1.0, 0.45, 1.1, Vector3(1.7, 2.75, 1.6), "dark_iron", 4)
		ArtMesh.box(node, "ForgeChimney", Vector3(0.85, 3.0, 0.85), Vector3(1.7, 4.2, 1.6), "slate")
		ArtMesh.box(node, "ChimneyCrown", Vector3(1.05, 0.2, 1.05), Vector3(1.7, 5.7, 1.6), "stone")
	else:
		ArtMesh.box(node, "Chimney", Vector3(0.7, 2.0, 0.75), Vector3(-1.55, height + 1, 1.3), "stone")

static func _arch(node: Node3D, gap: float, spring: float, depth: float) -> void:
	for side: float in [-1.0, 1.0]:
		ArtMesh.box(node, "ArchPier", Vector3(0.7, spring, depth), Vector3(side * (gap / 2 + 0.35), spring / 2, 0), "stone")
		ArtMesh.box(node, "PierFoot", Vector3(1.0, 0.3, depth + 0.25), Vector3(side * (gap / 2 + 0.5), 0.15, 0), "slate")
	var radius := gap / 2 + 0.35
	for voussoir: int in 9:
		var a := voussoir * PI / 9
		var b := (voussoir + 1) * PI / 9
		var inner := radius - 0.35
		var outer := radius + 0.35
		var points := PackedVector2Array([Vector2(cos(a) * inner, sin(a) * inner), Vector2(cos(a) * outer, sin(a) * outer), Vector2(cos(b) * outer, sin(b) * outer), Vector2(cos(b) * inner, sin(b) * inner)])
		ArtMesh.prism(node, "ArchStone", points, depth, Vector3(0, spring, 0), "fog" if voussoir == 4 else "stone")

static func _gate(node: Node3D) -> void:
	_arch(node, 3.0, 3.5, 1.2)
	for side: float in [-1.0, 1.0]:
		ArtMesh.box(node, "GateButtress", Vector3(0.9, 5.4, 1.6), Vector3(side * 2.2, 2.7, 0), "slate")
		ArtMesh.box(node, "GateCap", Vector3(1.1, 0.25, 1.8), Vector3(side * 2.2, 5.5, 0), "stone")
	ArtMesh.beam(node, "BannerPole", Vector3(2.3, 5.4, 0), Vector3(2.3, 7.5, 0), 0.08, 0.08, "timber")
	ArtMesh.prism(node, "LevyBanner", PackedVector2Array([Vector2(0, 0), Vector2(1.0, 0.22), Vector2(1.15, 1.35), Vector2(0, 1.4)]), 0.04, Vector3(2.3, 5.9, 0), "rust")

static func _wall(node: Node3D) -> void:
	ArtMesh.box(node, "CurtainWall", Vector3(7, 3.6, 0.8), Vector3(0, 1.8, 0), "stone")
	ArtMesh.box(node, "ParapetCourse", Vector3(7.2, 0.23, 1), Vector3(0, 3.6, 0), "slate")
	for tooth: int in 6:
		ArtMesh.box(node, "Merlon", Vector3(0.65, 0.7, 0.85), Vector3(-3.1 + tooth * 1.24, 4.05, 0), "stone")
	for block: int in 14:
		ArtMesh.box(node, "FacingBlock", Vector3(0.76, 0.32, 0.07), Vector3(-3 + (block % 7) * 0.96, 0.6 + (block / 7) * 1.5, -0.42), "slate" if block % 3 else "moss")

static func _keep(node: Node3D) -> void:
	_shell(node, 7.6, 8.0, 9.0, "slate", 2.0)
	_masonry(node, 7.6, 8.0, 16)
	ArtMesh.box(node, "BattlementWalk", Vector3(8.0, 0.4, 8.3), Vector3(0, 9.0, 0), "stone")
	for side: float in [-1.0, 1.0]:
		for tooth: int in 7:
			ArtMesh.box(node, "FrontMerlon", Vector3(0.65, 0.85, 0.65), Vector3(-3.7 + tooth * 1.23, 9.6, side * 3.8), "slate")
			ArtMesh.box(node, "SideMerlon", Vector3(0.65, 0.85, 0.65), Vector3(side * 3.7, 9.6, -3.7 + tooth * 1.23), "slate")
		for floor_index: int in 2:
			ArtMesh.box(node, "ArrowSlit", Vector3(0.18, 1.2, 0.04), Vector3(side * 2.2, 4.6 + floor_index * 2.5, -4.18), "ink")
		ArtMesh.box(node, "GateButtress", Vector3(0.8, 5.4, 1.0), Vector3(side * 3.3, 2.7, -4.2), "stone")

static func _tower(node: Node3D, ruined: bool) -> void:
	var height := 6.3 if ruined else 10.2
	_shell(node, 5.0, 5.0, height, "stone", 1.6)
	_masonry(node, 5.0, 5.0, 11 if ruined else 18)
	for side: float in [-1.0, 1.0]:
		ArtMesh.box(node, "CornerButtress", Vector3(0.68, height + 0.8, 0.85), Vector3(side * 2.25, (height + 0.8) / 2, 2.0), "slate")
	if ruined:
		ArtMesh.prism(node, "BrokenCrown", PackedVector2Array([Vector2(-2.5, 0), Vector2(2.5, 0), Vector2(2.5, 1.6), Vector2(1.6, 1.9), Vector2(0.95, 0.6), Vector2(0.3, 0.35), Vector2(-0.3, 1.1), Vector2(-1.0, 0.7), Vector2(-2.5, 2.2)]), 0.3, Vector3(0, height, 2.5), "slate")
		ArtMesh.box(node, "LitWindow", Vector3(0.6, 1.0, 0.05), Vector3(1.3, 4.0, -2.68), "warm")
		for rubble: int in 5:
			var chunk := ArtMesh.box(node, "FallenMasonry", Vector3(0.85, 0.65, 0.7), Vector3(3.3 + (rubble % 2) * 0.8, 0.5, -1.0 + rubble * 0.7), "stone")
			chunk.rotation = Vector3(0.12, rubble * 0.5, 0.2)
	else:
		var belfry := ArtMesh.pivot(node, "Belfry", Vector3(0, height, 0))
		_arch(belfry, 2.4, 1.6, 0.6)
		ArtMesh.beam(belfry, "BellYoke", Vector3(-1.5, 1.4, 0), Vector3(1.5, 1.4, 0), 0.2, 0.2, "timber")
		ArtMesh.cylinder(belfry, "AbbeyBell", 0.62, 0.27, 0.8, Vector3(0, 0.85, 0), "ochre")
		ArtMesh.box(belfry, "SplitSpire", Vector3(0.68, 3.0, 0.7), Vector3(-2.1, 1.5, 1.4), "slate")
		ArtMesh.box(belfry, "BrokenSpire", Vector3(0.68, 1.75, 0.7), Vector3(2.1, 0.87, 1.4), "slate")

static func _room(node: Node3D, crypt: bool) -> void:
	_shell(node, 10.0, 10.0, 8.0 if crypt else 4.5, "slate" if crypt else "stone", 2.2)
	for tile: int in 25:
		ArtMesh.box(node, "Flagstone", Vector3(1.84, 0.035, 1.84), Vector3(-4 + (tile % 5) * 2, 0.135, -4 + (tile / 5) * 2), "stone" if tile % 4 else "moss")
	for z: float in [-3.0, 0.0, 3.0]:
		if crypt:
			var rib := ArtMesh.pivot(node, "VaultRib", Vector3(0, 0.13, z))
			_arch(rib, 8.1, 3.0, 0.32)
		else:
			ArtMesh.box(node, "CeilingBeam", Vector3(9.7, 0.3, 0.27), Vector3(0, 4.0, z), "timber")
			for side: float in [-1.0, 1.0]:
				ArtMesh.box(node, "SupportPost", Vector3(0.27, 4, 0.27), Vector3(side * 4.5, 2.0, z), "timber")
	ArtMesh.box(node, "Ceiling", Vector3(10.0, 0.25, 10.0), Vector3(0, 8.0 if crypt else 4.55, 0), "slate" if crypt else "wood")
	if crypt:
		for side: float in [-1.0, 1.0]:
			for z: float in [-2.5, 2.5]:
				ArtMesh.box(node, "BurialPlinth", Vector3(1.5, 0.55, 2.35), Vector3(side * 3.3, 0.4, z), "stone")
				ArtMesh.box(node, "TombLid", Vector3(1.6, 0.18, 2.45), Vector3(side * 3.3, 0.75, z), "fog")
				ArtMesh.box(node, "CarvedCross", Vector3(0.1, 0.05, 1.2), Vector3(side * 3.3, 0.865, z), "slate")
				ArtMesh.box(node, "CrossArm", Vector3(0.65, 0.05, 0.1), Vector3(side * 3.3, 0.865, z - 0.2), "slate")
	else:
		for side: float in [-1.0, 1.0]:
			for shelf: int in 3:
				ArtMesh.box(node, "StoresShelf", Vector3(1.1, 0.14, 3.5), Vector3(side * 4.1, 0.5 + shelf, 1.9), "wood")
				ArtMesh.box(node, "GrainSack", Vector3(0.66, 0.63, 0.8), Vector3(side * 4.1, 0.88 + shelf, 1.5), "linen")

static func _crossing(node: Node3D, ferry: bool) -> void:
	var length := 5.0 if ferry else 10.0
	for plank: int in 16:
		ArtMesh.box(node, "DeckPlank", Vector3(3.0, 0.16, length / 16 - 0.018), Vector3(0, 0.24, -length / 2 + (plank + 0.5) * length / 16), "wood" if plank % 4 else "timber")
	for side: float in [-1.0, 1.0]:
		ArtMesh.box(node, "Stringer", Vector3(0.22, 0.24, length), Vector3(side * 1.2, 0.12, 0), "timber")
		for post: int in 5:
			ArtMesh.box(node, "RailPost", Vector3(0.16, 1.3, 0.16), Vector3(side * 1.42, 0.8, -length / 2 + 0.1 + post * (length - 0.2) / 4), "timber")
		ArtMesh.box(node, "Handrail", Vector3(0.12, 0.15, length), Vector3(side * 1.42, 1.3, 0), "wood")
	if ferry:
		ArtMesh.beam(node, "FerryMast", Vector3(0, 0.3, 0.4), Vector3(0, 3.7, 0.4), 0.16, 0.16, "timber")
		ArtMesh.beam(node, "CrossYard", Vector3(-1.3, 3.4, 0.4), Vector3(1.3, 3.4, 0.4), 0.12, 0.12, "timber")
		ArtMesh.box(node, "FurledCanvas", Vector3(2.0, 0.25, 0.3), Vector3(0, 3.25, 0.4), "linen")

static func _tent(node: Node3D) -> void:
	for side: float in [-1.0, 1.0]:
		for stripe: int in 6:
			var cloth := ArtMesh.box(node, "CanvasStripe", Vector3(Vector2(2.1, 2.3).length(), 0.055, 0.7), Vector3(side * 1.05, 2.25, -1.75 + stripe * 0.7), "linen" if stripe % 2 else "reed")
			cloth.rotation.z = -side * atan2(2.3, 2.1)
		ArtMesh.box(node, "CanvasSkirt", Vector3(0.055, 1.1, 4.2), Vector3(side * 2.1, 0.55, 0), "linen")
		ArtMesh.beam(node, "EntrancePole", Vector3(side * 0.87, 0, -2.05), Vector3(side * 0.87, 3.4, -2.05), 0.08, 0.08, "timber")
	ArtMesh.beam(node, "RidgePole", Vector3(0, 3.4, -2.2), Vector3(0, 3.4, 2.2), 0.1, 0.1, "timber")
	ArtMesh.prism(node, "RearCanvas", PackedVector2Array([Vector2(-2.1, 0), Vector2(2.1, 0), Vector2(2.1, 1.1), Vector2(0, 3.4), Vector2(-2.1, 1.1)]), 0.04, Vector3(0, 0, 2.1), "linen")

static func _kiln(node: Node3D) -> void:
	# Segmented walls leave an open firing mouth on the south-facing side.
	for block: int in 11:
		var angle := (block + 1) * TAU / 12
		var segment := ArtMesh.box(node, "KilnWall", Vector3(0.9, 1.7, 0.38), Vector3(sin(angle) * 1.7, 0.85, -cos(angle) * 1.7), "ink" if block % 3 else "slate")
		segment.rotation.y = -angle
	ArtMesh.cylinder(node, "KilnDome", 2.0, 0.43, 1.5, Vector3(0, 2.2, 0), "peat", 12)
	ArtMesh.cylinder(node, "SmokeVent", 0.4, 0.32, 0.65, Vector3(0, 3.2, 0), "ink")
	ArtMesh.box(node, "MouthLintel", Vector3(1.5, 0.22, 0.5), Vector3(0, 1.55, -1.7), "slate")
