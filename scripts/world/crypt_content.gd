class_name CryptContent
extends RefCounted
## Crypt objects derive their saved state from QuestService's single puzzle flag.

const PUZZLE_ID: StringName = &"crypt_bell_puzzle"
const GATE_ID: StringName = &"crypt_vault_gate"
const CHIMES := [
	{"id": &"crypt_reed_chime", "symbol": &"reed", "x": 4.4, "z": 2.0},
	{"id": &"crypt_stone_chime", "symbol": &"stone", "x": 4.4, "z": 0.0},
	{"id": &"crypt_flame_chime", "symbol": &"flame", "x": 4.4, "z": -2.0},
]
const PUZZLE_POSITION := Vector3(0, 0, -32)
const CLUE_POSITION := Vector3(-4.4, 0, -32)
const CHARTER_POSITION := Vector3(0, 0, -40)

class Puzzle extends Node3D:
	var gate: StaticBody3D
	var gate_visual: Node3D
	var status: Label3D
	var interactions: Dictionary = {}
	var markers: Array[MeshInstance3D] = []
	var labels: Array[Label3D] = []
	var _active: bool = false
	var _configured: bool = false
	var _solved: bool = false

	func configure(world: Node3D, solved: bool) -> MireTypes.ActionResult:
		if _configured or not is_inside_tree() or get_parent() != world:
			return MireTypes.failure(&"invalid_runtime", &"Add one crypt puzzle to its world before configuring it.")
		_configured = true
		position = PUZZLE_POSITION
		gate = StaticBody3D.new()
		gate.name = "VaultGate"
		gate.position = Vector3(0, 0, -3)
		gate.collision_mask = 0
		add_child(gate)
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(4.08, 3.1, 0.4)
		collider.shape = shape
		collider.position.y = 1.55
		gate.add_child(collider)
		gate_visual = Node3D.new()
		gate_visual.name = "IronVaultGrille"
		gate.add_child(gate_visual)
		for index: int in range(-7, 8):
			ArtMesh.box(gate_visual, "Bar", Vector3(0.065, 3.05, 0.085), Vector3(index * 0.27, 1.525, 0), "dark_iron")
		for height: float in [0.25, 1.55, 2.85]:
			ArtMesh.box(gate_visual, "Crossbar", Vector3(4.0, 0.12, 0.10), Vector3(0, height, 0), "iron")
		world.entities[GATE_ID] = gate
		status = _label("PuzzleStatus", Vector3(0, 2.35, -2.65), 30)
		status.text = "The charter vault is closed."
		for index: int in CHIMES.size():
			var row: Dictionary = CHIMES[index]
			var body := StaticBody3D.new()
			body.name = String(row.id)
			body.position = Vector3(float(row.x), 0, float(row.z))
			body.rotation.y = PI / 2
			body.collision_layer = MireTypes.WORLD
			body.collision_mask = 0
			add_child(body)
			var art := VisualFactory.prop(StringName(String(row.symbol) + "_chime"))
			art.scale.y = 0.68
			body.add_child(art)
			var collision := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(0.84, 1.3, 0.64)
			collision.shape = box
			collision.position.y = 0.65
			body.add_child(collision)
			var obstacle := NavigationObstacle3D.new()
			obstacle.radius = 0.55
			obstacle.height = 1.35
			obstacle.avoidance_enabled = true
			body.add_child(obstacle)
			var interaction := InteractionComponent.new()
			interaction.entity_id = row.id
			interaction.action_id = &"ring"
			interaction.kind = "puzzle"
			interaction.enabled = false
			interaction.physical_body = body
			interaction.focus_offset = Vector3(0, 0.9, -0.34)
			interaction.offer_handler = _offer.bind(row.symbol)
			interaction.action_handler = _ring.bind(row.symbol)
			var focus := CollisionShape3D.new()
			var target := BoxShape3D.new()
			target.size = Vector3(0.9, 1.35, 0.7)
			focus.shape = target
			focus.position.y = 0.675
			interaction.add_child(focus)
			body.add_child(interaction)
			interactions[row.symbol] = interaction
			world.entities[row.id] = interaction
			labels.append(_label(String(row.symbol) + "Label", Vector3(float(row.x), 1.6, float(row.z)), 32))
			markers.append(ArtMesh.sphere(self, String(row.symbol) + "Marker", 0.09, Vector3(float(row.x) - 0.05, 1.42, float(row.z)), "flame"))
		_present(solved, 0)
		return MireTypes.success()

	func activate() -> MireTypes.ActionResult:
		if not _configured or not is_inside_tree():
			return MireTypes.failure(&"unavailable", &"The crypt puzzle has not been prepared.")
		if not _active:
			EventBus.evidence_acquired.connect(_evidence_changed)
			EventBus.session_restored.connect(refresh)
			_active = true
		for interaction: InteractionComponent in interactions.values():
			interaction.enabled = true
		refresh()
		return MireTypes.success()

	func deactivate() -> void:
		_active = false
		for interaction: InteractionComponent in interactions.values():
			interaction.enabled = false
		if EventBus.evidence_acquired.is_connected(_evidence_changed):
			EventBus.evidence_acquired.disconnect(_evidence_changed)
		if EventBus.session_restored.is_connected(refresh):
			EventBus.session_restored.disconnect(refresh)

	func refresh() -> void:
		if _active:
			_present(bool(GameSession.state.flags.puzzle_solved), GameSession.quests.puzzle_progress)

	func _present(solved: bool, progress: int) -> void:
		_solved = solved
		gate.collision_layer = 0 if solved else MireTypes.WORLD
		gate_visual.position.y = 3.15 if solved else 0.0
		status.text = "The charter vault is open." if solved else "Chimes set: %d / 3. Read the inscription." % progress
		for index: int in CHIMES.size():
			var lit: bool = solved or index < progress
			markers[index].visible = lit
			labels[index].text = String(CHIMES[index].symbol).capitalize() + (" · Set" if lit else "")

	func _offer(actor_id: StringName, symbol: StringName) -> MireTypes.InteractionOffer:
		var allowed: bool = _active and actor_id == &"player" and GameSession.active and not GameSession.travelling and not _solved
		return MireTypes.InteractionOffer.new(interactions[symbol].entity_id, "Ring " + String(symbol) + " chime", allowed, "The vault is already open." if _solved else "" if allowed else "The chime is not active.", &"ring")

	func _ring(actor_id: StringName, action_id: StringName, symbol: StringName) -> MireTypes.ActionResult:
		if action_id != &"ring" or not _offer(actor_id, symbol).allowed:
			return MireTypes.failure(&"unavailable", &"This chime cannot be rung now.")
		var result := GameSession.quests.ring_chime(symbol)
		if not result.ok:
			return result
		refresh()
		if result.payload.get("reset", false):
			status.text = "Wrong order. Begin again with reed."
			EventBus.feedback.emit("The chimes fall quiet. Start again: reed, stone, flame.")
			AudioService.play_event(&"bell_low", global_position)
		elif result.payload.get("solved", false):
			EventBus.feedback.emit("Reed, stone, flame. The charter vault is open.")
			AudioService.play_event(&"bell_solved", global_position)
		else:
			EventBus.feedback.emit("%s chime set. %d of 3." % [String(symbol).capitalize(), int(result.payload.progress)])
			AudioService.play_event(&"bell_chime", global_position)
		return result

	func _label(label_name: String, at: Vector3, font_size: int) -> Label3D:
		var label := Label3D.new()
		label.name = label_name
		label.position = at
		label.font_size = font_size
		label.pixel_size = 0.006
		label.outline_size = 8
		label.modulate = Color(ArtMesh.PALETTE.parchment)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.visibility_range_end = 18
		add_child(label)
		return label

	func _evidence_changed(id: StringName) -> void:
		if id == &"puzzle/crypt_bell_puzzle":
			refresh()

	func _exit_tree() -> void:
		deactivate()

