# Architecture Proposal — `space` plugin

**Status: PROPOSAL, for review.** This is step 2 of the build plan: agree on
this before any combat code is written. Everything here was checked against
AresMUSH core source for feasibility; nothing requires a core change.

---

## 1. Plugin layout

One plugin. Folder name `space`, module `AresMUSH::Space` (core resolves the
module by upcased folder name, so these must match).

```
plugins/space/
  space.rb                  # module def, get_cmd_handler, get_web_request_handler,
                            # get_event_handler, self.init_plugin
  plugin.yml
  map/                      # sector + terrain models, movement, ASCII rendering
  ships/                    # ship model, ship-class/weapon config readers, stations
  combat/                   # orders, round resolution, damage
  helpers/
  templates/                # ERB templates for consoles and round reports
  locales/locale_en.yml
  help/en/*.md
game/config/
  space.yml                 # general settings, skill mappings, tuning numbers
  space_ships.yml           # ship class definitions
  space_weapons.yml         # weapon definitions
```

Map/ships/combat stay separate *folders*, not separate plugins: Ares has no
plugin dependency mechanism, and core's fs3combat sets the precedent of one
plugin with many helper modules. The config split mirrors
`fs3combat_weapons.yml` / `fs3combat_vehicles.yml` conventions.

## 2. Data model

Class/weapon *definitions* live in YAML config (like fs3combat gear).
*Instances and live state* live in Ohm/Redis models.

### YAML: ship classes (`space_ships.yml`)

```yaml
space:
  ship_classes:
    Talon:                      # fighter
      silhouette: 3
      hull: 4
      shields: 6                # single shield pool for small craft
      speed: 4                  # squares/round at full burn
      agility: 2                # facing changes allowed per move + evade bonus
      stations: [ pilot ]       # one person does everything
      hardpoints:
        - { arc: forward, weapon: Light Cannon }
        - { arc: forward, weapon: Seeker }
    Covenant:                   # capital
      silhouette: 8
      speed: 1
      agility: 0
      sections:                 # capitals have sections; fighters don't
        fore:      { hull: 10, shields: 8, systems: [ sensors, weapons ] }
        aft:       { hull: 10, shields: 8, systems: [ engines, weapons ] }
        port:      { hull: 8,  shields: 6, systems: [ flight_deck ] }
        starboard: { hull: 8,  shields: 6, systems: [ weapons ] }
      stations: [ helm, gunnery, engineering, sensors, flight_ops ]
      hardpoints:
        - { arc: forward,   weapon: Heavy Battery,   scale: capital }
        - { arc: port,      weapon: Point Defense,   scale: fighter }
        # ...
```

### YAML: weapons (`space_weapons.yml`)

```yaml
space:
  weapons:
    Light Cannon: { scale: fighter, damage: 3, range: 3, arcs_locked: true }
    Heavy Battery: { scale: capital, damage: 8, range: 8, slow: true }
    Point Defense: { scale: fighter, damage: 2, range: 2 }
```

`scale` drives the silhouette interaction (see §3).

### Ohm models (persistent state)

- **`SpaceSector`** — name, width, height, status. The contested system is
  one or more persistent sectors (Debris Field, Concord Graveyard, etc.).
- **`SpaceTerrain`** — sector ref, type (asteroid_field, debris, wreck,
  resource_zone), x, y, radius, effects hash (sensor penalty, targeting
  penalty, collision risk). Config-typed like universalmap objects but with
  combat-relevant effects.
- **`SpaceShip`** — the workhorse:
  - identity: name, class key (into YAML), faction/IFF
  - position: sector ref, x, y, facing (0–7, eight-way), current speed
  - state: hull/shield current values (per-section hash for capitals),
    system damage hash (`engines: damaged`), status
    (active / destroyed / docked / derelict)
  - crew: stations hash mapping station → character id or NPC skill rating
    (`{ pilot: "char:123" }` or `{ pilot: "npc:3" }`)
  - orders: pending orders hash for the current round (cleared on resolve)
  - carrier ref: fighters docked aboard the Covenant point at it
- **`SpaceCombat`** — sector ref, round number, participant ship ids,
  state (setup / active / paused / resolved), round log. Exists so a sector
  can have contacts drifting around outside of combat, and combat is an
  explicit engagement with turn structure.

