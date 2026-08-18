module AresMUSH
  module Space
    # space/vent - bleed off system strain through damage control.
    class SpaceVentCmd
      include CommandHandler

      def handle
        ship = Ships.ship_for_char(enactor)
        return client.emit_failure t('space.not_crewing') if !ship

        Space.emit_order_result(client, Orders.issue(ship, :vent))
      end
    end
  end
end
