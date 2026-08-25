module AresMUSH
  module Space
    # space/spawn <sector>/<class>=<name>
    # space/spawn <sector>/<class>=<name>/<body>            (default system)
    # space/spawn <sector>/<class>=<name>/<system>/<body>   (named system)
    #
    # The trailing placement is optional and mirrors space/station's own
    # <system>/<body> shape (see Systems.place). Without it a spawned
    # ship has only a tactical position - invisible to the system map,
    # and unable to space/travel until a GM separately runs
    # space/station - which is easy to forget and worth being able to
    # do in one command.
    class SpaceSpawnCmd
      include CommandHandler

      attr_accessor :sector_name, :class_name, :ship_name, :system_name, :body_name

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_slash_arg2_equals_arg3)
        self.sector_name = args.arg1
        self.class_name = args.arg2

        parts = "#{args.arg3}".split("/")
        self.ship_name = titlecase_arg(parts[0])
        self.system_name = parts[1]
        self.body_name = parts[2]
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

        message = t('space.ship_spawned',
          name: ship.name, ship_class: ship.ship_class, sector: sector.name,
          x: ship.pos[0], y: ship.pos[1])

        if !self.system_name.to_s.empty?
          placed = Systems.place(ship, self.system_name, self.body_name)
          message += " " + (placed[:error] ? t('space.spawn_placement_failed', reason: placed[:error])
                                            : placed[:message])
        end

        client.emit_success message
      end
    end
  end
end
