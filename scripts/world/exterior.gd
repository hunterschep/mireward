class_name MireExterior
extends Node3D
## World-only scene. Router supplies the persistent player and gameplay adapters.

signal navigation_synchronized
const NAVIGATION_PATH := "res://scenes/world/exterior/exterior_nav.tres"
var scene_id: StringName = &"exterior"
var entrances: Dictionary = {}
var rest_anchors: Dictionary = {}
var entities: Dictionary = {}
var navigation_regions: Array[NavigationRegion3D] = []
var landmarks: Dictionary = {}
var landmark_areas: Dictionary = {}
var hazard_definitions: Array = []
var objective_reservations: Dictionary = {}
var npc_reservations: Dictionary = {}
var portal_definitions: Array = []
var decoration: Array[Dictionary] = []
var manifest: Dictionary = {}
var use_baked_navigation: bool = true
var navigation_error: String = ""
var _navigation_ready: bool = false

func _ready() -> void:
	manifest = get_node("/root/ContentDB").map.duplicate(true)
	_build_registry()
	ExteriorTerrain.build(self, manifest)
	landmarks = ExteriorLandmarks.build(self, manifest)
	decoration = ExteriorDecor.build(self, manifest)
	_lighting()
	_discovery_areas()
	if use_baked_navigation and not navigation_cache_current():
		navigation_error = "The exterior navigation cache does not match the map. Run tools/bake_world.gd."
		push_warning(navigation_error)
	elif use_baked_navigation:
		var region := NavigationRegion3D.new()
		region.name = "ValleyNavigation"
		region.navigation_mesh = load(NAVIGATION_PATH) as NavigationMesh
		add_child(region)
		navigation_regions.append(region)
		var map_rid: RID = get_world_3d().navigation_map
		NavigationServer3D.map_set_cell_size(map_rid, region.navigation_mesh.cell_size)
		NavigationServer3D.map_set_cell_height(map_rid, region.navigation_mesh.cell_height)
		_wait_for_navigation()

func _build_registry() -> void:
	for id: String in manifest.scenes.exterior.entrances:
		var origin := ExteriorTerrain.vector(manifest.scenes.exterior.entrances[id])
		var yaw: float = float(manifest.exterior.entrance_yaws.get(id, 0))
		entrances[StringName(id)] = Transform3D(Basis(Vector3.UP, yaw), origin)
	for id: String in manifest.rest_points:
		var anchor: Dictionary = manifest.rest_points[id]
		if anchor.scene_id == "exterior":
			rest_anchors[StringName(id)] = Transform3D(Basis.IDENTITY, ExteriorTerrain.vector(anchor.position))
	for row: Dictionary in manifest.exterior.objective_reservations:
		objective_reservations[StringName(row.id)] = row.duplicate(true)
	for row: Dictionary in manifest.exterior.npc_reservations:
		npc_reservations[StringName(row.id)] = row.duplicate(true)
	hazard_definitions = manifest.exterior.hazards.duplicate(true)
	portal_definitions = manifest.exterior.portals.duplicate(true)

func _discovery_areas() -> void:
	for landmark: Dictionary in manifest.landmarks:
		var area := Area3D.new()
		area.name = String(landmark.id) + "_discovery"
		area.position = ExteriorTerrain.vector(landmark.position)
		area.collision_layer = MireTypes.TRIGGER
		area.collision_mask = MireTypes.PLAYER
		area.set_meta("landmark_id", StringName(landmark.id))
		var collision := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = float(landmark.discovery_radius)
		shape.height = 12
		collision.shape = shape
		collision.position.y = 3
		area.add_child(collision)
		add_child(area)
		landmark_areas[StringName(landmark.id)] = area

func is_navigation_ready() -> bool:
	return _navigation_ready

func navigation_cache_current() -> bool:
	if not ResourceLoader.exists(NAVIGATION_PATH):
		return false
	var mesh := load(NAVIGATION_PATH) as NavigationMesh
	return mesh != null and mesh.get_meta("map_sha256", "") == FileAccess.get_sha256("res://data/world/map.json")

func _wait_for_navigation() -> void:
	for frame: int in 120:
		await get_tree().physics_frame
		if not is_inside_tree() or navigation_regions.is_empty():
			return
		var map_rid: RID = get_world_3d().navigation_map
		var region: NavigationRegion3D = navigation_regions[0]
		var start: Vector3 = entrances[&"start"].origin
		if NavigationServer3D.map_get_iteration_id(map_rid) > 0 and NavigationServer3D.region_get_iteration_id(region.get_rid()) > 0 and NavigationServer3D.map_get_closest_point_owner(map_rid, start) == region.get_rid() and NavigationServer3D.map_get_closest_point(map_rid, start).distance_to(start) < 1.0:
			_navigation_ready = true
			navigation_synchronized.emit()
			return
	navigation_error = "Exterior navigation failed to synchronize; regenerate the authored navigation resource."
	push_error(navigation_error)

func _lighting() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("697c78")
	sky_material.sky_horizon_color = Color("bcc0ac")
	sky_material.ground_horizon_color = Color("b2b7a1")
	sky_material.ground_bottom_color = Color("68736b")
	sky.sky_material = sky_material
	settings.sky = sky
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("b1b9b0")
	settings.ambient_light_energy = 0.45
	settings.fog_enabled = true
	settings.fog_light_color = Color("a8b2aa")
	settings.fog_density = 0.0015
	settings.fog_sky_affect = 0.12
	environment.environment = settings
	add_child(environment)
	var sunlight := DirectionalLight3D.new()
	sunlight.name = "LateAfternoonSun"
	sunlight.rotation_degrees = Vector3(-33, -32, 0)
	sunlight.light_color = Color("f3d4a3")
	sunlight.light_energy = 1.0
	sunlight.shadow_enabled = true
	sunlight.directional_shadow_max_distance = 90
	add_child(sunlight)
