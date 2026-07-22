## First-person player. Fast, floaty-free, no acceleration ceremony — movement
## is tuned to feel like an early-90s shooter rather than a modern milsim.
##
## Look input comes from two places at once: raw mouse motion (frame-rate
## independent, no smoothing) and the right stick (velocity based, with a
## response curve so small stick deflections stay precise).
class_name Player
extends CharacterBody3D

const GROUP := &"player"

@export_group("Movement")
@export var walk_speed := 8.0
@export var sprint_multiplier := 1.45
@export var crouch_multiplier := 0.45
@export var ground_acceleration := 70.0
@export var air_acceleration := 14.0
@export var ground_friction := 14.0
@export var gravity := 22.0
@export var jump_velocity := 6.5
## Tallest ledge the player can walk straight up without jumping.
@export var step_height := 0.45

@export_group("Look")
@export_range(0.01, 2.0, 0.01) var mouse_sensitivity := 0.25
@export_range(0.5, 8.0, 0.1) var gamepad_sensitivity := 3.2
## Exponent applied to stick deflection. Higher = finer control near centre.
@export_range(1.0, 4.0, 0.1) var gamepad_response := 2.0
@export var invert_look_y := false
@export_range(45.0, 89.9, 0.1) var pitch_limit := 89.0

@export_group("Stature")
@export var stand_height := 1.8
@export var crouch_height := 1.0

@export_group("Vitality")
@export var max_health := 100
@export var max_armor := 100
## Fraction of incoming damage armour soaks while it lasts.
@export_range(0.0, 0.95, 0.05) var armor_absorption := 0.5

@export_group("Feel")
@export var head_bob_amount := 0.055
@export var head_bob_speed := 12.0

@onready var _collision: CollisionShape3D = $Collision
@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D
@onready var _interact_ray: RayCast3D = $Head/Camera3D/InteractRay
@onready var _weapons: WeaponManager = $Weapons

var health := 100
var armor := 0
var is_alive := true

var _active := false
var _yaw := 0.0
var _pitch := 0.0
var _crouching := false
var _head_base_y := 0.0
var _bob_phase := 0.0
var _recoil_pitch := 0.0
var _shake := 0.0
var _capsule: CapsuleShape3D
var _interact_prompt := ""


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = Layers.PLAYER
	collision_mask = Layers.WORLD | Layers.ENEMY

	# Ramps up to ~50 degrees are walkable; snapping keeps us glued to stairs.
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = step_height + 0.1

	# The shape resource is shared by every instance of player.tscn, and crouching
	# mutates its height — without this copy a crouch would persist into the next
	# life after a restart.
	_capsule = (_collision.shape as CapsuleShape3D).duplicate()
	_capsule.height = stand_height
	_collision.shape = _capsule
	_collision.position.y = stand_height * 0.5
	_head_base_y = _head.position.y
	_yaw = rotation.y

	health = max_health
	_interact_ray.collision_mask = Layers.INTERACTABLE

	_weapons.setup(_camera, self)
	Game.player = self
	Game.player_spawned.emit(self)
	_emit_stats()


## Gates all input. Main flips this for pause, death and the level-end screen.
func set_active(value: bool) -> void:
	_active = value
	_weapons.active = value and is_alive
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if value else Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if not _active or not is_alive:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := (event as InputEventMouseMotion).relative
		_add_look(-motion.x * mouse_sensitivity * 0.01, -motion.y * mouse_sensitivity * 0.01)

	if event.is_action_pressed(&"interact"):
		_try_interact()


func _process(delta: float) -> void:
	if _active and is_alive:
		_gamepad_look(delta)
	_update_view(delta)
	_update_interact_prompt()


func _physics_process(delta: float) -> void:
	if not is_alive:
		velocity.x = move_toward(velocity.x, 0.0, ground_friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, ground_friction * delta)
		velocity.y -= gravity * delta
		move_and_slide()
		return

	_update_crouch(delta)

	var on_floor := is_on_floor()
	if not on_floor:
		velocity.y -= gravity * delta
	elif _active and Input.is_action_just_pressed(&"jump") and not _crouching:
		velocity.y = jump_velocity

	var wish := _wish_direction()
	var speed := walk_speed
	if _crouching:
		speed *= crouch_multiplier
	elif _active and Input.is_action_pressed(&"sprint"):
		speed *= sprint_multiplier

	var accel := ground_acceleration if on_floor else air_acceleration
	var target := wish * speed
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)

	if on_floor and wish == Vector3.ZERO:
		velocity.x = move_toward(velocity.x, 0.0, ground_friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, ground_friction * delta)

	_step_up(delta)
	move_and_slide()

	if on_floor:
		_bob_phase += delta * head_bob_speed * clampf(
				Vector2(velocity.x, velocity.z).length() / walk_speed, 0.0, 1.5)


func _wish_direction() -> Vector3:
	if not _active:
		return Vector3.ZERO
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if input == Vector2.ZERO:
		return Vector3.ZERO
	# Clamped rather than normalised so analog sticks keep their fine control.
	if input.length() > 1.0:
		input = input.normalized()
	var basis := global_transform.basis
	return (basis.x * input.x + basis.z * input.y)


