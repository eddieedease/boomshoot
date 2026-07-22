## One-shot scene generator.
##
##   godot --headless --path . tools/build_scenes.tscn
##
## Builds the player, the grunt, the main scene and the demo level in code and
## lets Godot serialise them, which guarantees valid .tscn files. The results
## are ordinary scenes: open them in the editor and edit them by hand from here
## on. Re-running OVERWRITES them, so only do that if you want a clean slate.
##
## This runs as a *scene* rather than via `--script` on purpose: `--script`
## compiles before autoloads are registered, so every gameplay script that
## refers to `Game` would fail to compile.
extends Node

const PISTOL_PATH := "res://src/player/weapons/pistol.tres"
const PLAYER_PATH := "res://src/player/player.tscn"
const GRUNT_PATH := "res://src/entities/grunt.tscn"
const MAIN_PATH := "res://src/main.tscn"
const LEVEL_PATH := "res://levels/demo_level.tscn"

const SPRITES := "res://assets/sprites/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://src/player/weapons")
	_build_pistol()
	_build_player()
	_build_grunt()
	_build_main()
	_build_demo_level()
	print("[build_scenes] done")
	get_tree().quit()


# ------------------------------------------------------------------ helpers --

## Parents `node` and gives it the scene root as owner, which is what makes it
## survive `PackedScene.pack()`.
func _attach(parent: Node, node: Node, root: Node, node_name: String) -> Node:
	node.name = node_name
	parent.add_child(node)
	node.owner = root
	return node


func _save_scene(root: Node, path: String) -> void:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("pack failed for %s (%d)" % [path, err])
		return
	err = ResourceSaver.save(packed, path)
	if err != OK:
		push_error("save failed for %s (%d)" % [path, err])
	else:
		print("  wrote ", path)
	# The template tree has served its purpose; drop it so the generator exits
	# without a wall of leak warnings.
	root.free()


func _tex(file_name: String) -> Texture2D:
	return load(SPRITES + file_name) as Texture2D


# ------------------------------------------------------------------- pistol --

func _build_pistol() -> void:
	var weapon := WeaponData.new()
	weapon.display_name = "Pistol"
	weapon.damage = 15.0
	weapon.pellets = 1
	weapon.spread_degrees = 0.6
	weapon.spread_bloom = 1.6
	weapon.range_metres = 120.0
	weapon.headshot_multiplier = 2.5
	weapon.automatic = false
	weapon.shots_per_second = 5.5
	weapon.mag_size = 12
	weapon.reserve_max = 150
	weapon.reserve_start = 60
	weapon.reload_time = 1.0
	weapon.recoil_kick = 1.6
	weapon.screen_shake = 0.18
	weapon.sprite_idle = _tex("pistol_idle.png")

	var frames: Array[Texture2D] = [_tex("pistol_fire_0.png"), _tex("pistol_fire_1.png")]
	weapon.sprite_fire = frames
	weapon.fire_frame_time = 0.05

	var err := ResourceSaver.save(weapon, PISTOL_PATH)
	if err != OK:
		push_error("could not save pistol (%d)" % err)
	else:
		print("  wrote ", PISTOL_PATH)


# ------------------------------------------------------------------- player --

func _build_player() -> void:
	var root := CharacterBody3D.new()
	root.name = "Player"
	root.set_script(load("res://src/player/player.gd"))

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	var collision := CollisionShape3D.new()
	collision.shape = capsule
	collision.position = Vector3(0.0, 0.9, 0.0)
	_attach(root, collision, root, "Collision")

	var head := Node3D.new()
	head.position = Vector3(0.0, 1.6, 0.0)
	_attach(root, head, root, "Head")

	var camera := Camera3D.new()
	camera.fov = 90.0
	camera.near = 0.05
	camera.far = 500.0
	_attach(head, camera, root, "Camera3D")

	var ray := RayCast3D.new()
	ray.target_position = Vector3(0.0, 0.0, -2.5)
	_attach(camera, ray, root, "InteractRay")

	var weapons := Node.new()
	weapons.set_script(load("res://src/player/weapon_manager.gd"))
	var loadout: Array[WeaponData] = [load(PISTOL_PATH) as WeaponData]
	weapons.set(&"weapons", loadout)
	_attach(root, weapons, root, "Weapons")

	_save_scene(root, PLAYER_PATH)


# -------------------------------------------------------------------- grunt --

