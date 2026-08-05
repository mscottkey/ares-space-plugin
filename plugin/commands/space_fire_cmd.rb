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

        result = Orders.issue(ship, :fire,
          target: self.target_name, hardpoint: self.hardpoint)
        Space.emit_order_result(client, result)
      end
    end
  end
end
