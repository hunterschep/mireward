extends RefCounted

class ArrivalBlocker extends StaticBody3D:
	var entries: int = 0
	func _enter_tree() -> void:
		entries += 1
		collision_layer = MireTypes.WORLD if entries > 1 else 0

var t: SceneTree
var session: Node
var saves: Node
var db: Node
var player: MirePlayer
var router: WorldRouter
var modes: GameModeController
var ray: InteractionRay
var factory: CampaignWorld
var activations: int = 0

func run(runner: SceneTree) -> void:
	t = runner
	session = t.root.get_node("GameSession")
	saves = t.root.get_node("SaveService")
	db = t.root.get_node("ContentDB")
	session.new_game()
	var container := Node3D.new()
	t.root.add_child(container)
	player = load("res://scenes/player/player.tscn").instantiate()
	t.root.add_child(player)
	player.set_physics_process(false)
	player.combat.input_driven = false
	var host := ModalHost.new()
	t.root.add_child(host)
	modes = GameModeController.new()
	t.root.add_child(modes)
	modes.configure(player, host)
	ray = InteractionRay.new()
	player.add_child(ray)
	ray.configure(player, modes)
	ray.set_physics_process(false)
	router = WorldRouter.new()
	t.root.add_child(router)
	router.fade_seconds = 0
	t.check(router.configure(player, container, modes).ok, "T16 opening factory uses the real persistent runtime")
	factory = CampaignWorld.new(player)
	router.world_builder = factory.build
	router.world_activated.connect(_activate)
	t.check(session.recovery.bind_runtime(player, router.is_dangerous, router.reset_living_encounters, router.recovery_travel).ok and saves.bind_runtime(player, router).ok, "T16 opening binds the actual recovery and save services")
	saves.set_physics_process(false)
	await _detached()
	await _restore(session.fresh_snapshot())
	await _clearance()
	await _opening_quest(false)
	await _cart_chase_and_loot()
	await _reconstruction()
	await _restore(session.fresh_snapshot())
	await _opening_quest(true)
	await frames(2)
	var bus: Node = t.root.get_node("EventBus")
	var before: int = bus.inventory_changed.get_connections().size()
	saves.unbind_runtime()
	saves.set_physics_process(true)
	session.recovery.unbind_runtime()
	router.free()
	container.free()
	t.check(bus.inventory_changed.get_connections().size() < before, "T16 disposing the world removes its object listeners")
	player.free()
	modes.free()
	host.free()
	t.paused = false
	session.new_game()
	await frames(2)

func frames(count: int = 2) -> void:
	for frame: int in count:
		await t.physics_frame
	await t.process_frame

func _activate(world: Node3D) -> void:
	for node: Node in world.find_children("*", "", true, false):
		if node is NpcActor or node is WorldObject or node is TrainingDummy:
			t.check(node.activate().ok, "T16 activate configured physical adapter")
	t.check(factory.activate(world).ok, "T16 factory binds live encounter hooks after world commit")
	activations += 1

func _restore(snapshot: Dictionary) -> void:
	var prepared: MireTypes.ActionResult = await router.prepare_restore(snapshot)
	t.check(prepared.ok, "T16 populated scene prepares on real navigation")
	if not prepared.ok:
		printerr(prepared.message_key)
		return
	var accepted := router.commit_restore(StringName(prepared.payload.prepared_token))
	t.check(accepted.ok, "T16 populated scene accepts prepared commit")
	var arrived: Array = await router.travel_completed
	t.check(arrived[1].ok, "T16 populated scene reaches actual terminal arrival")
	await frames(2)

