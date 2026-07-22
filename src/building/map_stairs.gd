## A run of steps climbing towards local +Z. Rotate the node to aim it.
##
## Keep `step_rise` at or below the player's step height (0.4 by default) or the
## stairs become an invisible wall.
@tool
class_name MapStairs
extends MapPart

@export_range(1, 64, 1, "or_greater") var steps := 6:
	set(v): steps = maxi(1, v); queue_rebuild()
@export_range(0.05, 1.0, 0.01, "or_greater") var step_rise := 0.3:
	set(v): step_rise = v; queue_rebuild()
@export_range(0.1, 3.0, 0.01, "or_greater") var step_run := 0.5:
	set(v): step_run = v; queue_rebuild()
@export_range(0.5, 30.0, 0.1, "or_greater") var width := 4.0:
	set(v): width = v; queue_rebuild()
## Solid mass beneath each tread instead of floating slabs.
@export var fill_below := true:
	set(v): fill_below = v; queue_rebuild()

@export_group("Surfaces")
@export var surface: MapMaterials.Surface = MapMaterials.Surface.STONE:
	set(v): surface = v; queue_rebuild()
@export_range(0.05, 4.0, 0.05) var texture_scale := 0.5:
	set(v): texture_scale = v; queue_rebuild()


## Total climb, handy when lining a staircase up with a platform.
func get_total_rise() -> float:
	return steps * step_rise


func get_total_run() -> float:
	return steps * step_run


func _build() -> void:
	for i in steps:
		var top := (i + 1) * step_rise
		var height := top if fill_below else step_rise
		var center := Vector3(0.0, top - height * 0.5, (i + 0.5) * step_run)
		_box(center, Vector3(width, height, step_run), surface, texture_scale)
