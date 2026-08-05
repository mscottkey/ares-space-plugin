module AresMUSH
  module Space
    # space/fire <target>=<hardpoint index>
    class SpaceFireCmd
      include CommandHandler

      attr_accessor :target_name, :hardpoint

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_optional_arg2)
        self.target_name = args.arg1
        self.hardpoint = args.arg2
      end

      def required_args
        [ self.target_name ]
      end

      def handle
        ship = Ships.ship_for_char(enactor)
        return client.emit_failure t('space.not_crewing') if !ship
        return client.emit_failure t('space.ship_destroyed_order') if !ship.active?

        target = Ships.find_ship_in_sector(ship.sector, self.target_name)
        return client.emit_failure t('space.target_not_found', name: self.target_name) if !target

        index = self.hardpoint ? self.hardpoint.to_i : 0
        error = Orders.validate_fire(ship, target, index)
        return client.emit_failure error if error

        hp = Ships.hardpoint(ship, index)
        firing_arc = Geometry.arc(ship.geometry, ship.pos, ship.facing, target.pos,
                                  SpaceConfig.arc_diagonal_bias)
        if "#{firing_arc}" != "#{hp['arc']}"
          client.emit_ooc t('space.arc_warning',
            weapon: hp["weapon"], arc: hp["arc"], actual: firing_arc || "none")
        end

        Orders.add_fire(ship, target.name, index)
        client.emit_success t('space.fire_ordered',
          weapon: hp["weapon"], target: target.name)
      end
    end
  end
end
