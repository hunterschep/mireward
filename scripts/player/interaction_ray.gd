class_name InteractionRay
extends Node

signal focus_changed(offer: MireTypes.InteractionOffer)
signal interaction_completed(result: MireTypes.ActionResult)

const REACH: float = 2.5

var actor_id: StringName = &"player"
var player: MirePlayer
var mode_controller: GameModeController
var focused: InteractionComponent
var offer: MireTypes.InteractionOffer
var _interact_held: bool = false

func configure(controlled_player: MirePlayer, controller: GameModeController) -> void:
	if is_instance_valid(mode_controller) and mode_controller.mode_changed.is_connected(_on_mode_changed):
		mode_controller.mode_changed.disconnect(_on_mode_changed)
	player = controlled_player
	mode_controller = controller
	mode_controller.mode_changed.connect(_on_mode_changed)
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _physics_process(_delta: float) -> void:
	if not _can_interact():
		clear_focus()
		return
	refresh_focus()
	var held: bool = Input.is_action_pressed(&"interact")
	if held and not _interact_held and player.controls.pressed(&"interact"):
		interact_focused()
	_interact_held = held

func refresh_focus() -> void:
	if not _can_interact():
		clear_focus()
		return
	var target: InteractionComponent = _find_target()
	var next_offer: MireTypes.InteractionOffer = target.get_offer(actor_id) if target != null else null
	var changed: bool = target != focused or not _same_offer(offer, next_offer)
	focused = target
	offer = next_offer
	if changed:
		focus_changed.emit(offer)

func interact_focused() -> MireTypes.ActionResult:
	if not _can_interact():
		return _report(MireTypes.failure(&"unavailable", &"Return to the game before interacting."))
	var expected: InteractionComponent = focused if is_instance_valid(focused) else null
	var expected_action: StringName = offer.action_id if offer != null else &""
	refresh_focus()
	if focused == null:
		return _report(MireTypes.failure(&"no_target", &"Move closer and look at an object."))
	if expected != focused or offer.action_id != expected_action:
		return _report(MireTypes.failure(&"stale_offer", &"The target changed. Look at the object again."))
	var result: MireTypes.ActionResult = focused.interact(actor_id, expected_action)
	refresh_focus()
	return _report(result)

func clear_focus() -> void:
	if focused != null or offer != null:
		focused = null
		offer = null
		focus_changed.emit(null)

func _find_target() -> InteractionComponent:
	var origin: Vector3 = player.camera.global_position
	var forward: Vector3 = -player.camera.global_basis.z
	var end: Vector3 = origin + forward * REACH
	var query := PhysicsRayQueryParameters3D.create(origin, end, MireTypes.INTERACTABLE, [player.get_rid()])
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.hit_from_inside = true
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var closest: InteractionComponent
	var distance: float = INF
	for _index: int in 32:
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			break
		var collider: Variant = hit.collider
		var excluded: Array[RID] = query.exclude
		excluded.append(hit.rid)
		query.exclude = excluded
		if not collider is InteractionComponent or not collider.enabled or collider.entity_id.is_empty():
			continue
		var target: InteractionComponent = collider
		var anchor: Vector3 = target.focus_position()
		var target_distance: float = origin.distance_to(anchor)
		if target_distance > REACH or target_distance >= distance or forward.dot(anchor - origin) <= 0.0:
			continue
		var exceptions: Array[RID] = target.visibility_exclusions()
		exceptions.append(player.get_rid())
		var sight := PhysicsRayQueryParameters3D.create(origin, end, MireTypes.WORLD, exceptions)
		var barrier: Dictionary = space.intersect_ray(sight)
		if not barrier.is_empty() and origin.distance_to(barrier.position) + 0.01 < forward.dot(anchor - origin):
			continue
		sight.to = anchor
		if not space.intersect_ray(sight).is_empty():
			continue
		closest = target
		distance = target_distance
	return closest

func _can_interact() -> bool:
	return is_inside_tree() and is_instance_valid(player) and is_instance_valid(mode_controller) and mode_controller.mode == &"gameplay" and player.input_enabled and not get_tree().paused

func _on_mode_changed(_mode: StringName) -> void:
	clear_focus()
	_interact_held = Input.is_action_pressed(&"interact")

func _same_offer(first: MireTypes.InteractionOffer, second: MireTypes.InteractionOffer) -> bool:
	if first == null or second == null:
		return first == second
	return first.entity_id == second.entity_id and first.action_id == second.action_id and first.prompt_key == second.prompt_key and first.allowed == second.allowed and first.reason_key == second.reason_key

func _report(result: MireTypes.ActionResult) -> MireTypes.ActionResult:
	interaction_completed.emit(result)
	return result

func _exit_tree() -> void:
	if is_instance_valid(mode_controller) and mode_controller.mode_changed.is_connected(_on_mode_changed):
		mode_controller.mode_changed.disconnect(_on_mode_changed)
