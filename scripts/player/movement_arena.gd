extends Node3D

func _ready() -> void:
	GameSession.new_game()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("a8b2aa")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d8ceb1")
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -28, 0)
	sun.light_color = Color("e1b978")
	sun.shadow_enabled = true
	add_child(sun)
	box(Vector3(100, 1, 100), Vector3(0, -0.5, 0), "moss")
	box(Vector3(10, 3, 0.5), Vector3(0, 1.5, -12), "stone")
	box(Vector3(0.5, 3, 10), Vector3(-12, 1.5, -8), "stone")
	for step: int in 5:
		box(Vector3(3, 0.15 * (step + 1), 0.6), Vector3(7, 0.075 * (step + 1), -3 - step * 0.6), "stone")
	var slope := box(Vector3(3, 0.3, 5), Vector3(-6, 0.8, -5), "wood")
	slope.rotation.x = deg_to_rad(20)
	for id: StringName in [&"cutpurse", &"levy_spearman", &"hollow_keeper"]:
		var model := VisualFactory.actor(id)
		model.position = Vector3(4 + 2 * [&"cutpurse", &"levy_spearman", &"hollow_keeper"].find(id), 0, -8)
		add_child(model)
	var player: MirePlayer = load("res://scenes/player/player.tscn").instantiate()
	add_child(player)
	player.spawn_at(Vector3.ZERO)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://tests/output/player")
		get_viewport().get_texture().get_image().save_png("res://tests/output/player/movement_arena.png")
		get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().quit()

func box(size: Vector3, at: Vector3, material: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = MireTypes.WORLD
	body.collision_mask = MireTypes.PLAYER | MireTypes.HOSTILE
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	ArtMesh.box(body, "Surface", size, Vector3.ZERO, material)
	add_child(body)
	return body
