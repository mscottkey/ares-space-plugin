module AresMUSH
  module Space
    # space/leave <station>
    #
    # The inverse of space/take - steps away from a station you hold.
    # Refuses if it isn't yours; that's space/crew's job, and only for
    # staff or the ship's owner.
    class SpaceLeaveCmd
      include CommandHandler

      attr_accessor :station

      def parse_args
        self.station = downcase_arg(cmd.args)
      end

      def required_args
        [ self.station ]
      end

      def handle
        ship = enactor.current_ship
        return client.emit_failure t('space.not_boarded') if !ship

        result = Crew.release(enactor, ship, self.station)
        return client.emit_failure result[:error] if result[:error]
        client.emit_success result[:message]
      end
    end
  end
end
