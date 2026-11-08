# Normandy 1944

[![tests][tests-badge]][tests]
[![License: MIT][license-badge]](LICENSE)

[tests-badge]: https://github.com/vistik/turn-based-war-game/actions/workflows/tests.yml/badge.svg
[tests]: https://github.com/vistik/turn-based-war-game/actions/workflows/tests.yml
[license-badge]: https://img.shields.io/badge/license-MIT-blue.svg

Turn-based squad tactics on an isometric grid, in the Normandy bocage in June 1944: the Allies against Germany,
fighting over churches, crossroads and farms between the hedgerows. Every map is fresh, the AI only knows what
its side can see, and a friend can take the other side online, with no server in between. All the art is drawn
in code; the game is built with Godot 4.7.

<!-- screenshot: TODO -->

## Download

Get the latest build from the [Releases page](https://github.com/vistik/turn-based-war-game/releases).

- **macOS**: download the `.dmg`, open it and drag Normandy 1944 to Applications. The app isn't notarized, so
  the first time, right-click it and choose Open.
- **Windows**: download the `.zip`, unzip it and run `Normandy 1944.exe`. It isn't signed, so SmartScreen asks
  once: click More info > Run anyway.

## Features

- **One click to play**: Play starts a battle against the AI on a fresh random map; Quick test drops both sides
  into a firing line on a small map.
- **Skirmish**: the hand-made Normandy village or a random map (bocage crossroads, hedgerow hamlets, a shelled
  market town, a forest edge) in four sizes, with a minimap of the very map you'll play. Play the AI, hotseat,
  or watch AI vs AI.
- **Two players online**: a campaign of 1 to 5 maps against a friend. Spend supply on units in secret before
  each map, pick a deployment, and win maps for points.
- Two actions per soldier per turn, and the exact hit chance with every modifier shown.
- Eight roles a side: officer, rifleman, SMG, MG, AT, medic, sniper and mortar, with American and German weapons.
- Directional cover, flanking, fog of war, overwatch, suppression, wounds and panic.
- Hedges you can see over standing and hide behind prone; walls, windows and whole buildings that come down
  under fire.
- Hills, cliffs and multi-storey buildings: the high ground sees further and shoots better.
- Fire that spreads through wheat and tall grass, exploding fuel drums, hidden mines, tree bursts and rocket
  backblast.
- A move preview that shows where you'd be seen and what you could shoot from there, without revealing hidden
  enemies.
- A fair AI with a game plan per battle (a flank hook, a pincer, an ambush, an all-out push and more), and
  **Suggest a move** (H), where the same AI advises you.
- Replays of every battle, with the fog of war switchable between either side's view and the whole map.
- A map and scenario editor: terrain, walls, height and storeys, units and objectives.
- An optional agent link that lets an AI agent such as Claude advise you, or play a side in a skirmish.

Every rule in detail: [docs/RULES.md](docs/RULES.md).

## Controls

| Key | Action |
|---|---|
| Left click | Select a soldier, move, pick a target |
| Right click / Esc | Cancel the action; Esc again deselects the soldier, so the left button drags the map |
| Hold right click (moving) | Count and ring the seen enemies the soldier could target from the hovered tile |
| 1 – 4 | 1 shoot (a steady shot with both actions left), 2 overwatch, 3 reload, 4 go prone / stand up |
| 5 – 0 | The role's own actions in bar order: suppressive fire, grenade, smoke, rally, medkit, mortar |
| Action bar | Bottom right: every action with its key and what's left; hover for its name |
| H / Shift+H | Suggest a move / suggest for the selected soldier |
| Space | This soldier is done for the turn; the next one is selected, and the last one ends the turn |
| Tab / Enter | Next soldier / end turn |
| WASD, arrows, middle drag, left drag (nothing selected) | Pan |
| Wheel, pinch / F | Zoom / focus the selected soldier |
| Ctrl/Cmd + wheel, Page Up / Page Down | The cursor up or down a floor in tall buildings |
| Two-finger swipe | Pan (trackpad) |
| Q / E / V | Rotate the view / switch isometric and top-down |
| + / - | Playback speed |
| M | Music on / off |

While watching a replay: Space play / pause, N next action, Enter next turn, R restart, 1 / 2 / 3 the Allies'
view, Germany's view, the whole map. The map editor lists its own keys in its panel.

## Online play

Two players is an online campaign. Both players agree a password first.

- **Host**: open Two players, type the password, set up the campaign (maps, supply, map size) and host it. The
  waiting page shows your addresses: one for your own network, one for the internet.
- **Join**: open Two players, type the same password and the address the host gives you, and join.
- Players on the same network should use the "On your network" address. Over the internet, if neither side's
  router lets the connection through, the joiner's game shows its own internet address: the host pastes it into
  **Let them in**. If that fails too, forward UDP port 24944 on the host's router or use a VPN such as
  Tailscale.
- The campaign saves between maps and at agreed turn changes, and either player can host it again to continue.

### Privacy and network

- **Direct connection, no server.** The two games talk to each other peer to peer over UDP (port 24944 by
  default). No game server, account or lobby is involved.
- **UPnP**: when hosting over the internet, the game asks your router to forward UDP port 24944 to your
  computer, with a 4-hour lease (or a permanent one, on routers that only take those). The mapping is removed
  when the game closes.
- **STUN**: to learn your public address, the game sends one STUN request to `stun.l.google.com`,
  `stun.cloudflare.com` or `stun1.l.google.com` (tried in that order). They see your IP address and nothing
  else. While a host waits, the request is repeated now and then to keep the router's mapping open.
- **The password never travels.** It is stretched with 20,000 rounds of SHA-256, and each side proves it knows
  it with an HMAC over fresh random nonces (challenge and response, in both directions). Five wrong passwords
  within a minute lock the game to everyone for a minute.
- **Agent link**: off by default. When switched on in a battle it listens on `127.0.0.1` only (port 24945),
  needs a bearer token, and refuses requests from web pages. In online games it never makes moves, and only
  reads your side's view if you allow that in Settings. See
  [docs/MCP.md](docs/MCP.md).
- **No telemetry.** The game sends no analytics, crash reports or usage data and never checks for updates.
  Apart from online play (the other player, your router and the STUN servers above) it makes no network
  connections.

## Music

The repository ships without music tracks. Drop your own MP3, OGG or WAV files into the save folder's `music/`
(or into `music/` in the project when running from source) and they play as one looping playlist in name
order. The save folder is `~/Library/Application Support/Godot/app_userdata/Normandy 1944` on macOS and
`%APPDATA%\Godot\app_userdata\Normandy 1944` on Windows. Without any tracks the game plays themes composed in
code. Press M in battle to turn the music off, or set the volume in Settings.

## Building from source

You need [Godot 4.7](https://godotengine.org) (`Godot` below means its binary, e.g.
`~/Downloads/Godot.app/Contents/MacOS/Godot`).

```sh
Godot --path .                  # play from the project
Godot --path . --editor         # open it in the Godot editor
```

Builds and GitHub releases:

```sh
tools/release.sh --build-only   # the macOS .dmg and Windows .zip, in build/release/
tools/release.sh --draft        # build, then create a draft GitHub release v<version>
tools/release.sh                # build, then publish the release
```

The version is `config/version` in `project.godot`; bump it and commit before releasing. Publishing needs the
commit pushed, a clean tree and the [GitHub CLI](https://cli.github.com) logged in. The script finds Godot in
`~/Downloads` or `/Applications` (or set `GODOT=`) and downloads missing export templates the first time.

To try online play on one computer, open the app twice (`open -n "build/Normandy 1944.app"`), go to Two players
in both, type the same password, host in one and join `127.0.0.1` in the other.

## Testing and balancing

```sh
Godot --headless --path . -s tests/run_tests.gd       # combat engine and AI
Godot --headless --path . -s tests/advisor_tests.gd   # move suggestions and the agent link's MCP tools and server
Godot --headless --path . -s tests/terrain_tests.gd   # fuel drums, oil tanks, fire, mines, wheat and wire
Godot --headless --path . -s tests/theatre_tests.gd   # theatres: Normandy as data, plus the shelved theatres
Godot --headless --path . -s tests/height_tests.gd    # hills, storeys, stairs, roofs: sight, cover, shooting, blasts
Godot --headless --path . -s tests/agent_play.gd      # an agent plays a whole battle over the agent link (HTTP)
Godot --headless --path . -s tests/simulate.gd -- 10  # AI vs AI battles, results printed
GODOT=Godot sh tests/net_resume.sh 26000 44           # two copies online: save, quit, resume, desync checks
GODOT=Godot sh tests/net_auth.sh 26100                # passwords, wrong passwords, joining from a punched port
```

`tests/net_match.gd` plays an online campaign between two processes with the AI on both sides
(`-- host PORT [size] [maps N]` and `-- join PORT`); its header lists the options, such as `cheat` and `tamper`.

Balance tools:

```sh
# AI vs AI: win rates with confidence intervals, endings, kills per role, objective control
Godot --headless --path . -s tools/balance.gd -- --scenario res://scenarios/village.json --games 50 --seed 1
Godot --headless --path . -s tools/balance.gd -- --map random --size 64 --games 20 --csv /tmp/balance.csv
# Every role against every enemy role, 1v1 and 2v2, on a small arena
Godot --headless --path . -s tools/matchups.gd -- --theatre normandy --games 8 --sizes 1,2 --out /tmp/matchups.md
# Soldier art sheet (needs a window)
Godot --path . -s tools/soldier_preview.gd -- normandy /tmp/soldiers.png 3 detail
```

## Project layout

| Path | Contents |
|---|---|
| `scripts/theatres/` | Sides, units, weapons, looks, skirmish forces and map generator choice |
| `scripts/combat/` | The rules engine: battle, map, line of sight, pathfinding, units, weapons, AI, map generators |
| `scripts/view/` | Battle scene, isometric projection and the painters for terrain and soldiers |
| `scripts/ui/` | Main menu, skirmish and two-player screens, minimap preview, settings, theme, map editor |
| `scripts/campaign/` | The two-player campaign |
| `scripts/replay/` | Recording battles and replay files |
| `scripts/net/` | Online play |
| `scripts/advisor/`, `scripts/mcp/` | Move suggestions and the agent link |
| `scripts/audio/` | Music playlist and the themes composed in code |
| `scenarios/` | Bundled scenarios (JSON) |
| `tests/`, `tools/` | Tests, the online test harness, balance tools and the release script |
| `docs/` | [Rules](docs/RULES.md), [design](docs/DESIGN.md), [agent link](docs/MCP.md), [ideas](docs/IDEAS.md) |

## Contributing, security and license

- **Contributing**: see [CONTRIBUTING.md](CONTRIBUTING.md).
- **Security**: report vulnerabilities as described in [SECURITY.md](SECURITY.md).
- **Changelog**: [CHANGELOG.md](CHANGELOG.md).
- **License**: MIT, © 2026 Visti Kløft; see [LICENSE](LICENSE).

Made with [Godot Engine](https://godotengine.org); see the in-game Credits for the engine and third-party
licenses.
