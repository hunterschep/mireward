extends Node3D
## Standalone art review. --capture writes both 540p review views and exits.

var _actors: Array[Node3D] = []
var _camera: Camera3D
var _time: float = 0.0

func _ready() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("a8b2aa")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("b1b9b0")
	settings.ambient_light_energy = 0.42
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	add_child(environment)
	var sunlight := DirectionalLight3D.new()
	sunlight.rotation_degrees = Vector3(-42, -28, 0)
	sunlight.light_color = Color("ffe3b3")
	sunlight.light_energy = 0.95
	sunlight.shadow_enabled = true
	add_child(sunlight)
	ArtMesh.box(self, "Meadow", Vector3(60, 0.2, 55), Vector3(0, -0.12, -6), "moss")
	ArtMesh.box(self, "VillagePath", Vector3(34, 0.025, 5), Vector3(0, -0.009, 1), "stone")
	_place(VisualFactory.building(&"cottage"), Vector3(-8, 0, -8))
	_place(VisualFactory.building(&"forge"), Vector3(0, 0, -12))
	_place(VisualFactory.building(&"inn"), Vector3(8, 0, -9))
	_place(VisualFactory.building(&"monastery_arch"), Vector3(-16, 0, -6))
	_place(VisualFactory.building(&"monastery_tower"), Vector3(-20, 0, -20))
	_place(VisualFactory.building(&"keep"), Vector3(17, 0, -22))
	for x: float in [-21, -13, 13, 23]:
		_place(VisualFactory.prop(&"oak"), Vector3(x, 0, -2))
		_place(VisualFactory.prop(&"pine"), Vector3(x - 2, 0, -18))
	for index: int in 5:
		var model := VisualFactory.actor(ArtActors.ARCHETYPES[index])
		_place(model, Vector3(-3.2 + index * 1.6, 0, -1.4))
		_actors.append(model)
	_place(VisualFactory.prop(&"writ_table"), Vector3(-6, 0, 1.1))
	_place(VisualFactory.prop(&"shrine"), Vector3(5.8, 0, -1.2))
	_place(VisualFactory.prop(&"medicine_chest"), Vector3(-4.7, 0, -0.7))
	_place(VisualFactory.prop(&"banner_crown"), Vector3(7.6, 0, -2))
	_place(VisualFactory.prop(&"cart"), Vector3(-9.5, 0, -1))
	for index: int in 3:
		_place(VisualFactory.prop(ArtProps.KINDS[11 + index]), Vector3(9.5 + index, 0, -1))
	_place(VisualFactory.building(&"crypt_room"), Vector3(40, 0, 0))
	_place(VisualFactory.prop(&"shrine"), Vector3(40, 0.12, -3))
	for index: int in 3:
		_place(VisualFactory.prop(ArtProps.KINDS[11 + index]), Vector3(37.2 + index, 0.12, -2))
	var interior_light := OmniLight3D.new()
	interior_light.position = Vector3(40, 2.7, -1)
	interior_light.omni_range = 10
	interior_light.light_energy = 1.5
	interior_light.light_color = Color("e1b978")
	add_child(interior_light)
	_camera = Camera3D.new()
	_camera.fov = 65
	_camera.position = Vector3(9, 6, 12)
	add_child(_camera)
	_camera.look_at(Vector3(0, 1.2, -4))
	_camera.current = true
	if "--capture" in OS.get_cmdline_user_args():
		_capture()

func _place(node: Node3D, at: Vector3) -> void:
	node.position = at
	node.rotation.y = PI
	add_child(node)

func _process(delta: float) -> void:
	_time += delta
	for model: Node3D in _actors:
		VisualFactory.pose(model, &"idle", _time)

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute("res://tests/output/art")
	get_window().size = Vector2i(960, 540)
	get_viewport().size = Vector2i(960, 540)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/output/art/showcase_540.png")
	_camera.position = Vector3(2.6, 1.65, 2.5)
	_camera.look_at(Vector3(2.1, 1.15, -1.4))
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/output/art/knights_first_person_540.png")
	_camera.position = Vector3(40, 1.65, 3.4)
	_camera.look_at(Vector3(40, 1.5, -2.5))
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/output/art/crypt_first_person_540.png")
	print("Showcase screenshots saved to tests/output/art")
	get_tree().quit()
