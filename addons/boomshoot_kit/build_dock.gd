## The level-building palette.
##
## Click a part and it lands on the ground plane where the 3D viewport camera is
## looking, snapped to the grid, parented to whatever is selected, and wrapped in
## an undo step. That loop — look, click, tweak in the inspector — is the whole
## level editing workflow.
@tool
extends VBoxContainer

## Set by plugin.gd. Needed for `get_undo_redo()`.
var plugin: EditorPlugin

const SNAP_CHOICES: Array[float] = [0.25, 0.5, 1.0, 2.0, 4.0]

## label -> factory. Kept as plain data so adding a new part is a one-line edit.
const GEOMETRY := ["Room", "Block", "Stairs", "Ramp", "Door"]
const GAMEPLAY := ["Player Start", "Level Exit", "Light"]
const PICKUPS := ["Health", "Armor", "Ammo", "Keycard"]
const ENTITIES := ["Grunt"]

const GRUNT_SCENE := "res://src/entities/grunt.tscn"

## Compass directions for Attach Room. `axis` is the direction to grow in,
## `depth` says whether that direction measures the room's Z (true) or X.
const ATTACH := {
	"North": {"axis": Vector3(0, 0, -1), "source_wall": &"wall_north", "new_wall": &"wall_south", "depth": true},
	"South": {"axis": Vector3(0, 0, 1), "source_wall": &"wall_south", "new_wall": &"wall_north", "depth": true},
	"West": {"axis": Vector3(-1, 0, 0), "source_wall": &"wall_west", "new_wall": &"wall_east", "depth": false},
	"East": {"axis": Vector3(1, 0, 0), "source_wall": &"wall_east", "new_wall": &"wall_west", "depth": false},
}

var _snap := 1.0
var _snap_button: OptionButton
var _status: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_build_ui()


# ----------------------------------------------------------------------- ui --

func _build_ui() -> void:
	var title := Label.new()
	title.text = "BOOMSHOOT KIT"
	title.add_theme_font_size_override("font_size", 15)
	add_child(title)

	var hint := Label.new()
	hint.text = "Parts drop where the 3D view is aimed."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	hint.add_theme_font_size_override("font_size", 11)
	add_child(hint)

	# --- grid snap ---
	var snap_row := HBoxContainer.new()
	add_child(snap_row)

	var snap_label := Label.new()
	snap_label.text = "Grid"
	snap_row.add_child(snap_label)

	_snap_button = OptionButton.new()
	_snap_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for value in SNAP_CHOICES:
		_snap_button.add_item("%.2f m" % value)
	_snap_button.selected = SNAP_CHOICES.find(1.0)
	_snap_button.item_selected.connect(func(index: int) -> void: _snap = SNAP_CHOICES[index])
	snap_row.add_child(_snap_button)

	_section("Geometry", GEOMETRY)
	_attach_section()
	_section("Gameplay", GAMEPLAY)
	_section("Pickups", PICKUPS)
	_section("Entities", ENTITIES)

	add_child(HSeparator.new())

	var snap_selected := Button.new()
	snap_selected.text = "Snap Selection to Grid"
	snap_selected.pressed.connect(_snap_selection)
	add_child(snap_selected)

	var rebuild := Button.new()
	rebuild.text = "Rebuild All Parts"
	rebuild.tooltip_text = "Regenerates every MapPart in the open scene. Use after editing textures or part scripts."
	rebuild.pressed.connect(_rebuild_all)
	add_child(rebuild)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", Color(0.55, 0.75, 0.55))
	add_child(_status)


## The fastest way to grow a level: pick a room, pick a compass direction, get a
## correctly aligned neighbour with the doorway already cut. No arithmetic.
func _attach_section() -> void:
	add_child(HSeparator.new())

	var label := Label.new()
	label.text = "Attach Room to Selection"
	label.add_theme_color_override("font_color", Color(0.95, 0.72, 0.35))
	add_child(label)

	var hint := Label.new()
	hint.text = "Butts a new room onto the selected room and cuts a doorway."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	hint.add_theme_font_size_override("font_size", 11)
	add_child(hint)

	var grid := GridContainer.new()
	grid.columns = 2
	add_child(grid)

	for direction: String in ATTACH:
		var button := Button.new()
		button.text = direction
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_attach_room.bind(direction))
		grid.add_child(button)


func _section(heading: String, entries: Array) -> void:
	add_child(HSeparator.new())

	var label := Label.new()
	label.text = heading
	label.add_theme_color_override("font_color", Color(0.95, 0.72, 0.35))
	add_child(label)

	var grid := GridContainer.new()
	grid.columns = 2
	add_child(grid)

	for entry: String in entries:
		var button := Button.new()
		button.text = entry
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_place.bind(entry))
		grid.add_child(button)


# ------------------------------------------------------------------ placing --

func _place(kind: String) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_report("Open a level scene first.", false)
		return

	var node := _make(kind)
	if node == null:
		_report("Don't know how to build '%s'." % kind, false)
		return

	var parent := _pick_parent(root)
	node.name = kind.replace(" ", "")

	if node is Node3D:
		var target := _drop_point()
		var local := target
		if parent is Node3D:
			local = (parent as Node3D).global_transform.affine_inverse() * target
		(node as Node3D).position = local.snappedf(_snap)

	var undo := plugin.get_undo_redo()
	undo.create_action("Place %s" % kind)
	undo.add_do_method(parent, &"add_child", node, true)
	undo.add_do_method(node, &"set_owner", root)
	undo.add_do_reference(node)
	undo.add_undo_method(parent, &"remove_child", node)
	undo.commit_action()

	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(node)
	_report("Placed %s under %s." % [kind, parent.name], true)


