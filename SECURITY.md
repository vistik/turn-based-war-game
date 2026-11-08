# Security policy

## Supported versions

Only the latest release gets security fixes. Please check that a problem still happens there (or on `main`)
before reporting it.

## Reporting a vulnerability

Please **don't open a public issue**. Report it privately through GitHub instead: the repository's
**Security** tab > **Report a vulnerability**. Say what's affected, how to reproduce it and what an attacker
could do with it. I'll answer there, and credit you in the fix unless you'd rather not.

## What's in scope

The game is single-player and offline except for two network features:

- **Online play** (`scripts/net/`): a direct peer-to-peer connection between two copies of the game, with no
  server in between. One player hosts on a UDP port (24944 by default) and the other joins by address. Both
  prove they know the shared password with HMACs over fresh nonces before the host accepts anything else,
  and repeated wrong guesses are locked out. For play over the internet the game can ask the router to open
  the port (UPnP), asks public STUN servers for its outside address, and can "let in" a joiner by sending
  packets towards them (NAT hole punching). Issues here include getting past the password, crashing or
  taking over the other player's game with crafted packets, or a port being left open after the game closes. Online
  traffic is gated by the password but not encrypted; that's a known limitation, not a vulnerability.
- **Agent link** (`scripts/mcp/`, [docs/MCP.md](docs/MCP.md)): an opt-in Model Context Protocol server, off by
  default, that listens on `127.0.0.1` only (port 24945 by default) and needs a bearer token. Requests from
  web pages (a non-localhost `Origin` or `Host`) are refused. Issues here include reaching it from another
  machine or a browser tab, using it without the token, or doing more through it than its tools allow.

Desyncs between two honest players, cheating that only changes your own game, and bugs that need someone who
already controls your computer are ordinary bugs: please open a normal issue for those.
