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
    #
    # A hangared small craft reuses every bit of this: the room it docks
    # into just happens to belong to a ship (carrier.hangar_room) rather
    # than a body. See landing_room_for.
    module Docking

      # Where a ship is docked, if anywhere - a carrier's hangar_room if
      # it's parked inside one, otherwise whatever landing room its
      # current body has (which may be none). A hangared craft has no
      # system_key/location_key of its own (see land/launch below), so
      # checking carrier first isn't just an optimization - it's the
      # only path that means anything for it.
      def self.landing_room_for(ship)
        return hangar_room_for(ship.carrier) if ship.carrier
        Systems.landing_room_for(ship.system_key, ship.location_key)
      end

      # A carrier's own hangar, created lazily the first time something
      # actually docks in it - same reasoning as entry_room: most ships,
      # even hangar-capable ones, spend a test fight never using it.
      # Returns nil for a class with no flight deck at all; nothing
      # should be landing there regardless of what a command forgot to
      # check.
      def self.hangar_room_for(carrier)
        return nil if !carrier.hangar?
        return carrier.hangar_room if carrier.hangar_room

        room = Room.create(name: "#{carrier.name} (Flight Deck)")
        carrier.update(hangar_room: room)
        room
      end

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
      # arrival, a GM's direct placement, or landing in a hangar alike -
      # it clears any previous docking first, so a ship that skipped a
      # proper undock can't leave a stale door open at the last place it
      # was.
      def self.dock(ship)
        undock(ship)

        room = landing_room_for(ship)
        return if !room

        out_exit_for(ship).update(dest: room)
        ship.update(dock_exit: Exit.create(name: ship.name, source: room, dest: Boarding.entry_room_for(ship)))
      end

      # Closes the door both ways. Called on departure (before travel
      # starts) as well as defensively at the top of dock - between
      # those two, a ship in transit correctly has no door anywhere,
      # the same way it has no location_key worth reading. Also what a
      # freshly launched fighter goes through: flying, it has no door,
      # the same as a ship in transit between bodies.
      def self.undock(ship)
        out = ship.entry_room ? ship.entry_room.get_exit("Out") : nil
        out.update(dest: nil) if out

        return if !ship.dock_exit
        ship.dock_exit.delete
        ship.update(dock_exit: nil)
      end

      # ---------------------------------------------------------------
      # Carrier launch/recovery
      # ---------------------------------------------------------------
      #
      # Deliberately outside a tactical sector: neither of these touches
      # the resolver's turn structure, so both refuse while either ship
      # is in an active engagement rather than get tangled in it. A
      # hangared craft has no system_key/location_key of its own - its
      # position IS "wherever the carrier is," not a second copy of that
      # fact to keep in sync.

      def self.land(ship, carrier)
        # Without this, a character crewing the carrier itself
        # (space/land <own ship>) sails straight through same_position? -
        # trivially true against yourself - and sets carrier: self,
        # clearing its own system_key/location_key in the process. That's
        # not a hangared ship anymore, it's a ship whose position is
        # itself; nothing after this point can distinguish that from
        # every other checked precondition, so it has to be caught first.
        return failure(t('space.cannot_land_on_self', ship: ship.name)) if ship.id.to_s == carrier.id.to_s
        return failure(t('space.not_a_carrier', name: carrier.name)) if !carrier.hangar?
        return failure(t('space.already_docked', ship: ship.name)) if ship.carrier
        return failure(t('space.ship_in_combat', ship: ship.name)) if Engagements.combat_for_ship(ship) || Engagements.combat_for_ship(carrier)
        return failure(t('space.not_together', ship: ship.name, carrier: carrier.name)) if !same_position?(ship, carrier)

        ship.update(carrier: carrier, system_key: nil, location_key: nil,
                    destination_key: nil, departed_at: nil, travel_seconds: 0)
        dock(ship)
        success(t('space.landed', ship: ship.name, carrier: carrier.name))
      end

      def self.launch(ship)
        return failure(t('space.not_docked', ship: ship.name)) if !ship.carrier

        carrier = ship.carrier
        ship.update(carrier: nil, system_key: carrier.system_key, location_key: carrier.location_key)
        undock(ship)
        success(t('space.launched', ship: ship.name, carrier: carrier.name))
      end

      def self.same_position?(ship, carrier)
        !ship.system_key.to_s.empty? &&
          ship.system_key.to_s == carrier.system_key.to_s &&
          ship.location_key.to_s == carrier.location_key.to_s
      end

      def self.success(message)
        { ok: true, message: message, error: nil }
      end

      def self.failure(error)
        { ok: false, message: nil, error: error }
      end
    end
  end
end
