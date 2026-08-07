module AresMUSH
  module Space

    # Everything a ship derives from its stored attributes and its class
    # definition. Kept separate from the Ohm model so the persistence
    # layer stays thin - and so the resolver can be exercised against a
    # plain in-memory double without the two drifting apart.
    #
    # Includers must provide: name, ship_class, x, y, facing, speed,
    # sections, stations, orders, ammo, status, sector, sweep_range,
    # evade_margin, and an update(hash).
    module ShipBehavior

      def pos
        [ self.x.to_i, self.y.to_i ]
      end

      def active?
        self.status == "active"
      end

      def destroyed?
        self.status == "destroyed"
      end

      def geometry
        self.sector ? self.sector.geometry : "square"
      end

      def facing_name
        Geometry.facing_name(self.geometry, self.facing)
      end

      def class_data
        SpaceConfig.ship_class(self.ship_class) || {}
      end

      def silhouette
        (class_data["silhouette"] || 3).to_i
      end

      def max_speed
        (class_data["speed"] || 0).to_i
      end

      def agility
        (class_data["agility"] || 0).to_i
      end

      # Can this ship carry small craft docked inside it? A design-time
      # choice per class (space_ships.yml), not something that follows
      # automatically from size - a large freighter with no flight deck
      # built in shouldn't suddenly be able to carry fighters.
      def hangar?
        !!class_data["hangar"]
      end

      def hardpoints
        class_data["hardpoints"] || []
      end

      # Small craft carry a single section - one shield bubble over the
      # whole hull. Capitals carry one section per arc.
      def small_craft?
        self.sections.keys.count <= 1
      end

      def section_for_arc(arc)
        return self.sections.keys.first if small_craft?
        name = "#{arc}"
        self.sections.key?(name) ? name : self.sections.keys.first
      end

      def systems_offline
        Rules.systems_offline(self.sections)
      end

      def system_online?(system)
        Rules.system_online?(self.sections, system)
      end

      def total_hull
        Rules.hull_totals(self.sections)
      end

      def crew_at(station)
        self.stations["#{station}"]
      end

      def crewed_stations
        self.stations.keys
      end
    end
  end
end
