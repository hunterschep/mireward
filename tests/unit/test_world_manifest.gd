extends RefCounted

const Validator = preload("res://core/exterior_validation.gd")

func run(t: SceneTree) -> void:
	var db: Node = t.root.get_node("ContentDB")
	var canonical: Dictionary = db.map.duplicate(true)
	var original: Dictionary = canonical.duplicate(true)
	var errors: PackedStringArray = Validator.validate(canonical, db.containers, db.dialogues)
	t.check(errors.is_empty(), "R04 canonical exterior manifest: " + "; ".join(errors))
	t.check(canonical == original, "R04 exterior validation leaves authored content unchanged")
	t.check(Validator.validate(JSON.parse_string(JSON.stringify(canonical)), db.containers, db.dialogues).is_empty(), "R04 JSON-decoded exterior numbers remain valid")
	check_mutations(t, db, canonical)
	check_nested_types(t, db, canonical)
	check_record_identity(t, db, canonical)
	check_registry_coverage(t, db, canonical)

func check_mutations(t: SceneTree, db: Node, canonical: Dictionary) -> void:
	var cases: Array[Dictionary] = [
		{"path": ["exterior"], "value": [], "error": "map.exterior"},
		{"path": ["exterior", "routes", 0, "width"], "value": 0, "error": "central_road width"},
		{"path": ["exterior", "routes", 0, "width"], "value": INF, "error": "central_road width"},
		{"path": ["exterior", "routes", 0, "points"], "value": [[0, 0, 0]], "error": "central_road points"},
		{"path": ["exterior", "routes", 0, "points", 1], "value": [0, "floor", 224], "error": "central_road points[1]"},
		{"path": ["exterior", "routes", 0, "points", 1], "value": [32, 9, 252], "error": "horizontal separation"},
		{"path": ["exterior", "routes", 0, "points", 1], "value": [321, 0, 224], "error": "outside map.bounds"},
		{"path": ["exterior", "routes", 0, "id"], "value": "other_road", "error": "Missing required exterior route central_road"},
		{"path": ["exterior", "structures", 0, "family"], "value": "skyscraper", "error": "unknown art family for brackenford_inn"},
		{"path": ["exterior", "structures", 0, "category"], "value": "prop", "error": "unknown art family for brackenford_inn"},
		{"path": ["exterior", "structures", 0, "collision"], "value": "wall", "error": "no wall footprint for brackenford_inn"},
		{"path": ["exterior", "structures", 0, "collision"], "value": "solid", "error": "unknown collision type for brackenford_inn"},
		{"path": ["exterior", "structures", 0, "landmark_id"], "value": "lm_missing", "error": "unknown landmark for brackenford_inn"},
		{"path": ["exterior", "structures", 0, "scale"], "value": [1, 0, 1], "error": "scale must be positive for brackenford_inn"},
		{"path": ["exterior", "structures", 0, "scale"], "value": [1, 1], "error": "invalid transform for brackenford_inn"},
		{"path": ["exterior", "structures", 0, "position"], "value": null, "error": "invalid transform for brackenford_inn"},
		{"path": ["exterior", "structures", 0, "yaw"], "value": NAN, "error": "invalid transform for brackenford_inn"},
		{"path": ["exterior", "portals", 0, "target_scene"], "value": "missing_scene", "error": "Scene missing_scene"},
		{"path": ["exterior", "portals", 0, "target_scene"], "value": "interior_crypt", "error": "inn_door must pair interior_inn/entry"},
		{"path": ["exterior", "portals", 0, "target_entrance"], "value": "missing_door", "error": "inn_door target_entrance"},
		{"path": ["exterior", "portals", 0, "return_entrance"], "value": "missing_return", "error": "inn_door return_entrance"},
		{"path": ["exterior", "portals", 0, "return_entrance"], "value": "from_crypt", "error": "inn_door must pair interior_inn/entry"},
		{"path": ["exterior", "portals", 0, "size"], "value": [1, -2, 1], "error": "inn_door size"},
		{"path": ["exterior", "portals", 0, "position"], "value": [0, INF, 0], "error": "inn_door position"},
		{"path": ["scenes", "exterior", "entrances", "from_inn"], "value": [-119, 0, 133.5], "error": "inn_door return_entrance must clear"},
		{"path": ["scenes", "exterior", "entrances", "from_inn"], "value": [400, 0, 136], "error": "exterior entrance from_inn position lies outside"},
		{"path": ["scenes", "exterior", "safe_anchor"], "value": [400, 0, 149], "error": "exterior safe_anchor position lies outside"},
		{"path": ["scenes", "interior_inn", "entrances", "entry"], "value": [0, "floor", 3], "error": "interior_inn entrance entry"},
		{"path": ["scenes", "interior_inn", "entrances"], "value": {}, "error": "interior_inn needs a nonempty entrance registry"},
		{"path": ["exterior", "objective_reservations", 0, "id"], "value": "missing_coffer", "error": "missing_coffer references an unknown container"},
		{"path": ["exterior", "objective_reservations", 0, "scene_id"], "value": "missing_scene", "error": "cart_coffer references an unknown scene_id"},
		{"path": ["exterior", "objective_reservations", 0, "radius"], "value": -1, "error": "cart_coffer radius"},
		{"path": ["exterior", "objective_reservations", 11, "position"], "value": [0, false, -40], "error": "charter_vault_coffer position"},
		{"path": ["exterior", "npc_reservations", 0, "id"], "value": "missing_speaker", "error": "missing_speaker references an unknown dialogue"},
		{"path": ["exterior", "npc_reservations", 2, "scene_id"], "value": [], "error": "tamsin_reed references an unknown scene_id"},
		{"path": ["exterior", "npc_reservations", 0, "radius"], "value": INF, "error": "mara_venn radius"},
		{"path": ["landmarks", 0, "discovery_radius"], "value": 0, "error": "lm_brackenford discovery_radius"},
		{"path": ["landmarks", 0, "discovery_radius"], "value": "wide", "error": "lm_brackenford discovery_radius"},
		{"path": ["rest_points", "village_shrine", "scene_id"], "value": "missing_scene", "error": "rest point village_shrine references an unknown scene_id"},
		{"path": ["rest_points", "inn_bed", "scene_id"], "value": "exterior", "error": "Required rest point inn_bed"},
		{"path": ["rest_points", "village_shrine", "position"], "value": [0, null, 0], "error": "rest point village_shrine position"},
		{"path": ["exterior", "hazards", 0, "shape"], "value": "sphere", "error": "millpond_deep_water deep_water shape"},
		{"path": ["exterior", "hazards", 0, "radii"], "value": [44, 0], "error": "millpond_deep_water radii"},
		{"path": ["exterior", "hazards", 0, "radii"], "value": [44, 33, 5], "error": "millpond_deep_water radii"},
		{"path": ["exterior", "hazards", 0, "center"], "value": {}, "error": "millpond_deep_water center position"},
		{"path": ["exterior", "hazards", 0, "min_y"], "value": 0, "error": "millpond_deep_water must have finite min_y below max_y"},
		{"path": ["exterior", "hazards", 0, "max_y"], "value": INF, "error": "millpond_deep_water must have finite min_y below max_y"},
		{"path": ["exterior", "hazards", 1, "maximum"], "value": [320, -40, 320], "error": "exterior_bounds minimum must be below maximum"},
		{"path": ["exterior", "hazards", 1, "maximum"], "value": [320, 90, 310], "error": "exterior_bounds horizontal limits"},
		{"path": ["exterior", "hazards", 1, "minimum"], "value": [0, 0], "error": "exterior_bounds minimum and maximum"},
		{"path": ["exterior", "hazards", 0, "kind"], "value": "lava", "error": "millpond_deep_water kind"},
		{"path": ["exterior", "pond", "radii"], "value": "large", "error": "exterior.pond requires"},
		{"path": ["exterior", "pond", "depth"], "value": -1, "error": "exterior.pond requires"},
		{"path": ["exterior", "viewpoints", 0, "targets"], "value": ["lm_missing"], "error": "unknown landmark target lm_missing"},
		{"path": ["exterior", "viewpoints", 0, "targets"], "value": ["lm_orra", "lm_orra"], "error": "repeats target lm_orra"},
		{"path": ["exterior", "viewpoints", 0, "targets"], "value": [], "error": "targets must be a nonempty landmark list"},
		{"path": ["exterior", "entrance_yaws", "start"], "value": "north", "error": "entrance_yaws/start"},
		{"path": ["exterior", "entrance_yaws"], "value": {"missing": 0}, "error": "entrance_yaws/missing"},
		{"path": ["exterior", "decor_count"], "value": 1.5, "error": "decor_count"},
		{"path": ["exterior", "terrain", "cell_size"], "value": 0, "error": "terrain.cell_size"},
		{"path": ["exterior", "terrain", "cell_size"], "value": 3, "error": "grid must tile"},
		{"path": ["exterior", "terrain", "rim_start"], "value": 320, "error": "rim_start must be inside"},
		{"path": ["exterior", "terrain", "half_extent"], "value": 400, "error": "half_extent must match"},
		{"path": ["exterior", "terrain", "navigation_cell_size"], "value": INF, "error": "navigation_cell_size"},
		{"path": ["seed"], "value": 1.5, "error": "map.seed"},
		{"path": ["bounds"], "value": -320, "error": "map.bounds"},
		{"path": ["start"], "value": [0, 0, 0], "error": "map.start must match"},
	]
	for fixture: Dictionary in cases:
		var changed: Dictionary = canonical.duplicate(true)
		var cursor: Variant = changed
		for index: int in fixture.path.size() - 1:
			cursor = cursor[fixture.path[index]]
		cursor[fixture.path.back()] = fixture.value
		_reject(t, db, changed, fixture.error)

