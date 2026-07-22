## In-game HUD: viewmodel, crosshair, vitals and messages.
##
## Built entirely in code and driven by the `Game` signal bus, so it never has
## to reach into the player or the weapon system. Add a stat by subscribing to
## one more signal.
class_name Hud
extends CanvasLayer

const BAR_FONT_SIZE := 34
const MESSAGE_FONT_SIZE := 26
const AMBER := Color(1.0, 0.78, 0.35)
const DIM := Color(0.62, 0.62, 0.66)

## Base placement of the gun sprite, relative to the bottom centre of the screen.
const VIEWMODEL_SIZE := Vector2(512.0, 384.0)

var _viewmodel: TextureRect
var _crosshair: Control
var _health_label: Label
var _armor_label: Label
var _ammo_label: Label
var _weapon_label: Label
var _kills_label: Label
var _keys_box: HBoxContainer
var _message_label: Label
var _interact_label: Label
var _damage_flash: ColorRect

var _weapon: WeaponData = null
var _fire_frames: Array[Texture2D] = []
var _fire_frame_index := -1
var _fire_frame_timer := 0.0
var _bob_phase := 0.0
var _recoil := 0.0
var _message_timer := 0.0
var _prompt_text := ""
## Tracks the last device used so the prompt shows the right button.
var _using_gamepad := false


func _ready() -> void:
	layer = 1
	_build()
	_connect_signals()


func _build() -> void:
	_damage_flash = ColorRect.new()
	_damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_flash.color = Color(0.8, 0.05, 0.05, 0.0)
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_damage_flash)

	_viewmodel = TextureRect.new()
	_viewmodel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_viewmodel.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_viewmodel.size = VIEWMODEL_SIZE
	_viewmodel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_viewmodel)

	_crosshair = Crosshair.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)

	# --- bottom status bar ---
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -76.0
	bar.offset_left = 48.0
	bar.offset_right = -48.0
	bar.offset_bottom = -20.0
	bar.add_theme_constant_override("separation", 48)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	_health_label = _make_stat(bar, "HEALTH", Color(1.0, 0.45, 0.42))
	_armor_label = _make_stat(bar, "ARMOR", Color(0.5, 0.75, 1.0))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	_keys_box = HBoxContainer.new()
	_keys_box.add_theme_constant_override("separation", 8)
	bar.add_child(_keys_box)

	_kills_label = _make_stat(bar, "KILLS", DIM)
	_weapon_label = _make_stat(bar, "WEAPON", DIM)
	_ammo_label = _make_stat(bar, "AMMO", AMBER)

	# --- interact prompt, just under the crosshair ---
	_interact_label = Label.new()
	_interact_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_interact_label.anchor_top = 0.5
	_interact_label.anchor_bottom = 0.5
	_interact_label.offset_top = 54.0
	_interact_label.offset_bottom = 94.0
	_interact_label.offset_left = -400.0
	_interact_label.offset_right = 400.0
	_interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(_interact_label, 24, Color(0.92, 0.94, 1.0))
	_interact_label.visible = false
	_interact_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_interact_label)

	# --- transient message ---
	_message_label = Label.new()
	_message_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_message_label.offset_top = -140.0
	_message_label.offset_bottom = -100.0
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(_message_label, MESSAGE_FONT_SIZE, AMBER)
	_message_label.modulate.a = 0.0
	_message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_message_label)


## One label pair: a small dim caption over a large value.
func _make_stat(parent: Node, caption: String, color: Color) -> Label:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", -4)
	parent.add_child(column)

	var caption_label := Label.new()
	caption_label.text = caption
	_style(caption_label, 16, DIM)
	column.add_child(caption_label)

	var value := Label.new()
	value.text = "0"
	_style(value, BAR_FONT_SIZE, color)
	column.add_child(value)
	return value


func _style(label: Label, size: int, color: Color) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	# Outline keeps text legible over bright floors and muzzle flashes.
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)


func _connect_signals() -> void:
	Game.player_stats_changed.connect(_on_stats_changed)
	Game.ammo_changed.connect(_on_ammo_changed)
	Game.weapon_changed.connect(_on_weapon_changed)
	Game.weapon_fired.connect(_on_weapon_fired)
	Game.player_damaged.connect(_on_player_damaged)
	Game.keys_changed.connect(_on_keys_changed)
	Game.message_posted.connect(_on_message)
	Game.interact_prompt_changed.connect(_on_interact_prompt)
	Game.enemy_died.connect(func(_e: Node3D) -> void: _refresh_kills())
	Game.level_started.connect(_refresh_kills)


# --------------------------------------------------------------- per-frame --

func _process(delta: float) -> void:
	_update_viewmodel(delta)
	_update_message(delta)

	if _damage_flash.color.a > 0.0:
		_damage_flash.color.a = maxf(0.0, _damage_flash.color.a - delta * 1.6)


