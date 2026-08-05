module AresMUSH
  module Space
    class SpaceHoldCmd
      include CommandHandler

      def handle
        ship = Ships.ship_for_char(enactor)
        return client.emit_failure t('space.not_crewing') if !ship

        Orders.set_hold(ship)
        client.emit_success t('space.hold_ordered', ship: ship.name)
      end
    end
  end
end
