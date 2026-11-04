# Normandy 1944

Turn-based squad tactics on an isometric grid, inspired by UFO: Enemy Unknown and XCOM 2, in three theatres
of war that share one engine: the Normandy bocage in June 1944 (the Allies against Germany), Vietnam in 1967
(the US Army against the Viet Cong) and Iraq 2004 (the Coalition against insurgents).
Built with Godot 4.7 in GDScript; all art is drawn in code.

The rules and architecture are in [docs/DESIGN.md](docs/DESIGN.md), the agent link in [docs/MCP.md](docs/MCP.md),
and ideas for later in [docs/IDEAS.md](docs/IDEAS.md).

## Features

**Theatres**
- **For now only Normandy 1944 is playable.** Vietnam and Iraq 2004 are switched off in the menus and the map
  editor (`Theatres.PLAYABLE`) while WW2 gets the attention; their code, tests and tools still run, and their
  saves, replays and scenarios still load. Add an id back to `PLAYABLE` and the main menu shows a theatre
  picker again; every way to play then starts in the theatre picked.
- Each theatre has its own colour scheme for menus and the battle screen, so it's plain which one is picked:
  olive and khaki for Normandy, jungle green and bamboo amber for Vietnam, slate and desert sand for Iraq 2004.
- The engine (movement, shooting, cover, suppression, AI, online, replays) is shared. Each theatre brings its own
  sides, units, weapons, uniforms and vehicles, maps, campaign and a few rules of its own
  (`scripts/theatres/`).
- **Normandy 1944**: everything below. Allies and Germany field the same kinds of soldier with their own weapons.
- **Vietnam 1967**: lopsided on purpose.
  - The **US Army** has few soldiers. They are tough, good shots and slow under heavy loads: squad leader,
    riflemen, an M60 gunner, an M79 grenadier who lobs grenades far, a medic, a sniper and an
    **RTO** whose radio calls **artillery** or **napalm** onto anything he can see. Napalm burns jungle and grass
    away. Reinforcements **fly in by Huey** to a landing zone.
  - The **Viet Cong** have many soldiers. They are cheap, fast and poorly armed: cadres, guerrillas with SKS
    rifles, AK-47 assault troops, RPD gunners, RPG teams (the warhead tears cover apart), a mortar, and
    **sappers** who hide **punji traps** (hard to spot, wound whoever steps in, tanks crush them). They move
    through **tunnels**: from one of their entrances to another in a turn. Their reinforcements come up out of
    the ground. Americans find entrances by walking past or seeing them used, and blow them in with G.
  - New ground: **jungle** (slow, hides anyone in it beyond 3 tiles, and sight reaches only one tile into it),
    **rice paddies** behind low dykes (slow, bog vehicles down) and **elephant grass** (hides prone soldiers).
    Maps have a hamlet of bamboo huts, a trail crossing and a landing zone cut out of the jungle.
  - The Americans score for **ground**; the Viet Cong score for **every American killed**.
