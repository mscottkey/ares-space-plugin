module AresMUSH
  module Space
    # space/station <ship>=<system>/<body>
    # space/station <ship>=<system>/<ring>
    #
    # Places a ship at a body, or at a bare ring number for a ship
    # holding position with no body under it, without any travel time -
    # for setup, or when a GM needs to move something. A bare integer
    # target means a ring (see Systems.parse_ring); anything else is
    # looked up as a body name/key.
    class SpaceStationCmd
      include CommandHandler

      attr_accessor :ship_name, :system_name, :body_name

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2_slash_optional_arg3)
        self.ship_name = args.arg1
        self.system_name = args.arg2
        self.body_name = args.arg3
      end

      def required_args
        [ self.ship_name, self.system_name ]
      end

      def check_admin
        return t('dispatcher.not_allowed') if !enactor.is_admin?
        return nil
      end

      def handle
        ship = Ships.find_ship(self.ship_name)
        return client.emit_failure t('space.ship_not_found', name: self.ship_name) if !ship

        # One argument means a body in the default system.
        if self.body_name.to_s.empty?
          key = Systems.default_system_key
          wanted_body = self.system_name
        else
          key = Systems.find_system_key(self.system_name)
          wanted_body = self.body_name
        end

        return client.emit_failure t('space.no_such_system', name: self.system_name) if !key

        # A direct GM placement is authoritative: it always leaves the
        # ship with an independent position, even if it was hangared
        # (or, worst case, self-hangared - see Docking.land) beforehand.
        # Without clearing carrier here, Docking.dock below would still
        # route through hangar_room_for(ship.carrier) and ignore the
        # system_key/location_key/system_ring just set.
        ring = Systems.parse_ring(wanted_body)
        if ring
          ship.update(system_key: "#{key}", location_key: nil,
                      system_ring: ring, system_angle: Systems.ring_angle_for(ship),
                      destination_key: nil, departed_at: nil, travel_seconds: 0,
                      carrier: nil)
          Docking.dock(ship)

          return client.emit_success t('space.ship_stationed_ring',
            name: ship.name, ring: ring, system: Systems.system(key)["name"])
        end

        body = Systems.body(key, wanted_body)
        return client.emit_failure t('space.no_such_body', name: wanted_body) if !body

        ship.update(system_key: "#{key}", location_key: body["key"],
                    system_ring: nil, system_angle: nil,
                    destination_key: nil, departed_at: nil, travel_seconds: 0,
                    carrier: nil)
        Docking.dock(ship)

        client.emit_success t('space.ship_stationed',
          name: ship.name, body: body["name"] || body["key"],
          system: Systems.system(key)["name"])
      end
    end
  end
end
