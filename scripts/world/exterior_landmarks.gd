class_name ExteriorLandmarks
extends RefCounted

# Width, depth, wall height, and clear front doorway width from T03 architecture.
const SHELLS := {
	&"cottage": Vector4(5.8, 5.4, 3.0, 1.6),
	&"forge": Vector4(5.8, 5.4, 3.0, 1.6),
	&"inn": Vector4(6.6, 7.6, 4.5, 1.6),
	&"keep": Vector4(7.6, 8.0, 9.0, 2.0),
	&"monastery_tower": Vector4(5.0, 5.0, 10.2, 1.6),
	&"ruined_watchtower": Vector4(5.0, 5.0, 6.3, 1.6),
	&"crypt_room": Vector4(10.0, 10.0, 8.0, 2.2),
	&"undercroft_room": Vector4(10.0, 10.0, 4.5, 2.2),
}
const SILHOUETTES: Array[StringName] = [&"keep", &"monastery_tower", &"ruined_watchtower"]
const GROUND_PROPS: Array[StringName] = [&"oak", &"pine", &"rock", &"cart", &"well", &"kiln", &"shrine"]

static func build(parent: Node3D, manifest: Dictionary) -> Dictionary:
	var errors: PackedStringArray = validate(manifest)
	if not errors.is_empty():
		push_error("Invalid exterior landmark structures: " + "; ".join(errors))
		return {}
	var roots: Dictionary = {}
	for landmark: Dictionary in manifest.landmarks:
		var id := StringName(landmark.id)
		var root := Node3D.new()
		root.name = id
		root.position = _vector(landmark.position)
		root.set_meta("landmark_id", id)
		parent.add_child(root)
		roots[id] = root
	for entry: Dictionary in manifest.exterior.structures:
		var landmark_root: Node3D = roots[StringName(entry.landmark_id)]
		var structure := Node3D.new()
		structure.name = entry.id
		structure.position = _vector(entry.position) - landmark_root.position
		structure.rotation.y = float(entry.yaw)
		structure.set_meta("structure_id", StringName(entry.id))
		structure.set_meta("landmark_id", StringName(entry.landmark_id))
		landmark_root.add_child(structure)
		var family := StringName(entry.family)
		var scale: Vector3 = _vector(entry.scale)
		var model: Node3D = VisualFactory.building(family) if entry.category == "building" else VisualFactory.prop(family)
		model.name = "Visual"
		model.scale = scale
		structure.add_child(model)
		_visibility(model, 700.0 if family in SILHOUETTES else 220.0)
		if entry.collision == "none":
			continue
		var body := StaticBody3D.new()
		body.name = "WorldCollision"
		body.collision_layer = MireTypes.WORLD
		body.collision_mask = MireTypes.PLAYER | MireTypes.HOSTILE | MireTypes.NEUTRAL
		structure.add_child(body)
		match entry.collision:
			"shell":
				if SHELLS.has(family):
					_shell(body, SHELLS[family], scale)
					if family == &"forge":
						_box(body, Vector3(1.8, 0.8, 1.5), Vector3(1.7, 0.4, 1.6), scale)
				elif family in [&"bridge", &"ferry"]:
					_deck(body, family == &"ferry", scale)
				else:
					_tent(body, scale)
			"gate": _gate(body, family == &"road_gate", scale)
			"wall": _box(body, Vector3(7.0, 4.4, 0.8), Vector3(0, 2.2, 0), scale)
			"prop": _prop(body, family, scale)
	return roots

