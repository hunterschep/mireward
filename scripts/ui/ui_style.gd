class_name UIStyle
extends RefCounted

const INK := Color("17251f")
const PANEL := Color("24372e")
const PAPER := Color("e6dfc5")
const MUTED := Color("b4bea9")
const GOLD := Color("d7b86d")
static var _action_sequence: int = 0

static func theme_for(scale: float) -> Theme:
	var theme := Theme.new()
	theme.default_font = ThemeDB.fallback_font
	theme.default_font_size = roundi(18 * scale)
	for type: StringName in [&"Label", &"Button", &"CheckButton", &"OptionButton", &"LineEdit", &"SpinBox"]:
		theme.set_color(&"font_color", type, PAPER)
		theme.set_color(&"font_focus_color", type, Color.WHITE)
		theme.set_color(&"font_hover_color", type, Color.WHITE)
		theme.set_color(&"font_disabled_color", type, Color("889486"))
	for type: StringName in [&"Button", &"OptionButton"]:
		theme.set_stylebox(&"normal", type, box(PANEL, Color("52654e")))
		theme.set_stylebox(&"hover", type, box(Color("354b3b"), GOLD))
		theme.set_stylebox(&"pressed", type, box(INK, GOLD))
		theme.set_stylebox(&"disabled", type, box(Color("1c2c24"), Color("374b3b")))
		theme.set_stylebox(&"focus", type, box(Color.TRANSPARENT, GOLD, 3))
	theme.set_stylebox(&"panel", &"PanelContainer", box(INK, Color("647252")))
	theme.set_stylebox(&"background", &"ProgressBar", box(Color("101b16"), Color("52654e")))
	theme.set_stylebox(&"fill", &"ProgressBar", box(Color("758654"), Color.TRANSPARENT, 0))
	theme.set_color(&"font_color", &"ProgressBar", PAPER)
	theme.set_constant(&"separation", &"VBoxContainer", roundi(10 * scale))
	theme.set_constant(&"separation", &"HBoxContainer", roundi(10 * scale))
	return theme

static func box(color: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(3)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

static func label(text: String, muted: bool = false) -> Label:
	var control := Label.new()
	control.text = text
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if muted:
		control.modulate = MUTED
	return control

static func button(text: String, action: Callable, id: String = "") -> Button:
	var control := Button.new()
	control.text = text
	control.alignment = HORIZONTAL_ALIGNMENT_LEFT
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.custom_minimum_size.y = 44
	control.set_meta("ui_id", id)
	control.pressed.connect(action)
	return control

static func scroll_content(parent: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	return column

static func clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

static func focus_id(parent: Control) -> String:
	var focused := parent.get_viewport().gui_get_focus_owner()
	return String(focused.get_meta("ui_id", "")) if focused != null and parent.is_ancestor_of(focused) else ""

static func restore_focus(parent: Control, id: String) -> void:
	if id.is_empty() or not parent.is_visible_in_tree():
		return
	for child: Node in parent.find_children("*", "Control", true, false):
		if child.get_meta("ui_id", "") == id and child is Control:
			UIStyle.focus_visible.call_deferred(child)
			return

static func action_id(prefix: String) -> StringName:
	while true:
		_action_sequence += 1
		var id := StringName("ui/" + prefix + "/" + str(_action_sequence))
		if not GameSession.state.transactions.has(String(id)):
			return id
	return &""

static func focus_visible(control: Variant) -> void:
	# A queued focus target may have been freed by a refreshed panel.
	if is_instance_valid(control) and control is Control and control.is_inside_tree() and control.is_visible_in_tree():
		control.grab_focus()

static func outline(label: Label) -> void:
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", 4)
