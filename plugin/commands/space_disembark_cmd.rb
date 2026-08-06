module AresMUSH
  module Space
    # space/disembark
    #
    # No arguments: looks at the room you're standing in rather than
    # asking which ship, since you can only be in one room - and
    # therefore aboard at most one ship - at a time.
    class SpaceDisembarkCmd
      include CommandHandler

      def handle
        ship = Boarding.ship_for_room(enactor.room)
        return client.emit_failure t('space.not_aboard', ship: t('space.deep_space')) if !ship

        result = Boarding.disembark(client, enactor, ship)
        return client.emit_failure result[:error] if result[:error]
        client.emit_success result[:message]
      end
    end
  end
end
