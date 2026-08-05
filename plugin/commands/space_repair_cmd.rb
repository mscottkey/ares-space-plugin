module AresMUSH
  module Space
    # space/repair <section>
    class SpaceRepairCmd
      include CommandHandler

      attr_accessor :section

      def parse_args
        self.section = downcase_arg(cmd.args)
      end

      def required_args
        [ self.section ]
      end

      def handle
        ship = Ships.ship_for_char(enactor)
        return client.emit_failure t('space.not_crewing') if !ship
        return client.emit_failure t('space.ship_destroyed_order') if !ship.active?

        if !ship.sections.key?(self.section)
          return client.emit_failure t('space.no_such_section',
            section: self.section, valid: ship.sections.keys.join(', '))
        end

        Orders.set_repair(ship, self.section)
        client.emit_success t('space.repair_ordered', section: self.section, ship: ship.name)
      end
    end
  end
end
