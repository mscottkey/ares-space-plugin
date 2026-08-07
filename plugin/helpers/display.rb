module AresMUSH
  module Space

    # Renders the sector as an instrument readout.
    #
    # Everything here is drawn from ONE ship's point of view - what that
    # hull's sensors have actually resolved - because that is what a crew
    # would be looking at.
    module Display

      SELF_SYMBOL = "@"
      UNKNOWN_SYMBOL = "?"
      EMPTY = "."

      # Hex sectors are stored in axial coordinates but drawn in offset
      # rows, which is what makes the staggered grid look right.
      def self.axial_for_display(row, col)
        [ col - ((row - (row & 1)) / 2), row ]
      end

      def self.display_for_axial(pos)
        q, r = pos
        [ r, q + ((r - (r & 1)) / 2) ]
      end

      def self.symbol_for(ship, contact_map, viewer)
        return SELF_SYMBOL if viewer && ship.id == viewer.id
        contact = contact_map[ship.id]
        return UNKNOWN_SYMBOL if contact && !contact[:identified]
        ship.name.to_s[0, 1].upcase
      end

      # The grid itself.
      def self.render_grid(sector, viewer = nil)
        geometry = sector.geometry
        hex = Geometry.hex?(geometry)
        width = sector.width.to_i
        height = sector.height.to_i

        terrain_list = Ships.sector_terrain(sector)
        visible = visible_ships(sector, viewer)
        contact_map = {}
        if viewer
          Sensors.contacts(viewer).each { |c| contact_map[c[:ship].id] = c }
        end

        occupied = {}
        visible.each do |ship|
          key = hex ? display_for_axial(ship.pos) : [ ship.pos[1], ship.pos[0] ]
          occupied[key] ||= []
          occupied[key] << ship
        end

        lines = []
        lines << header_row(width, hex)

        (0...height).each do |row|
          cells = (0...width).map do |col|
            pos = hex ? axial_for_display(row, col) : [ col, row ]
            ships_here = occupied[[ row, col ]] || []

            if ships_here.any?
              symbol_for(ships_here.first, contact_map, viewer)
            else
              terrain = Sensors.terrain_at(sector, pos, terrain_list).first
              terrain ? Sensors.terrain_symbol(terrain.terrain_type) : EMPTY
            end
          end

          indent = (hex && row.odd?) ? " " : ""
          lines << "#{row.to_s.rjust(2)} #{indent}#{cells.join(' ')}"
        end

        lines.join("\n")
      end

      def self.header_row(width, hex)
        labels = (0...width).map { |c| (c % 10).to_s }
        "   #{labels.join(' ')}"
      end

      # Ships the viewer can see. With no viewer (GM view) that's all of them.
      def self.visible_ships(sector, viewer)
        all = Ships.sector_ships(sector).select { |s| !s.destroyed? }
        return all if !viewer
        detected = Sensors.contacts(viewer).map { |c| c[:ship].id }
        all.select { |s| s.id == viewer.id || detected.include?(s.id) }
      end

      # The contact list beside the grid: bearing, range, aspect.
      def self.render_contacts(viewer)
        contacts = Sensors.contacts(viewer)
        return "  #{t('space.no_contacts')}" if contacts.empty?

        geometry = viewer.geometry
        contacts.map do |c|
          ship = c[:ship]
          bearing = c[:bearing].nil? ? "---" : Geometry.facing_name(geometry, c[:bearing])
          name = c[:identified] ? ship.name : t('space.unknown_contact')
          faction = c[:identified] ? ship.faction : "?"
          aspect = c[:arc] ? "#{c[:arc]}".upcase : "-"

          line = "  %xh#{name.to_s.ljust(16)}%xn #{faction.to_s.ljust(10)} " \
                 "brg #{bearing.to_s.ljust(3)} rng #{c[:distance].to_s.ljust(3)} #{aspect}"
          if c[:identified]
            line += " [#{hull_bar(ship)}]"
          end
          line
        end.join("\n")
      end

      # A compact hull/shield readout: shields then hull, as fractions.
      def self.hull_bar(ship)
        totals = ship.total_hull
        shields = ship.sections.values.sum { |s| s["shields"].to_i }
        max_shields = ship.sections.values.sum { |s| (s["max_shields"] || 0).to_i }
        "S #{shields}/#{max_shields} H #{totals[:current]}/#{totals[:max]}"
      end

      def self.render_sections(ship)
        ship.sections.map do |name, section|
          systems = (section["systems"] || [])
          status = section["hull"].to_i <= 0 ? "%xrDESTROYED%xn" : "operational"
          sys = systems.empty? ? "-" : systems.join(", ")
          sys = "%xr#{sys} (offline)%xn" if section["hull"].to_i <= 0

          "  %xh#{name.to_s.upcase.ljust(11)}%xn " \
          "shields #{section['shields'].to_i.to_s.rjust(2)}/#{(section['max_shields'] || 0).to_i.to_s.ljust(2)}  " \
          "hull #{section['hull'].to_i.to_s.rjust(2)}/#{(section['max_hull'] || 0).to_i.to_s.ljust(2)}  " \
          "#{status}  #{sys}"
        end.join("\n")
      end

      def self.render_hardpoints(ship)
        summary = Ships.hardpoint_summary(ship)
        return "  #{t('space.no_hardpoints')}" if summary.empty?

        summary.map do |hp|
          ammo = hp[:ammo].nil? ? "" : "  ammo #{hp[:ammo]}"
          "  [#{hp[:index]}] #{hp[:weapon].to_s.ljust(16)} #{hp[:arc].to_s.ljust(10)} " \
          "#{hp[:scale].to_s.ljust(8)} dmg #{hp[:damage]}  rng #{hp[:range]}#{ammo}"
        end.join("\n")
      end

      def self.render_stations(ship)
        stations = Crew.station_summary(ship)
        return "  #{t('space.no_stations')}" if stations.empty?

        stations.map do |s|
          order = s[:order] ? describe_order(s[:order], ship.geometry) : t('space.no_orders')
          "  %xh#{s[:station].to_s.ljust(12)}%xn #{s[:crew].to_s.ljust(20)} " \
          "#{s[:skill].to_s.ljust(14)} #{order}"
        end.join("\n")
      end

      # geometry is needed to name the stored facing index; without it a
      # pending order reads as "come to heading 4" instead of "S".
      def self.describe_order(order, geometry = "square")
        return "" if !order
        case order["action"]
        when "move"
          t('space.order_move',
            heading: Geometry.facing_name(geometry, order["heading"]),
            speed: order["speed"])
        when "evade" then t('space.order_evade')
        when "hold" then t('space.order_hold')
        when "repair" then t('space.order_repair', section: order["section"])
        when "sweep" then t('space.order_sweep')
        else "#{order['action']}"
        end
      end

      # The round report players actually read after a resolve.
      def self.render_report(report, geometry = "square")
        lines = []
        lines << "%xh--- #{t('space.round_header', round: report[:round], sector: report[:sector])} ---%xn"

        report[:sweeps].each do |s|
          lines << t('space.report_sweep', ship: s[:ship], roller: s[:roller],
                     successes: s[:successes], range: s[:range])
        end

        report[:evades].each do |e|
          lines << t('space.report_evade', ship: e[:ship], roller: e[:roller], margin: e[:margin])
        end

        report[:moves].each do |m|
          line = t('space.report_move', ship: m[:ship], facing: m[:facing],
                   speed: m[:speed], x: m[:to][0], y: m[:to][1])
          line += " #{t('space.turn_limited')}" if m[:turn_limited]
          line += " #{t('space.speed_limited')}" if m[:speed_limited]
          line += " #{t('space.move_blocked')}" if m[:blocked]
          lines << line
        end

        report[:attacks].each do |a|
          if a[:error]
            lines << "%xx#{t('space.report_attack_failed', attacker: a[:attacker], target: a[:target], reason: a[:error])}%xn"
          elsif !a[:hit]
            lines << t('space.report_miss', attacker: a[:attacker], weapon: a[:weapon],
                       target: a[:target], successes: a[:successes], evade: a[:evade])
          else
            line = "%xh" + t('space.report_hit', attacker: a[:attacker], weapon: a[:weapon],
                             target: a[:target], damage: a[:damage], section: a[:section]) + "%xn"
            line += " #{t('space.systems_only_note')}" if a[:systems_only]
            lines << line
            if a[:systems_lost] && a[:systems_lost].any?
              lines << "    %xr#{t('space.systems_lost', systems: a[:systems_lost].join(', '))}%xn"
            end
          end
        end

        report[:engineering].each do |e|
          lines << t('space.report_repair', ship: e[:ship], roller: e[:roller],
                     section: e[:section], amount: e[:repaired])
        end

        report[:destroyed].uniq.each do |name|
          lines << "%xr*** #{t('space.report_destroyed', ship: name)} ***%xn"
        end

        lines << "%xx#{t('space.no_activity')}%xn" if lines.count == 1
        lines.join("\n")
      end
    end
  end
end
