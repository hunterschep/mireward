class_name WorldObject
extends StaticBody3D
## Fixed world presentation. Services own loot, evidence and all saved mutations.

const CONTAINERS := {
	"cart_coffer": "medicine_chest", "checkpoint_receipt_box": "chest",
	"charter_vault_coffer": "ledger_chest", "watchtower_ledger_chest": "ledger_chest",
	"captain_seal_chest": "seal_chest", "kiln_hammer_crate": "crate",
	"ferry_blanket_barrel": "barrel", "shrine_ring_bowl": "ring",
	"monastery_candle_01": "candle", "monastery_candle_02": "candle", "monastery_candle_03": "candle",
	"watchtower_badge_locker": "badge_locker", "raider_medicine_cache": "medicine_chest",
}
var entity_id: StringName
var interaction: InteractionComponent
var model: Node3D
var label: String = ""
var _bound_id: StringName
var _kind: StringName
var _family: StringName
var _default_record: Dictionary = {}
var _corpse: bool = false
var _active: bool = false
var _depleted: bool = false
var _lid: Node3D
var _contents: Node3D
var _pickup: Node3D

func _ready() -> void:
	collision_layer = 0
	collision_mask = 0

func configure(source_id: StringName, kind: StringName, snapshot: Dictionary) -> MireTypes.ActionResult:
	if not is_node_ready() or not _bound_id.is_empty():
		return MireTypes.failure(&"invalid_setup", &"Add a new world object before configuring it once.")
	if kind not in [&"loot", &"readable"] or not snapshot.get("world") is Dictionary:
		return MireTypes.failure(&"invalid_setup", &"World objects need a loot/readable kind and a detached world snapshot.")
	var id := String(source_id)
	var record: Variant = snapshot.world.get(id, {})
	if not record is Dictionary or not SessionValidation.json_safe(record):
		return MireTypes.failure(&"invalid_state", &"The object has an invalid saved record.")
	_corpse = false
	_family = &""
	_default_record.clear()
	if kind == &"readable":
		if not QuestService.DOCUMENTS.has(id):
			return MireTypes.failure(&"unknown_document", &"That readable is not authored.")
		label = QuestService.DOCUMENTS[id][0]
	elif CONTAINERS.has(id) and ContentDB.containers.has(id):
		var definition: Dictionary = ContentDB.containers[id]
		label = definition.label
		_family = StringName(CONTAINERS[id])
		_default_record = {"kind": "container", "opened": false, "remaining": definition.items.duplicate(true), "crowns_remaining": int(definition.crowns)}
	else:
		for spawn: Dictionary in ContentDB.map.spawns:
			if spawn.id == id:
				_corpse = true
				_family = &"corpse_loot"
				label = "Fallen " + String(spawn.archetype).replace("_", " ") + "'s purse"
				_default_record = {"kind": "corpse", "opened": false, "remaining": {}, "crowns_remaining": int(ContentDB.enemies[StringName(spawn.archetype)].data.loot_crowns), "defeated": false, "disabled": false, "archetype": spawn.archetype}
				break
		if not _corpse:
			return MireTypes.failure(&"unknown_source", &"That fixed loot source is not authored.")
	if kind == &"loot":
		var candidate: Dictionary = _default_record.duplicate(true)
		candidate.merge(record, true)
		var checked := SessionValidation.validate_loot_record(id, candidate, ContentDB)
		if not checked.ok: return checked
	_bound_id = source_id
	entity_id = source_id
	_kind = kind
	var size: Vector3 = _build_art()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	collider.position.y = size.y / 2
	add_child(collider)
	collision_layer = 0 if _corpse or _family == &"candle" else MireTypes.WORLD
	interaction = InteractionComponent.new()
	interaction.name = "Interaction"
	interaction.entity_id = entity_id
	interaction.kind = "container" if kind == &"loot" else "readable"
	interaction.action_id = &"open" if kind == &"loot" else &"read"
	interaction.physical_body = self
	interaction.focus_offset = Vector3(0, size.y * 0.6, -size.z * 0.5 - 0.01)
	interaction.offer_handler = _offer
	interaction.action_handler = _interact
	interaction.enabled = false
	var target := CollisionShape3D.new()
	var target_shape := BoxShape3D.new()
	target_shape.size = Vector3(maxf(size.x, 0.4), maxf(size.y, 0.4), maxf(size.z, 0.3))
	target.shape = target_shape
	target.position.y = target_shape.size.y / 2
	interaction.add_child(target)
	add_child(interaction)
	return apply_persistent_state(record)

