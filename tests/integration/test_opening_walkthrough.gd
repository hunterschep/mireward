extends RefCounted
## Opt-in normal-speed opening traversal. No grants, teleports or domain writes.

const MQ01 := "mq_01_bread_and_iron"
const MQ02 := "mq_02_the_kings_due"
var t: SceneTree
var game: MireGameRoot
var session: Node
var saves: Node
var _held: Dictionary = {}
var _report: Array[Dictionary] = []
var _walked: float = 0.0
var _max_step: float = 0.0
var _look_fallbacks: int = 0
var _mouse_events: int = 0
var _started_ms: int

func run(runner: SceneTree) -> void:
	t = runner
	session = t.root.get_node("GameSession")
	saves = t.root.get_node("SaveService")
	_started_ms = Time.get_ticks_msec()
	var original_size: Vector2i = t.root.size
	t.root.size = Vector2i(1280, 720)
	game = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(game)
	var full: bool = OS.get_environment("MIREWARD_OPENING_WALKTHROUGH") == "1"
	var passed: bool = await _new_game()
	if passed and full:
		passed = await _campaign()
	elif passed:
		var start: Vector3 = game.player.global_position
		passed = await _walk_to(start + Vector3(-8, 0, -6), "default_short_walk", 8)
		t.check(passed and _walked > 8.5 and game.player.is_on_floor(), "R07 default walkthrough smoke moves actual player through bound movement events")
		t.check("movement" in saves.settings.dismissed_hints and Input.is_physical_key_pressed(KEY_W) == false, "R08 default walk crosses real hint persistence and releases its held key normally")
		t.check(session.state.quests[MQ01].state == "AVAILABLE", "R29 short default walkthrough leaves story unaccepted")
	var summary := {"full_walkthrough": full, "passed": passed, "walked_meters": snappedf(_walked, 0.01), "max_physics_step_meters": snappedf(_max_step, 0.0001), "elapsed_seconds": (Time.get_ticks_msec() - _started_ms) / 1000.0, "physics_ticks": Engine.physics_ticks_per_second, "time_scale": Engine.time_scale, "mouse_events": _mouse_events, "apply_look_fallbacks": _look_fallbacks, "native_hardware_input": false, "quests": {MQ01: session.state.quests[MQ01].state, MQ02: session.state.quests[MQ02].state}, "crowns": session.state.player.crowns, "health": session.state.player.health}
	_report.append(summary)
	print("OPENING_WALKTHROUGH_RESULT " + JSON.stringify(summary))
	if full:
		DirAccess.make_dir_recursive_absolute("res://tests/output/opening_walkthrough")
		var file := FileAccess.open("res://tests/output/opening_walkthrough/report.json", FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(_report, "  ") + "\n")
			file.close()
	_release_movement()
	for action: String in _held.keys():
		_set_action(StringName(action), false)
	game.free()
	await t.process_frame
	t.root.size = original_size
	t.check(not t.paused and t.get_nodes_in_group("player").is_empty(), "R40 walkthrough disposes its real player and modes")

func _new_game() -> bool:
	await _frames(2)
	if not await _ui("title/new"):
		return false
	if not await _wait_mode(&"gameplay", 15):
		return false
	var authored: Array = t.root.get_node("ContentDB").map.start
	var start := Vector3(authored[0], authored[1], authored[2])
	t.check(game.player.global_position.distance_to(start) < 0.15 and game.router.loaded_scene_id == &"exterior", "T16 New Game UI arrives at the authored start without fixture placement")
	t.check(Engine.time_scale == 1.0 and Engine.physics_ticks_per_second == 60, "T16 walkthrough uses production time scale and physics rate")
	await _checkpoint("authored_start")
	return game.router.loaded_scene_id == &"exterior"