## New nodes go under the current selection, matching how the editor's own Add
## Node button behaves. Falls back to the scene root.
func _pick_parent(root: Node) -> Node:
	var selected := EditorInterface.get_selection().get_selected_nodes()
	if selected.is_empty():
		return root
	var candidate: Node = selected[0]
	if candidate == root or root.is_ancestor_of(candidate):
		return candidate
	return root


## Where the 3D viewport camera is looking, projected onto the ground plane so
## parts land at floor level instead of floating in mid-air.
func _drop_point() -> Vector3:
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var camera := viewport.get_camera_3d() if viewport != null else null
	if camera == null:
		return Vector3.ZERO

	var origin := camera.global_position
	var forward := -camera.global_transform.basis.z

	# Intersect with y = 0. Near-horizontal views have no useful intersection,
	# so drop the part a fixed distance ahead instead.
	if forward.y < -0.05:
		var distance := -origin.y / forward.y
		if distance > 0.0 and distance < 500.0:
			return origin + forward * distance
	return origin + forward * 10.0


func _make(kind: String) -> Node:
	match kind:
		"Room": return MapRoom.new()
		"Block": return MapBlock.new()
		"Stairs": return MapStairs.new()
		"Ramp": return MapRamp.new()
		"Door": return MapDoor.new()
		"Player Start": return PlayerStart.new()
		"Level Exit": return LevelExit.new()
		"Light": return MapLight.new()
		"Health": return _pickup(Pickup.Kind.HEALTH, 25)
		"Armor": return _pickup(Pickup.Kind.ARMOR, 50)
		"Ammo": return _pickup(Pickup.Kind.AMMO, 24)
		"Keycard": return _pickup(Pickup.Kind.KEY, 1)
		"Grunt": return _instantiate(GRUNT_SCENE)
	return null


func _pickup(kind: Pickup.Kind, amount: int) -> Pickup:
	var pickup := Pickup.new()
	pickup.kind = kind
	pickup.amount = amount
	# Pickups read better floating at chest height.
	pickup.position = Vector3(0.0, 0.9, 0.0)
	return pickup


func _instantiate(path: String) -> Node:
	if not ResourceLoader.exists(path):
		return null
	return (load(path) as PackedScene).instantiate()


## Creates a neighbour that shares the selected room's style and proportions,
## positioned so their outer faces touch exactly, with the shared wall set to
## DOORWAY on the source and OPEN on the new room.
##
## Getting that seam right by hand is the tedious part of building with brushes,
## and it is pure arithmetic — so the tool does it.
func _attach_room(direction: String) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_report("Open a level scene first.", false)
		return

	var source: MapRoom = null
	for node in EditorInterface.get_selection().get_selected_nodes():
		if node is MapRoom:
			source = node as MapRoom
			break
	if source == null:
		_report("Select a Room first — Attach grows outwards from it.", false)
		return

	var spec: Dictionary = ATTACH[direction]

	var room := MapRoom.new()
	room.size = source.size
	room.wall_thickness = source.wall_thickness
	room.wall_surface = source.wall_surface
	room.floor_surface = source.floor_surface
	room.ceiling_surface = source.ceiling_surface
	room.texture_scale = source.texture_scale
	room.doorway_width = source.doorway_width
	room.doorway_height = source.doorway_height
	room.set(spec["new_wall"], MapRoom.WallMode.OPEN)
	room.name = "Room"

	# Half of each room along the shared axis, plus the wall band between them.
	var depth: bool = spec["depth"]
	var source_half: float = (source.size.z if depth else source.size.x) * 0.5
	var new_half: float = (room.size.z if depth else room.size.x) * 0.5
	var distance := source_half + source.wall_thickness + new_half

	var axis: Vector3 = spec["axis"]
	# Rotated through the source's own basis so attaching to an angled room works.
	room.position = source.position + source.transform.basis * (axis * distance)
	room.rotation = source.rotation

	var parent := source.get_parent()
	var wall_property: StringName = spec["source_wall"]
	var previous_wall: int = source.get(wall_property)

	var undo := plugin.get_undo_redo()
	undo.create_action("Attach Room %s" % direction)
	undo.add_do_method(parent, &"add_child", room, true)
	undo.add_do_method(room, &"set_owner", root)
	undo.add_do_reference(room)
	undo.add_do_property(source, wall_property, MapRoom.WallMode.DOORWAY)
	undo.add_undo_property(source, wall_property, previous_wall)
	undo.add_undo_method(parent, &"remove_child", room)
	undo.commit_action()

	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(room)
	_report("Attached a room to the %s with a doorway." % direction.to_lower(), true)


# ------------------------------------------------------------------ actions --

func _snap_selection() -> void:
	var nodes := EditorInterface.get_selection().get_selected_nodes()
	var undo := plugin.get_undo_redo()
	undo.create_action("Snap to Grid")
	var count := 0
	for node in nodes:
		if not node is Node3D:
			continue
		var node_3d := node as Node3D
		undo.add_do_property(node_3d, &"position", node_3d.position.snappedf(_snap))
		undo.add_undo_property(node_3d, &"position", node_3d.position)
		count += 1
	undo.commit_action()
	_report("Snapped %d node(s) to %.2f m." % [count, _snap], count > 0)


func _rebuild_all() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_report("Open a level scene first.", false)
		return
	MapMaterials.clear_cache()
	var count := 0
	for node in root.find_children("*", "", true, false):
		if node is MapPart:
			(node as MapPart).rebuild()
			count += 1
	_report("Rebuilt %d part(s)." % count, true)


func _report(message: String, good: bool) -> void:
	_status.text = message
	_status.add_theme_color_override("font_color",
			Color(0.55, 0.75, 0.55) if good else Color(0.9, 0.5, 0.45))
