class_name InteractionComponent
extends Area3D

const PROMPTS := {"readable": "Read", "container": "Open", "door": "Enter", "npc": "Talk", "rest": "Rest", "puzzle": "Activate", "ending": "Review writ"}

@export var entity_id: StringName
@export var action_id: StringName = &"interact"
@export_enum("readable", "container", "door", "npc", "rest", "puzzle", "ending") var kind: String = "readable"
@export var prompt: String = ""
@export var enabled: bool = true
@export var focus_offset: Vector3 = Vector3.ZERO
@export var physical_body: CollisionObject3D
var offer_handler: Callable
var action_handler: Callable

func _ready() -> void:
	collision_layer = MireTypes.INTERACTABLE
	collision_mask = 0
	monitoring = false
	if physical_body == null and get_parent() is CollisionObject3D:
		physical_body = get_parent()

func focus_position() -> Vector3:
	return to_global(focus_offset)

func get_offer(actor_id: StringName) -> MireTypes.InteractionOffer:
	var label: String = prompt if not prompt.is_empty() else String(PROMPTS.get(kind, "Interact"))
	if not enabled or entity_id.is_empty() or is_queued_for_deletion():
		return MireTypes.InteractionOffer.new(entity_id, label, false, "This action is no longer available.", action_id)
	if not action_handler.is_valid() or action_handler.get_argument_count() != 2:
		return MireTypes.InteractionOffer.new(entity_id, label, false, "This action is not available.", action_id)
	if offer_handler.is_valid():
		if offer_handler.get_argument_count() != 1:
			return MireTypes.InteractionOffer.new(entity_id, label, false, "This action is not available.", action_id)
		var offered: Variant = offer_handler.call(actor_id)
		if not offered is MireTypes.InteractionOffer or offered.entity_id != entity_id or offered.action_id.is_empty():
			return MireTypes.InteractionOffer.new(entity_id, label, false, "This action is not available.", action_id)
		return MireTypes.InteractionOffer.new(offered.entity_id, offered.prompt_key, offered.allowed, offered.reason_key, offered.action_id)
	return MireTypes.InteractionOffer.new(entity_id, label, true, "", action_id)

func interact(actor_id: StringName, requested_action: StringName) -> MireTypes.ActionResult:
	if not action_handler.is_valid() or action_handler.get_argument_count() != 2:
		return MireTypes.failure(&"unsupported", &"This action is not available.")
	var current: MireTypes.InteractionOffer = get_offer(actor_id)
	if current.action_id != requested_action:
		return MireTypes.failure(&"stale_offer", &"This action changed. Look at the object again.")
	if not current.allowed:
		return MireTypes.failure(&"unavailable", StringName(current.reason_key))
	var result: Variant = action_handler.call(actor_id, requested_action)
	if not result is MireTypes.ActionResult:
		return MireTypes.failure(&"unsupported", &"This action could not be completed.")
	return result

func visibility_exclusions() -> Array[RID]:
	var exclusions: Array[RID] = [get_rid()]
	if is_instance_valid(physical_body):
		exclusions.append(physical_body.get_rid())
	return exclusions