func _campaign() -> bool:
	if not await _walk_to(Vector3(-110, 0, 160), "southern_road_to_village", 75): return false
	if not await _walk_to(Vector3(-107, 0, 144.7), "village_to_mara", 12): return false
	if not await _interact(&"mara_venn", &"dialogue"): return false
	await _checkpoint("mara_offer")
	if not await _ui("dialogue/accept_mq01"): return false
	t.check(session.state.quests[MQ01].state == "ACTIVE", "R29 real focused Mara dialogue accepts the cart contract")
	if not await _ui("dialogue/@leave"): return false
	if not await _walk_to(Vector3(-20, 0, 116), "village_to_south_cart_path", 45): return false
	if not await _walk_to(Vector3(0, 0, 106.7), "coffer_southern_approach", 14): return false
	await _checkpoint("coffer_approach")
	if not await _interact(&"cart_coffer", &"inventory"): return false
	if not await _ui("take/cart_medicine"): return false
	t.check(int(session.state.key_items.get("cart_medicine", 0)) == 1 and session.state.quests[MQ01].state == "READY", "R25 actual ray-opened coffer and UI pickup make the return ready")
	var defeated: int = 0
	for id: String in ["south_cart_cutpurse_01", "south_cart_cutpurse_02"]:
		defeated += int(session.state.world.get(id, {}).get("defeated", false))
	t.check(defeated == 0 and float(session.state.player.health) == 100.0, "R29 authored southern approach safely bypasses both real north-facing cutpurses")
	_key(KEY_ESCAPE, true)
	await _frames(1)
	_key(KEY_ESCAPE, false)
	await _frames(3)
	if not await _walk_to(Vector3(-20, 0, 116), "coffer_return_path", 14): return false
	if not await _walk_to(Vector3(-107, 0, 144.7), "cart_to_mara", 45): return false
	if not await _interact(&"mara_venn", &"dialogue"): return false
	var crowns: int = int(session.state.player.crowns)
	var bandages: int = _item_count("bandage")
	await _checkpoint("mara_turn_in")
	if not await _ui("dialogue/complete_mq01"): return false
	t.check(session.state.quests[MQ01].state == "COMPLETED" and session.state.quests[MQ02].state == "AVAILABLE", "R29 normally walked opening completes MQ01 and unlocks MQ02")
	t.check(int(session.state.player.crowns) == crowns + 18 and _item_count("bandage") == bandages + 1, "R34 actual UI turn-in grants exactly 18 crowns and one bandage")
	t.check(not session.state.key_items.has("cart_medicine") and session.state.evidence.get("cart_medicine", false), "R33 ordinary hand-in consumes carried medicine and keeps its evidence")
	t.check(_button("dialogue/complete_mq01") == null and session.state.transactions.has("quest/" + MQ01 + "/completion"), "R34 completed turn-in has one stable receipt and no repeat UI action")
	if not await _await_saved(&"autosave", 4): return false
	if not await _ui("dialogue/@leave"): return false
	if not await _walk_to(Vector3(-119, 0, 134.7), "mara_to_inn_door", 12): return false
	if not await _interact(&"inn_door", &"gameplay", true): return false
	t.check(game.router.loaded_scene_id == &"interior_inn", "R06 ordinary doorway input enters the real inn")
	if not await _walk_to(Vector3(-1.4, 0, -2), "inn_to_tamsin", 8): return false
	if not await _interact(&"tamsin_reed", &"dialogue"): return false
	if not await _ui("dialogue/open_shop"): return false
	var bread: int = _item_count("bread")
	crowns = int(session.state.player.crowns)
	if not await _ui("buy/bread"): return false
	t.check(_item_count("bread") == bread + 1 and int(session.state.player.crowns) == crowns - 5, "R26 physically visited Tamsin sells real bread at its displayed price")
	_key(KEY_ESCAPE, true)
	await _frames(1)
	_key(KEY_ESCAPE, false)
	await _frames(3)
	if not await _interact(&"tamsin_reed", &"dialogue"): return false
	if not await _ui("dialogue/ask_rest_paid"): return false
	crowns = int(session.state.player.crowns)
	if not await _ui("dialogue/request_rest_paid"): return false
	if not await _wait_mode(&"gameplay", 15): return false
	t.check(session.state.player.rest_anchor == "inn_bed" and int(session.state.player.crowns) == crowns - 4 and not session.recovery.has_pending_recovery(), "R22 physically visited inn rest completes real arrival and charges four once")
	_key(KEY_ESCAPE, true)
	await _frames(1)
	_key(KEY_ESCAPE, false)
	await _frames(2)
	if not await _ui("pause/save"): return false
	if not await _ui("save/manual_1"): return false
	if not await _await_saved(&"manual_1", 2): return false
	_key(KEY_ESCAPE, true)
	await _frames(1)
	_key(KEY_ESCAPE, false)
	await _frames(2)
	if not await _ui("pause/load"): return false
	if not await _ui("load/manual_1"): return false
	if not await _wait_mode(&"gameplay", 15): return false
	t.check(session.state.quests[MQ01].state == "COMPLETED" and session.state.quests[MQ02].state == "AVAILABLE" and int(session.state.player.crowns) == crowns - 4, "R38 UI load preserves normally earned progress and cannot repeat turn-in rewards")
	t.check(game.router.loaded_scene_id == &"interior_inn" and game.router.current_world.entities.has(&"tamsin_reed"), "R38 actual slot reload reconstructs the occupied inn")
	await _checkpoint("loaded_inn")
	return true

