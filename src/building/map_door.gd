## A sliding door with optional key lock.
##
## Doors are the first place the immersive-sim layer shows up: they can open on
## proximity or require a deliberate Use press, and they can demand a keycard.
## The panel is an AnimatableBody3D so it carries and pushes bodies correctly
## rather than teleporting through them.
##
## Origin sits on the floor at the centre of the closed doorway.
@tool
class_name MapDoor
extends MapPart

enum SlideMode { UP, LEFT, RIGHT }
enum OpenMode {
	PROXIMITY,  ## Opens when the player (or an enemy) walks up to it.
	USE,        ## Requires the interact button.
}

@export var size := Vector3(3.0, 3.0, 0.3):
	set(v): size = v; queue_rebuild()
@export var slide: SlideMode = SlideMode.UP:
	set(v): slide = v; queue_rebuild()
@export var open_mode: OpenMode = OpenMode.PROXIMITY:
	set(v): open_mode = v; queue_rebuild()
## Metres per second the panel travels.
@export_range(0.5, 20.0, 0.1) var speed := 4.0
## Seconds fully open before sliding shut. Zero keeps it open forever.
@export_range(0.0, 30.0, 0.1) var auto_close_delay := 3.0
## Leave empty for an unlocked door, or name a key (e.g. &"red").
@export var required_key: StringName = &""
@export_range(0.5, 8.0, 0.1) var trigger_depth := 2.5:
	set(v): trigger_depth = v; queue_rebuild()

@export_group("Surfaces")
@export var surface: MapMaterials.Surface = MapMaterials.Surface.DOOR:
	set(v): surface = v; queue_rebuild()
@export_range(0.05, 4.0, 0.05) var texture_scale := 0.5:
	set(v): texture_scale = v; queue_rebuild()

var _panel: AnimatableBody3D
var _closed_position := Vector3.ZERO
var _open_offset := Vector3.ZERO
## 0 = shut, 1 = fully open.
var _openness := 0.0
var _want_open := false
var _hold_timer := 0.0
## Bodies inside the trigger volume. A door never closes on someone standing in it.
var _occupants: Array[Node3D] = []


func _build() -> void:
	_openness = 0.0
	_want_open = false
	_occupants.clear()

	_closed_position = Vector3(0.0, size.y * 0.5, 0.0)
	match slide:
		SlideMode.UP: _open_offset = Vector3(0.0, size.y * 0.98, 0.0)
		SlideMode.LEFT: _open_offset = Vector3(-size.x * 0.98, 0.0, 0.0)
		SlideMode.RIGHT: _open_offset = Vector3(size.x * 0.98, 0.0, 0.0)

	_panel = AnimatableBody3D.new()
	_panel.name = "Panel"
	_panel.collision_layer = Layers.WORLD
	_panel.collision_mask = 0
	_panel.sync_to_physics = true
	_panel.position = _closed_position
	_geometry.add_child(_panel)

	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = MapMaterials.get_material(surface, texture_scale)
	_panel.add_child(mi)

	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_panel.add_child(cs)

	if Engine.is_editor_hint():
		return

	var area := Area3D.new()
	area.name = "Trigger"
	area.collision_layer = 0
	area.collision_mask = Layers.PLAYER | Layers.ENEMY
	area.position = Vector3(0.0, size.y * 0.5, 0.0)
	_geometry.add_child(area)

	var trigger_shape := BoxShape3D.new()
	trigger_shape.size = Vector3(size.x + 1.0, size.y, size.z + trigger_depth * 2.0)
	var trigger_cs := CollisionShape3D.new()
	trigger_cs.shape = trigger_shape
	area.add_child(trigger_cs)

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _panel == null:
		return

	if _want_open and _openness >= 1.0 and auto_close_delay > 0.0:
		_hold_timer -= delta
		if _hold_timer <= 0.0 and _occupants.is_empty():
			_want_open = false

	var target := 1.0 if _want_open else 0.0
	if is_equal_approx(_openness, target):
		return

	# Normalise travel by distance so wide and tall doors move at the same pace.
	var travel := maxf(_open_offset.length(), 0.001)
	_openness = move_toward(_openness, target, (speed / travel) * delta)
	_panel.position = _closed_position + _open_offset * _openness


# ---------------------------------------------------------------- triggers --

func _on_body_entered(body: Node3D) -> void:
	if not _occupants.has(body):
		_occupants.append(body)
	if open_mode == OpenMode.PROXIMITY:
		_try_open(body)
	elif _openness > 0.0:
		# Already open — keep it open while someone is in the way.
		_hold_timer = auto_close_delay


func _on_body_exited(body: Node3D) -> void:
	_occupants.erase(body)
	if _want_open and auto_close_delay > 0.0:
		_hold_timer = minf(_hold_timer, auto_close_delay)


## Called by the player's interact ray. Also used by USE-mode doors.
func interact(_user: Node3D) -> bool:
	return _try_open(_user)


func _try_open(user: Node3D) -> bool:
	if _want_open:
		_hold_timer = auto_close_delay
		return true

	var is_player := user != null and user.is_in_group(&"player")
	if required_key != &"" and is_player and not Game.has_key(required_key):
		Game.post_message("The %s keycard is required." % String(required_key).to_upper())
		return false
	# Enemies can't open locked doors at all.
	if required_key != &"" and not is_player:
		return false

	_want_open = true
	_hold_timer = auto_close_delay
	return true


func is_open() -> bool:
	return _openness >= 1.0
