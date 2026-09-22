extends RefCounted

var terminal: Dictionary = {}

func run(t: SceneTree) -> void:
	var session: Node = t.root.get_node("GameSession")
	var saves: Node = t.root.get_node("SaveService")
	var original: Dictionary = saves.settings.duplicate(true)
	session.new_game()
	var game: MireGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(game)
	game.router.fade_seconds = 0
	game.router.travel_completed.connect(func(id: StringName, result: MireTypes.ActionResult) -> void: terminal[id] = result)
	t.check(game.modes.mode == &"title" and t.paused and not game.player.input_enabled, "R45 composed runtime begins safely in title mode")
	t.check(game.player.get_parent() == game.game_view and game.interface.get_viewport() == t.root, "R42 native interface is outside the 3D viewport")
	t.check(game.game_view.size.y == 540 and game.view_texture.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "R42 retro image uses 540 pixels and nearest filtering")
	for available: Vector2 in [Vector2(1280, 720), Vector2(1024, 768), Vector2(2100, 900), Vector2(600, 1000), Vector2(4000, 1000)]:
		var fitted: Rect2 = MireGameRoot.fitted_rect(available)
		var aspect: float = fitted.size.x / fitted.size.y
		t.check(aspect >= 4.0 / 3.0 - 0.001 and aspect <= 21.0 / 9.0 + 0.001 and fitted.position.is_equal_approx((available - fitted.size) / 2), "R42 aspect fits centered without stretching " + str(available))
	var window_size: Vector2i = t.root.size
	for pixels: Vector2i in [Vector2i(1024, 768), Vector2i(2100, 900), Vector2i(600, 1000), Vector2i(4000, 1000)]:
		t.root.size = pixels
		await t.process_frame
		await t.process_frame
		var expected_aspect: float = clampf(float(pixels.x) / pixels.y, 4.0 / 3.0, 21.0 / 9.0)
		saves.settings.render_mode = "retro"
		game.apply_settings()
		t.check(game.game_view.size == Vector2i(roundi(540 * expected_aspect), 540), "R42 actual window resize preserves the display aspect in retro " + str(pixels))
		saves.settings.render_mode = "native"
		game.apply_settings()
		var expected_pixels: Vector2i = Vector2i(MireGameRoot.fitted_rect(Vector2(pixels)).size.round())
		t.check(game.game_view.size == expected_pixels, "R42 actual window resize uses native pixels inside letterbox " + str(pixels))
	t.root.size = window_size
	await t.process_frame
	await t.process_frame
	saves.settings.render_mode = "retro"
	game.apply_settings()
	var player_id: int = game.player.get_instance_id()
	await _arrive(t, game, game.router.travel(&"exterior", &"start"))
	t.check(game.modes.mode == &"gameplay" and game.player.input_enabled and not t.paused, "R06 actual root releases gameplay after arrival")
	for frame: int in 5:
		await t.physics_frame
	t.check(game.player.is_on_floor(), "R07 real persistent player collides with the viewport world")
	var view_direction: Vector3 = -game.player.camera.global_basis.z
	var projection: float = game.player.camera.fov
	saves.settings.render_mode = "native"
	game.apply_settings()
	t.check(game.game_view.size == Vector2i(game.display_rect.size * (Vector2(t.root.size) / game.get_viewport_rect().size)), "R42 native view matches displayed pixel extent")
	t.check(game.player.camera.fov == projection and (-game.player.camera.global_basis.z).is_equal_approx(view_direction), "R42 switching resolution preserves camera framing and ray direction")
	saves.settings.render_mode = "retro"
	game.apply_settings()
	await _arrive(t, game, game.router.travel(&"interior_inn", &"entry"))
	t.check(game.player.get_instance_id() == player_id and t.get_nodes_in_group("player").size() == 1, "R06 composed graph preserves one player across actual world replacement")
	game.modes.push_mode(&"inventory")
	var before: Vector3 = game.player.position
	Input.action_press(&"move_forward")
	for frame: int in 4:
		await t.physics_frame
	Input.action_release(&"move_forward")
	t.check(game.player.position == before and t.paused and not game.player.input_enabled, "R45 native modal pauses the 3D player")
	game.free()
	await t.process_frame
	t.check(not t.paused and t.get_nodes_in_group("player").is_empty() and session.recovery.player == null, "R40 root teardown frees player and recovery bindings and releases pause")
	saves.settings = original
	session.new_game()

func _arrive(t: SceneTree, game: MireGameRoot, accepted: MireTypes.ActionResult) -> void:
	t.check(accepted.ok and accepted.payload.get("pending", false), "R06 composed router accepts travel")
	if not accepted.ok:
		return
	var id := StringName(accepted.payload.operation_id)
	for frame: int in 180:
		if terminal.has(id):
			break
		await t.physics_frame
	t.check(terminal.has(id) and terminal[id].ok, "R06 composed world reaches a verified arrival")
