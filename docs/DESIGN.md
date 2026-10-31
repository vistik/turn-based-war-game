# Combat engine prototype

WW2 squad combat in Normandy, June 1944: Allies (olive green) vs Germany (field grey) on a square grid,
inspired by UFO: Enemy Unknown and XCOM 2. Single height level. Play against the AI, hotseat, online against
another computer, or watch AI vs AI.

## Decisions

| Topic | Decision |
|---|---|
| Grid | Square, 8-way movement, diagonals cost 1.5, no cutting corners past walls/objects |
| View | Isometric by default (V toggles top-down), rotate in quarter turns (Q/E), pan/zoom camera. Props in front of soldiers or the cursor fade out |
| Actions | 2 per turn. Move (1) / dash (2). Shoot, aimed shot (needs both), suppressive fire, overwatch, hunker, grenade and mortar end the turn. Reload, set up MG, rally, smoke, medkit, changing stance and turning a tank cost 1 |
| Movement | Mobility = path-cost budget per action. Roads 0.75, rough ground/rubble 2, wheat/craters 1.5, vaulting a low wall +1, pushing through a hedgerow +3 |
| Stances | Stand, crouch or prone (C / Z), 1 action to change, kept until changed; moving keeps the stance. Tanks have none. **Crouched**: −10 to be hit (−20 behind half cover), +5 aim, moves cost ×1.5, sight −1. **Prone**: −20 to be hit at range (−30 behind half cover), +5 aim (+15 for a set-up MG), +10 suppression recovery, and hidden from anyone more than 4 tiles away while lying in wheat, until it fires (revealed until its next turn). But moves cost ×3 (crawl, at least 1 tile per action), sight −2, +15 to be hit within 2.5 tiles and +10 when flanked (a shooter from a side its cover doesn't face), and it can't throw grenades or smoke, fire a bazooka/Panzerschreck or work the mortar. Pinned soldiers can still change stance. Stance modifiers also apply to reaction shots, so crawling is the way past overwatch |
| Aimed shot | X: both actions, +15 aim, ends the turn |
| Suppressive fire | B: no damage roll. The target gets 1.5× the weapon's suppression and its allies within 1.5 tiles the full amount, and none of them recover suppression at the start of their next turn. Uses 2 rounds and ends the turn; not for tanks or rocket launchers, and tanks can't be targeted. An MG 42 pins a fresh target through their whole turn (83); a rifle only suppresses |
| Cover | Half (−20) or full (−40), directional, from objects on neighbouring tiles or walls/hedges on tile edges. Shell craters give half cover on every side |
| Flanking | No cover from the shooter's angle gives the shooter +40 crit |
| Line of sight | Full cover and smoke block, half cover doesn't. Units beside full cover step out to the side. Wheat hides targets at range (−10 beyond 4 tiles) |
| Hit chance | aim + weapon range table (+ aimed shot, + shooter's stance) − cover (×2 hunkered) − target's stance − suppression penalty − concealment, clamped 0–100. Shown exactly, line by line |
| Results | Hit, crit, graze (10% band above the hit chance, half damage), miss |
| Wounds | Surviving a hit slows the unit by 3 mobility for its next two turns. Medkits heal and treat wounds |
| Suppression | Every shot adds the weapon's suppression to its target (hits add +15). MGs also suppress the target's neighbours; explosions suppress everyone near the blast. Suppressed (30+): −15 aim, −2 mobility. Pinned (70+): can't move or overwatch, −30 aim, and a move into reaction fire can stop short. Recovers 35 per turn, more in cover, prone or near the officer, none the turn after suppressive fire |
| Morale | A death may panic allies within 5 tiles (30% to be pinned, less near the officer). Losing the officer suppresses the whole squad. Officers can Rally (−50 suppression around them) |
| Machine guns | Must be set up (1 action) before shooting or overwatch; moving packs them away |
| Mortar | Only fires if it hasn't moved this turn. Range 5–22, needs any friendly soldier to see the target tile. The shell lands at the start of the firing side's next turn, scattered up to 8% of the range, on a marked area both sides can see. HE (3–5 damage, destroys cover, leaves a crater) or smoke |
| Smoke | Grenades (which scatter like frag grenades) and mortar rounds. Blocks sight through it and hides anyone inside from all but adjacent tiles, for two rounds |
| Objectives | Church, crossroads and farm on the centre line. Held while only your side stands in the area. 1 point per held objective per round; first to 12 wins, else elimination, else most points after round 20 (level = draw) |
| Reinforcements | Waves join at the map edge on a set round (in the Normandy skirmish: a tank and a rifleman per side in round 4) |
| Tanks | Sherman / Panzer IV. Small arms bounce off; anti-tank hits lose 3/1/0 damage on the front/side/rear armour (front = within 60° of where the tank faces). Explosions lose 3 against tanks. The main gun fires high explosive: a hit also blasts (2–3 damage, radius 1) and destroys cover around the target; a miss bursts where it strays (see Stray rounds). Immune to suppression and panic. Soldiers next to a tank get half cover. A knocked-out tank becomes a burning wreck (full cover) |
| Tank driving | Tanks are slow to handle: every 45° the hull turns costs 1 movement, and backing up costs double but keeps the front toward the enemy. "Turn tank" pivots on the spot for one action. Tanks destroy what they drive over: crates, sandbags and hay (+1), trees (+2), fences and low walls (+1) and hedgerows (+4); rocks, wrecks and buildings stop them. The turret turns freely, so shooting never changes the hull's facing |
| Anti-tank | Bazooka / Panzerschreck: 6–9 damage, one round then reload, best up close |
| Stray rounds | Misses from MGs, rockets and tank guns can hit someone else, friends included. A missed rocket or shell lands on a random tile from 1 short of the target to 3 past it, within 1 tile of the line of fire (not within 1.5 of the shooter), stopping short of walls and buildings. Whoever stands there takes a direct hit 50% of the time (armour applies); it then bursts: a rocket on that tile only, a shell with radius 1, both 2–3 damage that destroys cover. A missed MG burst rolls 20% for each other soldier beside the target (1.5 tiles) or within 0.75 tiles of the line of fire, in turn; the first one hit takes half damage. The odds panel lists who is at risk and how likely; the map shows a rocket's landing area and rings friends in danger |
| Grenade scatter | Frag and smoke grenades land up to 0.12 tiles off target per tile thrown, +0.03 per aim point below 70, +0.6 suppressed or +1.2 pinned; under 1 tile of scatter it always lands on target (an unshaken aim-65 rifleman out to 7 tiles). Never further off than that; they bounce back off walls, full cover and buildings. Targeting shows the scatter ring, the blast on target and, fainter, everywhere it could reach, and which friends it could catch |
| Saving | Two slots: campaign (with any battle in progress) and skirmish, plus one for the online game in progress. Autosave at the start of each human turn; "Save & quit" in battle. A loaded game replays identically: the RNG state and the AI's memory are saved too. Saves live in user:// unless `--save-dir=PATH` is given after `--` (tests use this so two copies on one computer keep separate saves) |
| Map generator | `MapGenerator.generate(seed, size)`: road and crossroads village, church to the north and farm to the south on the centre line (the three objectives), outlying farmsteads on maps over 48 wide, bocage fields (grass, wheat, orchard, rough) packed into the open ground, craters and clutter. Built on the west half and mirrored; rerolled if any spawn can't reach every objective |
| Skirmish sizes | Village 48x48, or random maps: standard 44x44 (8 a side, 12 points to win, 20 rounds), large 64x64 (12 a side, 16 points, 24 rounds), huge 84x84 (15 a side with a tank each, 20 points, 28 rounds). `GameSession.build_skirmish(setup)` builds the same battle from the same setup every time |
| Online | Direct connection, no server: one player hosts (Allies) on a UDP port (24944 by default), the other joins by address. The host sends the setup once; after that only commands travel (`Battle.execute` takes commands as data). The engine is deterministic, so each command carries the sender's `Battle.checksum()` (SHA-256 of the whole state, dice included) after applying it, and the receiver compares: any difference, an impossible order or an order for the wrong side ends the game as out of sync on both screens. Over the internet the host forwards the port or both use a VPN |
| Online saves | The host makes a game id with the setup. Whoever verifies a command that changed the turn (or ended the battle) tells the other side its checksum matched (`Net.turn_agreed` on both), and both save the battle to their online slot with the game id, their side, the title, the opponent's address and the checksum; a finished game clears it. Leaving or losing the connection keeps it; the turn in progress is replayed. To continue, either player hosts "Continue online game" (each keeps their side) and the host's save is played on: it sends its saved battle, the joiner compares it with its own save (same game id and checksum go straight on; no save adopts the host's; a different, older or newer save asks first), loads it, and sends back the checksum of what it loaded. Only when that matches the host's does the host say go; otherwise both get "out of sync" and keep their saves. `Net.PROTOCOL` 2 |
| Campaign | Five missions (`Campaign.MISSIONS`) with one persistent squad of up to 8 deployed (12 on the roster). XP = 1 per mission survived + 1 per kill; Cpl. at 3, Sgt. at 7 (+5 aim, +1 HP per rank). Badly wounded (half HP or less) soldiers sit out the next mission; the dead stay dead. Supplies: +3 for a win, +1 for a loss; a replacement costs 1. A lost mission is retried |
| Turns | Each side moves all its units, in any order. The turn ends automatically when nobody can act |
| AI | Utility AI per side (`TacticalAI`). Plays fair: knows only what its side sees plus last-seen positions. Scores every unit's plans (shoot, aimed shot, suppressive fire, grenade, mortar, MG set-up, rally, medkit, reload, overwatch, hunker, stance change then follow up, turn tank, move then follow up) by expected damage, kill chance, suppression, incoming danger (including marked mortar zones), cover, objectives, role range and approach. Cover counts most when it faces the known enemies (or where they're expected), and ending a move in the open is penalised. Tanks judge spots with the hull facing the way it will end up, to keep the front armour toward the threat. Grenades are valued over everywhere they may land; MG, rocket and tank shots lose value for every friend a miss could hit (3x the expected harm, more if likelier than 12%). Stances: a stance's change in danger counts double (it lasts while the soldier holds the spot) against a cost for the slower movement (crouch 2, prone 12, halved when pinned); a crouched or prone soldier weighs standing up against the best full-speed move it opens, and the AI knows it is hidden lying in wheat. So it gets down when pinned in the open, crouches where several enemies can see it, and stands to move on. Suppressive fire is valued by the suppression left through the enemy's next turn, with a bonus for pinning or suppressing them, so it is used on targets that are hard to hit. Grows impatient after quiet rounds, and pushes for objectives harder the further behind on points it is. `decide()` returns the chosen command as data |
| Suggestions | H (Shift+H: selected soldier) asks `AdvisorAI`, the tactical AI working for the player with its own memory and only the team's sight, for a move; it is highlighted with its reasons and the player carries it out. Off in online games unless allowed |
| Agent link (MCP) | Opt-in MCP server (Streamable HTTP, JSON replies) on 127.0.0.1 while a battle is open, with a per-run bearer token. Tools: get_state (fog respected), get_unit_options, preview, suggest_move, propose_move (shows a proposal the player can accept), execute_command (only if the player allows it, never online). See docs/MCP.md |
| Scenarios | JSON files (`Scenario`, format in `scripts/combat/scenario.gd`): the map as terrain rows plus object and wall lists, units on exact tiles with facing, name and rank, objectives, reinforcement waves with spawn tiles, points to win, round limit, title, briefing and whether edits mirror. Bundled in `res://scenarios/` (the village), saved by the editor to `user://scenarios/`, listed in the skirmish map choice. Online, the scenario's data travels in the setup |
| Map editor | `scenes/editor.tscn`, from the main menu. Paints ground, objects, walls/hedges/fences on tile sides, units, objectives and reinforcement spawns on the battle's isometric view, with mirroring (edit one half, the other follows, or copy west onto east), undo, save/load, play (vs AI, hotseat, watch) and a quick AI-vs-AI balance test |
| RNG | Seeded `RandomNumberGenerator` per battle, so battles are reproducible and testable |
| Settings | `GameSettings` (static, saved to `user://settings.cfg`): instant movement, follow opponent moves with the camera, playback speed for your own and for opponent turns (+/- in battle saves it), camera pan speed, show hit chances, confirm ending the turn early, fullscreen. From the main menu or the Settings button in battle. Presentation only: the engine never reads them |

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
  - `Scenario`: hand-made battles as JSON; builds a Battle through `BattleFactory`, exports one from a battle or layout, mirrors and swaps sides.
- `scripts/tools/balance_sim.gd` (`BalanceSim`): AI vs AI games on worker threads and their statistics, for `tools/balance.gd` and the editor.
- `scripts/ui/map_editor.gd`: the map and scenario editor.
- `scripts/campaign/campaign.gd`: missions, the persistent roster, after-action results, recruiting.
- `scripts/net/net_session.gd` (autoload `Net`): hosting, joining, sending setup and commands, desync reports. `scripts/net/remote_player.gd`: the controller for the online opponent's side, which applies and verifies their commands and announces agreed turn changes.
- `scripts/game_settings.gd`: player settings. `scripts/ui/settings_panel.gd` builds the controls, used by the main menu's Settings page and the in-battle `scripts/ui/settings_popup.gd`.
- `scripts/game_session.gd`: what the battle scene should play, the skirmish builder, and the save slots. `scripts/ui/main_menu.gd`: main menu and campaign screens (`scenes/main_menu.tscn` is the main scene).
- `scripts/view/battle_view.gd`: input, AI turn pacing and event playback (speed 1x/2x/4x/instant). It never changes game state directly. The picture is a retained scene: terrain, shadows and fog are 8x8-tile chunks repainted lazily when on screen; each prop is its own canvas item, recorded once and faded/darkened through `modulate`; soldiers and smoke redraw every frame; depth order comes from `z_index`.
- `scripts/ui/ui_theme.gd`: the WW2 look (olive canvas panels, khaki buttons, paper fields and tooltips, typewriter text, stencil-style headings), built in code from system fonts and merged into Godot's default theme by `UITheme.apply()`, so every Control picks it up. Type variations: HeaderLarge/Medium/Small, PrimaryButton, SmallButton, TopBar, HelpLabel. The battle screen has a slim top bar (turn, score, view buttons, `?` controls) and a narrow side panel (unit, actions, target, a log that folds away).
- `scripts/view/terrain_painter.gd`, `soldier_painter.gd`, `vehicle_painter.gd`: procedural art. Soldiers are small 3D models (capsules and balls) projected through the view, so they face, walk, crouch, cower and fall correctly from any rotation.
- `scripts/view/view_projection.gd`: grid ↔ screen maths for iso/top-down and rotation.
- `scripts/advisor/`: move suggestions (`AdvisorAI`) and `AdvisorView`, the battle view's child for the H key, the highlight and the agent link. `scripts/mcp/`: `McpServer` (MCP over HTTP) and `McpGameTools` (the agent's tools). See `docs/MCP.md`.
- `tests/run_tests.gd`: headless engine and AI tests. `tests/advisor_tests.gd`: suggestions and the agent link. `tests/simulate.gd`: AI vs AI batch games for tuning.

```
Godot --headless --path . -s tests/run_tests.gd
Godot --headless --path . -s tests/advisor_tests.gd
Godot --headless --path . -s tests/simulate.gd -- 30 1 64   # games [first seed] [map size, 0 = village]
# Balance: win rates with 95% intervals, endings, survivors, kills per role, objective control; --help for all options
Godot --headless --path . -s tools/balance.gd -- --scenario res://scenarios/village.json --games 50 --seed 1
Godot --headless --path . -s tools/balance.gd -- --map random --size 64 --games 20 --swap --csv out.csv --json out.json
# Online: two games, AI on both sides, checking they stay identical (add "tamper" to the joiner to test desync detection)
Godot --headless --path . -s tests/net_match.gd -- host 25000 64 &
Godot --headless --path . -s tests/net_match.gd -- join 25000
# Online saves: play into round 3, both leave, both continue (also: joiner without a save, tampered load, swapped host)
GODOT=Godot tests/net_resume.sh 26000 44
```

## Next candidates

- Height levels: church tower, upper floors, high-ground aim bonus
- Digging in, sprinting, barbed wire and mines
- AI: smoke use, path choice around overwatch, difficulty levels; run its thinking off the main thread
- More mission types (defend, escort, raid), campaign branching
- Windows and Linux builds
- Online: campaign co-op, lobby/relay for players behind NAT, keep more than one saved online game
