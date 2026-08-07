module AresMUSH
  module Space
    # space/dock <body>
    #
    # Run while standing in the room that should serve as a body's
    # landing point. Staff only - this is world-building (deciding a
    # planet has a spaceport at all), not something a ship's owner needs;
    # an owner controls their ship, not the body it happens to be parked
    # at.
    class SpaceDockCmd
      include CommandHandler

      attr_accessor :body_name

      def parse_args
        self.body_name = cmd.args
      end

      def required_args
        [ self.body_name ]
      end

      def check_admin
        return t('dispatcher.not_allowed') if !enactor.is_admin?
        return nil
      end

      def handle
        return client.emit_failure t('space.no_room') if !enactor.room

        ship = Ships.ship_for_char(enactor)
        key = (ship && !ship.system_key.to_s.empty?) ? ship.system_key : Systems.default_system_key

        body = Systems.body(key, self.body_name)
        return client.emit_failure t('space.no_such_body', name: self.body_name) if !body

        Systems.set_landing_room(key, body["key"], enactor.room)

        # Retroactive: a ship already sitting here gets a door too, not
        # just the next one to arrive.
        Systems.ships_at(key, body["key"]).each { |s| Docking.dock(s) }

        client.emit_success t('space.body_docked',
          name: body["name"] || body["key"], room: enactor.room.name)
      end
    end
  end
end
