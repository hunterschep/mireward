class_name SideQuestReactions
extends Node3D
## Scene presentation only. Quest transactions own the two durable flags.

const LIGHTS_QUEST := &"sq_04_three_small_lights"
const BADGE_QUEST := &"sq_05_the_broken_badge"
const SHELTER_OFFSET := Vector3(4.5, 0, -2.5)
var shelter_lights: Node3D
var badge: Node3D
var memorial: StaticBody3D
var candles: Array[Node3D] = []
var _configured: bool = false
var _active: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## Call after CampaignWorld has placed Ada, before the prepared world is committed.
func configure(world: Node3D, candidate: Dictionary) -> MireTypes.ActionResult:
	var flags: Variant = candidate.get("flags")
	if _configured or not is_inside_tree() or get_parent() != world or not is_instance_valid(world) or world.get("scene_id") != &"exterior" or not world.get("entities") is Dictionary or not flags is Dictionary or not flags.get("shelter_lights") is bool or not flags.get("restored_badge") is bool:
		return MireTypes.failure(&"invalid_runtime", &"Prepare the exterior and both side-quest flags before adding their reactions once.")
	var ada: Variant = world.entities.get(&"ada_vey")
	if not ada is NpcActor or ada.npc_id != &"ada_vey" or not is_instance_valid(ada.model) or not world.get("rest_anchors") is Dictionary or not world.rest_anchors.has(&"monastery_shelter"):
		return MireTypes.failure(&"missing_station", &"Ada and the monastery shelter must exist before their reactions.")
	if ada.model.has_node("RestoredBadge"):
		return MireTypes.failure(&"duplicate_reaction", &"Ada already has a restored-badge attachment.")
	badge = VisualFactory.gear(&"ada_badge")
	badge.name = "RestoredBadge"
	badge.position = Vector3(0.12, 1.19, -0.205)
	badge.scale = Vector3.ONE * 0.75
	ada.model.add_child(badge)
	memorial = StaticBody3D.new()
	memorial.name = "ShelterMemorial"
	memorial.position = world.rest_anchors[&"monastery_shelter"].origin + SHELTER_OFFSET
	memorial.collision_layer = MireTypes.WORLD
	memorial.collision_mask = 0
	add_child(memorial)
	memorial.add_child(VisualFactory.prop(&"bench"))
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.5, 0.505, 0.45)
	collision.shape = shape
	collision.position.y = 0.2525
	memorial.add_child(collision)
	shelter_lights = Node3D.new()
	shelter_lights.name = "ThreeSmallLights"
	memorial.add_child(shelter_lights)
	for index: int in 3:
		var candle := VisualFactory.gear(&"votive_candle")
		candle.name = "ShelterCandle" + str(index + 1)
		candle.position = Vector3((index - 1) * 0.45, 0.505, 0)
		candle.scale = Vector3.ONE * 1.4
		shelter_lights.add_child(candle)
		candles.append(candle)
	_configured = true
	_present(flags)
	return MireTypes.success()

func activate() -> MireTypes.ActionResult:
	if not _configured or not is_inside_tree() or not is_instance_valid(badge):
		return MireTypes.failure(&"not_ready", &"Prepare the side-quest reactions before activation.")
	if not _active:
		EventBus.quest_updated.connect(_quest_changed)
		EventBus.session_restored.connect(refresh)
		_active = true
	refresh()
	return MireTypes.success()

func deactivate() -> void:
	_active = false
	if EventBus.quest_updated.is_connected(_quest_changed):
		EventBus.quest_updated.disconnect(_quest_changed)
	if EventBus.session_restored.is_connected(refresh):
		EventBus.session_restored.disconnect(refresh)

func refresh() -> void:
	if _active:
		_present(GameSession.state.flags)

func _quest_changed(quest_id: StringName) -> void:
	if quest_id in [LIGHTS_QUEST, BADGE_QUEST]:
		refresh()

func _present(flags: Dictionary) -> void:
	shelter_lights.visible = flags.shelter_lights
	badge.visible = flags.restored_badge

func _exit_tree() -> void:
	deactivate()

func _notification(what: int) -> void:
	# The badge follows Ada's articulated model, but this helper owns its lifetime.
	if what == NOTIFICATION_PREDELETE and is_instance_valid(badge):
		badge.free()
