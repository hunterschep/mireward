class_name WorldInteractions
extends Node
## Installs live adapters only after a prepared world becomes the active world.

var router: WorldRouter
var world: Node3D
var _sequence: int = 0
var _initial_discovery: bool = true
var _undercroft_bar: Node3D

func configure(owner_router: WorldRouter, active_world: Node3D) -> void:
	router = owner_router
	world = active_world
	for row: Dictionary in world.get("portal_definitions"):
		var component := _component(StringName(row.id), &"door", _vector(row.position), _vector(row.size))
		if world is MireExterior:
			_portal_art(row, component)
		component.prompt = "Return to Greyfen" if row.target_scene == "exterior" else "Enter " + {"interior_inn": "the inn", "interior_crypt": "the crypt", "interior_undercroft": "the undercroft"}[row.target_scene]
		component.offer_handler = func(_actor_id: StringName) -> MireTypes.InteractionOffer:
			var locked: bool = row.target_scene == "interior_undercroft" and not GameSession.state.flags.undercroft_open
			return MireTypes.InteractionOffer.new(component.entity_id, component.prompt, not locked, "The undercroft is barred. Show Ada the charter and grain ledger first." if locked else "", component.action_id)
		component.action_handler = func(_actor_id: StringName, _action_id: StringName) -> MireTypes.ActionResult:
			return router.travel(StringName(row.target_scene), StringName(row.target_entrance))
	for id: StringName in world.get("rest_anchors"):
		var at: Transform3D = world.get("rest_anchors")[id]
		var component := _component(id, &"rest", at.origin + Vector3(0, 0, -0.8), Vector3(0.7, 1.3, 0.7))
		var support := StaticBody3D.new()
		support.name = String(id) + "_lantern_support"
		support.position = at.origin + Vector3(0, 0, -0.8)
		support.collision_layer = MireTypes.WORLD
		support.collision_mask = 0
		var size := Vector3(0.4, 0.5, 0.4)
		ArtMesh.box(support, "Support", size, Vector3.UP * 0.25, "wood")
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		collision.position.y = 0.25
		support.add_child(collision)
		world.add_child(support)
		component.physical_body = support
		var lamp := VisualFactory.prop(&"lantern")
		lamp.position = at.origin + Vector3(0, 0.5, -0.8)
		world.add_child(lamp)
		component.prompt = "Rest at the inn (4 crowns)" if id == &"inn_bed" and not GameSession.state.flags.free_inn else "Rest"
		component.offer_handler = func(_actor_id: StringName) -> MireTypes.InteractionOffer:
			var offered: MireTypes.ActionResult = GameSession.recovery.rest_offer(id)
			var prompt := "Rest at the inn (4 crowns)" if id == &"inn_bed" and not GameSession.state.flags.free_inn else "Rest"
			return MireTypes.InteractionOffer.new(id, prompt, offered.ok, String(offered.message_key), component.action_id)
		component.action_handler = func(_actor_id: StringName, _action_id: StringName) -> MireTypes.ActionResult:
			_sequence += 1
			return GameSession.recovery.rest(id, StringName("world/rest/%s/%d/%d" % [id, Time.get_ticks_usec(), _sequence]))
	if world is MireExterior:
		for id: StringName in world.landmark_areas:
			var area: Area3D = world.landmark_areas[id]
			area.body_entered.connect(_discover.bind(id))
			for body: Node3D in area.get_overlapping_bodies():
				_discover(body, id)

func _physics_process(_delta: float) -> void:
	if is_instance_valid(_undercroft_bar):
		_undercroft_bar.visible = not GameSession.state.flags.undercroft_open
	if not _initial_discovery or GameSession.travelling or not is_instance_valid(world):
		return
	_initial_discovery = false
	if world is MireExterior:
		for id: StringName in world.landmark_areas:
			for body: Node3D in world.landmark_areas[id].get_overlapping_bodies():
				_discover(body, id)

func _portal_art(row: Dictionary, component: InteractionComponent) -> void:
	var at := _vector(row.position)
	var visual := VisualFactory.prop(&"door")
	visual.position = at
	visual.scale.x = float(row.size[0]) / 1.25
	world.add_child(visual)
	var body := StaticBody3D.new()
	body.position = at + Vector3.UP * 1.25
	body.collision_layer = MireTypes.WORLD
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(float(row.size[0]), 2.5, 0.2)
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body)
	component.physical_body = body
	component.focus_offset.z = float(row.size[2]) * 0.45
	if row.target_scene == "interior_undercroft":
		_undercroft_bar = Node3D.new()
		_undercroft_bar.position = at
		world.add_child(_undercroft_bar)
		ArtMesh.box(_undercroft_bar, "IronBar", Vector3(2.3, 0.15, 0.18), Vector3(0, 1.2, 0.17), "dark_iron")
		_undercroft_bar.visible = not GameSession.state.flags.undercroft_open

func _component(id: StringName, kind: StringName, at: Vector3, size: Vector3) -> InteractionComponent:
	var component := InteractionComponent.new()
	component.entity_id = id
	component.action_id = kind
	component.kind = String(kind)
	component.position = at + Vector3.UP * size.y / 2
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	component.add_child(collision)
	world.add_child(component)
	world.get("entities")[id] = component
	return component

func _discover(body: Node3D, landmark_id: StringName) -> void:
	if body != router.player or router.current_world != world or GameSession.travelling or landmark_id in GameSession.state.discoveries:
		return
	GameSession.transactions.run(StringName("discovery/" + String(landmark_id)), func(candidate: Dictionary) -> MireTypes.ActionResult:
		if String(landmark_id) not in candidate.discoveries:
			candidate.discoveries.append(String(landmark_id))
			return MireTypes.success({"landmark_id": String(landmark_id)}).event(&"landmark_discovered", [landmark_id])
		return MireTypes.success({"landmark_id": String(landmark_id)})
	)

func _vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])
