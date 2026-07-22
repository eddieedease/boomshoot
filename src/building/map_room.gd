## A hollow room: floor, ceiling and four walls, each independently solid, open
## or pierced by a doorway.
##
## This is the workhorse part. Rooms are meant to be butted against each other
## with matching doorways to form a level — set the shared wall to DOORWAY on
## one room and OPEN on its neighbour so the geometry doesn't z-fight.
##
## Origin sits at the centre of the floor, so a room's Y position is the floor
## height. Interior spans ±size.x/2, ±size.z/2 and 0..size.y.
@tool
class_name MapRoom
extends MapPart

enum WallMode {
	SOLID,    ## Full wall.
	OPEN,     ## No wall at all.
	DOORWAY,  ## Wall with a centred gap.
}

@export var size := Vector3(12.0, 4.0, 12.0):
	set(v): size = v; queue_rebuild()
@export_range(0.1, 4.0, 0.05, "or_greater") var wall_thickness := 0.5:
	set(v): wall_thickness = v; queue_rebuild()
@export var build_floor := true:
	set(v): build_floor = v; queue_rebuild()
@export var build_ceiling := true:
	set(v): build_ceiling = v; queue_rebuild()

@export_group("Walls")
@export var wall_north: WallMode = WallMode.SOLID:
	set(v): wall_north = v; queue_rebuild()
@export var wall_south: WallMode = WallMode.SOLID:
	set(v): wall_south = v; queue_rebuild()
@export var wall_east: WallMode = WallMode.SOLID:
	set(v): wall_east = v; queue_rebuild()
@export var wall_west: WallMode = WallMode.SOLID:
	set(v): wall_west = v; queue_rebuild()
@export_range(0.5, 20.0, 0.1, "or_greater") var doorway_width := 3.0:
	set(v): doorway_width = v; queue_rebuild()
@export_range(0.5, 20.0, 0.1, "or_greater") var doorway_height := 3.0:
	set(v): doorway_height = v; queue_rebuild()

@export_group("Surfaces")
@export var wall_surface: MapMaterials.Surface = MapMaterials.Surface.BRICK:
	set(v): wall_surface = v; queue_rebuild()
@export var floor_surface: MapMaterials.Surface = MapMaterials.Surface.CONCRETE:
	set(v): floor_surface = v; queue_rebuild()
@export var ceiling_surface: MapMaterials.Surface = MapMaterials.Surface.CEILING:
	set(v): ceiling_surface = v; queue_rebuild()
## Texture repeats per metre. Lower = chunkier.
@export_range(0.05, 4.0, 0.05) var texture_scale := 0.5:
	set(v): texture_scale = v; queue_rebuild()


func _build() -> void:
	var t := wall_thickness
	var half := Vector3(size.x * 0.5, 0.0, size.z * 0.5)
	# Slabs overhang by the wall thickness so corners close cleanly.
	var slab := Vector3(size.x + t * 2.0, t, size.z + t * 2.0)

	if build_floor:
		_box(Vector3(0.0, -t * 0.5, 0.0), slab, floor_surface, texture_scale)
	if build_ceiling:
		_box(Vector3(0.0, size.y + t * 0.5, 0.0), slab, ceiling_surface, texture_scale)

	# North/south run along X; east/west run along Z.
	_wall(wall_north, Vector3(0.0, 0.0, -(half.z + t * 0.5)), size.x + t * 2.0, true)
	_wall(wall_south, Vector3(0.0, 0.0, half.z + t * 0.5), size.x + t * 2.0, true)
	_wall(wall_west, Vector3(-(half.x + t * 0.5), 0.0, 0.0), size.z, false)
	_wall(wall_east, Vector3(half.x + t * 0.5, 0.0, 0.0), size.z, false)


## `span` is the wall's length; `along_x` picks which axis it runs down.
func _wall(mode: WallMode, base: Vector3, span: float, along_x: bool) -> void:
	if mode == WallMode.OPEN:
		return

	var t := wall_thickness
	var h := size.y

	if mode == WallMode.SOLID:
		var full := Vector3(span, h, t) if along_x else Vector3(t, h, span)
		_box(base + Vector3(0.0, h * 0.5, 0.0), full, wall_surface, texture_scale)
		return

	# DOORWAY: two side segments plus a header above the gap.
	var gap := minf(doorway_width, span)
	var gap_h := minf(doorway_height, h)
	var side := (span - gap) * 0.5

	if side > 0.001:
		for dir: float in [-1.0, 1.0]:
			var offset := dir * (gap + side) * 0.5
			var pos := base + Vector3(offset if along_x else 0.0, h * 0.5, 0.0 if along_x else offset)
			var seg := Vector3(side, h, t) if along_x else Vector3(t, h, side)
			_box(pos, seg, wall_surface, texture_scale)

	var header := h - gap_h
	if header > 0.001:
		var pos := base + Vector3(0.0, gap_h + header * 0.5, 0.0)
		var seg := Vector3(gap, header, t) if along_x else Vector3(t, header, gap)
		_box(pos, seg, wall_surface, texture_scale)
