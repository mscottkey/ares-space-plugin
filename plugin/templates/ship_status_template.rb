module AresMUSH
  module Space
    class ShipStatusTemplate < ErbTemplateRenderer
      attr_accessor :ship

      def initialize(ship)
        self.ship = ship
        super File.dirname(__FILE__) + "/ship_status_template.erb"
      end

      def sections
        Display.render_sections(ship)
      end

      def hardpoints
        Display.render_hardpoints(ship)
      end

      def stations
        Display.render_stations(ship)
      end

      def class_line
        data = ship.class_data
        t('space.class_line',
          ship_class: ship.ship_class,
          silhouette: ship.silhouette,
          speed: ship.max_speed,
          agility: ship.agility,
          description: data["description"] || "")
      end

      def position_line
        t('space.position_line',
          sector: ship.sector ? ship.sector.name : "-",
          x: ship.pos[0],
          y: ship.pos[1],
          facing: ship.facing_name,
          speed: ship.speed.to_i)
      end

      def status_line
        offline = ship.systems_offline
        return t('space.all_systems_nominal') if offline.empty?
        t('space.systems_offline_line', systems: offline.join(', '))
      end

      def strain_line
        Display.strain_bar(ship)
      end
    end
  end
end
