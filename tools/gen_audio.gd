## One-shot placeholder sound generator.
##
##   godot --headless --path . --script res://tools/gen_audio.gd
##
## Everything is synthesised from noise and oscillators and written out as plain
## 16-bit mono RIFF WAV, so the repo needs no audio dependencies and no licensed
## samples. 22050 Hz is deliberate: it is period-correct for the era and keeps
## the files small.
##
## To reskin the audio, change the numbers here and re-run.
extends SceneTree

const RATE := 22050
const DIR := "res://assets/audio"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)

	_write(_pistol_shot(), "pistol_shot")
	_write(_dry_fire(), "dry_fire")
	_write(_reload(), "reload")

	_write(_enemy_alert(), "enemy_alert")
	_write(_enemy_attack(), "enemy_attack")
	_write(_enemy_pain(), "enemy_pain")
	_write(_enemy_death(), "enemy_death")

	_write(_door_open(), "door_open")
	_write(_door_close(), "door_close")
	_write(_door_locked(), "door_locked")

	_write(_pickup(), "pickup")
	_write(_player_hurt(), "player_hurt")
	_write(_level_complete(), "level_complete")

	print("[gen_audio] done")
	quit()


# ---------------------------------------------------------------- plumbing --

func _buffer(seconds: float) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	buffer.resize(int(seconds * RATE))
	buffer.fill(0.0)
	return buffer


## Scales the whole buffer so its loudest sample sits at `peak`. Keeps the set
## roughly level-matched without hand-tuning every gain.
func _normalize(buffer: PackedFloat32Array, peak: float = 0.85) -> PackedFloat32Array:
	var loudest := 0.0
	for sample in buffer:
		loudest = maxf(loudest, absf(sample))
	if loudest < 0.0001:
		return buffer
	var gain := peak / loudest
	for i in buffer.size():
		buffer[i] *= gain
	return buffer


## One-pole low-pass with a per-sample cutoff, which is what turns flat white
## noise into something with a shape.
func _lowpass(buffer: PackedFloat32Array, from_hz: float, to_hz: float) -> void:
	var state := 0.0
	var count := buffer.size()
	for i in count:
		var t := float(i) / maxf(count - 1.0, 1.0)
		var cutoff := lerpf(from_hz, to_hz, t)
		var alpha := 1.0 - exp(-TAU * cutoff / RATE)
		state += (buffer[i] - state) * alpha
		buffer[i] = state


## Soft clip. Adds harmonics and stops peaks poking through.
func _saturate(buffer: PackedFloat32Array, drive: float) -> void:
	for i in buffer.size():
		buffer[i] = tanh(buffer[i] * drive) / tanh(drive)


func _write(buffer: PackedFloat32Array, name: String) -> void:
	var path := "%s/%s.wav" % [DIR, name]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write %s" % path)
		return

	var byte_count := buffer.size() * 2

	# RIFF/WAVE header, written by hand so this does not depend on engine
	# helpers that come and go between versions.
	file.store_string("RIFF")
	file.store_32(36 + byte_count)
	file.store_string("WAVE")
	file.store_string("fmt ")
	file.store_32(16)          # PCM chunk size
	file.store_16(1)           # format: PCM
	file.store_16(1)           # channels: mono
	file.store_32(RATE)
	file.store_32(RATE * 2)    # byte rate
	file.store_16(2)           # block align
	file.store_16(16)          # bits per sample
	file.store_string("data")
	file.store_32(byte_count)

	var pcm := PackedByteArray()
	pcm.resize(byte_count)
	for i in buffer.size():
		pcm.encode_s16(i * 2, int(clampf(buffer[i], -1.0, 1.0) * 32767.0))
	file.store_buffer(pcm)
	file.close()


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# ---------------------------------------------------------------- weapons --

