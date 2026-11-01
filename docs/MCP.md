# Move suggestions and the agent link (MCP)

Two ways to get help during a battle, where **you** give the orders, and a third where an agent plays a whole
side by itself.

- **Suggest a move (H)**: the game's own tactical AI looks at your side of the battle and suggests one move.
- **Agent link**: the game runs a small [Model Context Protocol](https://modelcontextprotocol.io) server, so an AI
  agent such as Claude Code or Claude Desktop can read your side of the battle, think it through with you, and
  put proposals on your screen.

## Suggest a move

Press **H** (or the **H Suggest** button) on your turn. The AI picks the best move for your side; **Shift+H** asks
about the selected soldier only. The game then:

- selects the soldier and outlines him,
- draws the path and rings the destination (with cover shields), or rings the target with the hit chance,
- shows a card in the bottom left with the reason, e.g. *"Move Sullivan to the wall: full cover facing 2 enemies,
  then shoot Weber at 65%"* or *"Garcia: shoot Neumann: 90% hit, flanked (65% crit), 90% kill chance"*,
- and logs it.

Nothing happens until you act: click the highlighted tile or target (shooting, grenades and medkits already have the
right targeting mode on), or press **Accept**. **Esc** or **Dismiss** clears it, and so does any move you make.

The suggestions come from `AdvisorAI`, a `TacticalAI` with its own memory (separate from any AI opponent). It plays
fair: it only knows what your side can see, plus where it last saw enemies. Unlike the opponent AI, it guesses where
the enemy started from the mirrored map, not from their real positions, so asking mid-battle gives nothing away.
The reasons are read from the AI's own scoring (cover against known enemies, danger, kill chance, follow-up shot),
without changing what it picks.

## The agent link

**Off by default.** Turn it on in a battle with the **Agent link** button (next to Save & quit). It stays on for later
battles until you turn it off. While it's on, a box in the top left shows the address, the token and the last
request.

- It listens on `127.0.0.1` only (port 24945 by default), so nothing else on the network can reach it.
- Every request needs the token, as `Authorization: Bearer <token>`. A new token is made each time the game
  starts; **Copy Claude Code command** puts the full setup command on the clipboard.
- Requests from web pages (an `Origin` header that isn't localhost) are refused, so a browser tab can't talk to it.
- The server only runs while a battle is open; it answers between frames, so the game never waits for it.

### Connect Claude Code

```
claude mcp add --transport http normandy http://127.0.0.1:24945/mcp --header "Authorization: Bearer <token>"
```

Use the token shown in the game (or press **Copy Claude Code command**, which also removes an earlier
`normandy` entry first). After restarting the game the token changes: `claude mcp remove normandy` and add it
again, or switch on **Keep the agent token** in Settings so it stays the same. Then ask, for example: *"Look at my battle and tell me what my
sniper should do"* or *"Propose a safe move for each of my soldiers, one at a time."*

### Connect Claude Desktop

Claude Desktop starts local servers as programs, so use the `mcp-remote` bridge (needs Node.js). In
`claude_desktop_config.json` (Settings > Developer > Edit Config):

```json
{
  "mcpServers": {
    "normandy": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "http://127.0.0.1:24945/mcp", "--header", "Authorization:${AUTH_HEADER}"],
      "env": { "AUTH_HEADER": "Bearer <token>" }
    }
  }
}
```

Restart Claude Desktop after changing the token.

### Let an agent play a whole battle

In the main menu's skirmish section, under the map and deployment choices:

- **Agent vs AI**: the agent plays the first side (the Allies, the US Army or the Coalition, by theatre) against the game's AI. You watch, from the agent's side of the fog.
- **Me vs agent**: you play the first side, the agent plays the second (Germany, the Viet Cong or the insurgents). The screen keeps your side's fog of war.

In Vietnam and Afghanistan & Iraq the agent also has `tunnel`, `trap` and `detonate` commands and `napalm`
rounds (see the command help in `instructions`).

The agent link starts by itself in these battles (the address and token are in the box in the top left), and the
agent needs no "Agent may play my moves" permission: choosing the mode is the permission. You can't give orders on
the agent's turns. Connect the agent as below, then ask it something like *"Play this battle to the end. Loop:
wait_for_turn, look at the state, make your moves with execute_command, end your turn."* The server's instructions
tell it the same.

- `wait_for_turn` holds its answer until it's the agent's turn (and nothing is playing out) or the battle is over,
  for up to 55 seconds; then it says whose turn it is, the round and score, what the agent's side saw happen
  meanwhile (enemy moves in sight, shots at its units, explosions, objectives changing hands), and, on its turn, the
  battle state as `get_state` gives it, so the agent needs no extra call to start thinking.
- `execute_command` holds its answer until the move has played out on screen, then says what happened: the shot's
  result, overwatch fire it drew, damage, deaths. It takes a `commands` list too (up to 20, e.g. a move and an
  overwatch for each of several soldiers), played in order in one call. The list stops early when something
  unexpected happens (one of the agent's soldiers is shot at, hurt or panics, or a new enemy comes into sight; turn
  it off with `stop_on_surprise: false`) or at the first order that isn't legal any more, and the answer says which
  orders ran and which didn't.
- `fast: true` on `execute_command` or `wait_for_turn` plays the moves out instantly instead of animating them,
  then puts the speed back.
- `{"cmd": "end_turn"}` ends the turn; it also ends by itself once none of the side's units can act.

The server's instructions spell out the rules agents tend to get wrong: an objective stays held after its soldiers
leave and keeps scoring for its holder even while contested, so it has to be taken, not just contested; a mortar
round lands at the start of the firer's next turn; grenades need a clear line; a dash leaves no action to shoot;
hunkering needs cover; a medkit can treat its carrier.

The reports respect the fog of war like everything else. The link lives as long as the battle screen: after the
battle, start the next one from the menu (the agent keeps the same token if **Keep the agent token** is on).
`tests/agent_play.gd` plays a full "Agent vs AI" battle over HTTP this way, taking the game's own suggestion each
time, and checks a list of orders with `fast` on its first turn.

### Tools

Tiles are `[x, y]` (x east, y south). Commands use the engine's format (`Battle.execute`) with tiles as `[x, y]`:
`{"cmd": "move", "unit": 3, "tile": [12, 30]}`, `{"cmd": "shoot", "unit": 3, "target": 11}`,
`{"cmd": "overwatch" | "hunker" | "reload" | "set_up" | "rally", "unit": 3}`,
`{"cmd": "grenade" | "smoke", "unit": 3, "tile": [x, y]}`, `{"cmd": "mortar", "unit": 7, "tile": [x, y], "kind": "he" | "smoke"}`,
`{"cmd": "medkit", "unit": 3, "target": 4}`, `{"cmd": "pivot", "unit": 9, "tile": [1, -1]}` (a heading), `{"cmd": "end_turn"}`.

| Tool | Arguments | Returns |
|---|---|---|
| `get_state` | `map`, `area` `[x, y, w, h]`, `full_map` (all optional) | Round, whose turn, score, objectives (holder), your units (HP, ammo, actions, mobility, suppression, status, kit, cover), enemies in sight (HP, suppression, status: what the screen shows, never ammo or kit), enemies last seen, marked mortar strikes, threats (which enemies in sight can see each of your units, their hit chance and your cover). The ASCII map (tiles, cover objects, wall and hedge edges, units) only comes with `map` (around the action), `area` or `full_map`, since it's long |
| `get_unit_options` | `unit`; optional `objective`, `covered_from`, `shoot_target`, `limit`, `all_tiles` | Allowed actions (and why others aren't), shot odds with modifiers, expected damage and kill chance per enemy in sight, and the best spots in reach: actions the move uses, cover against the enemies in sight, objective, and the shots still possible from there after a 1-action move. The filters list only tiles in an objective, in cover from an enemy, or with a shot at a target (best odds first). `all_tiles` lists every reachable tile as `[x, y, cost, actions]` |
| `preview` | `unit`, `tile` | Reachable? cost, actions the move uses (not actions left), path; cover per side; for each enemy in sight: your cover, whether they see you (flanked), their hit chance, your shot from there; the AI's danger estimate. Changes nothing |
| `suggest_move` | `unit`, `show` (both optional) | The built-in AI's command and reasons; `show` also puts it on screen |
| `propose_move` | `command`, `note` | Shows the move on the player's screen (in purple, "Agent suggests") to accept or ignore |
| `execute_command` | `command`, or `commands` (a list, up to 20); optional `stop_on_surprise` (true), `fast` | Makes the moves in order and waits until they have played out, then reports what happened (per order for a list, with `stopped` and `not_done` when it stopped early). Only when the agent plays this side, or the player ticked **Agent may play my moves**; never online |
| `wait_for_turn` | optional `timeout_seconds` (up to 55), `include_state` (true), `fast` | Waits for your side's turn or the end of the battle; whose turn, round, score, `game_over`/`winner`, what your side saw meanwhile, and the state (no map) once it's your turn |

Nothing an agent can call rolls dice or reveals what the player can't see: previews only consider enemies in sight,
and a command against an enemy out of sight gets the same "Unknown target" answer whether he exists or not.

### Online games

- `execute_command` never works online: an agent can't play for you against a person. The agent modes are
  local skirmishes only.
- Suggestions (the H button and every agent tool) are **off in online games** unless the `help_online` setting is on
  (`user://advisor.cfg`, `[advisor] help_online=true`; it belongs on the settings page). The opponent is never told
  either way: nothing about suggestions goes over the network, only the orders you give.

### Settings

`user://advisor.cfg`, section `[advisor]`: `mcp_enabled` (false), `mcp_port` (24945), `agent_may_act` (false),
`help_online` (false). The token is not stored.

## Try it with curl

```
T=<token>; U=http://127.0.0.1:24945/mcp
curl -s $U -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"curl","version":"1"}}}'
curl -s $U -H "Authorization: Bearer $T" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
curl -s $U -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"suggest_move","arguments":{"show":true}}}'
```

## Code

- `scripts/advisor/advisor_ai.gd`: `AdvisorAI`, suggestions with reasons.
- `scripts/advisor/advisor_view.gd`: the H key, highlight and card, and the agent link's switch and status box. A child
  of the battle view, added in its `_ready`.
- `scripts/advisor/advisor_settings.gd`: the settings and session token.
- `scripts/mcp/mcp_server.gd`: `McpServer`, Streamable HTTP (JSON replies, no event stream) over `TCPServer`, polled
  every frame. A tool that has to wait returns `{"wait": Callable}`; the connection stays open and the callable is
  asked each poll until it has the answer (waiting tools can't be batched).
- `scripts/mcp/game_tools.gd`: `McpGameTools`, the tools and the fog-respecting state.
- `tests/advisor_tests.gd`: `Godot --headless --path . -s tests/advisor_tests.gd`. A fake host there stands in for the
  battle screen, so lists of orders and their early stops are tested without one.
