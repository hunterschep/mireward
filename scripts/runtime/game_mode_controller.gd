class_name GameModeController
extends Node

signal mode_changed(current_mode: StringName)

const SUBORDINATE: Array[StringName] = [&"confirmation", &"readable"]
const PARENT_PANELS: Array[StringName] = [&"settings", &"save", &"load"]
const MENU_SHORTCUT_MODES: Array[StringName] = [&"gameplay", &"pause", &"inventory", &"journal", &"map"]

var mode: StringName = &"gameplay"
var stack: Array[StringName] = [&"gameplay"]
var player: MirePlayer
var modal_host: Control
var _configured: bool = false
var _focus_lost: bool = false
var _recovery_travel_mode: bool = false
var _back_locked: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _configured:
		_apply_mode()

func configure(controlled_player: MirePlayer, host: Control = null) -> void:
	if is_instance_valid(modal_host) and modal_host.has_signal("back_requested") and modal_host.is_connected("back_requested", pop_mode):
		modal_host.disconnect("back_requested", pop_mode)
	player = controlled_player
	modal_host = host
	_configured = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	if is_instance_valid(modal_host):
		modal_host.process_mode = Node.PROCESS_MODE_ALWAYS
		if modal_host.has_signal("back_requested"):
			modal_host.connect("back_requested", pop_mode)
	if is_inside_tree():
		_apply_mode()

func _process(_delta: float) -> void:
	if not _configured:
		return
	var pending: bool = GameSession.recovery.has_pending_recovery()
	if pending and mode == &"gameplay":
		_apply_mode()
	elif not pending and _recovery_travel_mode:
		_recovery_travel_mode = false
		if mode == &"travel":
			stack = [&"gameplay"]
			mode = &"gameplay"
			_apply_mode()

func push_mode(requested: StringName) -> MireTypes.ActionResult:
	if requested not in MireTypes.MODES:
		return MireTypes.failure(&"invalid_mode", &"That screen is not available.")
	if not _configured:
		return MireTypes.failure(&"unavailable", &"The game is not ready for input.")
	if requested == mode:
		if mode == &"gameplay" and GameSession.recovery.has_pending_recovery():
			_apply_mode()
		return MireTypes.success({"mode": String(mode)})
	_back_locked = false
	if requested in [&"gameplay", &"title"]:
		stack = [requested]
	elif requested in SUBORDINATE or (requested in PARENT_PANELS and mode in [&"pause", &"title"]):
		stack.append(requested)
	else:
		stack = [stack[0], requested]
	mode = requested
	_apply_mode()
	return MireTypes.success({"mode": String(mode)})

## Travel rollback preserves subordinate panels and applies input policy once.
func snapshot_stack() -> Array[StringName]:
	return stack.duplicate()

func restore_stack(saved: Array) -> MireTypes.ActionResult:
	if not _configured:
		return MireTypes.failure(&"unavailable", &"The game is not ready for input.")
	var restored: Array[StringName] = []
	for value: Variant in saved:
		if (not value is String and not value is StringName) or StringName(value) not in MireTypes.MODES:
			return MireTypes.failure(&"invalid_mode", &"The saved menu stack contains an unknown screen.")
		var requested := StringName(value)
		if restored.is_empty():
			if requested not in [&"gameplay", &"title"]:
				return MireTypes.failure(&"invalid_mode", &"The saved menu stack has no valid root.")
		elif requested in [&"gameplay", &"title"] or requested == restored.back() or (restored.size() > 1 and requested not in SUBORDINATE and not (requested in PARENT_PANELS and restored.back() in [&"pause", &"title"])):
			return MireTypes.failure(&"invalid_mode", &"The saved menu stack has an invalid parent screen.")
		restored.append(requested)
	if restored.is_empty():
		return MireTypes.failure(&"invalid_mode", &"The saved menu stack is empty.")
	stack = restored
	mode = stack.back()
	_back_locked = false
	_recovery_travel_mode = mode == &"travel" and GameSession.recovery.has_pending_recovery()
	_apply_mode()
	return MireTypes.success({"mode": String(mode)})

func set_back_locked(locked: bool) -> void:
	_back_locked = locked and mode == &"confirmation"

func pop_mode() -> void:
	if _back_locked or stack.size() <= 1 or mode in [&"death", &"travel"]:
		return
	_back_locked = false
	stack.pop_back()
	mode = stack.back()
	_apply_mode()

func handle_focus_loss() -> void:
	if not _configured:
		return
	_focus_lost = true
	if is_instance_valid(player):
		player.clear_input_edges()
	if mode == &"gameplay":
		push_mode(&"pause")
	else:
		_apply_mode()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		handle_focus_loss()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focus_lost = false
		if _configured and mode == &"gameplay":
			_apply_mode()

func _unhandled_input(event: InputEvent) -> void:
	if not _configured or event.is_echo():
		return
	var escape: bool = event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE
	if escape or event.is_action_pressed(&"pause"):
		if mode == &"gameplay":
			push_mode(&"pause")
		else:
			pop_mode()
		get_viewport().set_input_as_handled()
		return
	if mode not in MENU_SHORTCUT_MODES:
		return
	for menu: StringName in [&"inventory", &"journal", &"map"]:
		if event.is_action_pressed(menu):
			if mode == menu:
				pop_mode()
			else:
				push_mode(menu)
			get_viewport().set_input_as_handled()
			return

func _apply_mode() -> void:
	if not is_inside_tree():
		return
	if mode == &"gameplay" and GameSession.recovery.has_pending_recovery():
		_recovery_travel_mode = true
		stack = [&"gameplay", &"travel"]
		mode = &"travel"
	var gameplay: bool = mode == &"gameplay" and not _focus_lost
	if is_instance_valid(player):
		player.clear_input_edges()
		player.set_input_enabled(gameplay)
	get_tree().paused = not gameplay
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if gameplay else Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(modal_host):
		if modal_host.has_method("show_mode"):
			modal_host.call("show_mode", mode, stack.duplicate())
		else:
			modal_host.visible = mode != &"gameplay"
	mode_changed.emit(mode)
	EventBus.mode_changed.emit(mode)

func _exit_tree() -> void:
	if _configured:
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(modal_host) and modal_host.has_signal("back_requested") and modal_host.is_connected("back_requested", pop_mode):
		modal_host.disconnect("back_requested", pop_mode)
