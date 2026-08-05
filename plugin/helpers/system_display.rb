module AresMUSH
  module Space

    # The system view in telnet.
    #
    # An orbital map drawn in ASCII circles would be unreadable, so this
    # is a manifest instead: rings outward, what's on each, who holds it,
    # and where the shooting is. The browser gets the picture; both read
    # the same state.
    module SystemDisplay

      def self.render(system_key, viewer_ship = nil)
        data = Systems.system(system_key)
        return t('space.no_such_system', name: system_key) if !data

        Systems.settle_arrivals(system_key)

        lines = []
        lines << "%xh#{data['name']}%xn %xk(#{data.dig('star', 'name')}, #{data.dig('star', 'spectral')}-class)%xn"
        lines << ""

        if viewer_ship
          lines << own_ship_line(system_key, viewer_ship)
          lines << ""
        end

        lines << "%xh RING  BODY                 CLASS           CONTROL     PRESENT%xn"

        sorted = Systems.bodies(system_key).sort_by { |b| Systems.effective_ring(system_key, b) }
        sorted.each { |b| lines << body_line(system_key, b, viewer_ship) }

        under_way = Systems.system_ships(system_key).select { |s| s.in_transit? }
        if under_way.any?
          lines << ""
          lines << "%xhUNDER WAY%xn"
          under_way.each { |s| lines << transit_line(system_key, s) }
        end

        lines.join("\n")
      end

      def self.body_line(system_key, body_data, viewer_ship)
        key = body_data["key"]
        ring = Systems.effective_ring(system_key, body_data)
        name = body_data["name"] || key
        name = "  #{name}" if body_data["parent"]   # indent moons

        faction = Systems.controlling_faction(system_key, body_data)
        klass = body_data["classification"].to_s

        present = Systems.ships_at(system_key, key)
        present_str = present.empty? ? "-" : present.map { |s| s.name }.join(", ")

        marker = " "
        marker = "%xh>%xn" if viewer_ship && viewer_ship.location_key.to_s == key.to_s

        engagement = Systems.engagement_at(system_key, key)
        line = "#{marker}#{ring.to_s.rjust(4)}  #{name.to_s.ljust(20)} " \
               "#{klass.ljust(15)} #{faction.to_s.ljust(11)} #{present_str}"
        line += " %xr[ENGAGED r#{engagement[:combat].round}]%xn" if engagement
        line
      end

      def self.own_ship_line(system_key, ship)
        if ship.in_transit?
          t('space.own_transit_line',
            ship: ship.name,
            destination: Systems.body_name(system_key, ship.destination_key) || ship.destination_key,
            eta: Astro.format_duration(ship.eta_seconds))
        else
          where = Systems.body_name(system_key, ship.location_key) || t('space.deep_space')
          t('space.own_location_line', ship: ship.name, location: where)
        end
      end

      def self.transit_line(system_key, ship)
        "  #{ship.name.to_s.ljust(18)} -> " \
        "#{(Systems.body_name(system_key, ship.destination_key) || '?').to_s.ljust(20)} " \
        "ETA #{Astro.format_duration(ship.eta_seconds)}"
      end
    end
  end
end
