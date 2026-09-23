class_name ExteriorContent
extends Node3D
## Authored exterior readables and neutral residents. No persistent scenery IDs.

const READABLES := [
	{"id": "toll_notice", "position": Vector3(-20, 0, 28), "yaw": PI / 2},
	{"id": "ferry_ledger", "position": Vector3(-195, 0, 222), "yaw": PI},
	{"id": "broken_bell_plaque", "position": Vector3(198, 0, -101), "yaw": PI / 2},
	{"id": "village_writ_table", "position": Vector3(-122, 0, 141), "yaw": PI},
]
const RESIDENTS := [
	{"name": "CampResidentWest", "role": "Camp resident", "art": &"hobb_fenwick", "position": Vector3(-236, 0, -70), "yaw": -PI / 2},
	{"name": "CampResidentEast", "role": "Camp resident", "art": &"tamsin_reed", "position": Vector3(-221, 0, -70), "yaw": PI / 2},
	{"name": "CourtyardWardenWest", "role": "Courtyard warden", "art": &"ada_vey", "position": Vector3(32, 0, -225), "yaw": PI},
	{"name": "CourtyardWardenEast", "role": "Courtyard warden", "art": &"ada_vey", "position": Vector3(49, 0, -234), "yaw": PI},
]
var readables: Dictionary = {}
var residents: Array[StaticBody3D] = []
var _configured: bool = false
var _active: bool = false
var _clock: float = 0.0
var _models: Array[Node3D] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(false)

func configure(world: Node3D, candidate: Dictionary) -> MireTypes.ActionResult:
	if _configured or not is_inside_tree() or not is_instance_valid(world) or get_parent() != world or world.get("scene_id") != &"exterior" or not world.get("entities") is Dictionary or not candidate.get("world") is Dictionary:
		return MireTypes.failure(&"invalid_runtime", &"Add one exterior content helper to the prepared exterior before configuring it.")
	for row: Dictionary in READABLES:
		if world.entities.has(StringName(row.id)):
			return MireTypes.failure(&"duplicate_entity", &"This readable already has a physical source.")
	for row: Dictionary in READABLES:
		var object := WorldObject.new()
		object.name = String(row.id)
		object.position = row.position
		object.rotation.y = float(row.yaw)
		add_child(object)
		var configured := object.configure(StringName(row.id), &"readable", candidate)
		if not configured.ok:
			return configured
		world.entities[object.entity_id] = object
		readables[object.entity_id] = object
	for row: Dictionary in RESIDENTS:
		_resident(row)
	_sign("KilnCampSign", "Briar Camp", Vector3(-187, 0, 32), PI)
	_sign("EastPathAbbeySign", "Saint Orra", Vector3(148, 0, -8), 0)
	var supplies := Node3D.new()
	supplies.name = "CampSupplies"
	supplies.position = Vector3(-240, 0, -67)
	add_child(supplies)
	var crate := VisualFactory.prop(&"crate")
	crate.name = "RepairedCrate"
	supplies.add_child(crate)
	for at: Vector3 in [Vector3(-0.7, 0, 0.25), Vector3(0.7, 0, -0.25)]:
		var sack := VisualFactory.prop(&"sack")
		sack.position = at
		supplies.add_child(sack)
	_configured = true
	return MireTypes.success()

func activate() -> MireTypes.ActionResult:
	if not _configured or not is_inside_tree():
		return MireTypes.failure(&"unavailable", &"The exterior content has not been prepared.")
	_active = true
	set_process(true)
	return MireTypes.success()

func deactivate() -> void:
	_active = false
	set_process(false)

func _process(delta: float) -> void:
	if not _active:
		return
	_clock += delta
	for index: int in _models.size():
		VisualFactory.pose(_models[index], &"idle", _clock + index * 0.7)

func _exit_tree() -> void:
	deactivate()

func _resident(row: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.name = String(row.name)
	body.position = row.position
	body.rotation.y = float(row.yaw)
	body.collision_layer = MireTypes.NEUTRAL
	body.collision_mask = MireTypes.PLAYER
	body.set_meta("neutral_role", String(row.role))
	add_child(body)
	residents.append(body)
	var model := VisualFactory.actor(row.art)
	model.name = "Model"
	body.add_child(model)
	VisualFactory.pose(model, &"idle")
	_models.append(model)
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.32
	collision.position.y = 0.9
	collision.shape = capsule
	body.add_child(collision)
	var label := Label3D.new()
	label.name = "RoleLabel"
	label.text = row.role
	label.position.y = 2.0
	label.font_size = 26
	label.pixel_size = 0.006
	label.outline_size = 8
	label.modulate = Color(ArtMesh.PALETTE.parchment)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visibility_range_end = 18.0
	body.add_child(label)

func _sign(local_name: String, text: String, at: Vector3, yaw: float) -> void:
	var sign := VisualFactory.prop(&"sign")
	sign.name = local_name
	sign.position = at
	sign.rotation.y = yaw
	add_child(sign)
	ArtMesh.box(sign, "LetteringBoard", Vector3(1.15, 0.29, 0.02), Vector3(-0.03, 1.43, -0.06), "wood")
	var label := Label3D.new()
	label.name = "Destination"
	label.text = text
	label.position = Vector3(-0.03, 1.43, -0.075)
	label.font_size = 48
	label.pixel_size = 0.0035
	label.outline_size = 2
	label.modulate = Color(ArtMesh.PALETTE.parchment)
	sign.add_child(label)
