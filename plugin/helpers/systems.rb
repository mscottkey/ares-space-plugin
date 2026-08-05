module AresMUSH
  module Space

    # Star systems: the view a crew has of space when nobody is shooting.
    #
    # A ship's normal position is a body in a system. Sectors - the
    # tactical grids - are only spun up when there's a fight, and anchor
    # to a body so the system map can show where it's happening.
    module Systems

      # ---------------------------------------------------------------
      # Config
      # ---------------------------------------------------------------

      def self.all_systems
        Global.read_config("space", "systems") || {}
      end

      def self.system(key)
        return nil if key.nil?
        systems = all_systems
        systems[key] || systems.find { |k, _v| k.downcase == "#{key}".downcase }&.last
      end

      # Accepts a config key or a display name, so players can type either.
      def self.find_system_key(name_or_key)
        return nil if name_or_key.nil?
        wanted = "#{name_or_key}".downcase
        all_systems.each do |key, data|
          return key if key.downcase == wanted
          return key if "#{data['name']}".downcase == wanted
        end
        nil
      end

      def self.default_system_key
        all_systems.keys.first
      end

      def self.body_classes
        Global.read_config("space", "body_classes") || {}
      end

      def self.body_class(name)
        body_classes["#{name}"] || {}
      end

      def self.faction_colors
        Global.read_config("space", "faction_colors") || {}
      end

      def self.faction_color(faction)
        faction_colors["#{faction}"]
      end

      def self.orbit_layout
        Global.read_config("space", "orbit_layout") || {}
      end

      def self.travel_config
        Global.read_config("space", "travel") || {}
      end

      # ---------------------------------------------------------------
      # Bodies
      # ---------------------------------------------------------------

      def self.bodies(system_key)
        data = system(system_key)
        return [] if !data
        (data["bodies"] || [])
      end

      def self.body(system_key, body_key)
        return nil if body_key.nil?
        wanted = "#{body_key}".downcase
        bodies(system_key).find do |b|
          "#{b['key']}".downcase == wanted || "#{b['name']}".downcase == wanted
        end
      end

      def self.body_name(system_key, body_key)
        b = body(system_key, body_key)
        b ? (b["name"] || b["key"]) : nil
      end

      # A moon sits on its parent's ring; everything else has its own.
      def self.effective_ring(system_key, body_data)
        return body_data["ring"].to_i if body_data["ring"]
        parent = body(system_key, body_data["parent"])
        parent ? parent["ring"].to_i : 1
      end

      # ---------------------------------------------------------------
      # Control - the one part of a system that changes during play
      # ---------------------------------------------------------------

      def self.control_record(system_key, body_key)
        SpaceBodyState.all.select do |s|
          s.system_key.to_s == "#{system_key}" && s.body_key.to_s == "#{body_key}"
        end.first
      rescue => e
        Global.logger.warn "Space: failed to read body state: #{e}"
        nil
      end

      # Config supplies the starting faction; the database overrides it
      # once somebody takes the place.
      def self.controlling_faction(system_key, body_data)
        record = control_record(system_key, body_data["key"])
        return record.faction if record && !record.faction.to_s.empty?
        body_data["faction"] || "Unclaimed"
      end

      def self.claim(system_key, body_key, faction)
        record = control_record(system_key, body_key)
        if record
          record.update(faction: faction)
        else
          SpaceBodyState.create(system_key: "#{system_key}",
                                body_key: "#{body_key}",
                                faction: faction)
        end
      end

      # ---------------------------------------------------------------
      # Ships in the system
      # ---------------------------------------------------------------

      def self.system_ships(system_key)
        SpaceShip.all.select do |s|
          s.system_key.to_s == "#{system_key}" && !s.destroyed?
        end
      rescue => e
        Global.logger.warn "Space: failed to list ships for system #{system_key}: #{e}"
        []
      end

      def self.ships_at(system_key, body_key)
        system_ships(system_key).select do |s|
          s.location_key.to_s == "#{body_key}" && !s.in_transit?
        end
      end

      # Resolves any completed journeys. Travel has no scheduler behind
      # it - a ship arrives the moment somebody looks and finds its
      # clock has run out.
      def self.settle_arrivals(system_key)
        system_ships(system_key).each { |ship| settle_arrival(ship) }
      end

      def self.settle_arrival(ship)
        return false if !ship.in_transit?
        return false if !Astro.arrived?(ship.departed_at, ship.travel_seconds.to_i)

        ship.update(
          location_key: ship.destination_key,
          destination_key: nil,
          departed_at: nil,
          travel_seconds: 0
        )
        true
      end

      # Sets a course. Returns { ok:, message:, error: }.
      def self.set_course(ship, destination_key)
        settle_arrival(ship)

        system_key = ship.system_key
        return failure(t('space.ship_not_in_system')) if system_key.to_s.empty?

        destination = body(system_key, destination_key)
        return failure(t('space.no_such_body', name: destination_key)) if !destination

        if ship.in_transit?
          return failure(t('space.already_under_way',
            destination: body_name(system_key, ship.destination_key),
            eta: Astro.format_duration(ship.eta_seconds)))
        end

        dest_key = destination["key"]
        if ship.location_key.to_s == dest_key.to_s
          return failure(t('space.already_there', name: destination["name"] || dest_key))
        end

        if travel_config["block_during_combat"] && Engagements.active_combat(ship.sector)
          return failure(t('space.cannot_travel_in_combat'))
        end

        from_ring = current_ring(ship)
        to_ring = effective_ring(system_key, destination)
        seconds = Astro.travel_seconds(from_ring, to_ring, ship.max_speed, travel_config)

        ship.update(
          destination_key: dest_key,
          departed_at: Time.now,
          travel_seconds: seconds
        )

        success(t('space.course_set',
          ship: ship.name,
          destination: destination["name"] || dest_key,
          eta: Astro.format_duration(seconds)))
      end

      def self.current_ring(ship)
        data = body(ship.system_key, ship.location_key)
        data ? effective_ring(ship.system_key, data) : 1
      end

      def self.success(message)
        { ok: true, message: message, error: nil }
      end

      def self.failure(error)
        { ok: false, message: nil, error: error }
      end

      # ---------------------------------------------------------------
      # Sectors anchored to bodies
      # ---------------------------------------------------------------

      def self.sectors_at(system_key, body_key)
        SpaceSector.all.select do |s|
          s.system_key.to_s == "#{system_key}" && s.body_key.to_s == "#{body_key}"
        end
      rescue => e
        Global.logger.warn "Space: failed to list sectors for body: #{e}"
        []
      end

      # Any live engagement at this body, so the map can flag it.
      def self.engagement_at(system_key, body_key)
        sectors_at(system_key, body_key).each do |sector|
          combat = Engagements.active_combat(sector)
          return { sector: sector, combat: combat } if combat
        end
        nil
      end

      def self.anchor(sector, system_key, body_key)
        sector.update(system_key: "#{system_key}", body_key: "#{body_key}")
      end
    end
  end
end
