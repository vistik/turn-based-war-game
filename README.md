# Normandy 1944

Turn-based WW2 squad tactics in the Normandy bocage, June 1944: the Allies against Germany on an isometric
grid, inspired by UFO: Enemy Unknown and XCOM 2. Built with Godot 4.7 in GDScript; all art is drawn in code.

The rules and architecture are in [docs/DESIGN.md](docs/DESIGN.md), the agent link in [docs/MCP.md](docs/MCP.md),
and ideas for later in [docs/IDEAS.md](docs/IDEAS.md).

## Features

**Battles**
- Two actions per soldier per turn: move, dash, or move and act. Path cost depends on terrain, hedgerows, walls
  and stance. The exact hit chance is shown, with every modifier itemised.
- Directional half and full cover, flanking and line of sight that steps out around corners. Fog of war,
  overwatch, and destructible cover with craters.
- Suppression and pinning, wounds that slow soldiers for two turns, panic when friends die, and an officer
  who can rally the squad.
- Roles:
  - Officer, Rifleman, SMG and Sniper
  - Medic, with medkits
  - MG, which has to be set up before firing
  - Mortar, whose delayed, scattering shells can be high explosive or smoke
  - AT with Bazooka or Panzerschreck
  - Sherman and Panzer IV tanks
- Tanks have front, side and rear armour. They turn slowly (each 45° costs movement), can back up, and can
  pivot on the spot. They flatten crates, walls, hedges and trees, and leave burning wrecks.
- Stances, each with a trade-off:
  - crouch: harder to hit, moves slower
  - prone: very hard to hit at range and hidden in wheat, but crawls and is exposed up close
- Aimed shots and suppressive fire. Grenades scatter, and missed rockets, tank shells and MG bursts can hit
  someone else, friends included. The odds panel tells you who is at risk.
- Objectives (church, crossroads, farm) score victory points every round. Reinforcement waves arrive mid-battle.

**Ways to play**
- **Campaign**: five missions with one persistent squad. Soldiers gain XP and rank, get wounded and die for
  good. Supplies buy replacements.
- **Skirmish** on the hand-made Normandy village, a random map (standard 44x44, large 64x64, huge 84x84 with
  bigger forces), or your own scenarios. Play vs AI, hotseat, or watch AI vs AI.
- **Online**: two computers connect directly, no server needed. After every order both games check they hold
  the identical battle. Online games save at each agreed turn and can be continued later with the same
  opponent.
- **Map and scenario editor**: paint terrain, cover and walls, place units, objectives and reinforcement
  spawns, mirror one half onto the other, and save scenarios as JSON. Play or test them with the AI straight away.

**AI**
- A utility AI that plays fair: it only knows what its side can see. It weighs cover facing the enemy,
  objectives, stances, tank armour, friendly-fire risk and the score.
- **Suggest a move** (H): the same AI advises you, showing the move and why, and you make it yourself.
- **Agent link**: an opt-in MCP server on your own computer lets an agent like Claude read your side's view,
  suggest moves on screen and, only if you allow it, make them. Never in online games.

**Other**
- **Saves**: a campaign slot and a skirmish slot with autosave, "Save & quit", and exact replay (dice and AI
  memory included).
- **Settings**: instant movement, following opponent moves, playback speeds, camera pan speed, hit chances,
  end-turn confirmation, fullscreen, and the AI helper switches.

## Controls

| Key | Action |
|---|---|
| Left click | Select a soldier, move, pick a target |
| Right click / Esc | Cancel |
| 1 – 0 | Shoot, overwatch, hunker, reload, grenade, smoke, set up MG, rally, medkit, mortar |
| T | Turn a tank on the spot |
| C / Z | Crouch / go prone (press again to stand up) |
| X / B | Aimed shot / suppressive fire |
| H / Shift+H | Suggest a move / suggest for the selected soldier |
| Tab / Enter | Next soldier / end turn |
| WASD, arrows, middle drag | Pan |
| Wheel / F | Zoom / focus the selected soldier |
| Q / E / V | Rotate the view / switch isometric and top-down |
| + / - | Playback speed |

The map editor has its own keys, listed in its panel: 1–7 pick a tool, R turns a unit, Ctrl+Z undoes and
Ctrl+S saves.

## Running

You need Godot 4.7 (`Godot` below means its binary, e.g. `~/Downloads/Godot.app/Contents/MacOS/Godot`).

```sh
Godot --path .                 # play from the project
Godot --path . --editor        # open in the Godot editor
```

**macOS app:**

```sh
Godot --headless --path . --export-release "macOS" "build/Normandy 1944.app"
codesign --force --deep -s - "build/Normandy 1944.app"
```

Run the export command once first so the export templates for 4.7 are installed. To try online play on one
computer, open the app twice (`open -n "build/Normandy 1944.app"`), host in one and join `127.0.0.1` in the
other. Over the internet the host forwards UDP port 24944, or both players use a VPN such as Tailscale.

## Testing and balancing

```sh
Godot --headless --path . -s tests/run_tests.gd         # engine, AI, saves, scenarios, settings
Godot --headless --path . -s tests/advisor_tests.gd     # move suggestions and the MCP tools
GODOT=Godot sh tests/net_resume.sh 26000 44             # two copies online: save, quit, resume, desync checks

# AI vs AI balance: win rates with confidence intervals, endings, kills per role, objective control
Godot --headless --path . -s tools/balance.gd -- --scenario res://scenarios/village.json --games 50 --seed 1
Godot --headless --path . -s tools/balance.gd -- --map random --size 64 --games 20 --csv results.csv
```

A single online match between two processes, with the AI on both sides:
`tests/net_match.gd -- host PORT [size]` and `-- join PORT`. See the header of that file for options.

## Project layout

| Path | Contents |
|---|---|
| `scripts/combat/` | The rules engine: battle, map, line of sight, pathfinding, units, weapons, AI, map generator, scenarios |
| `scripts/view/` | Battle scene, isometric projection and procedural painters for terrain, soldiers and tanks |
| `scripts/ui/` | Main menu and campaign screens, settings, theme, map editor |
| `scripts/campaign/` | The campaign |
| `scripts/net/` | Online play |
| `scripts/advisor/`, `scripts/mcp/` | Move suggestions and the agent link |
| `scenarios/` | Bundled scenarios (JSON) |
| `tests/`, `tools/` | Tests, the online test harness, the balance simulator |
