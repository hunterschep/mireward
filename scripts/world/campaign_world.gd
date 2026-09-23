class_name CampaignWorld
extends RefCounted
## Authored exterior population. WorldRouter owns detached preparation and lifetime.

const NPC_SCENE := preload("res://scenes/actors/npc.tscn")
const ENEMY_SCENE := preload("res://scenes/actors/enemy.tscn")
const CART_POSITION := Vector3(3.8, 0, 106)
const SIGN_POSITION := Vector3(30.6, 0, 248.5)
const TRAINING_POSITION := Vector3(-97, 0, 137)
var player: MirePlayer

class Population extends Node:
	var coordinator: EncounterCoordinator
	var details: ExteriorContent
	var enemies: Array[EnemyActor] = []
	var purses: Dictionary = {}
	var _active: bool = false

	func activate() -> MireTypes.ActionResult:
		if not is_inside_tree():
			return MireTypes.failure(&"unavailable", &"The campaign world is not attached.")
		if _active:
			return MireTypes.success()
		if is_instance_valid(details):
			var ready := details.activate()
			if not ready.ok:
				return ready
		_active = true
		for enemy: EnemyActor in enemies:
			enemy.died.connect(_enemy_died.bind(enemy))
		if is_instance_valid(coordinator):
			coordinator.danger_changed.connect(_danger_changed)
			_danger_changed(coordinator.is_dangerous())
		else:
			_danger_changed(false)
		return MireTypes.success()

	func deactivate() -> void:
		if not _active:
			return
		_active = false
		if is_instance_valid(details):
			details.deactivate()
		for enemy: EnemyActor in enemies:
			if is_instance_valid(enemy) and enemy.died.is_connected(_enemy_died.bind(enemy)):
				enemy.died.disconnect(_enemy_died.bind(enemy))
		if is_instance_valid(coordinator) and coordinator.danger_changed.is_connected(_danger_changed):
			coordinator.danger_changed.disconnect(_danger_changed)

	func _enemy_died(id: StringName, enemy: EnemyActor) -> void:
		if not _active or not is_instance_valid(enemy) or enemy.entity_id != id or not enemy.combat.dead or not purses.has(id):
			return
		var purse: WorldObject = purses[id]
		var at: Vector3 = enemy.global_position + Vector3(0.65, 0, 0)
		var ground := enemy.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2, at - Vector3.UP * 4, MireTypes.WORLD))
		if not ground.is_empty():
			at.y = ground.position.y
		purse.global_position = at
		var result: MireTypes.ActionResult = GameSession.world_state.mark_defeated(id)
		if not result.ok:
			EventBus.feedback.emit(String(result.message_key))
			return
		purse.apply_persistent_state(GameSession.world_state.get_entity_state(id))

	func _danger_changed(danger: bool) -> void:
		if _active:
			GameSession.danger = danger

	func _exit_tree() -> void:
		deactivate()

func _init(controlled_player: MirePlayer) -> void:
	player = controlled_player

func build(world: Node3D, candidate: Dictionary) -> MireTypes.ActionResult:
	if not is_instance_valid(player) or not is_instance_valid(world) or not world.is_inside_tree() or not world.get("entities") is Dictionary or not ContentDB.map.scenes.has(String(world.get("scene_id"))) or not candidate.get("world") is Dictionary:
		return MireTypes.failure(&"invalid_runtime", &"Campaign construction needs a world, player and detached snapshot.")
	if world.has_node("CampaignPopulation"):
		return MireTypes.failure(&"duplicate_population", &"The campaign content is already installed in this world.")
	var population := Population.new()
	population.name = "CampaignPopulation"
	world.add_child(population)
	var scene_id := String(world.get("scene_id"))
	for reservation: Dictionary in ContentDB.map.exterior.npc_reservations:
		if reservation.scene_id != scene_id or StringName(reservation.id) not in NpcActor.NPC_IDS:
			continue
		if world.entities.has(StringName(reservation.id)):
			return MireTypes.failure(&"duplicate_entity", &"A character already owns this world identity.")
		var npc: NpcActor = NPC_SCENE.instantiate()
		npc.name = String(reservation.id)
		npc.position = _vector(reservation.position)
		npc.rotation.y = -PI / 2 if reservation.id == "tamsin_reed" else PI
		world.add_child(npc)
		var configured := npc.configure(GameSession, StringName(reservation.id), false)
		if not configured.ok:
			return configured
		world.entities[npc.entity_id] = npc
	if scene_id != "exterior":
		return MireTypes.success()
	for reservation: Dictionary in ContentDB.map.exterior.objective_reservations:
		if reservation.scene_id != scene_id:
			continue
		var placed := _object(world, StringName(reservation.id), &"loot", _vector(reservation.position), candidate)
		if not placed.ok:
			return placed
	var sign := _object(world, &"southern_sign", &"readable", SIGN_POSITION, candidate, -2.76)
	if not sign.ok:
		return sign
	_cart(world)
	var dummy := TrainingDummy.new()
	dummy.name = "TrainingDummy"
	dummy.position = TRAINING_POSITION
	dummy.rotation.y = PI
	world.add_child(dummy)
	world.entities[TrainingDummy.ENTITY_ID] = dummy
	var encounters := populate_encounters(world, candidate)
	if not encounters.ok:
		return encounters
	population.details = ExteriorContent.new()
	population.details.name = "ExteriorContent"
	world.add_child(population.details)
	var dressed := population.details.configure(world, candidate)
	if not dressed.ok:
		return dressed
	return MireTypes.success()

