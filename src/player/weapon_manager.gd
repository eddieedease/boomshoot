## Owns the player's guns: firing, ammo, reloading and switching.
##
## Shots are hitscan — a ray from the centre of the camera, which is what makes
## old-school shooters feel instant. Damage is delivered through a duck-typed
## `take_damage` call so anything in the world can be made shootable without
## inheriting from a common base.
class_name WeaponManager
extends Node

@export var weapons: Array[WeaponData] = []

## Set false while dead, paused or in a menu.
var active := false

var _camera: Camera3D
var _owner_body: CharacterBody3D
var _index := -1
var _in_mag: Array[int] = []
var _reserve: Array[int] = []
var _cooldown := 0.0
var _reload_remaining := 0.0
var _bloom := 0.0
var _trigger_held := false


func setup(camera: Camera3D, owner_body: CharacterBody3D) -> void:
	_camera = camera
	_owner_body = owner_body
	_in_mag.clear()
	_reserve.clear()
	for w in weapons:
		_in_mag.append(w.mag_size)
		_reserve.append(mini(w.reserve_start, w.reserve_max))
	if not weapons.is_empty():
		switch_to(0)


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	# Accuracy recovers quickly once the trigger is released.
	_bloom = maxf(0.0, _bloom - delta * (1.5 if _trigger_held else 6.0))

	if _reload_remaining > 0.0:
		_reload_remaining -= delta
		if _reload_remaining <= 0.0:
			_finish_reload()

	if not active:
		_trigger_held = false
		return

	if Input.is_action_just_pressed(&"weapon_next"):
		_cycle(1)
	elif Input.is_action_just_pressed(&"weapon_prev"):
		_cycle(-1)
	if Input.is_action_just_pressed(&"reload"):
		start_reload()

	var weapon := get_current()
	if weapon == null:
		return

	var wants_fire := Input.is_action_pressed(&"fire") if weapon.automatic \
			else Input.is_action_just_pressed(&"fire")
	_trigger_held = Input.is_action_pressed(&"fire")
	if wants_fire:
		_try_fire(weapon)


# ------------------------------------------------------------------ queries --

func get_current() -> WeaponData:
	if _index < 0 or _index >= weapons.size():
		return null
	return weapons[_index]


func get_in_mag() -> int:
	return _in_mag[_index] if _index >= 0 else 0


func get_reserve() -> int:
	return _reserve[_index] if _index >= 0 else 0


func is_reloading() -> bool:
	return _reload_remaining > 0.0


# ----------------------------------------------------------------- switching --

func switch_to(index: int) -> void:
	if index < 0 or index >= weapons.size() or index == _index:
		return
	_index = index
	_reload_remaining = 0.0
	_bloom = 0.0
	Game.weapon_changed.emit(weapons[_index])
	_emit_ammo()


func _cycle(step: int) -> void:
	if weapons.size() < 2:
		return
	switch_to(wrapi(_index + step, 0, weapons.size()))


# ------------------------------------------------------------------- firing --

func _try_fire(weapon: WeaponData) -> void:
	if _cooldown > 0.0 or is_reloading():
		return

	if weapon.uses_ammo() and _in_mag[_index] <= 0:
		if _reserve[_index] > 0:
			start_reload()
		else:
			Game.post_message("Out of ammo", 1.0)
			Sfx.play_ui(Sfx.DRY_FIRE, -6.0)
			_cooldown = 0.4
		return

	if weapon.uses_ammo():
		_in_mag[_index] -= 1
		_emit_ammo()

	_cooldown = weapon.get_shot_interval()
	_bloom = minf(_bloom + weapon.spread_bloom, weapon.spread_bloom * 3.0)

	for i in weapon.pellets:
		_trace(weapon)

	Sfx.play_ui(Sfx.PISTOL_SHOT, -3.0, 0.06)
	Game.weapon_fired.emit()
	if _owner_body != null and _owner_body.has_method("apply_recoil"):
		_owner_body.apply_recoil(weapon.recoil_kick, weapon.screen_shake)


func _trace(weapon: WeaponData) -> void:
	if _camera == null:
		return

	var origin := _camera.global_position
	var direction := _spread_direction(weapon)

	var query := PhysicsRayQueryParameters3D.create(
			origin, origin + direction * weapon.range_metres, Layers.SHOOTABLE)
	query.exclude = [_owner_body.get_rid()] if _owner_body != null else []
	query.collide_with_areas = false

	var hit := _camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return

	var collider := hit.collider as Node
	var point: Vector3 = hit.position
	var normal: Vector3 = hit.normal

	var target := _find_damageable(collider)
	if target == null:
		Fx.spawn_impact(_owner_body, point, normal)
		return

	var amount := weapon.damage
	if target.has_method(&"is_head_hit") and target.is_head_hit(point):
		amount *= weapon.headshot_multiplier
	target.take_damage(amount, point, direction, _owner_body)
	Fx.spawn_blood(_owner_body, point, -direction)


## Walks up from the collider so damage still lands when the shape belongs to a
## child node of the actual actor.
func _find_damageable(node: Node) -> Node:
	var current := node
	while current != null:
		if current.has_method(&"take_damage"):
			return current
		current = current.get_parent()
	return null


func _spread_direction(weapon: WeaponData) -> Vector3:
	var forward := -_camera.global_transform.basis.z
	var cone := deg_to_rad(weapon.spread_degrees + _bloom)
	if cone <= 0.0:
		return forward
	# Uniform disc sample keeps pellets from clumping in the middle.
	var angle := randf() * TAU
	var radius := sqrt(randf()) * cone
	var basis := _camera.global_transform.basis
	return (forward + basis.x * sin(angle) * radius + basis.y * cos(angle) * radius).normalized()


# ------------------------------------------------------------------ reloads --

func start_reload() -> void:
	var weapon := get_current()
	if weapon == null or not weapon.uses_ammo() or is_reloading():
		return
	if _in_mag[_index] >= weapon.mag_size or _reserve[_index] <= 0:
		return
	_reload_remaining = weapon.reload_time
	Sfx.play_ui(Sfx.RELOAD, -6.0)
	Game.weapon_reload_started.emit(weapon.reload_time)


func _finish_reload() -> void:
	var weapon := get_current()
	if weapon == null:
		return
	var needed := weapon.mag_size - _in_mag[_index]
	var taken := mini(needed, _reserve[_index])
	_in_mag[_index] += taken
	_reserve[_index] -= taken
	_emit_ammo()


# --------------------------------------------------------------------- ammo --

## Returns true if any of it fit, so pickups can refuse to disappear when full.
func add_ammo(amount: int, weapon_index: int = -1) -> bool:
	var idx := weapon_index if weapon_index >= 0 else _index
	if idx < 0 or idx >= weapons.size():
		return false
	var weapon := weapons[idx]
	if _reserve[idx] >= weapon.reserve_max:
		return false
	_reserve[idx] = mini(_reserve[idx] + amount, weapon.reserve_max)
	if idx == _index:
		_emit_ammo()
	return true


func _emit_ammo() -> void:
	Game.ammo_changed.emit(get_in_mag(), get_reserve())
