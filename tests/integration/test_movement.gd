extends RefCounted

func frames(t: SceneTree, count: int) -> void:
	for index: int in count:
		await t.physics_frame
	await t.process_frame

func run(t: SceneTree) -> void:
	var session: Node = t.root.get_node("GameSession")
	session.new_game()
	var arena := Node3D.new()
	t.root.add_child(arena)
	var floor_body := StaticBody3D.new()
	floor_body.position.y = -0.5
	var floor_shape := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	floor_shape.shape = shape
	floor_body.add_child(floor_shape)
	arena.add_child(floor_body)
	var player: MirePlayer = load("res://scenes/player/player.tscn").instantiate()
	arena.add_child(player)
	await frames(t, 10)
	t.check(player.is_on_floor(), "R07 player capsule grounds on world collision")
	var previous_fps: int = Engine.max_fps
	for fps: int in [30, 60, 120]:
		Engine.max_fps = fps
		player.spawn_at(Vector3.ZERO)
		await frames(t, 15)
		Input.action_press(&"move_forward")
		await frames(t, 30)
		var start: Vector3 = player.global_position
		await frames(t, 60)
		var distance: float = start.distance_to(player.global_position)
		t.check(absf(distance - 4.0) <= 0.2, "R07 fixed-physics walking speed at %d render FPS: %.3f m" % [fps, distance])
		Input.action_release(&"move_forward")
		await frames(t, 20)
	Engine.max_fps = previous_fps
	player.spawn_at(Vector3.ZERO)
	await frames(t, 15)
	Input.action_press(&"move_forward")
	Input.action_press(&"move_right")
	await frames(t, 30)
	var diagonal_start: Vector3 = player.global_position
	await frames(t, 60)
	t.check(absf(diagonal_start.distance_to(player.global_position) - 4.0) <= 0.2, "R07 diagonal movement is normalized")
	Input.action_release(&"move_forward")
	Input.action_release(&"move_right")
	await frames(t, 20)
	session.state.player.stamina = 100.0
	Input.action_press(&"sprint")
	await frames(t, 60)
	t.check(session.state.player.stamina == 100.0, "R07 stationary sprint spends no stamina")
	Input.action_press(&"move_forward")
	await frames(t, 60)
	t.check(absf(float(session.state.player.stamina) - 88.0) < 0.5, "R07 moving sprint costs twelve stamina per second")
	t.check(absf(Vector2(player.velocity.x, player.velocity.z).length() - 6.0) < 0.05, "R07 moving sprint reaches six meters per second")
	session.state.player.stamina = 0.0
	await frames(t, 12)
	t.check(not player.sprinting and Vector2(player.velocity.x, player.velocity.z).length() <= 4.01, "R07 exhausted sprint falls back to walking")
	Input.action_release(&"sprint")
	Input.action_release(&"move_forward")
	await frames(t, 20)
	player.spawn_at(Vector3.ZERO)
	await frames(t, 15)
	session.state.player.stamina = 100.0
	Input.action_press(&"jump")
	await frames(t, 3)
	Input.action_release(&"jump")
	var charged: float = session.state.player.stamina
	await frames(t, 2)
	Input.action_press(&"jump")
	await frames(t, 3)
	Input.action_release(&"jump")
	t.check(charged == 90.0 and session.state.player.stamina == 90.0 and not player.is_on_floor(), "R07 jump pays once and cannot repeat in air")
	await frames(t, 90)
	var wall := StaticBody3D.new()
	wall.position = Vector3(0, 1.5, -4)
	var wall_collision := CollisionShape3D.new()
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(10, 3, 0.5)
	wall_collision.shape = wall_shape
	wall.add_child(wall_collision)
	arena.add_child(wall)
	player.spawn_at(Vector3.ZERO)
	await frames(t, 15)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await frames(t, 120)
	t.check(player.global_position.z > -3.6, "R07 capsule cannot sprint through a wall")
	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")
	player.apply_look(Vector2(0, 100000))
	t.check(is_equal_approx(player.head.rotation.x, deg_to_rad(-85)), "R07 mouse pitch clamps to minus 85 degrees")
	var settings: Node = t.root.get_node("SaveService")
	settings.settings.invert_y = true
	player.apply_look(Vector2(0, 100000))
	t.check(is_equal_approx(player.head.rotation.x, deg_to_rad(85)), "R08 inverted look clamps to plus 85 degrees")
	settings.settings.invert_y = false
	arena.queue_free()
	await t.process_frame
