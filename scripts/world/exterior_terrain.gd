class_name ExteriorTerrain
extends RefCounted
## Seeded terrain with level authored travel and interaction corridors.

static func vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

static func height_at(x: float, z: float, map: Dictionary) -> float:
	var point := Vector2(x, z)
	var distance: float = route_distance(point, map)
	for landmark: Dictionary in map.landmarks:
		var at := vector(landmark.position)
		distance = minf(distance, point.distance_to(Vector2(at.x, at.z)) - 22)
	for structure: Dictionary in map.exterior.structures:
		var at := vector(structure.position)
		distance = minf(distance, point.distance_to(Vector2(at.x, at.z)) - 12)
	for row: Dictionary in map.spawns + map.exterior.objective_reservations + map.exterior.npc_reservations:
		if row.scene_id == "exterior":
			var at := vector(row.position)
			distance = minf(distance, point.distance_to(Vector2(at.x, at.z)) - 10)
	var hills: float = maxf(0, 2.8 * sin(x * 0.024) * cos(z * 0.018) + 1.3 * sin((x + z) * 0.017) + 1.0)
	var height: float = hills * smoothstep(12.0, 32.0, distance)
	var terrain: Dictionary = map.exterior.terrain
	var edge: float = maxf(absf(x), absf(z))
	var rim: float = smoothstep(float(terrain.rim_start), float(terrain.half_extent), edge)
	height += rim * float(terrain.rim_height) * (0.85 + 0.15 * sin((x - z) * 0.033))
	var pond: Dictionary = map.exterior.pond
	var center := vector(pond.center)
	var ellipse := Vector2((x - center.x) / float(pond.radii[0]), (z - center.z) / float(pond.radii[1])).length()
	height -= float(pond.depth) * (1.0 - smoothstep(0.55, 1.08, ellipse))
	return height

static func route_distance(point: Vector2, map: Dictionary) -> float:
	var nearest: float = INF
	for route: Dictionary in map.exterior.routes:
		for index: int in route.points.size() - 1:
			var a := vector(route.points[index])
			var b := vector(route.points[index + 1])
			var close := Geometry2D.get_closest_point_to_segment(point, Vector2(a.x, a.z), Vector2(b.x, b.z))
			nearest = minf(nearest, point.distance_to(close) - float(route.width) / 2)
	return nearest

static func build(parent: Node3D, map: Dictionary) -> void:
	var config: Dictionary = map.exterior.terrain
	var half: int = int(config.half_extent)
	var chunk: int = int(config.chunk_size)
	var step: int = int(config.cell_size)
	var ground := StandardMaterial3D.new()
	ground.vertex_color_use_as_albedo = true
	ground.roughness = 1.0
	for start_x: int in range(-half, half, chunk):
		for start_z: int in range(-half, half, chunk):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			for x: int in range(start_x, start_x + chunk, step):
				for z: int in range(start_z, start_z + chunk, step):
					var a := Vector3(x, height_at(x, z, map), z)
					var b := Vector3(x + step, height_at(x + step, z, map), z)
					var c := Vector3(x + step, height_at(x + step, z + step, map), z + step)
					var d := Vector3(x, height_at(x, z + step, map), z + step)
					var tint := Color("687044") if (x / step + z / step) % 5 == 0 else Color("626d48")
					if maxf(a.y, c.y) > 12:
						tint = Color("68736b") if x % 3 else Color("485850")
					for triangle: Array in [[a, b, c], [a, c, d]]:
						var normal: Vector3 = (triangle[2] - triangle[0]).cross(triangle[1] - triangle[0]).normalized()
						for vertex: Vector3 in triangle:
							surface.set_normal(normal)
							surface.set_color(tint)
							surface.add_vertex(vertex)
			var mesh: ArrayMesh = surface.commit()
			var tile := MeshInstance3D.new()
			tile.name = "Terrain_%d_%d" % [start_x, start_z]
			tile.mesh = mesh
			tile.material_override = ground
			parent.add_child(tile)
			var body := StaticBody3D.new()
			body.collision_layer = MireTypes.WORLD
			body.collision_mask = 0
			var collision := CollisionShape3D.new()
			collision.shape = mesh.create_trimesh_shape()
			body.add_child(collision)
			parent.add_child(body)
	_roads(parent, map)
	_pond(parent, map)
	for side: int in [-1, 1]:
		_boundary(parent, Vector3(side * 321, 40, 0), Vector3(2, 90, 644))
		_boundary(parent, Vector3(0, 40, side * 321), Vector3(644, 90, 2))

static func _roads(parent: Node3D, map: Dictionary) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for route: Dictionary in map.exterior.routes:
		for index: int in route.points.size() - 1:
			var a := vector(route.points[index]) + Vector3.UP * 0.035
			var b := vector(route.points[index + 1]) + Vector3.UP * 0.035
			var side := (b - a).normalized().cross(Vector3.UP) * float(route.width) / 2
			for vertex: Vector3 in [a - side, b - side, b + side, a - side, b + side, a + side]:
				surface.set_normal(Vector3.UP)
				surface.add_vertex(vertex)
	var roads := MeshInstance3D.new()
	roads.name = "AuthoredRoads"
	roads.mesh = surface.commit()
	roads.material_override = ArtMesh.material("wood")
	parent.add_child(roads)

static func _pond(parent: Node3D, map: Dictionary) -> void:
	var pond: Dictionary = map.exterior.pond
	var center := vector(pond.center)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in 40:
		var a: float = index * TAU / 40
		var b: float = (index + 1) * TAU / 40
		for vertex: Vector3 in [center, center + Vector3(cos(a) * pond.radii[0], 0, sin(a) * pond.radii[1]), center + Vector3(cos(b) * pond.radii[0], 0, sin(b) * pond.radii[1])]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(vertex)
	ArtMesh.mesh(parent, "MillpondWater", surface.commit(), Vector3.ZERO, "water")

static func _boundary(parent: Node3D, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "RidgeBoundary"
	body.collision_layer = MireTypes.WORLD
	body.collision_mask = 0
	body.position = at
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	parent.add_child(body)