func apply_persistent_state(record: Dictionary) -> MireTypes.ActionResult:
	if _bound_id.is_empty() or not is_instance_valid(model):
		return MireTypes.failure(&"not_ready", &"Configure the world object first.")
	if not SessionValidation.json_safe(record):
		return MireTypes.failure(&"invalid_state", &"The object has an invalid saved record.")
	if _kind == &"readable":
		return MireTypes.success()
	var state: Dictionary = _default_record.duplicate(true)
	state.merge(record, true)
	var checked := SessionValidation.validate_loot_record(String(_bound_id), state, ContentDB)
	if not checked.ok:
		return checked
	_depleted = state.remaining.is_empty() and int(state.crowns_remaining) == 0
	var opened: bool = state.opened or _depleted
	if is_instance_valid(_lid):
		_lid.rotation.x = 1.2 if opened else 0.0
	if is_instance_valid(_contents):
		_contents.visible = opened
	if is_instance_valid(_pickup):
		_pickup.visible = not _depleted
	model.visible = bool(state.defeated) and not _depleted if _corpse else not _depleted if _family == &"candle" else true
	interaction.enabled = _active and not (_depleted and (_corpse or _family in [&"candle", &"ring"])) and (not _corpse or bool(state.defeated))
	return MireTypes.success()

func activate() -> MireTypes.ActionResult:
	if not is_inside_tree() or _bound_id.is_empty() or entity_id != _bound_id or not is_instance_valid(interaction):
		return MireTypes.failure(&"invalid_identity", &"A configured world object must retain its identity.")
	if not _active:
		_active = true
		if _kind == &"loot":
			EventBus.inventory_changed.connect(_refresh)
			EventBus.currency_changed.connect(_refresh)
			EventBus.entity_defeated.connect(_defeated)
			EventBus.session_restored.connect(_refresh)
	interaction.enabled = true
	var refreshed := _refresh()
	if not refreshed.ok: deactivate()
	return refreshed

func deactivate() -> void:
	_active = false
	if is_instance_valid(interaction): interaction.enabled = false
	if EventBus.inventory_changed.is_connected(_refresh): EventBus.inventory_changed.disconnect(_refresh)
	if EventBus.currency_changed.is_connected(_refresh): EventBus.currency_changed.disconnect(_refresh)
	if EventBus.entity_defeated.is_connected(_defeated): EventBus.entity_defeated.disconnect(_defeated)
	if EventBus.session_restored.is_connected(_refresh): EventBus.session_restored.disconnect(_refresh)

func _exit_tree() -> void:
	deactivate()

func _refresh() -> MireTypes.ActionResult:
	return apply_persistent_state(GameSession.world_state.get_entity_state(_bound_id)) if _active and _kind == &"loot" else MireTypes.success()

func _defeated(id: StringName) -> void:
	if id == _bound_id: _refresh()

func _access() -> MireTypes.ActionResult:
	if not _active or entity_id != _bound_id or not GameSession.active or GameSession.travelling:
		return MireTypes.failure(&"unavailable", &"This object is not active.")
	if _bound_id == &"charter_vault_coffer" and not GameSession.state.flags.puzzle_solved:
		return MireTypes.failure(&"story_locked", &"Solve the crypt's reed, stone and flame puzzle to open the charter vault.")
	if _bound_id == &"captain_seal_chest" and not GameSession.state.world.get("captain_hall_captain_rusk_01", {}).get("defeated", false):
		return MireTypes.failure(&"story_locked", &"Defeat Captain Rusk before opening his seal chest.")
	if _kind == &"loot":
		return GameSession.world_state.read_loot(_bound_id)
	if _bound_id == &"village_writ_table" and (GameSession.state.quests[QuestPredicates.MQ06].state not in ["ACTIVE", "READY", "COMPLETED"] or not GameSession.state.evidence.get("conversation/" + QuestPredicates.MQ06 + "/discuss_resolution", false)):
		return MireTypes.failure(&"not_ready", &"Speak to Mara about The Last Toll first.")
	return MireTypes.success()

func _offer(actor_id: StringName) -> MireTypes.InteractionOffer:
	var checked: MireTypes.ActionResult = _access() if actor_id == &"player" else MireTypes.failure(&"unavailable", &"Only the player can use this object.")
	var prompt: String = ("Open " if _kind == &"loot" else "Read ") + label
	if _kind == &"loot" and checked.ok and checked.payload.empty: prompt = label + " (empty)"
	return MireTypes.InteractionOffer.new(entity_id, prompt, checked.ok, String(checked.message_key), interaction.action_id)

