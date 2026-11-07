# Where this could go

A roadmap in the loosest sense: nothing here is decided, and the order is not a promise.

## Done

- Normandy 1944 points battles against the AI, hotseat, or AI vs AI, on a hand-made village or generated maps
  with hills and multi-storey buildings
- An online two-player campaign over a direct connection (password, NAT help, desync checks, saves both sides
  can continue)
- Save/load, recorded replays, a map and scenario editor, move suggestions, and an agent link (MCP) so an AI
  agent can play or advise
- Height, destructible cover, fire, smoke, mines and battlefield chain reactions
- macOS and Windows builds

## Open

- **Bring back what is switched off.** Vehicles (`Theatre.VEHICLES_ENABLED`), missions beyond points battles,
  and the Vietnam 1967 and Iraq 2004 theatres (`Theatres.PLAYABLE`) still live in the code but are not offered.
  Each needs a balance pass before it comes back.
- **Real art and sound.** Soldiers, terrain and vehicles are drawn procedurally and the music is synthesised;
  real sprites or simple 3D, and recorded sound, would lift the whole game.
- **More platforms.** Linux, Steam Deck and web exports, and a touch pass on the controls for tablets and
  handhelds. Turn-based play suits them.
- **Asynchronous online play.** The engine is deterministic and every action is a command, so a turn can be sent
  as a few commands. A small relay would let players take turns hours apart and reach each other behind any NAT.
- **Better AI.** Path choice around overwatch, coordinated flanking, falling back, difficulty levels, and its
  thinking moved off the main thread.
- **Signed and notarised builds**, so macOS and Windows stop warning on first launch.
- **A translation pass**: the interface text is English only.
