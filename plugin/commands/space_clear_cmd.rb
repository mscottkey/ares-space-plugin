module AresMUSH
  module Space
    class SpaceClearCmd
      include CommandHandler

      def handle
        ship = Ships.ship_for_char(enactor)
        return client.emit_failure t('space.not_crewing') if !ship

        Orders.clear(ship)
        client.emit_success t('space.orders_cleared', ship: ship.name)
      end
    end
  end
end