func _detached() -> void:
	var bus: Node = t.root.get_node("EventBus")
	var before: Dictionary = session.snapshot()
	var listeners := [bus.inventory_changed.get_connections().size(), bus.quest_updated.get_connections().size(), player.combat.phase_changed.get_connections().size()]
	t.check(session.world_state.mark_defeated(&"south_cart_cutpurse_01").ok, "T16 construct real defeated candidate state")
	t.check(session.world_state.take_crowns(&"south_cart_cutpurse_01", &"opening/prepared_loot").ok, "T16 construct real looted candidate state")
	var candidate: Dictionary = session.snapshot()
	session.new_game()
	var prepared: MireTypes.ActionResult = await router.prepare_restore(candidate)
	t.check(prepared.ok and session.snapshot() == before and router.current_world == null, "T16 detached preparation cannot change the current session/world")
	if not prepared.ok: return
	var token := StringName(prepared.payload.prepared_token)
	var world: Node3D = router._prepared[token].world
	var population: CampaignWorld.Population = world.get_node("CampaignPopulation")
	t.check(not factory.build(world, candidate).ok, "T16 duplicate builder invocation cannot create duplicate sources")
	t.check(world.entities.size() == 41 and population.enemies.size() == 18 and population.purses.size() == 18, "T16 opening is preserved within the complete exterior population")
	t.check(population.coordinator.player == null and population.enemies[0].died.get_connections().is_empty(), "T16 prepared enemies have no live player/death bindings")
	t.check(world.entities[&"south_cart_cutpurse_01"].combat.dead and not population.purses[&"south_cart_cutpurse_01"].model.visible, "T16 detached saved defeat and depleted purse are applied before navigation")
	for id: StringName in [&"mara_venn", &"oswin_pike", &"cart_coffer", &"southern_sign", TrainingDummy.ENTITY_ID]:
		t.check(not world.entities[id].interaction.enabled, "T16 prepared adapter remains inactive: " + String(id))
	t.check(listeners == [bus.inventory_changed.get_connections().size(), bus.quest_updated.get_connections().size(), player.combat.phase_changed.get_connections().size()], "T16 preparation adds no global or player subscriptions")
	router.discard_prepared(token)
	t.check(session.snapshot() == before, "T16 discarding preparation changes no saved state")

func _clearance() -> void:
	var world: Node3D = router.current_world
	t.check(world.entities.size() == 47 and t.get_nodes_in_group("player").size() == 1, "T16 live opening adds only six router adapters and never duplicates the player")
	for id: StringName in world.entrances:
		t.check(router.validate_anchor(world, world.entrances[id]).ok, "T16 opening preserves entrance clearance: " + String(id))
	for id: StringName in world.rest_anchors:
		t.check(router.validate_anchor(world, world.rest_anchors[id]).ok, "T16 opening preserves rest clearance: " + String(id))
	for at: Vector3 in [Vector3(-107, 0, 144.7), Vector3(-99, 0, 136.7), Vector3(-97, 0, 138.7), Vector3(0, 0, 103.4)]:
		t.check(router.validate_anchor(world, Transform3D(Basis.IDENTITY, at)).ok, "T16 NPC, training and coffer approach is grounded, clear and navigable")
	var population: CampaignWorld.Population = world.get_node("CampaignPopulation")
	var connections: int = population.enemies[0].died.get_connections().size()
	t.check(factory.activate(world).ok and population.enemies[0].died.get_connections().size() == connections and connections == 1, "T16 repeated activation does not duplicate death handlers")
	var sign: WorldObject = world.entities[&"southern_sign"]
	var sign_result := await _interact(sign.interaction, CampaignWorld.SIGN_POSITION + Vector3(0, 0, 1.6))
	t.check(sign_result.ok and sign_result.payload.ui_action == "readable" and session.state.evidence.get("read/southern_sign", false), "T16 southern sign uses actual focus and retained canonical readable")
	var dummy: TrainingDummy = world.entities[TrainingDummy.ENTITY_ID]
	var training := await _interact(dummy.interaction, CampaignWorld.TRAINING_POSITION + Vector3(0, 0, 1.6))
	t.check(training.ok and training.payload.ui_action == "training", "T16 village dummy opens the genuine training flow")

func _interact(component: InteractionComponent, at: Vector3) -> MireTypes.ActionResult:
	player.spawn_at(at)
	player.camera.look_at(component.focus_position(), Vector3.UP)
	await frames(2)
	ray.refresh_focus()
	t.check(ray.focused == component, "T16 physical focus reaches " + String(component.entity_id))
	return ray.interact_focused()

