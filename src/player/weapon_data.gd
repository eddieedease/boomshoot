## Everything that makes one gun feel different from another.
##
## Weapons are pure data: create a new .tres, point it at some sprites, and add
## it to the player's `weapons` array. No code needed for a second gun unless it
## needs genuinely new behaviour.
@tool
class_name WeaponData
extends Resource

@export var display_name := "Pistol"

@export_group("Damage")
@export_range(1.0, 500.0, 1.0, "or_greater") var damage := 12.0
## Shots per trigger pull. Raise for a shotgun.
@export_range(1, 32, 1) var pellets := 1
## Cone half-angle. 0 is pinpoint accurate.
@export_range(0.0, 30.0, 0.1) var spread_degrees := 1.0
## Extra spread that builds up while holding the trigger down.
@export_range(0.0, 30.0, 0.1) var spread_bloom := 1.5
@export_range(1.0, 500.0, 1.0, "or_greater") var range_metres := 120.0
## Damage multiplier for hits above an enemy's shoulder line.
@export_range(1.0, 10.0, 0.1) var headshot_multiplier := 2.0

@export_group("Firing")
@export var automatic := false
@export_range(0.5, 30.0, 0.1) var shots_per_second := 5.0

@export_group("Ammo")
## 0 means the weapon never needs reloading.
@export_range(0, 200, 1) var mag_size := 12
@export_range(0, 999, 1) var reserve_max := 120
@export_range(0, 999, 1) var reserve_start := 48
@export_range(0.1, 10.0, 0.05) var reload_time := 1.1

@export_group("Feel")
## Degrees of upward camera kick per shot.
@export_range(0.0, 15.0, 0.1) var recoil_kick := 1.4
@export_range(0.0, 1.0, 0.01) var screen_shake := 0.15

@export_group("View model")
@export var sprite_idle: Texture2D
## Played in order after each shot, then back to idle.
@export var sprite_fire: Array[Texture2D] = []
@export_range(0.01, 0.5, 0.01) var fire_frame_time := 0.045


## Seconds between shots.
func get_shot_interval() -> float:
	return 1.0 / maxf(shots_per_second, 0.01)


func uses_ammo() -> bool:
	return mag_size > 0
