module AresMUSH
  module Space

    # The seam between space and the human layer.
    #
    # Every skill roll in this plugin goes through here and out to core
    # FS3. We never roll our own dice, never invent a skill system, and
    # never touch fs3combat's turn loop - only fs3skills' public API.
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

      # Does FS3 actually know this ability, or would it quietly treat it
      # as an unknown background and hand back a single die?
      def self.known_ability?(ability)
        return false if ability.nil?
        return false if !fs3_available?
        type = FS3Skills.get_ability_type("#{ability}")
        [ :action, :attribute, :language, :advantage ].include?(type)
      rescue => e
        Global.logger.debug "Space: could not classify ability #{ability}: #{e}"
        false
      end

      def self.fs3_available?
        defined?(FS3Skills) && FS3Skills.respond_to?(:one_shot_roll)
      end

      # Rolls a station's action.
      #
      # Returns { successes:, success_title:, roller:, ability:, dice: }.
      # Successes are FS3's: a positive count, 0 for failure, -1 for a
      # botch. A botched evasion leaving you easier to hit is intended.
      def self.roll_station(ship, station, modifier = 0)
        crew = ship.crew_at(station)
        ability = SpaceConfig.skill_for_station(station)
        roller = crew_name(crew)

        if !fs3_available?
          Global.logger.error "Space: FS3Skills is unavailable; cannot roll #{station}."
          return { successes: 0, success_title: t('space.no_fs3'), roller: roller,
                   ability: ability, dice: 0 }
        end

        char = crew_char(crew)

        if char && known_ability?(ability)
          result = FS3Skills.one_shot_roll(char, FS3Skills::RollParams.new(ability, modifier.to_i))
          return result.merge(roller: char.name, ability: ability, dice: nil)
        end

        # An NPC hand, an unmanned station, or a skill this game's FS3
        # config doesn't define: roll a flat pool rather than let FS3
        # silently treat an unknown ability as a single everyman die.
        base = npc_rating(crew) || SpaceConfig.untrained_dice
        dice = [ base.to_i + modifier.to_i, 1 ].max
        result = FS3Skills.one_shot_die_roll(dice)

        if char && !known_ability?(ability)
          Global.logger.warn "Space: station #{station} maps to '#{ability}', which FS3 does not define. Rolling #{dice} untrained dice."
        end

        result.merge(roller: roller, ability: ability, dice: dice)
      end

      # Rolls a flat pool with no station behind it (terrain hazards etc).
      def self.roll_dice(dice)
        return { successes: 0, success_title: t('space.no_fs3') } if !fs3_available?
        FS3Skills.one_shot_die_roll([ dice.to_i, 1 ].max)
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
