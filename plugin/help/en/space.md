---
toc: Space
order: 1
summary: Ships, sectors and space combat.
aliases:
- ships
- tactical
---

# Space

Space is not a room. You never walk into a sector - you read it off your
ship's instruments from wherever you are: the bridge, a cockpit, the
mess. Roleplay happens in normal grid rooms; the tactical situation is a
persistent overlay you pull up with a command.

All crew actions - flying, shooting, repairs, sensors - resolve through
your normal FS3 skills.

## Reading the plot

`space/tac`
Your ship's tactical plot: the sector grid, your heading and speed, and
every contact your sensors have resolved. Close contacts are identified;
distant ones and anything hiding in dust or debris show as `?`.

`space/contacts`
The contact list on its own - bearing, range and aspect for each.

`space/status [<ship>]`
Your ship's sections, shields, hull, systems, hardpoints and crew. With a
name, shows that ship instead.

`space/orders`
What your ship is set to do when the round resolves.

`space/clear`
Cancels your ship's pending orders.

## Giving orders

Orders are stored and take effect when the GM resolves the round. Several
stations can act in the same round, and on a single-seat fighter the
pilot can both fly and shoot.

`space/helm <heading>=<speed>`
Come to a heading at a speed. Headings are compass points - N, NE, E, SE,
S, SW, W, NW on a square sector; NE, E, SE, SW, W, NW on a hex one. Your
hull only turns so far in a round (its agility), so a hard reversal takes
more than one round. Speed above what the hull can manage is capped.

Example: `space/helm NE=3`

`space/evade`
Fly evasively instead of moving. Rolls Piloting once and banks the
successes as your defense against every shot aimed at you this round.

`space/hold`
Hold position.

`space/fire <target>=<hardpoint>`
Fire a hardpoint at a contact. Hardpoint numbers come from
`space/status`. Each hardpoint covers a fixed arc, so the target has to
bear when the round resolves - and everyone moves before anyone shoots,
so a shot lined up now may not bear then. You will be warned if it
doesn't currently bear.

Example: `space/fire Mote Alpha=0`

`space/repair <section>`
Damage control on a section. Rolls Engineering; successes restore hull.

`space/sweep`
Active sensor sweep. Rolls Sensors and pushes your detection range out
for the round.

## How a round resolves

1. Sensor sweeps.
2. Evasive pilots bank their defense.
3. Everyone moves at once.
4. Weapons fire, smallest ships first - nimble craft get their shot off
   before a capital's batteries can bear. Arcs and ranges are checked
   from where ships ended up, not where they started.
5. Damage control.

Damage burns through the struck side's shields, then that section's hull.
Wrecking a section knocks out the systems mounted in it - engines,
sensors, weapons, the flight deck.

## Size classes

Every hull has a silhouette, from a fighter at 3 to a capital ship at 8.
Shooting something much bigger than you is easier; something much smaller
is harder.

Fighter-scale guns can wound a capital ship - stripping shields, wrecking
sections and knocking out systems - but they will never breach its hull
on their own. Capital guns track fighters badly, but a hit is fatal. That
is what lets fighters and capital ships share one battle.

## For GMs

`space/sector <name>=<options>` - create a sector. Options: `hex` for hex
geometry, and a size like `20x20`. Example:
`space/sector Concord Graveyard=hex 20x20`

`space/sectors` - list sectors and whether they're engaged.

`space/spawn <sector>/<class>=<name>` - spawn a ship.
Example: `space/spawn Concord Graveyard/Talon=Talon One`

`space/place <ship>=<x,y>/<facing>` - move a ship directly.

`space/crew <ship>/<station>=<character>` - assign a station. Use
`npc:<dice>` for NPC hands, or `none` to clear it.
Example: `space/crew Talon One/pilot=Rhee`

`space/terrain <sector>/<type>=<x,y>/<radius>` - place terrain.

`space/start <sector>` - begin an engagement.

`space/resolve <sector>` - resolve the round and report it to every crew
in the sector.

`space/end <sector>` - end the engagement.

`space/remove <ship>` - delete a ship.

Ship classes, weapons and every tuning number live in
`game/config/space_ships.yml`, `space_weapons.yml` and `space.yml`.
