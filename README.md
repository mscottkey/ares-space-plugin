# ares-space-plugin

Space and space-combat system for [AresMUSH](https://aresmush.com), built for
the UCC Covenant game but written as a general-purpose plugin.

**Status: tactical-tabletop POC plus a web portal page. Verified on a
real AresMUSH server; the Ember page is not yet built.** 125 specs pass,
and every command and web handler has been exercised against a live
instance with Redis (see [docs/dev-server.md](docs/dev-server.md)). The
portal files are syntax-checked but no `ember build` has run against
them.
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
- **A web portal page** — the same sector drawn as SVG (square or hex),
  with clickable targeting and order buttons, updating live over the
  portal's websocket when a round resolves. Plain Ember, no bundle step.
  Orders from the browser run through the same validation as the
  in-game commands.
- **FS3 integration** — every human action (piloting, gunnery,
  engineering, damage control) resolves through core FS3 skill rolls via
  the public `FS3Skills` API. This plugin extends FS3 into space; it does
  not replace it.


Restart, then `manage/checkconfig` to catch station skills your game's
FS3 doesn't define. Full steps and a smoke test in
[docs/install.md](docs/install.md); to spin up a throwaway Ares instance
to test against, see [docs/dev-server.md](docs/dev-server.md).

To see it work without a server:

```
rspec              # 125 specs, no Redis or game required
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
    web_data.rb       JSON payloads for the portal, sensor-filtered
  commands/           22 player and GM commands
  templates/          ERB for the console and ship status
  web/                request handlers (tactical, sectors, ship, order, resolve)
  specs/              125 specs + in-memory harness
game/config/          space.yml, space_ships.yml, space_weapons.yml
webportal/
  app/routes/         space-sectors, space-tactical
  app/controllers/    space-tactical
  app/templates/      the two pages
  app/components/     space-plot (SVG, square + hex), colocated js + hbs
  app/styles/         _space.scss
  custom_files/       custom-routes.js (portal's route hook)
tools/demo.rb         scripted engagement, no server needed
```

## License

MIT.
