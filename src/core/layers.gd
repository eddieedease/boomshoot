## Collision layer bit masks, mirroring the names set in Project Settings.
##
## Godot's inspector shows layers 1-based while code needs the bit value, which
## is an easy place to introduce silent bugs — always go through these.
class_name Layers
extends Object

const WORLD := 1 << 0    ## Level geometry, doors, anything that blocks movement.
const PLAYER := 1 << 1
const ENEMY := 1 << 2
const PICKUP := 1 << 3
const TRIGGER := 1 << 4  ## Non-solid volumes: exits, door sensors.

## What a hitscan shot is allowed to hit.
const SHOOTABLE := WORLD | ENEMY

## What the player's interact ray looks for.
const INTERACTABLE := WORLD | PICKUP