func _interact(actor_id: StringName, action_id: StringName) -> MireTypes.ActionResult:
	if actor_id != &"player" or action_id != interaction.action_id:
		return MireTypes.failure(&"stale_offer", &"Look at the current object again.")
	var checked := _access()
	if not checked.ok: return checked
	if _kind == &"readable":
		var read: MireTypes.ActionResult = GameSession.quests.read_document(_bound_id)
		if read.ok: read.payload.merge({"ui_action": "writ" if _bound_id == &"village_writ_table" else "readable", "document_id": String(_bound_id)})
		return read
	if not checked.payload.opened:
		var opened: MireTypes.ActionResult = GameSession.world_state.apply_transaction({String(_bound_id): {"opened": true}}, StringName("world/open/" + String(_bound_id)))
		if not opened.ok: return opened
	_refresh()
	return MireTypes.success({"ui_action": "loot", "entity_id": String(_bound_id), "label": label})

func _build_art() -> Vector3:
	if _kind == &"readable": return _readable_art()
	if _family == &"ring":
		model = Node3D.new()
		ArtMesh.cylinder(model, "OfferingPedestal", 0.27, 0.3, 0.58, Vector3(0, 0.29, 0), "stone", 8)
		ArtMesh.cylinder(model, "OfferingBowl", 0.3, 0.23, 0.1, Vector3(0, 0.63, 0), "slate", 10)
		_pickup = VisualFactory.gear(&"hobb_ring")
		_pickup.rotation.x = PI / 2
		_pickup.position.y = 0.69
		model.add_child(_pickup)
	else:
		model = VisualFactory.prop(_family)
		if _family == &"candle": _pickup = model
	add_child(model)
	_lid = model.get_node_or_null("Lid") as Node3D
	var size := Vector3(0.95, 0.7, 0.72)
	if _family == &"badge_locker": size.y = 1.56
	elif _family == &"barrel": size = Vector3(0.6, 0.8, 0.6)
	elif _family == &"crate":
		size = Vector3(0.67, 0.62, 0.6)
		_lid = ArtMesh.pivot(model, "Lid", Vector3(0, 0.59, 0.28))
		ArtMesh.box(_lid, "Cover", Vector3(0.65, 0.04, 0.56), Vector3(0, 0, -0.28), "timber")
	elif _family == &"ring": size = Vector3(0.6, 0.72, 0.6)
	elif _family == &"candle": size = Vector3(0.4, 0.35, 0.35)
	elif _corpse: size = Vector3(0.5, 0.35, 0.4)
	if is_instance_valid(_lid):
		_contents = ArtMesh.box(model, "OpenInterior", Vector3(size.x * 0.74, 0.015, size.z * 0.72), Vector3(0, _lid.position.y + 0.012, 0), "peat")
	return size

func _readable_art() -> Vector3:
	if _bound_id == &"village_writ_table":
		model = VisualFactory.prop(&"writ_table")
		add_child(model)
		return Vector3(1.5, 0.95, 0.85)
	if _bound_id in [&"southern_sign", &"toll_notice"]:
		model = VisualFactory.prop(&"toll_notice" if _bound_id == &"toll_notice" else &"sign")
	else:
		model = Node3D.new()
		var stone: bool = _bound_id in [&"abbey_inscription", &"broken_bell_plaque"]
		ArtMesh.box(model, "ReadingStand", Vector3(0.62, 1.1, 0.22), Vector3(0, 0.55, 0), "stone" if stone else "wood")
		if stone:
			for line: int in 4:
				ArtMesh.box(model, "Inscription", Vector3(0.34 if line % 2 == 0 else 0.42, 0.012, 0.012), Vector3(0, 0.94 - line * 0.08, -0.116), "peat")
		else:
			var paper: Node3D = VisualFactory.gear(&"grain_ledger" if _bound_id in [&"grain_ledger", &"ferry_ledger"] else &"orra_charter")
			paper.position = Vector3(0, 0.72, -0.14)
			model.add_child(paper)
	add_child(model)
	return Vector3(1.3, 1.7, 0.2) if _bound_id in [&"southern_sign", &"toll_notice"] else Vector3(0.65, 1.15, 0.3)
