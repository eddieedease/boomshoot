## Sprite-billboard melee enemy — the "grunt".
##
## Deliberately simple: a small state machine, line-of-sight senses, and
## steering that falls back to wall-whiskers when the level has no baked
## navigation mesh. That fallback is what lets a designer drop enemies into a
## brand new room and have them work immediately.
##
## Every tunable is exported, so one scene covers fast weak swarmers and slow
## tanky bruisers without touching code.
class_name Enemy
extends CharacterBody3D

const GROUP := &"enemy"

enum State { IDLE, CHASE, ATTACK, PAIN, DEAD }

@export_group("Vitality")
@export var max_health := 40.0
## Chance an incoming hit interrupts what the enemy was doing.
@export_range(0.0, 1.0, 0.05) var pain_chance := 0.45
@export_range(0.0, 2.0, 0.05) var pain_duration := 0.35
## Hits above this height (relative to the feet) count as headshots.
@export var head_height := 1.25

@export_group("Senses")
@export var sight_range := 30.0
@export_range(10.0, 360.0, 1.0) var sight_fov_degrees := 140.0
## Seconds of lost sight before giving up and returning to idle.
@export var lose_interest_after := 6.0

@export_group("Movement")
@export var chase_speed := 4.2
@export var acceleration := 18.0
@export var turn_speed := 8.0
@export var gravity := 22.0

@export_group("Attack")
@export var attack_range := 2.0
@export var attack_damage := 12.0
## Telegraph before the hit lands, so the player can back off.
@export var attack_windup := 0.35
@export var attack_cooldown := 1.1
## Forward hop when swinging. Makes melee threatening at a distance.
@export var lunge_speed := 6.0

@export_group("Sprites")
@export var sprite_idle: Texture2D
@export var sprite_walk: Array[Texture2D] = []
@export var sprite_attack: Texture2D
@export var sprite_pain: Texture2D
@export var sprite_die: Array[Texture2D] = []
@export var walk_fps := 8.0
@export var death_fps := 9.0

@onready var _sprite: Sprite3D = $Sprite
@onready var _collision: CollisionShape3D = $Collision

var health := 0.0
var state: State = State.IDLE

var _player: Node3D = null
var _last_seen_position := Vector3.ZERO
var _time_since_seen := 999.0
var _state_timer := 0.0
var _attack_timer := 0.0
var _anim_time := 0.0
var _did_swing := false
var _use_navigation := false
var _agent: NavigationAgent3D = null


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = Layers.ENEMY
	collision_mask = Layers.WORLD | Layers.PLAYER
	floor_max_angle = deg_to_rad(55.0)

	health = max_health
	_sprite.texture = sprite_idle
	Game.register_enemy()

	# Navigation is opt-in by discovery: if the level author baked a navmesh we
	# use it, otherwise we steer manually. Deferred so regions have registered.
	_detect_navigation.call_deferred()


func _detect_navigation() -> void:
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_regions(map).is_empty():
		return
	_use_navigation = true
	_agent = NavigationAgent3D.new()
	_agent.radius = 0.5
	_agent.path_desired_distance = 0.6
	_agent.target_desired_distance = attack_range * 0.8
	add_child(_agent)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		_apply_gravity(delta)
		move_and_slide()
		return

	_state_timer = maxf(0.0, _state_timer - delta)
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_anim_time += delta

	_sense(delta)

	match state:
		State.IDLE: _tick_idle(delta)
		State.CHASE: _tick_chase(delta)
		State.ATTACK: _tick_attack(delta)
		State.PAIN: _tick_pain(delta)

	_apply_gravity(delta)
	move_and_slide()
	_face_travel_direction(delta)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta


# -------------------------------------------------------------------- senses --

func _sense(delta: float) -> void:
	_time_since_seen += delta
	if _player == null or not is_instance_valid(_player):
		_player = Game.player
	if _player == null:
		return
	if _can_see_player():
		_time_since_seen = 0.0
		_last_seen_position = _player.global_position


func _can_see_player() -> bool:
	var eye := global_position + Vector3.UP * head_height
	var target := _player.global_position + Vector3.UP * 1.2
	var to_target := target - eye
	if to_target.length() > sight_range:
		return false

	# Enemies that have already been alerted stop caring about facing, which
	# keeps them from losing you by turning a corner.
	if state == State.IDLE:
		var forward := -global_transform.basis.z
		if forward.angle_to(to_target.normalized()) > deg_to_rad(sight_fov_degrees * 0.5):
			return false

	var query := PhysicsRayQueryParameters3D.create(eye, target, Layers.WORLD | Layers.PLAYER)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and (hit.collider as Node).is_in_group(Player.GROUP)


func _distance_to_player() -> float:
	if _player == null:
		return INF
	return global_position.distance_to(_player.global_position)


# -------------------------------------------------------------------- states --

func _tick_idle(delta: float) -> void:
	_decelerate(delta)
	_set_frame(sprite_idle)
	if _time_since_seen < 0.1:
		_enter(State.CHASE)


func _tick_chase(delta: float) -> void:
	if _time_since_seen > lose_interest_after:
		_enter(State.IDLE)
		return

	if _distance_to_player() <= attack_range and _time_since_seen < 0.3 and _attack_timer <= 0.0:
		_enter(State.ATTACK)
		return

	var direction := _steer_towards(_last_seen_position)
	var target := direction * chase_speed
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)
	_animate_walk()


