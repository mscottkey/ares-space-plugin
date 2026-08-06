module AresMUSH
  module Space
    # space/board <ship>
    #
    # Open to any player, not staff-gated: walking into a ship's own
    # room isn't a privileged act, only sitting down at a station is
    # (see space/crew and the self-service claim commands). Explicit by
    # ship name for now - there's no notion yet of "the ship docked
    # here," so this can't just look at where you're standing the way
    # the eventual exit-based boarding will.
    class SpaceBoardCmd
      include CommandHandler

      attr_accessor :ship_name

      def parse_args
        self.ship_name = cmd.args
      end

      def required_args
        [ self.ship_name ]
      end

      def handle
        ship = Ships.find_ship(self.ship_name)
        return client.emit_failure t('space.ship_not_found', name: self.ship_name) if !ship

        result = Boarding.board(client, enactor, ship)
        return client.emit_failure result[:error] if result[:error]
        client.emit_success result[:message]
      end
    end
  end
end
