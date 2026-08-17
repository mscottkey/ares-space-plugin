# ares-space-plugin

Space and space-combat system for [AresMUSH](https://aresmush.com), built for
the Lost Colony game but written as a general-purpose plugin.

## Install

```
plugin/install https://github.com/mscottkey/ares-space-plugin
```

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
- **Pluggable dice** — every human action (piloting, gunnery,
  engineering, damage control) resolves through one adapter. Core FS3
  ships as the zero-config default via the public `FS3Skills` API; a game
  on another system writes one small file in `plugin/dice/` and names it
  in config. This plugin extends your dice system into space; it does not
  replace it.


`plugin/install` loads it automatically. Then `config/check` to catch
station skills your game's dice system doesn't define. Full steps, the
manual (SFTP) install path, and a smoke test are in
[docs/install.md](docs/install.md); to spin up a throwaway Ares instance
to test against, see [docs/dev-server.md](docs/dev-server.md).

To see it work without a server:

```
rspec              # 304 specs, no Redis or game required
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
    crew.rb           who is at which station, and under what name
    sensors.rb        per-ship contact detection
    orders.rb         order storage and validation
    display.rb        ASCII tactical console and round report
    web_data.rb       JSON payloads for the portal, sensor-filtered
  dice/               the dice seam - one adapter per system
    dice.rb           adapter selection and the roll contract
    fs3_adapter.rb    core FS3 (the default)
  commands/           22 player and GM commands
  templates/          ERB for the console and ship status
  web/                request handlers (tactical, sectors, ship, order, resolve)
  specs/              304 specs + in-memory harness
game/                 copied into your game/ by plugin/install
  config/             space.yml, space_ships.yml, space_weapons.yml,
                      space_systems.yml
  styles/             _space.scss - GAME styles, not portal styles; Ares
                      compiles these and the portal links the result last
webportal/            mirrors ares-webportal's app/ layout, so
                      plugin/install can copy it straight across
  routes/             space-system, space-sectors, space-tactical
  controllers/        space-system, space-tactical
  templates/          the three pages
  components/         space-plot (tactical SVG, square + hex) and
                      space-system-map (orbital SVG), colocated js + hbs
custom_files/         custom-routes.js (portal's shared route hook -
                      outside webportal/ so the installer never
                      auto-copies it; always merge by hand)
tools/                demo.rb, and finish-portal-install.sh for the two
                      shared hook files the installer can't touch
```

## License

MIT.