func _tick_attack(delta: float) -> void:
	_set_frame(sprite_attack)

	# Windup, then a single hit, then recovery.
	if not _did_swing and _state_timer <= 0.0:
		_did_swing = true
		_swing()
		_state_timer = attack_cooldown - attack_windup

	if not _did_swing and _player != null:
		# Lunge during the telegraph.
		var direction := (_player.global_position - global_position)
		direction.y = 0.0
		direction = direction.normalized()
		velocity.x = move_toward(velocity.x, direction.x * lunge_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * lunge_speed, acceleration * delta)
	else:
		_decelerate(delta)

	if _did_swing and _state_timer <= 0.0:
		_attack_timer = attack_cooldown
		_enter(State.CHASE)


func _swing() -> void:
	if _player == null or _distance_to_player() > attack_range * 1.35:
		return
	if not _player.has_method(&"take_damage"):
		return
	var direction := (_player.global_position - global_position).normalized()
	_player.take_damage(attack_damage, _player.global_position, direction, self)


func _tick_pain(delta: float) -> void:
	_decelerate(delta)
	_set_frame(sprite_pain)
	if _state_timer <= 0.0:
		_enter(State.CHASE)


func _enter(next: State) -> void:
	state = next
	_did_swing = false
	match next:
		State.ATTACK: _state_timer = attack_windup
		State.PAIN: _state_timer = pain_duration
		_: _state_timer = 0.0


# ------------------------------------------------------------------ steering --

func _steer_towards(target: Vector3) -> Vector3:
	if _use_navigation and _agent != null:
		_agent.target_position = target
		if not _agent.is_navigation_finished():
			var next := _agent.get_next_path_position()
			var to_next := next - global_position
			to_next.y = 0.0
			if to_next.length_squared() > 0.01:
				return to_next.normalized()

	var desired := target - global_position
	desired.y = 0.0
	if desired.length_squared() < 0.01:
		return Vector3.ZERO
	desired = desired.normalized()
	return _avoid_walls(desired)


## Three probe rays. If the path ahead is blocked, slide towards whichever
## shoulder is clear rather than grinding along the wall.
func _avoid_walls(desired: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * 0.9
	var probe := 1.6

	var left := desired.rotated(Vector3.UP, deg_to_rad(38.0))
	var right := desired.rotated(Vector3.UP, deg_to_rad(-38.0))

	var blocked_ahead := _probe(space, origin, desired, probe)
	if not blocked_ahead:
		return desired

	var blocked_left := _probe(space, origin, left, probe)
	var blocked_right := _probe(space, origin, right, probe)

	if blocked_left and blocked_right:
		# Boxed in — pick a side deterministically per-instance so a crowd
		# doesn't all jitter the same way.
		var side := 1.0 if (get_instance_id() % 2) == 0 else -1.0
		return desired.rotated(Vector3.UP, deg_to_rad(90.0) * side)
	if blocked_left:
		return right
	if blocked_right:
		return left
	return left if randf() < 0.5 else right


func _probe(space: PhysicsDirectSpaceState3D, origin: Vector3, direction: Vector3, distance: float) -> bool:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * distance, Layers.WORLD)
	query.exclude = [get_rid()]
	return not space.intersect_ray(query).is_empty()


func _decelerate(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)


func _face_travel_direction(delta: float) -> void:
	var facing := _player.global_position - global_position if _player != null and state != State.IDLE \
			else Vector3(velocity.x, 0.0, velocity.z)
	facing.y = 0.0
	if facing.length_squared() < 0.01:
		return
	var target_yaw := atan2(-facing.x, -facing.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, delta * turn_speed)


# ------------------------------------------------------------------- damage --

## Called by the weapon system, and by anything else that wants to hurt this.
func take_damage(amount: float, _hit_position: Vector3, direction: Vector3, _source: Node) -> void:
	if state == State.DEAD:
		return

	health -= amount
	# Being shot always reveals the shooter's rough position.
	_time_since_seen = 0.0
	if Game.player != null:
		_last_seen_position = Game.player.global_position

	if health <= 0.0:
		_die(direction)
		return

	if state != State.ATTACK and randf() < pain_chance:
		_enter(State.PAIN)
	elif state == State.IDLE:
		_enter(State.CHASE)

	# Small knock so hits read even without an animation change.
	var knock := direction
	knock.y = 0.0
	velocity += knock.normalized() * 2.0


func is_head_hit(point: Vector3) -> bool:
	return point.y >= global_position.y + head_height


func _die(direction: Vector3) -> void:
	state = State.DEAD
	_anim_time = 0.0
	# Corpses stop blocking shots and bodies, but stay visible.
	collision_layer = 0
	collision_mask = Layers.WORLD
	_collision.disabled = true
	velocity = direction.normalized() * 2.0
	Game.notify_enemy_died(self)
	_play_death()


func _play_death() -> void:
	if sprite_die.is_empty():
		return
	for frame in sprite_die:
		_sprite.texture = frame
		await get_tree().create_timer(1.0 / death_fps).timeout
		if not is_instance_valid(self):
			return


# ---------------------------------------------------------------- animation --

func _animate_walk() -> void:
	if sprite_walk.is_empty():
		_set_frame(sprite_idle)
		return
	var moving := Vector2(velocity.x, velocity.z).length() > 0.5
	if not moving:
		_set_frame(sprite_idle)
		return
	var index := int(_anim_time * walk_fps) % sprite_walk.size()
	_set_frame(sprite_walk[index])


func _set_frame(texture: Texture2D) -> void:
	if texture != null and _sprite.texture != texture:
		_sprite.texture = texture
