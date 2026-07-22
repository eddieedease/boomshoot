## One-shot project configuration.
##
## Run with:
##   godot --headless --path . --script res://tools/setup_project.gd
##
## Writing the input map through ProjectSettings (rather than hand-editing
## project.godot) lets Godot serialise the events itself, so the bindings stay
## editable in Project Settings > Input Map like any hand-made action.
extends SceneTree


func _initialize() -> void:
	_display()
	_rendering()
	_physics_layers()
	_autoloads()
	_plugins()
	_input_map()
	var err := ProjectSettings.save()
	if err != OK:
		push_error("could not save project.godot (%d)" % err)
	else:
		print("[setup_project] project.godot updated")
	quit()


func _display() -> void:
	ProjectSettings.set_setting("application/run/main_scene", "res://src/main.tscn")
	ProjectSettings.set_setting("application/config/name", "BOOMSHOOT")
	# 3 == Window.MODE_FULLSCREEN (borderless desktop fullscreen).
	ProjectSettings.set_setting("display/window/size/mode", 3)
	ProjectSettings.set_setting("display/window/size/viewport_width", 1920)
	ProjectSettings.set_setting("display/window/size/viewport_height", 1080)
	ProjectSettings.set_setting("display/window/stretch/mode", "canvas_items")
	ProjectSettings.set_setting("display/window/stretch/aspect", "expand")
	# The player script captures the mouse; this hides it for the frames before.
	ProjectSettings.set_setting("display/mouse_cursor/tooltip_position_offset", 0)


func _rendering() -> void:
	# Nearest filtering keeps the generated pixel art crisp in the HUD.
	ProjectSettings.set_setting("rendering/textures/canvas_textures/default_texture_filter", 0)
	ProjectSettings.set_setting("rendering/anti_aliasing/quality/msaa_3d", 0)
	ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 1)


func _physics_layers() -> void:
	var layers := {
		1: "world",
		2: "player",
		3: "enemy",
		4: "pickup",
		5: "trigger",
		6: "hitscan_blocker",
	}
	for i: int in layers:
		ProjectSettings.set_setting("layer_names/3d_physics/layer_%d" % i, layers[i])


func _autoloads() -> void:
	ProjectSettings.set_setting("autoload/Game", "*res://src/core/game.gd")


func _plugins() -> void:
	ProjectSettings.set_setting("editor_plugins/enabled",
			PackedStringArray(["res://addons/boomshoot_kit/plugin.cfg"]))


# ------------------------------------------------------------- input map ---

## InputMap only fires an action when the stored event's device matches the
## incoming one, and freshly constructed events do NOT default to a wildcard.
## Every binding is therefore pinned to -1 ("all devices") so keyboards and any
## connected gamepad both work.
const ALL_DEVICES := -1


func _key(kc: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = kc
	e.device = ALL_DEVICES
	return e


func _mb(b: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = b
	e.device = ALL_DEVICES
	return e


func _jb(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.device = ALL_DEVICES
	return e


func _ja(a: JoyAxis, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = a
	e.axis_value = v
	e.device = ALL_DEVICES
	return e


func _input_map() -> void:
	var actions := {
		# Movement — WASD/arrows plus the left stick.
		"move_forward": [_key(KEY_W), _key(KEY_UP), _ja(JOY_AXIS_LEFT_Y, -1.0)],
		"move_back": [_key(KEY_S), _key(KEY_DOWN), _ja(JOY_AXIS_LEFT_Y, 1.0)],
		"move_left": [_key(KEY_A), _ja(JOY_AXIS_LEFT_X, -1.0)],
		"move_right": [_key(KEY_D), _ja(JOY_AXIS_LEFT_X, 1.0)],
		# Right stick look. Mouse look is read from the raw motion event instead.
		"look_left": [_ja(JOY_AXIS_RIGHT_X, -1.0)],
		"look_right": [_ja(JOY_AXIS_RIGHT_X, 1.0)],
		"look_up": [_ja(JOY_AXIS_RIGHT_Y, -1.0)],
		"look_down": [_ja(JOY_AXIS_RIGHT_Y, 1.0)],

		"fire": [_mb(MOUSE_BUTTON_LEFT), _ja(JOY_AXIS_TRIGGER_RIGHT, 1.0)],
		"alt_fire": [_mb(MOUSE_BUTTON_RIGHT), _ja(JOY_AXIS_TRIGGER_LEFT, 1.0)],
		"reload": [_key(KEY_R), _jb(JOY_BUTTON_Y)],
		"jump": [_key(KEY_SPACE), _jb(JOY_BUTTON_A)],
		"crouch": [_key(KEY_CTRL), _key(KEY_C), _jb(JOY_BUTTON_B)],
		"sprint": [_key(KEY_SHIFT), _jb(JOY_BUTTON_LEFT_STICK)],
		"interact": [_key(KEY_E), _jb(JOY_BUTTON_X)],
		"weapon_next": [_mb(MOUSE_BUTTON_WHEEL_UP), _jb(JOY_BUTTON_RIGHT_SHOULDER)],
		"weapon_prev": [_mb(MOUSE_BUTTON_WHEEL_DOWN), _jb(JOY_BUTTON_LEFT_SHOULDER)],
		"pause": [_key(KEY_ESCAPE), _jb(JOY_BUTTON_START)],
	}
	for name: String in actions:
		ProjectSettings.set_setting("input/" + name, {
			"deadzone": 0.2,
			"events": actions[name],
		})
