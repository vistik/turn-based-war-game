# Changelog

What changed in each release of Normandy 1944, written for players. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **After-action report.** The game-over screen and the replay controls (T) show both sides' orders, shots,
  average hit chance, hits and crits against the hits and crits the odds promised (also split into long, fair
  and good odds), how often they shot at cover or caught the enemy on the flank, damage dealt and taken, kills,
  friendly fire, healing, times pinned, panics and tiles moved, plus a tab with every soldier's own numbers:
  the numbers to judge whether the dice or the play decided it.
- **High ground.** Maps have hills, grassy banks you can climb and cliffs nobody can, and buildings have
  several floors reached by stairs. Height gives better aim, sight and cover. The mouse wheel with Ctrl/Cmd
  (or Page Up / Page Down) moves the cursor up and down a floor, and buildings in the way turn see-through.
- **Things break and burn.** Walls crumble in stages under shells, rockets, grenades and machine-gun fire, and a
  building comes down once enough of its walls are gone, burying whoever is inside. Blasts set crops and brush
  alight and fire spreads. Mines set the ground round them burning, hay bales and crates burn, collapses throw
  up dust and spill rubble (half cover), blasts blow in windows nearby, and shells bursting in trees bring down
  branches and trunks.
- **Stray rounds.** Missed rifle, pistol, SMG and sniper shots fly on and can hit someone near the line of
  fire, stop at walls or shatter windows. A stray round ending in a car, oil tank or fuel drum may set it off.
- **Area fire.** AT gunners can fire at any tile in sight, and machine gunners can rake any tile.
- **Rocket backblast.** Every rocket shot blasts the tile behind the gunner: it can set dry crops alight, burns
  and shakes anyone standing there, and bounces back off a wall or hedge to shake the gunner.
- **Trenches**, a new ground type in the map editor: full cover from outside, none along the trench.
- **Random maps come in several kinds** (bocage, hamlets, forest), are no longer mirrored, and a minimap
  previews the exact map and where everyone starts. "Another map" rolls a new one.
- **AI game plans.** Each AI side picks a plan for the battle (a left or right hook, a pincer, take two and
  hold, wait and counterattack, and more) and changes it when it stops making sense. The skirmish page lets
  you choose the plan or leave it random.
- **Smarter move previews.** Holding the right mouse button while moving shows how many targets the move
  would bring into sight. Steps of a planned move that a visible enemy would spot turn orange, with an eye
  where he would first see you.
- **Quick test battle**: a small map with both sides already in a firing line, in cover and with a target on
  the first turn. Its page lets you pick the map kind and size, how the sides start (firing line, in contact
  or spread out) and who plays (you vs the AI, AI vs AI or hotseat).
- **Music**, composed in code, with an on/off switch on the main menu, M in battle and a volume setting. You
  can add your own MP3, OGG or WAV tracks to the `music` folder in the game's save folder.
- **Credits screen** on the main menu, with the game's license and those of Godot and the code it is built on.
- A new game icon: a WW2 M1 helmet.
- The selected soldier stands out with a gold ring and a bobbing arrow that buildings never hide.
- Drag the map with the left mouse button when no soldier is selected. Esc deselects, Space puts a soldier on
  hold for the turn, and the wheel zooms.

### Changed
- **The AI thinks faster when many enemies are in sight**, up to twice as fast in big battles at close
  quarters, so the game stalls far less between its moves. It still makes exactly the same moves.
- **A simpler main menu.** One big Play button starts a battle against the AI on a fresh random map. Saved
  games sit just below it as Continue rows. Normandy is the only theatre on the menu for now.
- **Two players is now an online campaign.** The host picks the number of maps (1 to 5), starting supply,
  supply per map, how much each side may commit per map, the unit cap, map size and kind; the friend joins.
  Orders stay secret until both sides have sealed them. The campaign saves between maps and can be hosted
  again to carry on. The hotseat two-player campaign is gone.
- **Every battle is a points battle**, scored by holding objectives.
- **Fewer, clearer actions.** A shot fired with both actions left is automatically a steady shot (+15 aim).
  Soldiers stand or go prone (no crouch or hunker). Only machine gunners lay suppressive fire. The number keys
  press the action bar by position (1 shoot, 2 overwatch, 3 reload, 4 prone, then the role's own), and the
  icons share one look.
- **Snipers** hold one round, so every shot needs a reload, and firing takes both actions: a sniper fires
  every other turn.
- **Heavy machine guns** no longer set up; they can fire after moving, at -25 aim.
- **Hedges** are shoulder high: standing, you see and shoot over one with half cover; prone, it is full cover
  and blocks sight both ways. They are shredded fast by gunfire and blown away by shells.
- **Mortars** fire high explosive only, land at once with a wider scatter, and can fire blind at tiles nobody
  on the side can see (with even more scatter). Medics carry no smoke; a medkit heals 5 and steadies a shaken
  soldier.
- The side that moves first gets one action per soldier on its opening turn.
- Soldiers see and shoot further (sight 18 tiles by default), with a balance pass across the roles.
- The AI is sharper: it overwatches where enemies are likely to walk, medics reach the wounded, officers rally
  shaken men, machine guns suppress threats and soldiers keep out of fire.
- Enemies show only their side and role; their health and state stay hidden.
- Calmer, easier to read maps: bigger fields, fewer and lower hills, hedgerows in long straight lines, plain
  low hedges, quieter ground, and a cleaner move range. Normandy buildings are red brick.
- Aiming shows the field of fire in red; moving shows only the move range.
- The camera centres on the selected soldier, and on enemy turns it follows only what you can see.
- Big maps run smoother.
- The macOS download is a disk image (.dmg): open it and drag Normandy 1944 into Applications.
- Online games need both players on this version; it can't play against 0.1.0.

### Removed
- The single-player campaign and its save slot.
- Vehicles (Sherman and Panzer IV tanks) are switched off for now; infantry only.
- The recorded music tracks used during development are not included; the game plays its own composed music
  instead. (Win-condition missions and the Brecourt Manor scenario, tried out after 0.1.0, were taken out
  again before release.)

## [0.1.0] - 2026-10-31

The first release: turn-based WW2 squad tactics in the Normandy bocage, the Allies against Germany on an
isometric grid, for macOS and Windows.

- Battles with two actions per soldier per turn, directional half and full cover, flanking, fog of war,
  overwatch, suppression and pinning, wounds, panic and an officer who rallies the squad.
- Officers, riflemen, SMGs, snipers, medics, machine guns, mortars, bazooka and Panzerschreck teams, and
  Sherman and Panzer IV tanks.
- Terrain hazards: fuel drums and oil tanks that explode, fire, hidden mines, wheat that hides prone soldiers,
  barbed wire.
- A five-mission campaign with a persistent squad that gains rank, gets wounded and dies for good.
- A two-player campaign (hotseat or against the AI) with secret supply bids and deployments.
- Skirmishes on the Normandy village, random maps up to 84x84, or your own scenarios, against the AI,
  hotseat, AI vs AI, or with an AI agent playing a side.
- Online play between two computers, password protected, with no server needed.
- A map and scenario editor, saves with autosave, replays of every battle, and a "Suggest a move" advisor.

[Unreleased]: https://github.com/vistik/turn-based-war-game/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/vistik/turn-based-war-game/releases/tag/v0.1.0
