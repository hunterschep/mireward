extends Node

var state: Dictionary = {}
var transactions: Transactions
var inventory: InventoryService
var world_state: WorldStateService
var economy: EconomyService
var recovery: RecoveryService
var quests: QuestService
var danger: bool = false
var action_locked: bool = false
var travelling: bool = false
var active: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 20
	InputBindings.install_defaults()
	transactions = Transactions.new(self)
	new_game()
	inventory = InventoryService.new(self)
	world_state = WorldStateService.new(self)
	economy = EconomyService.new(self)
	recovery = RecoveryService.new(self)
	inventory.consume_handler = recovery.start_consume
	quests = QuestService.new(self)
	EventBus.inventory_changed.connect(quests.reconcile)
	EventBus.evidence_acquired.connect(_reconcile_quest_evidence)
	EventBus.entity_defeated.connect(_reconcile_quest_evidence)
	quests.reconcile()
	active = false

func _physics_process(delta: float) -> void:
	if recovery != null:
		recovery.advance(delta)

func _reconcile_quest_evidence(_id: StringName) -> void:
	quests.reconcile()

func new_game() -> void:
	if recovery != null:
		recovery.reset_runtime()
	state = {
		"player": {"health": 100.0, "stamina": 100.0, "crowns": 12, "scene_id": "exterior", "position": [32.0, 0.0, 252.0], "yaw": 0.0, "rest_anchor": "village_shrine"},
		"inventory": [{"stack_id": "stack_1", "item_id": "rusted_sword", "quantity": 1}, {"stack_id": "stack_2", "item_id": "wooden_buckler", "quantity": 1}, {"stack_id": "stack_3", "item_id": "patched_coat", "quantity": 1}, {"stack_id": "stack_4", "item_id": "bandage", "quantity": 2}, {"stack_id": "stack_5", "item_id": "bread", "quantity": 1}],
		"equipment": {"weapon": "stack_1", "shield": "stack_2", "armor": "stack_3"},
		"key_items": {}, "evidence": {}, "quests": {}, "world": {},
		"choices": {"wren_terms": "unset", "medicine_recipient": "unset", "ending": "none"},
		"discoveries": [], "transactions": {}, "pending_delivery": {},
		"shop_stock": ContentDB.shops.duplicate(true),
		"flags": {"puzzle_solved": false, "free_inn": false, "shelter_lights": false, "restored_badge": false, "undercroft_open": false}, "next_stack": 6
	}
	for id: StringName in ContentDB.quests:
		var initial := "AVAILABLE" if String(id).begins_with("sq_") or String(id).begins_with("mq_01") else "LOCKED"
		state.quests[String(id)] = {"state": initial, "objectives": {}}
	danger = false
	action_locked = false
	travelling = false
	active = true
	if quests != null:
		quests.reset_runtime()
		quests.reconcile()

func snapshot() -> Dictionary:
	return state.duplicate(true)

func restore(candidate: Dictionary) -> MireTypes.ActionResult:
	var valid := validate_snapshot(candidate)
	if not valid.ok:
		return valid
	if recovery != null:
		recovery.reset_runtime()
	state = candidate.duplicate(true)
	danger = false
	action_locked = false
	travelling = false
	active = true
	if quests != null:
		quests.reset_runtime()
	EventBus.session_restored.emit()
	if quests != null:
		quests.reconcile()
	return MireTypes.success()

func validate_snapshot(candidate: Dictionary) -> MireTypes.ActionResult:
	return SessionValidation.validate(candidate, ContentDB)

func can_save() -> bool:
	return active and not danger and not action_locked and not travelling and not transactions.active
