extends Node
## Short background GPU review using an always-updating offscreen viewport.

func _ready() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var valley := MireExterior.new()
	viewport.add_child(valley)
	var camera := Camera3D.new()
	camera.fov = 75
	camera.far = 850
	viewport.add_child(camera)
	camera.current = true
	DirAccess.make_dir_recursive_absolute("res://tests/output/exterior")
	var views: Array[Dictionary] = [
		{"id": "village_540", "from": Vector3(-107, 2.2, 170), "to": Vector3(-112, 3, 135)},
		{"id": "valley_overview_540", "from": Vector3(250, 145, 290), "to": Vector3(-20, 0, -30)},
		{"id": "south_monastery_540", "from": Vector3(32, 1.65, 252), "to": Vector3(187, 15, -101)},
		{"id": "south_castle_540", "from": Vector3(32, 1.65, 252), "to": Vector3(40, 12, -252)},
		{"id": "north_monastery_540", "from": Vector3(-10, 1.65, -60), "to": Vector3(187, 15, -101)},
		{"id": "north_castle_540", "from": Vector3(-10, 1.65, -60), "to": Vector3(40, 12, -252)}
	]
	for view: Dictionary in views:
		camera.position = view.from
		camera.look_at(view.to)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var result: Error = viewport.get_texture().get_image().save_png("res://tests/output/exterior/" + view.id + ".png")
		if result != OK:
			printerr("Could not save exterior review image: " + view.id)
			get_tree().quit(1)
			return
	print("Saved six exterior GPU review images.")
	get_tree().quit(0)
