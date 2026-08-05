module AresMUSH
  module Space
    class SpaceClearCmd
      include CommandHandler

      def handle
        ship = Ships.ship_for_char(enactor)
        return client.emit_failure t('space.not_crewing') if !ship

        Space.emit_order_result(client, Orders.issue(ship, :clear))
      end
    end
  end
end
