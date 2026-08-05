module AresMUSH
  module Space
    # The standard view of space. Available to anyone, any time - you do
    # not need to be crewing a ship or have a fight running.
    class SpaceSystemCmd
      include CommandHandler

      attr_accessor :system_name

      def parse_args
        self.system_name = cmd.args
      end

      def handle
        ship = Ships.ship_for_char(enactor)

        key = if self.system_name
          Systems.find_system_key(self.system_name)
        else
          (ship && !ship.system_key.to_s.empty?) ? ship.system_key : Systems.default_system_key
        end

        if !key
          return client.emit_failure self.system_name ?
            t('space.no_such_system', name: self.system_name) : t('space.no_systems')
        end

        viewer = (ship && ship.system_key.to_s == key.to_s) ? ship : nil
        client.emit SystemDisplay.render(key, viewer)
      end
    end
  end
end