- **Iraq 2004**: Helmand's walled compounds, wheat fields and irrigation ditches, or an Iraqi town of
  stone houses, wrecked cars and concrete barriers (the map's seed picks one).
  - The **Coalition** wears **body armour** (a point off every hit until grenades shred it). It has an **EOD
    tech** who spots IEDs nearly every time, a **JTAC** who calls precise **air strikes** on what he sees, a SAW
    gunner, a marksman and a medic. (Its MRAP, like Vietnam's M113 and Normandy's tanks, is switched off for now.)
  - The **insurgents** are many and light: fighters with AKs, PKM gunners, RPG-7s, a Dragunov sniper, a mortar
    and **bomb makers**. Bomb makers plant **IEDs** (a big blast that cuts through armour) and **set them off
    remotely** (K) when they can see them. IEDs are already buried along the road in.
  - The Coalition scores for ground, the insurgents 1.75 times as much for every Coalition soldier killed (shown multiplied by 4: 4 per objective per round, 7 per kill).

**Music**
- The tracks in `music/` (MP3, OGG or WAV) play as one playlist, in name order, looping round all of them
  through menus and battles. Tracks added to the save folder's `music/` join the playlist.
- Turn it off with M in battle, or set the volume in Settings.
- With no tracks at all, the game falls back to themes composed in code for each theatre (a menu and a battle
  theme each).

**Battles**
- Two actions per soldier per turn: move, dash, or move and act. Path cost depends on terrain, hedgerows, walls
  and stance. The exact hit chance is shown, with every modifier itemised.
- The planned move warns where you'd be seen: steps an enemy your side can see now would spot the soldier
  turn orange, an eye marks where each one first would, a dashed line runs back to him, and the panel names
  them. Enemies out of sight are never counted, so the preview gives nothing away.
- Soldiers see 18 tiles (snipers further) and rifles stay accurate to about 9-10, so a unit can shoot about as
  far as it can run.
- A short list of actions per soldier: move, shoot, overwatch, reload and go prone for everyone, plus what the
  role brings (grenades, suppressive fire, rally, smoke, medkit, mortar...).
- A soldier who shoots with both actions left (nothing else done that turn) takes a steady shot: +15 aim.
- The side that moves first has only one action per soldier on its opening turn, so it can't fire an aimed
  volley or dash onto an objective before the other side has moved at all.
- Snipers move or fire in a turn, not both: after moving they can't shoot or go on overwatch, and after firing
  they can't move until their next turn. Heavy machine guns fire best set up: after moving they fire at -25 aim
  and can't lay suppressive fire.
- Firing takes a sniper both actions and he holds one round, so after every shot he must reload, and can't
  reload and fire in the same turn.
- Directional half and full cover, flanking and line of sight that steps out around corners. Fog of war,
  overwatch, and destructible cover with craters.
- Hedges are shoulder high: standing behind one you see and shoot over it but only get half cover; lie down
  and it's full cover, but you see nothing past it (and nobody sees you through it). They don't last: every
  rifle shot at someone behind one strips it a stage (three and it's gone), a machine gun burst breaches it,
  a grenade nearby too, and a shell or rocket blows it away.
- Walls come down in stages: damaged (shell holes, still full cover), breached (a jagged gap: half cover, climb
  and shoot through), gone. Windows, low walls and fences go in two. Tank shells, AT rockets and mortar rounds
  knock two stages off the walls round where they land (one further out); a grenade one. A tank shell or
  rocket fired at someone behind a wall breaches it. Machine guns shoot fences, hedges, bamboo and windows
  apart a stage a burst, but only chip stone, brick and mud.
- Hits on soldiers upstairs strike the wall in front of them, and a blast on an upper floor knocks a stage off
  that room's outer walls. A building of two storeys collapses once 40% of its outer walls (doorways not
  counted) are breached or gone, a taller one sooner (5% less per storey, at least a quarter): it becomes a heap of rubble inside broken stumps of wall. Everyone in it is hurt and shaken, those
  upstairs worse the further they fall.
- Climbing in or out through a glazed window smashes it: "CRASH", and from then on it's an empty frame with
  shards in the corners (still half cover). Mud-brick and bamboo windows have no glass to break.
- Buildings look like their war: Normandy's grey limestone with green shutters and slate roofs, Vietnam's
  ochre colonial stucco with blue-green shutters and red tile roofs (and bamboo huts), Iraq's rendered
  concrete with iron window grilles and pale flat roofs (and mud-brick compounds). Walls standing in rubble
  or by a crater are drawn shot up, broken off at uneven heights; bamboo huts are burnt to charred stumps.
  Shelled towns in Normandy and Iraq have ruined houses, and now and then a Vietnamese hut is burnt out.
- Fog of war hides what the enemy does out of sight: no turning, stance changes, reloading, healing or damage
  shown for units you can't see, only what you'd notice from afar (a mortar firing, smoke rising, a mine
  going off). On the enemy's turn the camera only follows a move to the part of it your side can see (a
  soldier hidden in the wheat doesn't count); a move entirely out of sight leaves the camera where it is.
  Before an enemy shot or throw plays, the camera brings shooter and target on screen, so you see the shot
  before what it does; a shell or rocket hit shows its explosion before the damage and the kill.
- Enemies show only who and where they are: their side and role. Never their health, suppression, wounds or
  status (overwatch); a hit on one just says HIT. The agent link and move suggestions
  follow the same rule.
- Overwatch holds its fire for targets it can't hurt, such as rifles and machine guns against a tank.
- The selected unit stands out: a pulsing gold ring and glow under it and a bobbing gold arrow over its
  health bar.
- Aiming (1) shows the selected soldier's field of fire in red: where he can shoot, which is everywhere he
  can see (shooting range is sight range; the further off, the harder to hit, by the weapon's range table),
  the deeper red where the gun is at its best. Moving shows only the move range: blue to walk, yellow to dash.
- Moving shows the cover at the destination, and "EXPOSED TO 2" if seen enemies would have it in the open.
- Hold the right mouse button while moving to see how many seen enemies the soldier could shoot at from the
  hovered destination ("3 TARGETS" in place of "EXPOSED TO", the targets ringed in red; "NO SHOT LEFT" if the move would leave no action to fire).
  Only enemies already in sight count, so it never reveals anyone hidden.
- Soldiers fall away from what killed them (thrown back by blasts), drop their weapon, and bleed out slowly;
  tanks brew up, their turret blown off its ring.
- Suppression and pinning, wounds that slow soldiers for two turns, panic when friends die, and an officer
  who can rally the squad.
- Roles:
  - Officer, Rifleman, SMG and Sniper
  - Medic, with medkits: each heals 5, treats a wound and takes 40 off the patient's suppression (a shaken man
    can be treated even unhurt)
  - MG, the only role that lays down suppressive fire (from where it set up); it pins and shakes everyone
    round the target
  - Mortar, with scattering high explosive shells that land at once, without ranging shots (the target
    circle shows where a round may come down). It is indirect fire: it can shell a tile nobody on your side
    sees, but that round scatters 1.5 times as far
  - AT with Bazooka or Panzerschreck
  - Sherman and Panzer IV tanks: switched off for now (no roster, wave, shop or editor offers them), as are
    Vietnam's M113 and Iraq's MRAP. Their rules are kept for when they come back.
- Tanks have front, side and rear armour. They turn slowly (each 45° costs movement) and can back up. A tank's
  move takes two clicks: where to go, then where to face when it gets there (click the destination again to
  keep the heading); click the selected tank itself to turn it on the spot. They flatten crates, walls,
  hedges and trees, and leave burning wrecks.
- Going prone has a trade-off: very hard to hit at range and hidden in wheat, but crawls and is exposed up
  close.
- Suppressive fire from machine guns. Grenades scatter, and missed rockets, tank shells and MG bursts can hit
  someone else, friends included. The odds panel tells you who is at risk.
- Missed rifle, pistol, SMG and sniper rounds fly on past the target, up to 5 tiles, until a wall, a tree or
  a glazed window stops them (the window shatters). Anyone close to their flight, friend or foe, may be hit
  (10% each, nearest first, half damage); a wall behind the target keeps whoever is behind it safe.
- Objectives (church, crossroads, farm) score victory points every round. Reinforcement waves arrive mid-battle.
- **Height**:
  - Ground rises in levels on rolling hills, ridges and knolls. A one-level step is a grassy bank, drawn as a
    slope: anyone can walk up it for one more movement (going down is free). Hills are drawn low, and higher
    ground a shade lighter per level, so they don't hide the tiles, hedges and move range behind them. Two levels or more is a cliff,
    drawn as a sheer face of rock, that nobody climbs.
    Random maps raise hills on rough ground, off the roads, buildings and both sides' starts. In Normandy
    hills are open knolls, with no hedges or walls across them, and hedgerows run in long straight lines
    with two-tile gateways: never along a road, never two side by side, never round a sliver of a field,
    and without short stubs. Some hills are escarpments, sloping up on
    most sides with one side a cliff. A hilltop can be an objective ("Hill 104").
  - Buildings of two or three storeys (the church's bell tower, village houses and farmhouses, Iraqi town
    houses, compound towers) have stairs up through every floor to a flat roof. Upstairs, cover is the walls
    and windows; the roof's parapet is half cover. Only one soldier stands on a tile, whatever the floor.
  - Shooting down from a level or more above gives the high ground (+10 aim) and ignores low cover; from two
    levels up, full cover only counts as half.
  - Higher up you see 2 tiles further per level and over walls and hedges. Ridges, floors and roofs block
    sight, and upstairs a doorway below is wall.
  - Blasts only hurt those within a level of where they go off. Shells and air strikes land on the roof;
    grenades go for the floor the enemy is on.
  - The cursor has a height. Ctrl/Cmd + mouse wheel (or Page Up / Page Down) raises and lowers it a floor at a time,
    starting at the selected soldier's floor. The building under the cursor opens up at that floor (the floors
    above are cut away) while every other building keeps its roof on. A dashed stalk drops from a raised
    cursor to the ground, the move range shows the tiles you can reach on that floor, and a click goes exactly
    there, or says it's out of reach. A tall building standing in front of the cursor or the planned move,
    or one the move walks through below its roof, turns see-through, so a move behind it doesn't look like
    one onto its roof.