No `character_id`-on-token indirection like universalmap: characters map to
*stations on ships*, which is the actual fiction.

## 3. Size class ("silhouette") mechanics

One number per class, roughly log-scale (3 fighter, 4 shuttle, 5 gunboat,
6 frigate, 7 cruiser, 8 Covenant). Two effects, both tunable in `space.yml`:

1. **To-hit modifier**: gunnery roll modifier = `(target_sil − attacker_sil)`
   clamped to ±3. Shooting something much smaller than you is hard;
   something much bigger is easy. This single rule lets fighters and
   capitals share one fight without capital ships being modeled as five
   fighters welded together.
2. **Damage scale gating**: `fighter`-scale weapons do full damage to
   silhouette ≤5, and against larger hulls can only damage *systems/
   sections* (strafing runs matter, but a Talon never core-breaches the
   Covenant with cannons). `capital`-scale weapons against silhouette ≤4
   suffer a steep to-hit penalty (slow tracking) but are devastating on the
   rare hit. Numbers live in config, not code.

## 4. Facing, arcs, sections

- Square grid, eight facings (N, NE, E, …). `agility` limits facing changes
  per move order.
- Four 90° arcs relative to facing: forward / aft / port / starboard.
  Hardpoints are arc-locked (config). A target's bearing determines which
  arc fires and, for capitals, which *section's* shields/hull take the hit.
- Capital sections carry systems (engines, sensors, weapons, flight_deck).
  Section hull reaching 0 knocks out its systems; ship death is a
  hull-integrity threshold, not "all sections dead" — crippled ships stay
  in the fiction as objectives/wrecks.

## 5. Stations and FS3 integration (exact call points)

`space.yml` maps stations to FS3 abilities, per-game configurable:

```yaml
space:
  station_skills:
    pilot:       Piloting
    helm:        Piloting
    gunnery:     Gunnery
    engineering: Engineering
    sensors:     Sensors     # or whatever the game's skill list has
```

Every human action is one FS3 roll, made at resolution time:

| Action | Roll | Opposed by / vs |
|---|---|---|
| Hard maneuver, evasive flying | `FS3Skills.one_shot_roll(pilot, Piloting + agility mod + terrain mod)` | fixed difficulty; successes bank as evade margin for the round |
| Firing a weapon | `FS3Skills.one_shot_roll(gunner, Gunnery + silhouette mod + range mod + arc/terrain mods)` | target's banked evade margin |
| Damage control | `FS3Skills.one_shot_roll(engineer, Engineering)` | fixed difficulty per system severity |
| Power routing / boost | Engineering roll; margin buys temporary shield/speed points | fixed |
| Sensor sweep (contacts, ID, target lock) | Sensors roll | fixed + terrain penalty |

NPC-crewed stations use the stored NPC rating with
`FS3Skills.one_shot_die_roll(dice)` — the same split fs3combat uses for its
NPCs. Success/margin comparison helpers are ours; the *dice* are always FS3.
We never touch fs3combat's combat loop — only fs3skills' public API.

## 6. Round resolution (POC — turn-based, request-response)

1. **Orders phase.** Each crewed station issues its order from wherever the
   player is standing: `space/helm heading=NE speed=2`,
   `space/fire <target>=<hardpoint>`, `space/eng repair=engines`. Orders
   store on the ship. NPC ships get GM orders or a trivial default doctrine.
2. **Resolve.** GM (or auto once all participant ships have orders) runs
   `space/resolve`:
   a. **Movement** — all ships simultaneously: apply helm orders bounded by
      speed/agility; piloting rolls happen here for contested/hard
      maneuvers; collisions with terrain checked.
   b. **Attacks** — declared fires resolve in silhouette order (small and
      nimble shoot first): arc check from *new* positions, gunnery roll vs
      evade margin, damage through the struck arc's shields → section hull
      → system crits.
   c. **Engineering** — repairs and reroutes apply.
   d. **Report** — round log written to `SpaceCombat`, formatted round
      summary emitted to every online crew member, tactical display
      re-rendered on demand.
3. Repeat. No scheduler, no background task; the sim only advances when
   `space/resolve` runs. This is the whole POC loop.

## 7. The console (space is not a room)

- `space/tac` — ASCII sensor display of your ship's sector: grid, contacts
  with bearing/range/IFF, terrain, your facing and speed. Rendered from any
  room; it *is* the instruments.
