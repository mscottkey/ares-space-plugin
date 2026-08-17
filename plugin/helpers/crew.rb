module AresMUSH
  module Space

    # The seam between space and the human layer: who is sitting at which
    # station, under what name, and which ability their seat maps to.
    #
    # WHICH dice then get rolled is Space::Dice's business, not this
    # module's - see plugin/dice/. We never roll our own dice and never
    # invent a skill system.
    module Crew

      CHAR_PREFIX = "char:"
      NPC_PREFIX = "npc:"

      def self.char_key(char)
        "#{CHAR_PREFIX}#{char.id}"
      end

      def self.npc_key(rating)
        "#{NPC_PREFIX}#{rating.to_i}"
      end

      def self.crew_char(crew_value)
        return nil if crew_value.nil?
        return nil if !"#{crew_value}".start_with?(CHAR_PREFIX)
        Character[ "#{crew_value}".after(CHAR_PREFIX) ]
      end

      def self.npc_rating(crew_value)
        return nil if crew_value.nil?
        return nil if !"#{crew_value}".start_with?(NPC_PREFIX)
        "#{crew_value}".after(NPC_PREFIX).to_i
      end

      def self.crew_name(crew_value)
        char = crew_char(crew_value)
        return char.name if char
        rating = npc_rating(crew_value)
        return t('space.npc_crew', rating: rating) if rating
        t('space.unmanned')
      end

      def self.assign(ship, station, crew_value)
        stations = ship.stations.to_h
        stations["#{station}"] = crew_value
        ship.update(stations: stations)
      end

      def self.unassign(ship, station)
        stations = ship.stations.to_h
        stations.delete("#{station}")
        ship.update(stations: stations)
      end

      def self.valid_station?(ship, station)
        (ship.class_data["stations"] || []).map { |s| "#{s}" }.include?("#{station}")
      end

      # Self-service claiming of an OPEN station - no staff needed, but
      # only for a seat nobody's in. Bumping someone already seated is a
      # different action (space/crew), gated to staff or the ship's
      # owner precisely because it isn't self-service.
      def self.claim(char, ship, station)
        return failure(t('space.not_aboard', ship: ship.name)) if !Boarding.aboard?(char, ship)
        return failure(t('space.no_such_station',
          station: station, valid: (ship.class_data["stations"] || []).join(', '))) if !valid_station?(ship, station)
        return failure(t('space.station_occupied',
          station: station, crew: crew_name(ship.crew_at(station)))) if ship.crew_at(station)

        assign(ship, station, char_key(char))
        success(t('space.station_claimed', name: char.name, station: station, ship: ship.name))
      end

      # The inverse - stepping away from a station you hold. Refuses to
      # release a seat that isn't yours; use space/crew to remove
      # someone else from theirs.
      def self.release(char, ship, station)
        return failure(t('space.not_aboard', ship: ship.name)) if !Boarding.aboard?(char, ship)
        return failure(t('space.not_your_station', station: station)) if ship.stations["#{station}"] != char_key(char)

        unassign(ship, station)
        success(t('space.station_released', name: char.name, station: station, ship: ship.name))
      end

      def self.success(message)
        { ok: true, message: message, error: nil }
      end

      def self.failure(error)
        { ok: false, message: nil, error: error }
      end

      # Does the configured dice system actually know this ability, or
      # would it quietly treat it as an unknown and hand back a token
      # roll?
      def self.known_ability?(ability)
        Dice.known_ability?(ability)
      end

      # Rolls a station's action.
      #
      # Returns { successes:, success_title:, roller:, ability:, ... } -
      # `successes` is the scalar the combat math runs on (positive count,
      # 0 for failure, negative for whatever the system calls worse than
      # failure; FS3 botches at -1). A botched evasion leaving you easier
      # to hit is intended. Anything else the dice system returned rides
      # along untouched.
      #
      # roller and ability are stamped AFTER the roll, so an adapter
      # cannot overwrite the display name this module already resolved.
      def self.roll_station(ship, station, modifier = 0)
        crew = ship.crew_at(station)
        ability = SpaceConfig.skill_for_station(station)
        roller = crew_name(crew)
        char = crew_char(crew)

        result =
          if char && known_ability?(ability)
            Dice.roll_ability(char, ability, modifier)
          else
            # An NPC hand, an unmanned station, or a skill this game's
            # dice system doesn't define: roll a flat pool rather than
            # let the system silently treat an unknown ability as a
            # token everyman roll.
            if char
              Global.logger.warn "Space: station #{station} maps to '#{ability}', which the dice system does not define. Rolling untrained."
            end
            Dice.roll_pool(npc_rating(crew) || SpaceConfig.untrained_dice, modifier)
          end

        result.merge(roller: roller, ability: ability)
      end

      def self.station_summary(ship)
        (ship.class_data["stations"] || []).map do |station|
          {
            station: station,
            crew: crew_name(ship.crew_at(station)),
            manned: !ship.crew_at(station).nil?,
            skill: SpaceConfig.skill_for_station(station),
            order: ship.orders["#{station}"]
          }
        end
      end
    end
  end
end
