module AresMUSH
  module Space

    # Builds the JSON payloads the web portal consumes.
    #
    # Kept out of the request handlers so the shape of what the portal
    # sees is testable without faking a web request, and so the telnet
    # console and the browser are provably reading the same state.
    module WebData

      def self.sector_summary(sector)
        combat = Engagements.active_combat(sector)
        {
          id: sector.id,
          name: sector.name,
          geometry: sector.geometry,
          width: sector.width.to_i,
          height: sector.height.to_i,
          ship_count: Ships.sector_ships(sector).count { |s| !s.destroyed? },
          in_combat: !combat.nil?,
          round: combat ? combat.round.to_i : nil
        }
      end

      def self.sectors_list
        SpaceSector.all.to_a.map { |s| sector_summary(s) }.sort_by { |s| s[:name].to_s }
      end

      # Full state of a ship - only ever sent for ships the viewer is
      # entitled to see in detail (their own, or anything if they're staff).
      def self.ship_detail(ship)
        {
          id: ship.id,
          name: ship.name,
          ship_class: ship.ship_class,
          faction: ship.faction,
          x: ship.pos[0],
          y: ship.pos[1],
          facing: ship.facing.to_i,
          facing_name: ship.facing_name,
          speed: ship.speed.to_i,
          max_speed: ship.max_speed,
          agility: ship.agility,
          silhouette: ship.silhouette,
          status: ship.status,
          small_craft: ship.small_craft?,
          sections: sections_payload(ship),
          systems_offline: ship.systems_offline,
          shields: ship.sections.values.sum { |s| s["shields"].to_i },
          max_shields: ship.sections.values.sum { |s| (s["max_shields"] || 0).to_i },
          hull: ship.total_hull[:current],
          max_hull: ship.total_hull[:max],
          hardpoints: Ships.hardpoint_summary(ship),
          stations: Crew.station_summary(ship).map do |s|
            {
              station: s[:station],
              crew: s[:crew],
              manned: s[:manned],
              skill: s[:skill]
            }
          end,
          orders: orders_payload(ship),
          identified: true
        }
      end

      def self.sections_payload(ship)
        ship.sections.map do |name, section|
          {
            name: name,
            shields: section["shields"].to_i,
            max_shields: (section["max_shields"] || 0).to_i,
            hull: section["hull"].to_i,
            max_hull: (section["max_hull"] || 0).to_i,
            systems: section["systems"] || [],
            destroyed: section["hull"].to_i <= 0
          }
        end
      end

      def self.orders_payload(ship)
        helm = Orders.get(ship, "helm")
        {
          helm: helm,
          fire: Orders.fire_orders(ship).map do |order|
            hp = Ships.hardpoint(ship, order["hardpoint"])
            {
              target: order["target"],
              hardpoint: order["hardpoint"],
              weapon: hp ? hp["weapon"] : nil
            }
          end,
          engineering: Orders.get(ship, "engineering"),
          sensors: Orders.get(ship, "sensors"),
          any: !ship.orders.empty?
        }
      end

      # What a contact looks like on someone else's plot. Unidentified
      # blips deliberately carry position and nothing else - the browser
      # must not receive what the crew hasn't resolved.
      def self.contact_payload(contact, geometry)
        ship = contact[:ship]
        base = {
          id: ship.id,
          x: ship.pos[0],
          y: ship.pos[1],
          distance: contact[:distance],
          bearing: contact[:bearing],
          bearing_name: contact[:bearing].nil? ? nil : Geometry.facing_name(geometry, contact[:bearing]),
          arc: contact[:arc] ? "#{contact[:arc]}" : nil,
          identified: contact[:identified]
        }
        return base if !contact[:identified]

        base.merge(
          name: ship.name,
          faction: ship.faction,
          ship_class: ship.ship_class,
          facing: ship.facing.to_i,
          facing_name: ship.facing_name,
          silhouette: ship.silhouette,
          status: ship.status,
          shields: ship.sections.values.sum { |s| s["shields"].to_i },
          max_shields: ship.sections.values.sum { |s| (s["max_shields"] || 0).to_i },
          hull: ship.total_hull[:current],
          max_hull: ship.total_hull[:max]
        )
      end

      def self.terrain_payload(sector)
        Ships.sector_terrain(sector).map do |terr|
          {
            id: terr.id,
            type: terr.terrain_type,
            label: Sensors.terrain_label(terr.terrain_type),
            symbol: Sensors.terrain_symbol(terr.terrain_type),
            x: terr.pos[0],
            y: terr.pos[1],
            radius: terr.radius.to_i
          }
        end
      end

      # ---------------------------------------------------------------
      # The system map - the standard view of space
      # ---------------------------------------------------------------

      # Everything the browser needs to draw the orbital map. Positions
      # are computed here rather than in JavaScript: nothing in the
      # rules depends on where a planet is drawn, so a single
      # implementation beats keeping two in step.
      def self.system_map(system_key, viewer_ship = nil)
        data = Systems.system(system_key)
        return nil if !data

        Systems.settle_arrivals(system_key)

        layout = Systems.orbit_layout
        rings = (data["rings"] || 10).to_i
        size = Astro.canvas_size(rings, layout)
        center = size / 2.0

        ring_radii = (1..rings).map do |r|
          { ring: r, radius: Astro.ring_radius(r, layout) }
        end

        bodies = Systems.bodies(system_key).map do |b|
          body_map_entry(system_key, b, center, layout)
        end
        by_key = bodies.each_with_object({}) { |b, h| h[b[:key]] = b }

        {
          key: system_key,
          name: data["name"],
          description: data["description"],
          star: {
            name: data.dig("star", "name"),
            spectral: data.dig("star", "spectral"),
            radius: (data.dig("star", "radius") || 24).to_i,
            x: center,
            y: center
          },
          size: size,
          center: center,
          label_size: Astro.label_size(layout),
          rings: ring_radii,
          bodies: bodies,
          ships: system_ship_entries(system_key, by_key, center),
          legend: Systems.body_classes.map do |name, cfg|
            { key: name, label: cfg["label"] || name,
              fill: cfg["fill"], stroke: cfg["stroke"] }
          end,
          own_ship: viewer_ship ? ship_map_entry(viewer_ship, by_key, center) : nil
        }
      end

      def self.body_map_entry(system_key, body_data, center, layout)
        key = body_data["key"]
        angle = (body_data["angle"] || 0).to_f

        if body_data["parent"]
          # A moon's `angle` is around its PARENT, not the star - it is
          # not a second, independent bearing from the star. Getting this
          # wrong was a real bug: a moon at ring 3 with its own angle of
          # 210 while its parent sat at 62 rendered nowhere near its
          # parent, out past bodies on farther rings entirely by
          # coincidence of the numbers involved.
          #
          # So `ring`/`orbit_radius` here describe the moon's own small
          # orbit (radius = moon_orbit, around the parent's position),
          # not a radius from the star.
          parent_data = Systems.body(system_key, body_data["parent"]) || {}
          ring = Systems.effective_ring(system_key, parent_data)
          parent_radius = Astro.ring_radius(ring, layout)
          parent_angle = (parent_data["angle"] || 0).to_f
          parent_x, parent_y = Astro.position(center, center, parent_radius, parent_angle)

          orbit_radius = (body_data["moon_orbit"] || 18).to_f
          x, y = Astro.position(parent_x, parent_y, orbit_radius, angle)
        else
          ring = Systems.effective_ring(system_key, body_data)
          orbit_radius = Astro.ring_radius(ring, layout)
          x, y = Astro.position(center, center, orbit_radius, angle)
        end

        klass = Systems.body_class(body_data["classification"])
        faction = Systems.controlling_faction(system_key, body_data)
        engagement = Systems.engagement_at(system_key, key)

        {
          key: key,
          name: body_data["name"] || key,
          type: body_data["type"],
          classification: body_data["classification"],
          description: body_data["description"],
          callout: body_data["callout"],
          parent: body_data["parent"],
          ring: ring,
          angle: angle,
          orbit_radius: orbit_radius.round(2),
          x: x,
          y: y,
          size: Astro.body_radius(body_data["size"] || 6, layout),
          fill: klass["fill"],
          stroke: klass["stroke"],
          faction: faction,
          faction_color: Systems.faction_color(faction),
          is_belt: "#{body_data['type']}" == "belt",
          ships: Systems.ships_at(system_key, key).map { |s| s.name },
          engaged: !engagement.nil?,
          sector_id: engagement ? engagement[:sector].id : nil,
          round: engagement ? engagement[:combat].round.to_i : nil
        }
      end

      def self.system_ship_entries(system_key, bodies_by_key, center)
        Systems.system_ships(system_key).map do |ship|
          ship_map_entry(ship, bodies_by_key, center)
        end.compact
      end

      # A ship sits on its body, or partway along the line to wherever
      # it's going.
      def self.ship_map_entry(ship, bodies_by_key, center)
        origin = bodies_by_key[ship.location_key.to_s]
        entry = {
          id: ship.id,
          name: ship.name,
          faction: ship.faction,
          faction_color: Systems.faction_color(ship.faction),
          location: ship.location_key,
          location_name: origin ? origin[:name] : nil,
          in_transit: ship.in_transit?
        }

        if ship.in_transit?
          destination = bodies_by_key[ship.destination_key.to_s]
          from = origin ? [ origin[:x], origin[:y] ] : [ center, center ]
          to = destination ? [ destination[:x], destination[:y] ] : [ center, center ]
          fraction = Astro.progress(ship.departed_at, ship.travel_seconds.to_i)
          x, y = Astro.transit_position(from, to, fraction)

          entry.merge(
            x: x, y: y,
            from_x: from[0], from_y: from[1],
            to_x: to[0], to_y: to[1],
            destination: ship.destination_key,
            destination_name: destination ? destination[:name] : nil,
            progress: fraction.round(3),
            eta_seconds: ship.eta_seconds,
            eta: Astro.format_duration(ship.eta_seconds)
          )
        else
          return nil if !origin
          entry.merge(x: origin[:x], y: origin[:y])
        end
      end

      # The tactical plot.
      #
      # With a viewer ship, contacts are exactly what that hull's sensors
      # have resolved. Staff with no ship in the sector get the god view.
      def self.tactical(sector, viewer, is_admin = false)
        combat = Engagements.active_combat(sector)
        geometry = sector.geometry

        contacts =
          if viewer
            Sensors.contacts(viewer).map { |c| contact_payload(c, geometry) }
          elsif is_admin
            Ships.sector_ships(sector).reject { |s| s.destroyed? }.map do |ship|
              ship_detail(ship).merge(distance: nil, bearing: nil, arc: nil)
            end
          else
            []
          end

        {
          id: sector.id,
          name: sector.name,
          geometry: sector.geometry,
          width: sector.width.to_i,
          height: sector.height.to_i,
          facings: Geometry.facing_names(geometry),
          round: combat ? combat.round.to_i : nil,
          in_combat: !combat.nil?,
          last_report: combat ? combat.last_report : nil,
          is_admin: is_admin,
          gm_view: viewer.nil? && is_admin,
          own_ship: viewer ? ship_detail(viewer) : nil,
          contacts: contacts,
          terrain: terrain_payload(sector),
          awaiting_orders: is_admin ? Orders.ships_awaiting_orders(sector).map { |s| s.name } : []
        }
      end
    end
  end
end
