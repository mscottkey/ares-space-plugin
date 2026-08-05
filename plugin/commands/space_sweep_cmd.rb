module AresMUSH
  module Space
    # An active sensor sweep - a Sensors roll that pushes detection range
    # out for the round. Resolves with everything else.
    class SpaceSweepCmd
      include CommandHandler

      def handle
        ship = Ships.ship_for_char(enactor)
        return client.emit_failure t('space.not_crewing') if !ship

        Space.emit_order_result(client, Orders.issue(ship, :sweep))
      end
    end
  end
end
