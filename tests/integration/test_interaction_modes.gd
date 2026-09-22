extends RefCounted

func frames(t: SceneTree, count: int = 2) -> void:
	for _index: int in count:
		await t.physics_frame
	await t.process_frame

func key(physical: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = physical
	event.pressed = pressed
	Input.parse_input_event(event)

func body(parent: Node3D, at: Vector3, size: Vector3) -> StaticBody3D:
	var solid := StaticBody3D.new()
	solid.position = at
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	solid.add_child(collision)
	parent.add_child(solid)
	return solid

func target(parent: Node3D, id: StringName, at: Vector3, size: Vector3, calls: Array) -> InteractionComponent:
	var component := InteractionComponent.new()
	component.entity_id = id
	component.position = at
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	component.add_child(collision)
	component.action_handler = func(actor: StringName, action: StringName) -> MireTypes.ActionResult:
		calls.append({"entity": String(id), "actor": String(actor), "action": String(action)})
		return MireTypes.success()
	parent.add_child(component)
	return component

func run(t: SceneTree) -> void:
	t.root.get_node("GameSession").new_game()
	var arena := Node3D.new()
	t.root.add_child(arena)
	body(arena, Vector3(0, -0.5, 0), Vector3(50, 1, 50))
	var player: MirePlayer = load("res://scenes/player/player.tscn").instantiate()
	arena.add_child(player)
	var host := ModalHost.new()
	t.root.add_child(host)
	var controller := GameModeController.new()
	arena.add_child(controller)
	controller.configure(player, host)
	var ray := InteractionRay.new()
	player.add_child(ray)
	ray.configure(player, controller)
	await frames(t, 15)
	var calls: Array = []
	var near: InteractionComponent = target(arena, &"near", Vector3(0, 1.65, -1.4), Vector3(0.7, 0.7, 0.3), calls)
	var far: InteractionComponent = target(arena, &"far", Vector3(0, 1.65, -2.2), Vector3(0.8, 0.8, 2.7), calls)
	await frames(t)
	ray.refresh_focus()
	t.check(ray.focused == near, "R09 nearest physical target wins even when a farther trigger protrudes in front")
	key(KEY_E, true)
	await frames(t, 12)
	t.check(calls.size() == 1 and calls[0].entity == "near", "R09 holding E activates once through the actual input map")
	key(KEY_E, false)
	await frames(t)
	key(KEY_E, true)
	await frames(t, 3)
	key(KEY_E, false)
	t.check(calls.size() == 2, "R09 a separate E press validates and activates again")
	var locked: Dictionary = {"value": false}
	near.offer_handler = func(_actor: StringName) -> MireTypes.InteractionOffer:
		return MireTypes.InteractionOffer.new(&"near", "Enter", not locked.value, "The door is barred.", &"interact")
	ray.refresh_focus()
	locked.value = true
	var refused: MireTypes.ActionResult = ray.interact_focused()
	t.check(not refused.ok and refused.code == &"unavailable" and calls.size() == 2 and ray.offer.reason_key == "The door is barred.", "R09 stale availability revalidates at commit and displays the current refusal reason")
	locked.value = false
	var changed_action: Dictionary = {"value": &"open"}
	near.offer_handler = func(_actor: StringName) -> MireTypes.InteractionOffer:
		return MireTypes.InteractionOffer.new(&"near", "Open", true, "", changed_action.value)
	ray.refresh_focus()
	changed_action.value = &"read"
	t.check(ray.interact_focused().code == &"stale_offer" and calls.size() == 2, "R09 an action that changes after its prompt cannot commit under the old action ID")
	near.queue_free()
	await frames(t)
	var wall: StaticBody3D = body(arena, Vector3(0, 1.5, -1.3), Vector3(3, 3, 0.2))
	await frames(t)
	ray.refresh_focus()
	t.check(ray.focused == null, "R09 solid wall blocks an oversized interaction trigger that crosses the wall")
	t.check(not ray.interact_focused().ok and calls.size() == 2, "R09 no interaction commits through world geometry")
	wall.queue_free()
	await frames(t)
	far.position.z = -3.2
	await frames(t)
	ray.refresh_focus()
	t.check(ray.focused == null, "R09 actual focus point must remain within 2.5 meters despite an oversized trigger")
	far.position.z = -2.2
	await frames(t)
	ray.refresh_focus()
	far.position.x = 4.0
	await frames(t)
	t.check(not ray.interact_focused().ok and calls.size() == 2, "R09 moving the target after focus prevents stale spatial activation")
	far.queue_free()
	await frames(t)
	for kind: String in ["readable", "container", "door", "npc"]:
		var adapter := InteractionComponent.new()
		adapter.entity_id = StringName(kind)
		adapter.kind = kind
		arena.add_child(adapter)
		t.check(not adapter.get_offer(&"player").allowed and adapter.interact(&"player", &"interact").code == &"unsupported", "R09 unbound " + kind + " adapter cannot report a fake success")
		adapter.queue_free()
	var door: StaticBody3D = body(arena, Vector3(0, 1.5, -1.8), Vector3(1, 3, 0.2))
	var door_target: InteractionComponent = target(arena, &"door", Vector3(0, 1.65, -1.8), Vector3(1, 1, 0.5), calls)
	door_target.physical_body = door
	await frames(t)
	ray.refresh_focus()
	t.check(ray.focused == door_target, "R09 a solid door can interact with its own surface without ignoring other world blockers")
	var modal_calls: Array[int] = [0]
	door_target.action_handler = func(_actor: StringName, _action: StringName) -> MireTypes.ActionResult:
		modal_calls[0] += 1
		controller.push_mode(&"readable")
		return MireTypes.success()
	key(KEY_E, true)
	await t.create_timer(0.04, true).timeout
	t.check(controller.mode == &"readable" and modal_calls[0] == 1, "R09 R45 a world action can open its registered modal through the controller")
	controller.pop_mode()
	await frames(t, 4)
	t.check(controller.mode == &"gameplay" and modal_calls[0] == 1, "R08 holding E while closing its opened panel cannot retrigger interaction")
	key(KEY_E, false)
	await frames(t)
	await check_modes(t, player, controller, host, ray)
	door_target.queue_free()
	door.queue_free()
	controller.push_mode(&"pause")
	arena.queue_free()
	host.queue_free()
	await t.process_frame
	t.check(not t.paused, "R45 removing the controller releases tree pause for the next scene")

func check_modes(t: SceneTree, player: MirePlayer, controller: GameModeController, host: ModalHost, ray: InteractionRay) -> void:
	var inventory := VBoxContainer.new()
	var inventory_button := Button.new()
	inventory_button.text = "Inspect equipment"
	inventory.add_child(inventory_button)
	t.check(host.register_panel(&"inventory", inventory, inventory_button).ok, "R45 modal host accepts a real panel and initial focus")
	key(KEY_TAB, true)
	await t.process_frame
	key(KEY_TAB, false)
	await t.process_frame
	t.check(controller.mode == &"inventory" and t.paused and not player.input_enabled and host.visible and inventory_button.has_focus(), "R45 Tab enters inventory with paused simulation and keyboard focus")
	t.check(ray.offer == null and not ray.interact_focused().ok, "R09 R45 modal input cannot activate the previous world offer")
	controller.push_mode(&"confirmation")
	await t.process_frame
	controller.pop_mode()
	await t.process_frame
	t.check(controller.mode == &"inventory" and inventory_button.has_focus(), "R45 subordinate confirmation returns to its parent and restores focus")
	key(KEY_J, true)
	await t.process_frame
	key(KEY_J, false)
	t.check(controller.mode == &"journal" and controller.stack == [&"gameplay", &"journal"] and not inventory.visible, "R45 opening another gameplay menu replaces the prior main panel")
	key(KEY_ESCAPE, true)
	await t.process_frame
	key(KEY_ESCAPE, false)
	t.check(controller.mode == &"gameplay" and not t.paused and player.input_enabled and not host.visible, "R45 Escape returns from a main panel to gameplay")
	controller.push_mode(&"pause")
	controller.push_mode(&"settings")
	controller.push_mode(&"confirmation")
	controller.pop_mode()
	t.check(controller.mode == &"settings" and t.paused, "R45 confirmation above settings restores settings")
	controller.pop_mode()
	t.check(controller.mode == &"pause", "R45 settings opened from pause returns to pause")
	controller.pop_mode()
	var modes_valid: bool = true
	for requested: StringName in MireTypes.MODES:
		modes_valid = modes_valid and controller.push_mode(requested).ok
		controller.push_mode(&"gameplay")
	t.check(modes_valid, "R45 all frozen mode IDs can be entered through the central API")
	t.check(not controller.push_mode(&"unknown_mode").ok and controller.mode == &"gameplay", "R45 invalid modes leave the current mode unchanged")
	var stable_stack := controller.snapshot_stack()
	var detached_stack := controller.snapshot_stack()
	detached_stack.append(&"pause")
	t.check(controller.stack == stable_stack, "R45 menu stack snapshots are detached")
	for invalid: Array in [[], [null], [{}], [&"unknown"], [&"confirmation"], [&"gameplay", &"gameplay"], [&"gameplay", &"pause", &"inventory"], [&"gameplay", &"pause", &"pause"]]:
		t.check(not controller.restore_stack(invalid).ok and controller.stack == stable_stack and controller.mode == &"gameplay" and not t.paused, "R45 invalid stack restore has no partial menu or input changes")
	t.check(controller.restore_stack(["gameplay", "pause", "load", "confirmation"]).ok and controller.stack == [&"gameplay", &"pause", &"load", &"confirmation"], "R45 valid complete menu stack restores through controller policy")
	controller.set_back_locked(true)
	controller.pop_mode()
	t.check(controller.mode == &"confirmation", "R35 committed ending confirmation can require explicit save handling before Back")
	controller.push_mode(&"gameplay")
	controller.push_mode(&"inventory")
	controller.pop_mode()
	t.check(controller.mode == &"gameplay", "R45 a subsequent ordinary menu keeps normal Back navigation")
	var recovery: RecoveryService = t.root.get_node("GameSession").recovery
	recovery._pending_recovery = {"reason": "fixture"}
	t.check(controller.restore_stack([&"gameplay"]).ok and controller.mode == &"travel" and t.paused and not player.input_enabled, "R45 restoring gameplay cannot bypass pending recovery ownership")
	recovery._pending_recovery.clear()
	await t.process_frame
	t.check(controller.mode == &"gameplay" and not t.paused and player.input_enabled, "R45 controller releases restored recovery travel only when recovery settles")
	Input.action_press(&"attack_light")
	Input.action_press(&"block")
	controller.push_mode(&"inventory")
	controller.pop_mode()
	await frames(t)
	t.check(not player.controls.pressed(&"attack_light") and not player.controls.held(&"block") and player.controls.suppressed, "R08 held attack and block stay suppressed across menu resume")
	Input.action_release(&"attack_light")
	Input.action_release(&"block")
	await frames(t)
	Input.action_press(&"attack_light")
	t.check(player.controls.pressed(&"attack_light"), "R08 a released then newly pressed attack is accepted")
	Input.action_release(&"attack_light")
	controller.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	t.check(controller.mode == &"pause" and t.paused and not player.input_enabled, "R08 window focus loss pauses gameplay and disables player input")
	controller.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	t.check(controller.mode == &"pause" and t.paused, "R08 returning focus does not resume combat automatically")
	controller.pop_mode()
	await frames(t)
	Input.action_press(&"move_forward")
	await frames(t, 6)
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.one_shot = true
	player.add_child(timer)
	timer.start()
	controller.push_mode(&"pause")
	var position: Vector3 = player.global_position
	var remaining: float = timer.time_left
	var stamina: float = t.root.get_node("GameSession").state.player.stamina
	await t.create_timer(0.1, true).timeout
	t.check(player.global_position == position and timer.time_left == remaining and t.root.get_node("GameSession").state.player.stamina == stamina, "R45 movement and gameplay resource/timer state freeze during a modal")
	controller.pop_mode()
	await frames(t, 3)
	t.check(timer.time_left < remaining and timer.time_left > remaining - 0.2, "R45 resuming advances only resumed time without skipping the modal interval")
	Input.action_release(&"move_forward")
	timer.queue_free()
	await frames(t)
