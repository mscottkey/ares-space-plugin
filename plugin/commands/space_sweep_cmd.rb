module AresMUSH
  module Space
    # An active sensor sweep - a Sensors roll that pushes detection range
    # out for the round. Resolves with everything else.
    class SpaceSweepCmd
      include CommandHandler

      def handle
        ship = Ships.ship_for_char(enactor)
        return client.emit_failure t('space.not_crewing') if !ship
        return client.emit_failure t('space.ship_destroyed_order') if !ship.active?

        Orders.set_sweep(ship)
        client.emit_success t('space.sweep_ordered', ship: ship.name)
      end
    end
  end
end
