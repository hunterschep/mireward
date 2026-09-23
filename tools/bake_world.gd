extends SceneTree
## Offline deterministic navigation bake; ordinary gameplay only loads the result.
var failures: int = 0

func _initialize() -> void:
	call_deferred("verify_route_walks" if "--verify-walks" in OS.get_cmdline_user_args() else "bake")

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL " + description)

func verify_route_walks() -> void:
	var suite: RefCounted = load("res://tests/integration/test_exterior.gd").new()
	await suite.walk_all_routes(self, "--populated" in OS.get_cmdline_user_args())
	print("%s full exterior route walking, %d failures." % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)

func bake() -> void:
	var valley := MireExterior.new()
	valley.use_baked_navigation = false
	root.add_child(valley)
	await process_frame
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = MireTypes.WORLD
	mesh.cell_size = float(valley.manifest.exterior.terrain.navigation_cell_size)
	mesh.cell_height = float(valley.manifest.exterior.terrain.navigation_cell_height)
	mesh.agent_radius = 0.5
	mesh.agent_height = 2.0
	mesh.agent_max_climb = 0.4
	mesh.agent_max_slope = 40
	mesh.region_min_size = 4
	mesh.region_merge_size = 12
	mesh.edge_max_length = 16
	mesh.edge_max_error = 1.0
	mesh.filter_baking_aabb = AABB(Vector3(-274, -0.1, -274), Vector3(548, 16, 548))
	var source := NavigationMeshSourceGeometryData3D.new()
	var started: int = Time.get_ticks_msec()
	NavigationServer3D.parse_source_geometry_data(mesh, source, valley)
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	if mesh.get_polygon_count() == 0:
		printerr("Exterior navigation bake produced no walkable polygons.")
		quit(1)
		return
	if not await _connected(valley, mesh):
		printerr("Exterior navigation does not connect the start to every landmark.")
		quit(1)
		return
	mesh.set_meta("map_sha256", FileAccess.get_sha256("res://data/world/map.json"))
	var result: Error = ResourceSaver.save(mesh, MireExterior.NAVIGATION_PATH)
	if result != OK:
		printerr("Cannot save exterior navigation: " + error_string(result))
		quit(1)
		return
	var report := {"seed": int(valley.manifest.seed), "navigation_polygons": mesh.get_polygon_count(), "navigation_vertices": mesh.get_vertices().size(), "decorations": valley.decoration.size(), "landmarks": valley.landmarks.size(), "map_sha256": FileAccess.get_sha256("res://data/world/map.json")}
	var file := FileAccess.open("res://scenes/world/exterior/bake_manifest.json", FileAccess.WRITE)
	if file == null:
		printerr("Cannot save exterior bake report.")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		printerr("Cannot finish exterior bake report: " + error_string(write_error))
		quit(1)
		return
	print("Exterior baked: %d polygons, %d decorations, %d landmarks in %d ms." % [mesh.get_polygon_count(), valley.decoration.size(), valley.landmarks.size(), Time.get_ticks_msec() - started])
	quit(0)

func _connected(valley: MireExterior, mesh: NavigationMesh) -> bool:
	var region := NavigationRegion3D.new()
	region.navigation_mesh = mesh
	valley.add_child(region)
	var map_rid: RID = valley.get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map_rid, mesh.cell_size)
	NavigationServer3D.map_set_cell_height(map_rid, mesh.cell_height)
	for frame: int in 120:
		await physics_frame
		if NavigationServer3D.region_get_iteration_id(region.get_rid()) == 0 or NavigationServer3D.map_get_iteration_id(map_rid) == 0:
			continue
		var start: Vector3 = valley.entrances[&"start"].origin
		if NavigationServer3D.map_get_closest_point_owner(map_rid, start) != region.get_rid():
			continue
		if NavigationServer3D.map_get_closest_point(map_rid, start).distance_to(start) >= 1:
			return false
		for landmark: Dictionary in valley.manifest.landmarks:
			var target := ExteriorTerrain.vector(landmark.position)
			var path: PackedVector3Array = NavigationServer3D.map_get_path(map_rid, start, target, true)
			if path.size() < 2 or path[path.size() - 1].distance_to(target) >= 1:
				return false
		return true
	return false
