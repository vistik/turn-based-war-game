# Combat engine prototype

WW2 squad combat in Normandy, June 1944: Allies (olive green) vs Germany (field grey) on a square grid,
inspired by UFO: Enemy Unknown and XCOM 2. Single height level. Play against the AI, hotseat, online against
another computer, or watch AI vs AI.

## Decisions

| Topic | Decision |
|---|---|
| Grid | Square, 8-way movement, diagonals cost 1.5, no cutting corners past walls/objects |
| View | Isometric by default (V toggles top-down), rotate in quarter turns (Q/E), pan/zoom camera. Props in front of soldiers or the cursor fade out |
| Actions | 2 per turn. Move (1) / dash (2). Shoot, overwatch, hunker, grenade and mortar end the turn. Reload, set up MG, rally, smoke, medkit and turning a tank cost 1 |
| Movement | Mobility = path-cost budget per action. Roads 0.75, rough ground/rubble 2, wheat/craters 1.5, vaulting a low wall +1, pushing through a hedgerow +3 |
| Cover | Half (−20) or full (−40), directional, from objects on neighbouring tiles or walls/hedges on tile edges. Shell craters give half cover on every side |
| Flanking | No cover from the shooter's angle gives the shooter +40 crit |
| Line of sight | Full cover and smoke block, half cover doesn't. Units beside full cover step out to the side. Wheat hides targets at range (−10 beyond 4 tiles) |
| Hit chance | aim + weapon range table − cover (×2 hunkered) − suppression penalty − concealment, clamped 0–100. Shown exactly |
| Results | Hit, crit, graze (10% band above the hit chance, half damage), miss |
| Wounds | Surviving a hit slows the unit by 3 mobility for its next two turns. Medkits heal and treat wounds |
| Suppression | Every shot adds the weapon's suppression to its target (hits add +15). MGs also suppress the target's neighbours; explosions suppress everyone near the blast. Suppressed (30+): −15 aim, −2 mobility. Pinned (70+): can't move or overwatch, −30 aim, and a move into reaction fire can stop short. Recovers 35 per turn, more in cover or near the officer |
| Morale | A death may panic allies within 5 tiles (30% to be pinned, less near the officer). Losing the officer suppresses the whole squad. Officers can Rally (−50 suppression around them) |
| Machine guns | Must be set up (1 action) before shooting or overwatch; moving packs them away |
| Mortar | Only fires if it hasn't moved this turn. Range 5–22, needs any friendly soldier to see the target tile. The shell lands at the start of the firing side's next turn, scattered up to 8% of the range, on a marked area both sides can see. HE (3–5 damage, destroys cover, leaves a crater) or smoke |
| Smoke | Grenades and mortar rounds. Blocks sight through it and hides anyone inside from all but adjacent tiles, for two rounds |
| Objectives | Church, crossroads and farm on the centre line. Held while only your side stands in the area. 1 point per held objective per round; first to 12 wins, else elimination, else most points after round 20 (level = draw) |
| Reinforcements | Waves join at the map edge on a set round (in the Normandy skirmish: a tank and a rifleman per side in round 4) |
| Tanks | Sherman / Panzer IV. Small arms bounce off; anti-tank hits lose 3/1/0 damage on the front/side/rear armour (front = within 60° of where the tank faces). Explosions lose 3 against tanks. The main gun fires high explosive: a hit or near miss also blasts (2–3 damage) and destroys cover around the target. Immune to suppression and panic. Soldiers next to a tank get half cover. A knocked-out tank becomes a burning wreck (full cover) |
| Tank driving | Tanks are slow to handle: every 45° the hull turns costs 1 movement, and backing up costs double but keeps the front toward the enemy. "Turn tank" pivots on the spot for one action. Tanks destroy what they drive over: crates, sandbags and hay (+1), trees (+2), fences and low walls (+1) and hedgerows (+4); rocks, wrecks and buildings stop them. The turret turns freely, so shooting never changes the hull's facing |
| Anti-tank | Bazooka / Panzerschreck: 6–9 damage, one round then reload, best up close |
| Saving | Two slots: campaign (with any battle in progress) and skirmish. Autosave at the start of each human turn; "Save & quit" in battle. A loaded game replays identically: the RNG state and the AI's memory are saved too |
| Map generator | `MapGenerator.generate(seed, size)`: road and crossroads village, church to the north and farm to the south on the centre line (the three objectives), outlying farmsteads on maps over 48 wide, bocage fields (grass, wheat, orchard, rough) packed into the open ground, craters and clutter. Built on the west half and mirrored; rerolled if any spawn can't reach every objective |
| Skirmish sizes | Village 48x48, or random maps: standard 44x44 (8 a side, 12 points to win, 20 rounds), large 64x64 (12 a side, 16 points, 24 rounds), huge 84x84 (15 a side with a tank each, 20 points, 28 rounds). `GameSession.build_skirmish(setup)` builds the same battle from the same setup every time |
| Online | Direct connection, no server: one player hosts (Allies) on a UDP port (24944 by default), the other joins by address. The host sends the setup once; after that only commands travel (`Battle.execute` takes commands as data). The engine is deterministic, so each command carries the sender's `Battle.checksum()` (SHA-256 of the whole state, dice included) after applying it, and the receiver compares: any difference, an impossible order or an order for the wrong side ends the game as out of sync on both screens. Online battles aren't saved. Over the internet the host forwards the port or both use a VPN |
| Campaign | Five missions (`Campaign.MISSIONS`) with one persistent squad of up to 8 deployed (12 on the roster). XP = 1 per mission survived + 1 per kill; Cpl. at 3, Sgt. at 7 (+5 aim, +1 HP per rank). Badly wounded (half HP or less) soldiers sit out the next mission; the dead stay dead. Supplies: +3 for a win, +1 for a loss; a replacement costs 1. A lost mission is retried |
| Turns | Each side moves all its units, in any order. The turn ends automatically when nobody can act |
| AI | Utility AI per side (`TacticalAI`). Plays fair: knows only what its side sees plus last-seen positions. Scores every unit's plans (shoot, grenade, mortar, MG set-up, rally, medkit, reload, overwatch, hunker, turn tank, move then follow up) by expected damage, kill chance, suppression, incoming danger (including marked mortar zones), cover, objectives, role range and approach. Cover counts most when it faces the known enemies (or where they're expected), and ending a move in the open is penalised. Tanks judge spots with the hull facing the way it will end up, to keep the front armour toward the threat. Grows impatient after quiet rounds, and pushes for objectives harder the further behind on points it is. `decide()` returns the chosen command as data |
| RNG | Seeded `RandomNumberGenerator` per battle, so battles are reproducible and testable |

