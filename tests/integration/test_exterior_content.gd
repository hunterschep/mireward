extends RefCounted

var t: SceneTree
var session: Node
var bus: Node
var db: Node
var player: MirePlayer
var world: MireExterior
var modes: GameModeController
var ray: InteractionRay
var factory: CampaignWorld
var validator: WorldRouter

func run(runner: SceneTree) -> void:
	t = runner
	session = t.root.get_node("GameSession")
	bus = t.root.get_node("EventBus")
	db = t.root.get_node("ContentDB")
	session.new_game()
	player = load("res://scenes/player/player.tscn").instantiate()
	t.root.add_child(player)
	player.set_physics_process(false)
	player.combat.input_driven = false
	modes = GameModeController.new()
	t.root.add_child(modes)
	modes.configure(player)
	ray = InteractionRay.new()
	player.add_child(ray)
	ray.configure(player, modes)
	ray.set_physics_process(false)
	factory = CampaignWorld.new(player)
	validator = WorldRouter.new()
	var subscriptions := _listeners()
	var before: Dictionary = session.snapshot()
	world = await _build(before)
	var population: CampaignWorld.Population = world.get_node("CampaignPopulation")
	t.check(session.snapshot() == before and _listeners() == subscriptions, "T17 complete staged population has no live subscriptions or domain effects")
	t.check(world.entities.size() == 41 and population.enemies.size() == 18 and population.purses.size() == 18, "T17 canonical staged registry contains 41 entities and 18 sibling purses")
	t.check(not factory.build(world, before).ok and not factory.populate_encounters(world, before).ok, "T17 duplicate population and encounter calls are rejected")
	await _registry_and_clearance(population)
	_activate(population)
	await _all_approaches()
	await _persistence(population)
	world.free()
	await frames()
	t.check(_listeners() == subscriptions, "T17 complete population disposal releases all live subscriptions")
	await _interior_boundary()
	validator.free()
	modes.free()
	player.free()
	session.new_game()
	await frames()

func frames(count: int = 2) -> void:
	for frame: int in count:
		await t.physics_frame
	await t.process_frame

func _listeners() -> Array:
	return [bus.inventory_changed.get_connections().size(), bus.quest_updated.get_connections().size(), bus.session_restored.get_connections().size(), player.combat.phase_changed.get_connections().size()]

func _build(snapshot: Dictionary) -> MireExterior:
	var next: MireExterior = load(WorldRouter.SCENES[&"exterior"]).instantiate()
	t.root.add_child(next)
	await next.navigation_synchronized
	t.check(factory.build(next, snapshot).ok, "T17 actual exterior builds from detached snapshot")
	next.get_node("CampaignPopulation").coordinator.set_physics_process(false)
	await frames()
	return next

func _activate(population: CampaignWorld.Population) -> void:
	for node: Node in world.find_children("*", "", true, false):
		if node is NpcActor or node is WorldObject or node is TrainingDummy:
			t.check(node.activate().ok, "T17 physical adapter activates after commit")
	t.check(factory.activate(world).ok and factory.activate(world).ok, "T17 repeated population activation is safe")
	var connected := _listeners()
	population.deactivate()
	population.deactivate()
	t.check(not population.details.is_processing(), "T17 population deactivation stops neutral idle")
	t.check(factory.activate(world).ok and _listeners() == connected, "T17 population reactivation adds no duplicate listeners")
	# Geometry inspection keeps hostile AI static; separate T07/T16 suites exercise combat.
	population.coordinator.configure(player)
	population.coordinator.set_physics_process(false)

