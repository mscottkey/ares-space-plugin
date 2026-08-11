module AresMUSH
  module Space
    # space/travel <body>
    # space/travel <ring>
    #
    # A bare integer destination means a ring, not a body - Systems.
    # set_course resolves which (see Systems.parse_ring). Lets a player
    # course for open space, not just a planet - holding position
    # between worlds, or heading somewhere no body has been built yet.
    class SpaceTravelCmd
      include CommandHandler

      attr_accessor :destination

      def parse_args
        self.destination = cmd.args
      end

      def required_args
        [ self.destination ]
      end

      def handle
        ship = Ships.ship_for_char(enactor)
        return client.emit_failure t('space.not_crewing') if !ship
        return client.emit_failure t('space.ship_destroyed_order') if !ship.active?

        result = Systems.set_course(ship, self.destination)
        return client.emit_failure result[:error] if result[:error]
        client.emit_success result[:message]
      end
    end
  end
end
