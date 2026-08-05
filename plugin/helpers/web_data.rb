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