func _build_grunt() -> void:
	var root := CharacterBody3D.new()
	root.name = "Grunt"
	root.set_script(load("res://src/entities/enemy.gd"))

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.7
	var collision := CollisionShape3D.new()
	collision.shape = capsule
	collision.position = Vector3(0.0, 0.85, 0.0)
	_attach(root, collision, root, "Collision")

	var sprite := Sprite3D.new()
	sprite.texture = _tex("grunt_idle.png")
	sprite.position = Vector3(0.0, 0.96, 0.0)
	sprite.pixel_size = 0.04
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Discard rather than blend, so sprites sort correctly against each other.
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.shaded = true
	sprite.double_sided = true
	_attach(root, sprite, root, "Sprite")

	var walk: Array[Texture2D] = [
		_tex("grunt_walk_0.png"), _tex("grunt_walk_1.png"),
		_tex("grunt_walk_2.png"), _tex("grunt_walk_3.png"),
	]
	var die: Array[Texture2D] = [
		_tex("grunt_die_0.png"), _tex("grunt_die_1.png"), _tex("grunt_die_2.png"),
	]
	root.set(&"sprite_idle", _tex("grunt_idle.png"))
	root.set(&"sprite_walk", walk)
	root.set(&"sprite_attack", _tex("grunt_attack.png"))
	root.set(&"sprite_pain", _tex("grunt_pain.png"))
	root.set(&"sprite_die", die)

	_save_scene(root, GRUNT_PATH)


# --------------------------------------------------------------------- main --

func _build_main() -> void:
	var root := Node.new()
	root.name = "Main"
	root.set_script(load("res://src/main.gd"))
	root.set(&"player_scene", load(PLAYER_PATH))
	root.set(&"starting_level", LEVEL_PATH)

	_attach(root, Node3D.new(), root, "LevelRoot")

	_save_scene(root, MAIN_PATH)


# --------------------------------------------------------------- demo level --