func _registry_and_clearance(population: CampaignWorld.Population) -> void:
	var names: Array[String] = []
	var sources: Array[String] = []
	var groups: Dictionary = {}
	for reservation: Dictionary in db.map.exterior.npc_reservations:
		if reservation.scene_id != "exterior": continue
		var actor: NpcActor = world.entities[StringName(reservation.id)]
		names.append(reservation.id)
		t.check(actor.position == ExteriorTerrain.vector(reservation.position) and not actor.interaction.enabled, "T17 staged NPC uses exact manifest station: " + reservation.id)
	for reservation: Dictionary in db.map.exterior.objective_reservations:
		if reservation.scene_id != "exterior": continue
		var source: WorldObject = world.entities[StringName(reservation.id)]
		sources.append(reservation.id)
		t.check(source.position == ExteriorTerrain.vector(reservation.position) and not source.interaction.enabled, "T17 fixed source uses exact manifest station: " + reservation.id)
	t.check(names.size() == 6 and sources.size() == 11 and not world.entities.has(&"captain_rusk"), "T17 six exterior noncombat speakers and eleven fixed sources exclude interior assignments")
	t.check(world.find_children("*", "EncounterCoordinator", true, false).size() == 1 and population.coordinator.actors().size() == 18, "T17 all exterior groups share one global coordinator")
	for spawn: Dictionary in db.map.spawns:
		if spawn.scene_id != "exterior": continue
		var actor: EnemyActor = world.entities[StringName(spawn.id)]
		groups[spawn.group] = true
		t.check(actor.coordinator == population.coordinator and actor.global_position.is_equal_approx(ExteriorTerrain.vector(spawn.position) + Vector3.UP * 0.04), "T17 hostile uses exact manifest spawn and shared coordinator: " + spawn.id)
		t.check(population.purses[actor.entity_id].get_parent() == world and not population.purses[actor.entity_id].model.visible, "T17 living enemy owns registry identity; hidden sibling purse cannot grant early loot")
		var floor_hit := _ground(actor.position, [actor.get_rid()])
		t.check(not floor_hit.is_empty() and actor.position.y - floor_hit.position.y >= 0.025 and actor.position.y - floor_hit.position.y < 0.08, "T17 sleeping hostile feet clear the actual ground: " + spawn.id)
		var query := PhysicsShapeQueryParameters3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.32
		capsule.height = 1.8
		query.shape = capsule
		query.transform = Transform3D(Basis.IDENTITY, actor.position + Vector3.UP * 0.9)
		query.collision_mask = MireTypes.WORLD | MireTypes.HOSTILE | MireTypes.NEUTRAL
		query.exclude = [actor.get_rid()]
		t.check(world.get_world_3d().direct_space_state.intersect_shape(query).is_empty(), "T17 initial hostile capsule is not embedded: " + spawn.id)
	t.check(groups.size() == 8, "T17 all eight exterior encounter groups are present")
	for id: StringName in world.entrances:
		t.check(validator.validate_anchor(world, world.entrances[id]).ok, "T17 populated entrance clearance: " + String(id))
	for id: StringName in world.rest_anchors:
		t.check(validator.validate_anchor(world, world.rest_anchors[id]).ok, "T17 populated rest clearance: " + String(id))
	t.check(world.landmarks.size() == 9 and world.landmark_areas.size() == 9, "T17 all nine visible landmarks retain discovery triggers")
	for landmark: Dictionary in db.map.landmarks:
		var at := ExteriorTerrain.vector(landmark.position)
		t.check(world.landmarks[StringName(landmark.id)].position == at and world.landmark_areas[StringName(landmark.id)].position == at, "T17 visible landmark and discovery geometry retain canonical anchor: " + landmark.id)
	t.check(population.details.residents.size() == 4, "T17 two camp residents and two courtyard wardens are physically present")
	for neutral: StaticBody3D in population.details.residents:
		t.check(neutral.collision_layer == MireTypes.NEUTRAL and not neutral is NpcActor and neutral.find_children("*", "CombatComponent", true, false).is_empty() and neutral.find_children("*", "CombatHurtbox", true, false).is_empty(), "T17 unnamed residents are clearly neutral and invulnerable")
		t.check(validator.validate_anchor(world, Transform3D(Basis.IDENTITY, neutral.position - neutral.basis.z * 1.7)).ok, "T17 neutral resident approach is grounded and clear")

func _ground(at: Vector3, excluded: Array[RID] = []) -> Dictionary:
	return world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.5, at - Vector3.UP, MireTypes.WORLD, excluded))

func _all_approaches() -> void:
	for id: StringName in world.entities:
		var node: Node3D = world.entities[id]
		if not node is NpcActor and not node is WorldObject: continue
		var at: Vector3 = node.global_position - node.global_basis.z * 1.7
		if id == &"ferry_blanket_barrel":
			at = node.global_position + Vector3(-1.7, 0, 0)
		var ground := _ground(at)
		if not ground.is_empty(): at.y = ground.position.y
		var safe := validator.validate_anchor(world, Transform3D(Basis.IDENTITY, at))
		t.check(safe.ok, "T17 grounded, navigable approach: " + String(id) + " " + String(safe.message_key))
		player.spawn_at(at)
		player.camera.look_at(node.interaction.focus_position(), Vector3.UP)
		await frames()
		ray.refresh_focus()
		t.check(ray.focused == node.interaction, "T17 real player ray reaches: " + String(id))
		var result := ray.interact_focused()
		if id == &"village_writ_table":
			t.check(not result.ok and not session.state.evidence.get("read/village_writ_table", false), "T17 early writ remains quest-gated despite physical reach")
		else:
			t.check(result.ok, "T17 actual adapter interaction succeeds: " + String(id))
		if node is NpcActor:
			session.dialogue.close()
		elif node._kind == &"readable" and id != &"village_writ_table":
			t.check(session.state.evidence.get("read/" + String(id), false), "T17 environmental readable permanently enters the journal")
	var population: CampaignWorld.Population = world.get_node("CampaignPopulation")
	for spawn: Dictionary in db.map.spawns:
		if spawn.scene_id != "exterior": continue
		player.spawn_at(ExteriorTerrain.vector(spawn.position) + Vector3(0, 0, 10))
		population.coordinator.refresh_budget()
		t.check(population.coordinator.active_count <= 12, "T17 global thinking cap holds at each encounter station")
		for enemy: EnemyActor in population.enemies:
			population.coordinator.reserve_attack(enemy)
			population.coordinator.release_attack(enemy.entity_id)
			enemy.set_thinking(false)
	# Crowd all canonical groups only inside this fixture to exercise the global caps.
	var positions: Dictionary = {}
	player.spawn_at(Vector3.ZERO)
	for index: int in population.enemies.size():
		var enemy: EnemyActor = population.enemies[index]
		positions[enemy.entity_id] = enemy.position
		enemy.position = Vector3(index % 6, 0.04, -3 - index / 6)
	population.coordinator.refresh_budget()
	t.check(population.coordinator.active_count == 12, "T17 crowded canonical groups still share exactly twelve thinking slots")
	var most_reserved: int = 0
	for enemy: EnemyActor in population.coordinator.actors():
		population.coordinator._physics_process(0.26)
		population.coordinator.reserve_attack(enemy)
		most_reserved = maxi(most_reserved, population.coordinator.reservation_count)
		t.check(population.coordinator.reservation_count <= 2, "T17 cross-group attack reservations never exceed two")
	t.check(most_reserved == 2, "T17 shared coordinator permits two real reservations while rejecting a third")
	for enemy: EnemyActor in population.enemies:
		population.coordinator.release_attack(enemy.entity_id)
		enemy.set_thinking(false)
		enemy.position = positions[enemy.entity_id]

