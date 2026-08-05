module AresMUSH
  module Space
    # space/sector <name>=<geometry> <width>x<height>
    # e.g. space/sector Concord Graveyard=hex 20x20
    class SpaceSectorCmd
      include CommandHandler

      attr_accessor :name, :options

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_optional_arg2)
        self.name = titlecase_arg(args.arg1)
        self.options = downcase_arg(args.arg2 || "")
      end

      def required_args
        [ self.name ]
      end

      def check_admin
        return t('dispatcher.not_allowed') if !enactor.is_admin?
        return nil
      end

      def handle
        return client.emit_failure t('space.sector_name_taken', name: self.name) if SpaceSector.find_one_by_name(self.name)

        geometry = self.options.include?("hex") ? "hex" : SpaceConfig.default_geometry
        width, height = parse_size(self.options)

        sector = SpaceSector.create(
          name: self.name,
          geometry: geometry,
          width: width,
          height: height
        )

        client.emit_success t('space.sector_created',
          name: sector.name, geometry: geometry, width: width, height: height)
      end

      def parse_size(options)
        match = options.match(/(\d+)\s*x\s*(\d+)/)
        return [ 20, 20 ] if !match
        [ [ match[1].to_i, 1 ].max, [ match[2].to_i, 1 ].max ]
      end
    end
  end
end
