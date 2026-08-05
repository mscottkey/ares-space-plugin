module AresMUSH
  module Space
    # space/terrain <sector>/<type>=<x,y>/<radius>
    class SpaceTerrainCmd
      include CommandHandler

      attr_accessor :sector_name, :terrain_type, :coords, :radius

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_slash_arg2_equals_arg3)
        self.sector_name = args.arg1
        self.terrain_type = downcase_arg(args.arg2)
        rest = "#{args.arg3}".split('/')
        self.coords = rest[0].to_s.strip
        self.radius = rest[1].to_s.strip
      end

      def required_args
        [ self.sector_name, self.terrain_type, self.coords ]
      end

      def check_admin
        return t('dispatcher.not_allowed') if !enactor.is_admin?
        return nil
      end

      def handle
        sector = SpaceSector.find_one_by_name(self.sector_name)
        return client.emit_failure t('space.sector_not_found', name: self.sector_name) if !sector

        types = Global.read_config("space", "terrain_types") || {}
        if !types.key?(self.terrain_type)
          return client.emit_failure t('space.unknown_terrain',
            type: self.terrain_type, valid: types.keys.join(', '))
        end

        return client.emit_failure t('space.bad_coords') if !(self.coords =~ /\A-?\d+\s*,\s*-?\d+\z/)
        x, y = self.coords.split(',').map { |c| c.strip.to_i }

        SpaceTerrain.create(
          sector: sector,
          terrain_type: self.terrain_type,
          name: Sensors.terrain_label(self.terrain_type),
          x: x,
          y: y,
          radius: self.radius.to_s.empty? ? 0 : self.radius.to_i
        )

        client.emit_success t('space.terrain_added',
          type: Sensors.terrain_label(self.terrain_type),
          sector: sector.name, x: x, y: y)
      end
    end
  end
end
