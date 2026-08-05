module AresMUSH
  module Space
    # space/remove <ship>
    class SpaceRemoveCmd
      include CommandHandler

      attr_accessor :ship_name

      def parse_args
        self.ship_name = cmd.args
      end

      def required_args
        [ self.ship_name ]
      end

      def check_admin
        return t('dispatcher.not_allowed') if !enactor.is_admin?
        return nil
      end

      def handle
        ship = Ships.find_ship(self.ship_name)
        return client.emit_failure t('space.ship_not_found', name: self.ship_name) if !ship

        name = ship.name
        ship.delete
        client.emit_success t('space.ship_removed', name: name)
      end
    end
  end
end
