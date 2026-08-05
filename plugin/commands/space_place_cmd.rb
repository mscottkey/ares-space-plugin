module AresMUSH
  module Space
    # space/place <ship>=<x,y>/<facing>
    class SpacePlaceCmd
      include CommandHandler

      attr_accessor :ship_name, :coords, :facing

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2_slash_optional_arg3)
        self.ship_name = args.arg1
        self.coords = args.arg2
        self.facing = args.arg3
      end

      def required_args
        [ self.ship_name, self.coords ]
      end

      def check_admin
        return t('dispatcher.not_allowed') if !enactor.is_admin?
        return nil
      end

      def handle
        ship = Ships.find_ship(self.ship_name)
        return client.emit_failure t('space.ship_not_found', name: self.ship_name) if !ship
        return client.emit_failure t('space.bad_coords') if !(self.coords =~ /\A-?\d+\s*,\s*-?\d+\z/)

        x, y = self.coords.split(',').map { |c| c.strip.to_i }

        facing = nil
        if self.facing
          facing = Geometry.parse_facing(ship.geometry, self.facing)
          if facing.nil?
            return client.emit_failure t('space.bad_heading',
              heading: self.facing,
              valid: Geometry.facing_names(ship.geometry).join(', '))
          end
        end

        Ships.place(ship, x, y, facing)
        client.emit_success t('space.ship_placed',
          name: ship.name, x: ship.pos[0], y: ship.pos[1], facing: ship.facing_name)
      end
    end
  end
end
