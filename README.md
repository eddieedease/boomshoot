# BOOMSHOOT

An old-school first-person shooter in Godot 4.7 — chunky textures, billboard
sprite enemies, hitscan guns, keycards and a level exit. Built as the base for
an immersive sim, so the systems are deliberately data-driven and decoupled.

Run it: open the project in Godot and press **F5**. It launches fullscreen with
the mouse captured.

---

## Controls

| Action | Keyboard / Mouse | Gamepad |
| --- | --- | --- |
| Move | `WASD` / arrows | Left stick |
| Look | Mouse | Right stick |
| Fire | Left mouse | Right trigger |
| Alt fire | Right mouse | Left trigger |
| Jump | `Space` | A |
| Crouch | `Ctrl` / `C` | B |
| Sprint | `Shift` | L3 |
| Interact / open door | `E` | X |
| Reload | `R` | Y |
| Next / prev weapon | Wheel up / down | RB / LB |
| Pause | `Esc` | Start |

All of it is editable in **Project Settings → Input Map**.

Doors set to `USE` show a prompt under the crosshair when you look at them, and
the button hint follows whichever device you last touched.

---

## Building levels

**See [LEVEL_EDITING.md](LEVEL_EDITING.md) for the full guide** — editor setup
for top-down work, scale reference, and troubleshooting.

The short version: Doom maps were drawn top-down, and dragging gizmos in a
perspective 3D view is the wrong tool. You mostly don't have to. Select a room,
click **Attach Room → North** in the dock, and you get a correctly aligned
neighbour with the doorway already cut — no coordinates, no dragging. For
everything else, set the 3D view to **Top + Orthogonal** with snapping on and it
behaves like a plan view.

The dock also drops parts **where the 3D viewport camera is aimed**, projected
onto the ground plane and snapped to your chosen grid, parented to the current
selection, as one undo step. Then tune values in the Inspector — geometry
rebuilds live.

Open `levels/demo_level.tscn` to see it all in place.

### The parts

| Part | What it is | Key values |
| --- | --- | --- |
| **Room** | Hollow box: floor, ceiling, four walls | `size`, `wall_thickness`, per-wall `SOLID / OPEN / DOORWAY`, `doorway_width/height`, wall/floor/ceiling surfaces |
| **Block** | One textured box — pillars, crates, ledges, platforms | `size`, `origin_at_base`, `solid`, `surface` |
| **Stairs** | A run of steps climbing towards local +Z | `steps`, `step_rise`, `step_run`, `width`, `fill_below` |
| **Ramp** | A slope climbing towards local +Z | `run`, `rise`, `width`, `thickness` |
| **Door** | Sliding door, optionally locked | `size`, `slide` (up/left/right), `open_mode` (proximity/use), `speed`, `auto_close_delay`, `required_key` |
| **Light** | Omni light with a visible fixture | `color`, `energy`, `range_metres`, `flicker_amount`, `flicker_speed` |
| **Player Start** | Where the player spawns — the level's start | Its **-Z axis is the facing direction** |
| **Level Exit** | Glowing pad that ends the level | `next_level`, `required_key`, `require_all_enemies_dead` |
| **Pickups** | Health, armour, ammo, keycard | `kind`, `amount`, `key_id`, `respawn_seconds` |
| **Grunt** | The enemy | health, senses, speed, attack damage/range/windup — all per-instance |

Two rules worth knowing:

- **Butt rooms together by their outer faces, not their interiors.** A room
  occupies its `size` plus a wall band of `wall_thickness` on every side that
  has a wall. So a neighbour's interior must stop where that wall band *ends*.
  Set the shared wall to `DOORWAY` on one room and `OPEN` on the other, and only
  the `DOORWAY` room builds anything in the seam.

  Overlapping two rooms puts two upward-facing floors in the same plane, which
  is what causes depth flicker. Floor and ceiling slabs deliberately do not
  overhang under the walls; each wall carries its own sill instead, so doorways
  still have something to walk across.
