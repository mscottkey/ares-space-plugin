module AresMUSH
  module Space

    # Retargets exits so boarding is walking through a door once a ship
    # is actually somewhere with one, instead of always typing its name.
    # space/board (slice 1) is what this falls back to when there's
    # nowhere to walk in from - deep space, a body nobody's built a
    # landing room for, or a sector, which is instruments only (§7) and
    # was never meant to have a door.
    #
    # Most bodies have no landing_room at all, and that's fine - a ship
    # is still "at" one either way (that's just system_key/location_key
    # on the ship, untouched by any of this). This only ever decides
    # whether arriving there also opens a walk-in door.
    module Docking

      # The ship's own way out. Created once, alongside entry_room, and
      # retargeted on every dock/undock rather than recreated - there's
      # only ever one, and it belongs to the ship, not to wherever it
      # currently happens to be docked. Named "Out" on purpose: core's
      # own Room#way_out/#out_exit already look for exactly that name,
      # so a plain `go out` (or whatever core's own tools build on that)
      # already works with no special-casing here.
      def self.out_exit_for(ship)
        room = Boarding.entry_room_for(ship)
        room.get_exit("Out") || Exit.create(name: "Out", source: room, dest: nil)
      end

      # Points a ship's own exit at wherever it's currently docked, and
      # gives the landing room a door back in, named after the ship -
      # unlike the ship's own exit, this one can't be a single
      # persistent reference, because more than one ship can be docked
      # at the same landing room at once, each needing its own door.
      #
      # Safe to call unconditionally whenever a ship's position changes,
      # arrival or a GM's direct placement alike - it clears any
      # previous docking first, so a ship that skipped a proper undock
      # can't leave a stale door open at the last place it was.
      def self.dock(ship)
        undock(ship)

        room = Systems.landing_room_for(ship.system_key, ship.location_key)
        return if !room

        out_exit_for(ship).update(dest: room)
        ship.update(dock_exit: Exit.create(name: ship.name, source: room, dest: Boarding.entry_room_for(ship)))
      end

      # Closes the door both ways. Called on departure (before travel
      # starts) as well as defensively at the top of dock - between
      # those two, a ship in transit correctly has no door anywhere,
      # the same way it has no location_key worth reading.
      def self.undock(ship)
        out = ship.entry_room ? ship.entry_room.get_exit("Out") : nil
        out.update(dest: nil) if out

        return if !ship.dock_exit
        ship.dock_exit.delete
        ship.update(dock_exit: nil)
      end
    end
  end
end
