## A light fixture with an optional flicker, plus a small emissive housing so
## the source is visible in the room rather than being a floating glow.
@tool
class_name MapLight
extends MapPart

@export var color := Color(1.0, 0.86, 0.66):
	set(v): color = v; queue_rebuild()
@export_range(0.0, 32.0, 0.1, "or_greater") var energy := 3.0:
	set(v): energy = v; queue_rebuild()
@export_range(0.5, 60.0, 0.1, "or_greater") var range_metres := 12.0:
	set(v): range_metres = v; queue_rebuild()
@export var cast_shadows := true:
	set(v): cast_shadows = v; queue_rebuild()
@export var show_fixture := true:
	set(v): show_fixture = v; queue_rebuild()

@export_group("Flicker")
## 0 disables flicker. Higher values dip the light harder.
@export_range(0.0, 1.0, 0.01) var flicker_amount := 0.0
@export_range(0.1, 30.0, 0.1) var flicker_speed := 8.0

var _light: OmniLight3D
var _phase := 0.0


func _build() -> void:
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = energy
	_light.omni_range = range_metres
	_light.shadow_enabled = cast_shadows
	# Softer falloff reads closer to the flat pools of light in early shooters.
	_light.omni_attenuation = 0.8
	_geometry.add_child(_light)

	if show_fixture:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 2.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.5, 0.12, 0.5)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		_geometry.add_child(mi)

	_phase = randf() * TAU


func _process(delta: float) -> void:
	if _light == null or flicker_amount <= 0.0 or Engine.is_editor_hint():
		return
	_phase += delta * flicker_speed
	# Two out-of-step sines beat against each other, which avoids the obvious
	# metronome look of a single wave.
	var wave := sin(_phase) * 0.6 + sin(_phase * 2.37) * 0.4
	_light.light_energy = energy * (1.0 - flicker_amount * (0.5 - wave * 0.5))
