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
	await _test_no_overlapping_floors()
	await _test_room_attachment()
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


## Two floor slabs occupying the same space put two upward-facing surfaces in
## one plane, which is what makes the seam between rooms flicker. Sampling the
## slab layer for points inside more than one shape catches that directly.
func _test_no_overlapping_floors() -> void:
	print("\n[smoke] no overlapping geometry")
	var player := Game.player as Player
	if player == null:
		_check(false, "no player to query the world with")
		return

	var space := player.get_world_3d().direct_space_state
	var worst := 0
	var worst_at := Vector3.ZERO

	# y = -0.25 sits inside the floor slabs and wall sills, below any prop. The
	# odd fractional offsets matter: room edges land on whole and half metres, and
	# a sample sitting exactly on a shared face counts as inside both shapes.
	for x in range(-22, 12):
		for z in range(-43, 8):
			var query := PhysicsPointQueryParameters3D.new()
			query.position = Vector3(x + 0.137, -0.25, z + 0.263)
			query.collision_mask = Layers.WORLD
			query.collide_with_areas = false
			var hits := space.intersect_point(query, 8).size()
			if hits > worst:
				worst = hits
				worst_at = query.position

	_check(worst <= 1, "no point sits inside two solids (worst = %d at %s)" % [worst, worst_at])


## Locks in the arithmetic the dock's Attach Room button uses: two rooms butted
## by their outer faces must leave one continuous walkable floor and no overlap.
func _test_room_attachment() -> void:
	print("\n[smoke] attached rooms")
	var holder := Node3D.new()
	holder.position = Vector3(500.0, 0.0, 0.0)  # far from the demo level
	add_child(holder)

	var source := MapRoom.new()
	source.size = Vector3(10.0, 4.0, 10.0)
	source.wall_north = MapRoom.WallMode.DOORWAY
	holder.add_child(source)

	var neighbour := MapRoom.new()
	neighbour.size = Vector3(10.0, 4.0, 10.0)
	neighbour.wall_south = MapRoom.WallMode.OPEN
	# Same formula as build_dock.gd: half + wall band + half.
	neighbour.position = Vector3(0.0, 0.0, -(5.0 + source.wall_thickness + 5.0))
	holder.add_child(neighbour)

	await _settle(6)

	var space := get_viewport().world_3d.direct_space_state
	var gaps := 0
	var overlaps := 0
	# Walk the seam from deep in one room to deep in the other. The offset keeps
	# samples off the exact face boundaries, which would read as false overlaps.
	for step in 60:
		var z := 3.93 - step * 0.29
		var origin := holder.position + Vector3(0.0, 2.0, z)
		var ray := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 4.0, Layers.WORLD)
		if space.intersect_ray(ray).is_empty():
			gaps += 1

		var point := PhysicsPointQueryParameters3D.new()
		point.position = holder.position + Vector3(0.0, -0.25, z)
		point.collision_mask = Layers.WORLD
		if space.intersect_point(point, 8).size() > 1:
			overlaps += 1

	_check(gaps == 0, "floor is continuous through the shared doorway (%d gaps)" % gaps)
	_check(overlaps == 0, "attached rooms do not overlap (%d overlapping samples)" % overlaps)

	holder.queue_free()


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
