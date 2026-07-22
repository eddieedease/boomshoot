## The one full-screen menu, reused for pause, death and level complete.
##
## Runs with PROCESS_MODE_ALWAYS so it stays responsive while the tree is
## paused, and grabs focus on the first button so a gamepad can drive it
## without ever touching the mouse.
class_name OverlayMenu
extends CanvasLayer

signal action_selected(id: StringName)

var _dim: ColorRect
var _title: Label
var _subtitle: Label
var _buttons: VBoxContainer


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	hide_menu()


func _build() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.02, 0.02, 0.04, 0.82)
	add_child(_dim)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	add_child(column)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 84)
	_title.add_theme_color_override("font_color", Color(1.0, 0.72, 0.28))
	column.add_child(_title)

	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", 26)
	_subtitle.add_theme_color_override("font_color", Color(0.72, 0.72, 0.78))
	column.add_child(_subtitle)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 32)
	column.add_child(gap)

	_buttons = VBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 10)
	column.add_child(_buttons)


## `options` is an array of {id: StringName, text: String}.
func show_menu(title: String, subtitle: String, options: Array) -> void:
	_title.text = title
	_subtitle.text = subtitle
	_subtitle.visible = subtitle != ""

	for child in _buttons.get_children():
		child.queue_free()

	var first: Button = null
	for option: Dictionary in options:
		var button := Button.new()
		button.text = option["text"]
		button.custom_minimum_size = Vector2(420, 62)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.add_theme_font_size_override("font_size", 28)
		button.focus_mode = Control.FOCUS_ALL
		var id: StringName = option["id"]
		button.pressed.connect(func() -> void: action_selected.emit(id))
		_buttons.add_child(button)
		if first == null:
			first = button

	visible = true
	if first != null:
		first.grab_focus.call_deferred()


func hide_menu() -> void:
	visible = false