- **Keep `step_rise` at or below the player's `step_height`** (0.45 default) or
  the stairs become an invisible wall.

### How the parts work

A part stores **only its parameters**. Meshes and collision shapes are generated
at `_ready` into an unowned child container, which is why:

- the saved `.tscn` is tiny and diffable — a transform plus a few numbers,
- geometry can never drift out of sync with the values describing it,
- changing an export reshapes it live in the editor.

Anything *you* parent to a part keeps its owner and survives rebuilds.

Texturing is world-space triplanar, so texel density stays constant no matter
how a part is scaled or rotated and textures line up across neighbours. You
never touch a UV.

### The demo level

`levels/demo_level.tscn` — start room → corridor → auto door → arena, with a
side vault holding the red keycard behind a `USE` door. The exit sits on a
raised platform and is locked until you have the key. 5 grunts.

---

## Architecture

```
src/
  core/       game.gd (autoload signal bus + run state), layers.gd, map_materials.gd
  building/   map_part.gd and every level part, plus pickup.gd
  player/     player.gd, weapon_manager.gd, weapon_data.gd, weapons/*.tres
  entities/   enemy.gd, grunt.tscn
  ui/         hud.gd, overlay_menu.gd        (built in code, no scene files)
  fx/         fx.gd                          (impact bursts)
  core/sfx.gd                                (fire-and-forget sound)
  main.gd/tscn                               (level loading, spawn, menus)
addons/boomshoot_kit/                        (the editor dock)
tools/                                       (one-shot generators + smoke test)
```

Two decisions shape everything else:

**Nothing reaches for anything else.** Gameplay nodes announce on the `Game`
autoload and whoever cares subscribes. The HUD never touches the player; the
exit never touches the enemies. That is what will let AI senses, factions and
objectives hook in later without surgery.

**Damage is duck-typed.** Anything with
`take_damage(amount, hit_position, direction, source)` is shootable — no shared
base class. The weapon walks up from the collider to find it, so child collision
shapes work too.

### Sound

`Sfx.play_at(node, stream)` spawns a positional voice that frees itself;
`Sfx.play_ui(stream)` is the non-positional version for the player's own weapon
and for UI. Nothing owns an `AudioStreamPlayer`. Pitch is jittered per shot by
default, because a clip that repeats bit-identically is what makes a game sound
cheap.

Wired up: pistol shot, dry fire, reload, enemy alert/attack/pain/death, door
open/close/locked, pickup, player hurt, level complete. All of it is synthesised
by `tools/gen_audio.gd` — no samples, no licences.

### Adding a second gun

Create a new `WeaponData` resource, point it at some sprites, and add it to the
player's `Weapons` node array. `pellets` + `spread_degrees` gives you a shotgun;
`automatic` + a high `shots_per_second` gives you a chaingun. No code.

---

## Tools

```bash
# Regenerate all placeholder sounds (synthesised, written as 16-bit mono WAV)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/gen_audio.gd

# Regenerate all placeholder art (textures and sprites are drawn in code)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/gen_art.gd

# Re-apply project settings: fullscreen, input map, layers, autoloads
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/setup_project.gd

# Headless gameplay test — geometry, hitscan, doors, keys, exit. Exits non-zero on failure.
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . tools/smoke_test.tscn
```

`tools/build_scenes.tscn` generated `player.tscn`, `grunt.tscn`, `main.tscn` and
the demo level. **It overwrites them** — it exists to bootstrap valid scenes, not
to be re-run casually. Everything it made is a normal scene you edit by hand now.

---

## Where this goes next

Groundwork already in place for the immersive sim:

- **Doors** have lock/key and a proximity-vs-deliberate-use distinction.
- **Enemies** auto-detect a baked `NavigationRegion3D` and use it if present,
  falling back to wall-whisker steering so new rooms work with zero setup.
- **The exit** gates on keys or on clearing the level, as data.
- **The signal bus** is the seam for senses, alarms and factions.

Obvious next steps: a second weapon, enemy ranged attacks, footsteps and
ambient loops, saving, and an inventory that makes the keycards into real items.