func build(world: Node3D, candidate: Dictionary) -> MireTypes.ActionResult:
	if not is_instance_valid(world) or not world.is_inside_tree() or world.get("scene_id") != &"interior_crypt" or not world.get("entities") is Dictionary or not candidate.get("flags") is Dictionary or not candidate.flags.get("puzzle_solved") is bool or not candidate.get("world") is Dictionary:
		return MireTypes.failure(&"invalid_runtime", &"Crypt construction needs its prepared scene and detached snapshot.")
	var ids: Array[StringName] = [PUZZLE_ID, GATE_ID, &"abbey_inscription", &"charter_vault_coffer"]
	for row: Dictionary in CHIMES:
		ids.append(row.id)
	for id: StringName in ids:
		if world.entities.has(id):
			return MireTypes.failure(&"duplicate_entity", &"The crypt content already owns this identity.")
	var puzzle := Puzzle.new()
	puzzle.name = "CryptPuzzle"
	world.add_child(puzzle)
	var configured := puzzle.configure(world, bool(candidate.flags.puzzle_solved))
	if not configured.ok:
		return configured
	world.entities[PUZZLE_ID] = puzzle
	for row: Dictionary in [{"id": &"abbey_inscription", "kind": &"readable", "position": CLUE_POSITION, "yaw": PI}, {"id": &"charter_vault_coffer", "kind": &"loot", "position": CHARTER_POSITION, "yaw": PI}]:
		var object := WorldObject.new()
		object.name = String(row.id)
		object.position = row.position
		object.rotation.y = float(row.yaw)
		world.add_child(object)
		configured = object.configure(row.id, row.kind, candidate)
		if not configured.ok:
			return configured
		world.entities[row.id] = object
	return MireTypes.success()

func activate(world: Node3D) -> MireTypes.ActionResult:
	if not is_instance_valid(world) or world.get("scene_id") != &"interior_crypt" or not world.get("entities") is Dictionary:
		return MireTypes.failure(&"unavailable", &"The active crypt is not available.")
	var puzzle: Variant = world.entities.get(PUZZLE_ID)
	return puzzle.activate() if puzzle is Puzzle else MireTypes.failure(&"unavailable", &"The crypt puzzle has not been built.")
