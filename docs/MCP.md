# Move suggestions and the agent link (MCP)

Two ways to get help during a battle. In both, **you** give the orders.

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

Use the token shown in the game (or press **Copy Claude Code command**). After restarting the game the token
changes: `claude mcp remove normandy` and add it again. Then ask, for example: *"Look at my battle and tell me what my
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

### Tools

Tiles are `[x, y]` (x east, y south). Commands use the engine's format (`Battle.execute`) with tiles as `[x, y]`:
`{"cmd": "move", "unit": 3, "tile": [12, 30]}`, `{"cmd": "shoot", "unit": 3, "target": 11}`,
`{"cmd": "overwatch" | "hunker" | "reload" | "set_up" | "rally", "unit": 3}`,
`{"cmd": "grenade" | "smoke", "unit": 3, "tile": [x, y]}`, `{"cmd": "mortar", "unit": 7, "tile": [x, y], "kind": "he" | "smoke"}`,
`{"cmd": "medkit", "unit": 3, "target": 4}`, `{"cmd": "pivot", "unit": 9, "tile": [1, -1]}` (a heading), `{"cmd": "end_turn"}`.

| Tool | Arguments | Returns |
|---|---|---|
| `get_state` | `area` `[x, y, w, h]`, `full_map` (both optional) | Round, whose turn, score, objectives (holder), your units (HP, ammo, actions, mobility, suppression, status, kit, cover), enemies in sight (HP, suppression, status: what the screen shows, never ammo or kit), enemies last seen, marked mortar strikes, and an ASCII map (tiles, cover objects, wall and hedge edges, units) around the action |
| `get_unit_options` | `unit`, `all_tiles` (optional) | Allowed actions (and why others aren't), shot odds with modifiers, expected damage and kill chance per enemy in sight, the best cover spots in reach |
| `preview` | `unit`, `tile` | Reachable? cost, actions, path; cover per side; for each enemy in sight: your cover, whether they see you (flanked), their hit chance, your shot from there; the AI's danger estimate. Changes nothing |
| `suggest_move` | `unit`, `show` (both optional) | The built-in AI's command and reasons; `show` also puts it on screen |
| `propose_move` | `command`, `note` | Shows the move on the player's screen (in purple, "Agent suggests") to accept or ignore |
| `execute_command` | `command` | Makes the move, only if the player ticked **Agent may play my moves**; never online |

Nothing an agent can call rolls dice or reveals what the player can't see: previews only consider enemies in sight,
and a command against an enemy out of sight gets the same "Unknown target" answer whether he exists or not.

### Online games

- `execute_command` never works online: an agent can't play for you against a person.
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
  every frame.
- `scripts/mcp/game_tools.gd`: `McpGameTools`, the tools and the fog-respecting state.
- `tests/advisor_tests.gd`: `Godot --headless --path . -s tests/advisor_tests.gd`.
