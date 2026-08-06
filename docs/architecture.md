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

`space.yml` maps stations to FS3 abilities, per-game configurable.
(Illustrative names below; the ability names actually shipped as
defaults are §12's Technician/Alertness/Composure, chosen because they
exist in stock FS3 — "Engineering" and "Sensors" don't.)

```yaml
space:
  station_skills:
    pilot:       Piloting
    helm:        Piloting
    gunnery:     Gunnery
    engineering: Engineering  # whatever the game's skill list has
    sensors:     Sensors
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

## 8. Web portal

Built. Native Ember, no React and no separate bundle step.

- **Routes** registered through the portal's sanctioned
  `app/custom-routes.js` hook: `/space` (sector list) and `/space/:id`
  (tactical plot). Every other file is new, so a portal upgrade doesn't
  collide with them.
- **Data** via `gameApi.requestOne('spaceTactical', { id })` and friends,
  which POST to the engine's `/request` endpoint and land in
  `get_web_request_handler`. Handlers return `{ error: ... }` on failure -
  the portal checks `response.error`; a `c_error` key (which the
  universalmap plugin used) is silently ignored by the portal and was a
  real bug inherited from it.
- **Rendering** is one SVG component, `space-plot`, that draws square and
  hex sectors from the same payload. Its geometry math deliberately
  mirrors `helpers/geometry.rb` one-for-one - same axial projection, same
  direction tables - so the browser and the ASCII console agree about
  where things are.
- **Orders** from the browser call `Orders.issue`, the same entry point
  the in-game commands use. Neither surface can drift into validating
  differently, and both produce the same warnings ("that turn exceeds
  your agility", "that hardpoint doesn't bear yet").
- **Live updates** via `Global.client_monitor.notify_web_clients` over
  the websocket the portal already keeps open - the pattern fs3combat
  uses for `combat_activity`. Payloads are prefixed with the sector id so
  a page ignores traffic for sectors it isn't watching. No polling.
- **Sensor discipline holds in the browser.** The tactical payload is
  built per viewer: unidentified contacts carry position and nothing
  else, so a player cannot read a name or hull state out of the network
  tab that their crew hasn't resolved. Staff with no ship in the sector
  get the god view explicitly.

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

Built and covered by 121 passing specs (`rspec` at the repo root):

- Sectors, ships, terrain and engagements as Ohm models.
- Square and hex geometry, facing, turn cost limited by agility, arcs.
- Silhouette to-hit and damage-scale gating.
- Sections, shields, hull, system knockouts, destruction.
- Per-ship sensor contacts with identification falloff and terrain
  concealment.
- Order commands, the round resolver, and an ASCII tactical console.
- Web request handlers and an Ember portal page (§8).

`tools/demo.rb` runs a scripted engagement and prints the console and
round report with no game server, for tuning by eye.

## 12. Found by running it on a real game

The plugin was installed on a live AresMUSH instance (Redis, real Ohm
models, real command dispatch). Five things broke that no amount of
spec-writing against doubles had caught:

1. **Ships stacked, and stacking deadlocked combat.** A pilot closing to
   contact flew onto the target's square. Co-located there is no bearing
   between two ships, so no hardpoint could bear and the fight simply
   stopped - reachable in one move by anyone who charges. Movement now
   walks cell by cell and stops short of an occupied one; a co-located
   pair (which a GM can still create by hand) is treated as bearing on
   everything rather than deadlocking.
2. **`Ohm::IndexNotFound` on deleting a sector.** Ohm derives a
   collection's foreign key from the declaring class, so
   `collection :ships, "AresMUSH::SpaceShip"` looked for
   `space_sector_id` while the reference wrote `sector_id`. The third
   argument (`:sector`) is load-bearing. This is the same indexing trap
   the universalmap plugin fought with.
3. **Default station skills didn't exist.** Stock FS3 has no
   Engineering, Sensors or Leadership - it has Technician, Alertness and
   Composure. The `check_config` hook reported all three at boot, which
   is exactly what it was written for, but the shipped defaults should
   work on a stock game and now do.
4. **Pending orders displayed a raw facing index** - "come to heading 4"
   instead of "come to heading S", because the stored order keeps the
   integer and the renderer wasn't given the geometry to name it.
5. **A failed sensor sweep reported "sensors out to 0"**, which reads as
   though the array had failed, when passive range was intact. It now
   reports effective detection range.

Ship classes also gained a default `faction`, so a spawned hull reads as
UCC or Swarm on the plot instead of "Unknown" sitting confusingly next
to genuinely unidentified contacts.

### 12a. The system map, found the same way

The first build of the orbital map reached the browser as a black disc
with every world stacked on a horizontal line. One mistake caused all of
it: **the map's placement depended on its stylesheet.**

Each body was drawn at its resting position on the +x axis, and the only
thing that swung it round to its configured angle was a CSS
`animation-delay`. So with `_space.scss` not compiled into the page,
nothing had an angle - and unstyled SVG `<circle>` fills solid black,
which is what the outermost orbit ring became.

The fix is a separation that should have been there from the start:

- **Placement is a static SVG `transform` attribute.** It needs no
  stylesheet, no animation support, and survives the pause button.
- **Motion is CSS**, on a group *enclosing* the placement (CSS
  `transform` beats the `transform` attribute on the same element, so
  they have to be different elements), with a counter-rotating group
  inside to keep labels level.
- **Every visual rule is mirrored as a presentation attribute** in the
  template. CSS wins wherever both apply, so the stylesheet still
  governs; the attributes only decide what an unstyled build looks like,
  and they turn "unreadable" into "plain".

Two smaller things fell out of finally looking at it rendered:

- `.space-body-faction` carried `r: 1`. In SVG2 `r` is a CSS property,
  and CSS beats the presentation attribute - so every faction halo was
  collapsing to a one-unit dot. Deleted.
- Sizes were being drawn literally. A body's `size` in the config is
  *relative* (how big this world is next to its neighbours), but the
  canvas of a twelve-ring system is ~1400 units across, so a `size: 6`
  world rendered about three pixels wide. `body_scale` and `label_size`
  in `orbit_layout` convert relative figures into legible ones, and the
  canvas margin now derives from `label_size` so a long name on the
  outermost orbit isn't clipped by the viewBox.

None of this needed a game server. It needed the SVG rendered in a real
browser: the payload from `WebData.system_map` fed through the markup the
template emits, loaded in headless Chromium both with and without the
stylesheet, then measured - distinct positions, distance from the star
holding constant under animation, label rotation staying at zero. Those
three measurements would have failed loudly on the original build.

### 12b. A moon isn't a second planet

Reported from a real screenshot: P3's moon, Sentinel, rendered on the far
side of the map from P3 - "a moon can't be further away than other
planets."

The cause was that a moon's position was computed exactly like a
planet's: its own ring, its own independently configured `angle`, both
measured from the star. `Sentinel` (angle 210) next to `P3` (angle 62)
put the two at a shared radius but opposite bearings - nowhere near each
other, and past several outer-ring planets by coincidence of the numbers
involved. "Rides its parent's orbit" was a comment above code that didn't
do that.

Fixed on both sides of the wire, because the front end doesn't read the
server's `x`/`y` for body placement (see 12a) - it recomputes position
itself from `orbit_radius` and `angle`, so a Ruby-only fix would have
left the actual map unchanged:

- **`WebData.body_map_entry`** now computes a moon's position from its
  *parent's* true position plus a (`moon_orbit`, `angle`) offset, where
  `angle` is relative to the parent. `orbit_radius` for a moon becomes
  that offset distance, not a radius from the star. This is what the
  detail panel and ship-transit lines read.
- **`space-system-map.js`/`.hbs`** nest a moon's SVG group *inside* its
  parent's rotating group, rather than drawing it as a sibling with a
  star-relative angle of its own. This is load-bearing, not cosmetic:
  rotations compose by adding angles regardless of pivot, so a moon that
  bypasses its parent's own counter-rotation group has to undo *both*
  the parent's static angle and its own in a single combined
  counter-transform, or the label picks up the parent's tilt. A lone
  body only ever has one angle to undo.

Verified the same way as 12a - rendering, not reading. The nested markup
was fed through Chromium with the animation running (5s period rather
than the real ~4-6 minutes, to observe multiple phases quickly): a moon's
on-screen distance from its parent measured 10.3px at three points across
the rotation, never drifting, with label tilt at 0.00° throughout. 159
specs pass (4 new), including one that pins the exact regression - a
moon's own angle no longer decides where it lands relative to the star.

### 12c. Working and invisible are not the same thing

Reported as "the orbits never animate." They did: `animation-play-state`
read `running`, `prefers-reduced-motion` was `false`, and a click did
visibly reset the whole map - but between clicks, nothing looked like it
was moving. It wasn't broken; it was 240 seconds per revolution for the
fastest (ring 1) body, and slower for every ring after that. Watching for
a normal few seconds shows a body drift a couple of degrees - real, but
below the threshold of noticing unless you already know to look for it,
which makes "is this even working" impossible to answer just by looking.

Two separate things came out of chasing this:

- The click-reset was real and worth fixing regardless of the pacing
  question: `bodies` is a `computed()` keyed to `selectedKey`, returning
  a fresh array of fresh objects on every click. `{{#each}}` with no
  explicit `key` matches by object identity, so every click read as "an
  entirely different list" and tore down and rebuilt every `<g>` in the
  SVG tree - restarting every element's animation clock at once, planets
  and moons alike. `key="key"` on both the body and moon loops fixes it:
  a click now only touches the `is-selected` class on the one body
  clicked, and every other element's running animation is undisturbed.
- The pace itself needed to be a dial, not a constant. `orbit_period` in
  `orbit_layout` (default 24s per ring-1 revolution, scaled per ring the
  same way the ring spacing itself is) replaces the JS's hardcoded 240.
  The default is picked to be obviously alive at a glance, not to model
  real orbital ratios - a value that did the latter would put slower
  rings below the noticeable threshold regardless, which is the
  complaint this was answering in the first place.

Verified in Chromium against the real payload with no artificial
speed-up: every body's on-screen position moved 18-20px within a 2-second
window at typical render scale - the literal "can you tell inside a
couple of seconds" test the report asked. 162 specs pass (3 new).

## 13. Ships and the room grid

Space is not the room grid - a sector is instruments, not a place you walk
into (§7). But a ship's *interior* is a place, and RP happens in rooms,
so this plugin needs a seam to the grid without owning it or changing how
it works. Traced instead of assumed:

- `Room` and `Exit` (`engine/aresmush/models/room.rb`, `exit.rb`) are
  plain Ohm models any plugin can create - `Room.create(name:, area:)`
  is the exact call `plugins/rooms/web/location_create_request_handler.rb`
  itself makes. Retargeting an exit at runtime (a docking bay pointing
  wherever a ship currently is) is an ordinary reference write,
  `exit.update(dest: room)`.
- `Rooms.move_to(client, char, room, exit_name)` is the `rooms` plugin's
  public API (`plugins/rooms/public/rooms_api.rb`) - the same thing a
  plain `go` command calls. Boarding uses this rather than reimplementing
  room echoes and screen-reader handling.
- Reopening a core model from a plugin's own file is an established
  pattern, not a fork - `fs3combat`, `places`, `scenes`, `describe`, and
  `rooms` itself all reopen `Room` from their own `public/*_room.rb`.
  This plugin reopens `Character` the same way, to add one reference.

None of this touches core.

### Model

- `SpaceShip.entry_room` - the one room external exits connect to.
  Created lazily on first board, not at spawn (most ships spawned for a
  test fight are never boarded).
- `SpaceShip.operational_rooms` - every room a character can run ship
  commands from. Always includes `entry_room`; staff or the ship's
  `owner` can tag more by standing in a room they've built and running
  `space/tag`. Deliberately unlabeled - nothing here cares whether
  you're on the bridge or in engineering, only whether the room counts
  as on duty at all. A private cabin off the same interior isn't tagged,
  and doesn't count. A ship is one room mechanically for as long as a
  scene runs, whatever its deck plan says; staff can build the deck plan
  out for flavor without any of it being mechanically load-bearing until
  someone tags a specific room on purpose.
- `SpaceShip.owner` - optional. Set, that character can bump anyone off
  a station the way staff always could; unset, only staff can force a
  reassignment (self-service claiming of an *open* station is unaffected
  either way - that's slice 2).
- `Character.current_ship` - authoritative, not derived from the room
  graph. "Which ship are you on" is "which ship did you last board,"
  full stop, until you board a different one or explicitly disembark.
  Wandering off through an ordinary exit without disembarking does
  *not* clear it - orders still go to that ship, the same way forgetting
  to log out of a console doesn't log you out. `Boarding.aboard?` (a
  physical room check, independent of the stamp) is a separate,
  non-authoritative signal reserved for flagging that mismatch somewhere
  later - a "?" on a status line - never something that overrides the
  stamp.

### Commands

`space/board <ship>`, `space/disembark` (no argument - you can only be
in one room, so at most one ship, at a time), `space/tag` (also no
argument - tags the room you're standing in). Boarding is open to any
player; only staff or the owner can tag a room, checked via a
`check_can_tag` guard (`CommandHandler` auto-calls any `check_*` method).

### What's deliberately not built yet

- Exit retargeting so boarding is walking through a door instead of
  typing a ship's name - `space/board` is a placeholder for that.
- Self-service station claiming, and the `Ships.ship_for_char` fix that
  has to ship alongside it once a character can hold a seat on more than
  one ship (`.first` on a hash scan is already technically wrong today,
  just unreachable while only staff can create the ambiguity).
- Hangar bays / carrier launch-recovery, using the same retargeting
  mechanism recursively.

## 13a. Self-service crew (slice 2)

The two gaps §13 left open, since they're really one change - claiming
a seat and knowing which ship that seat's orders belong to are the same
problem once more than one ship can be involved.

- **`space/take <station>`** / **`space/leave <station>`** - self-service,
  no staff needed, but only for a station nobody's in. Both act on
  `Character.current_ship` (whichever ship you last boarded) and require
  `Boarding.aboard?` at the moment of the action - claiming a seat is
  something you do standing there, unlike issuing an order once seated,
  which trusts the stamp regardless of where you've since wandered.
  `Crew.claim`/`Crew.release` hold the logic; the commands are thin
  wrappers, same as everywhere else in this plugin.
- **`space/crew` gained an owner exception.** It was admin-only; now
  `check_can_assign` passes for admin *or* the target ship's `owner`.
  Bumping someone already seated - as opposed to claiming an open one -
  still isn't self-service for anyone else, by design.
- **`Ships.ship_for_char` now prefers the stamp.** It used to be a flat
  scan - `SpaceShip.all.select { stations include me }.first` - silently
  arbitrary the moment a character held seats on two ships, which
  self-service claiming makes an ordinary Tuesday instead of a staff
  mistake. It now prefers `char.current_ship`, but only if that ship
  still lists them in its `stations` - a character who boarded but never
  claimed anything, or whose stamped ship somehow lost their seat, falls
  back to the old scan rather than returning a ship they hold nothing on.
  A destroyed `current_ship` is ignored the same way the old scan always
  ignored inactive ships.

198 specs pass (13 new: `crew_specs.rb` and `ships_specs.rb` -
`current_ship`'s own coverage shipped with the stamp itself in §13).

## 14. Still to do

- Carrier operations: launching and recovering fighters from the
  Covenant's flight deck (`carrier` reference exists on the model) -
  see §13, now that entry_room/operational_rooms exist to build it on.
- Pseudo-real-time tick (§9), after the POC has been played.
