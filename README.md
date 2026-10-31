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
- Fog of war hides what the enemy does out of sight: no turning, stance changes, reloading, healing or damage
  shown for units you can't see, only what you'd notice from afar (a mortar firing, smoke rising, a mine
  going off).
- Overwatch holds its fire for targets it can't hurt, such as rifles and machine guns against a tank.
- The selected soldier's field of fire: an outline round everything it can see, green where its gun is at its
  best and a red tint where the range is poor (filled in while aiming).
- Moving shows the cover at the destination, and "EXPOSED TO 2" if seen enemies would have it in the open.
- Soldiers fall away from what killed them (thrown back by blasts), drop their weapon, and bleed out slowly;
  tanks brew up, their turret blown off its ring.
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
- Terrain hazards:
  - **Fuel drums and oil tanks:** they explode when shot, caught in a blast or run over by a tank, set off
    others nearby, and leave the ground burning. Nobody can enter fire, and anyone in it is burnt at the
    start of their turn.
  - **Mines:** hidden. Soldiers may spot them as they walk past (tank crews never do), clear spotted ones
    from next to them, and blasts set them off.
  - **Wheat:** trampled flat when soldiers walk through it (crawling leaves it standing), so it stops hiding
    anyone.
  - **Barbed wire:** slow going on foot; tanks and explosions flatten it.
- Units are easy to tell apart:
  - a badge over each one shows its role as an icon (star for the officer, red cross for the medic, crosshair
    for the sniper, and so on);
  - a ring underneath in the side's colour shows which side it's on;
  - each role carries its own gear: officer's cap or striped helmet, MG ammo belt, sniper's helmet scrim,
    mortar baseplate, rocket bag;
  - the sides wear their own uniforms: Americans in khaki field jackets, canvas leggings and the round M1
    helmet, Germans in field grey with jackboots and the flared Stahlhelm. Soldiers bend at the knee to crouch
    and hold their rifles at the ready.

**Ways to play**
- **Campaign**: five missions with one persistent squad. Soldiers gain XP and rank, get wounded and die for
  good. Supplies buy replacements.
- **Two-player campaign** (hotseat, or against the AI):
  - 3 to 5 maps, each worth a different number of points (1–5), and one pool of 100 supply per side for the
    whole campaign.
  - Before every map both sides secretly commit 12–45 supply and buy units with it (rifleman 3 up to tank 15).
    Committed supply is gone; the rest carries over to later maps.
  - Each side also picks a deployment: balanced, left or right flank, and offensive (deployed further
    forward) or defensive (further back, behind sandbags, crouched).
  - Win a map to take its points; a draw splits them. Most points wins.
- **Skirmish** on the hand-made Normandy village, a random map (standard 44x44, large 64x64, huge 84x84 with
  bigger forces), or your own scenarios. Play vs AI, hotseat, watch AI vs AI, or let an AI agent play a side
  (Agent vs AI, Me vs agent). On the village and random
  maps each side picks a deployment, as in the two-player campaign: the usual spawns, balanced or massed on
  the left or right flank, offensive (further forward) or defensive (further back, behind sandbags,
  crouched), or random. Online, the host picks both.
- **Online**: two computers connect directly, at home or over the internet, no server needed.
  - Every game has a password. The joiner proves it knows the password before the host lets it in (the
    password itself never travels); wrong guesses are turned away, and a run of them locks the game for a
    minute.
  - Over the internet the host's game asks the router to open the port (UPnP) and shows its internet
    address. If the router won't, the joiner's game shows *its* internet address, and the host pastes it into
    "Let them in" to punch through the NAT. Finding the address asks a public STUN server (Google or
    Cloudflare) what address it sees.
  - After every order both games check they hold the identical battle. Online games save at each agreed turn
    and can be continued later with the same opponent.
- **Map and scenario editor**: paint terrain, cover and walls, place units, objectives and reinforcement
  spawns, mirror one half onto the other, and save scenarios as JSON. Play or test them with the AI straight away.

**AI**
- A utility AI that plays fair: it only knows what its side can see. It weighs cover facing the enemy,
  objectives, stances, tank armour, friendly-fire risk and the score.
- **Suggest a move** (H): the same AI advises you, showing the move and why, and you make it yourself.
- **Agent link**: an opt-in MCP server on your own computer lets an agent like Claude read your side's view,
  suggest moves on screen and, only if you allow it, make them. Never in online games.
