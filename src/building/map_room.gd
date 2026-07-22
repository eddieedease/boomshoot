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


## The room occupies exactly its interior plus a wall band on each side that has
## a wall. Butt two rooms so their *outer* faces touch and nothing overlaps.
func _build() -> void:
	var t := wall_thickness
	var hx := size.x * 0.5
	var hz := size.z * 0.5

	# Slabs cover the interior only — they deliberately do NOT overhang under
	# the walls. Overhanging makes neighbouring rooms share a coplanar upward
	# face in the seam, which is exactly what makes floors flicker. Each wall
	# carries its own sill instead, so doorways still have something to walk on.
	if build_floor:
		_box(Vector3(0.0, -t * 0.5, 0.0), Vector3(size.x, t, size.z), floor_surface, texture_scale)
	if build_ceiling:
		_box(Vector3(0.0, size.y + t * 0.5, 0.0), Vector3(size.x, t, size.z),
				ceiling_surface, texture_scale)

	# North/south walls run along X and stretch out to close the corners — but
	# only towards a side that actually has a wall to meet. Stretching towards an
	# OPEN side would push geometry into the neighbouring room.
	var west_ext := t if wall_west != WallMode.OPEN else 0.0
	var east_ext := t if wall_east != WallMode.OPEN else 0.0
	_wall(wall_north, -(hz + t * 0.5), true, -hx - west_ext, hx + east_ext)
	_wall(wall_south, hz + t * 0.5, true, -hx - west_ext, hx + east_ext)
	# East/west walls span the interior only; the corners are already covered.
	_wall(wall_west, -(hx + t * 0.5), false, -hz, hz)
	_wall(wall_east, hx + t * 0.5, false, -hz, hz)


## Builds one wall. `offset` is its position along its own normal, `along_x`
## picks the axis it runs down, and `min_a`/`max_a` are its extents on that axis.
func _wall(mode: WallMode, offset: float, along_x: bool, min_a: float, max_a: float) -> void:
	if mode == WallMode.OPEN:
		return

	var t := wall_thickness
	var span := max_a - min_a
	if span <= 0.001:
		return

	# Walls run from under the floor to above the ceiling so the seams close.
	var bottom := -t if build_floor else 0.0
	var top := size.y + (t if build_ceiling else 0.0)

	if mode == WallMode.SOLID:
		_segment(offset, along_x, (min_a + max_a) * 0.5, span, bottom, top)
		return

	# DOORWAY: a sill under the opening, a jamb either side, and a header above.
	# The gap stays centred on the room's interior, not on the stretched wall.
	var gap := minf(doorway_width, span)
	var gap_h := minf(doorway_height, size.y)

	if bottom < 0.0:
		_segment(offset, along_x, (min_a + max_a) * 0.5, span, bottom, 0.0)

	var left := -gap * 0.5 - min_a
	if left > 0.001:
		_segment(offset, along_x, min_a + left * 0.5, left, 0.0, top)

	var right := max_a - gap * 0.5
	if right > 0.001:
		_segment(offset, along_x, max_a - right * 0.5, right, 0.0, top)

	if top - gap_h > 0.001:
		_segment(offset, along_x, 0.0, gap, gap_h, top)


func _segment(offset: float, along_x: bool, center: float, length: float,
		y_bottom: float, y_top: float) -> void:
	var height := y_top - y_bottom
	if height <= 0.001 or length <= 0.001:
		return
	var t := wall_thickness
	var mid_y := (y_bottom + y_top) * 0.5
	var position := Vector3(center, mid_y, offset) if along_x else Vector3(offset, mid_y, center)
	var box := Vector3(length, height, t) if along_x else Vector3(t, height, length)
	_box(position, box, wall_surface, texture_scale)
