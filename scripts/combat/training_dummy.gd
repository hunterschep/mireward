class_name TrainingDummy
extends StaticBody3D
## The village's reusable target has no persistent defeat or loot identity.

const ENTITY_ID: StringName = &"village_training_dummy"
var combat: CombatComponent
var interaction: InteractionComponent
var body: Node3D
var _recoil: float = 0.0
var _active: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	collision_layer = MireTypes.HOSTILE
	collision_mask = 0
	ArtMesh.cylinder(self, "Foot", 0.42, 0.48, 0.12, Vector3(0, 0.06, 0), "timber", 8)
	ArtMesh.cylinder(self, "Post", 0.08, 0.10, 1.45, Vector3(0, 0.77, 0), "wood", 8)
	body = ArtMesh.pivot(self, "StrawBody", Vector3(0, 0.85, 0))
	ArtMesh.box(body, "StuffedCoat", Vector3(0.65, 0.75, 0.42), Vector3(0, 0.22, 0), "linen")
	ArtMesh.sphere(body, "StrawHead", 0.23, Vector3(0, 0.83, 0), "ochre")
	ArtMesh.box(body, "Belt", Vector3(0.68, 0.07, 0.45), Vector3(0, 0.05, 0), "timber")
	ArtMesh.box(body, "Arms", Vector3(1.05, 0.14, 0.15), Vector3(0, 0.46, 0), "wood")
	for side: float in [-1.0, 1.0]:
		ArtMesh.box(body, "PaintedEye", Vector3(0.04, 0.04, 0.02), Vector3(side * 0.08, 0.88, -0.22), "ink")
	ArtMesh.batch(body)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.7
	var collider := CollisionShape3D.new()
	collider.position.y = 0.85
	collider.shape = capsule
	add_child(collider)
	combat = CombatComponent.new()
	add_child(combat)
	var target_data: Dictionary = ContentDB.get_enemy(&"cutpurse").data.duplicate(true)
	target_data.max_health = 1000
	target_data.armor = 0.0
	combat.configure_enemy(self, ENTITY_ID, MireTypes.EnemyDef.new(target_data))
	combat.hit_received.connect(_hit_received)
	var hurtbox := CombatHurtbox.new()
	hurtbox.name = "Hurtbox"
	hurtbox.position.y = 0.85
	hurtbox.configure(combat, 0.32, 1.7)
	add_child(hurtbox)
	interaction = InteractionComponent.new()
	interaction.entity_id = ENTITY_ID
	interaction.action_id = &"training"
	interaction.prompt = "Training instructions"
	interaction.focus_offset = Vector3(0, 1.3, 0)
	interaction.physical_body = self
	interaction.action_handler = _read_board
	var focus := CollisionShape3D.new()
	focus.position.y = 0.85
	focus.shape = capsule
	interaction.add_child(focus)
	add_child(interaction)
	deactivate()

func activate() -> MireTypes.ActionResult:
	_active = true
	interaction.enabled = true
	get_node("Hurtbox").collision_layer = MireTypes.HURTBOX
	return MireTypes.success()

func deactivate() -> void:
	_active = false
	if is_instance_valid(interaction):
		interaction.enabled = false
	if has_node("Hurtbox"):
		get_node("Hurtbox").collision_layer = 0

func _read_board(actor_id: StringName, action_id: StringName) -> MireTypes.ActionResult:
	if not _active or actor_id != &"player" or action_id != &"training":
		return MireTypes.failure(&"unavailable", &"The training board is not available.")
	return MireTypes.success({"ui_action": "training", "step": "intro"})

func _hit_received(request: MireTypes.DamageRequest, result: MireTypes.DamageResult) -> void:
	combat.health = combat.max_health
	if result.health_damage <= 0:
		return
	_recoil = 0.35
	EventBus.feedback.emit("Heavy strike. Let the weapon recover before attacking again." if request.attack_kind == &"heavy" else "Light strike. A raised shield protects the direction you face.")

func _physics_process(delta: float) -> void:
	_recoil = maxf(0.0, _recoil - delta)
	body.rotation.x = sin(_recoil * 18.0) * _recoil * 0.6

func _exit_tree() -> void:
	deactivate()
