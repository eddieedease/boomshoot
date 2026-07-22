## Headless gameplay smoke test.
##
##   godot --headless --path . tools/smoke_test.tscn
##
## Boots the real main scene and drives the actual systems — geometry, hitscan
## damage, doors, keys, the exit — rather than asserting on mocks. Exits with a
## non-zero code on failure so it can gate a commit.
extends Node

var _failures: Array[String] = []
var _completed := false


func _ready() -> void:
	Game.level_completed.connect(func(_next: String) -> void: _completed = true)

	var main := (load("res://src/main.tscn") as PackedScene).instantiate()
	add_child(main)

	await _settle(10)
	await _test_level_loaded()
	await _test_geometry_is_solid()
	await _test_shooting_kills()
	await _test_door_opens()
	await _test_locked_exit()

	if _failures.is_empty():
		print("\n[smoke] PASS — all checks green")
		get_tree().quit(0)
	else:
		print("\n[smoke] FAIL (%d)" % _failures.size())
		for failure in _failures:
			print("  x ", failure)
		get_tree().quit(1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  ok  ", description)
	else:
		_failures.append(description)
		print("  FAIL ", description)


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


# -------------------------------------------------------------------- tests --

func _test_level_loaded() -> void:
	print("\n[smoke] level load")
	_check(Game.player != null, "player spawned")
	_check(Game.enemies_total == 5, "5 enemies registered (got %d)" % Game.enemies_total)

	var starts := get_tree().get_nodes_in_group(&"player_start")
	_check(starts.size() == 1, "exactly one PlayerStart (got %d)" % starts.size())


func _test_geometry_is_solid() -> void:
	print("\n[smoke] procedural geometry")
	var player := Game.player as Player
	if player == null:
		_check(false, "no player to test geometry with")
		return

	await _settle(30)
	_check(player.is_on_floor(), "player is standing on generated floor")
	_check(player.global_position.y > -5.0,
			"player did not fall out of the world (y=%.2f)" % player.global_position.y)

	# Walls must actually collide, not just render.
	var space := player.get_world_3d().direct_space_state
	var from := Vector3(0.0, 1.5, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, 0.0, 20.0), Layers.WORLD)
	_check(not space.intersect_ray(query).is_empty(), "start room south wall blocks a ray")


func _test_shooting_kills() -> void:
	print("\n[smoke] hitscan damage")
	var player := Game.player as Player
	var enemy: Enemy = null
	for node in get_tree().get_nodes_in_group(&"enemy"):
		if (node as Enemy).state != Enemy.State.DEAD:
			enemy = node
			break
	if player == null or enemy == null:
		_check(false, "needed a live player and enemy")
		return

	# Stand 4m away, facing it down -Z.
	player.global_position = enemy.global_position + Vector3(0.0, 0.1, 4.0)
	player.rotation.y = 0.0
	player.set(&"_yaw", 0.0)
	await _settle(4)

	var weapons := player.get_weapons()
	var weapon := weapons.get_current()
	_check(weapon != null, "player has a weapon equipped")
	if weapon == null:
		return

	var kills_before := Game.kills
	for i in 8:
		weapons.set(&"_cooldown", 0.0)
		weapons.call(&"_try_fire", weapon)
		await get_tree().physics_frame

	_check(Game.kills > kills_before, "shooting an enemy killed it (kills %d -> %d)"
			% [kills_before, Game.kills])
	_check(enemy.state == Enemy.State.DEAD, "enemy entered the DEAD state")


func _test_door_opens() -> void:
	print("\n[smoke] proximity door")
	var player := Game.player as Player
	var door: MapDoor = null
	for node in _find_all(self, "MapDoor"):
		if (node as MapDoor).open_mode == MapDoor.OpenMode.PROXIMITY:
			door = node
			break
	if player == null or door == null:
		_check(false, "found a proximity door")
		return

	player.global_position = door.global_position + Vector3(0.0, 0.1, 1.2)
	await _settle(90)
	_check(door.is_open(), "door opened when the player approached")


func _test_locked_exit() -> void:
	print("\n[smoke] key-gated exit")
	var player := Game.player as Player
	var exit_pad: LevelExit = null
	for node in _find_all(self, "LevelExit"):
		exit_pad = node
		break
	if player == null or exit_pad == null:
		_check(false, "found the level exit")
		return

	# Without the key the exit must refuse.
	player.global_position = exit_pad.global_position + Vector3(0.0, 0.3, 0.0)
	await _settle(20)
	_check(not _completed, "exit stays locked without the red keycard")

	Game.add_key(&"red")
	await _settle(20)
	_check(_completed, "exit completes the level once the keycard is held")


func _find_all(root: Node, type_name: String) -> Array[Node]:
	var found: Array[Node] = []
	if root == null:
		return found
	for node in root.find_children("*", "", true, false):
		if node.get_script() != null and node.get_script().get_global_name() == type_name:
			found.append(node)
	return found
