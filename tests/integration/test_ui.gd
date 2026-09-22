extends RefCounted

var game: MireGameRoot
var ui: GameUI
var t: SceneTree
var session: Node
var saves: Node

func run(runner: SceneTree) -> void:
	t = runner
	session = t.root.get_node("GameSession")
	saves = t.root.get_node("SaveService")
	var original: Dictionary = saves.settings.duplicate(true)
	var original_size: Vector2i = t.root.size
	t.root.size = Vector2i(1280, 720)
	session.new_game()
	game = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(game)
	game.router.fade_seconds = 0
	ui = game.ui
	await _frames()
	t.check(game.modes.mode == &"title" and _button("title/new") != null and _button("title/continue").disabled, "R45 title has actual controls and honest empty Continue")
	t.check(ui.panels.size() == 15 and ui.inventory.content != null, "R44 all menu panels are registered")
	_press("title/settings")
	await _frames()
	t.check(game.modes.mode == &"settings" and ui.settings.controls.size() == 15, "R46 settings opens actual controls")
	ui.settings.controls.fov.value = 90
	ui.settings.controls.text_scale.select(2)
	ui.settings.controls.text_scale.item_selected.emit(2)
	ui.settings.controls.view_bob.value = 0
	ui.settings.controls.camera_shake.button_pressed = false
	_press("settings/apply")
	await _frames()
	t.check(saves.settings.fov == 90 and saves.settings.text_scale == 1.5 and game.player.camera.fov == 90 and saves.settings.view_bob == 0 and not saves.settings.camera_shake, "R46 actual settings controls persist and update root camera")
	game.modes.pop_mode()
	await _frames()
	_press("title/new")
	await _arrival()
	t.check(game.router.loaded_scene_id == &"exterior" and game.modes.mode == &"gameplay" and session.active, "R45 New Game button reaches real playable world")
	await _frames(8)
	t.check(ui.hud.weapon.texture != null and ui.hud.resources.text.contains("12 crowns"), "R44 HUD reads actual equipment and resources")
	await _target_bar()
	await _inventory_and_shop()
	await _dialogue_and_loot()
	await _pending_rewards_and_death()
	await _journal_map()
	await _save_load()
	await _backup_and_continue()
	await _binding_and_layout()
	await _ending_failure()
	game.free()
	await _frames()
	t.check(not t.paused and session.recovery.player == null, "R40 UI graph disposes with real session bindings")
	saves.save_settings(original)
	t.root.size = original_size
	session.new_game()

func _inventory_and_shop() -> void:
	session.inventory.try_add(&"arming_sword", 1, &"ui_fixture_sword")
	game.modes.push_mode(&"inventory")
	await _frames()
	var sword: String = ""
	for stack: Dictionary in session.state.inventory:
		if stack.item_id == "arming_sword": sword = stack.stack_id
	_press("equip/" + sword)
	await _frames()
	t.check(session.state.equipment.weapon == sword, "R44 equipment button calls actual inventory transaction")
	_press("unequip/shield")
	await _frames()
	t.check(session.state.equipment.shield == "", "R44 shield unequip is reflected in saved ownership")
	session.state.player.health = 45.0
	_press("use/stack_4")
	await _frames(65)
	t.check(session.state.player.health == 80 and session.state.inventory[3].quantity == 1 and game.modes.mode == &"gameplay", "R17 R44 Use button closes modal and completes real timed healing once")
	ui.handle_action(MireTypes.success({"ui_action": "shop", "shop_id": "tamsin_reed"}))
	await _frames()
	var before: int = session.state.player.crowns
	_press("buy/bread")
	await _frames()
	t.check(session.state.player.crowns == before - 5 and session.state.inventory[4].quantity == 2, "R26 shop buy button uses real stock price and ownership")
	_press("sell/stack_5")
	await _frames()
	t.check(session.state.player.crowns == before - 4 and session.state.inventory[4].quantity == 1, "R26 shop sell button uses exact resale price")
	ui.handle_action(MireTypes.success({"ui_action": "shop", "shop_id": "oswin_pike"}))
	await _frames()
	var snapshot: Dictionary = session.snapshot()
	_press("buy/mail_coat")
	await _frames()
	t.check(session.snapshot() == snapshot and ui.feedback.text.contains("crowns"), "R26 failed expensive purchase reports actual refusal without mutation")
	game.modes.push_mode(&"gameplay")

