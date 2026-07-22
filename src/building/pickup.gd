## Floating collectable: health, armour, ammo or a keycard.
##
## Runs as a @tool so the icon updates in the editor the moment you change the
## kind — you can see what a room contains without pressing play.
@tool
class_name Pickup
extends Area3D

enum Kind { HEALTH, ARMOR, AMMO, KEY }

const ICONS := {
	Kind.HEALTH: "res://assets/sprites/pickup_health.png",
	Kind.ARMOR: "res://assets/sprites/pickup_armor.png",
	Kind.AMMO: "res://assets/sprites/pickup_ammo.png",
	Kind.KEY: "res://assets/sprites/pickup_key.png",
}

## Keycards are one white sprite tinted per colour, so adding a new key is a
## one-line change here rather than new art.
const KEY_COLORS := {
	&"red": Color(1.0, 0.3, 0.3),
	&"blue": Color(0.4, 0.6, 1.0),
	&"yellow": Color(1.0, 0.9, 0.35),
}

@export var kind: Kind = Kind.HEALTH:
	set(v): kind = v; _rebuild_deferred()
@export_range(1, 500, 1) var amount := 25
@export var key_id: StringName = &"red":
	set(v): key_id = v; _rebuild_deferred()
## Seconds until it comes back. 0 = gone for good.
@export_range(0.0, 120.0, 1.0) var respawn_seconds := 0.0
@export var bob_height := 0.12
@export var spin_speed := 1.6

var _sprite: Sprite3D
var _light: OmniLight3D
var _base_y := 0.0
var _phase := 0.0
var _taken := false
var _queued := false


func _ready() -> void:
	_base_y = position.y
	_phase = randf() * TAU
	collision_layer = Layers.PICKUP
	collision_mask = Layers.PLAYER
	monitoring = not Engine.is_editor_hint()
	_rebuild()
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)


func _rebuild_deferred() -> void:
	if not is_node_ready() or _queued:
		return
	_queued = true
	(func() -> void: _queued = false; _rebuild()).call_deferred()


func _rebuild() -> void:
	for child in get_children():
		if child.owner == null:
			remove_child(child)
			child.queue_free()

	var tint := _tint()

	_sprite = Sprite3D.new()
	_sprite.texture = load(ICONS[kind])
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.shaded = false
	_sprite.pixel_size = 0.022
	_sprite.modulate = tint
	add_child(_sprite)

	_light = OmniLight3D.new()
	_light.light_color = tint
	_light.light_energy = 1.2
	_light.omni_range = 3.0
	add_child(_light)

	var shape := SphereShape3D.new()
	shape.radius = 0.7
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)


func _tint() -> Color:
	match kind:
		Kind.KEY: return KEY_COLORS.get(key_id, Color.WHITE)
		Kind.HEALTH: return Color(1.0, 0.55, 0.55)
		Kind.ARMOR: return Color(0.55, 0.8, 1.0)
		_: return Color(1.0, 0.85, 0.5)


func _process(delta: float) -> void:
	# Never animate in the editor — bobbing would rewrite `position` and mark the
	# level scene dirty on every frame.
	if Engine.is_editor_hint() or _taken or _sprite == null:
		return
	_phase += delta
	position.y = _base_y + sin(_phase * 2.4) * bob_height
	if kind != Kind.KEY:
		_sprite.rotation.y += delta * spin_speed


func _on_body_entered(body: Node3D) -> void:
	if _taken or not body.is_in_group(Player.GROUP):
		return
	if _apply_to(body):
		_consume()


## Returns false when the player is already full, leaving the pickup in place.
func _apply_to(player: Node) -> bool:
	match kind:
		Kind.HEALTH:
			if not player.heal(amount):
				return false
			Game.post_message("+%d health" % amount, 1.2)
		Kind.ARMOR:
			if not player.add_armor(amount):
				return false
			Game.post_message("+%d armor" % amount, 1.2)
		Kind.AMMO:
			if not player.add_ammo(amount):
				return false
			Game.post_message("+%d ammo" % amount, 1.2)
		Kind.KEY:
			if Game.has_key(key_id):
				return false
			Game.add_key(key_id)
			Game.post_message("Picked up the %s keycard" % String(key_id).to_upper(), 2.5)
	return true


func _consume() -> void:
	_taken = true
	if respawn_seconds <= 0.0:
		queue_free()
		return
	visible = false
	monitoring = false
	await get_tree().create_timer(respawn_seconds).timeout
	if not is_instance_valid(self):
		return
	_taken = false
	visible = true
	monitoring = true
