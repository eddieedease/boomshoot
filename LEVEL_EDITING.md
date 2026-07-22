# Building levels

## You're right about top-down

Doom levels were drawn in a 2D top-down editor, and trying to lay out a floor
plan by dragging gizmos in a perspective 3D view *is* miserable. You're not
missing anything — that's genuinely the wrong tool for the job.

The fix is that you rarely need to drag anything at all. There are three ways to
place geometry here, and the first one covers most of a level:

| | How | When |
| --- | --- | --- |
| **1. Attach Room** | Select a room, click a compass direction in the dock | Growing a floor plan. No dragging, no coordinates. |
| **2. Top view + snap** | Orthogonal top view, snap on, drag on the grid | Positioning props, platforms, doors, spawns. |
| **3. Type it** | Set `position` and `size` in the Inspector | Precise or awkward cases. |

Set up **2** once (below) and it behaves like a top-down editor: an orthogonal
grid seen from above, where dragging moves things in whole metres.

---

## One-time editor setup

Do this once per project; Godot remembers it.

1. **Split the viewport.** In the 3D editor's top menu bar: **View → 2
   Viewports**. You get two panes.
2. **Make the top pane top-down.** Click the view name in that pane's top-left
   corner (it says *Perspective*) and choose **Top**. Then click it again and
   choose **Orthogonal**. Now you are looking straight down at a flat plan, with
   no perspective distortion.
   *Shortcuts, if you have a numpad: `7` for top view, `5` to toggle
   orthogonal.*
3. **Turn on snapping.** **Transform → Configure Snap…** and set **Translate
   Snap** to `1 m`. Close it, then enable the magnet toggle in the toolbar
   (shortcut `Y`). Dragging now moves in exact 1 m steps.
4. **Match the dock.** Set the **Grid** dropdown in the Boomshoot dock to the
   same value, so parts you drop land on the same lattice you're dragging on.

Keep the bottom pane on Perspective. Lay out in the top pane, glance down to see
what it looks like.

Useful while working: **F** focuses the viewport on the selected node, and
selecting several parts at once lets you edit a shared value for all of them in
the Inspector.

---

## Scale reference

Everything is in metres. Guessing these wrong is the most common reason a level
feels off, so here are the real numbers from the code:

| Thing | Value |
| --- | --- |
| Player height / width | 1.8 m / 0.8 m |
| Player crouched | 1.0 m |
| **Step-up height** | **0.45 m** — anything taller needs a jump |
| Jump height | ~0.95 m |
| Walk / sprint speed | 8 / 11.6 m/s |
| Grunt height / width | 1.7 m / 0.9 m |
| Grunt chase speed | 4.2 m/s (slower than you — you can back off) |
| Grunt sight range | 30 m |
| Grunt melee range | 2.0 m |
| Default room | 12 × 12, 4 m ceiling |
| Default doorway | 3.0 wide × 3.0 tall |
| Default wall thickness | 0.5 m |

Rules of thumb: a corridor feels right at **3–4 m wide**; a normal room ceiling
is **4 m**, a grand one **6 m**; a fight needs at least **10 × 10 m** to move in.

Combat maths, if you're placing enemies: the pistol does 15 damage (37 on a
headshot), the grunt has 40 HP — so **3 body shots or 2 headshots**. A grunt
hits for 12 every 1.1 s, and you have 100 HP.

---

## Building your first level

1. **New scene → Node3D**, name it, save it into `levels/`.
2. Dock → **Room**. It lands on the ground plane in front of the camera.
3. In the Inspector, set its `size`. This is the **interior** — the space you
   actually walk in.
4. Dock → **Attach Room → North**. You get a second room butted against the
   first, with a doorway already cut between them. Repeat to grow the plan.
5. Resize any attached room afterwards if you want — but see *Moving rooms
   afterwards* below.
6. Dock → **Player Start**, and drag it into the first room. Its **blue -Z
   arrow is the direction the player faces**.
7. Dock → **Level Exit**, drop it in the last room.
8. Dock → **Light**, one per room. Rooms are pitch black otherwise.
9. Dock → **Grunt** a few times, and a **Health** / **Ammo** pickup.
10. Press **F5** to play, or **F6** to play just this scene.

To make it the level that loads on F5, open `src/main.tscn` and set
`starting_level` on the `Main` node.

---

## How rooms connect

A room occupies its `size` **plus a wall band of `wall_thickness` on every side
that has a wall**. So two rooms touch when their *outer* faces meet — not their
interiors.

Worked example, two 10 × 10 rooms with 0.5 m walls, one north of the other:

```
   room A at z = 0      interior  z = -5 .. +5
   A's north wall band            z = -5.5 .. -5
   room B interior starts at      z = -5.5
   room B is 10 deep, so its centre is at
       z = -(5 + 0.5 + 5) = -10.5
```

Then set **A's north wall to `DOORWAY`** and **B's south wall to `OPEN`**. Only
one room builds geometry in the seam.

**Attach Room does all of this for you**, which is exactly why it exists. Use it
rather than doing this by hand.

### Why overlapping flickers

