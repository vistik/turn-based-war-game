# Contributing

Thanks for helping. Bug reports, ideas and pull requests are all welcome; for anything big, open an issue
first so we can agree on the approach.

## Setup

You need [Godot 4.7](https://godotengine.org/download). `Godot` below means its binary, e.g.
`/Applications/Godot.app/Contents/MacOS/Godot`.

```sh
Godot --path .            # play from the project
Godot --path . --editor   # open in the editor
```

## Tests

Run the headless suites before sending a pull request. `tests/run_tests.gd` is the main one; CI runs all five.

```sh
Godot --headless --path . --import                  # once after cloning, so the class caches exist
Godot --headless --path . -s tests/run_tests.gd     # engine, AI, saves, replays, scenarios, settings
Godot --headless --path . -s tests/advisor_tests.gd # move suggestions and the MCP tools
Godot --headless --path . -s tests/terrain_tests.gd
Godot --headless --path . -s tests/theatre_tests.gd
Godot --headless --path . -s tests/height_tests.gd
```

Each prints `FAIL: ...` for a failed check and exits non-zero. If you touch online play, also run
`GODOT=Godot sh tests/net_resume.sh 26000 44` and `GODOT=Godot sh tests/net_auth.sh 26100`. The README's
"Testing and balancing" section has the rest, including the AI-vs-AI balance tools.

## Keep the engine deterministic

Online play sends only commands and compares state checksums after each one, and replays and saves re-run
the same commands, so the rules engine must give exactly the same result on every machine (see
[docs/DESIGN.md](docs/DESIGN.md)). In battle logic:

- use the battle's own seeded random numbers, never `randi()`, `randf()` or anything time-based;
- don't depend on dictionary or node order you didn't set, frame timing, or anything only the view knows;
- keep the view (animation, sound, camera) out of the engine's decisions.

## Style

- Follow the surrounding code: typed GDScript, tabs, `##` doc comments for classes and public functions.
- Add or update tests for rule changes.
- Update `README.md` whenever you add or remove a feature.
- Keep pull requests focused, with a short description of what changed and why.

## License

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