## Three layers: a noise crack, a pitched-down body thump, and a click on the
## very first samples so the transient reads as mechanical.
func _pistol_shot() -> PackedFloat32Array:
	var rng := _rng(2001)
	var buffer := _buffer(0.26)
	var crack := _buffer(0.26)

	for i in buffer.size():
		crack[i] = rng.randf_range(-1.0, 1.0)
	_lowpass(crack, 7000.0, 500.0)

	for i in buffer.size():
		var t := float(i) / RATE
		var crack_env: float = exp(-t / 0.035)
		var body_env: float = exp(-t / 0.075)
		# Body sweeps from a snap down to a thud.
		var body_hz := lerpf(340.0, 55.0, minf(t / 0.09, 1.0))
		var body := sin(TAU * body_hz * t) * body_env
		var click: float = 1.0 if i < 3 else 0.0
		buffer[i] = crack[i] * crack_env * 0.9 + body * 0.75 + click * 0.5

	_saturate(buffer, 2.2)
	return _normalize(buffer)


func _dry_fire() -> PackedFloat32Array:
	var rng := _rng(2002)
	var buffer := _buffer(0.07)
	for i in buffer.size():
		var t := float(i) / RATE
		buffer[i] = rng.randf_range(-1.0, 1.0) * exp(-t / 0.006)
	_lowpass(buffer, 6000.0, 2200.0)
	return _normalize(buffer, 0.5)


## Two mechanical clacks: magazine out, magazine in.
func _reload() -> PackedFloat32Array:
	var rng := _rng(2003)
	var buffer := _buffer(1.0)
	for offset: float in [0.02, 0.55]:
		var start := int(offset * RATE)
		for i in range(start, mini(start + int(0.12 * RATE), buffer.size())):
			var t := float(i - start) / RATE
			var env: float = exp(-t / 0.02)
			buffer[i] += rng.randf_range(-1.0, 1.0) * env * 0.8
			buffer[i] += sin(TAU * 180.0 * t) * env * 0.4
	_lowpass(buffer, 5000.0, 1400.0)
	return _normalize(buffer, 0.6)


# ---------------------------------------------------------------- enemies --

## Low sawtooth with vibrato — the vibrato is what makes it read as a throat
## rather than a synth tone.
func _growl(seconds: float, from_hz: float, to_hz: float, seed_value: int) -> PackedFloat32Array:
	var rng := _rng(seed_value)
	var buffer := _buffer(seconds)
	var phase := 0.0
	for i in buffer.size():
		var t := float(i) / RATE
		var progress := t / seconds
		var hz := lerpf(from_hz, to_hz, progress) * (1.0 + sin(TAU * 11.0 * t) * 0.09)
		phase += hz / RATE
		var saw := fposmod(phase, 1.0) * 2.0 - 1.0
		var env: float = exp(-t / (seconds * 0.45))
		buffer[i] = (saw * 0.8 + rng.randf_range(-1.0, 1.0) * 0.25) * env
	_lowpass(buffer, 1800.0, 400.0)
	_saturate(buffer, 2.6)
	return _normalize(buffer)


func _enemy_alert() -> PackedFloat32Array:
	return _growl(0.55, 130.0, 95.0, 2101)


func _enemy_pain() -> PackedFloat32Array:
	return _growl(0.26, 260.0, 150.0, 2102)


func _enemy_death() -> PackedFloat32Array:
	return _growl(1.0, 170.0, 38.0, 2103)


## A claw swipe: filtered noise whose passband sweeps up then away.
func _enemy_attack() -> PackedFloat32Array:
	var rng := _rng(2104)
	var buffer := _buffer(0.3)
	for i in buffer.size():
		var t := float(i) / RATE
		# Swell in, then cut off, so it sounds like something passing you.
		var env := sin(PI * clampf(t / 0.3, 0.0, 1.0))
		buffer[i] = rng.randf_range(-1.0, 1.0) * env * env
	_lowpass(buffer, 900.0, 5200.0)
	return _normalize(buffer, 0.7)


# ------------------------------------------------------------------ doors --