## Lifts the body over a low ledge before `move_and_slide` runs, so stairs and
## kerbs don't stop the player dead. Floor snapping settles us back down.
func _step_up(delta: float) -> void:
	if not is_on_floor():
		return
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length_squared() < 0.01:
		return

	var motion := horizontal * delta
	if not test_move(global_transform, motion):
		return  # Path is clear; nothing in the way to step over.

	var lift := Vector3.UP * step_height
	if test_move(global_transform, lift):
		return  # No headroom to rise.
	if test_move(global_transform.translated(lift), motion):
		return  # Still blocked up there — it's a wall, not a step.

	global_position += lift


# --------------------------------------------------------------------- look --

func _gamepad_look(delta: float) -> void:
	var stick := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if stick == Vector2.ZERO:
		return
	# Preserve direction while curving magnitude.
	var magnitude := pow(minf(stick.length(), 1.0), gamepad_response)
	var curved := stick.normalized() * magnitude * gamepad_sensitivity * delta
	_add_look(-curved.x, -curved.y)


func _add_look(yaw_delta: float, pitch_delta: float) -> void:
	_yaw += yaw_delta
	_pitch += pitch_delta * (-1.0 if invert_look_y else 1.0)
	_pitch = clampf(_pitch, deg_to_rad(-pitch_limit), deg_to_rad(pitch_limit))


## Applies yaw/pitch plus the cosmetic layers (recoil, shake, bob) that must
## never feed back into the actual aim angles.
func _update_view(delta: float) -> void:
	rotation.y = _yaw

	_recoil_pitch = move_toward(_recoil_pitch, 0.0, delta * 6.0)
	_shake = move_toward(_shake, 0.0, delta * 2.5)

	_head.rotation.x = _pitch + _recoil_pitch

	var bob_y := sin(_bob_phase) * head_bob_amount
	var bob_x := cos(_bob_phase * 0.5) * head_bob_amount * 0.6
	var target_head_y := _head_base_y * (crouch_height / stand_height) if _crouching else _head_base_y
	_head.position.y = lerpf(_head.position.y, target_head_y + bob_y, delta * 12.0)
	_head.position.x = bob_x

	if _shake > 0.0:
		_camera.position = Vector3(
				randf_range(-_shake, _shake), randf_range(-_shake, _shake), 0.0) * 0.06
	else:
		_camera.position = Vector3.ZERO
	_camera.rotation.z = -bob_x * 0.6


func apply_recoil(degrees: float, shake: float) -> void:
	_recoil_pitch += deg_to_rad(degrees)
	_shake = minf(_shake + shake, 1.0)


# ------------------------------------------------------------------- crouch --

func _update_crouch(_delta: float) -> void:
	var wants := _active and Input.is_action_pressed(&"crouch")
	if wants == _crouching:
		return
	if not wants and not _has_headroom():
		return  # Something above us; stay down.

	_crouching = wants
	var height := crouch_height if wants else stand_height
	_capsule.height = height
	_collision.position.y = height * 0.5


func _has_headroom() -> bool:
	var lift := Vector3.UP * (stand_height - crouch_height)
	return not test_move(global_transform, lift)


# ----------------------------------------------------------------- interact --

func _try_interact() -> void:
	var target := _interact_target()
	if target != null:
		target.interact(self)


## Nearest thing under the crosshair that can be used, or null. Walks up the
## tree so a collision shape parented under an actor still resolves to it.
func _interact_target() -> Node:
	if not _interact_ray.is_colliding():
		return null
	var node := _interact_ray.get_collider() as Node
	while node != null:
		if node.has_method(&"interact"):
			return node
		node = node.get_parent()
	return null


## Publishes what the player could use right now, so the HUD can prompt. Without
## this a `USE` door just looks like a wall.
func _update_interact_prompt() -> void:
	var prompt := ""
	if _active and is_alive:
		var target := _interact_target()
		if target != null:
			prompt = target.get_interact_prompt() if target.has_method(&"get_interact_prompt") \
					else "Use"
	if prompt != _interact_prompt:
		_interact_prompt = prompt
		Game.interact_prompt_changed.emit(prompt)


# ----------------------------------------------------------------- vitality --

func take_damage(amount: float, _hit_position: Vector3, direction: Vector3, _source: Node) -> void:
	if not is_alive:
		return

	var incoming := int(round(amount))
	if armor > 0:
		var soaked := mini(armor, int(incoming * armor_absorption))
		armor -= soaked
		incoming -= soaked

	health = maxi(0, health - incoming)
	_shake = minf(_shake + 0.4, 1.0)
	Game.player_damaged.emit(incoming, direction)
	_emit_stats()

	if health <= 0:
		_die()


func heal(amount: int) -> bool:
	if health >= max_health:
		return false
	health = mini(max_health, health + amount)
	_emit_stats()
	return true


func add_armor(amount: int) -> bool:
	if armor >= max_armor:
		return false
	armor = mini(max_armor, armor + amount)
	_emit_stats()
	return true


func add_ammo(amount: int) -> bool:
	return _weapons.add_ammo(amount)


func get_weapons() -> WeaponManager:
	return _weapons


func _die() -> void:
	is_alive = false
	_weapons.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Drop the view to the floor for the classic death slump.
	var tween := create_tween()
	tween.tween_property(_head, "position:y", 0.35, 0.9).set_trans(Tween.TRANS_CUBIC)
	Game.player_died.emit()


func _emit_stats() -> void:
	Game.player_stats_changed.emit(health, max_health, armor)
