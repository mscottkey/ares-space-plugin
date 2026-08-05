module AresMUSH
  module Space
    # space/claim <body>=<faction>
    class SpaceClaimCmd
      include CommandHandler

      attr_accessor :body_name, :faction

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)
        self.body_name = args.arg1
        self.faction = args.arg2
      end

      def required_args
        [ self.body_name, self.faction ]
      end

      def check_admin
        return t('dispatcher.not_allowed') if !enactor.is_admin?
        return nil
      end

      def handle
        key = Systems.default_system_key
        ship = Ships.ship_for_char(enactor)
        key = ship.system_key if ship && !ship.system_key.to_s.empty?

        body = Systems.body(key, self.body_name)
        return client.emit_failure t('space.no_such_body', name: self.body_name) if !body

        Systems.claim(key, body["key"], self.faction)
        client.emit_success t('space.body_claimed',
          name: body["name"] || body["key"], faction: self.faction)
      end
    end
  end
end