func _update_viewmodel(delta: float) -> void:
	if _weapon == null:
		return

	# Advance the muzzle-flash frames, then settle back to idle.
	if _fire_frame_index >= 0:
		_fire_frame_timer -= delta
		if _fire_frame_timer <= 0.0:
			_fire_frame_index += 1
			if _fire_frame_index >= _fire_frames.size():
				_fire_frame_index = -1
				_viewmodel.texture = _weapon.sprite_idle
			else:
				_viewmodel.texture = _fire_frames[_fire_frame_index]
				_fire_frame_timer = _weapon.fire_frame_time

	var speed := 0.0
	var player := Game.player
	if player != null and is_instance_valid(player):
		speed = Vector2(player.velocity.x, player.velocity.z).length()
	_bob_phase += delta * (6.0 + speed * 0.9)

	_recoil = move_toward(_recoil, 0.0, delta * 5.0)

	var screen := get_viewport().get_visible_rect().size
	var sway := Vector2(sin(_bob_phase) * 10.0, absf(cos(_bob_phase)) * 8.0) * minf(speed / 8.0, 1.0)
	_viewmodel.position = Vector2(
			(screen.x - VIEWMODEL_SIZE.x) * 0.5 + sway.x,
			screen.y - VIEWMODEL_SIZE.y + 40.0 + sway.y + _recoil * 26.0)


func _update_message(delta: float) -> void:
	if _message_timer <= 0.0:
		return
	_message_timer -= delta
	# Hold at full opacity, then fade over the last half second.
	_message_label.modulate.a = clampf(_message_timer / 0.5, 0.0, 1.0)


# ---------------------------------------------------------------- handlers --

func _on_stats_changed(health: int, max_health: int, armor: int) -> void:
	_health_label.text = str(health)
	_health_label.add_theme_color_override("font_color",
			Color(1.0, 0.25, 0.2) if health <= max_health / 4 else Color(1.0, 0.45, 0.42))
	_armor_label.text = str(armor)


func _on_ammo_changed(in_mag: int, reserve: int) -> void:
	_ammo_label.text = "%d / %d" % [in_mag, reserve]


func _on_weapon_changed(weapon: Resource) -> void:
	_weapon = weapon as WeaponData
	if _weapon == null:
		return
	_fire_frames = _weapon.sprite_fire
	_fire_frame_index = -1
	_viewmodel.texture = _weapon.sprite_idle
	_weapon_label.text = _weapon.display_name.to_upper()


func _on_weapon_fired() -> void:
	_recoil = 1.0
	if _fire_frames.is_empty():
		return
	_fire_frame_index = 0
	_fire_frame_timer = _weapon.fire_frame_time
	_viewmodel.texture = _fire_frames[0]


func _on_player_damaged(amount: int, _direction: Vector3) -> void:
	_damage_flash.color.a = minf(0.55, _damage_flash.color.a + 0.12 + amount * 0.012)


func _on_keys_changed(keys: Array) -> void:
	for child in _keys_box.get_children():
		child.queue_free()
	for key: StringName in keys:
		var swatch := ColorRect.new()
		swatch.color = Pickup.KEY_COLORS.get(key, Color.WHITE)
		swatch.custom_minimum_size = Vector2(20, 30)
		_keys_box.add_child(swatch)


## Watches which device the player is actually using, so the interact prompt
## says "E" on a keyboard and "X" on a pad without any settings screen.
func _input(event: InputEvent) -> void:
	var gamepad := _using_gamepad
	if event is InputEventJoypadButton:
		gamepad = true
	elif event is InputEventJoypadMotion:
		# Stick drift would flip this constantly, so require a real deflection.
		if absf((event as InputEventJoypadMotion).axis_value) > 0.5:
			gamepad = true
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		gamepad = false
	if gamepad != _using_gamepad:
		_using_gamepad = gamepad
		_refresh_prompt()


func _on_interact_prompt(prompt: String) -> void:
	_prompt_text = prompt
	_refresh_prompt()


func _refresh_prompt() -> void:
	_interact_label.visible = _prompt_text != ""
	if _interact_label.visible:
		_interact_label.text = "[%s]  %s" % ["X" if _using_gamepad else "E", _prompt_text]


func _on_message(text: String, duration: float) -> void:
	_message_label.text = text
	_message_timer = duration
	_message_label.modulate.a = 1.0


func _refresh_kills() -> void:
	_kills_label.text = "%d / %d" % [Game.kills, Game.enemies_total]


## Simple four-tick crosshair. Drawn rather than textured so it stays crisp at
## any resolution.
class Crosshair extends Control:
	const GAP := 7.0
	const LENGTH := 11.0
	const THICKNESS := 2.0

	func _draw() -> void:
		var c := size * 0.5
		var color := Color(0.9, 0.95, 1.0, 0.85)
		var shadow := Color(0, 0, 0, 0.5)
		for offset: Vector2 in [Vector2.ONE, Vector2.ZERO]:
			var col := shadow if offset == Vector2.ONE else color
			draw_line(c + Vector2(-GAP - LENGTH, 0) + offset, c + Vector2(-GAP, 0) + offset, col, THICKNESS)
			draw_line(c + Vector2(GAP, 0) + offset, c + Vector2(GAP + LENGTH, 0) + offset, col, THICKNESS)
			draw_line(c + Vector2(0, -GAP - LENGTH) + offset, c + Vector2(0, -GAP) + offset, col, THICKNESS)
			draw_line(c + Vector2(0, GAP) + offset, c + Vector2(0, GAP + LENGTH) + offset, col, THICKNESS)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()
