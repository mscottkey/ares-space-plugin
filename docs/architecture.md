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

## 5. Stations and the dice seam (exact call points)

`space.yml` maps stations to ability names, per-game configurable. The
names must be ones the configured dice system actually defines — the
shipped defaults are §12's Technician/Alertness/Composure, chosen
because they exist in stock FS3 ("Engineering" and "Sensors" don't).

```yaml
space:
  station_skills:
    pilot:       Piloting
    helm:        Piloting
    gunnery:     Gunnery
    engineering: Engineering  # whatever the game's skill list has
    sensors:     Sensors
```

Every human action is one roll, made at resolution time:

| Action | Roll | Opposed by / vs |
|---|---|---|
| Hard maneuver, evasive flying | pilot's skill + agility mod + terrain mod | fixed difficulty; successes bank as evade margin for the round |
| Firing a weapon | gunner's skill + silhouette mod + range mod + arc/terrain mods | target's banked evade margin |
| Damage control | engineer's skill | fixed difficulty per system severity |
| Power routing / boost | engineering roll; margin buys temporary shield/speed points | fixed |
| Sensor sweep (contacts, ID, target lock) | sensors roll | fixed + terrain penalty |

NPC-crewed stations roll the stored NPC rating as a flat pool instead of
a character's skill — the same split fs3combat uses for its own NPCs.

The success/margin comparison helpers are ours; the dice belong to
whichever system `dice_system` names, and FS3 is the shipped default.
See §14 for that seam. We never touch fs3combat's combat loop.

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

4. **Stations map to abilities in YAML.** `station_skills` maps each
   station to an ability. Anything the dice system doesn't define falls
   back to a configurable flat pool (`untrained_dice`, default 2) rather
   than letting the system quietly treat an unknown ability as a token
   roll (FS3 gives it 1 background die). `check_config` reports such
   mismatches at startup. Which system does the rolling is itself
   configurable — see §14.

5. **Fighter shields: a single pool.** Small craft carry one section
   named `hull` — one bubble over the whole ship. Capitals carry one
   section per arc. Both run through identical code paths, so there is no
   special-casing for small craft anywhere in the resolver.

## 11. What the POC actually implements

Built and covered by passing specs (`rspec` at the repo root; the count
is noted per slice below, currently 324):

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
  typing a ship's name - `space/board` is a placeholder for that. Done
  in §13b, for any body staff has actually built a landing room at;
  `space/board` stays as the fallback everywhere else.
- Self-service station claiming, and the `Ships.ship_for_char` fix that
  has to ship alongside it once a character can hold a seat on more than
  one ship (`.first` on a hash scan is already technically wrong today,
  just unreachable while only staff can create the ambiguity). Done in
  §13a.
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

## 13b. Walking through a door (slice 3)

`space/board <ship>` (§13) always worked, but it was a placeholder by
design - it never cared whether the ship was actually anywhere you could
plausibly walk in from. This slice is what makes boarding a real door
instead of a command, for the bodies staff have actually built one at.

Most bodies never get this - an unexplored rock has nowhere to dock, and
that's fine. A ship is still "at" a body either way; that's just
`system_key`/`location_key`, untouched by any of this. What's new only
decides whether arriving somewhere *also* opens a walk-in door.

- **`SpaceBodyState.landing_room`** - a body's optional dock, set by
  staff standing in the room and running `space/dock <body>`
  (`check_admin` - this is deciding a planet has a spaceport at all,
  not something a ship's owner needs control over). Retroactive: any
  ship already sitting there when the room gets tagged is docked
  immediately, not just the next arrival.
- **`SpaceShip.dock_exit`** - the door FROM the landing room INTO the
  ship, at wherever it's currently docked. Recreated per visit, not
  reused: more than one ship can be at the same landing room at once,
  each needing its own exit, named after the ship itself (`go Talon
  One`, not `go board ship`).
- **The ship's own way out is different: one persistent exit, not
  recreated.** `Docking.out_exit_for` creates it once, alongside
  `entry_room`, and every dock/undock just retargets its destination.
  There's only ever one destination that makes sense for a given ship
  at a given moment, so recreating it every visit would just mean
  churning object ids for no reason. Named "Out" on purpose - core's own
  `Room#way_out`/`#out_exit` already look for exactly that name, so
  whatever already consumes those keeps working with no special-casing
  on our part.
- **`Docking.dock` is safe to call unconditionally**, and does - from
  `Systems.settle_arrival` (an ordinary arrival), `space_station_cmd.rb`
  (a GM's direct placement), and `space/dock` itself (retroactively). It
  clears any previous docking first, so a ship that skipped a proper
  undock somewhere - a GM's `space/station` skipping the normal
  departure path, say - can't leave a stale door open at the last place
  it was. `Docking.undock` runs the moment a course is set
  (`Systems.set_course`, before travel starts) and on `space/remove`,
  so a ship in transit correctly has no door anywhere, and a deleted
  ship doesn't leave one hanging.

One gap surfaced while wiring this up, not introduced by it:
`Systems.control_record`/`claim` had never actually been exercised in
specs - `control_record`'s own `rescue => nil` was quietly swallowing
the missing `SpaceBodyState` constant every time, and nothing had ever
called `claim` (which has no rescue of its own) to notice `.create`
would raise instead. `set_landing_room` calls the same `.create`, so the
harness needed a real `SpaceBodyState` double before this could be
tested at all - not something this slice broke, but something it made
impossible to keep ignoring.

207 specs pass (9 new: `docking_specs.rb`). The harness also gained
`Exit` and `SpaceBodyState` doubles, both mirroring the same real APIs
they stand in for rather than reinventing behavior.

## 13c. Carrier launch and recovery (slice 4)

The prediction in §13b held: a hangar bay needed no new mechanism, just
the existing one pointed at a room that belongs to a ship instead of a
body.

- **`hangar: true` in `space_ships.yml`** - a design-time choice per
  class, not a size threshold. The Covenant already had a `port` section
  flavored as `flight_deck`; this is that flavor becoming mechanical.
  `ShipBehavior#hangar?` reads it.
- **`SpaceShip.hangar_room`** - a carrier's own landing room, created
  lazily on first use exactly like `entry_room`. A class with no flight
  deck never gets one, and `Docking.hangar_room_for` returns nil rather
  than create one regardless of what a command forgot to check.
- **`Docking.landing_room_for(ship)`** is the one seam that makes
  everything else free: it checks `ship.carrier` first, and only falls
  back to a body's landing room if there isn't one. `dock`/`undock`
  never needed to change - they already just ask "where does this ship
  dock" and retarget exits accordingly, so a hangared fighter docks
  through the exact same code path a ship docks at a body through.
- **`space/land <carrier>`** / **`space/launch`** - `Docking.land`
  requires the target actually have a flight deck, that the boarding
  ship isn't already docked somewhere, that neither ship is in an
  *active tactical engagement* (deliberately out of scope - this never
  touches the resolver's turn structure), and that both are at the same
  system/body. On success the fighter's `system_key`/`location_key` are
  cleared, not synced to the carrier's - a hangared ship's position IS
  "wherever the carrier is," not a second copy of that fact to drift out
  of step. `launch` reverses it, reading the carrier's *current*
  position (which may have moved while the fighter sat docked) rather
  than wherever it was at landing.

220 specs pass (13 new, appended to `docking_specs.rb`). Also gave
`TestShip` three fields it turned out it had never had -
`destination_key`/`departed_at`/`travel_seconds` - and an `in_transit?`
to match: nothing had ever needed a ship's own travel state in a spec
before `land` needed to clear it.

**Bug found smoke-testing on a live server, fixed after the fact:** the
"active engagement" check above originally read `ship.sector ||
carrier.sector` - truthy for *any* ship that had ever been assigned a
sector, not just one currently fighting in it. That's every ship that
exists: `space/spawn` requires a sector argument, and nothing anywhere
in the plugin ever clears `SpaceShip.sector` afterward - `space/station`
and the travel system move a ship between system bodies without
touching it. So `space/land` refused unconditionally, on every ship, the
moment it left the sector it was born in. `Systems.set_course` already
had the right idiom for this exact question -
`Engagements.active_combat(ship.sector)`, not `ship.sector` alone -
`Docking.land` now uses `Engagements.combat_for_ship` to match. Same gap
as `SpaceBodyState` in §13b: `Engagements.sector_combats`'s own `rescue
=> nil` had quietly swallowed a missing `SpaceCombat` harness double,
so nothing had ever exercised "is there really a fight going on" versus
"was this ship ever in a sector at all." The harness now has a
`SpaceCombat` double (mirroring `TestCombat`, which `resolver_specs.rb`
had only ever driven directly, bypassing `SpaceCombat.all` entirely),
and `docking_specs.rb` gained a spec for each half of the distinction.

**Second bug, same source:** `Docking.land` never checked `ship` and
`carrier` for being the same ship. A character crewing the carrier
itself who runs `space/land <own ship>` sailed straight through
`same_position?` - trivially true against yourself - and got
`ship.update(carrier: carrier, system_key: nil, location_key: nil, ...)`
applied to the carrier's own record: `carrier: self`, its own position
cleared, hangared inside its own hangar. Nothing after that point in the
resolver code has a way to tell that apart from a real hangared
fighter, and it isn't cleanly reversible by `space/launch` either -
`launch` reads `carrier.system_key`/`location_key` to restore the
docked ship's position, but here `carrier` *is* the ship, so by the time
`launch` reads it, its own position has already been nil'd by `land`.
Recovering a ship caught in this state needs a GM to reset it directly
with `space/station <ship>=<system>/<body>`, not `space/launch` - and
that only works because `space/station` was also fixed here to clear
`carrier: nil` unconditionally on a direct placement. It didn't before:
`Docking.dock` prefers `hangar_room_for(ship.carrier)` over the
system/body landing room whenever `carrier` is set, so a station command
that left a stale `carrier` in place (self-referential or otherwise)
would silently re-dock the ship into that hangar and ignore the
system_key/location_key it had just been given. A GM placement is
authoritative and should never leave a ship both "at a body" and
"inside a carrier" at once - that combination isn't one the rest of
`Docking` expects.

`Docking.land` now also refuses up front (`space.cannot_land_on_self`)
if `ship.id == carrier.id`, before any state changes, so this can't
happen again going forward.

## 13d. Ring-anchored ships, and the system map's ship markers

Two related product problems, reported from the same screenshot: a
ship's map marker never tracked the body it was parked at (it sat at a
coordinate snapshot from whenever the page last loaded, while the
body's own decorative CSS spin animation kept sweeping around it - the
body visibly drifted away from its own "parked" ship), and there was no
way to represent a ship holding position with no body under it at all -
a capital ship staging between planets, or a station - since every
ship's position was always `location_key`, a body key, full stop.

**Position model.** `SpaceShip` gained `system_ring`
(`DataType::Integer`) and `system_angle` (`DataType::Float`) -
mutually exclusive with `location_key`, the same invariant shape as
`carrier` vs. an independent position from §13c. No config gives a
ring-parked ship's angle the way a body's does, so `Systems.
ring_angle_for(ship)` just spreads ships around the ring
deterministically (`ship.id * 47 % 360`) rather than stacking them all
on the +x axis.

**Command surface.** Both `space/station <ship>=<system>/<n>` and
`space/travel <n>` treat a bare integer as a ring rather than a body -
`Systems.parse_ring` is the one place that distinction gets made.
Internally, a ring destination is encoded as `"ring:<n>"` in
`destination_key`, the same string field a body key already uses,
rather than a second parallel set of transit fields - `Systems.
ring_key`/`ring_from_key` convert at the two edges (`set_course` writes
it, `settle_arrival` reads it back to decide whether a completed trip
lands the ship on a body or a bare ring).

**Which ships get a map marker.** This is the actual fix for the
reported bug, and it's a filter, not an animation patch: `WebData.
system_ship_entries` only marks a ship that's under way, ring-anchored,
or present at a body with an *active engagement* there. A ship simply
parked at a body with nothing going on gets no marker at all - it's
already visible through that body's own `ships` list, the "Present"
panel, and the Bodies table's Ships column, and drawing a second,
independently-positioned dot for it was the bug, not a feature to
preserve. `ship_map_entry` itself still computes a position/status for
*every* ship regardless of this filter, because `own_ship` (the
toolbar's "holding at X" line) needs one even for the excluded,
peaceful-parked case - the filter lives one level up, in
`system_ship_entries`, precisely so `own_ship` doesn't go through it.

**Where the surviving markers live.** An engaged ship is nested inside
its body's own `<g>` in `body_map_entry`'s `engaged_ships` (only
populated when the body actually is engaged, empty otherwise), and
`space-system-map.js`'s `dockedShips` places it exactly like a moon -
a small fixed offset from the body's resting point, riding the same
spin+start transform, with the same two-angle counter-rotation to keep
its label level. A ring-anchored ship has no body to nest inside, so it
gets its own animated group (`ringShips`) structured exactly like a
lone body's spin/start/counter/unstart chain, just ship-styled. Both
reuse the `.space-orbit-spin`/`.space-orbit-counter` CSS classes
verbatim - no new stylesheet needed. The flat `space-system-ships`
layer that used to hold every non-transit ship now only ever holds
ships actually in transit, which is the one case an orbit-spin
animation never applied to in the first place (it tracks a course line
between two points, not a fixed orbit).

Verified two ways: `web_data_specs.rb` gained specs for all four
marker cases (parked-and-excluded, engaged-and-nested, ring-anchored,
transiting-to-a-ring) plus the `own_ship` non-filtering case, and a
Playwright render against the real compiled stylesheet (not the specs'
in-memory harness) confirmed, over a real running CSS animation: a
parked-unengaged ship has no DOM node at all; an engaged ship's marker
stays at a constant, non-drifting distance from its body's core across
the animation; a ring-anchored ship's marker actually moves over time
and stays at a constant radius from the star, i.e. traces its ring
rather than drifting off it.

**Two more gaps surfaced along the way, not introduced by this slice:**
`Systems.system_ships` calls `SpaceShip.all` directly rather than going
through the already-doubled `Ships` module, and there was no
`SpaceShip` constant in the harness at all - every caller (`ships_at`,
`settle_arrivals`, `WebData.system_ship_entries`) was silently hitting
`system_ships`'s own `rescue => e; []` and getting an empty list back,
every time, in every spec that ever ran. Same story for `Systems.
sectors_at`/`engagement_at`: no `SpaceSector` double existed, so
`engagement_at` could never actually return anything - "a ship at an
engaged body" was untestable before this. Both fixed the same way as
`SpaceBodyState`/`SpaceCombat` earlier: `Systems.system_ships` is now
overridden in the harness to read `TestWorld.ships` directly, and a
`SpaceSector` module double (`.all`/`.create`/`.reset!`) backs
`TestSector`, which already existed but was only ever constructed
directly, bypassing the lookup path production code actually uses.

258 specs pass (36 new: 27 in `systems_specs.rb` - a from-scratch file,
since `Systems.set_course`/`settle_arrival` had no direct coverage at
all before this - plus 9 new cases in `web_data_specs.rb`).

## 14. Pluggable dice

Nothing about ships, arcs, sections, silhouette or the round structure is
FS3-specific — only the dice are. `plugin/dice/` is the seam that lets a
game on another system use everything else. FS3 remains the default and
needs no configuration; a game that sets nothing behaves exactly as it
always has.

Worth stating plainly: **Ares core has no system-agnostic dice interface
to conform to.** There is no registry, no dispatcher, no roll API — the
only cross-system convention in core is `<System>.app_review(char)`,
dispatched by a hardcoded if-chain in chargen. So this is a convention we
are defining, not one we are implementing. If Ares ever grows a standard,
this wants revisiting.

### The contract

An adapter is a stateless module with four methods:

```ruby
available?                             # is the system loaded and enabled?
known_ability?(ability)                # would this ability really resolve?
roll_ability(char, ability, modifier)  # => { successes:, ... }
roll_pool(rating, modifier)            # => { successes:, ... }
```

Both roll methods return a hash carrying an **Integer `:successes`**.
That scalar is the whole contract with the combat math. Extras are
welcome and pass through untouched — the resolver ignores them.

Reserved keys an adapter must not return, because something downstream
owns them: `:roller` and `:ability` (`Crew` stamps these *after* the
roll, so an adapter cannot overwrite a display name already resolved),
and `:range`, `:station`, `:modifier` (merged over the roll hash by
`Sensors.sweep`).

`known_ability?` exists because of a real FS3 footgun worth repeating for
anyone writing an adapter: FS3's `get_ability_type` answers `:background`
for a name it has never heard of rather than failing, so a typo'd skill
silently becomes a one-die everyman roll instead of an error. Any system
needs an equivalent "is this real?" answer or a misconfigured station
degrades invisibly.

`roll_pool` takes the raw rating and the modifier **separately** rather
than a finished die count. Combining them — and deciding there is a floor
of one die — is an FS3 rule, so it lives in the FS3 adapter rather than
being imposed on every system on the way in.

### Selection

`space.yml`'s `dice_system` names it. A bare name is one shipped here
(`fs3` → `Space::Dice::Fs3Adapter`, case-insensitive, underscores
camel-cased); a name containing `::` is a fully-qualified constant, so a
third-party system can ship its adapter inside its **own** plugin rather
than reopening this namespace.

Lookup happens per call, not via load-time registration: core's
`PluginManager#code_files` globs directories in no guaranteed order (and
`dice` sorts before `helpers`), so anything self-registering into a table
at load time would race whatever populates that table.

### Failure is degraded, not fatal

`Dice.invoke` funnels both roll paths so a missing, half-written,
unavailable or exploding dice system yields zero successes instead of
raising. That matters more than it looks: **the resolver spends ammo
before it rolls**, so an exception escaping a roll would abandon the
round half-applied — ammo gone, movement committed, no report emitted. A
zero is a bad roll; a raise is a corrupt round. `check_config` reports
all four failure modes by name at startup.

### What this does and doesn't buy an FFG game

The user's motivating example was Star Wars on FFG/Genesys narrative
dice. Under this contract an FFG adapter **can** map a character and
ability to that game's pool, decide what `modifier: +2` means (two boost
dice, say), collapse the symbol results to a net-successes integer, and
return `advantage:`/`threat:`/`triumph:`/`despair:` as extras.

As of §16/§17 below, it also **can** spend net threat into `:strain` on
the acting ship (a real, mechanical consequence - see §16) and describe
advantage/triumph/despair in `:detail`, which now reaches the round
report (see §17). That closes the gap this section used to describe here
and retires the corresponding item from §15.

It still **cannot**, without further work:

- **Give arbitrary symbols beyond strain/detail any mechanical
  consequence.** The resolver's side-effects channel is exactly two keys
  wide. Advantage cannot recover a shield point through this channel;
  despair cannot wreck a hardpoint. An adapter that wants more than
  "spend threat into strain, narrate the rest" needs new plugin
  mechanics, not just a wider hash.
- **Escape FS3's calibration.** `hit_threshold`, `untrained_dice`,
  `range_mods`, `silhouette_tohit_clamp`, `Rules.damage_bonus(net) ==
  net - 1`, one success = one hull point repaired, and one success = one
  grid cell of extra sweep range are all sized to FS3's success curve. An
  adapter returning a 0-or-1 binary makes `damage_bonus` dead and repairs
  uselessly slow; one returning a d20-style margin makes damage explode.

That last one is the largest limitation and the least obvious: **the code
seam is narrow, but the numeric calibration is not.** Writing an adapter
is a small job; tuning `space.yml` so a non-FS3 game plays well is the
real one. This contract makes another system *usable*, not *native* — a
deliberate trade to keep a working, well-tested resolver stable.

304 specs pass (46 new: `dice_specs.rb` for the seam itself, and
`crew_dice_specs.rb` for what `Crew` hands down plus a full round —
attacks, evasion, repair, sweeps — resolved end-to-end by a fake system
that is deliberately not FS3. That last one is the actual proof the
combat math runs off the scalar and nothing else). The harness gained a
`TestConfig.override` hook, since the suite uses no rspec-mocks anywhere
and had no way to exercise a non-default setting.

## 15. Still to do

- A "?" indicator somewhere a character's status is shown, for when
  `Character.current_ship` and `Boarding.aboard?` disagree (see §13) -
  flagged as a real gap when the stamp was designed, not yet built
  because nothing displays a character's location today for it to
  attach to.
- Pseudo-real-time tick (§9), after the POC has been played.
- The FFG adapter itself - blocked on the upgraded FFG plugin exposing
  an integer net-success count. See §18.

## 16. System strain — a second damage track

Ship-level, not per-section. The per-section shields/hull model (§4)
already covers the "zoned" half of FFG's damage model; strain is the
whole-ship "stressed, not broken" pool sitting beside it, the same way
FFG has it.

**Why this and not a fork.** The alternative considered was a parallel
FFG-flavoured combat mode. Two things ruled that out: the Ares FFG plugin
(`AresMUSH/ares-ffg-plugin`, checked at HEAD `1f446d8`) has no ship or
vehicle layer at all — no silhouette, hull, shields, arcs, or anything
this plugin would need to defer to — so there's nothing to converge
*with* short of building it here; and a range-band position model (the
other FFG-native idea) isn't a `Geometry` mode but a genuinely different
movement/arc/section-selection model, its own project (see §19). Strain
and the roll side-effects channel (§17) are the two pieces of this slice
that are system-agnostic and stand on their own for FS3 games — nothing
here is FFG-only.

**Model.** `SpaceShip#strain` (Integer, default 0). Threshold comes from
`ShipBehavior#strain_threshold`: `space_ships.yml`'s `strain_threshold:`
per class if set, else `silhouette * 2` — so every class defined before
strain existed keeps working untouched.

**Rules** (`plugin/helpers/rules.rb`, pure — no Ohm, no config):

```ruby
Rules.apply_strain(current, amount, threshold)  # => { strain:, events: [] }
Rules.recover_strain(current, amount)           # => clamped at 0
Rules.strained_out?(strain, threshold)          # => strain >= threshold
```

`apply_strain` emits `:strained_out` only on the blow that crosses the
threshold, mirroring how `apply_damage` emits `:section_destroyed` once
rather than on every hit after a section is already wrecked.

**Behaviour.** A strained-out ship is **disabled, not destroyed**: its
`status` stays `"active"`, so every existing `active?`/`destroyed?` check
keeps meaning exactly what it always meant. `strained_out?` is a second,
*derived* gate the resolver has to remember to ask about — deliberate
(it would have been a bigger, riskier change to thread a new `status`
value through everything that switches on it), but it means future phase
code has to remember to check both.

**Resolver.** A strained-out ship skips the movement and attack phases
entirely (`Resolver.resolve_movement`/`resolve_attacks`), but still rolls
engineering and sensors — being adrift is exactly when you want the
engineer working. Recovery is passive, `strain.regen` per round
(`space.yml`, same shape as `damage.shield_regen`), applied in
`finish_round` alongside `Ships.regen_shields`. An engineering order,
`space/vent` (`Orders.issue(ship, :vent)`), rolls engineering and spends
successes to vent strain directly — the same shape as `space/repair`.

**Where strain comes from**, in this slice:

1. The roll side-effects channel (§17) — the FFG hook.
2. A botched roll: `strain.on_botch` (`space.yml`, default 1), applied
   whenever a roll's `:successes` comes back negative — FS3 botches at
   -1. This is what gives strain a role for a game that never wires up
   an FFG-style adapter: "the manoeuvre went badly and you stressed the
   frame" is a natural, system-neutral reading, not an FFG-only idea
   wearing an FS3 costume.
3. GM/engineering adjustment (direct `ship.update(strain: ...)`, same as
   any other stat).

`Resolver.apply_roll_strain(ship, roll, report)` is the one place a roll
becomes strain — every phase that rolls (sweeps, evasion, attacks,
engineering) funnels through it rather than reimplementing the botch
check.

Deliberately **not** built here: strain-dealing weapon qualities, or
speed-pushing strain. Both are real FFG concepts, but each is its own
feature and neither is needed to give advantage/threat a home.

## 17. The roll side-effects channel

Two optional keys an adapter's roll result may carry, documented in
`plugin/dice/dice.rb` alongside the rest of the contract (§14) and read
by the resolver when present:

| Key | Type | Meaning |
|---|---|---|
| `:strain` | Integer | strain inflicted on the **acting** ship |
| `:detail` | String | short narrative note, rendered in the round report |

Both are additive to the base contract — `:successes` remains the only
required key, and `Rules` is untouched by either. `Dice.invoke` already
merges an adapter's whole hash through, so no filtering was needed to
add these; the change was entirely in what the resolver and `display.rb`
do with keys that were already arriving and being dropped.

`:strain` is spent through `Resolver.apply_roll_strain` (§16) — additive
to whatever that same call applies for a botched roll, so a roll can be
both a mechanical botch *and* carry adapter-supplied strain in one shot.
`:detail` rides into the matching report entry (sweep/evade/attack/
engineering) under its own `:detail` key and is rendered by
`Display.render_report` next to that line.

An FFG adapter's mapping, once it exists: net successes → `:successes`;
net threat → `:strain`; advantage/triumph/despair prose → `:detail`. The
FS3 adapter returns neither key, so a game that never sets `dice_system`
sees no behaviour change — verified by the existing 304 specs staying
green plus new coverage in `crew_dice_specs.rb`'s "roll side-effects
channel" block (scripts a result with both keys via `FakeAdapter`, then
scripts a bare FS3-shaped result and asserts nothing moved).

324 specs pass (20 new: `rules_specs.rb` for `apply_strain`/
`recover_strain`/`strained_out?` including the crossing-transition-only
event; `strain_specs.rb` for the resolver lifecycle — skips movement and
attacks while strained out, still rolls engineering and sensors, passive
regen, `space/vent`, the botch source, stays `active?`/not `destroyed?`;
and a "roll side-effects channel" block in `crew_dice_specs.rb` scripting
`FakeAdapter` results with and without `:strain`/`:detail`).

This closes the gap §14 used to describe — extras documented but
unreachable — and retires that item from §15.

## 18. What the FFG adapter will need from the FFG plugin

Not built in this slice. The FFG plugin is being upgraded in parallel to
cover full advantage handling and a web portal; this section is a target
list for that work, written against HEAD `1f446d8`, so both sides can
meet in the middle. **If the upgrade reshapes the roll API, re-read
`rolls.rb` before writing the adapter rather than trusting the mapping
table here.**

Full advantage handling is the upstream half of §17: the FFG plugin
decides *what* advantage and threat buy in FFG terms; `:strain`/
`:detail` are where the ship-combat consequences land here. The two
designs fit together without either side knowing the other's internals.

One blocker is concrete in today's code: `Ffg.determine_outcome(dice)`
computes `successes` and `failures` locally and then **discards the
magnitude**, returning `FfgRollResults` with `successful` as a *Boolean*.
This plugin's contract needs an integer.

For the adapter to be writable, the upgraded plugin should expose:

1. **Net success count as an Integer** (`successes − failures`), not just
   `successful`. The hard requirement — damage scales off it.
2. **A structured roll entry point.** Today the only way in is
   `Ffg.roll_ability(char, roll_str)`, where `roll_str` is a *display*
   string like `"Piloting Space+2D+1B"`, reparsed internally. An adapter
   would have to build strings; a params-object or keyword entry point
   would be far more robust.
3. **Triumph/despair as counts**, not Booleans, if they should scale
   into `:detail` or a future extension of the side-effects channel.
4. **A stable home for these.** The roll functions currently live in
   `plugin/rolls.rb`, not `plugin/public/`, so they carry no stability
   contract by Ares convention.

**Install note worth documenting:** the FFG plugin's default *Genesys*
config has no piloting or gunnery skills at all — only the `sw-eote` and
`sw-rebellion` config sets do. A Star Wars config set is a prerequisite
for `station_skills` to resolve, and `config/check` (§14's
`Dice.check_config`) will already report this correctly once an adapter
exists.

## 19. Deferred (with reasons, so they aren't rediscovered)

- **Range bands.** Not a `Geometry` mode — a different position model.
  `Rules.range_mod` is already abstract (it takes scalars), so a future
  band mode is feasible, but it needs new rules for movement, the
  firing-arc gate, and section selection, plus a parallel
  `space-plot.js` renderer (which duplicates the Ruby direction tables
  in JS — see §8). Its own project.
- **Critical hit tables.** A real FFG concept with no analogue here, and
  not needed to make advantage/threat matter.
- **Fleet scale.** Agreed as its own later slice. Worth noting it is
  *not* FFG-specific in shape: "a big battle resolves over a few command
  rolls and the PCs' actions tilt it" works on FS3 equally well.
