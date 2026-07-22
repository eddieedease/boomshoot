## One-shot placeholder art generator.
##
## Run with:
##   godot --headless --path . --script res://tools/gen_art.gd
##
## Everything is drawn procedurally so the repo stays dependency free. Textures
## are 64x64 and tile seamlessly; sprites are pixel art with a hard outline.
## Re-running overwrites the PNGs, so tweak the constants and re-run to reskin.
extends SceneTree

const TEX_DIR := "res://assets/textures"
const SPR_DIR := "res://assets/sprites"

const OUTLINE := Color8(17, 8, 8)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(TEX_DIR)
	DirAccess.make_dir_recursive_absolute(SPR_DIR)
	_gen_textures()
	_gen_grunt()
	_gen_pistol()
	_gen_pickups()
	print("[gen_art] done")
	quit()


# ---------------------------------------------------------------- helpers ---

func _img(w: int, h: int) -> Image:
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	return image


func _save(image: Image, path: String) -> void:
	var err := image.save_png(path)
	if err != OK:
		push_error("failed to save %s (%d)" % [path, err])


func _rect(image: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for py in range(y, y + h):
		for px in range(x, x + w):
			if px >= 0 and py >= 0 and px < image.get_width() and py < image.get_height():
				image.set_pixel(px, py, c)


## Filled ellipse. Coordinates may sit outside the image; pixels are clipped.
func _ellipse(image: Image, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	for py in range(int(cy - ry) - 1, int(cy + ry) + 2):
		for px in range(int(cx - rx) - 1, int(cx + rx) + 2):
			if px < 0 or py < 0 or px >= image.get_width() or py >= image.get_height():
				continue
			var dx := (px + 0.5 - cx) / rx
			var dy := (py + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				image.set_pixel(px, py, c)


## Wraps a 1px dark border around every opaque pixel. Cheap way to make flat
## shapes read as deliberate pixel art rather than mush.
func _outline(image: Image, c: Color = OUTLINE) -> void:
	var w := image.get_width()
	var h := image.get_height()
	var src := image.duplicate() as Image
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a > 0.0:
				continue
			var touching := false
			for oy in [-1, 0, 1]:
				for ox in [-1, 0, 1]:
					var nx: int = x + ox
					var ny: int = y + oy
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					if src.get_pixel(nx, ny).a > 0.0:
						touching = true
			if touching:
				image.set_pixel(x, y, c)


## Per-pixel value jitter. Doom-era textures are grainy, so this is applied
## everywhere rather than smoothed into gradients.
func _grain(image: Image, rng: RandomNumberGenerator, amount: float) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var d := rng.randf_range(-amount, amount)
			image.set_pixel(x, y, Color(
				clampf(c.r + d, 0.0, 1.0),
				clampf(c.g + d, 0.0, 1.0),
				clampf(c.b + d, 0.0, 1.0),
				c.a))


func _shade(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0.0, 1.0), clampf(c.g * f, 0.0, 1.0), clampf(c.b * f, 0.0, 1.0), c.a)


# --------------------------------------------------------------- textures ---

func _gen_textures() -> void:
	_tex_brick()
	_tex_tech()
	_tex_stone()
	_tex_concrete()
	_tex_grate()
	_tex_ceiling()
	_tex_door()
	_tex_exit()
	_tex_hazard()


## Offset brick courses. Bricks are 16x8 with a 1px mortar gap, which tiles
## cleanly at 64x64.
func _tex_brick() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1001
	var image := _img(64, 64)
	var mortar := Color8(58, 50, 46)
	image.fill(mortar)
	for row in 8:
		var oy := row * 8
		var offset := 8 if row % 2 == 1 else 0
		for col in 4:
			var ox := col * 16 + offset
			var base := Color8(122, 58, 44).lerp(Color8(90, 40, 32), rng.randf())
			for y in range(oy + 1, oy + 8):
				for x in range(ox + 1, ox + 16):
					image.set_pixel(x % 64, y, base)
			# top/left highlight, bottom shadow
			for x in range(ox + 1, ox + 16):
				image.set_pixel(x % 64, oy + 1, _shade(base, 1.25))
				image.set_pixel(x % 64, oy + 7, _shade(base, 0.7))
	_grain(image, rng, 0.05)
	_save(image, TEX_DIR + "/wall_brick.png")


## Riveted metal panels.
func _tex_tech() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1002
	var image := _img(64, 64)
	var base := Color8(96, 102, 112)
	image.fill(base)
	for py in 2:
		for px in 2:
			var ox := px * 32
			var oy := py * 32
			_rect(image, ox + 2, oy + 2, 28, 28, _shade(base, 1.1))
			_rect(image, ox + 3, oy + 3, 26, 26, base)
			_rect(image, ox + 3, oy + 28, 26, 1, _shade(base, 0.72))
			_rect(image, ox + 28, oy + 3, 1, 26, _shade(base, 0.72))
			for r in [Vector2i(6, 6), Vector2i(25, 6), Vector2i(6, 25), Vector2i(25, 25)]:
				image.set_pixel(ox + r.x, oy + r.y, _shade(base, 0.55))
				image.set_pixel(ox + r.x - 1, oy + r.y - 1, _shade(base, 1.35))
	_grain(image, rng, 0.04)
	_save(image, TEX_DIR + "/wall_tech.png")


## Irregular ashlar blocks.
func _tex_stone() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1003
	var image := _img(64, 64)
	image.fill(Color8(52, 52, 56))
	var rows := [0, 13, 26, 42, 55]
	for i in rows.size():
		var oy: int = rows[i]
		var hgt: int = (rows[i + 1] if i + 1 < rows.size() else 64) - oy
		var x := (i * 9) % 64
		while x < 64 + 22:
			var wdt := rng.randi_range(14, 24)
			var base := Color8(120, 118, 112).lerp(Color8(78, 76, 74), rng.randf())
			for y in range(oy + 1, oy + hgt - 1):
				for px in range(x + 1, x + wdt - 1):
					image.set_pixel(px % 64, y, base)
			for px in range(x + 1, x + wdt - 1):
				image.set_pixel(px % 64, oy + 1, _shade(base, 1.2))
				image.set_pixel(px % 64, oy + hgt - 2, _shade(base, 0.72))
			x += wdt
	_grain(image, rng, 0.06)
	_save(image, TEX_DIR + "/wall_stone.png")


func _tex_concrete() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1004
	var image := _img(64, 64)
	image.fill(Color8(88, 86, 84))
	# Blotches, wrapped so the tile stays seamless.
	for i in 60:
		var cx := rng.randf_range(0.0, 64.0)
		var cy := rng.randf_range(0.0, 64.0)
		var r := rng.randf_range(2.0, 7.0)
		var c := _shade(Color8(88, 86, 84), rng.randf_range(0.8, 1.18))
		for oy in [-64, 0, 64]:
			for ox in [-64, 0, 64]:
				_ellipse(image, cx + ox, cy + oy, r, r, c)
	_grain(image, rng, 0.07)
	_save(image, TEX_DIR + "/floor_concrete.png")


## Walkway grating. The dark holes read as depth without any real geometry.
func _tex_grate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1005
	var image := _img(64, 64)
	var metal := Color8(104, 108, 116)
	image.fill(metal)
	for py in 4:
		for px in 4:
			_rect(image, px * 16 + 3, py * 16 + 3, 11, 11, Color8(26, 27, 30))
			_rect(image, px * 16 + 3, py * 16 + 3, 11, 1, Color8(14, 15, 17))
			_rect(image, px * 16 + 4, py * 16 + 13, 10, 1, _shade(metal, 1.3))
	_grain(image, rng, 0.05)
	_save(image, TEX_DIR + "/floor_grate.png")


func _tex_ceiling() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1006
	var image := _img(64, 64)
	var base := Color8(48, 46, 50)
	image.fill(base)
	for py in 2:
		for px in 2:
			_rect(image, px * 32 + 1, py * 32 + 1, 30, 30, _shade(base, 1.12))
			_rect(image, px * 32 + 2, py * 32 + 2, 28, 28, base)
	_grain(image, rng, 0.05)
	_save(image, TEX_DIR + "/ceiling_panel.png")


## Vertical-panelled door with a centre seam. Deliberately warm so doors pop
## against the grey/brown level palette.
func _tex_door() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1007
	var image := _img(64, 64)
	var base := Color8(150, 108, 44)
	image.fill(base)
	for i in 4:
		var ox := i * 16
		_rect(image, ox + 2, 2, 12, 60, _shade(base, 1.15))
		_rect(image, ox + 3, 3, 10, 58, base)
		_rect(image, ox + 3, 60, 10, 1, _shade(base, 0.7))
	_rect(image, 31, 0, 2, 64, _shade(base, 0.5))
	_grain(image, rng, 0.05)
	_save(image, TEX_DIR + "/door_metal.png")


## Exit marker: glowing green with an up chevron. Used unshaded so it reads as
## emissive from across the room.
func _tex_exit() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1008
	var image := _img(64, 64)
	image.fill(Color8(20, 54, 30))
	for i in 3:
		var oy := 8 + i * 18
		for y in 12:
			var half := y
			for x in range(32 - half, 32 + half):
				if x >= 0 and x < 64:
					image.set_pixel(x, oy + y, Color8(70, 230, 110))
	_grain(image, rng, 0.04)
	_save(image, TEX_DIR + "/exit_glow.png")


func _tex_hazard() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1009
	var image := _img(64, 64)
	for y in 64:
		for x in 64:
			var band := ((x + y) / 8) % 2
			image.set_pixel(x, y, Color8(214, 176, 40) if band == 0 else Color8(32, 30, 28))
	_grain(image, rng, 0.05)
	_save(image, TEX_DIR + "/hazard.png")


# ---------------------------------------------------------------- sprites ---

const GRUNT_W := 40
const GRUNT_H := 48

const SKIN := Color8(122, 46, 42)
const SKIN_DARK := Color8(78, 26, 26)
const BONE := Color8(214, 198, 160)
const EYE := Color8(255, 214, 74)


## Draws the grunt from a handful of parameters so every animation frame stays
## anatomically consistent. `phase` swings the legs, `arm` raises the claws,
## `squash` flattens the whole body for the death sequence.
func _draw_grunt(image: Image, phase: float, arm: float, squash: float, tint: Color) -> void:
	var cx := GRUNT_W * 0.5
	var ground := float(GRUNT_H) - 2.0
	var scale_y := 1.0 - squash
	var hip := ground - 16.0 * scale_y
	var chest := hip - 12.0 * scale_y
	var head_y := chest - 7.0 * scale_y

	var body := SKIN.lerp(tint, tint.a)
	var body_dark := SKIN_DARK.lerp(tint, tint.a)

	# Legs (alternating stride).
	var swing := sin(phase) * 4.0
	for side: float in [-1.0, 1.0]:
		var lx := cx + side * 5.0 + (swing * side * 0.5)
		_ellipse(image, lx, (hip + ground) * 0.5, 4.0, (ground - hip) * 0.5 + 1.0, body_dark)
		_ellipse(image, lx + side * 1.0, ground - 1.0, 5.0, 2.5, body_dark)

	# Torso.
	_ellipse(image, cx, (chest + hip) * 0.5, 9.0, (hip - chest) * 0.5 + 4.0, body)
	_ellipse(image, cx, chest + 3.0, 10.0, 5.0 * scale_y + squash * 4.0, body)

	# Arms — swing opposite the legs, or lift forward when attacking.
	for side: float in [-1.0, 1.0]:
		var shoulder_x := cx + side * 9.0
		var reach := lerpf(-swing * side * 0.6, -8.0 * scale_y, arm)
		var hand_y := chest + 8.0 * scale_y + reach
		_ellipse(image, shoulder_x, chest + 3.0, 3.5, 4.0, body)
		_ellipse(image, shoulder_x + side * 1.5, (chest + hand_y) * 0.5 + 2.0, 3.0, 5.0, body_dark)
		_ellipse(image, shoulder_x + side * 2.5, hand_y, 3.0, 3.0, BONE)

	# Head, horns, eyes.
	_ellipse(image, cx, head_y, 7.0, 6.0 * scale_y + squash * 3.0, body)
	for side: float in [-1.0, 1.0]:
		_ellipse(image, cx + side * 6.0, head_y - 5.0 * scale_y, 1.8, 3.5 * scale_y, BONE)
		_ellipse(image, cx + side * 7.0, head_y - 8.0 * scale_y, 1.2, 2.0 * scale_y, BONE)
	if squash < 0.55:
		for side: float in [-1.0, 1.0]:
			_ellipse(image, cx + side * 3.0, head_y - 0.5, 1.6, 1.6 * scale_y, EYE)
	# Mouth.
	_ellipse(image, cx, head_y + 3.5 * scale_y, 3.0, 1.2, Color8(40, 12, 12))


func _grunt_frame(name: String, phase: float, arm: float, squash: float, tint: Color) -> void:
	var image := _img(GRUNT_W, GRUNT_H)
	_draw_grunt(image, phase, arm, squash, tint)
	_outline(image)
	_save(image, SPR_DIR + "/grunt_%s.png" % name)


func _gen_grunt() -> void:
	var none := Color(1, 1, 1, 0.0)
	var hurt := Color(1.0, 1.0, 1.0, 0.55)
	_grunt_frame("idle", 0.0, 0.0, 0.0, none)
	_grunt_frame("walk_0", 0.0, 0.0, 0.0, none)
	_grunt_frame("walk_1", PI * 0.5, 0.0, 0.0, none)
	_grunt_frame("walk_2", PI, 0.0, 0.0, none)
	_grunt_frame("walk_3", PI * 1.5, 0.0, 0.0, none)
	_grunt_frame("attack", 0.0, 1.0, 0.0, none)
	_grunt_frame("pain", 0.0, 0.2, 0.05, hurt)
	_grunt_frame("die_0", 0.0, 0.4, 0.25, none)
	_grunt_frame("die_1", 0.0, 0.2, 0.55, none)
	_grunt_frame("die_2", 0.0, 0.0, 0.8, none)


const GUN_W := 128
const GUN_H := 96

const METAL := Color8(74, 76, 86)
const METAL_HI := Color8(126, 128, 140)
const METAL_LO := Color8(34, 34, 42)
const HAND := Color8(198, 138, 92)
const HAND_DARK := Color8(150, 98, 60)


## Pistol viewmodel, drawn slightly right of centre like a Doom weapon sprite.
## `recoil` slides it down/back, `flash` adds the muzzle bloom.
func _draw_pistol(image: Image, recoil: float, flash: float) -> void:
	var ox := GUN_W * 0.52
	var oy := GUN_H - 4.0 + recoil * 10.0

	# Grip and hand.
	_rect(image, int(ox - 8), int(oy - 34), 20, 34, METAL_LO)
	_ellipse(image, ox + 2.0, oy - 20.0, 13.0, 15.0, HAND)
	_ellipse(image, ox + 2.0, oy - 12.0, 13.0, 8.0, HAND_DARK)
	for i in 4:
		_ellipse(image, ox - 7.0 + i * 0.0, oy - 30.0 + i * 6.0, 4.0, 2.6, HAND)

	# Frame and slide.
	_rect(image, int(ox - 12), int(oy - 46), 40, 13, METAL)
	_rect(image, int(ox - 12), int(oy - 46), 40, 2, METAL_HI)
	_rect(image, int(ox - 12), int(oy - 35), 40, 2, METAL_LO)
	# Barrel.
	_rect(image, int(ox + 20), int(oy - 43), 16, 8, METAL)
	_rect(image, int(ox + 20), int(oy - 43), 16, 2, METAL_HI)
	# Rear sight.
	_rect(image, int(ox - 10), int(oy - 50), 4, 5, METAL_HI)
	# Trigger guard.
	_rect(image, int(ox - 6), int(oy - 33), 14, 3, METAL_LO)

	if flash > 0.0:
		var fx := ox + 38.0
		var fy := oy - 39.0
		_ellipse(image, fx, fy, 16.0 * flash, 11.0 * flash, Color8(255, 236, 140))
		_ellipse(image, fx, fy, 10.0 * flash, 6.5 * flash, Color8(255, 255, 232))
		for i in 6:
			var a := TAU * i / 6.0
			_ellipse(image, fx + cos(a) * 15.0 * flash, fy + sin(a) * 11.0 * flash,
					4.0 * flash, 3.0 * flash, Color8(255, 200, 90))


func _gen_pistol() -> void:
	for f: Array in [["idle", 0.0, 0.0], ["fire_0", 1.0, 1.0], ["fire_1", 0.45, 0.35]]:
		var image := _img(GUN_W, GUN_H)
		_draw_pistol(image, f[1], f[2])
		_outline(image)
		_save(image, SPR_DIR + "/pistol_%s.png" % f[0])


## Pickup icons, used on billboarded Sprite3D nodes.
func _gen_pickups() -> void:
	var health := _img(24, 24)
	_rect(health, 2, 2, 20, 20, Color8(232, 232, 236))
	_rect(health, 4, 4, 16, 16, Color8(206, 208, 214))
	_rect(health, 10, 5, 4, 14, Color8(206, 40, 44))
	_rect(health, 5, 10, 14, 4, Color8(206, 40, 44))
	_outline(health)
	_save(health, SPR_DIR + "/pickup_health.png")

	# Shield outline for armour.
	var armor := _img(24, 24)
	for y in 20:
		# Taper the lower half to a point so it reads as a shield, not a box.
		var t := float(y) / 19.0
		var half := int(round(9.0 * (1.0 - maxf(0.0, t - 0.45) / 0.55 * 0.92)))
		_rect(armor, 12 - half, 2 + y, half * 2, 1, Color8(160, 176, 208))
	for y in 14:
		var t := float(y) / 13.0
		var half := int(round(6.0 * (1.0 - maxf(0.0, t - 0.45) / 0.55 * 0.9)))
		_rect(armor, 12 - half, 5 + y, half * 2, 1, Color8(96, 118, 160))
	_outline(armor)
	_save(armor, SPR_DIR + "/pickup_armor.png")

	var ammo := _img(24, 24)
	_rect(ammo, 4, 6, 16, 14, Color8(150, 120, 48))
	_rect(ammo, 4, 6, 16, 3, Color8(200, 166, 74))
	for i in 3:
		_rect(ammo, 6 + i * 5, 2, 3, 6, Color8(214, 190, 120))
	_outline(ammo)
	_save(ammo, SPR_DIR + "/pickup_ammo.png")

	# Keycard — colour is tinted per-instance via modulate.
	var key := _img(24, 24)
	_rect(key, 5, 4, 14, 17, Color8(240, 240, 240))
	_rect(key, 7, 7, 10, 6, Color8(180, 182, 190))
	_rect(key, 7, 15, 10, 3, Color8(180, 182, 190))
	_outline(key)
	_save(key, SPR_DIR + "/pickup_key.png")
