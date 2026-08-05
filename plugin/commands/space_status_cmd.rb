module AresMUSH
  module Space
    class SpaceStatusCmd
      include CommandHandler

      attr_accessor :ship_name

      def parse_args
        self.ship_name = cmd.args
      end

      def handle
        ship = if self.ship_name
          Ships.find_ship(self.ship_name)
        else
          Ships.ship_for_char(enactor)
        end

        if !ship
          return client.emit_failure self.ship_name ?
            t('space.ship_not_found', name: self.ship_name) : t('space.not_crewing')
        end

        client.emit ShipStatusTemplate.new(ship).render
      end
    end
  end
end
