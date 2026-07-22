## Entry point: owns level loading, the player spawn, the HUD and the menus.
##
## Levels themselves know nothing about any of this — a level is just geometry
## plus a PlayerStart and a LevelExit, which is what keeps them cheap to make.
class_name Main
extends Node

@export_file("*.tscn") var starting_level := "res://levels/demo_level.tscn"
@export var player_scene: PackedScene

@onready var _level_root: Node3D = $LevelRoot

var _hud: Hud
var _menu: OverlayMenu
var _player: Player
var _current_level_path := ""
var _state: StringName = &"playing"


func _ready() -> void:
	# Must keep running while the tree is paused so the menu can unpause it.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_install_environment()

	_hud = Hud.new()
	add_child(_hud)

	_menu = OverlayMenu.new()
	_menu.action_selected.connect(_on_menu_action)
	add_child(_menu)

	Game.player_died.connect(_on_player_died)
	Game.level_completed.connect(_on_level_completed)
	Game.restart_requested.connect(_restart)

	load_level(starting_level)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		if _state == &"playing":
			_pause()
		elif _state == &"paused":
			_resume()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------ level loading --

func load_level(path: String) -> void:
	if path == "" or not ResourceLoader.exists(path):
		push_error("Main: level not found: %s" % path)
		return

	_teardown_level()
	_current_level_path = path

	# Reset before the level enters the tree — enemies register during _ready.
	Game.reset_run()

	var level := (load(path) as PackedScene).instantiate()
	_level_root.add_child(level)

	_spawn_player(level)
	Game.begin_level()
	_set_state(&"playing")


func _teardown_level() -> void:
	_player = null
	Game.player = null
	for child in _level_root.get_children():
		_level_root.remove_child(child)
		child.queue_free()


func _spawn_player(level: Node) -> void:
	if player_scene == null:
		push_error("Main: player_scene is not set")
		return

	_player = player_scene.instantiate() as Player
	_level_root.add_child(_player)

	var start := _find_player_start(level)
	if start == null:
		push_warning("Main: no PlayerStart in %s — spawning at the origin" % _current_level_path)
		_player.global_position = Vector3(0.0, 1.0, 0.0)
		return

	var spawn := start.get_spawn_transform()
	_player.global_position = spawn.origin
	_player.rotation.y = spawn.basis.get_euler().y
	# The look angle is tracked separately from the node rotation.
	_player.set(&"_yaw", _player.rotation.y)


func _find_player_start(level: Node) -> PlayerStart:
	for node in level.find_children("*", "", true, false):
		if node is PlayerStart:
			return node as PlayerStart
	return null


func _restart() -> void:
	load_level(_current_level_path)


# -------------------------------------------------------------------- state --

func _set_state(next: StringName) -> void:
	_state = next
	var playing := next == &"playing"
	# "dead" deliberately keeps running so the death slump animation plays.
	get_tree().paused = next == &"paused" or next == &"complete"
	if _player != null and is_instance_valid(_player):
		_player.set_active(playing)
	if playing:
		_menu.hide_menu()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if playing else Input.MOUSE_MODE_VISIBLE


func _pause() -> void:
	_set_state(&"paused")
	_menu.show_menu("PAUSED", "", [
		{"id": &"resume", "text": "Resume"},
		{"id": &"restart", "text": "Restart Level"},
		{"id": &"quit", "text": "Quit"},
	])


func _resume() -> void:
	_set_state(&"playing")


func _on_player_died() -> void:
	# Deliberately not paused, so the death slump animation plays out.
	_set_state(&"dead")
	_menu.show_menu("YOU DIED", "Kills: %d / %d" % [Game.kills, Game.enemies_total], [
		{"id": &"restart", "text": "Try Again"},
		{"id": &"quit", "text": "Quit"},
	])


func _on_level_completed(next_level: String) -> void:
	Sfx.play_ui(Sfx.LEVEL_COMPLETE, -4.0)
	_set_state(&"complete")
	var stats := "Time %s     Kills %d / %d" % [Game.format_time(), Game.kills, Game.enemies_total]
	var options: Array = []
	if next_level != "" and ResourceLoader.exists(next_level):
		options.append({"id": &"next", "text": "Next Level"})
	options.append({"id": &"restart", "text": "Replay Level"})
	options.append({"id": &"quit", "text": "Quit"})
	_menu.set_meta(&"next_level", next_level)
	_menu.show_menu("LEVEL CLEARED", stats, options)


func _on_menu_action(id: StringName) -> void:
	match id:
		&"resume": _resume()
		&"restart": _restart()
		&"next": load_level(_menu.get_meta(&"next_level", ""))
		&"quit": get_tree().quit()


# -------------------------------------------------------------- environment --

## A shared indoor look: dark ambient, mild fog for depth, and glow so emissive
## surfaces (the exit pad, muzzle flashes) actually bloom. Levels can still add
## their own WorldEnvironment to override this.
func _install_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.03, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.36, 0.44)
	env.ambient_light_energy = 0.5

	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.07, 0.1)
	env.fog_density = 0.012

	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