- Terrain hazards:
  - **Fuel drums and oil tanks:** they explode when shot, caught in a blast or run over by a tank, set off
    others nearby, and leave the ground burning. Nobody can enter fire, and anyone in it is burnt at the
    start of their turn. A fire fills its tile with smoke (blocking sight) until two turns after it dies, and a
    soldier who starts his turn next to one is shaken by the heat.
  - **Blast fires:** grenades, mortar rounds, rockets and tank shells set what burns alight for a couple of
    turns (four in dry crops and tall grass): dry crops and tall grass catch easily, grass, scrub and jungle
    less; roads, rubble, water and floors indoors never. A soldier lying in crops or tall grass may catch
    fire too (at half the chance), and burns unless he gets out. Crops and undergrowth burn away to scorched ground.
  - **Spreading fire:** once a round every fire may creep into the tiles beside it, by their ground: about
    one in five for wheat and tall grass, less for trampled crops, scrub and jungle, rarely over bare grass,
    never across roads, rubble, water, walls or hedges, nor under a tank (under a soldier only in crops or
    tall grass, at half the chance). A fuel drum or oil tank
    next to a fire may cook off. Burnt crops turn to scrub, which rarely catches, so fires die out once the crops are gone.
  - **Mines:** hidden. Soldiers may spot them as they walk past (tank crews never do), clear spotted ones
    from next to them, and blasts set them off.
  - **Wheat:** trampled flat when soldiers walk through it (crawling leaves it standing), so it stops hiding
    anyone.
  - **Barbed wire:** slow going on foot; tanks and explosions flatten it.
  - **Trenches:** dug below the ground. Full cover against fire from outside, but none along the trench, so
    fire down the trench line from its end catches everyone in it. A little slow to walk (1.5), and it costs
    1 more to climb in or out. From a trench you see along it and only 3 tiles past its edge, and nobody
    further out sees in (except from a level or more higher up), so a trench line is fought at close quarters.
    Blasts don't fill them in. Paint them in the map editor.
