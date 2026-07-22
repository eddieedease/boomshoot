## A single textured box: pillars, crates, ledges, platforms, plugs for holes.
##
## Origin is at the block's centre by default; flip `origin_at_base` to make it
## sit on the floor, which is usually what you want when placing platforms.
@tool
class_name MapBlock
extends MapPart

@export var size := Vector3(2.0, 2.0, 2.0):
	set(v): size = v; queue_rebuild()
@export var origin_at_base := true:
	set(v): origin_at_base = v; queue_rebuild()
@export var solid := true:
	set(v): solid = v; queue_rebuild()

@export_group("Surfaces")
@export var surface: MapMaterials.Surface = MapMaterials.Surface.TECH:
	set(v): surface = v; queue_rebuild()
@export_range(0.05, 4.0, 0.05) var texture_scale := 0.5:
	set(v): texture_scale = v; queue_rebuild()


func _build() -> void:
	var center := Vector3(0.0, size.y * 0.5, 0.0) if origin_at_base else Vector3.ZERO
	_box(center, size, surface, texture_scale, solid)
