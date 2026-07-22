## Where the player appears. The level's start.
##
## Place exactly one per level. Its -Z axis is the facing direction, matching
## Godot's convention for cameras, so the blue arrow in the editor gizmo points
## where the player will look.
@tool
class_name PlayerStart
extends MapPart

const GROUP := &"player_start"


func _ready() -> void:
	add_to_group(GROUP)
	super()


func _build() -> void:
	# Roughly player-sized so you can eyeball headroom while building.
	_editor_gizmo(Vector3(0.8, 1.8, 0.8), Color(0.3, 0.8, 1.0, 0.35), Vector3(0.0, 0.9, 0.0))
	# A stub pointing down -Z to make the facing unmistakable.
	_editor_gizmo(Vector3(0.15, 0.15, 1.2), Color(0.2, 0.5, 1.0, 0.7), Vector3(0.0, 1.5, -0.7))


## Spawn transform, with any accidental pitch/roll flattened out.
func get_spawn_transform() -> Transform3D:
	var basis_flat := Basis(Vector3.UP, global_rotation.y)
	return Transform3D(basis_flat, global_position)
