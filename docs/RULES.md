# Rules in detail

How a battle in Normandy 1944 plays, rule by rule. The short version is in the [README](../README.md); the
architecture and the reasoning behind the rules are in [DESIGN.md](DESIGN.md).

## Turns and actions

- Two actions per soldier per turn: move, dash, or move and act. Path cost depends on terrain, hedgerows, walls
  and stance. The exact hit chance is shown, with every modifier itemised.
- The side that moves first has only one action per soldier on its opening turn, so it can't fire an aimed
  volley or dash onto an objective before the other side has moved at all.
- A soldier who shoots with both actions left (nothing else done that turn) takes a steady shot: +15 aim.
- A short list of actions per soldier: move, shoot, overwatch, reload and go prone for everyone, plus what the
  role brings (grenades, suppressive fire, rally, smoke, medkit, mortar).
- Objectives (church, crossroads, farm, hilltops) score victory points every round. Reinforcement waves arrive
  mid-battle.

## Sight and range

- Soldiers see 18 tiles (snipers further) and rifles stay accurate to about 9-10, so a unit can shoot about as
  far as it can run.
- Directional half and full cover, flanking, and line of sight that steps out around corners.
- Fog of war hides what the enemy does out of sight: no turning, stance changes, reloading, healing or damage
  shown for units you can't see, only what you'd notice from afar (a mortar firing, smoke rising, a mine
  going off). On the enemy's turn the camera only follows the part of a move your side can see; a move
  entirely out of sight leaves the camera where it is. Before an enemy shot or throw plays, the camera brings
  shooter and target on screen.
- Enemies show only who and where they are: their side and role. Never their health, suppression, wounds or
  status (overwatch); a hit on one just says HIT. Move suggestions and the agent link follow the same rule.

## Planning a move

- The planned move warns where you'd be seen: steps an enemy your side can see now would spot the soldier
  turn orange, an eye marks where each one first would, a dashed line runs back to him, and the panel names
  them. Enemies out of sight are never counted, so the preview gives nothing away.
- Moving shows the cover at the destination, and "EXPOSED TO 2" if seen enemies would have it in the open.
- Hold the right mouse button while moving to see how many seen enemies the soldier could shoot at from the
  hovered destination ("3 TARGETS", the targets ringed in red; "NO SHOT LEFT" if the move would leave no
  action to fire). Only enemies already in sight count.
- Aiming (1) shows the selected soldier's field of fire in red: everywhere he can see, the deeper red where the
  gun is at its best. Moving shows the move range: blue to walk, yellow to dash.

## Roles

- **Officer, Rifleman, SMG.** The officer can rally the squad.
- **Medic**, with medkits: each heals 5, treats a wound and takes 40 off the patient's suppression (a shaken
  man can be treated even unhurt).
- **MG**, the only role that lays down suppressive fire; it pins and shakes everyone round the target. It can
  also rake any tile in sight, enemy or not (Fire suppressive, then click a tile): it shakes every enemy round
  it and chews down the wall on the near side. After moving, a heavy MG fires at -25 aim and can't lay
  suppressive fire.
- **Sniper**: moves or fires in a turn, not both. Firing takes both actions and he holds one round, so after
  every shot he must reload, and can't reload and fire in the same turn.
- **Mortar**: scattering high explosive shells that land at once (the target circle shows where a round may
  come down). It is indirect fire: it can shell a tile nobody on your side sees, but that round scatters 1.5
  times as far.
- **AT** with Bazooka or Panzerschreck. It can fire at any tile in sight, enemy or not (Shoot, then click a
  tile): +20 to hit a patch of ground, a miss lands short or long. It bursts there, breaking walls and cover,
  maybe starting a fire, and hits anyone hidden on the tile with the full warhead. A rocket or MG burst can be
  aimed at the wall in front of a tile, and fired blind into smoke or dust.
- **Backblast**: every rocket blasts the tile behind the gunner. In dry crops or tall grass it may set it
  alight, and it burns and shakes anyone standing there. With a wall, hedge or rock right behind him, or firing
  from inside a room, it bounces back and shakes the gunner himself.

## Morale and wounds

- Suppression and pinning, wounds that slow soldiers for two turns, panic when friends die, and an officer who
  can rally the squad.
- Going prone has a trade-off: very hard to hit at range and hidden in wheat, but crawls and is exposed up
  close.
- Soldiers fall away from what killed them (thrown back by blasts), drop their weapon, and bleed out slowly.

## Stray fire

- Grenades scatter, and missed rockets and MG bursts can hit someone else, friends included. The odds panel
  tells you who is at risk.
- Missed rifle, pistol, SMG and sniper rounds fly on past the target, up to 5 tiles, until a wall, a tree or a
  glazed window stops them (the window shatters). Anyone close to their flight, friend or foe, may be hit (10%
  each, nearest first, half damage); a wall behind the target keeps whoever is behind it safe.
- A missed rifle, pistol or SMG round that ends in an oil tank or fuel drums may set it off.

## Hedges, walls and buildings

