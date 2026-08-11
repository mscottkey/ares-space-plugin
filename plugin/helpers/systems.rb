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

      def self.landing_room_for(system_key, body_key)
        record = control_record(system_key, body_key)
        record ? record.landing_room : nil
      end

      def self.set_landing_room(system_key, body_key, room)
        record = control_record(system_key, body_key)
        if record
          record.update(landing_room: room)
        else
          SpaceBodyState.create(system_key: "#{system_key}",
                                body_key: "#{body_key}",
                                landing_room: room)
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

      # Ships holding position in a bare ring - no body, see system_ring
      # on SpaceShip.
      def self.ships_at_ring(system_key, ring)
        system_ships(system_key).select do |s|
          s.location_key.to_s.empty? && s.system_ring.to_i == ring.to_i && !s.in_transit?
        end
      end

      # ---------------------------------------------------------------
      # Ring-only positions (no body) - space/station and set_course
      # both accept a bare ring number, encoded here as "ring:<n>" in
      # destination_key so the existing travel/arrival plumbing (a
      # single string field) doesn't need a second parallel set of
      # fields just for this one case.
      # ---------------------------------------------------------------

      def self.parse_ring(value)
        s = "#{value}".strip
        return nil if s !~ /\A\d+\z/
        s.to_i
      end

      def self.ring_key(ring)
        "ring:#{ring.to_i}"
      end

      def self.ring_from_key(key)
        m = /\Aring:(\d+)\z/.match("#{key}")
        m ? m[1].to_i : nil
      end

      # No config gives a ring-parked ship's bearing the way a body's
      # angle does, so this just spreads ships around the ring instead
      # of stacking every one of them on the +x axis.
      def self.ring_angle_for(ship)
        (ship.id.to_i * 47) % 360
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

        ring = ring_from_key(ship.destination_key)
        if ring
          ship.update(
            location_key: nil,
            system_ring: ring,
            system_angle: ring_angle_for(ship),
            destination_key: nil,
            departed_at: nil,
            travel_seconds: 0
          )
        else
          ship.update(
            location_key: ship.destination_key,
            system_ring: nil,
            system_angle: nil,
            destination_key: nil,
            departed_at: nil,
            travel_seconds: 0
          )
        end
        Docking.dock(ship)
        true
      end

      # A body's display name, or "Ring <n>" for a bare-ring key - the
      # one thing body_name alone can't say, since a ring isn't a body.
      def self.destination_name(system_key, key)
        ring = ring_from_key(key)
        return t('space.ring_n', ring: ring) if ring
        body_name(system_key, key) || key
      end

      # Sets a course. destination is either a body (name or key) or a
      # bare ring number - see parse_ring. Returns { ok:, message:, error: }.
      def self.set_course(ship, destination)
        settle_arrival(ship)

        system_key = ship.system_key
        return failure(t('space.ship_not_in_system')) if system_key.to_s.empty?

        ring = parse_ring(destination)
        body_data = ring ? nil : body(system_key, destination)
        return failure(t('space.no_such_body', name: destination)) if !ring && !body_data

        if ship.in_transit?
          return failure(t('space.already_under_way',
            destination: destination_name(system_key, ship.destination_key),
            eta: Astro.format_duration(ship.eta_seconds)))
        end

        if ring
          dest_key = ring_key(ring)
          dest_name = t('space.ring_n', ring: ring)
          to_ring = ring
          already_there = ship.location_key.to_s.empty? && ship.system_ring.to_i == ring
        else
          dest_key = body_data["key"]
          dest_name = body_data["name"] || dest_key
          to_ring = effective_ring(system_key, body_data)
          already_there = ship.location_key.to_s == dest_key.to_s
        end
        return failure(t('space.already_there', name: dest_name)) if already_there

        if travel_config["block_during_combat"] && Engagements.active_combat(ship.sector)
          return failure(t('space.cannot_travel_in_combat'))
        end

        from_ring = current_ring(ship)
        seconds = Astro.travel_seconds(from_ring, to_ring, ship.max_speed, travel_config)

        ship.update(
          destination_key: dest_key,
          departed_at: Time.now,
          travel_seconds: seconds
        )
        Docking.undock(ship)

        success(t('space.course_set',
          ship: ship.name,
          destination: dest_name,
          eta: Astro.format_duration(seconds)))
      end

      def self.current_ring(ship)
        return ship.system_ring.to_i if ship.system_ring
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
