module AresMUSH
  module Space
    # space/take <station>
    #
    # Self-service - claims an open station on your current ship (see
    # Character.current_ship). Only works on a station nobody's in;
    # bumping someone already seated needs space/crew, which only staff
    # or the ship's owner can run.
    class SpaceTakeCmd
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

        result = Crew.claim(enactor, ship, self.station)
        return client.emit_failure result[:error] if result[:error]
        client.emit_success result[:message]
      end
    end
  end
end