- Units are easy to tell apart:
  - a badge over each one shows its role as an icon (star for the officer, red cross for the medic, crosshair
    for the sniper, and so on);
  - a ring underneath in the side's colour shows which side it's on;
  - each role carries its own gear: officer's cap or striped helmet, MG ammo belt, sniper's helmet scrim,
    mortar baseplate, rocket bag;
  - the sides wear their own uniforms: Americans in khaki field jackets, canvas leggings and the round M1
    helmet, Germans in field grey with jackboots and the flared Stahlhelm. Machine gunners kneel behind their gun
    while they stay put, and everyone holds their rifle at the ready.

**Ways to play**
- **Main menu**: built around one big **Play** button (focused, so Enter works too): one click starts a battle
  against the AI on a fresh standard 44x44 random map, fighting for the objectives, both sides spread out,
  the AI on a random game plan. Saved games sit in compact Continue rows under it, the other modes (Campaign,
  Skirmish, Two players, Online) in a grid below, and Quick test, Replays, Map editor, Settings and Quit in
  a quiet footer.
- **Campaign**: five missions with one persistent squad. Soldiers gain XP and rank, get wounded and die for
  good. Supplies buy replacements.
- **Two-player campaign** (hotseat, or against the AI):
  - 3 to 5 maps, each worth a different number of points (1–5), and one pool of 100 supply per side for the
    whole campaign.
  - Before every map both sides secretly commit 12–45 supply and buy units with it (2 to 8 supply a soldier).
    Committed supply is gone; the rest carries over to later maps.
  - Each side also picks a deployment: balanced, left or right flank, and offensive (deployed further
    forward) or defensive (further back, behind sandbags).
  - Win a map to take its points; a draw splits them. Most points wins.
