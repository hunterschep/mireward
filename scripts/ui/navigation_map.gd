class_name NavigationMap
extends Control

var game: MireGameRoot

func _ready() -> void:
	custom_minimum_size = Vector2(320, 310)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	draw_style_box(UIStyle.box(Color("c9c6a7"), Color("657457")), Rect2(Vector2.ZERO, size))
	var font := ThemeDB.fallback_font
	var scale: float = float(SaveService.settings.text_scale)
	var font_size := roundi(15 * scale)
	draw_string(font, Vector2(18, 26), "GREYFEN VALE   ·   N ↑", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UIStyle.INK)
	for route: Dictionary in ContentDB.map.exterior.routes:
		var points := PackedVector2Array()
		for position: Array in route.points:
			points.append(_project(Vector3(position[0], position[1], position[2])))
		draw_polyline(points, Color("8c7c59"), 3, true)
	for landmark: Dictionary in ContentDB.map.landmarks:
		if landmark.id not in GameSession.state.discoveries:
			continue
		var at := _project(Vector3(landmark.position[0], landmark.position[1], landmark.position[2]))
		draw_circle(at, 5, UIStyle.INK)
		draw_string(font, at + Vector2(8, -6), landmark.name, HORIZONTAL_ALIGNMENT_LEFT, maxf(30, size.x - at.x - 16), font_size, UIStyle.INK)
	if game == null or not GameSession.active:
		return
	var position: Vector3 = game.player.global_position
	if game.router.loaded_scene_id != &"exterior":
		var exit_id := "from_" + String(game.router.loaded_scene_id).trim_prefix("interior_")
		var entrance: Array = ContentDB.map.scenes.exterior.entrances.get(exit_id, ContentDB.map.start)
		position = Vector3(entrance[0], entrance[1], entrance[2])
	var at := _project(position)
	draw_circle(at, 9, Color("f9f1d3"))
	draw_circle(at, 5, Color("334e6b"))
	draw_string(font, at + Vector2(10, 22), "You" if game.router.loaded_scene_id == &"exterior" else "Your entrance", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UIStyle.INK)
	var tracked := GameSession.quests.tracked_view()
	if not tracked.is_empty():
		var located := locate_target(game, StringName(tracked.objective.get("hint_target_id", tracked.objective.target_id)))
		if located.get("scene_id") == "exterior":
			var target := _project(located.position)
			draw_circle(target, 10, Color("8b632c"), false, 3)
			draw_line(target - Vector2(0, 13), target + Vector2(0, 13), Color("8b632c"), 2)
			draw_line(target - Vector2(13, 0), target + Vector2(13, 0), Color("8b632c"), 2)

func _project(position: Vector3) -> Vector2:
	var area := Rect2(Vector2(36, 43), (size - Vector2(72, 74)).max(Vector2.ONE))
	return area.position + Vector2((position.x + 320) / 640, (position.z + 320) / 640) * area.size

static func locate_target(owner: MireGameRoot, id: StringName) -> Dictionary:
	var world: Node3D = owner.router.current_world
	if is_instance_valid(world) and world.entities.has(id) and world.entities[id] is Node3D:
		return {"position": world.entities[id].global_position, "scene_id": String(owner.router.loaded_scene_id)}
	for section: String in ["portals", "npc_reservations", "objective_reservations"]:
		for row: Dictionary in ContentDB.map.exterior.get(section, []):
			if row.id == String(id):
				return {"position": Vector3(row.position[0], row.position[1], row.position[2]), "scene_id": row.get("scene_id", "exterior")}
	for row: Dictionary in ContentDB.map.spawns:
		if row.id == String(id):
			return {"position": Vector3(row.position[0], row.position[1], row.position[2]), "scene_id": row.scene_id}
	return {}
