module AresMUSH
  module Space
    # Defensive flying. Banks a Piloting roll as this round's defense
    # against every incoming shot, at the cost of going nowhere.
    class SpaceEvadeCmd
      include CommandHandler

      def handle
        ship = Ships.ship_for_char(enactor)
        return client.emit_failure t('space.not_crewing') if !ship

        Space.emit_order_result(client, Orders.issue(ship, :evade))
      end
    end
  end
end