func _opening_quest(early_full: bool) -> void:
	var world: Node3D = router.current_world
	var mara: NpcActor = world.entities[&"mara_venn"]
	var coffer: WorldObject = world.entities[&"cart_coffer"]
	if early_full:
		t.check(session.inventory.try_add(&"bandage", 8, &"opening/fill_bandages").ok, "T16 fill existing bandage stack through inventory API")
		for index: int in range(16 - session.state.inventory.size()):
			t.check(session.inventory.try_add(&"arming_sword", 1, StringName("opening/fill/" + str(index))).ok, "T16 full inventory fixture uses valid stack additions")
	else:
		var start := await _interact(mara.interaction, mara.position + Vector3(0, 0, 1.7))
		t.check(start.ok and session.dialogue.choose(StringName(start.payload.dialogue.node_id), &"accept_mq01").ok, "T16 physical Mara dialogue accepts Bread and Iron")
		session.dialogue.close()
	var opened := await _interact(coffer.interaction, coffer.position + Vector3(0, 0, -1.6))
	t.check(opened.ok and opened.payload.ui_action == "loot", "T16 physical medicine coffer opens real loot source")
	t.check(session.world_state.take_loot(&"cart_coffer", &"cart_medicine", 1, &"opening/medicine").ok, "T16 collect actual coffer medicine")
	var start := await _interact(mara.interaction, mara.position + Vector3(0, 0, 1.7))
	if early_full:
		t.check(start.ok and session.dialogue.choose(StringName(start.payload.dialogue.node_id), &"accept_mq01").ok, "T16 early collected medicine reconciles when Mara's quest is accepted")
		session.dialogue.close()
		start = await _interact(mara.interaction, mara.position + Vector3(0, 0, 1.7))
	var crowns: int = session.state.player.crowns
	var completed: MireTypes.ActionResult = session.dialogue.choose(StringName(start.payload.dialogue.node_id), &"complete_mq01")
	t.check(completed.ok and session.state.player.crowns == crowns + 18 and session.state.quests.mq_02_the_kings_due.state == "AVAILABLE", "T16 returning medicine pays once and unlocks MQ02")
	var after: Dictionary = session.snapshot()
	t.check(not session.dialogue.choose(StringName(start.payload.dialogue.node_id), &"complete_mq01").ok and session.snapshot() == after, "T16 stale repeated physical turn-in cannot pay twice")
	t.check(not session.state.key_items.has("cart_medicine") and session.state.evidence.cart_medicine, "T16 hand-in consumes medicine but retains its evidence")
	if early_full:
		t.check(session.state.pending_delivery.has("mq_01_bread_and_iron/bandage"), "T16 full-inventory turn-in preserves its bandage as pending delivery")
	session.dialogue.close()

func _cart_chase_and_loot() -> void:
	var world: Node3D = router.current_world
	var enemy: EnemyActor = world.entities[&"south_cart_cutpurse_02"]
	player.spawn_at(Vector3(3.8, 0, 111))
	player.combat.faction = &"neutral"
	var population: CampaignWorld.Population = world.get_node("CampaignPopulation")
	population.coordinator.refresh_budget()
	enemy.alert_to_player()
	var closest: float = enemy.global_position.distance_to(player.global_position)
	for frame: int in 480:
		await t.physics_frame
		closest = minf(closest, enemy.global_position.distance_to(player.global_position))
		if closest < 2.4: break
	t.check(closest < 2.4, "T16 normal-physics cutpurse chase routes around the placed cart")
	player.combat.faction = &"player"
	var defeated: EnemyActor = world.entities[&"south_cart_cutpurse_01"]
	var death_at: Vector3 = defeated.global_position
	var crowns: int = session.state.player.crowns
	var hit := defeated.combat.receive_hit(MireTypes.DamageRequest.new(&"player", 93001, defeated.entity_id, 100, &"heavy", player.global_position, &"player"))
	t.check(hit.outcome == &"killed" and session.world_state.get_entity_state(defeated.entity_id).defeated, "T16 actual enemy death commits the canonical persistent defeat")
	var purse: WorldObject = population.purses[defeated.entity_id]
	t.check(purse.get_parent() == world and purse.model.visible and purse.global_position.distance_to(death_at) < 1.1 and world.entities[defeated.entity_id] == defeated, "T16 purse is a visible sibling beside actual death, with actor retaining entity ownership")
	t.check(session.state.player.crowns == crowns and purse.collision_layer == 0, "T16 defeat grants no duplicate money and corpse purse never blocks movement")
	t.check(session.world_state.take_crowns(defeated.entity_id, &"opening/purse").ok and session.state.player.crowns == crowns + 4, "T16 purse grants authored crowns exactly once")
	var after: Dictionary = session.snapshot()
	t.check(session.world_state.take_crowns(defeated.entity_id, &"opening/purse").payload.replayed and session.snapshot() == after and not purse.model.visible, "T16 replay cannot duplicate purse crowns or resurrect its visual")
	player.spawn_at(Vector3(-107, 0, 145))
	await frames(20)

