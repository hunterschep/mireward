class_name FirstPersonGear
extends Node3D

var weapon_mount: Node3D
var shield_mount: Node3D
var weapon: Node3D
var shield: Node3D
var hands: Node3D
var current_ids: Dictionary = {}

func _ready() -> void:
	weapon_mount = Node3D.new()
	weapon_mount.name = "WeaponMount"
	weapon_mount.position = Vector3(0.42, -0.45, -0.87)
	weapon_mount.rotation = Vector3(-0.15, -0.12, -0.17)
	add_child(weapon_mount)
	shield_mount = Node3D.new()
	shield_mount.name = "ShieldMount"
	shield_mount.position = Vector3(-0.42, -0.42, -0.85)
	shield_mount.rotation.y = 0.3
	add_child(shield_mount)
	EventBus.equipment_changed.connect(refresh)
	EventBus.session_restored.connect(refresh)
	refresh()

func refresh() -> void:
	if not is_node_ready():
		return
	var ids: Dictionary = {}
	for slot: String in ["weapon", "shield", "armor"]:
		ids[slot] = ""
		for stack: Dictionary in GameSession.state.inventory:
			if stack.stack_id == GameSession.state.equipment.get(slot, ""):
				ids[slot] = stack.item_id
	if ids == current_ids:
		return
	current_ids = ids
	for child: Node in weapon_mount.get_children():
		child.free()
	for child: Node in shield_mount.get_children():
		child.free()
	weapon = VisualFactory.gear(StringName(ids.weapon))
	weapon_mount.add_child(weapon)
	shield = null
	if not str(ids.shield).is_empty():
		shield = VisualFactory.gear(StringName(ids.shield))
		shield_mount.add_child(shield)
	if is_instance_valid(hands):
		hands.free()
	hands = Node3D.new()
	hands.name = "ArmoredHands"
	add_child(hands)
	var sleeve := "linen" if ids.armor == "patched_coat" else ("wood" if ids.armor == "leather_jack" else "dark_iron")
	for side: float in [-1.0, 1.0]:
		var arm := ArtMesh.pivot(hands, "LeftHand" if side < 0 else "RightHand", Vector3(side * 0.4, -0.49, -0.77))
		arm.rotation.x = -0.8
		ArtMesh.box(arm, "Sleeve", Vector3(0.15, 0.33, 0.15), Vector3(0, -0.15, 0.04), sleeve)
		ArtMesh.box(arm, "Glove", Vector3(0.13, 0.16, 0.12), Vector3.ZERO, "wood")
		if ids.armor == "mail_coat":
			ArtMesh.box(arm, "KnucklePlate", Vector3(0.14, 0.06, 0.04), Vector3(0, 0.025, -0.07), "iron")
	_disable_view_shadows(self)

func _disable_view_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child: Node in node.get_children():
		_disable_view_shadows(child)

func pose(state: StringName, phase: float = 0.0) -> void:
	if is_instance_valid(weapon):
		VisualFactory.pose_gear(weapon, state, phase)
	if is_instance_valid(shield):
		VisualFactory.pose_gear(shield, &"guard" if state == &"guard" else &"idle", phase)
	shield_mount.position = Vector3(-0.25, -0.17, -0.65) if state == &"guard" else Vector3(-0.42, -0.42, -0.85)
