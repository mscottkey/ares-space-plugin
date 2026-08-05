module AresMUSH
  module Space
    # space/spawn <sector>/<class>=<name>
    class SpaceSpawnCmd
      include CommandHandler

      attr_accessor :sector_name, :class_name, :ship_name

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_slash_arg2_equals_arg3)
        self.sector_name = args.arg1
        self.class_name = args.arg2
        self.ship_name = titlecase_arg(args.arg3)
      end

      def required_args
        [ self.sector_name, self.class_name, self.ship_name ]
      end

      def check_admin
        return t('dispatcher.not_allowed') if !enactor.is_admin?
        return nil
      end

      def handle
        sector = SpaceSector.find_one_by_name(self.sector_name)
        return client.emit_failure t('space.sector_not_found', name: self.sector_name) if !sector

        ship, error = Ships.spawn(sector, self.class_name, self.ship_name)
        return client.emit_failure error if error

        client.emit_success t('space.ship_spawned',
          name: ship.name, ship_class: ship.ship_class, sector: sector.name,
          x: ship.pos[0], y: ship.pos[1])
      end
    end
  end
end