func _reconstruction() -> void:
	var before: Dictionary = session.snapshot()
	t.check(saves.save_slot(&"manual_1").ok, "T16 completed opening can write a real manual save")
	var loaded: MireTypes.ActionResult = await saves.load_slot(&"manual_1")
	t.check(loaded.ok, "T16 completed opening reconstructs through actual file validation and terminal load")
	var world: Node3D = router.current_world
	t.check(world.entities[&"south_cart_cutpurse_01"].combat.dead and world.entities[&"south_cart_cutpurse_02"].combat.health == 45, "T16 reconstruction keeps defeated actor dead and restores living actor fully")
	t.check(not world.get_node("CampaignPopulation").purses[&"south_cart_cutpurse_01"].model.visible and session.state.player.crowns == before.player.crowns, "T16 reconstructed purse retains depletion without replaying currency")
	t.check(world.entities[&"cart_coffer"].model.get_node("Lid").rotation.x > 0 and session.state.quests.mq_01_bread_and_iron.state == "COMPLETED", "T16 completed quest and open coffer survive scene reconstruction")
	before = session.snapshot()
	var bus: Node = t.root.get_node("EventBus")
	var subscriptions := [bus.inventory_changed.get_connections().size(), bus.quest_updated.get_connections().size(), player.combat.phase_changed.get_connections().size()]
	router.world_builder = func(prepared: Node3D, candidate: Dictionary) -> MireTypes.ActionResult:
		var built := factory.build(prepared, candidate)
		if not built.ok: return built
		var blocker := ArrivalBlocker.new()
		blocker.position = Vector3(0, 1, 3)
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(3, 2, 3)
		collision.shape = box
		blocker.add_child(collision)
		prepared.add_child(blocker)
		return MireTypes.success()
	var failed := router.travel(&"interior_inn", &"entry")
	t.check(failed.ok, "T16 rollback fixture reaches actual final-arrival validation")
	var rejected: Array = await router.travel_completed
	t.check(not rejected[1].ok and router.current_world == world and session.snapshot() == before, "T16 failed arrival restores the populated prior world without domain changes")
	t.check(subscriptions == [bus.inventory_changed.get_connections().size(), bus.quest_updated.get_connections().size(), player.combat.phase_changed.get_connections().size()] and world.entities[&"south_cart_cutpurse_01"].died.get_connections().size() == 1, "T16 world re-entry reconnects each live binding exactly once")
	router.world_builder = factory.build
	for trip: int in 2:
		var accepted := router.travel(&"interior_inn", &"entry")
		t.check(accepted.ok, "T16 opening enters the real inn")
		var arrived: Array = await router.travel_completed
		t.check(arrived[1].ok and router.current_world.entities.has(&"tamsin_reed"), "T16 Tamsin populates only the inn")
		t.check(router.validate_anchor(router.current_world, router.current_world.rest_anchors[&"inn_bed"]).ok, "T16 Tamsin preserves the canonical bed anchor")
		accepted = router.travel(&"exterior", &"from_inn")
		t.check(accepted.ok, "T16 return to the persistent opening")
		arrived = await router.travel_completed
		t.check(arrived[1].ok and router.current_world.entities.size() == 47, "T16 return never duplicates opening sources")
		var population: CampaignWorld.Population = router.current_world.get_node("CampaignPopulation")
		t.check(population.enemies[0].died.get_connections().size() == 1 and population.coordinator.actors().size() == 18, "T16 return binds each canonical actor exactly once")
