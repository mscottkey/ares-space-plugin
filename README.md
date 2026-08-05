# ares-space-plugin

Space and space-combat system for [AresMUSH](https://aresmush.com), built for
the UCC Covenant game but written as a general-purpose plugin.

**Status: tactical-tabletop POC, untested on a live game.** The rules
engine, commands, console and config are written and covered by 92
passing specs, but nothing has run against a real AresMUSH server yet.
See [docs/architecture.md](docs/architecture.md) for the design and
[docs/install.md](docs/install.md) to try it.

## What it is

A single Ares plugin providing:

- **Persistent tactical sectors** — space is not a room. The tactical
  situation is stateful data (Redis/Ohm) that crews query from normal RP
  rooms (bridge, cockpit) via a sensor-console command, the way crews
  actually read space: off instruments.
- **Ships as first-class entities** — size class (silhouette), facing,
  firing arcs, sections, hardpoints, and crew stations. Capital ships are
  modeled as capital ships, not as stacks of oversized fighters.
- **Turn-based combat resolution** — players issue orders, the round
  resolves, an ASCII tactical display renders. Fully request-response; no
  game loop.
- **FS3 integration** — every human action (piloting, gunnery,
  engineering, damage control) resolves through core FS3 skill rolls via
  the public `FS3Skills` API. This plugin extends FS3 into space; it does
  not replace it.

## Hard constraints

- Plugins only. No AresMUSH core changes, ever.
- Follows official [Ares plugin conventions](https://aresmush.com/tutorials/code/).
- Uses core FS3 for all skill resolution.

## Try it

```
cp -r plugin /path/to/aresmush/game/plugins/space   # folder must be "space"
cp game/config/space*.yml /path/to/aresmush/game/config/
```

Restart, then `manage/checkconfig` to catch station skills your game's
FS3 doesn't define. Full steps and a smoke test in
[docs/install.md](docs/install.md).

To see it work without a server:

```
rspec              # 92 specs, no Redis or game required
ruby tools/demo.rb # prints a scripted engagement's console and report
```

## Layout

```
plugin/
  space.rb            module, command dispatch, init_plugin, check_config
  public/             Ohm models, plugin.yml
  helpers/
    geometry.rb       square (8-facing) and hex (6-facing) math
    rules.rb          silhouette, scale, range, damage - pure functions
    ship_behavior.rb  derived ship state, shared by model and specs
    resolver.rb       the round: sweeps, evasion, movement, fire, repairs
    crew.rb           the FS3 seam - every skill roll goes through here
    sensors.rb        per-ship contact detection
    orders.rb         order storage and validation
    display.rb        ASCII tactical console and round report
  commands/           22 player and GM commands
  templates/          ERB for the console and ship status
  web/                request handlers for the (future) Ember page
  specs/              92 specs + in-memory harness
game/config/          space.yml, space_ships.yml, space_weapons.yml
tools/demo.rb         scripted engagement, no server needed
```

## Lineage

Structural conventions follow
[ares-universalmap-plugin](https://github.com/mscottkey/ares-universalmap-plugin);
the assessment that led to this being a separate plugin lives in that
repo's `docs/foundation-assessment.md`.

## License

MIT.
