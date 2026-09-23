class_name UndercroftContent
extends RefCounted
## The arena owns its runtime gate; shared services own victory and fixed loot.

const GATE_ID: StringName = &"captain_arena_gate"
const GATE_Z: float = -33.0
var player: MirePlayer

class Arena extends Node3D:
	var boss: CaptainRusk
	var population: CampaignWorld.Population
	var gate: StaticBody3D
	var grille: Node3D
	var _live: bool = false

	func configure() -> void:
		gate = StaticBody3D.new()
		gate.name = "CaptainHallGate"
		gate.position = Vector3(0, 0, GATE_Z)
		gate.collision_layer = 0
		gate.collision_mask = 0
		add_child(gate)
		var shape := BoxShape3D.new()
		shape.size = Vector3(5.08, 3.1, 0.4)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position.y = 1.55
		gate.add_child(collision)
		grille = Node3D.new()
		grille.name = "RaisedPortcullis"
		gate.add_child(grille)
		for index: int in range(-8, 9):
			ArtMesh.box(grille, "IronBar", Vector3(0.08, 3.05, 0.1), Vector3(index * 0.29, 1.525, 0), "dark_iron")
		for height: float in [0.25, 1.55, 2.85]:
			ArtMesh.box(grille, "Crossbar", Vector3(5, 0.13, 0.12), Vector3(0, height, 0), "iron")
		_duel_changed(false)

	func activate() -> MireTypes.ActionResult:
		if not is_inside_tree() or not is_instance_valid(boss) or not is_instance_valid(population):
			return MireTypes.failure(&"unavailable", &"The captain's arena has not been prepared.")
		if not _live:
			boss.duel_changed.connect(_duel_changed)
			_live = true
		_duel_changed(boss.is_duel_active())
		return boss.activate()

	func check_challenge() -> MireTypes.ActionResult:
		if not _live or not is_instance_valid(boss.player) or boss.player.global_position.z >= GATE_Z - 1 or boss.global_position.z >= GATE_Z - 1:
			return MireTypes.failure(&"outside_arena", &"Enter the captain's hall before issuing the challenge.")
		for actor: EnemyActor in population.enemies:
			if actor != boss and actor.is_alive_hostile() and actor.global_position.z < GATE_Z + 0.85:
				return MireTypes.failure(&"arena_unsafe", &"Clear pursuing retainers from the hall and gate before challenging Rusk.")
		return MireTypes.success()

	func _duel_changed(active: bool) -> void:
		gate.collision_layer = MireTypes.WORLD if active else 0
		grille.position.y = 0 if active else 3.15

	func _exit_tree() -> void:
		if is_instance_valid(boss) and boss.duel_changed.is_connected(_duel_changed):
			boss.duel_changed.disconnect(_duel_changed)
		_live = false

func _init(controlled_player: MirePlayer) -> void:
	player = controlled_player

func build(world: Node3D, candidate: Dictionary) -> MireTypes.ActionResult:
	if not is_instance_valid(player) or not is_instance_valid(world) or not world.is_inside_tree() or world.get("scene_id") != &"interior_undercroft" or not world.get("entities") is Dictionary or not candidate.get("world") is Dictionary:
		return MireTypes.failure(&"invalid_runtime", &"The undercroft needs its prepared world, player and snapshot.")
	var population := world.get_node_or_null("CampaignPopulation") as CampaignWorld.Population
	if population == null or not is_instance_valid(population.coordinator):
		return MireTypes.failure(&"invalid_runtime", &"Populate the undercroft's ordinary retainers before its captain.")
	for id: StringName in [GATE_ID, CaptainRusk.ENTITY_ID, &"captain_seal_chest", &"captains_order"]:
		if world.entities.has(id):
			return MireTypes.failure(&"duplicate_entity", &"This undercroft identity is already installed.")
	var arena := Arena.new()
	arena.name = "CaptainArena"
	arena.population = population
	world.add_child(arena)
	arena.configure()
	world.entities[GATE_ID] = arena.gate
	var spawn: Dictionary = {}
	for row: Dictionary in ContentDB.map.spawns:
		if row.id == String(CaptainRusk.ENTITY_ID):
			spawn = row
	if spawn.is_empty():
		return MireTypes.failure(&"unknown_entity", &"The captain's authored spawn is missing.")
	var boss := CaptainRusk.new()
	boss.name = "CaptainRusk"
	world.add_child(boss)
	var configured := boss.configure(spawn, player, population.coordinator)
	if not configured.ok:
		return configured
	configured = boss.apply_persistent_state(candidate.world.get(String(CaptainRusk.ENTITY_ID), {}))
	if not configured.ok:
		return configured
	world.entities[CaptainRusk.ENTITY_ID] = boss
	population.enemies.append(boss)
	var purse := WorldObject.new()
	purse.name = "CaptainPurse"
	purse.position = Vector3(spawn.position[0] + 0.65, spawn.position[1], spawn.position[2])
	world.add_child(purse)
	configured = purse.configure(CaptainRusk.ENTITY_ID, &"loot", candidate)
	if not configured.ok:
		return configured
	population.purses[CaptainRusk.ENTITY_ID] = purse
	arena.boss = boss
	boss.challenge_check = arena.check_challenge
	for row: Dictionary in [{"id": &"captain_seal_chest", "kind": &"loot", "position": Vector3(3, 0, -50)}, {"id": &"captains_order", "kind": &"readable", "position": Vector3(-5, 0, -43)}]:
		var object := WorldObject.new()
		object.name = String(row.id)
		object.position = row.position
		object.rotation.y = PI
		world.add_child(object)
		configured = object.configure(row.id, row.kind, candidate)
		if not configured.ok:
			return configured
		world.entities[row.id] = object
	return MireTypes.success()

func activate(world: Node3D) -> MireTypes.ActionResult:
	if not is_instance_valid(world) or world.get("scene_id") != &"interior_undercroft":
		return MireTypes.failure(&"unavailable", &"The undercroft is not active.")
	var arena := world.get_node_or_null("CaptainArena") as Arena
	return arena.activate() if arena != null else MireTypes.failure(&"unavailable", &"The captain's arena is missing.")
