# Where this could go

Saved from a design discussion; nothing here is decided.

## Directions

1. **WW2 campaign with a persistent squad** (favourite). One platoon from D-Day inland through Normandy.
   Soldiers keep experience, traits and promotions; the dead stay dead; bad wounds sit out a mission.
   Between battles: spend supplies on replacements, ammo, mortar shells, later tanks; pick the next sector.
   Mission types: hold a bridge, take a village, raid an artillery position, escort a wounded officer out.
2. **Asynchronous online multiplayer.** The engine is deterministic from a seed and every action is a command
   producing events, so a turn can be sent as a few commands and replayed exactly. Replays and spectating come
   almost free. Needs a small backend to relay turns.
3. **Scenario editor and skirmish generator.** In-game map editor plus a generator for Normandy terrain
   (bocage fields, villages, roads). Cheapest route to lots of content.
4. **Roguelite run.** 8-10 procedurally generated battles in a row with events and upgrades until the squad falls.
5. **Platforms.** Godot exports to Windows, macOS, Linux, web, iPad/Android and Steam Deck. Turn-based suits
   touch and handhelds once the controls get a touch pass.

## Needed whichever way

- Real art (sprites or simple 3D), sound and music
- Tanks and height levels (planned)
- Save/load (straightforward: all state lives in plain engine objects)
- Better AI: smoke, falling back, coordinated flanking

## Suggested order

1. Save/load and a map generator (useful for every direction)
2. A small 5-mission campaign with persistent soldiers, to test the loop
3. Tanks
