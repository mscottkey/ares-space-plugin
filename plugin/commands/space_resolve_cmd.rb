module AresMUSH
  module Space
    # space/resolve <sector>
    #
    # The GM pulls the trigger for the POC. The resolver itself does not
    # care who calls it, so an auto-resolve trigger or a scheduled tick
    # can drive the same code later without touching the rules.
    class SpaceResolveCmd
      include CommandHandler

      attr_accessor :sector_name

      def parse_args
        self.sector_name = cmd.args
      end

      def required_args
        [ self.sector_name ]
      end

      def check_admin
        return t('dispatcher.not_allowed') if !enactor.is_admin?
        return nil
      end

      def handle
        sector = SpaceSector.find_one_by_name(self.sector_name)
        return client.emit_failure t('space.sector_not_found', name: self.sector_name) if !sector

        combat = Engagements.active_combat(sector)
        return client.emit_failure t('space.no_active_combat', sector: sector.name) if !combat

        waiting = Orders.ships_awaiting_orders(sector)
        if waiting.any?
          client.emit_ooc t('space.resolving_without_orders',
            ships: waiting.map { |s| s.name }.join(', '))
        end

        report = Resolver.resolve_round(combat)
        return client.emit_failure report[:error] if report[:error]

        rendered = Display.render_report(report, sector.geometry)
        client.emit rendered
        Engagements.notify_crews(sector, rendered)
        Engagements.notify_web(sector, :space_round, rendered)
      end
    end
  end
end