func _walk_to(goal: Vector3, label: String, limit_seconds: float) -> bool:
	if game.modes.mode != &"gameplay":
		t.check(false, "R07 walking requires ordinary gameplay: " + label)
		return false
	_release_movement()
	var start: Vector3 = game.player.global_position
	var started: int = Time.get_ticks_msec()
	var nav: RID = game.router.current_world.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(nav, start, goal, true)
	if path.size() < 2 or Vector2(path[-1].x - goal.x, path[-1].z - goal.z).length() > 0.5:
		t.check(false, "R07 normal traversal needs a complete navigation route: " + label)
		return false
	var progress_at: Vector3 = start
	var progress_time: int = started
	var distance: float = 0.0
	var reached: bool = true
	for index: int in range(1, path.size()):
		var waypoint: Vector3 = path[index]
		var tolerance: float = 0.14 if index == path.size() - 1 else 0.5
		while Vector2(game.player.global_position.x - waypoint.x, game.player.global_position.z - waypoint.z).length() > tolerance:
			if game.modes.mode != &"gameplay" or float(session.state.player.health) <= 0 or Time.get_ticks_msec() - started > limit_seconds * 1000:
				reached = false
				break
			var before: Vector3 = game.player.global_position
			_aim(before + Vector3(waypoint.x - before.x, 0, waypoint.z - before.z) + Vector3.UP * 1.65)
			_set_action(&"move_forward", true)
			await t.physics_frame
			var step: float = before.distance_to(game.player.global_position)
			distance += step
			_max_step = maxf(_max_step, step)
			if game.player.global_position.distance_to(progress_at) > 0.5:
				progress_at = game.player.global_position
				progress_time = Time.get_ticks_msec()
			elif Time.get_ticks_msec() - progress_time > 4500:
				var collisions: Array[Dictionary] = []
				for contact: int in game.player.get_slide_collision_count():
					var collision := game.player.get_slide_collision(contact)
					var collider: Object = collision.get_collider()
					collisions.append({"path": str(collider.get_path()) if collider is Node else str(collider), "position": collision.get_position(), "normal": collision.get_normal()})
				print("OPENING_WALK_STALLED " + JSON.stringify({"waypoint": waypoint, "player": game.player.global_position, "velocity": game.player.velocity, "yaw": game.player.rotation.y, "collisions": collisions, "held_actions": _held.duplicate(), "forward_pressed": Input.is_action_pressed(&"move_forward"), "physical_w": Input.is_physical_key_pressed(KEY_W), "player_enabled": game.player.input_enabled, "paused": t.paused, "dismissed_hints": saves.settings.dismissed_hints}))
				reached = false
				break
		_release_movement()
		if not reached: break
	await _frames(3)
	_walked += distance
	var result := {"leg": label, "passed": reached, "meters": snappedf(distance, 0.01), "seconds": (Time.get_ticks_msec() - started) / 1000.0, "position": game.player.global_position, "health": session.state.player.health, "mode": String(game.modes.mode)}
	_report.append(result)
	print("OPENING_WALK_LEG " + JSON.stringify(result))
	t.check(reached and _max_step < 0.11, "R07 continuous normal-speed input reaches " + label + " without a position jump")
	return reached

func _aim(point: Vector3) -> void:
	var offset: Vector3 = point - game.player.camera.global_position
	var horizontal := Vector2(offset.x, offset.z)
	if horizontal.length() < 0.001: return
	var yaw: float = atan2(-offset.x, -offset.z)
	var pitch: float = atan2(offset.y, horizontal.length())
	var sensitivity: float = float(saves.settings.mouse_sensitivity)
	var sign_y: float = -1 if saves.settings.invert_y else 1
	var motion := Vector2(-wrapf(yaw - game.player.rotation.y, -PI, PI) / sensitivity, (game.player.head.rotation.x - pitch) / (sensitivity * sign_y))
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var event := InputEventMouseMotion.new()
		event.position = game.get_viewport_rect().get_center()
		event.relative = motion
		event.screen_relative = motion
		t.root.push_input(event)
		_mouse_events += 1
	else:
		# Headless DisplayServer cannot capture a cursor; use the same look method.
		game.player.apply_look(motion)
		_look_fallbacks += 1