func _dialogue_and_loot() -> void:
	ui.handle_action(session.dialogue.start(&"mara_venn"))
	await _frames()
	t.check(game.modes.mode == &"dialogue" and _button("dialogue/accept_mq01") != null, "R32 actual dialogue view exposes current available quest")
	var choices_scroll: ScrollContainer = ui.panels[&"dialogue"].get_child(1)
	var visible_choices: int = 0
	for child: Control in choices_scroll.get_child(0).get_children():
		if child.get_global_rect().intersection(choices_scroll.get_global_rect()).size.y > 1:
			visible_choices += 1
	t.check(visible_choices <= 3, "R32 dialogue viewport shows at most three choices including partial rows")
	var first := _button("dialogue/accept_mq01")
	first.grab_focus()
	for step: int in 5:
		_key(KEY_DOWN, true)
		_key(KEY_DOWN, false)
		await _frames()
	t.check(choices_scroll.scroll_vertical > 0 and choices_scroll.is_ancestor_of(t.root.gui_get_focus_owner()), "R45 real keyboard navigation scrolls to later dialogue choices")
	first.grab_focus()
	_key(KEY_ENTER, true)
	_key(KEY_ENTER, false)
	await _frames()
	t.check(session.state.quests.mq_01_bread_and_iron.state == "ACTIVE", "R29 dialogue acceptance uses actual quest API")
	_press("dialogue/@leave")
	await _frames()
	var world: Node3D = game.router.current_world
	var source := Node3D.new()
	world.add_child(source)
	world.entities[&"cart_coffer"] = source
	ui.handle_action(MireTypes.success({"ui_action": "loot", "entity_id": "cart_coffer"}))
	await _frames()
	_press("take/cart_medicine")
	await _frames()
	t.check(session.state.key_items.cart_medicine == 1 and session.state.quests.mq_01_bread_and_iron.state == "READY", "R25 loot button collects fixed medicine and reconciles quest")
	game.modes.push_mode(&"journal")
	await _frames()
	game.modes.push_mode(&"inventory")
	await _frames()
	t.check(ui.inventory.loot_id.is_empty() and _button("take/cart_medicine") == null, "R25 reopening inventory does not retain a remote loot source")
	game.modes.push_mode(&"gameplay")
	ui.handle_action(session.dialogue.start(&"mara_venn"))
	await _frames()
	var turn_in: Button
	for button: Node in ui.panels[&"dialogue"].find_children("*", "Button", true, false):
		if String(button.get_meta("ui_id", "")).contains("turn"):
			turn_in = button
	# Find the authored completion effect rather than rely on visible wording.
	var view: Dictionary = session.dialogue.view()
	for choice: Dictionary in view.choices:
		if choice.id != "@leave" and String(choice.id).contains("complete"):
			turn_in = _button("dialogue/" + choice.id)
	t.check(turn_in != null, "R29 ready dialogue supplies a turn-in control")
	if turn_in != null:
		turn_in.pressed.emit()
		await _frames()
	t.check(session.state.quests.mq_01_bread_and_iron.state == "COMPLETED" and not session.state.key_items.has("cart_medicine"), "R29 turn-in control completes atomically")
	game.modes.push_mode(&"gameplay")

func _journal_map() -> void:
	game.modes.push_mode(&"journal")
	await _frames()
	t.check(_labels(ui.journal).contains("Bread and Iron"), "R44 completed quest is readable in journal")
	session.quests.read_document(&"toll_notice")
	ui.refresh()
	await _frames()
	_press("document/toll_notice")
	await _frames()
	t.check(game.modes.mode == &"readable" and _labels(ui.panels[&"readable"]).contains("grain levy doubled"), "R33 journal document opens retained canonical text")
	game.modes.pop_mode()
	game.modes.push_mode(&"map")
	await _frames()
	t.check(ui.map_panel.map_view.game == game and ui.map_panel.map_caption.text.contains("Mara"), "R10 map carries a current actionable main giver hint")
	game.modes.push_mode(&"gameplay")

