class_name ArtMesh
extends RefCounted
## Flat-shaded meter-scale geometry and the shared Greyfen palette.

const PALETTE := {
	"peat": "242b28", "fog": "a8b2aa", "stone": "68736b", "reed": "777844",
	"rust": "824d3c", "warm": "e1b978", "parchment": "d8ceb1", "wood": "574939",
	"timber": "3b352d", "moss": "465846", "slate": "485850", "iron": "7b8881",
	"dark_iron": "444e4c", "skin": "b48e6e", "skin_dark": "886a51", "linen": "ada68d",
	"water": "536f70", "flame": "e5b46e", "ochre": "a38a51", "ink": "292f2c",
}
static var _materials: Dictionary = {}

static func material(key: String) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.resource_name = "Greyfen_" + key
	mat.albedo_color = Color(PALETTE.get(key, PALETTE.stone))
	mat.roughness = 0.92
	if key in ["iron", "dark_iron"]:
		mat.metallic = 0.42
		mat.roughness = 0.66
	if key == "flame":
		mat.emission_enabled = true
		mat.emission = Color(PALETTE.warm)
		mat.emission_energy_multiplier = 0.75
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	if key in ["stone", "timber", "linen", "parchment"]:
		var texture_path: String = "res://assets/textures/" + key + ".png"
		if FileAccess.file_exists(texture_path + ".import"):
			mat.albedo_texture = load(texture_path) as Texture2D
			mat.albedo_color = Color.WHITE
			mat.uv1_triplanar = true
			mat.uv1_world_triplanar = true
			mat.uv1_scale = Vector3.ONE * (2.0 if key == "linen" else 0.5)
	_materials[key] = mat
	return mat

static func root(label: String) -> Node3D:
	var node := Node3D.new()
	node.name = label
	return node

static func pivot(parent: Node3D, label: String, at: Vector3) -> Node3D:
	var node := root(label)
	node.position = at
	parent.add_child(node, true)
	return node

static func mesh(parent: Node3D, label: String, shape: Mesh, at: Vector3, color: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = shape
	instance.material_override = material(color)
	instance.position = at
	parent.add_child(instance, true)
	return instance

static func box(parent: Node3D, label: String, size: Vector3, at: Vector3, color: String) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return mesh(parent, label, shape, at, color)

static func cylinder(parent: Node3D, label: String, bottom: float, top: float, height: float, at: Vector3, color: String, sides: int = 8) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.bottom_radius = bottom
	shape.top_radius = top
	shape.height = height
	shape.radial_segments = sides
	shape.rings = 1
	return mesh(parent, label, shape, at, color)

static func sphere(parent: Node3D, label: String, radius: float, at: Vector3, color: String) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius = radius
	shape.height = radius * 2.0
	shape.radial_segments = 6
	shape.rings = 3
	return mesh(parent, label, shape, at, color)

static func beam(parent: Node3D, label: String, a: Vector3, b: Vector3, width: float, depth: float, color: String) -> MeshInstance3D:
	var instance := box(parent, label, Vector3(width, a.distance_to(b), depth), (a + b) / 2.0, color)
	instance.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	return instance

## A solid silhouette in XY extruded along Z; vertices must be counterclockwise.
static func prism(parent: Node3D, label: String, points: PackedVector2Array, depth: float, at: Vector3, color: String) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := Geometry2D.triangulate_polygon(points)
	for side: float in [-1.0, 1.0]:
		for index: int in range(0, faces.size(), 3):
			var order: Array[int] = [faces[index], faces[index + 1], faces[index + 2]]
			if side < 0.0:
				order.reverse()
			for point_index: int in order:
				var point := points[point_index]
				surface.set_normal(Vector3(0, 0, side))
				surface.set_uv(point)
				surface.add_vertex(Vector3(point.x, point.y, depth * side / 2.0))
	for index: int in points.size():
		var a := points[index]
		var b := points[(index + 1) % points.size()]
		var normal := Vector3(b.y - a.y, a.x - b.x, 0).normalized()
		for vertex: Vector3 in [Vector3(a.x, a.y, -depth / 2), Vector3(b.x, b.y, depth / 2), Vector3(b.x, b.y, -depth / 2), Vector3(a.x, a.y, -depth / 2), Vector3(a.x, a.y, depth / 2), Vector3(b.x, b.y, depth / 2)]:
			surface.set_normal(normal)
			surface.set_uv(Vector2(vertex.x, vertex.y))
			surface.add_vertex(vertex)
	var result := mesh(parent, label, surface.commit(), at, color)
	# Both sides remain visible on handmade silhouette meshes.
	var mat := material(color).duplicate() as StandardMaterial3D
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	result.material_override = mat
	return result

static func own_tree(node: Node, owner_root: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner_root
		own_tree(child, owner_root)

## Static families submit one mesh per material, regardless of assembled detail.
static func batch(node: Node3D) -> void:
	var groups: Dictionary = {}
	var originals: Array[MeshInstance3D] = []
	_collect_meshes(node, Transform3D.IDENTITY, groups, originals)
	for key: String in groups:
		var group: Dictionary = groups[key]
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for entry: Dictionary in group.entries:
			var source: MeshInstance3D = entry.node
			for index: int in source.mesh.get_surface_count():
				surface.append_from(source.mesh, index, entry.transform)
		var combined := MeshInstance3D.new()
		combined.name = "Surface_" + key
		combined.mesh = surface.commit()
		combined.material_override = group.material
		node.add_child(combined)
	for original: MeshInstance3D in originals:
		original.get_parent().remove_child(original)
		original.free()

static func _collect_meshes(node: Node3D, parent_transform: Transform3D, groups: Dictionary, originals: Array[MeshInstance3D]) -> void:
	for child: Node in node.get_children():
		if not child is Node3D:
			continue
		var spatial := child as Node3D
		var local: Transform3D = parent_transform * spatial.transform
		if spatial is MeshInstance3D:
			var instance := spatial as MeshInstance3D
			var mat := instance.material_override as StandardMaterial3D
			var key: String = mat.resource_name + ("_two_sided" if mat.cull_mode == BaseMaterial3D.CULL_DISABLED else "")
			if not groups.has(key):
				groups[key] = {"material": mat, "entries": []}
			groups[key].entries.append({"node": instance, "transform": local})
			originals.append(instance)
		_collect_meshes(spatial, local, groups, originals)
