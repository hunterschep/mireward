class_name ModalHost
extends Control

signal back_requested

const TITLES := {"pause": "Paused", "inventory": "Inventory", "journal": "Journal", "map": "Greyfen Vale", "dialogue": "Conversation", "shop": "Trade", "settings": "Settings", "death": "You have fallen", "epilogue": "The Last Toll", "confirmation": "Confirm", "readable": "Read", "travel": "Travelling", "save": "Save game", "load": "Load game", "title": "MIREWARD"}

var panels: Dictionary = {}
var first_focus: Dictionary = {}
var _remembered_focus: Dictionary = {}
var _mode: StringName = &"gameplay"
var _heading: Label
var _content: VBoxContainer
var _back: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.035, 0.045, 0.04, 0.86)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = 0.17
	panel.anchor_right = 0.83
	panel.anchor_top = 0.12
	panel.anchor_bottom = 0.88
	add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	_heading = Label.new()
	_heading.add_theme_font_size_override("font_size", 28)
	column.add_child(_heading)
	_content = VBoxContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_content)
	_back = Button.new()
	_back.text = "Back"
	_back.custom_minimum_size.y = 44
	_back.pressed.connect(func() -> void: back_requested.emit())
	column.add_child(_back)
	visible = false

func register_panel(panel_mode: StringName, panel: Control, initial_focus: Control = null) -> MireTypes.ActionResult:
	if not is_node_ready() or panel_mode not in MireTypes.MODES or panel == null:
		return MireTypes.failure(&"invalid_mode", &"That screen is not available.")
	if panels.has(panel_mode) and panels[panel_mode] != panel:
		return MireTypes.failure(&"duplicate_panel", &"That screen already has a panel.")
	if panel.get_parent() == null:
		_content.add_child(panel)
	elif panel.get_parent() != _content:
		panel.reparent(_content)
	panels[panel_mode] = panel
	first_focus[panel_mode] = weakref(initial_focus) if initial_focus != null else null
	panel.visible = panel_mode == _mode
	return MireTypes.success()

func unregister_panel(panel_mode: StringName) -> void:
	if panels.has(panel_mode) and is_instance_valid(panels[panel_mode]):
		panels[panel_mode].queue_free()
	panels.erase(panel_mode)
	first_focus.erase(panel_mode)
	_remembered_focus.erase(panel_mode)

func show_mode(current_mode: StringName, mode_stack: Array[StringName]) -> void:
	if not is_node_ready():
		return
	var previous_focus: Control = get_viewport().gui_get_focus_owner()
	if previous_focus != null and is_ancestor_of(previous_focus):
		_remembered_focus[_mode] = weakref(previous_focus)
	_mode = current_mode
	visible = current_mode != &"gameplay"
	_heading.text = String(TITLES.get(String(current_mode), "MIREWARD"))
	for registered: StringName in panels:
		if is_instance_valid(panels[registered]):
			panels[registered].visible = visible and registered == current_mode
	_back.visible = mode_stack.size() > 1 and current_mode not in [&"death", &"travel"]
	_back.text = "Resume" if current_mode == &"pause" else "Back"
	if not visible:
		if previous_focus != null:
			previous_focus.release_focus()
		return
	var desired: Control = _focus_for(current_mode)
	if desired != null:
		desired.grab_focus.call_deferred()

func _focus_for(panel_mode: StringName) -> Control:
	for remembered: Dictionary in [_remembered_focus, first_focus]:
		if remembered.get(panel_mode) is WeakRef:
			var candidate: Variant = remembered[panel_mode].get_ref()
			if candidate is Control and candidate.is_visible_in_tree() and candidate.focus_mode != Control.FOCUS_NONE:
				return candidate
	return _back if _back.visible else null