- **Skirmish** on the hand-made Normandy village, a random map, or your own scenarios.
  - Random maps come in several kinds per theatre, picked by name, in four sizes (small 32x32, standard 44x44,
    large 64x64, huge 84x84 with bigger forces):
    - Normandy: bocage crossroads, hedgerow hamlets, a shelled market town, a forest edge.
    - Vietnam: a paddy valley, a jungle trail, delta hamlets.
    - Iraq 2004: the Helmand green zone, an Iraqi town, a desert village with a wadi and a checkpoint.
  - A minimap shows the very map you are about to play (ground, woods, hedges and walls, buildings,
    objectives and both sides' starts); "Another map" rolls a new one of the same kind.
  - No map is a mirror image. Roads wind round rough ground, villages grow along them, fields are an
    irregular patchwork, and each side's half is its own. Objectives are picked from the map's landmarks
    (church, crossroads, farm, bazaar, landing zone...) so that both sides walk about as far to them. Play vs AI, hotseat, watch AI vs AI, or let an AI agent play a side
  (Agent vs AI, Me vs agent). On the village and random
  maps each side picks a deployment, as in the two-player campaign: spread out along the whole edge, corner
  to corner (the default), grouped at the usual spawns, balanced or massed on the left or right flank, offensive (further forward) or defensive (further back, behind sandbags),
  in contact (a few tiles apart either side of the middle) or random. The minimap shows where each side's soldiers will start (a random deployment only once the
  battle begins), and changes as you pick. Online, the host picks both.
- **Quick test battle** (main menu footer): one click starts a small 32x32 random map in the chosen theatre, against
  the AI, with both sides already in contact mid-map: the fastest way to try something out.
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
- **Map and scenario editor**: paint terrain, cover and walls, ground height, storeys and stairs (the Height
  tool), place units, objectives and reinforcement spawns, and save
  scenarios as JSON. Play or test them with the AI straight away.

**AI**
- A utility AI that plays fair: it only knows what its side can see. It weighs cover facing the enemy,
  objectives, stances, tank armour, friendly-fire risk and the score.
- **Game plans**: each AI side picks a plan for the whole battle, so no two games against it play alike:
  broad front, take two neighbouring objectives and dig in on them, a left or right hook rolling up the
  objectives from that flank, a punch through the centre (keeping together), a pincer on both flanks, an
  armoured spearhead (infantry following behind the tanks), wait near home and counterattack, an all-out push,
  or bleeding the enemy from cover at long range. Plans only come up where they fit (tanks, enough objectives). It changes plan when it stops making sense: the spearhead without tanks, the ambush
  when its time is up or it falls behind, and anything turns into an all-out push when far behind late on.
  Its plan is shown in the log when the battle ends (and at the start when watching AI vs AI).
  In a skirmish, "Choose AI plans" sets the plan for each side the AI plays, or leaves it random (the
  default); a plan that doesn't suit the battle falls back to random.
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
| Left click | Select a soldier, move, pick a target. Tanks: click where to go, then where to face; click the selected tank to turn it on the spot |
| Right click / Esc | Cancel the action; Esc again deselects the soldier, so the left button drags the map |
| Hold right click (moving) | Count and ring the seen enemies the soldier could target from the hovered tile |
| 1 – 4 | The actions every soldier has, always on the same keys: 1 shoot (a steady shot with both actions left), 2 overwatch, 3 reload, 4 go prone / stand up (tanks have no 4) |
| 5 – 0 | The role's own actions, numbered in the order they sit on the bar: suppressive fire, grenade, smoke, rally, medkit, mortar, trap, IED, then the ones that only show up now and then (a tunnel entrance, a mine or tunnel next to the soldier). An officer: 5 grenade, 6 smoke, 7 rally. Gear that runs out stays on the bar, greyed, so the keys never shift |
| Action bar | Bottom right: every action the soldier has as an icon with its key in the corner and what's left (grenades, smoke, medkits, ammo); hover for its name. The icons share one look: ink only, the same size and line weight |
| Shoot on drums / an oil tank | In shoot mode, click fuel drums or an oil tank to blow them up |
| H / Shift+H | Suggest a move / suggest for the selected soldier |
| Space | Hold: this soldier is done for the turn (keeps the actions he has left unspent); the next one is selected, and the last one to hold ends the turn |
| Tab / Enter | Next soldier / end turn (the camera centres on each newly selected soldier) |
| WASD, arrows, middle drag, left drag (no soldier selected) | Pan |
| Wheel, pinch / F | Zoom / focus the selected soldier |
| Ctrl/Cmd + wheel | On maps with tall buildings: the cursor up or down a floor (the building under it opens at that floor). Elsewhere: zoom |
| Two-finger swipe | Pan (trackpad) |
| Q / E / V | Rotate the view / switch isometric and top-down |
| Page Up / Page Down | The cursor up / down a floor, like Ctrl/Cmd + wheel |
| + / - | Playback speed |
| M | Music on / off |