## Squads

Officer (Thompson / MP 40, smoke), Riflemen (M1 Garand / Kar98k), AT (Bazooka / Panzerschreck), Medic (carbine,
medkits, smoke), SMG, MG (M1919 / MG 42, needs set-up, heavy suppression), Sniper (sight 16, best at long range),
Mortar team (carbine, 4 HE and 2 smoke rounds) and Tanks. Maps are built by mirroring the west half, so both sides
get identical ground.

## Architecture

- `scripts/combat/`: the rules engine, plain `RefCounted` classes with no nodes.
  - `Battle` is the engine. Commands (`move`, `shoot`, `fire_mortar`, …) check `can_*`, change state and return **event dictionaries**.
  - `TacticalMap` (terrain, objects and walls with kinds, smoke, cover), `LineOfSight`, `Pathfinder`, `CombatRules` (tunable numbers and hit formula), `Unit`, `Weapon`.
  - `MapBuilder` (mirrored map construction), `NormandyScenario` (the hand-made 48x48 village), `MapGenerator` (random maps).
  - `BattleFactory`: a battle from a map layout and two rosters, with objectives and reinforcement waves.
  - `TacticalAI`: issues the same commands a player does, one per `act()` call.
- `scripts/campaign/campaign.gd`: missions, the persistent roster, after-action results, recruiting.
- `scripts/net/net_session.gd` (autoload `Net`): hosting, joining, sending setup and commands, desync reports. `scripts/net/remote_player.gd`: the controller for the online opponent's side, which applies and verifies their commands.
- `scripts/game_session.gd`: what the battle scene should play, the skirmish builder, and the save slots. `scripts/ui/main_menu.gd`: main menu and campaign screens (`scenes/main_menu.tscn` is the main scene).
- `scripts/view/battle_view.gd`: input, AI turn pacing and event playback (speed 1x/2x/4x/instant). It never changes game state directly. The picture is a retained scene: terrain, shadows and fog are 8x8-tile chunks repainted lazily when on screen; each prop is its own canvas item, recorded once and faded/darkened through `modulate`; soldiers and smoke redraw every frame; depth order comes from `z_index`.
- `scripts/view/terrain_painter.gd`, `soldier_painter.gd`, `vehicle_painter.gd`: procedural art. Soldiers are small 3D models (capsules and balls) projected through the view, so they face, walk, crouch, cower and fall correctly from any rotation.
- `scripts/view/view_projection.gd`: grid ↔ screen maths for iso/top-down and rotation.
- `tests/run_tests.gd`: headless engine and AI tests. `tests/simulate.gd`: AI vs AI batch games for tuning.

```
Godot --headless --path . -s tests/run_tests.gd
Godot --headless --path . -s tests/simulate.gd -- 30 1 64   # games [first seed] [map size, 0 = village]
# Online: two games, AI on both sides, checking they stay identical (add "tamper" to the joiner to test desync detection)
Godot --headless --path . -s tests/net_match.gd -- host 25000 64 &
Godot --headless --path . -s tests/net_match.gd -- join 25000
```

## Next candidates

- Height levels: church tower, upper floors, high-ground aim bonus
- Prone stance, digging in, barbed wire and mines
- AI: smoke use, path choice around overwatch, difficulty levels; run its thinking off the main thread
- Map editor, more mission types (defend, escort, raid), campaign branching
- Windows and Linux builds
- Online: resume a dropped game from both players' last agreed state, campaign co-op, lobby/relay for players behind NAT
