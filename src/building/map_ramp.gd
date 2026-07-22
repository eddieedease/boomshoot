## A sloped surface climbing towards local +Z. Smoother than stairs and cheaper
## in collision, useful for vehicle-scale spaces and for keeping enemies moving.
##
## The bottom edge sits at the origin; `run` and `rise` describe the far edge.
@tool
class_name MapRamp
extends MapPart

@export_range(0.5, 40.0, 0.1, "or_greater") var run := 6.0:
	set(v): run = maxf(0.1, v); queue_rebuild()
@export_range(0.1, 20.0, 0.1, "or_greater") var rise := 2.0:
	set(v): rise = v; queue_rebuild()
@export_range(0.5, 30.0, 0.1, "or_greater") var width := 4.0:
	set(v): width = v; queue_rebuild()
@export_range(0.1, 3.0, 0.05, "or_greater") var thickness := 0.5:
	set(v): thickness = v; queue_rebuild()

@export_group("Surfaces")
@export var surface: MapMaterials.Surface = MapMaterials.Surface.CONCRETE:
	set(v): surface = v; queue_rebuild()
@export_range(0.05, 4.0, 0.05) var texture_scale := 0.5:
	set(v): texture_scale = v; queue_rebuild()


## Slope in degrees. Above ~50 the player will slide back down.
func get_angle_degrees() -> float:
	return rad_to_deg(atan2(rise, run))


func _build() -> void:
	var angle := atan2(rise, run)
	var length := sqrt(run * run + rise * rise)
	# The slab is centred on the slope, then dropped by half its thickness so
	# the walking surface passes through the origin.
	var center := Vector3(0.0, rise * 0.5, run * 0.5)
	center.y -= cos(angle) * thickness * 0.5
	center.z += sin(angle) * thickness * 0.5
	_box(center, Vector3(width, thickness, length), surface, texture_scale, true,
			Vector3(-rad_to_deg(angle), 0.0, 0.0))
