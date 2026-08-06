module AresMUSH
  module Space

    # Where a ship meets the room grid.
    #
    # A ship is a single grid room for as long as a scene runs - everyone
    # works their station from wherever they're standing, whatever the
    # ship's fiction says its deck plan looks like. entry_room is where
    # boarding always lands you and, once docking retargets exits, the
    # anchor an exit points at. operational_rooms is the wider set a
    # character can actually run ship commands from: entry_room always
    # counts, and staff or the ship's owner can tag more rooms onto it by
    # standing in them - deliberately unlabeled, since nothing here cares
    # whether you're on the bridge or in engineering, only whether you're
    # somewhere that counts as on duty. A private cabin off the same
    # interior isn't tagged, and doesn't count.
    #
    # Movement itself is never reimplemented here. Rooms.move_to is core's
    # own public API (plugins/rooms/public/rooms_api.rb) - the same thing
    # a plain `go` command calls - so boarding gets the real arrival/
    # departure room echoes for free instead of a silent teleport.
    module Boarding

      # Creates the room on first need rather than at spawn: most ships
      # spawned for a test fight are never boarded at all.
      def self.entry_room_for(ship)
        return ship.entry_room if ship.entry_room

        room = Room.create(name: "#{ship.name} (Ship)")
        rooms = (ship.operational_rooms || []) + [ room.id.to_s ]
        ship.update(entry_room: room, operational_rooms: rooms.uniq)
        room
      end

      # Any room a character can run ship commands from - always
      # entry_room, plus whatever's been tagged on.
      def self.aboard?(char, ship)
        return false if !char || !char.room
        entry = ship.entry_room
        return true if entry && char.room.id.to_s == entry.id.to_s
        (ship.operational_rooms || []).include?(char.room.id.to_s)
      end

      # The reverse lookup: which ship, if any, counts this room as part
      # of it. Used by commands that take no ship argument because you
      # can only stand in one room, and therefore be aboard at most one
      # ship, at a time.
      def self.ship_for_room(room)
        return nil if !room
        Ships.all_ships.find do |s|
          (s.entry_room && s.entry_room.id.to_s == room.id.to_s) ||
            (s.operational_rooms || []).include?(room.id.to_s)
        end
      end

      # Adds the room the enactor is standing in to the ship's
      # operational set. Idempotent - tagging the same room twice is a
      # no-op, not an error.
      def self.tag_room(ship, room)
        return failure(t('space.no_room')) if !room
        rooms = (ship.operational_rooms || [])
        return success(t('space.room_already_tagged', room: room.name)) if rooms.include?(room.id.to_s)

        ship.update(operational_rooms: rooms + [ room.id.to_s ])
        success(t('space.room_tagged', room: room.name, ship: ship.name))
      end

      def self.board(client, char, ship)
        return failure(t('space.already_aboard', ship: ship.name)) if aboard?(char, ship)

        room = entry_room_for(ship)
        remember_origin(ship, char, char.room)
        Rooms.move_to(client, char, room, "board")
        # Overwrites whatever was stamped before, including a stale
        # "still on the last ship" left over from wandering off it
        # without disembarking - boarding a different ship is what
        # changes which one your orders go to, not walking away from
        # the last one did.
        char.update(current_ship: ship)
        success(t('space.boarded', ship: ship.name))
      end

      def self.disembark(client, char, ship)
        return failure(t('space.not_aboard', ship: ship.name)) if !aboard?(char, ship)

        destination = recall_origin(ship, char) || Rooms.ooc_room
        forget_origin(ship, char)
        Rooms.move_to(client, char, destination, "disembark")
        char.update(current_ship: nil)
        success(t('space.disembarked', ship: ship.name))
      end

      def self.remember_origin(ship, char, room)
        record = (ship.boarded_from || {}).dup
        record[Crew.char_key(char)] = room ? room.id.to_s : nil
        ship.update(boarded_from: record)
      end

      def self.recall_origin(ship, char)
        id = (ship.boarded_from || {})[Crew.char_key(char)]
        id ? Room[id] : nil
      end

      def self.forget_origin(ship, char)
        record = (ship.boarded_from || {}).dup
        record.delete(Crew.char_key(char))
        ship.update(boarded_from: record)
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