static func validate(manifest: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if not manifest.get("landmarks") is Array or not manifest.get("exterior") is Dictionary or not manifest.exterior.get("structures") is Array:
		return PackedStringArray(["landmarks and exterior.structures must be lists"])
	var landmark_ids: Dictionary = {}
	for landmark: Variant in manifest.landmarks:
		if not landmark is Dictionary or not SessionValidation.identifier(landmark.get("id")) or not SessionValidation.vector(landmark.get("position")):
			errors.append("invalid landmark identity or position")
			continue
		if landmark_ids.has(landmark.id):
			errors.append("duplicate landmark " + landmark.id)
		landmark_ids[landmark.id] = true
	var structure_ids: Dictionary = {}
	for entry: Variant in manifest.exterior.structures:
		if not entry is Dictionary or not SessionValidation.identifier(entry.get("id")):
			errors.append("structure needs a string ID")
			continue
		var id: String = entry.id
		if structure_ids.has(id):
			errors.append("duplicate structure " + id)
		structure_ids[id] = true
		if not entry.get("landmark_id") is String or not landmark_ids.has(entry.landmark_id):
			errors.append("unknown landmark for " + id)
		if not SessionValidation.vector(entry.get("position")) or not SessionValidation.vector(entry.get("scale")) or not SessionValidation.number(entry.get("yaw")) or not is_finite(float(entry.yaw)):
			errors.append("invalid transform for " + id)
			continue
		var scale: Vector3 = _vector(entry.scale)
		if scale.x <= 0 or scale.y <= 0 or scale.z <= 0:
			errors.append("scale must be positive for " + id)
		if not SessionValidation.identifier(entry.get("family")) or entry.get("category") not in ["building", "prop"]:
			errors.append("invalid art category or family for " + id)
			continue
		var family := StringName(entry.family)
		if (entry.category == "building" and family not in ArtBuildings.FAMILIES) or (entry.category == "prop" and family not in ArtProps.KINDS):
			errors.append("unknown art family for " + id)
		match entry.get("collision"):
			"shell":
				if not SHELLS.has(family) and family not in [&"tent", &"bridge", &"ferry"]:
					errors.append("no shell footprint for " + id)
			"gate":
				if family not in [&"road_gate", &"monastery_arch"]:
					errors.append("no gate footprint for " + id)
			"wall":
				if family != &"wall":
					errors.append("no wall footprint for " + id)
			"prop":
				if family not in GROUND_PROPS:
					errors.append("no ground footprint for " + id)
			"none": pass
			_: errors.append("unknown collision type for " + id)
	return errors

static func _shell(body: StaticBody3D, dimensions: Vector4, scale: Vector3) -> void:
	var width: float = dimensions.x
	var depth: float = dimensions.y
	var height: float = dimensions.z
	var door: float = dimensions.w
	_box(body, Vector3(width, 0.12, depth), Vector3(0, 0.06, 0), scale)
	_box(body, Vector3(width, 0.2, depth), Vector3(0, height - 0.1, 0), scale)
	for side: float in [-1.0, 1.0]:
		_box(body, Vector3(0.28, height, depth), Vector3(side * (width - 0.28) * 0.5, height * 0.5, 0), scale)
		_box(body, Vector3((width - door) * 0.5, height, 0.4), Vector3(side * (width + door) * 0.25, height * 0.5, -depth * 0.5), scale)
	_box(body, Vector3(width, height, 0.3), Vector3(0, height * 0.5, depth * 0.5), scale)
	_box(body, Vector3(door, height - 2.5, 0.44), Vector3(0, (height + 2.5) * 0.5, -depth * 0.5), scale)
	_ramp(body, door, 0.12, 0.45, -depth * 0.5, false, scale)

static func _gate(body: StaticBody3D, road_gate: bool, scale: Vector3) -> void:
	var spring: float = 3.5 if road_gate else 3.4
	var depth: float = 1.2 if road_gate else 0.75
	for side: float in [-1.0, 1.0]:
		_box(body, Vector3(0.7, spring, depth), Vector3(side * 1.85, spring * 0.5, 0), scale)
		_box(body, Vector3(1.0, 0.3, depth + 0.25), Vector3(side * 2.0, 0.15, 0), scale)
		if road_gate:
			_box(body, Vector3(0.9, 5.4, 1.6), Vector3(side * 2.2, 2.7, 0), scale)
	_box(body, Vector3(3.0, 0.7, depth), Vector3(0, spring + 1.85, 0), scale)

static func _deck(body: StaticBody3D, ferry: bool, scale: Vector3) -> void:
	var length: float = 5.0 if ferry else 10.0
	_box(body, Vector3(3.0, 0.32, length), Vector3(0, 0.16, 0), scale)
	for side: float in [-1.0, 1.0]:
		_box(body, Vector3(0.16, 1.3, length), Vector3(side * 1.42, 0.8, 0), scale)
	_ramp(body, 2.5, 0.32, 0.9, -length * 0.5, false, scale)
	_ramp(body, 2.5, 0.32, 0.9, length * 0.5, true, scale)
	if ferry:
		_box(body, Vector3(0.16, 3.4, 0.16), Vector3(0, 2.0, 0.4), scale)

static func _tent(body: StaticBody3D, scale: Vector3) -> void:
	for side: float in [-1.0, 1.0]:
		_box(body, Vector3(0.08, 1.1, 4.2), Vector3(side * 2.1, 0.55, 0), scale)
		_box(body, Vector3(0.08, 3.4, 0.08), Vector3(side * 0.87, 1.7, -2.05), scale)
		var roof := PackedVector3Array()
		for z: float in [-2.1, 2.1]:
			for point: Vector2 in [Vector2(0, 3.37), Vector2(side * 2.1, 1.07), Vector2(side * 2.1, 1.13), Vector2(0, 3.43)]:
				roof.append(Vector3(point.x, point.y, z))
		_convex(body, roof, scale)
	_box(body, Vector3(4.2, 1.1, 0.08), Vector3(0, 0.55, 2.1), scale)
	var back := PackedVector3Array()
	for z: float in [2.06, 2.14]:
		for point: Vector2 in [Vector2(-2.1, 1.1), Vector2(2.1, 1.1), Vector2(0, 3.4)]:
			back.append(Vector3(point.x, point.y, z))
	_convex(body, back, scale)

static func _prop(body: StaticBody3D, family: StringName, scale: Vector3) -> void:
	match family:
		&"oak": _round(body, 0.28, 3.4, scale)
		&"pine": _round(body, 0.19, 4.5, scale)
		&"kiln": _round(body, 2.0, 3.0, scale)
		&"rock": _box(body, Vector3(2.1, 1.0, 1.4), Vector3(0, 0.5, 0), scale)
		&"cart": _box(body, Vector3(1.85, 1.1, 2.2), Vector3(0, 0.55, 0.1), scale)
		&"well":
			_round(body, 0.8, 0.72, scale)
			for side: float in [-1.0, 1.0]:
				_box(body, Vector3(0.18, 2.3, 0.18), Vector3(side * 0.95, 1.15, 0), scale)
		&"shrine":
			_box(body, Vector3(1.5, 0.18, 1.25), Vector3(0, 0.09, 0), scale)
			_box(body, Vector3(1.0, 0.72, 0.65), Vector3(0, 0.54, 0.15), scale)
			_box(body, Vector3(0.76, 1.25, 0.2), Vector3(0, 1.525, 0.28), scale)

static func _box(body: StaticBody3D, size: Vector3, position: Vector3, scale: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size * scale
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = position * scale
	body.add_child(collision)

static func _round(body: StaticBody3D, radius: float, height: float, scale: Vector3) -> void:
	var points := PackedVector3Array()
	for y: float in [0.0, height]:
		for index: int in 12:
			var angle: float = index * TAU / 12
			points.append(Vector3(cos(angle) * radius, y, sin(angle) * radius))
	_convex(body, points, scale)

static func _ramp(body: StaticBody3D, width: float, height: float, length: float, edge: float, reverse: bool, scale: Vector3) -> void:
	var points := PackedVector3Array()
	for side: float in [-1.0, 1.0]:
		points.append(Vector3(side * width * 0.5, 0, edge + (length if reverse else -length)))
		points.append(Vector3(side * width * 0.5, 0, edge))
		points.append(Vector3(side * width * 0.5, height, edge))
	_convex(body, points, scale)

static func _convex(body: StaticBody3D, points: PackedVector3Array, scale: Vector3) -> void:
	for index: int in points.size():
		points[index] *= scale
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)

static func _visibility(node: Node, distance: float) -> void:
	if node is GeometryInstance3D:
		node.visibility_range_end = distance
		node.visibility_range_end_margin = 20.0
	for child: Node in node.get_children():
		_visibility(child, distance)

static func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
