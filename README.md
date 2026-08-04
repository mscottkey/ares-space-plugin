# ares-space-plugin

Space and space-combat system for [AresMUSH](https://aresmush.com), built for
the UCC Covenant game but written as a general-purpose plugin.

**Status: design phase.** See [docs/architecture.md](docs/architecture.md) for
the current architecture proposal. No runtime code yet.

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

## Lineage

Structural conventions follow
[ares-universalmap-plugin](https://github.com/mscottkey/ares-universalmap-plugin);
the assessment that led to this being a separate plugin lives in that
repo's `docs/foundation-assessment.md`.

## License

MIT.
