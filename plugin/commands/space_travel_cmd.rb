module AresMUSH
  module Space
    # space/travel <body>
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