## Servo whine over a low rumble, with grit on top.
func _door_move(seconds: float, from_hz: float, to_hz: float, seed_value: int) -> PackedFloat32Array:
	var rng := _rng(seed_value)
	var buffer := _buffer(seconds)
	for i in buffer.size():
		var t := float(i) / RATE
		var progress := t / seconds
		# Fade in and out so the loop does not click at either end.
		var env := clampf(t / 0.08, 0.0, 1.0) * clampf((seconds - t) / 0.15, 0.0, 1.0)
		var whine := sin(TAU * lerpf(from_hz, to_hz, progress) * t)
		var rumble := sin(TAU * 46.0 * t) * (0.8 + sin(TAU * 7.0 * t) * 0.2)
		var grit := rng.randf_range(-1.0, 1.0)
		buffer[i] = (whine * 0.35 + rumble * 0.55 + grit * 0.18) * env
	_lowpass(buffer, 2600.0, 900.0)
	_saturate(buffer, 1.8)
	return _normalize(buffer, 0.75)


func _door_open() -> PackedFloat32Array:
	return _door_move(0.85, 150.0, 230.0, 2201)


## Same machinery running down, plus a thud where it lands.
func _door_close() -> PackedFloat32Array:
	var buffer := _door_move(0.8, 230.0, 140.0, 2202)
	var thud_start := int(0.62 * RATE)
	for i in range(thud_start, buffer.size()):
		var t := float(i - thud_start) / RATE
		buffer[i] += sin(TAU * 62.0 * t) * exp(-t / 0.05) * 0.9
	return _normalize(buffer, 0.85)


## Two flat buzzes. Deliberately unpleasant — it means "no".
func _door_locked() -> PackedFloat32Array:
	var buffer := _buffer(0.36)
	for burst: float in [0.0, 0.18]:
		var start := int(burst * RATE)
		for i in range(start, mini(start + int(0.11 * RATE), buffer.size())):
			var t := float(i - start) / RATE
			var square := 1.0 if fposmod(150.0 * t, 1.0) < 0.5 else -1.0
			buffer[i] += square * clampf((0.11 - t) / 0.02, 0.0, 1.0) * 0.7
	_lowpass(buffer, 2400.0, 1600.0)
	return _normalize(buffer, 0.55)


# ------------------------------------------------------------------ misc ---

## Two ascending blips. Reads as "you got something" in any era.
func _pickup() -> PackedFloat32Array:
	var buffer := _buffer(0.28)
	var notes := [[0.0, 720.0], [0.075, 1080.0]]
	for note: Array in notes:
		var start := int(float(note[0]) * RATE)
		var hz: float = note[1]
		for i in range(start, mini(start + int(0.16 * RATE), buffer.size())):
			var t := float(i - start) / RATE
			buffer[i] += sin(TAU * hz * t) * exp(-t / 0.045) * 0.7
	return _normalize(buffer, 0.5)


func _player_hurt() -> PackedFloat32Array:
	var rng := _rng(2301)
	var buffer := _buffer(0.34)
	var phase := 0.0
	for i in buffer.size():
		var t := float(i) / RATE
		var hz := lerpf(210.0, 110.0, minf(t / 0.3, 1.0))
		phase += hz / RATE
		var saw := fposmod(phase, 1.0) * 2.0 - 1.0
		var env: float = exp(-t / 0.11)
		buffer[i] = (saw * 0.7 + rng.randf_range(-1.0, 1.0) * 0.35) * env
	_lowpass(buffer, 2000.0, 600.0)
	_saturate(buffer, 2.0)
	return _normalize(buffer, 0.8)


## Rising major triad — the only genuinely happy sound in the game.
func _level_complete() -> PackedFloat32Array:
	var buffer := _buffer(1.3)
	var notes := [[0.0, 523.25], [0.16, 659.25], [0.32, 783.99], [0.48, 1046.5]]
	for note: Array in notes:
		var start := int(float(note[0]) * RATE)
		var hz: float = note[1]
		for i in range(start, buffer.size()):
			var t := float(i - start) / RATE
			var env: float = exp(-t / 0.32)
			buffer[i] += (sin(TAU * hz * t) * 0.6 + sin(TAU * hz * 2.0 * t) * 0.2) * env
	return _normalize(buffer, 0.65)
