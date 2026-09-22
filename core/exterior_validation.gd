class_name ExteriorValidation
extends RefCounted
## Validates authored geometry and links before exterior construction.

const PORTALS := {
	"inn_door": ["interior_inn", "from_inn"],
	"crypt_door": ["interior_crypt", "from_crypt"],
	"undercroft_door": ["interior_undercroft", "from_undercroft"],
}
const REST_SCENES := {
	"village_shrine": "exterior", "reed_shrine": "exterior",
	"monastery_shelter": "exterior", "inn_bed": "interior_inn",
}

static func validate(map: Dictionary, containers: Dictionary, dialogues: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if not map.get("exterior") is Dictionary:
		return PackedStringArray(["map.exterior must be a dictionary."])
	var exterior: Dictionary = map.exterior
	var occupied: Dictionary = {}
	var landmarks: Array[Dictionary] = _records(map.get("landmarks"), "landmarks", occupied, errors)
	_records(map.get("spawns"), "spawns", occupied, errors)
	var landmark_ids: Dictionary = {}
	for landmark: Dictionary in landmarks:
		landmark_ids[landmark.id] = true
		_position(landmark.get("position"), "landmark " + landmark.id, map, errors)
		if not _positive(landmark.get("discovery_radius")):
			errors.append("landmark %s discovery_radius must be finite and positive." % landmark.id)
	_terrain(map, exterior, errors)
	var scenes: Dictionary = {}
	if map.get("scenes") is Dictionary:
		scenes = map.scenes
	else:
		errors.append("map.scenes must be a dictionary for exterior destination links.")
	var entrances: Dictionary = _entrances(scenes, "exterior", errors)
	for id: Variant in entrances:
		_position(entrances[id], "exterior entrance " + str(id), map, errors)
	if scenes.get("exterior") is Dictionary:
		_position(scenes.exterior.get("safe_anchor"), "exterior safe_anchor", map, errors)
	if not SessionValidation.vector(map.get("start")) or not SessionValidation.vector(entrances.get("start")) or entrances.start != map.start:
		errors.append("map.start must match the exterior start entrance's finite position.")
	_routes(exterior, map, occupied, errors)
	var structures := _records(exterior.get("structures"), "exterior.structures", occupied, errors)
	errors.append_array(ExteriorLandmarks.validate(map))
	for structure: Dictionary in structures:
		_position(structure.get("position"), "structure " + structure.id, map, errors)
	_reservations(exterior, "objective_reservations", containers, 13, scenes, map, occupied, errors)
	_reservations(exterior, "npc_reservations", dialogues, 8, scenes, map, occupied, errors)
	_portals(exterior, scenes, entrances, map, occupied, errors)
	_rest_points(map, scenes, occupied, errors)
	_hazards(exterior, map, occupied, errors)
	_views(exterior, landmark_ids, map, occupied, errors)
	var yaws: Variant = exterior.get("entrance_yaws")
	if not yaws is Dictionary:
		errors.append("exterior.entrance_yaws must be a dictionary.")
	else:
		for id: Variant in yaws:
			if not SessionValidation.identifier(id) or not entrances.has(id) or not _finite(yaws[id]):
				errors.append("exterior.entrance_yaws/%s needs an existing entrance and finite yaw." % str(id))
		for id: Variant in entrances:
			if not yaws.has(id):
				errors.append("Missing exterior.entrance_yaws/%s." % str(id))
	return errors

static func _terrain(map: Dictionary, exterior: Dictionary, errors: PackedStringArray) -> void:
	if not SessionValidation.whole(map.get("seed")):
		errors.append("map.seed must be a finite integer for deterministic decoration.")
	if not _positive(map.get("bounds")):
		errors.append("map.bounds must be finite and positive.")
	if not SessionValidation.whole(exterior.get("decor_count")) or exterior.decor_count < 0:
		errors.append("exterior.decor_count must be a nonnegative integer.")
	var terrain: Variant = exterior.get("terrain")
	if not terrain is Dictionary:
		errors.append("exterior.terrain must be a dictionary.")
	else:
		var grid_valid: bool = true
		for field: String in ["half_extent", "cell_size", "chunk_size"]:
			if not SessionValidation.whole(terrain.get(field)) or terrain[field] <= 0:
				errors.append("exterior.terrain.%s must be a positive integer." % field)
				grid_valid = false
		for field: String in ["rim_start", "rim_height", "navigation_cell_size", "navigation_cell_height"]:
			if not _positive(terrain.get(field)):
				errors.append("exterior.terrain.%s must be finite and positive." % field)
		if grid_valid:
			if int(terrain.chunk_size) % int(terrain.cell_size) != 0 or (2 * int(terrain.half_extent)) % int(terrain.chunk_size) != 0:
				errors.append("exterior.terrain grid must tile its chunks and full extent exactly.")
			if _positive(map.get("bounds")) and terrain.half_extent != map.bounds:
				errors.append("exterior.terrain.half_extent must match map.bounds.")
			if _finite(terrain.get("rim_start")) and terrain.rim_start >= terrain.half_extent:
				errors.append("exterior.terrain.rim_start must be inside half_extent.")
	var pond: Variant = exterior.get("pond")
	if not pond is Dictionary:
		errors.append("exterior.pond must be a dictionary.")
		return
	_position(pond.get("center"), "exterior.pond center", map, errors)
	if not _radii(pond.get("radii")) or not _positive(pond.get("depth")):
		errors.append("exterior.pond requires two positive finite radii and positive depth.")

static func _routes(exterior: Dictionary, map: Dictionary, occupied: Dictionary, errors: PackedStringArray) -> void:
	var routes := _records(exterior.get("routes"), "exterior.routes", occupied, errors)
	var ids: Array[String] = []
	for route: Dictionary in routes:
		ids.append(route.id)
		if not _positive(route.get("width")):
			errors.append("route %s width must be finite and positive." % route.id)
		if not route.get("points") is Array or route.points.size() < 2:
			errors.append("route %s points must contain at least two positions." % route.id)
			continue
		for index: int in route.points.size():
			var point: Variant = route.points[index]
			_position(point, "route %s points[%d]" % [route.id, index], map, errors)
			if index > 0 and SessionValidation.vector(point) and SessionValidation.vector(route.points[index - 1]):
				var previous: Array = route.points[index - 1]
				if point[0] == previous[0] and point[2] == previous[2]:
					errors.append("route %s points[%d] has no horizontal separation from its predecessor." % [route.id, index])
	for id: String in ["central_road", "western_bypass", "eastern_bypass"]:
		if id not in ids:
			errors.append("Missing required exterior route " + id + ".")

static func _reservations(exterior: Dictionary, section: String, definitions: Dictionary, expected_count: int, scenes: Dictionary, map: Dictionary, occupied: Dictionary, errors: PackedStringArray) -> void:
	var rows := _records(exterior.get(section), "exterior." + section, occupied, errors)
	if rows.size() != expected_count:
		errors.append("exterior.%s must contain exactly %d reservations." % [section, expected_count])
	var reserved: Dictionary = {}
	for row: Dictionary in rows:
		reserved[row.id] = true
		var label: String = section + " " + row.id
		if not definitions.has(row.id):
			errors.append(label + " references an unknown " + ("container" if section == "objective_reservations" else "dialogue") + " ID.")
		var scene_id: Variant = row.get("scene_id")
		if not SessionValidation.identifier(scene_id) or not scenes.has(scene_id) or not scenes[scene_id] is Dictionary:
			errors.append(label + " references an unknown scene_id.")
		if scene_id is String and scene_id == "exterior":
			_position(row.get("position"), label, map, errors)
		elif not SessionValidation.vector(row.get("position")):
			errors.append(label + " position must have three finite coordinates.")
		if not _positive(row.get("radius")):
			errors.append(label + " radius must be finite and positive.")
	for id: Variant in definitions:
		if not reserved.has(id):
			errors.append("Missing %s target for %s." % [section, str(id)])

static func _portals(exterior: Dictionary, scenes: Dictionary, entrances: Dictionary, map: Dictionary, occupied: Dictionary, errors: PackedStringArray) -> void:
	var portals := _records(exterior.get("portals"), "exterior.portals", occupied, errors)
	var present: Dictionary = {}
	for portal: Dictionary in portals:
		var label: String = "portal " + portal.id
		present[portal.id] = true
		_position(portal.get("position"), label, map, errors)
		if not _positive_vector(portal.get("size")):
			errors.append(label + " size must have three positive finite dimensions.")
		var target: Variant = portal.get("target_scene")
		if not SessionValidation.identifier(target):
			errors.append(label + " target_scene must be a scene ID.")
			continue
		var target_entrances: Dictionary = _entrances(scenes, target, errors)
		if not SessionValidation.identifier(portal.get("target_entrance")) or not target_entrances.has(portal.target_entrance):
			errors.append(label + " target_entrance is absent from scene " + target + ".")
		if not SessionValidation.identifier(portal.get("return_entrance")) or not entrances.has(portal.return_entrance):
			errors.append(label + " return_entrance is absent from exterior entrances.")
		elif SessionValidation.vector(portal.get("position")) and _positive_vector(portal.get("size")) and SessionValidation.vector(entrances[portal.return_entrance]):
			var origin: Array = entrances[portal.return_entrance]
			var offset := Vector2(maxf(0, absf(origin[0] - portal.position[0]) - portal.size[0] * 0.5), maxf(0, absf(origin[2] - portal.position[2]) - portal.size[2] * 0.5))
			if offset.length() < 1.5:
				errors.append(label + " return_entrance must clear its trigger by at least 1.5 m.")
		if not PORTALS.has(portal.id):
			errors.append("Unknown exterior portal ID: " + portal.id + ".")
		elif not SessionValidation.identifier(portal.get("target_entrance")) or not SessionValidation.identifier(portal.get("return_entrance")) or target != PORTALS[portal.id][0] or portal.target_entrance != "entry" or portal.return_entrance != PORTALS[portal.id][1]:
			errors.append(label + " must pair %s/entry with exterior/%s." % PORTALS[portal.id])
	for id: String in PORTALS:
		if not present.has(id):
			errors.append("Missing exterior portal " + id + ".")

static func _rest_points(map: Dictionary, scenes: Dictionary, occupied: Dictionary, errors: PackedStringArray) -> void:
	if not map.get("rest_points") is Dictionary:
		errors.append("map.rest_points must be a dictionary.")
		return
	for id: Variant in map.rest_points:
		var rest: Variant = map.rest_points[id]
		if not SessionValidation.identifier(id) or not rest is Dictionary:
			errors.append("Invalid rest point " + str(id) + ".")
			continue
		if occupied.has(id):
			errors.append("Duplicate world ID %s in rest_points; already used by %s." % [id, occupied[id]])
		occupied[id] = "rest_points"
		if not SessionValidation.identifier(rest.get("scene_id")) or not scenes.has(rest.scene_id):
			errors.append("rest point %s references an unknown scene_id." % id)
		if rest.get("scene_id") is String and rest.scene_id == "exterior":
			_position(rest.get("position"), "rest point " + id, map, errors)
		elif not SessionValidation.vector(rest.get("position")):
			errors.append("rest point %s position must have three finite coordinates." % id)
	for id: String in REST_SCENES:
		var rest: Variant = map.rest_points.get(id)
		if not rest is Dictionary or not SessionValidation.identifier(rest.get("scene_id")) or rest.scene_id != REST_SCENES[id]:
			errors.append("Required rest point %s must exist in %s." % [id, REST_SCENES[id]])

static func _hazards(exterior: Dictionary, map: Dictionary, occupied: Dictionary, errors: PackedStringArray) -> void:
	var hazards := _records(exterior.get("hazards"), "exterior.hazards", occupied, errors)
	var kinds: Array[String] = []
	for hazard: Dictionary in hazards:
		var label: String = "hazard " + hazard.id
		match hazard.get("kind"):
			"deep_water":
				kinds.append("deep_water")
				if not hazard.get("shape") is String or hazard.shape != "ellipse":
					errors.append(label + " deep_water shape must be ellipse.")
				_position(hazard.get("center"), label + " center", map, errors)
				if not _radii(hazard.get("radii")):
					errors.append(label + " radii must have two positive finite values.")
				if not _finite(hazard.get("min_y")) or not _finite(hazard.get("max_y")) or hazard.min_y >= hazard.max_y:
					errors.append(label + " must have finite min_y below max_y.")
			"bounds":
				kinds.append("bounds")
				if not SessionValidation.vector(hazard.get("minimum")) or not SessionValidation.vector(hazard.get("maximum")):
					errors.append(label + " minimum and maximum must have three finite coordinates.")
					continue
				for axis: int in 3:
					if hazard.minimum[axis] >= hazard.maximum[axis]:
						errors.append(label + " minimum must be below maximum on each axis.")
				if _positive(map.get("bounds")) and (hazard.minimum[0] != -map.bounds or hazard.minimum[2] != -map.bounds or hazard.maximum[0] != map.bounds or hazard.maximum[2] != map.bounds):
					errors.append(label + " horizontal limits must match map.bounds.")
			_:
				errors.append(label + " kind must be deep_water or bounds.")
	for kind: String in ["deep_water", "bounds"]:
		if kind not in kinds:
			errors.append("Missing exterior " + kind + " hazard.")

static func _views(exterior: Dictionary, landmark_ids: Dictionary, map: Dictionary, occupied: Dictionary, errors: PackedStringArray) -> void:
	for view: Dictionary in _records(exterior.get("viewpoints"), "exterior.viewpoints", occupied, errors):
		_position(view.get("position"), "viewpoint " + view.id, map, errors)
		if not view.get("targets") is Array or view.targets.is_empty():
			errors.append("viewpoint %s targets must be a nonempty landmark list." % view.id)
			continue
		var targets: Dictionary = {}
		for target: Variant in view.targets:
			if not SessionValidation.identifier(target) or not landmark_ids.has(target):
				errors.append("viewpoint %s has unknown landmark target %s." % [view.id, str(target)])
			elif targets.has(target):
				errors.append("viewpoint %s repeats target %s." % [view.id, target])
			else:
				targets[target] = true

static func _records(value: Variant, section: String, occupied: Dictionary, errors: PackedStringArray) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if not value is Array:
		errors.append(section + " must be a list.")
		return rows
	for index: int in value.size():
		var row: Variant = value[index]
		if not row is Dictionary or not SessionValidation.identifier(row.get("id")):
			errors.append("%s[%d] requires a dictionary with a nonempty string ID." % [section, index])
			continue
		if occupied.has(row.id):
			errors.append("Duplicate world ID %s in %s; already used by %s." % [row.id, section, occupied[row.id]])
		occupied[row.id] = section
		rows.append(row)
	return rows

static func _entrances(scenes: Dictionary, scene_id: String, errors: PackedStringArray) -> Dictionary:
	var scene: Variant = scenes.get(scene_id)
	if not scene is Dictionary or not scene.get("entrances") is Dictionary or scene.entrances.is_empty():
		errors.append("Scene %s needs a nonempty entrance registry." % scene_id)
		return {}
	for id: Variant in scene.entrances:
		if not SessionValidation.identifier(id) or not SessionValidation.vector(scene.entrances[id]):
			errors.append("Scene %s entrance %s requires three finite coordinates." % [scene_id, str(id)])
	return scene.entrances

static func _position(value: Variant, label: String, map: Dictionary, errors: PackedStringArray) -> void:
	if not SessionValidation.vector(value):
		errors.append(label + " position must have three finite coordinates.")
	elif _positive(map.get("bounds")) and (absf(value[0]) > map.bounds or absf(value[2]) > map.bounds):
		errors.append(label + " position lies outside map.bounds.")

static func _finite(value: Variant) -> bool:
	return SessionValidation.number(value) and is_finite(float(value))

static func _positive(value: Variant) -> bool:
	return _finite(value) and value > 0

static func _radii(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _positive(value[0]) and _positive(value[1])

static func _positive_vector(value: Variant) -> bool:
	return SessionValidation.vector(value) and value[0] > 0 and value[1] > 0 and value[2] > 0