func _save_load() -> void:
	game.modes.push_mode(&"pause")
	_press("pause/save")
	await _frames()
	_press("save/manual_1")
	await _frames()
	t.check(saves.inspect_slot(&"manual_1").ok, "R37 manual save button writes validated actual slot")
	var saved_crowns: int = session.state.player.crowns
	session.inventory.try_add(&"bread", 1, &"ui_after_save")
	game.modes.push_mode(&"load")
	await _frames()
	_press("load/manual_1")
	await _arrival()
	t.check(session.state.player.crowns == saved_crowns and not session.state.transactions.has("inventory/add/ui_after_save"), "R38 load button restores actual saved world/state")
	game.modes.push_mode(&"pause")
	_press("pause/title")
	await _frames()
	_press("confirmation/cancel")
	await _frames()
	t.check(game.modes.mode == &"pause" and session.active, "R45 cancelling title confirmation preserves running session")
	game.modes.push_mode(&"gameplay")

func _binding_and_layout() -> void:
	game.modes.push_mode(&"settings")
	await _frames()
	_press("binding/interact")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_J
	event.pressed = true
	Input.parse_input_event(event)
	await _frames()
	t.check(game.modes.mode == &"confirmation" and _labels(ui.panels[&"confirmation"]).contains("Swap"), "R46 binding conflict shows a material swap confirmation")
	_press("confirmation/cancel")
	await _frames()
	t.check(InputBindings.label(&"interact").contains("E"), "R46 cancelling conflict keeps the old binding")
	_press("binding/interact")
	Input.parse_input_event(event)
	await _frames()
	_press("confirmation/confirm")
	await _frames()
	t.check(saves.settings.bindings.interact.code == KEY_J and saves.settings.bindings.journal.code == KEY_E, "R46 confirmed swap persists both bindings")
	for mode: StringName in [&"inventory", &"journal", &"map", &"settings", &"pause", &"save", &"load"]:
		game.modes.push_mode(mode)
		await _frames()
		if mode == &"map":
			ui.map_panel.map_caption.text = "A Bell Without a Rope: Show the recovered charter to Sister Elian for attestation at the Saint Orra monastery shelter. Read the journal for the complete clue and objective count."
			await _frames()
		var panel: Control = ui.panels[mode]
		t.check(panel.get_global_rect().end.y <= 720 and panel.get_global_rect().position.y >= 0 and panel.size.x <= 1280, "R46 essential modal viewport fits 720p at150%: " + String(mode))
		t.check(game.modal_host._back.get_global_rect().end.y <= 720 and game.modal_host._back.get_global_rect().end.x <= 1280, "R46 Back stays accessible at150%: " + String(mode))
	game.modes.push_mode(&"gameplay")

func _ending_failure() -> void:
	var fixture: Script = load("res://tests/unit/test_quests.gd")
	t.check(fixture.ending_checkpoint(session, &"none").ok, "R35 UI ending fixture uses genuine campaign APIs")
	# The runtime remains the exterior; the fixture only changes domain progress.
	saves.write_fault = func(stage: String) -> bool: return stage == "temporary_open"
	ui.handle_action(MireTypes.success({"ui_action": "writ"}))
	await _frames()
	_press("ending/charter")
	await _frames()
	t.check(_labels(ui.panels[&"confirmation"]).contains("15% less"), "R35 ending confirmation states selected systemic consequences")
	_press("confirmation/confirm")
	await _frames(10)
	t.check(session.state.choices.ending == "charter" and game.modes.mode == &"confirmation" and _button("ending/continue_unsaved") != null, "R35 failed actual ending save retains committed choice and offers explicit continuation")
	game.modes.pop_mode()
	t.check(game.modes.mode == &"confirmation", "R35 Escape cannot bypass failed ending save decision")
	_press("ending/continue_unsaved")
	await _frames()
	t.check(game.modes.mode == &"epilogue" and _labels(ui.panels[&"epilogue"]).contains("no single hand"), "R36 explicit continue-unsaved unlocks actual epilogue")
	_press("epilogue/next")
	await _frames()
	_press("epilogue/next")
	await _frames()
	_press("epilogue/valley")
	await _frames()
	t.check(game.modes.mode == &"gameplay" and session.active, "R36 epilogue returns to functional valley")
	saves.write_fault = Callable()
	var completed: Dictionary = session.snapshot()
	ui.handle_action(MireTypes.success({"ui_action": "writ"}))
	await _frames()
	t.check(_button("ending/charter") == null and _button("writ/replay") != null and _labels(ui.panels[&"readable"]).contains("resolution is settled"), "R35 completed writ shows locked choice and only a replay action")
	t.check(session.snapshot() == completed and not ui._awaiting_ending, "R35 reopening the settled writ neither mutates progress nor waits for another autosave")
	_press("writ/replay")
	await _frames()
	t.check(game.modes.mode == &"epilogue" and session.snapshot() == completed, "R36 settled writ epilogue replay is read-only")
	game.modes.push_mode(&"pause")
	t.check(saves.save_slot(&"manual_3").ok, "R37 completed ending checkpoint saved through real persistence")
	await game.load_slot(&"manual_3")
	await _frames()
	ui.handle_action(MireTypes.success({"ui_action": "writ"}))
	await _frames()
	t.check(not saves.pending_autosave().ending_ready and _button("writ/replay") != null and _button("ending/charter") == null, "R36 loaded ending exposes pure replay without reopening its save-before-epilogue gate")
	_press("writ/replay")
	await _frames()
	t.check(game.modes.mode == &"epilogue", "R36 loaded completed writ can replay epilogue without a new ending event")

