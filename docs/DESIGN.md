# Combat engine prototype

Square-grid tactical combat inspired by UFO: Enemy Unknown and XCOM 2. Single height level. Play against the AI, hotseat, or watch AI vs AI.

## Decisions

| Topic | Decision |
|---|---|
| Grid | Square, 8-way movement, diagonals cost 1.5, no cutting corners past walls/objects |
| View | Isometric by default (V toggles top-down), rotate in quarter turns (Q/E), pan/zoom camera. Walls and objects in front of units or the cursor fade out. One level (height comes later) |
| Actions | 2 per turn. Move (1) / dash (2). Shoot, overwatch, hunker and grenade end the turn. Reload and medkit cost 1 |
| Movement | Mobility = path-cost budget per action. Rough ground and rubble cost 2, vaulting a low wall +1 |
| Cover | Half (−20) or full (−40), directional. Comes from objects on neighbouring tiles or walls on tile edges |
| Flanking | No cover from the shooter's angle gives the shooter +40 crit |
| Line of sight | Full cover blocks, half doesn't. Units beside full cover step out to the side (XCOM style) |
| Fog of war | Per team, recomputed after every action. Sight 12 tiles |
| Hit chance | aim + weapon range table − cover (×2 hunkered) − defense, clamped 0–100. Shown exactly, no hidden fudging |
| Results | Hit, crit (+crit damage), graze (the 10% band above the hit chance, half damage), miss. Armor absorbs damage point for point |
| Overwatch | Fires once at the first enemy that moves in sight. 70% aim, the moving target gets no cover. Lasts until the owner's next turn |
| Destruction | Grenades destroy all objects and walls in the blast. Objects leave rubble |
| Turns | Each team moves all its units, in any order. The turn ends automatically when nobody can act |
| AI | Utility AI per team (`TacticalAI`). Plays fair: knows only what its team sees, plus last-seen positions. Each step it scores every unit's plans (shoot, grenade, medkit, reload, overwatch, hunker, move then follow up) by expected damage, kill chance, incoming danger, cover, range and approach, and runs the best. Grows impatient after quiet rounds to break overwatch standoffs |
| RNG | Seeded `RandomNumberGenerator` per battle, so battles are reproducible and testable |

## Architecture

- `scripts/combat/`: the rules engine, plain `RefCounted` classes with no nodes.
  - `Battle` is the engine. Commands (`move`, `shoot`, …) check `can_*`, change state and return **event dictionaries**.
  - `TacticalMap` (terrain, objects, wall edges, cover), `LineOfSight`, `Pathfinder`, `CombatRules` (tunable numbers and hit formula), `Unit`, `Weapon`.
  - `SkirmishScenario`: the hand-made test map and rosters.
- `scripts/combat/tactical_ai.gd`: the AI. It issues the same commands a player does, one per `act()` call.
- `scripts/view/battle_view.gd`: input, menus, AI turn pacing and event playback (speed 1x/2x/4x/instant). It never changes game state directly.
- `scripts/view/terrain_painter.gd`, `soldier_painter.gd`: procedural art. Soldiers are small 3D models (capsules and balls) projected through the view, so they face, walk, crouch and fall correctly from any rotation. The ground is on its own layer that only repaints when it changes.
- `scripts/view/view_projection.gd`: grid ↔ screen maths for iso/top-down and rotation. The view keeps positions in grid space and only projects at draw time.
- `tests/run_tests.gd`: headless engine and AI tests. `tests/simulate.gd`: AI vs AI batch games for tuning.

```
Godot --headless --path . -s tests/run_tests.gd
Godot --headless --path . -s tests/simulate.gd -- 30   # games [first seed]
```

## Next candidates

- Height levels: tile elevation, aim bonus from high ground, ladders
- AI personalities and difficulty levels, smarter path choice around overwatch
- More abilities and items, ammo types, armor shred on weapons
- Map loading from files or an editor
- Missed shots damaging cover