- Hedges are shoulder high: standing behind one you see and shoot over it but only get half cover; lie down
  and it's full cover, but you see nothing past it (and nobody sees you through it). They don't last: every
  rifle shot at someone behind one strips it a stage (three and it's gone), a machine gun burst breaches it, a
  grenade nearby too, and a shell or rocket blows it away.
- Walls come down in stages: damaged (shell holes, still full cover), breached (a jagged gap: half cover, climb
  and shoot through), gone. Windows, low walls and fences go in two. AT rockets and mortar rounds knock two
  stages off the walls round where they land (one further out); a grenade one. A rocket fired at someone
  behind a wall breaches it. Machine guns shoot fences, hedges and windows apart a stage a burst, but an aimed
  shot only chips stone and brick; suppressive fire knocks even a brick wall a stage further every burst
  (three and it's gone).
- Brick and stone walls throw up dust when they're breached or brought down: both sides of the gap fill with
  dust (blocking sight like smoke) through the other side's reply, and rubble spills onto the open tile on the
  far side from the blast or gun. Rubble is slow ground, but half cover on every side, like a crater.
- Blast concussion blows in windows: every glazed window within two tiles of an explosion's reach loses its
  glass (the frame stays half cover). Climbing in or out through a glazed window smashes it.
- Hits on soldiers upstairs strike the wall in front of them, and a blast on an upper floor knocks a stage off
  that room's outer walls. A building of two storeys collapses once 40% of its outer walls (doorways not
  counted) are breached or gone, a taller one sooner (5% less per storey, at least a quarter): it becomes a
  heap of rubble inside broken stumps of wall, under a dust cloud for two rounds, with rubble spilling into the
  street. Everyone in it is hurt and shaken, those upstairs worse the further they fall.

## Height

- Ground rises in levels on rolling hills, ridges and knolls. A one-level step is a grassy bank: anyone can
  walk up it for one more movement (going down is free). Two levels or more is a cliff that nobody climbs.
  Some hills are escarpments, sloping up on most sides with one side a cliff. A hilltop can be an objective
  ("Hill 104").
- Buildings of two or three storeys (the church's bell tower, village houses and farmhouses) have stairs up
  through every floor to a flat roof. Upstairs, cover is the walls and windows; the roof's parapet is half
  cover. Only one soldier stands on a tile, whatever the floor.
- Shooting down from a level or more above gives the high ground (+10 aim) and ignores low cover; from two
  levels up, full cover only counts as half.
- Higher up you see 2 tiles further per level and over walls and hedges. Ridges, floors and roofs block sight,
  and upstairs a doorway below is wall.
- Blasts only hurt those within a level of where they go off. Shells land on the roof; grenades go for the
  floor the enemy is on.
- The cursor has a height: Ctrl/Cmd + mouse wheel (or Page Up / Page Down) raises and lowers it a floor at a
  time. The building under the cursor opens up at that floor, and a tall building in front of the cursor or
  the planned move turns see-through.

## Fire and hazards

- **Fuel drums and oil tanks** explode when shot or caught in a blast, set off others nearby, and leave the
  ground burning. Nobody can enter fire, and anyone in it is burnt at the start of their turn. A fire fills
  its tile with smoke (blocking sight) until two turns after it dies, and a soldier who starts his turn next to
  one is shaken by the heat.
- **Blast fires**: grenades, mortar rounds and rockets set what burns alight for a couple of turns (four in dry
  crops and tall grass). Dry crops and tall grass catch easily, grass and scrub less; roads, rubble, water and
  floors indoors never. A soldier lying in crops or tall grass may catch fire too, and burns unless he gets
  out. Crops burn away to scorched ground.
- **Spreading fire**: once a round every fire may creep into the tiles beside it: about one in five for wheat
  and tall grass, less for trampled crops and scrub, rarely over bare grass, never across roads, rubble,
  water, walls or hedges. A fuel drum or oil tank next to a fire may cook off, and a hay bale catches (about
  one in three; a crate one in ten). Burnt crops turn to scrub, so fires die out once the crops are gone.
- **Mines** are hidden. Soldiers may spot them as they walk past, clear spotted ones from next to them, and
  blasts set them off. A mine going off sets the ground round it alight.
- **Tree bursts**: a mortar shell that comes down among trees bursts in the branches: a wider blast that hurts
  more, so woods are no shelter from shellfire. Trees a blast catches are splintered to scrub or brought down
  as a fallen trunk (half cover that blocks the way).
- **Wheat** is trampled flat when soldiers walk through it (crawling leaves it standing), so it stops hiding
  anyone.
- **Barbed wire** is slow going on foot; explosions flatten it.
- **Trenches** (painted in the map editor) are dug below the ground: full cover against fire from outside, but
  none along the trench, so fire down the trench line catches everyone in it. A little slow to walk, and it
  costs 1 more to climb in or out. From a trench you see along it and only 3 tiles past its edge, and nobody
  further out sees in (except from higher up).

## Telling units apart

- A badge over each soldier shows his role as an icon (star for the officer, red cross for the medic,
  crosshair for the sniper, and so on), and a ring underneath in the side's colour shows his side.
- Each role carries its own gear: officer's cap, MG ammo belt, sniper's helmet scrim, mortar baseplate, rocket
  bag. Americans wear khaki field jackets, canvas leggings and the round M1 helmet; Germans field grey with
  jackboots and the flared Stahlhelm.
