module AresMUSH
  module Space
    # space/crew <ship>/<station>=<character name, npc:N, or "none">
    class SpaceCrewCmd
      include CommandHandler

      attr_accessor :ship_name, :station, :crew

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_slash_arg2_equals_arg3)
        self.ship_name = args.arg1
        self.station = downcase_arg(args.arg2)
        self.crew = args.arg3
      end

      def required_args
        [ self.ship_name, self.station, self.crew ]
      end

      def check_admin
        return t('dispatcher.not_allowed') if !enactor.is_admin?
        return nil
      end

      def handle
        ship = Ships.find_ship(self.ship_name)
        return client.emit_failure t('space.ship_not_found', name: self.ship_name) if !ship

        if !Crew.valid_station?(ship, self.station)
          return client.emit_failure t('space.no_such_station',
            station: self.station,
            valid: (ship.class_data["stations"] || []).join(', '))
        end

        if self.crew.downcase == "none"
          Crew.unassign(ship, self.station)
          return client.emit_success t('space.station_cleared', station: self.station, ship: ship.name)
        end

        if self.crew.downcase.start_with?("npc:")
          rating = self.crew.after(":").to_i
          Crew.assign(ship, self.station, Crew.npc_key(rating))
          return client.emit_success t('space.station_npc_assigned',
            station: self.station, ship: ship.name, rating: rating)
        end

        char = Character.find_one_by_name(self.crew)
        return client.emit_failure t('db.object_not_found') if !char

        Crew.assign(ship, self.station, Crew.char_key(char))
        client.emit_success t('space.station_assigned',
          name: char.name, station: self.station, ship: ship.name)
      end
    end
  end
end