func check_nested_types(t: SceneTree, db: Node, canonical: Dictionary) -> void:
	var paths: Array[Array] = [
		["exterior", "terrain"], ["exterior", "terrain", "half_extent"],
		["exterior", "pond"], ["exterior", "decor_count"],
		["exterior", "structures", 0, "category"], ["exterior", "structures", 0, "collision"],
		["exterior", "structures", 0, "family"], ["exterior", "structures", 0, "landmark_id"],
		["exterior", "portals", 0, "target_scene"], ["exterior", "portals", 0, "target_entrance"],
		["exterior", "portals", 0, "return_entrance"], ["exterior", "hazards", 0, "kind"],
		["exterior", "hazards", 0, "shape"], ["exterior", "hazards", 0, "min_y"],
		["exterior", "entrance_yaws"], ["exterior", "viewpoints", 0, "targets"],
		["rest_points", "village_shrine"], ["rest_points", "village_shrine", "scene_id"],
		["scenes"], ["scenes", "exterior"], ["scenes", "exterior", "entrances", "start"],
		["scenes", "interior_inn"], ["landmarks"], ["bounds"], ["start"],
	]
	for path: Array in paths:
		for value: Variant in [null, false, [], {}, NAN]:
			var changed: Dictionary = canonical.duplicate(true)
			var cursor: Variant = changed
			for index: int in path.size() - 1:
				cursor = cursor[path[index]]
			cursor[path.back()] = value
			t.check(not Validator.validate(changed, db.containers, db.dialogues).is_empty(), "R04 malformed nested value rejected at " + str(path) + ": " + str(value))

