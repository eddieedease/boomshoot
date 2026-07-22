## Autoload `Game` — global signal bus and run state.
##
## Gameplay nodes never reach for each other directly; they announce things here
## and whoever cares subscribes. That decoupling is what will let the immersive
## sim layers (AI senses, factions, objectives) hook in later without surgery on
## the player or the enemies.
extends Node

# --- Player -----------------------------------------------------------------
signal player_spawned(player_node: Node3D)
signal player_stats_changed(health: int, max_health: int, armor: int)
signal player_damaged(amount: int, from_direction: Vector3)
signal player_died()

# --- Weapons ----------------------------------------------------------------
signal weapon_changed(weapon: Resource)
signal ammo_changed(in_mag: int, reserve: int)
signal weapon_fired()
signal weapon_reload_started(duration: float)

# --- World ------------------------------------------------------------------
signal enemy_died(enemy: Node3D)
signal keys_changed(keys: Array)
signal message_posted(text: String, duration: float)
## What the player is currently looking at, if it can be used. Empty = nothing.
signal interact_prompt_changed(prompt: String)

# --- Flow -------------------------------------------------------------------
signal level_started()
signal level_completed(next_level: String)
signal restart_requested()

## Set by the player as it enters the tree. Read-only for everyone else.
var player: Node3D = null

var kills := 0
var enemies_alive := 0
var enemies_total := 0
var secrets_found := 0
var level_time := 0.0

var _keys: Array[StringName] = []
var _level_running := false


func _process(delta: float) -> void:
	if _level_running and not get_tree().paused:
		level_time += delta


# ------------------------------------------------------------ run lifecycle --

## Clears run state. Call this *before* the level enters the tree so enemies can
## register themselves as they spawn.
func reset_run() -> void:
	kills = 0
	enemies_alive = 0
	enemies_total = 0
	secrets_found = 0
	level_time = 0.0
	_keys.clear()
	keys_changed.emit(_keys)


## Call once the level is in the tree and every enemy has registered.
func begin_level() -> void:
	_level_running = true
	level_started.emit()


func finish_level(next_level: String = "") -> void:
	if not _level_running:
		return
	_level_running = false
	level_completed.emit(next_level)


func request_restart() -> void:
	restart_requested.emit()


# -------------------------------------------------------------------- keys --

func add_key(id: StringName) -> void:
	if id == &"" or _keys.has(id):
		return
	_keys.append(id)
	keys_changed.emit(_keys)


func has_key(id: StringName) -> bool:
	return id == &"" or _keys.has(id)


func get_keys() -> Array[StringName]:
	return _keys.duplicate()


# ------------------------------------------------------------------ enemies --

## Enemies call this from `_ready` so the HUD can show a kill target.
func register_enemy() -> void:
	enemies_total += 1
	enemies_alive += 1


func notify_enemy_died(enemy: Node3D) -> void:
	kills += 1
	enemies_alive = maxi(0, enemies_alive - 1)
	enemy_died.emit(enemy)


# ------------------------------------------------------------------ helpers --

func post_message(text: String, duration: float = 2.5) -> void:
	message_posted.emit(text, duration)


func format_time() -> String:
	var total := int(level_time)
	return "%d:%02d" % [total / 60, total % 60]