func _press(id: String) -> void:
	var button := _button(id)
	t.check(button != null and not button.disabled, "UI action available: " + id)
	if button != null and not button.disabled:
		button.pressed.emit()

func _button(id: String) -> Button:
	for node: Node in game.modal_host.find_children("*", "Button", true, false):
		if node.get_meta("ui_id", "") == id:
			return node
	return null

func _labels(parent: Node) -> String:
	var text: String = ""
	for node: Node in parent.find_children("*", "Label", true, false):
		text += node.text + "\n"
	return text

func _frames(count: int = 2) -> void:
	for frame: int in count:
		await t.process_frame
		await t.physics_frame

func _arrival() -> void:
	for frame: int in 240:
		await t.physics_frame
		if not ui._busy and not session.travelling and game.router.current_world != null:
			break
	await _frames()

func _pending_rewards_and_death() -> void:
	session.inventory.try_add(&"arming_sword", 16 - session.state.inventory.size(), &"ui_fill_pack")
	session.quests.activate(&"sq_01_a_smiths_hand")
	session.world_state.take_loot(&"kiln_hammer_crate", &"smith_hammer", 1, &"ui_hammer")
	session.quests.complete(&"sq_01_a_smiths_hand", &"ui_hammer_return")
	var delivery := "sq_01_a_smiths_hand/arming_sword"
	game.modes.push_mode(&"inventory")
	await _frames()
	_press("claim/" + delivery)
	await _frames()
	t.check(session.state.pending_delivery.has(delivery) and ui.feedback.text.contains("room"), "R25 full-pack pending reward claim reports actual capacity refusal")
	ui.handle_action(MireTypes.success({"ui_action": "shop", "shop_id": "tamsin_reed"}))
	await _frames()
	_press("sell/stack_5")
	await _frames()
	game.modes.push_mode(&"inventory")
	await _frames()
	_press("claim/" + delivery)
	await _frames()
	t.check(not session.state.pending_delivery.has(delivery) and session.state.transactions.has("inventory/claim/" + delivery), "R25 pending reward button claims exactly once after an actual sale frees space")
	game.modes.push_mode(&"gameplay")
	var before: int = session.state.player.crowns
	game.player.combat.receive_hit(MireTypes.DamageRequest.new(&"ui_fixture", 1, &"player", 500, &"light", game.player.global_position + Vector3.FORWARD, &"hostile"))
	await _frames()
	t.check(game.modes.mode == &"death" and _button("death/recover") != null, "R22 actual combat death opens the recovery control")
	_press("death/recover")
	await _arrival()
	t.check(session.state.player.health == 100 and session.state.player.crowns == before - mini(12, floori(before * 0.1)) and not session.recovery.has_pending_recovery(), "R22 recovery button waits for real world arrival and pays one exact fee")