func _interact(id: StringName, expected_mode: StringName, doorway: bool = false) -> bool:
	_release_movement()
	var node: Node = game.router.current_world.entities.get(id)
	var component: InteractionComponent = node if node is InteractionComponent else node.get("interaction") if node != null else null
	if component == null:
		t.check(false, "R09 authored target exists: " + String(id))
		return false
	_aim(component.focus_position())
	await _frames(4)
	var offer: MireTypes.InteractionOffer = game.interaction.offer
	if offer == null or offer.entity_id != id or not offer.allowed:
		t.check(false, "R09 real focused offer permits " + String(id) + ": " + (String(offer.reason_key) if offer != null else "no offer"))
		return false
	t.check(true, "R09 actual eye ray focuses " + String(id) + " within ordinary reach")
	_set_action(&"interact", true)
	await _frames(1)
	_set_action(&"interact", false)
	await _frames(3)
	if doorway:
		return await _wait_mode(expected_mode, 15)
	var reached: bool = game.modes.mode == expected_mode
	t.check(reached, "R09 bound interact key opens " + String(id) + " through the production handler")
	return reached

func _ui(id: String) -> bool:
	_release_movement()
	var button := _button(id)
	if button == null or button.disabled:
		t.check(false, "R45 ordinary UI action available: " + id)
		return false
	button.grab_focus()
	await _frames(2)
	_key(KEY_ENTER, true)
	await _frames(1)
	_key(KEY_ENTER, false)
	await _frames(3)
	t.check(true, "R45 focused UI button activated through Enter: " + id)
	return true

func _button(id: String) -> Button:
	for node: Node in game.modal_host.find_children("*", "Button", true, false):
		if node is Button and node.get_meta("ui_id", "") == id and node.is_visible_in_tree():
			return node
	return null

func _wait_mode(mode: StringName, seconds: float) -> bool:
	for frame: int in ceili(seconds * 60):
		if game.modes.mode == mode and not session.travelling and not saves.is_loading() and not game.ui._busy:
			await _frames(2)
			return true
		await t.physics_frame
	t.check(false, "R06 real transition reaches " + String(mode))
	return false

func _await_saved(slot: StringName, seconds: float) -> bool:
	for frame: int in ceili(seconds * 15):
		var saved: MireTypes.ActionResult = saves.inspect_slot(slot)
		if saved.ok and saved.payload.snapshot.quests[MQ01].state == "COMPLETED":
			t.check(true, "R37 actual validated " + String(slot) + " retains completed opening")
			return true
		await _frames(4)
	t.check(false, "R37 actual save completes after ordinary UI progression: " + String(slot))
	return false

func _item_count(id: String) -> int:
	var count: int = 0
	for stack: Dictionary in session.state.inventory:
		if stack.item_id == id: count += int(stack.quantity)
	return count

func _set_action(action: StringName, pressed: bool) -> void:
	if bool(_held.get(String(action), false)) == pressed: return
	_held[String(action)] = pressed
	var event: InputEvent = InputMap.action_get_events(action)[0].duplicate()
	if event is InputEventKey:
		event.pressed = pressed
		event.keycode = event.physical_keycode
	elif event is InputEventMouseButton:
		event.pressed = pressed
	Input.parse_input_event(event)

func _release_movement() -> void:
	for action: StringName in [&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint"]:
		_set_action(action, false)

func _key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)

func _frames(count: int) -> void:
	for frame: int in count:
		await t.physics_frame
	await t.process_frame

func _checkpoint(label: String) -> void:
	if OS.get_environment("MIREWARD_OPENING_CAPTURE") != "1" or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute("res://tests/output/opening_walkthrough")
	RenderingServer.viewport_set_update_mode(t.root.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	await t.process_frame
	await RenderingServer.frame_post_draw
	var image: Image = t.root.get_texture().get_image()
	var path: String = "res://tests/output/opening_walkthrough/" + label + ".png"
	t.check(image != null and not image.is_empty() and image.save_png(path) == OK, "R42 graphical checkpoint captures the same ordinary-input run: " + label)
