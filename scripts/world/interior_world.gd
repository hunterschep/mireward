class_name MireInterior
extends Node3D
## Deterministic rooms, collision and navigation share the same floor and obstacle plan.

signal navigation_synchronized
@export var scene_id: StringName = &"interior_inn"
var entrances: Dictionary = {}
var rest_anchors: Dictionary = {}
var entities: Dictionary = {}
var navigation_regions: Array[NavigationRegion3D] = []
var portal_definitions: Array = []
var hazard_definitions: Array = []
var navigation_error: String = ""
var rooms: Dictionary = {}
var _floors: Array[Rect2] = []
var _obstacles: Array[AABB] = []
var _navigation_ready: bool = false

func _ready() -> void:
	var manifest: Dictionary = get_node("/root/ContentDB").map
	for id: String in manifest.scenes[String(scene_id)].entrances:
		entrances[StringName(id)] = Transform3D(Basis.IDENTITY, _vector(manifest.scenes[String(scene_id)].entrances[id]))
	for id: String in manifest.rest_points:
		var row: Dictionary = manifest.rest_points[id]
		if row.scene_id == String(scene_id):
			rest_anchors[StringName(id)] = Transform3D(Basis.IDENTITY, _vector(row.position))
	match scene_id:
		&"interior_inn": _inn()
		&"interior_crypt": _crypt()
		&"interior_undercroft": _undercroft()
	var suffix := String(scene_id).trim_prefix("interior_")
	portal_definitions.append({"id": suffix + "_exit", "position": [0, 0, 5.5], "size": [1.5, 2.5, 0.6], "target_scene": "exterior", "target_entrance": "from_" + suffix})
	_prop(&"door", Vector3(0, 0, 5.6), Vector3(1.5, 2.5, 0.18), PI)
	_build_navigation()
	_lighting()
	_wait_for_navigation()

func is_navigation_ready() -> bool:
	return _navigation_ready

func _inn() -> void:
	_room("CommonRoom", Rect2(-7, -7, 14, 13), 3.6, "linen")
	rooms = {&"common_room": Vector3(2, 0, -2), &"sleeping_alcove": Vector3(-4, 0, -2)}
	# Partition leaves a broad opening beside the canonical bedside anchor.
	_wall(Vector3(-1.7, 1.5, -5), Vector3(0.25, 3, 4), "timber")
	_wall(Vector3(-4.3, 1.5, 0.5), Vector3(5.2, 3, 0.25), "timber")
	_prop(&"bed", Vector3(-5.4, 0, -2.6), Vector3(1.05, 0.6, 2.05))
	for at: Vector3 in [Vector3(3.8, 0, -4.4), Vector3(3.8, 0, -0.5)]:
		_prop(&"bench", at, Vector3(1.7, 0.65, 0.7))
	_prop(&"barrel", Vector3(6, 0, -5.7), Vector3(0.65, 0.85, 0.65))
	for x: float in [-6.5, 6.5]:
		_wall(Vector3(x, 2.3, -0.5), Vector3(0.2, 0.22, 12), "timber")
		_prop(&"lantern", Vector3(x * 0.8, 2.1, -4), Vector3.ZERO)

func _crypt() -> void:
	_room("CryptShell", Rect2(-7, -43, 14, 49), 4.2, "stone")
	rooms = {&"vestibule": Vector3(0, 0, 0), &"reed_chamber": Vector3(0, 0, -11), &"stone_chamber": Vector3(0, 0, -21), &"flame_chamber": Vector3(0, 0, -31), &"charter_vault": Vector3(0, 0, -39)}
	for z: float in [-5, -15, -25, -35]:
		_partition(z, 14, 4, 4.2)
		var arch := VisualFactory.building(&"monastery_arch")
		arch.position = Vector3(0, 0, z)
		arch.scale = Vector3(1.3, 1.15, 0.7)
		add_child(arch)
	for z: float in [-10, -20, -30]:
		for side: float in [-1, 1]:
			_wall(Vector3(side * 5.8, 0.4, z), Vector3(1.1, 0.8, 3.2), "slate")
			_wall(Vector3(side * 5.8, 0.88, z), Vector3(1.24, 0.16, 3.34), "stone")
			_prop(&"candle", Vector3(side * 5.8, 0.97, z), Vector3.ZERO)

func _undercroft() -> void:
	_room("UndercroftShell", Rect2(-8, -55, 16, 61), 4.5, "stone")
	rooms = {&"storehouse": Vector3(0, 0, -6), &"guard_corridor": Vector3(0, 0, -24), &"captains_hall": Vector3(0, 0, -45)}
	_partition(-17, 16, 5, 4.5)
	_partition(-33, 16, 5, 4.5)
	for side: float in [-1, 1]:
		_wall(Vector3(side * 4.2, 2.25, -25), Vector3(0.4, 4.5, 16), "stone")
		for z: float in [-2, -7, -12]:
			_prop(&"crate", Vector3(side * 6.2, 0, z), Vector3(0.75, 0.7, 0.65))
			_prop(&"sack", Vector3(side * 5.1, 0, z + 0.4), Vector3(0.65, 0.9, 0.65))
		for z: float in [-38, -47]:
			_wall(Vector3(side * 7, 2.25, z), Vector3(0.55, 4.5, 0.65), "slate")
		_prop(&"banner_crown", Vector3(side * 6.4, 0, -52), Vector3.ZERO)