- `space/status` — your ship: sections, shields, systems, crew stations,
  pending orders.
- `space/contacts` — sensor list view (what sensors have actually resolved;
  terrain and sensor rolls gate detail).
- Sensor visibility is **per-ship** (what your ship has detected), not
  universalmap-style global GM reveal.

GM/admin: `space/newsector`, `space/spawn <class>=<name>`, `space/crew`,
`space/start`, `space/resolve`, `space/damage`, `space/remove`.

## 8. Web portal (post-POC)

Native Ember, no React/webpack:

- Route added via the portal's sanctioned `app/custom-routes.js` hook +
  route/template/component files shipped in `webportal/` with install
  instructions (additive files survive portal upgrades).
- Data via `gameApi.requestOne('space_tac', …)` → engine `POST /request` →
  our `get_web_request_handler`.
- Live updates via `Global.client_monitor.notify_web_clients(:space_activity,
  data, true)` over the existing portal websocket — the exact pattern
  fs3combat uses for `combat_activity` / `new_combat_turn`.

## 9. Phase two — pseudo-real-time (deferred; feasibility notes)

Verified against core: `CronEvent` ticks at 1-minute granularity (too coarse
for a sim tick); `Global.dispatcher.queue_timer(seconds, …)` is a sanctioned
EventMachine one-shot timer widely used by core plugins, and a self-re-arming
timer chain gives N-second ticks with zero core changes. Caveats: timers die
on restart (re-arm from `init_plugin`), everything runs on the single reactor
thread (ticks must be cheap), errors must rescue-and-re-arm. Decision point
comes after the POC proves the resolution engine; the tick would then just
call the same resolve step on a clock instead of on command.

## 10. Decisions taken (were open questions)

All five resolved; the POC is built on these.

1. **Geometry: both, per sector.** `square` (8 facings, Chebyshev
   distance) and `hex` (6 facings, axial coordinates) are implemented
   behind one `Geometry` interface and chosen when the sector is created,
   defaulting from `space.yml`.

   One correction to the original framing: geometry cannot be a
   *rendering* toggle — square in telnet, hex on the web. Distance,
   facing, turn cost and firing arcs are all computed from it, so the two
   would be different games on the same data. It is a property of the
   sector; both renderers draw whatever that sector actually uses. A game
   can run hex sectors and square sectors side by side.

2. **Evasion: banked.** The pilot rolls Piloting once per round and banks
   the successes as defense against every incoming shot. `evade_model` in
   `space.yml` dispatches this, with `per_attack` reserved for later.

3. **Resolution: GM-triggered, but not hard-wired.** `space/resolve` is a
   thin command over `Resolver.resolve_round(combat)`. Auto-resolve is
   already scaffolded (`auto_resolve` in config,
   `Engagements.ready_to_resolve?`), and a scheduled tick would call the
   same function — so moving off GM-only is a small change, not a rewrite.

4. **Stations map to FS3 abilities in YAML.** `station_skills` maps each
   station to an ability. Anything FS3 doesn't define falls back to a
   configurable flat pool (`untrained_dice`, default 2) rather than
   letting FS3 quietly treat an unknown ability as a 1-die background
   roll. `check_config` reports such mismatches at startup.

5. **Fighter shields: a single pool.** Small craft carry one section
   named `hull` — one bubble over the whole ship. Capitals carry one
   section per arc. Both run through identical code paths, so there is no
   special-casing for small craft anywhere in the resolver.

## 11. What the POC actually implements

Built and covered by 92 passing specs (`rspec` at the repo root):

- Sectors, ships, terrain and engagements as Ohm models.
- Square and hex geometry, facing, turn cost limited by agility, arcs.
- Silhouette to-hit and damage-scale gating.
- Sections, shields, hull, system knockouts, destruction.
- Per-ship sensor contacts with identification falloff and terrain
  concealment.
- Order commands, the round resolver, and an ASCII tactical console.
- Web request handlers ready for the Ember page.

`tools/demo.rb` runs a scripted engagement and prints the console and
round report with no game server, for tuning by eye.

## 12. Still to do

- The Ember tactical page (§8) — handlers exist, the portal files don't.
- Carrier operations: launching and recovering fighters from the
  Covenant's flight deck (`carrier` reference exists on the model).
- Pseudo-real-time tick (§9), after the POC has been played.