While watching a replay: Space play / pause, N next action, Enter next turn, R restart, 1 / 2 / 3 the Allies'
view, Germany's view, the whole map. Camera keys and + / - work as in battle.

The map editor has its own keys, listed in its panel: 1–8 pick a tool, R turns a unit, Ctrl+Z undoes and
Ctrl+S saves.

## Running

You need Godot 4.7 (`Godot` below means its binary, e.g. `~/Downloads/Godot.app/Contents/MacOS/Godot`).

```sh
Godot --path .                 # play from the project
Godot --path . --editor        # open in the Godot editor
```

**macOS and Windows builds, and GitHub releases:**

```sh
tools/release.sh --build-only   # build/Normandy 1944.app, build/windows/Normandy 1944.exe, the macOS .dmg and Windows .zip in build/release/
tools/release.sh --draft        # build, then create a draft GitHub release v<version> with the .dmg and .zip
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
Godot --headless --path . -s tests/theatre_tests.gd     # theatres: Normandy as data, Vietnam and Iraq 2004 rules and maps
Godot --headless --path . -s tests/height_tests.gd      # hills, storeys, stairs, roofs: moving, sight, cover, blasts, maps, AI
Godot --headless --path . -s tests/agent_play.gd        # an agent plays a whole battle over the agent link (HTTP)
Godot --path . -s tools/soldier_preview.gd -- out.png 3 detail   # soldier art sheet (needs a window; add "german", "lying", "vietnam", "modern")
GODOT=Godot sh tests/net_resume.sh 26000 44             # two copies online: save, quit, resume, desync checks
GODOT=Godot sh tests/net_auth.sh 26100                  # passwords, wrong passwords, joining from a punched port

# AI vs AI balance: win rates with confidence intervals, endings, kills per role, objective control
Godot --headless --path . -s tools/balance.gd -- --scenario res://scenarios/village.json --games 50 --seed 1
Godot --headless --path . -s tools/balance.gd -- --map random --size 64 --games 20 --csv results.csv
Godot --headless --path . -s tools/balance.gd -- --theatre vietnam --map random --size 44 --games 20
# Unit against unit: every role against every enemy role, 1v1 and 2v2, on a small arena (win rates per matchup)
Godot --headless --path . -s tools/matchups.gd -- --theatre normandy --games 8 --sizes 1,2 --out matchups.md
```

A single online match between two processes, with the AI on both sides:
`tests/net_match.gd -- host PORT [size]` and `-- join PORT`. See the header of that file for options.

## Project layout

| Path | Contents |
|---|---|
| `scripts/theatres/` | The theatres: each one's sides, units, weapons, looks, skirmish forces, campaign and map generator choice |
| `scripts/combat/` | The rules engine: battle, map, line of sight, pathfinding, units, weapons, AI, map generators, scenarios |
| `scripts/view/` | Battle scene, isometric projection and procedural painters for terrain, soldiers and tanks |
| `scripts/ui/` | Main menu and campaign screens, map minimap preview, settings, theme, map editor |
| `scripts/campaign/` | The campaign |
| `scripts/replay/` | Recording battles and replay files (the viewer is `scripts/view/replay_controls.gd`) |
| `scripts/net/` | Online play |
| `scripts/advisor/`, `scripts/mcp/` | Move suggestions and the agent link |
| `scenarios/` | Bundled scenarios (JSON) |
| `tests/`, `tools/` | Tests, the online test harness, the balance simulator |