func _backup_and_continue() -> void:
	await _frames(5)
	t.check(saves.save_slot(&"manual_1").ok, "R38 UI backup fixture rotates a genuine valid manual slot")
	var corrupt := FileAccess.open(saves.slot_path(&"manual_1"), FileAccess.WRITE)
	corrupt.store_string("{damaged")
	corrupt.close()
	game.modes.push_mode(&"load")
	await _frames()
	_press("backup/manual_1")
	await _frames()
	t.check(_labels(ui.panels[&"confirmation"]).contains("damaged file is preserved"), "R38 UI explicitly offers valid backup recovery")
	_press("confirmation/confirm")
	await _arrival()
	t.check(FileAccess.get_file_as_string(saves.slot_path(&"manual_1")) == "{damaged", "R38 UI backup load preserves damaged primary evidence")
	t.check(saves.save_slot(&"manual_2").ok, "R37 Continue fixture writes second slot")
	corrupt = FileAccess.open(saves.slot_path(&"manual_2"), FileAccess.WRITE)
	corrupt.store_string("{damaged")
	corrupt.close()
	t.check(saves.save_slot(&"manual_3").ok, "R37 Continue fixture writes newest valid third slot")
	ui.report(game.leave_to_title())
	await _frames()
	t.check(not _button("title/continue").disabled, "R45 Continue enables when an actual valid save exists")
	_press("title/continue")
	await _arrival()
	t.check(session.active and ui.feedback.text.contains("Unavailable saves were skipped"), "R39 Continue loads newest valid save and explains skipped damage")

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _target_bar() -> void:
	var world: Node3D = game.router.current_world
	var original_position: Vector3 = game.player.global_position
	var original_yaw: float = game.player.rotation.y
	var actor: EnemyActor = world.entities[&"south_cart_cutpurse_01"]
	var coordinator: EncounterCoordinator = actor.coordinator
	coordinator.set_physics_process(false)
	for other: EnemyActor in coordinator.actors():
		other.set_thinking(false)
	t.check(actor.player == game.player and not actor.combat.dead, "R44 target-bar test uses the actual registered opening cutpurse")
	game.player.spawn_at(actor.spawn_position + Vector3(0, 0, 1.7), 0)
	await _frames(8)
	t.check(ui.hud.target.visible and ui.hud.target.text == "Cutpurse" and ui.hud.target_health.value == actor.combat.get_health(), "R44 target bar names actual enemy definition and shows real health")
	t.check(game.player.combat.request_attack(&"light").ok, "R44 recent-hit target fixture starts actual player swing")
	await _frames(45)
	game.player.rotation.y = PI
	await _frames(8)
	t.check(actor.combat.get_health() < actor.combat.max_health and ui.hud.target.visible and ui.hud.target.text == "Cutpurse", "R44 actual recent hit keeps hostile health visible briefly after looking away")
	actor.combat.receive_hit(MireTypes.DamageRequest.new(&"player", 100, actor.entity_id, 500, &"light", game.player.global_position, &"player"))
	await _frames(8)
	t.check(not ui.hud.target.visible and world.entities[actor.entity_id] == actor and session.state.world[String(actor.entity_id)].defeated, "R44 defeated hostile stays registered and persistent but has no health bar")
	var dummy: TrainingDummy = world.entities[TrainingDummy.ENTITY_ID]
	game.player.spawn_at(dummy.global_position + Vector3(0, 0, 1.7), 0)
	await _frames(8)
	t.check(not ui.hud.target.visible and not ui.hud.target_health.visible, "R44 aiming at the nonattacking training dummy shows no hostile health bar")
	var hits: Array[int] = []
	var received := func(_request: MireTypes.DamageRequest, result: MireTypes.DamageResult) -> void: hits.append(result.health_damage)
	dummy.combat.hit_received.connect(received)
	var crowns: int = session.state.player.crowns
	t.check(game.player.combat.request_attack(&"light").ok, "R47 actual player swing can still target the training dummy")
	await _frames(53)
	t.check(hits.size() == 1 and hits[0] > 0 and dummy.combat.health == dummy.combat.max_health, "R47 dummy accepts real melee contact and resets health without changing hit masks")
	t.check(ui.hud._recent_target != TrainingDummy.ENTITY_ID and not ui.hud.target.visible, "R44 a real dummy hit never enters recent hostile target retention")
	game.player.rotation.y = PI
	await _frames(8)
	t.check(not ui.hud.target.visible and session.state.player.crowns == crowns and not session.state.world.has(String(TrainingDummy.ENTITY_ID)), "R47 looking away from struck dummy shows no hostile bar or persistent reward")
	dummy.combat.hit_received.disconnect(received)
	game.player.spawn_at(original_position - Vector3.UP * 0.06, original_yaw)
	coordinator.set_physics_process(true)
	coordinator.refresh_budget()