- **Agent plays**: in the "Agent vs AI" and "Me vs agent" skirmishes an agent plays a whole side through the
  link by itself: it waits for its turn, makes its moves and hears what happened, until the battle ends. It can
  give several orders in one call (stopping early if it's surprised), find tiles in an objective, in cover or with
  a shot, and skip the playback animation.

**Other**
- **Saves**: a campaign slot and a skirmish slot with autosave, "Save & quit", and exact replay (dice and AI
  memory included).
- **Replays**: every battle is recorded (against the AI, hotseat, AI vs AI, both campaigns, online), including
  across saves. Watch it from the game-over screen or the main menu's Replays page (the last 20 finished
  battles, plus battles in progress). Play, pause, step one order at a time, skip to the next turn, restart,
  change the speed, and switch the fog of war at any moment between the Allies' view, Germany's view and the
  whole map.
- **Settings**: instant movement, following opponent moves, playback speeds, camera pan speed, hit chances,
  end-turn confirmation, fullscreen, and the AI helper switches.

## Controls

| Key | Action |
|---|---|
| Left click | Select a soldier, move, pick a target |
| Right click / Esc | Cancel |
| 1 – 0 | Shoot, overwatch, hunker, reload, grenade, smoke, set up MG, rally, medkit, mortar |
| Action bar | Bottom right: every action the soldier has as an icon with its key in the corner and what's left (grenades, smoke, medkits, ammo); hover for its name |
| T | Turn a tank on the spot |
| C / Z | Crouch / go prone (press again to stand up) |
| X / B | Aimed shot / suppressive fire |
| G | Clear a spotted mine next to the soldier |
| 1 on drums / an oil tank | In shoot mode, click fuel drums or an oil tank to blow them up |
| H / Shift+H | Suggest a move / suggest for the selected soldier |
| Tab / Enter | Next soldier / end turn |
| WASD, arrows, middle drag | Pan |
| Wheel / F | Zoom / focus the selected soldier |
| Q / E / V | Rotate the view / switch isometric and top-down |
| + / - | Playback speed |

While watching a replay: Space play / pause, N next action, Enter next turn, R restart, 1 / 2 / 3 the Allies'
view, Germany's view, the whole map. Camera keys and + / - work as in battle.

The map editor has its own keys, listed in its panel: 1–7 pick a tool, R turns a unit, Ctrl+Z undoes and
Ctrl+S saves.

## Running

You need Godot 4.7 (`Godot` below means its binary, e.g. `~/Downloads/Godot.app/Contents/MacOS/Godot`).

```sh
Godot --path .                 # play from the project
Godot --path . --editor        # open in the Godot editor
```

**macOS and Windows builds, and GitHub releases:**

```sh
tools/release.sh --build-only   # build/Normandy 1944.app, build/windows/Normandy 1944.exe and both zips in build/release/
tools/release.sh --draft        # build, then create a draft GitHub release v<version> with both zips
tools/release.sh                # build, then publish the release
```

The version is `config/version` in `project.godot`: bump it and commit before releasing. To publish, the
commit has to be pushed, the tree clean, and the [GitHub CLI](https://cli.github.com) logged in. The script
finds Godot in `~/Downloads` or `/Applications` (or set `GODOT=`) and downloads the export templates it's
missing the first time (about 1 GB). The Mac app is universal and ad-hoc signed but not notarized, so first
open it with right-click > Open. The Windows build is one 64-bit `.exe` with the game inside, unsigned, so
SmartScreen asks once (More info > Run anyway).

To try online play on one
computer, open the app twice (`open -n "build/Normandy 1944.app"`), type the same password in both, host in
one and join `127.0.0.1` in the other. Players behind the same router always use the "On your network"
address: most routers won't pass a connection to their own internet address back inside, and the joining
game says so. Over the internet, join the address the host's waiting page shows. If
neither the router nor "Let them in" gets you connected (some mobile and office networks block it), forward
UDP port 24944 on the host's router, or both use a VPN such as Tailscale.

## Testing and balancing

```sh
Godot --headless --path . -s tests/run_tests.gd         # engine, AI, saves, replays, scenarios, settings
Godot --headless --path . -s tests/advisor_tests.gd     # move suggestions and the MCP tools
Godot --headless --path . -s tests/terrain_tests.gd     # fuel drums, oil tanks, fire, mines, wheat and wire
Godot --headless --path . -s tests/agent_play.gd        # an agent plays a whole battle over the agent link (HTTP)
Godot --path . -s tools/soldier_preview.gd -- out.png 3 detail   # soldier art sheet (needs a window; add "german", "lying")
GODOT=Godot sh tests/net_resume.sh 26000 44             # two copies online: save, quit, resume, desync checks
GODOT=Godot sh tests/net_auth.sh 26100                  # passwords, wrong passwords, joining from a punched port

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
| `scripts/replay/` | Recording battles and replay files (the viewer is `scripts/view/replay_controls.gd`) |
| `scripts/net/` | Online play |
| `scripts/advisor/`, `scripts/mcp/` | Move suggestions and the agent link |
| `scenarios/` | Bundled scenarios (JSON) |
| `tests/`, `tools/` | Tests, the online test harness, the balance simulator |