func _room(label: String, footprint: Rect2, height: float, color: String) -> void:
	_floors.append(footprint)
	var center := footprint.get_center()
	var room := Node3D.new()
	room.name = label
	add_child(room)
	_solid(room, "Floor", Vector3(center.x, -0.15, center.y), Vector3(footprint.size.x, 0.3, footprint.size.y), "slate", false)
	_solid(room, "Ceiling", Vector3(center.x, height + 0.15, center.y), Vector3(footprint.size.x, 0.3, footprint.size.y), color, false)
	for side: float in [-1, 1]:
		_wall(Vector3(center.x + side * footprint.size.x / 2, height / 2, center.y), Vector3(0.3, height, footprint.size.y), color)
		_wall(Vector3(center.x, height / 2, center.y + side * footprint.size.y / 2), Vector3(footprint.size.x, height, 0.3), color)

func _partition(z: float, width: float, gap: float, height: float) -> void:
	for side: float in [-1, 1]:
		_wall(Vector3(side * (width + gap) / 4, height / 2, z), Vector3((width - gap) / 2, height, 0.4), "stone")
	_wall(Vector3(0, 3.65, z), Vector3(gap, height - 3.0, 0.4), "stone", false)

func _wall(at: Vector3, size: Vector3, color: String, blocks_navigation: bool = true) -> void:
	_solid(self, "Masonry", at, size, color, blocks_navigation)

func _solid(parent: Node3D, label: String, at: Vector3, size: Vector3, color: String, blocks_navigation: bool) -> void:
	ArtMesh.box(parent, label, size, at, color)
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = MireTypes.WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	if blocks_navigation:
		_obstacles.append(AABB(at - size / 2, size))

func _prop(kind: StringName, at: Vector3, size: Vector3, yaw: float = 0) -> void:
	var visual := VisualFactory.prop(kind)
	visual.position = at
	visual.rotation.y = yaw
	add_child(visual)
	if size == Vector3.ZERO:
		return
	var body := StaticBody3D.new()
	body.collision_layer = MireTypes.WORLD
	body.collision_mask = 0
	body.position = at + Vector3.UP * size.y / 2
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	_obstacles.append(AABB(body.position - size / 2, size))

func _build_navigation() -> void:
	# Authored flat cells share vertices, so region topology cannot bridge a wall.
	var mesh := NavigationMesh.new()
	mesh.cell_size = 0.5
	mesh.cell_height = 0.2
	mesh.agent_radius = 0.4
	mesh.agent_height = 1.8
	var vertices := PackedVector3Array()
	var indices: Dictionary = {}
	var polygons: Array[PackedInt32Array] = []
	for floor_rect: Rect2 in _floors:
		for xi: int in range(ceili(floor_rect.position.x * 2), floori(floor_rect.end.x * 2)):
			for zi: int in range(ceili(floor_rect.position.y * 2), floori(floor_rect.end.y * 2)):
				var center := Vector3((xi + 0.5) / 2, 0.9, (zi + 0.5) / 2)
				var blocked: bool = false
				for obstacle: AABB in _obstacles:
					if obstacle.grow(0.62).has_point(center):
						blocked = true
						break
				if blocked:
					continue
				var polygon := PackedInt32Array()
				for corner: Vector2i in [Vector2i(xi, zi), Vector2i(xi, zi + 1), Vector2i(xi + 1, zi + 1), Vector2i(xi + 1, zi)]:
					if not indices.has(corner):
						indices[corner] = vertices.size()
						vertices.append(Vector3(corner.x / 2.0, 0, corner.y / 2.0))
					polygon.append(indices[corner])
				polygons.append(polygon)
	mesh.vertices = vertices
	for polygon: PackedInt32Array in polygons:
		mesh.add_polygon(polygon)
	var region := NavigationRegion3D.new()
	region.name = "InteriorNavigation"
	region.navigation_mesh = mesh
	add_child(region)
	navigation_regions.append(region)
	NavigationServer3D.map_set_cell_size(get_world_3d().navigation_map, mesh.cell_size)
	NavigationServer3D.map_set_cell_height(get_world_3d().navigation_map, mesh.cell_height)

func _wait_for_navigation() -> void:
	for frame: int in 120:
		await get_tree().physics_frame
		if not is_inside_tree():
			return
		var map_rid: RID = get_world_3d().navigation_map
		var region: NavigationRegion3D = navigation_regions[0]
		var entry: Vector3 = entrances[&"entry"].origin
		if NavigationServer3D.map_get_iteration_id(map_rid) > 0 and NavigationServer3D.region_get_iteration_id(region.get_rid()) > 0 and NavigationServer3D.map_get_closest_point_owner(map_rid, entry) == region.get_rid():
			_navigation_ready = true
			navigation_synchronized.emit()
			return
	navigation_error = "Interior navigation did not synchronize."

func _lighting() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("242b28")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b1b9b0")
	environment.ambient_light_energy = 0.65 if scene_id == &"interior_inn" else 0.42
	world_environment.environment = environment
	add_child(world_environment)
	var locations: Array[Vector3] = [Vector3(0, 3.1, 0), Vector3(0, 3.1, -13), Vector3(0, 3.1, -27), Vector3(0, 3.1, -43)]
	if scene_id == &"interior_inn":
		locations = [Vector3(0, 2.7, -2)]
	for at: Vector3 in locations:
		var light := OmniLight3D.new()
		light.position = at
		light.light_color = Color("e1b978")
		light.light_energy = 1.15
		light.omni_range = 13
		add_child(light)

func _vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])
