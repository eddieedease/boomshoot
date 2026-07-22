## Throwaway hit effects, built in code so there are no effect scenes to keep
## in sync. Each burst frees itself when its tween finishes.
class_name Fx
extends Object

const SPARK_COLOR := Color(1.0, 0.85, 0.4)
const BLOOD_COLOR := Color(0.75, 0.08, 0.08)


## Puff of debris at a hit point. `normal` aims the spray back at the shooter.
static func spawn_impact(parent: Node, position: Vector3, normal: Vector3, color: Color = SPARK_COLOR) -> void:
	if not is_instance_valid(parent):
		return

	var root := Node3D.new()
	root.top_level = true
	parent.add_child(root)
	root.global_position = position

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.09
	flash_mesh.height = 0.18
	flash_mesh.radial_segments = 6
	flash_mesh.rings = 3

	var flash := MeshInstance3D.new()
	flash.mesh = flash_mesh
	flash.material_override = mat
	root.add_child(flash)

	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.03, 0.03, 0.12)

	var tween := root.create_tween()
	tween.set_parallel(true)

	for i in 5:
		var spark := MeshInstance3D.new()
		spark.mesh = spark_mesh
		spark.material_override = mat
		root.add_child(spark)
		# Scatter around the surface normal so debris flies off the wall.
		var dir := (normal + Vector3(randf_range(-0.9, 0.9), randf_range(-0.5, 0.9), randf_range(-0.9, 0.9))).normalized()
		spark.look_at_from_position(Vector3.ZERO, dir, Vector3.UP, true)
		tween.tween_property(spark, "position", dir * randf_range(0.3, 0.8), 0.22)
		tween.tween_property(spark, "scale", Vector3.ZERO, 0.22)

	tween.tween_property(flash, "scale", Vector3.ZERO, 0.12)
	tween.chain().tween_callback(root.queue_free)


static func spawn_blood(parent: Node, position: Vector3, normal: Vector3) -> void:
	spawn_impact(parent, position, normal, BLOOD_COLOR)
