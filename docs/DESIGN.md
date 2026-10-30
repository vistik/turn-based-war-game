# Combat engine prototype

Top-down, square-grid tactical combat inspired by UFO: Enemy Unknown and XCOM 2. Single height level, hotseat.

## Decisions

| Topic | Decision |
|---|---|
| Grid | Square, 8-way movement, diagonals cost 1.5, no cutting corners past walls/objects |
| View | Top-down, one level (height comes later) |
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
| RNG | Seeded `RandomNumberGenerator` per battle, so battles are reproducible and testable |

## Architecture

- `scripts/combat/`: the rules engine, plain `RefCounted` classes with no nodes.
  - `Battle` is the engine. Commands (`move`, `shoot`, …) check `can_*`, change state and return **event dictionaries**.
  - `TacticalMap` (terrain, objects, wall edges, cover), `LineOfSight`, `Pathfinder`, `CombatRules` (tunable numbers and hit formula), `Unit`, `Weapon`.
  - `SkirmishScenario`: the hand-made test map and rosters.
- `scripts/view/battle_view.gd`: draws everything with `_draw()` and plays events back with animations. It never changes game state directly.
- `tests/run_tests.gd`: headless engine tests.

```
Godot --headless --path . -s tests/run_tests.gd
```

## Next candidates

- Height levels: tile elevation, aim bonus from high ground, ladders
- Simple AI to replace hotseat
- More abilities and items, ammo types, armor shred on weapons
- Map loading from files or an editor, larger maps with camera pan and zoom
- Missed shots damaging cover
