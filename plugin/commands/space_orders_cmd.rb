module AresMUSH
  module Space
    class SpaceOrdersCmd
      include CommandHandler

      def handle
        ship = Ships.ship_for_char(enactor)
        return client.emit_failure t('space.not_crewing') if !ship

        if ship.orders.empty?
          return client.emit_success t('space.no_orders_pending', ship: ship.name)
        end

        lines = [ t('space.orders_header', ship: ship.name) ]

        helm = Orders.get(ship, "helm")
        lines << "  helm:    #{Display.describe_order(helm, ship.geometry)}" if helm

        Orders.fire_orders(ship).each do |order|
          hp = Ships.hardpoint(ship, order["hardpoint"])
          weapon = hp ? hp["weapon"] : "?"
          lines << "  fire:    #{weapon} -> #{order['target']}"
        end

        eng = Orders.get(ship, "engineering")
        lines << "  engine:  #{Display.describe_order(eng, ship.geometry)}" if eng

        sensors = Orders.get(ship, "sensors")
        lines << "  sensors: #{Display.describe_order(sensors, ship.geometry)}" if sensors

        client.emit lines.join("\n")
      end
    end
  end
end