If you overlap two rooms, both build a floor in the shared strip, and two
upward-facing surfaces end up in the same plane. The renderer can't decide which
is in front, so it flickers as you move.

Floor and ceiling slabs deliberately stop at the interior and never overhang.
Each wall carries its own **sill** under the doorway instead, so the floor stays
continuous where you walk through. That's what keeps neighbouring rooms from
ever sharing a surface.

### Moving rooms afterwards

Attach Room only computes the seam at the moment you click. If you later resize
or move a room, its neighbour does **not** follow — you'll need to fix the
position, or delete the neighbour and re-attach it. Decide a room's size before
attaching to it and you'll rarely hit this.

---

## Doors

Drop a **Door** into a doorway. Set its `size` to match the opening
(`3.5 × 3` if you used those doorway values) and position it in the wall band.

| Value | Effect |
| --- | --- |
| `open_mode` | `PROXIMITY` opens on approach; `USE` needs the interact button |
| `slide` | `UP` into the header, or `LEFT` / `RIGHT` into the wall |
| `required_key` | Empty = unlocked. `red`, `blue`, `yellow` need that keycard |
| `auto_close_delay` | Seconds open before closing. `0` = stays open |

`USE` doors show a prompt under the crosshair when you look at them; proximity
doors don't, because they need no input. A locked door tells the player which
keycard it wants, and buzzes.

If a door sits in a wall running along Z rather than X, **rotate it 90° on Y**.

---

## Going vertical

- **Stairs** climb towards local **+Z** — rotate the node to aim them. Keep
  `step_rise` at or below **0.45** or the player can't walk up. `steps ×
  step_rise` is the total climb, and `steps × step_run` is how much floor it
  eats.
- **Ramp** is smoother and cheaper. Keep the slope under ~45° or you slide back.
- **Block** with `origin_at_base` on is your platform, pillar, crate or ledge.

To put a platform at the top of stairs, make the stairs' total rise equal the
block's height, and butt the top step against the block's edge.

Push a block **slightly into** an adjacent wall (0.1–0.2 m) rather than ending
flush with it. Ending exactly flush puts two faces in the same plane.

---

## Lighting

There is a dim global ambient, and that's all. An unlit room is nearly black.

- One **Light** per room, near the ceiling, `range_metres` roughly the room's
  width.
- `energy` 2–4 indoors.
- `flicker_amount` around 0.4 on a corridor light is a cheap, effective bit of
  atmosphere. Leave it at 0 elsewhere — everything flickering is just noise.
- The exit pad glows green on its own, which reads as a landmark from across a
  dark room. That's deliberate; don't light it out.

---

## Enemies, pickups, start and exit

**Grunts** are scene instances, so every value is per-instance — select one and
change `max_health`, `chase_speed`, `attack_damage`, `sight_range` to make a
fast weak swarmer or a slow bruiser from the same scene.

They see you within `sight_range` inside a 140° cone, need line of sight, and
once alerted stop caring about facing so you can't lose them by turning a corner.
Shooting one always alerts it. They path with wall-avoidance steering by default;
if you add a `NavigationRegion3D` and bake it, they detect it and use it
automatically — no setting to flip.

**Pickups** — `kind` picks health / armour / ammo / keycard, `amount` is how
much, and a pickup refuses to be collected when you're already full. Keycards
use `key_id` (`red`, `blue`, `yellow`).

**Player Start** — exactly one per level. -Z is the facing direction.

**Level Exit** — gate it with `required_key`, or `require_all_enemies_dead`, or
neither. `next_level` chains to another scene; leave it empty to show the
level-complete screen. `blocked_message` is what the player is told when they
step on a gated exit.

---

## Testing

**F6** plays the open scene directly, which is much faster than F5 while
iterating. `Esc` pauses and frees the mouse.

Before committing a level, run the headless check — it verifies geometry is
solid, that nothing overlaps, and that shooting, doors, keys and the exit all
work:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . tools/smoke_test.tscn
```

---

## When something's wrong

| Symptom | Cause |
| --- | --- |
| Flickering surfaces | Two parts overlap. Rooms must butt by outer faces; nudge props *into* walls, never flush with them. |
| Can't walk up stairs | `step_rise` above 0.45. |
| Fall through the floor at a doorway | Rooms are too far apart — there's a real gap. Re-attach. |
| Fall out of the world | A room with `build_floor` off, or nothing under a doorway. |
| Room is pitch black | No Light in it. |
| Enemies stand still | No line of sight from where they start, or they're outside `sight_range`. |
| Door won't open | `USE` mode and you didn't press the interact key, or it wants a keycard. |
| Geometry looks stale after editing a script | Dock → **Rebuild All Parts**. |
| Parts are off the grid | Select them → dock → **Snap Selection to Grid**. |

---

## What this kit is not

It's a **box-brush** kit: everything is axis-aligned boxes. That covers the Doom
vocabulary — rooms, corridors, doorways, ledges, stairs — but it can't do
arbitrary polygon sectors, sloped floors other than ramps, or curves.

For anything more organic, build a mesh elsewhere and drop it in as a normal
`MeshInstance3D` with a `StaticBody3D` for collision. The parts here and
hand-made geometry mix fine in the same scene.
