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

        Space.emit_order_result(client, Orders.issue(ship, :repair, section: self.section))
      end
    end
  end
end
