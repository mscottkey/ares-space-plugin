module AresMUSH
  module Space
    # space/helm <heading>=<speed>
    class SpaceHelmCmd
      include CommandHandler

      attr_accessor :heading, :speed

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_optional_arg2)
        self.heading = args.arg1
        self.speed = args.arg2
      end

      def required_args
        [ self.heading ]
      end

      def handle
        ship = Ships.ship_for_char(enactor)
        return client.emit_failure t('space.not_crewing') if !ship
        return client.emit_failure t('space.ship_destroyed_order') if !ship.active?

        facing = Geometry.parse_facing(ship.geometry, self.heading)
        if facing.nil?
          return client.emit_failure t('space.bad_heading',
            heading: self.heading,
            valid: Geometry.facing_names(ship.geometry).join(', '))
        end

        requested_speed = self.speed ? self.speed.to_i : ship.max_speed
        max = Resolver.effective_max_speed(ship)
        if requested_speed > max
          client.emit_ooc t('space.speed_capped', requested: requested_speed, max: max)
          requested_speed = max
        end
        requested_speed = 0 if requested_speed < 0

        Orders.set_move(ship, facing, requested_speed)

        turn = Geometry.turn_cost(ship.geometry, ship.facing, facing)
        if turn > ship.agility
          client.emit_ooc t('space.turn_will_be_limited', agility: ship.agility, needed: turn)
        end

        client.emit_success t('space.helm_ordered',
          ship: ship.name,
          heading: Geometry.facing_name(ship.geometry, facing),
          speed: requested_speed)
      end
    end
  end
end