## Layout, looking down (X right, -Z away from the start):
##
##        +---------------- ARENA (20 x 22, h6) ----------------+
##   VAULT|                                   [platform + exit] |
##   (key)|                                                     |
##        +--------------------[door]---------------------------+
##                              | corridor |
##                              +----------+
##                        +---- START (14 x 12) ----+
##
## Every value below is also editable in the inspector once the scene is open —
## nothing here is baked into geometry.
func _build_demo_level() -> void:
	var root := Node3D.new()
	root.name = "DemoLevel"

	var grunt := load(GRUNT_PATH) as PackedScene

	# --- Start room -----------------------------------------------------------
	var start_room := MapRoom.new()
	start_room.size = Vector3(14.0, 4.0, 12.0)
	start_room.wall_surface = MapMaterials.Surface.BRICK
	start_room.wall_north = MapRoom.WallMode.DOORWAY
	start_room.doorway_width = 3.5
	start_room.doorway_height = 3.0
	_attach(root, start_room, root, "StartRoom")

	var start := PlayerStart.new()
	start.position = Vector3(0.0, 0.0, 4.0)
	_attach(root, start, root, "PlayerStart")

	_light(root, "StartLight", Vector3(0.0, 3.5, 0.0), Color(1.0, 0.86, 0.66), 3.0, 14.0)
	_pickup(root, "StartAmmo", Vector3(-4.0, 0.9, -2.0), Pickup.Kind.AMMO, 24)

	# --- Corridor -------------------------------------------------------------
	var corridor := MapRoom.new()
	corridor.position = Vector3(0.0, 0.0, -13.0)
	corridor.size = Vector3(4.0, 3.5, 14.0)
	corridor.wall_surface = MapMaterials.Surface.TECH
	corridor.floor_surface = MapMaterials.Surface.GRATE
	corridor.wall_north = MapRoom.WallMode.OPEN
	corridor.wall_south = MapRoom.WallMode.OPEN
	_attach(root, corridor, root, "Corridor")

	_light(root, "CorridorLight", Vector3(0.0, 3.0, -10.0), Color(0.7, 0.85, 1.0), 2.2, 10.0, 0.45)
	_light(root, "CorridorLight2", Vector3(0.0, 3.0, -17.0), Color(0.7, 0.85, 1.0), 2.2, 10.0)

	var corridor_grunt := grunt.instantiate()
	corridor_grunt.position = Vector3(0.0, 0.1, -16.0)
	_attach(root, corridor_grunt, root, "CorridorGrunt")

	# --- Arena ----------------------------------------------------------------
	var arena := MapRoom.new()
	arena.position = Vector3(0.0, 0.0, -31.0)
	arena.size = Vector3(20.0, 6.0, 22.0)
	arena.wall_surface = MapMaterials.Surface.STONE
	arena.wall_south = MapRoom.WallMode.DOORWAY
	arena.wall_west = MapRoom.WallMode.DOORWAY
	arena.doorway_width = 3.5
	arena.doorway_height = 3.0
	_attach(root, arena, root, "Arena")

	# Auto-opening door where the corridor meets the arena.
	var arena_door := MapDoor.new()
	arena_door.position = Vector3(0.0, 0.0, -19.75)
	arena_door.size = Vector3(3.5, 3.0, 0.3)
	arena_door.slide = MapDoor.SlideMode.UP
	_attach(root, arena_door, root, "ArenaDoor")

	_light(root, "ArenaLightA", Vector3(-5.0, 5.5, -25.0), Color(1.0, 0.8, 0.6), 4.0, 18.0)
	_light(root, "ArenaLightB", Vector3(5.0, 5.5, -37.0), Color(1.0, 0.8, 0.6), 4.0, 18.0)

	# Raised platform with the exit on top, reached by stairs.
	var platform := MapBlock.new()
	platform.position = Vector3(6.0, 0.0, -36.0)
	platform.size = Vector3(8.0, 2.5, 8.0)
	platform.surface = MapMaterials.Surface.TECH
	_attach(root, platform, root, "ExitPlatform")

	var stairs := MapStairs.new()
	stairs.position = Vector3(6.0, 0.0, -27.0)
	stairs.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	stairs.steps = 10
	stairs.step_rise = 0.25
	stairs.step_run = 0.5
	stairs.width = 4.0
	_attach(root, stairs, root, "ExitStairs")

	var exit_pad := LevelExit.new()
	exit_pad.position = Vector3(6.0, 2.5, -37.0)
	exit_pad.pad_size = Vector3(3.0, 0.2, 3.0)
	exit_pad.required_key = &"red"
	exit_pad.blocked_message = "The blast door is locked."
	_attach(root, exit_pad, root, "LevelExit")

	_pickup(root, "ArenaHealth", Vector3(-7.0, 0.9, -25.0), Pickup.Kind.HEALTH, 25)
	_pickup(root, "ArenaAmmo", Vector3(8.0, 0.9, -23.0), Pickup.Kind.AMMO, 24)

	for spec: Array in [
		["ArenaGrunt1", Vector3(-6.0, 0.1, -34.0)],
		["ArenaGrunt2", Vector3(2.0, 0.1, -39.0)],
		["PlatformGrunt", Vector3(6.0, 2.6, -34.5)],
	]:
		var enemy := grunt.instantiate()
		enemy.position = spec[1]
		_attach(root, enemy, root, spec[0])

	# --- Key vault ------------------------------------------------------------
	var vault := MapRoom.new()
	vault.position = Vector3(-15.0, 0.0, -31.0)
	vault.size = Vector3(10.0, 4.0, 10.0)
	vault.wall_surface = MapMaterials.Surface.BRICK
	vault.floor_surface = MapMaterials.Surface.CONCRETE
	vault.wall_east = MapRoom.WallMode.OPEN
	_attach(root, vault, root, "KeyVault")

	# Rotated a quarter turn because it sits in a wall that runs along Z.
	var vault_door := MapDoor.new()
	vault_door.position = Vector3(-10.25, 0.0, -31.0)
	vault_door.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	vault_door.size = Vector3(3.5, 3.0, 0.3)
	vault_door.slide = MapDoor.SlideMode.UP
	vault_door.open_mode = MapDoor.OpenMode.USE
	_attach(root, vault_door, root, "VaultDoor")

	_light(root, "VaultLight", Vector3(-15.0, 3.5, -31.0), Color(1.0, 0.5, 0.45), 3.0, 12.0)

	_pickup(root, "RedKey", Vector3(-15.0, 1.2, -34.0), Pickup.Kind.KEY, 1, &"red")
	_pickup(root, "VaultArmor", Vector3(-17.5, 0.9, -28.5), Pickup.Kind.ARMOR, 50)

	var vault_grunt := grunt.instantiate()
	vault_grunt.position = Vector3(-15.0, 0.1, -29.0)
	_attach(root, vault_grunt, root, "VaultGrunt")

	_save_scene(root, LEVEL_PATH)


func _light(root: Node, node_name: String, position: Vector3, color: Color,
		energy: float, range_metres: float, flicker: float = 0.0) -> void:
	var light := MapLight.new()
	light.position = position
	light.color = color
	light.energy = energy
	light.range_metres = range_metres
	light.flicker_amount = flicker
	_attach(root, light, root, node_name)


func _pickup(root: Node, node_name: String, position: Vector3, kind: Pickup.Kind,
		amount: int, key_id: StringName = &"red") -> void:
	var pickup := Pickup.new()
	pickup.position = position
	pickup.kind = kind
	pickup.amount = amount
	pickup.key_id = key_id
	_attach(root, pickup, root, node_name)
