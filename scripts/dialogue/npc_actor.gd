class_name NpcActor
extends StaticBody3D
## Stationary civilian presentation. DialogueService owns every conversation effect.

const NPC_IDS: Array[StringName] = [&"mara_venn", &"oswin_pike", &"tamsin_reed", &"sister_elian", &"hobb_fenwick", &"ada_vey", &"wren_kest"]

@export var npc_id: StringName
@export var entity_id: StringName
@export var activate_on_ready: bool = true

var model: Node3D
var interaction: InteractionComponent
var name_label: Label3D
var quest_marker: Label3D
var _session: Node
var _bound_npc_id: StringName
var _bound_entity_id: StringName
var _clock: float = 0.0
var _active: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	collision_layer = 0
	collision_mask = MireTypes.PLAYER
	var shape := CapsuleShape3D.new()
	shape.height = 1.8
	shape.radius = 0.32
	var collider := CollisionShape3D.new()
	collider.name = "BodyShape"
	collider.position.y = 0.9
	collider.shape = shape
	add_child(collider)
	interaction = InteractionComponent.new()
	interaction.name = "Interaction"
	interaction.kind = "npc"
	interaction.action_id = &"talk"
	interaction.enabled = false
	interaction.focus_offset = Vector3(0, 1.5, -0.18)
	interaction.physical_body = self
	interaction.offer_handler = _offer
	interaction.action_handler = _interact
	var focus_shape := CollisionShape3D.new()
	focus_shape.position.y = 0.9
	focus_shape.shape = shape
	interaction.add_child(focus_shape)
	add_child(interaction)
	name_label = _label("SpeakerName", 1.98, 28)
	quest_marker = _label("QuestMarker", 2.25, 42)
	quest_marker.modulate = Color(ArtMesh.PALETTE.warm)
	set_process(false)
	if not npc_id.is_empty():
		configure(GameSession, npc_id, activate_on_ready)

func configure(owner_session: Node, speaker_id: StringName, live: bool = true) -> MireTypes.ActionResult:
	if not is_node_ready():
		return MireTypes.failure(&"not_ready", &"Add the character to the world before configuring it.")
	if speaker_id not in NPC_IDS:
		return MireTypes.failure(&"unsupported", &"This actor supports noncombat speakers only.")
	if not _bound_npc_id.is_empty():
		if speaker_id != _bound_npc_id or owner_session != _session or npc_id != _bound_npc_id or entity_id != _bound_entity_id:
			return MireTypes.failure(&"invalid_identity", &"A placed character cannot change identity.")
		if live:
			return activate()
		deactivate()
		refresh_view()
		return MireTypes.success()
	if not is_instance_valid(owner_session):
		return MireTypes.failure(&"unavailable", &"The conversation is not available.")
	_session = owner_session
	npc_id = speaker_id
	if entity_id.is_empty():
		entity_id = speaker_id
	_bound_npc_id = npc_id
	_bound_entity_id = entity_id
	interaction.entity_id = entity_id
	model = VisualFactory.actor(npc_id)
	model.name = "Model"
	add_child(model)
	collision_layer = MireTypes.NEUTRAL
	VisualFactory.pose(model, &"idle")
	refresh_view()
	if live:
		return activate()
	return MireTypes.success()

func activate() -> MireTypes.ActionResult:
	if not is_inside_tree() or not is_node_ready() or _bound_npc_id.is_empty() or not is_instance_valid(_session):
		return MireTypes.failure(&"not_ready", &"Configure the character in the world before activating it.")
	if npc_id != _bound_npc_id or entity_id != _bound_entity_id:
		return MireTypes.failure(&"invalid_identity", &"A placed character cannot change identity.")
	if not _active:
		EventBus.quest_updated.connect(_quest_changed)
		EventBus.choice_committed.connect(_choice_changed)
		EventBus.session_restored.connect(refresh_view)
		_active = true
	interaction.enabled = true
	set_process(true)
	refresh_view()
	return MireTypes.success()

func deactivate() -> void:
	_active = false
	set_process(false)
	if is_instance_valid(interaction):
		interaction.enabled = false
	if EventBus.quest_updated.is_connected(_quest_changed):
		EventBus.quest_updated.disconnect(_quest_changed)
	if EventBus.choice_committed.is_connected(_choice_changed):
		EventBus.choice_committed.disconnect(_choice_changed)
	if EventBus.session_restored.is_connected(refresh_view):
		EventBus.session_restored.disconnect(refresh_view)

func _exit_tree() -> void:
	deactivate()

func refresh_view() -> void:
	if not is_instance_valid(name_label):
		return
	var view: Dictionary = _view()
	name_label.text = String(view.get("speaker_name", ""))
	name_label.visible = not name_label.text.is_empty()
	var marker: String = String(view.get("marker", "none"))
	quest_marker.text = "?" if marker == "turn_in" else "!"
	quest_marker.visible = marker in ["turn_in", "quest"]
	interaction.prompt = "Talk to " + name_label.text if name_label.visible else "Talk"

func _process(delta: float) -> void:
	if not _active:
		return
	_clock += delta
	VisualFactory.pose(model, &"idle", _clock)

func _offer(actor_id: StringName) -> MireTypes.InteractionOffer:
	if _active:
		refresh_view()
	var allowed: bool = _active and actor_id == &"player" and npc_id == _bound_npc_id and entity_id == _bound_entity_id and not _view().is_empty()
	return MireTypes.InteractionOffer.new(interaction.entity_id, interaction.prompt, allowed, "" if allowed else "The conversation is not available.", &"talk")

func _interact(actor_id: StringName, action_id: StringName) -> MireTypes.ActionResult:
	if action_id != &"talk" or not _offer(actor_id).allowed:
		return MireTypes.failure(&"unavailable", &"The conversation is not available.")
	var service: Object = _dialogue()
	var result: Variant = service.call("start", _bound_npc_id)
	if not result is MireTypes.ActionResult:
		return MireTypes.failure(&"unsupported", &"The conversation could not be opened.")
	return result

func _dialogue() -> Object:
	if not is_instance_valid(_session):
		return null
	var service: Variant = _session.get("dialogue")
	if not service is Object or not is_instance_valid(service) or not service.has_method("npc_view") or not service.has_method("start"):
		return null
	return service

func _view() -> Dictionary:
	var service: Object = _dialogue()
	if service == null or _bound_npc_id.is_empty():
		return {}
	var view: Variant = service.call("npc_view", _bound_npc_id)
	if not view is Dictionary or view.get("npc_id", "") != String(_bound_npc_id) or not view.get("speaker_name") is String or String(view.speaker_name).is_empty():
		return {}
	return view

func _label(label_name: String, height: float, size: int) -> Label3D:
	var label := Label3D.new()
	label.name = label_name
	label.position.y = height
	label.font_size = size
	label.pixel_size = 0.006
	label.outline_size = 8
	label.modulate = Color(ArtMesh.PALETTE.parchment)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visibility_range_end = 24.0
	label.visible = false
	add_child(label)
	return label

func _quest_changed(_quest_id: StringName) -> void:
	refresh_view()

func _choice_changed(_choice_id: StringName, _value: StringName) -> void:
	refresh_view()
