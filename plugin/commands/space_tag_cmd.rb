module AresMUSH
  module Space
    # space/tag
    #
    # Run while standing in a room built out behind a ship's entry_room,
    # this adds it to the set a character can run ship commands from.
    # No argument and no room name: the room you're standing in is the
    # room being tagged, the same "stand there and run it" shape as
    # other room-scoped commands elsewhere in Ares.
    class SpaceTagCmd
      include CommandHandler

      def check_can_tag
        ship = enactor.current_ship
        return t('space.not_boarded') if !ship
        return nil if enactor.is_admin?
        return nil if ship.owner && ship.owner.id.to_s == enactor.id.to_s
        t('space.not_ship_owner', ship: ship.name)
      end

      def handle
        ship = enactor.current_ship
        result = Boarding.tag_room(ship, enactor.room)
        return client.emit_failure result[:error] if result[:error]
        client.emit_success result[:message]
      end
    end
  end
end
