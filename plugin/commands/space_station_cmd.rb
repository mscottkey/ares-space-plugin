module AresMUSH
  module Space
    # space/station <ship>=<system>/<body>
    # space/station <ship>=<system>/<ring>
    #
    # Places a ship at a body, or at a bare ring number for a ship
    # holding position with no body under it, without any travel time -
    # for setup, or when a GM needs to move something. A bare integer
    # target means a ring (see Systems.parse_ring); anything else is
    # looked up as a body name/key.
    class SpaceStationCmd
      include CommandHandler

      attr_accessor :ship_name, :system_name, :body_name

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2_slash_optional_arg3)
        self.ship_name = args.arg1
        self.system_name = args.arg2
        self.body_name = args.arg3
      end

      def required_args
        [ self.ship_name, self.system_name ]
      end

      def check_admin
        return t('dispatcher.not_allowed') if !enactor.is_admin?
        return nil
      end

      def handle
        ship = Ships.find_ship(self.ship_name)
        return client.emit_failure t('space.ship_not_found', name: self.ship_name) if !ship

        # One argument means a body in the default system - see
        # Systems.place for the shared resolution/placement logic
        # (also used by space/spawn's optional trailing placement).
        result = Systems.place(ship, self.system_name, self.body_name)
        return client.emit_failure result[:error] if result[:error]
        client.emit_success result[:message]
      end
    end
  end
end
