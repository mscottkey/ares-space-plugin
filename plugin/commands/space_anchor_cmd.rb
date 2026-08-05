module AresMUSH
  module Space
    # space/anchor <sector>=<body>
    #
    # Ties a tactical grid to a place in the system, so the system map
    # can show that there's a fight going on there.
    class SpaceAnchorCmd
      include CommandHandler

      attr_accessor :sector_name, :body_name

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)
        self.sector_name = args.arg1
        self.body_name = args.arg2
      end

      def required_args
        [ self.sector_name, self.body_name ]
      end

      def check_admin
        return t('dispatcher.not_allowed') if !enactor.is_admin?
        return nil
      end

      def handle
        sector = SpaceSector.find_one_by_name(self.sector_name)
        return client.emit_failure t('space.sector_not_found', name: self.sector_name) if !sector

        key = Systems.default_system_key
        body = Systems.body(key, self.body_name)
        return client.emit_failure t('space.no_such_body', name: self.body_name) if !body

        Systems.anchor(sector, key, body["key"])
        client.emit_success t('space.sector_anchored',
          sector: sector.name, body: body["name"] || body["key"])
      end
    end
  end
end