## Interior chapter builders reuse the same ordinary-actor and purse lifecycle.
func populate_encounters(world: Node3D, candidate: Dictionary) -> MireTypes.ActionResult:
	if not is_instance_valid(player) or not is_instance_valid(world) or not world.is_inside_tree() or not world.get("entities") is Dictionary or not ContentDB.map.scenes.has(String(world.get("scene_id"))) or not candidate.get("world") is Dictionary:
		return MireTypes.failure(&"invalid_runtime", &"Encounter construction needs a prepared world and snapshot.")
	var population := world.get_node_or_null("CampaignPopulation") as Population
	if population == null or is_instance_valid(population.coordinator):
		return MireTypes.failure(&"duplicate_population", &"Prepare one campaign population before adding its encounters once.")
	var scene_id := String(world.get("scene_id"))
	population.coordinator = EncounterCoordinator.new()
	population.coordinator.name = "WorldEncounter"
	world.add_child(population.coordinator)
	for spawn: Dictionary in ContentDB.map.spawns:
		if spawn.scene_id != scene_id or StringName(spawn.archetype) not in EnemyActor.ARCHETYPES:
			continue
		if world.entities.has(StringName(spawn.id)):
			return MireTypes.failure(&"duplicate_entity", &"An actor already owns this world identity.")
		var enemy: EnemyActor = ENEMY_SCENE.instantiate()
		enemy.name = String(spawn.id)
		world.add_child(enemy)
		var configured := enemy.configure(spawn, player, population.coordinator)
		if not configured.ok:
			return configured
		var applied := enemy.apply_persistent_state(candidate.world.get(spawn.id, {}))
		if not applied.ok:
			return applied
		world.entities[enemy.entity_id] = enemy
		population.enemies.append(enemy)
		var purse := WorldObject.new()
		purse.name = String(spawn.id) + "_purse"
		purse.position = _vector(spawn.position) + Vector3(0.65, 0, 0)
		world.add_child(purse)
		configured = purse.configure(enemy.entity_id, &"loot", candidate)
		if not configured.ok:
			return configured
		population.purses[enemy.entity_id] = purse
	return MireTypes.success()

func activate(world: Node3D) -> MireTypes.ActionResult:
	if not is_instance_valid(world):
		return MireTypes.failure(&"unavailable", &"The campaign world is not available.")
	var population := world.get_node_or_null("CampaignPopulation") as Population
	return population.activate() if population != null else MireTypes.failure(&"unavailable", &"The campaign world has not been prepared.")

func _object(world: Node3D, id: StringName, kind: StringName, at: Vector3, candidate: Dictionary, yaw: float = 0) -> MireTypes.ActionResult:
	if world.entities.has(id):
		return MireTypes.failure(&"duplicate_entity", &"A world object already owns this identity.")
	var object := WorldObject.new()
	object.name = String(id)
	object.position = at
	object.rotation.y = yaw
	world.add_child(object)
	var configured := object.configure(id, kind, candidate)
	if configured.ok:
		world.entities[id] = object
	return configured

func _cart(world: Node3D) -> void:
	var cart := StaticBody3D.new()
	cart.name = "RobbedCart"
	cart.position = CART_POSITION
	cart.collision_layer = MireTypes.WORLD
	cart.collision_mask = 0
	cart.add_child(VisualFactory.prop(&"cart"))
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.05, 1.15, 2.3)
	collision.shape = box
	collision.position.y = 0.575
	cart.add_child(collision)
	for side: float in [-1, 1]:
		var shaft := CollisionShape3D.new()
		var shaft_shape := BoxShape3D.new()
		shaft_shape.size = Vector3(0.14, 0.16, 2.1)
		shaft.shape = shaft_shape
		shaft.position = Vector3(side * 0.7, 0.55, -1.6)
		cart.add_child(shaft)
	world.add_child(cart)
	var obstacle := NavigationObstacle3D.new()
	obstacle.name = "CartAvoidance"
	obstacle.position = CART_POSITION + Vector3(0, 0, -0.7)
	obstacle.radius = 2.0
	obstacle.height = 1.5
	obstacle.avoidance_enabled = true
	world.add_child(obstacle)

func _vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])