func _persistence(population: CampaignWorld.Population) -> void:
	var id := &"watchtower_deserter_raider_01"
	var actor: EnemyActor = world.entities[id]
	var crowns: int = session.state.player.crowns
	var hit := actor.combat.receive_hit(MireTypes.DamageRequest.new(&"player", 97101, id, 100, &"heavy", player.global_position, &"player"))
	t.check(hit.outcome == &"killed" and session.world_state.get_entity_state(id).defeated and population.purses[id].model.visible, "T17 non-opening actual defeat creates canonical corpse loot")
	t.check(session.world_state.take_crowns(id, &"t17/watchtower_purse").ok and session.state.player.crowns > crowns, "T17 canonical non-opening purse grants its authored crowns")
	t.check(session.world_state.take_loot(&"raider_medicine_cache", &"camp_medicine", 1, &"t17/early_medicine").ok, "T17 fixed camp medicine remains collectible before MQ04 activation")
	var before: Dictionary = session.snapshot()
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(before))
	world.free()
	await frames()
	world = await _build(snapshot)
	population = world.get_node("CampaignPopulation")
	t.check(world.entities[id].combat.dead and not population.purses[id].model.visible, "T17 JSON snapshot reconstructs defeated actor and depleted purse")
	t.check(world.entities[&"raider_medicine_cache"].model.get_node("Lid").rotation.x > 0 and session.snapshot() == before, "T17 opened fixed source reconstruction has no extra domain effects")

func _interior_boundary() -> void:
	for scene_id: StringName in [&"interior_inn", &"interior_crypt", &"interior_undercroft"]:
		var interior: Node3D = load(WorldRouter.SCENES[scene_id]).instantiate()
		t.root.add_child(interior)
		t.check(factory.build(interior, session.snapshot()).ok, "T17 base campaign can prepare " + String(scene_id))
		var population: CampaignWorld.Population = interior.get_node("CampaignPopulation")
		t.check(population.enemies.is_empty() and population.coordinator == null, "T17 unfinished interior encounters require explicit chapter composition")
		if scene_id == &"interior_inn":
			t.check(interior.entities.size() == 1 and interior.entities.has(&"tamsin_reed"), "T17 seventh noncombat speaker lives only in the inn")
			var tamsin: NpcActor = interior.entities[&"tamsin_reed"]
			t.check(tamsin.activate().ok, "T17 inn speaker activates through the shared adapter")
			player.spawn_at(tamsin.position - tamsin.basis.z * 1.7)
			player.camera.look_at(tamsin.interaction.focus_position(), Vector3.UP)
			await frames()
			ray.refresh_focus()
			t.check(ray.focused == tamsin.interaction and ray.interact_focused().ok, "T17 actual player ray reaches Tamsin in the inn")
			session.dialogue.close()
		else:
			t.check(interior.entities.is_empty(), "T17 interior story sources remain assigned to chapter owner")
			t.check(factory.populate_encounters(interior, session.snapshot()).ok and not factory.populate_encounters(interior, session.snapshot()).ok, "T17 explicit shared interior encounter lifecycle installs exactly once")
			t.check(population.enemies.size() == (4 if scene_id == &"interior_crypt" else 3), "T17 shared lifecycle provides exact ordinary interior count and excludes Rusk")
		interior.free()
	await frames()
