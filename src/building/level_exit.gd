## The level's end: a glowing pad that finishes the level when the player
## stands on it.
##
## Conditions are deliberately data-driven so a designer can gate the exit on a
## keycard, on clearing the level, or on nothing at all.
@tool
class_name LevelExit
extends MapPart

@export var pad_size := Vector3(3.0, 0.2, 3.0):
	set(v): pad_size = v; queue_rebuild()
## Scene path loaded on completion. Empty shows the level-complete screen.
@export_file("*.tscn") var next_level := ""
@export var required_key: StringName = &""
@export var require_all_enemies_dead := false
## Shown when the player steps on a blocked exit.
@export var blocked_message := "The way out is sealed."

@export_group("Surfaces")
@export_range(0.05, 4.0, 0.05) var texture_scale := 0.5:
	set(v): texture_scale = v; queue_rebuild()

var _area: Area3D
## Latched so a blocked exit doesn't spam the message every physics frame.
var _player_inside := false


func _build() -> void:
	_box(Vector3(0.0, pad_size.y * 0.5, 0.0), pad_size, MapMaterials.Surface.EXIT, texture_scale)

	var light := OmniLight3D.new()
	light.light_color = Color(0.35, 1.0, 0.5)
	light.light_energy = 2.5
	light.omni_range = maxf(pad_size.x, pad_size.z) * 2.5
	light.position = Vector3(0.0, 1.2, 0.0)
	_geometry.add_child(light)

	if Engine.is_editor_hint():
		return

	_area = Area3D.new()
	_area.name = "ExitTrigger"
	_area.collision_layer = Layers.TRIGGER
	_area.collision_mask = Layers.PLAYER
	_area.position = Vector3(0.0, pad_size.y + 1.0, 0.0)
	_geometry.add_child(_area)

	var shape := BoxShape3D.new()
	shape.size = Vector3(pad_size.x, 2.0, pad_size.z)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_area.add_child(cs)

	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)

	# The gate can also be satisfied while the player is already standing here,
	# so re-check whenever a condition could have changed.
	Game.enemy_died.connect(func(_e: Node3D) -> void: _attempt_exit())
	Game.keys_changed.connect(func(_k: Array) -> void: _attempt_exit())


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group(&"player"):
		return
	_player_inside = true
	_attempt_exit()


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group(&"player"):
		_player_inside = false


func _attempt_exit() -> void:
	if not _player_inside:
		return

	if required_key != &"" and not Game.has_key(required_key):
		Game.post_message("%s (%s keycard)" % [blocked_message, String(required_key).to_upper()])
		return
	if require_all_enemies_dead and Game.enemies_alive > 0:
		Game.post_message("%s (%d hostiles remaining)" % [blocked_message, Game.enemies_alive])
		return

	Game.finish_level(next_level)
