module AresMUSH
  module Space
    class TacticalTemplate < ErbTemplateRenderer
      attr_accessor :sector, :viewer

      # viewer is the ship whose sensors we are reading. Nil means the
      # GM's god-view of the whole sector.
      def initialize(sector, viewer = nil)
        self.sector = sector
        self.viewer = viewer
        super File.dirname(__FILE__) + "/tactical_template.erb"
      end

      def grid
        Display.render_grid(sector, viewer)
      end

      def contacts
        return t('space.gm_view_no_contacts') if !viewer
        Display.render_contacts(viewer)
      end

      def geometry_label
        Geometry.hex?(sector.geometry) ? "hex" : "square"
      end

      def own_line
        return t('space.no_viewer_ship') if !viewer
        t('space.own_status',
          name: viewer.name,
          facing: viewer.facing_name,
          speed: viewer.speed.to_i,
          x: viewer.pos[0],
          y: viewer.pos[1],
          hull: Display.hull_bar(viewer))
      end
    end
  end
end
