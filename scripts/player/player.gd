class_name MirePlayer
extends CharacterBody3D

const WALK_SPEED: float = 4.0
const SPRINT_SPEED: float = 6.0
const GUARD_SPEED: float = 2.2
const ACCELERATION: float = 18.0
const GRAVITY: float = 16.0
const JUMP_VELOCITY: float = 4.5

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var gear: FirstPersonGear = $Head/Camera3D/Gear
var controls := PlayerInput.new()
var vitals := PlayerVitals.new()
var input_enabled: bool = true
var guarding: bool = false
var sprinting: bool = false
var bob_clock: float = 0.0
var step_distance: float = 0.0
var combat: Node

func _ready() -> void:
	add_to_group("player")
	apply_settings()

func apply_settings() -> void:
	if not is_node_ready():
		return
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = clampf(float(SaveService.settings.fov), 60.0, 95.0)

func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if not enabled:
		clear_input_edges()

func clear_input_edges() -> void:
	controls.clear_edges()
	if is_instance_valid(combat) and combat.has_method("clear_input_edges"):
		combat.clear_input_edges()

func spawn_at(at: Vector3, yaw: float = 0.0) -> void:
	global_position = at + Vector3.UP * 0.06
	rotation.y = yaw
	head.rotation.x = 0.0
	velocity = Vector3.ZERO
	guarding = false
	sprinting = false
	vitals.reset()
	clear_input_edges()

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or get_tree().paused or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		apply_look(event.relative)

func apply_look(relative: Vector2) -> void:
	var sensitivity: float = float(SaveService.settings.mouse_sensitivity)
	rotation.y -= relative.x * sensitivity
	var sign_y: float = -1.0 if SaveService.settings.invert_y else 1.0
	head.rotation.x = clampf(head.rotation.x - relative.y * sensitivity * sign_y, deg_to_rad(-85.0), deg_to_rad(85.0))

func _physics_process(delta: float) -> void:
	controls.tick()
	if not input_enabled or not GameSession.active or GameSession.travelling:
		return
	var axis := controls.movement()
	var direction := global_basis * Vector3(axis.x, 0.0, axis.y)
	direction.y = 0.0
	direction = direction.limit_length()
	sprinting = Input.is_action_pressed(&"sprint") and axis.length_squared() > 0.0 and float(GameSession.state.player.stamina) > 0.0 and not guarding and not GameSession.action_locked
	var speed: float = GUARD_SPEED if guarding else (SPRINT_SPEED if sprinting else WALK_SPEED)
	var acceleration: float = ACCELERATION * (1.0 if is_on_floor() else 0.3)
	velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	if controls.pressed(&"jump") and is_on_floor() and vitals.spend_stamina(10.0):
		velocity.y = JUMP_VELOCITY
	var before: Vector3 = global_position
	move_and_slide()
	var walked: float = Vector2(global_position.x - before.x, global_position.z - before.z).length()
	if sprinting and walked > 0.001:
		vitals.drain_sprint(delta)
	else:
		sprinting = false
	vitals.advance(delta, sprinting or guarding or GameSession.action_locked)
	if is_on_floor() and walked > 0.001:
		bob_clock += walked * 2.8
		step_distance += walked
		if step_distance >= 1.65:
			step_distance = 0.0
			var surface := &"dirt" if GameSession.state.player.scene_id == "exterior" else (&"wood" if GameSession.state.player.scene_id == "interior_inn" else &"stone")
			AudioService.play_event(StringName("footstep_" + String(surface)), global_position)
	var bob: float = float(SaveService.settings.view_bob) * sin(bob_clock) if is_on_floor() and walked > 0.001 else 0.0
	head.position.y = move_toward(head.position.y, 1.65 + bob, delta * 0.4)
	GameSession.state.player.position = [global_position.x, global_position.y, global_position.z]
	GameSession.state.player.yaw = rotation.y