func check_record_identity(t: SceneTree, db: Node, canonical: Dictionary) -> void:
	for section: String in ["routes", "structures", "objective_reservations", "npc_reservations", "portals", "hazards", "viewpoints"]:
		var changed: Dictionary = canonical.duplicate(true)
		changed.exterior[section] = 7
		_reject(t, db, changed, "exterior." + section + " must be a list")
		changed = canonical.duplicate(true)
		changed.exterior[section][0] = false
		_reject(t, db, changed, "exterior." + section + "[0] requires a dictionary")
		changed = canonical.duplicate(true)
		changed.exterior[section][0].id = ""
		_reject(t, db, changed, "exterior." + section + "[0] requires a dictionary")
		changed = canonical.duplicate(true)
		changed.exterior[section][1].id = changed.exterior[section][0].id
		_reject(t, db, changed, "Duplicate world ID " + changed.exterior[section][0].id)
	var changed: Dictionary = canonical.duplicate(true)
	changed.exterior.structures[0].id = canonical.spawns[0].id
	_reject(t, db, changed, "Duplicate world ID " + canonical.spawns[0].id)
	changed = canonical.duplicate(true)
	changed.exterior.hazards[0].id = canonical.exterior.portals[0].id
	_reject(t, db, changed, "Duplicate world ID inn_door")

func check_registry_coverage(t: SceneTree, db: Node, canonical: Dictionary) -> void:
	var changed: Dictionary = canonical.duplicate(true)
	changed.exterior.objective_reservations.pop_back()
	_reject(t, db, changed, "Missing objective_reservations target for captain_seal_chest")
	changed = canonical.duplicate(true)
	changed.exterior.npc_reservations.pop_back()
	_reject(t, db, changed, "Missing npc_reservations target for captain_rusk")
	changed = canonical.duplicate(true)
	changed.exterior.portals.pop_back()
	_reject(t, db, changed, "Missing exterior portal undercroft_door")
	changed = canonical.duplicate(true)
	changed.rest_points.erase("village_shrine")
	_reject(t, db, changed, "Required rest point village_shrine")
	changed = canonical.duplicate(true)
	changed.exterior.entrance_yaws.erase("from_crypt")
	_reject(t, db, changed, "Missing exterior.entrance_yaws/from_crypt")
	var containers: Dictionary = db.containers.duplicate(true)
	containers.erase("cart_coffer")
	t.check("; ".join(Validator.validate(canonical, containers, db.dialogues)).contains("cart_coffer references an unknown container"), "R04 reservation requires the actual container registry target")
	var dialogues: Dictionary = db.dialogues.duplicate()
	dialogues.erase(&"mara_venn")
	t.check("; ".join(Validator.validate(canonical, db.containers, dialogues)).contains("mara_venn references an unknown dialogue"), "R04 reservation requires the actual dialogue registry target")
	changed = canonical.duplicate(true)
	changed.exterior.objective_reservations[11].position = [400, 0, -40]
	t.check(Validator.validate(changed, db.containers, db.dialogues).is_empty(), "R04 interior reservations use local coordinates independent of exterior bounds")

func _reject(t: SceneTree, db: Node, changed: Dictionary, expected: String) -> void:
	var errors: PackedStringArray = Validator.validate(changed, db.containers, db.dialogues)
	t.check("; ".join(errors).contains(expected), "R04 exterior rejects " + expected + ": " + "; ".join(errors))
