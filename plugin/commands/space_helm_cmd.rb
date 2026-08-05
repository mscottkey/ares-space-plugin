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

        result = Orders.issue(ship, :helm, heading: self.heading, speed: self.speed)
        Space.emit_order_result(client, result)
      end
    end
  end
end
