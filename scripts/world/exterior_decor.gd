class_name ExteriorDecor
extends RefCounted
## Cosmetic scatter is seeded and excluded from authored paths, stations and views.

static func placements(map: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var random := RandomNumberGenerator.new()
	random.seed = int(map.seed)
	for attempt: int in int(map.exterior.decor_count) * 30:
		if result.size() >= int(map.exterior.decor_count):
			break
		var point := Vector2(random.randf_range(-265, 265), random.randf_range(-265, 265))
		if reserved(point, map):
			continue
		var height: float = ExteriorTerrain.height_at(point.x, point.y, map)
		if height < -0.05 or height > 10:
			continue
		var kind: String = "rock" if attempt % 5 == 0 else ("pine" if point.y < 0 else "oak")
		var size: float = random.randf_range(0.85, 1.6)
		result.append({"id": "decor_%03d" % result.size(), "kind": kind, "position": [point.x, height, point.y], "scale": size, "yaw": random.randf_range(-PI, PI)})
	return result

static func reserved(point: Vector2, map: Dictionary) -> bool:
	if ExteriorTerrain.route_distance(point, map) < 7:
		return true
	for landmark: Dictionary in map.landmarks:
		if _distance(point, landmark.position) < 24:
			return true
	for structure: Dictionary in map.exterior.structures:
		if _distance(point, structure.position) < 16:
			return true
	for row: Dictionary in map.spawns + map.exterior.objective_reservations + map.exterior.npc_reservations:
		if row.scene_id == "exterior" and _distance(point, row.position) < 12:
			return true
	for portal: Dictionary in map.exterior.portals:
		if _distance(point, portal.position) < 12:
			return true
	for anchor: Array in map.scenes.exterior.entrances.values():
		if _distance(point, anchor) < 12:
			return true
	for rest: Dictionary in map.rest_points.values():
		if rest.scene_id == "exterior" and _distance(point, rest.position) < 12:
			return true
	for view: Dictionary in map.exterior.viewpoints:
		var from := Vector2(view.position[0], view.position[2])
		for landmark: Dictionary in map.landmarks:
			if landmark.id in view.targets:
				var to := Vector2(landmark.position[0], landmark.position[2])
				if point.distance_to(Geometry2D.get_closest_point_to_segment(point, from, to)) < 10:
					return true
	return false

static func _distance(point: Vector2, values: Array) -> float:
	return point.distance_to(Vector2(values[0], values[2]))

static func build(parent: Node3D, map: Dictionary) -> Array[Dictionary]:
	var specs := placements(map)
	var templates: Dictionary = {}
	for kind: StringName in [&"oak", &"pine", &"rock"]:
		templates[String(kind)] = VisualFactory.prop(kind)
	for spec: Dictionary in specs:
		var model: Node3D = templates[spec.kind].duplicate()
		model.name = spec.id
		model.position = ExteriorTerrain.vector(spec.position)
		model.rotation.y = float(spec.yaw)
		model.scale = Vector3.ONE * float(spec.scale)
		_cull(model, 85 if spec.kind == "rock" else 160)
		parent.add_child(model)
		var body := StaticBody3D.new()
		body.name = spec.id + "_collision"
		body.position = model.position
		body.collision_layer = MireTypes.WORLD
		body.collision_mask = 0
		var collider := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = (1.15 if spec.kind == "rock" else 0.31) * float(spec.scale)
		cylinder.height = (1.2 if spec.kind == "rock" else 3.4) * float(spec.scale)
		collider.shape = cylinder
		collider.position.y = cylinder.height / 2
		body.add_child(collider)
		parent.add_child(body)
	for node: Node3D in templates.values():
		node.free()
	return specs

static func _cull(node: Node, distance: float) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).visibility_range_end = distance
	for child: Node in node.get_children():
		_cull(child, distance)
