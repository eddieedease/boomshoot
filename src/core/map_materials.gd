## Shared surface materials for level geometry.
##
## Every surface uses world-space triplanar mapping, which is what makes the
## box-brush workflow practical: texel density stays identical no matter how a
## part is scaled or rotated, and textures line up across neighbouring parts
## without anyone touching a UV.
@tool
class_name MapMaterials
extends Object

enum Surface {
	BRICK,
	TECH,
	STONE,
	CONCRETE,
	GRATE,
	CEILING,
	DOOR,
	EXIT,
	HAZARD,
}

const TEXTURES := {
	Surface.BRICK: "res://assets/textures/wall_brick.png",
	Surface.TECH: "res://assets/textures/wall_tech.png",
	Surface.STONE: "res://assets/textures/wall_stone.png",
	Surface.CONCRETE: "res://assets/textures/floor_concrete.png",
	Surface.GRATE: "res://assets/textures/floor_grate.png",
	Surface.CEILING: "res://assets/textures/ceiling_panel.png",
	Surface.DOOR: "res://assets/textures/door_metal.png",
	Surface.EXIT: "res://assets/textures/exit_glow.png",
	Surface.HAZARD: "res://assets/textures/hazard.png",
}

## Surfaces that glow so they stay readable from across a dark room.
const EMISSIVE := {
	Surface.EXIT: 0.9,
	Surface.HAZARD: 0.18,
}

static var _cache: Dictionary = {}


## `uv_scale` is texture repeats per metre — 0.5 means the 64px tile covers 2m.
static func get_material(surface: Surface, uv_scale: float) -> StandardMaterial3D:
	var key := "%d|%.4f" % [surface, uv_scale]
	var cached: StandardMaterial3D = _cache.get(key)
	if cached != null:
		return cached

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(TEXTURES[surface])
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE * uv_scale
	# Flat, matte surfaces — specular highlights read as "modern" and fight the
	# chunky texture work.
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	if EMISSIVE.has(surface):
		mat.emission_enabled = true
		mat.emission = Color.WHITE
		mat.emission_texture = mat.albedo_texture
		mat.emission_energy_multiplier = EMISSIVE[surface]

	_cache[key] = mat
	return mat


## Dropped when the editor plugin reloads so texture edits show up immediately.
static func clear_cache() -> void:
	_cache.clear()
