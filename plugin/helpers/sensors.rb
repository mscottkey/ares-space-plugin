module AresMUSH
  module Space

    # What a ship can actually see.
    #
    # Detection is per-ship, not a global GM reveal: the Covenant's plot
    # and a Talon's gunsight are different instruments looking at the
    # same sector.
    module Sensors

      def self.terrain_type(type)
        (Global.read_config("space", "terrain_types") || {})["#{type}"] || {}
      end

      def self.terrain_label(type)
        terrain_type(type)["label"] || "#{type}".titlecase
      end

      def self.terrain_symbol(type)
        terrain_type(type)["symbol"] || "?"
      end

      # Terrain covering a position, cheapest to compute per lookup.
      def self.terrain_at(sector, position, terrain_list = nil)
        list = terrain_list || Ships.sector_terrain(sector)
        list.select { |terr| terr.covers?(sector.geometry, position) }
      end

      def self.sensor_mod_at(sector, position, terrain_list = nil)
        terrain_at(sector, position, terrain_list).sum do |terr|
          (terrain_type(terr.terrain_type)["sensor_mod"] || 0).to_i
        end
      end

      def self.targeting_mod_between(sector, from, to, terrain_list = nil)
        list = terrain_list || Ships.sector_terrain(sector)
        # Terrain at either end fouls the shot; we don't trace the whole
        # line for the POC, just the endpoints.
        mod = 0
        mod += terrain_at(sector, from, list).sum { |terr| (terrain_type(terr.terrain_type)["targeting_mod"] || 0).to_i }
        mod += terrain_at(sector, to, list).sum { |terr| (terrain_type(terr.terrain_type)["targeting_mod"] || 0).to_i }
        mod
      end

      # How far this ship can see right now: passive reach, extended by a
      # successful sweep this round, and blinded if its sensors are out.
      def self.detection_range(ship)
        return 1 if !ship.system_online?("sensors") && !ship.small_craft?
        [ SpaceConfig.passive_sensor_range, ship.sweep_range.to_i ].max
      end

      # Every contact this ship has resolved.
      #
      # Returns [ { ship:, distance:, bearing:, arc:, faction:, identified: } ].
      # Contacts at the edge of reach or buried in a dust cloud show up as
      # unidentified blips rather than named ships.
      def self.contacts(ship, opts = {})
        sector = ship.sector
        return [] if !sector

        geometry = sector.geometry
        terrain_list = Ships.sector_terrain(sector)
        reach = detection_range(ship)

        Ships.sector_ships(sector).map do |other|
          next if other.id == ship.id
          next if other.destroyed? && !opts[:include_destroyed]

          distance = Geometry.distance(geometry, ship.pos, other.pos)
          concealment = sensor_mod_at(sector, other.pos, terrain_list)
          effective_reach = reach + concealment

          next if distance > effective_reach

          {
            ship: other,
            distance: distance,
            bearing: Geometry.bearing(geometry, ship.pos, other.pos),
            arc: Geometry.arc(geometry, ship.pos, ship.facing, other.pos,
                              SpaceConfig.arc_diagonal_bias),
            faction: other.faction,
            # Close contacts and clean space read cleanly; the rest are blips.
            identified: distance <= (effective_reach / 2.0).ceil
          }
        end.compact.sort_by { |c| c[:distance] }
      end

      # An active sweep: a Sensors roll that pushes reach out to the
      # configured active range for the rest of the round.
      def self.sweep(ship)
        station = Orders.station_for_role(ship, :sensors)
        mod = sensor_mod_at(ship.sector, ship.pos)
        roll = Crew.roll_station(ship, station, mod)

        successes = roll[:successes].to_i
        if successes > 0
          gained = [ SpaceConfig.passive_sensor_range + successes,
                     SpaceConfig.active_sensor_range ].min
          ship.update(sweep_range: gained)
        end

        roll.merge(range: ship.sweep_range.to_i, station: station, modifier: mod)
      end

      def self.clear_sweeps(ships)
        ships.each { |s| s.update(sweep_range: 0) }
      end
    end
  end
end
