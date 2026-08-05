module AresMUSH
  module Space
    # Defensive flying. Banks a Piloting roll as this round's defense
    # against every incoming shot, at the cost of going nowhere.
    class SpaceEvadeCmd
      include CommandHandler

      def handle
        ship = Ships.ship_for_char(enactor)
        return client.emit_failure t('space.not_crewing') if !ship
        return client.emit_failure t('space.ship_destroyed_order') if !ship.active?

        Orders.set_evade(ship)
        client.emit_success t('space.evade_ordered', ship: ship.name)
      end
    end
  end
end
