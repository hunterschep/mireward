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
	await _session_cycles(t, game, session, saves, player_id)
	await t.process_frame
	game.free()
	await t.process_frame
	t.check(not t.paused and t.get_nodes_in_group("player").is_empty() and session.recovery.player == null, "R40 root teardown frees player and recovery bindings and releases pause")
	saves.settings = original
	session.new_game()

func _session_cycles(t: SceneTree, game: MireGameRoot, session: Node, saves: Node, player_id: int) -> void:
	t.check(saves.save_slot(&"manual_1").ok, "R37 the actual composed runtime writes a manual save")
	var manual_path: String = saves.slot_path(&"manual_1")
	var manual_hash := FileAccess.get_sha256(manual_path)
	var recorded: Dictionary = saves.inspect_slot(&"manual_1").payload.snapshot
	for cycle: int in 3:
		t.check(game.leave_to_title().ok and not session.active and game.modes.mode == &"title" and game.world_container.get_child_count() == 0, "R40 title teardown clears the real world in cycle " + str(cycle))
		t.check(session.quests.autosave_requested.get_connections().is_empty() and session.recovery.player == null, "R40 title removes live recovery and autosave listeners")
		var loaded: MireTypes.ActionResult = await game.load_slot(&"manual_1")
		t.check(loaded.ok and session.active and game.router.loaded_scene_id == &"interior_inn" and session.state.inventory == recorded.inventory, "R39 title load reconstructs the recorded world and inventory")
		t.check(game.player.get_instance_id() == player_id and t.get_nodes_in_group("player").size() == 1 and session.quests.autosave_requested.get_connections().size() == 1, "R40 repeated title/load has one player and one autosave subscription")
	var unchanged: Dictionary = session.snapshot()
	var absent: MireTypes.ActionResult = await game.load_slot(&"manual_3")
	t.check(not absent.ok and session.snapshot() == unchanged and game.modes.mode == &"gameplay", "R39 an empty load leaves current gameplay intact")
	t.check(saves.save_slot(&"autosave").ok, "R40 create the actual autosave before New Game confirmation")
	var denied: MireTypes.ActionResult = await game.start_new_game(false)
	t.check(not denied.ok and denied.code == &"confirmation_required" and session.state.inventory == recorded.inventory, "R40 New Game refuses unconfirmed autosave replacement")
	var selected: Dictionary = saves.settings.duplicate(true)
	selected.fov = 85.0
	var settings_result: MireTypes.ActionResult = saves.save_settings(selected)
	t.check(settings_result.ok and is_equal_approx(game.player.camera.fov, 85.0), "R42 persisted settings update the active camera: " + String(settings_result.message_key))
	var started: MireTypes.ActionResult = await game.start_new_game(true)
	t.check(started.ok and game.router.loaded_scene_id == &"exterior" and session.state.player.crowns == 12 and session.state.choices.ending == "none" and saves.settings.fov == 85.0, "R40 confirmed New Game resets progress and retains settings")
	t.check(FileAccess.get_sha256(manual_path) == manual_hash, "R40 loading and New Game never alter the manual slot")

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
