## Fire-and-forget sound playback.
##
## Every call spawns a throwaway player that frees itself when the clip ends, so
## nothing has to own an AudioStreamPlayer or track voices. Positional sounds are
## the default: in a shooter, *where* a growl came from is information.
##
## Pitch jitter is applied by default because a sound that is bit-identical on
## every repeat is the fastest way to make a game feel cheap.
class_name Sfx
extends Object

const PISTOL_SHOT := preload("res://assets/audio/pistol_shot.wav")
const DRY_FIRE := preload("res://assets/audio/dry_fire.wav")
const RELOAD := preload("res://assets/audio/reload.wav")

const ENEMY_ALERT := preload("res://assets/audio/enemy_alert.wav")
const ENEMY_ATTACK := preload("res://assets/audio/enemy_attack.wav")
const ENEMY_PAIN := preload("res://assets/audio/enemy_pain.wav")
const ENEMY_DEATH := preload("res://assets/audio/enemy_death.wav")

const DOOR_OPEN := preload("res://assets/audio/door_open.wav")
const DOOR_CLOSE := preload("res://assets/audio/door_close.wav")
const DOOR_LOCKED := preload("res://assets/audio/door_locked.wav")

const PICKUP := preload("res://assets/audio/pickup.wav")
const PLAYER_HURT := preload("res://assets/audio/player_hurt.wav")
const LEVEL_COMPLETE := preload("res://assets/audio/level_complete.wav")


## Plays `stream` at `anchor`'s position in the world.
##
## The voice is parented to the anchor's *parent*, not the anchor, so a sound
## still finishes when the thing that made it is freed — pickups disappear the
## instant you touch them.
static func play_at(anchor: Node3D, stream: AudioStream, volume_db: float = 0.0,
		pitch_jitter: float = 0.07, max_distance: float = 45.0) -> void:
	if stream == null or anchor == null or not anchor.is_inside_tree():
		return

	var host := anchor.get_parent()
	if host == null:
		host = anchor

	var voice := AudioStreamPlayer3D.new()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.max_distance = max_distance
	voice.unit_size = 8.0
	voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	voice.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	host.add_child(voice)
	voice.global_position = anchor.global_position
	voice.finished.connect(voice.queue_free)
	voice.play()


## Non-positional. For the player's own weapon and for UI — things that happen
## "at the camera" rather than somewhere in the level.
static func play_ui(stream: AudioStream, volume_db: float = 0.0,
		pitch_jitter: float = 0.0) -> void:
	if stream == null:
		return
	var voice := AudioStreamPlayer.new()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	# Parented to the Game autoload so it survives a level swap mid-clip.
	Game.add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()
