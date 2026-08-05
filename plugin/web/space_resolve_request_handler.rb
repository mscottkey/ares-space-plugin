module AresMUSH
  module Space
    # Resolves a round from the web portal. Staff only, and it calls the
    # very same resolver the in-game command does.
    class SpaceResolveRequestHandler
      def handle(request)
        error = Website.check_login(request)
        return error if error

        enactor = request.enactor
        return { error: t('dispatcher.not_allowed') } if !enactor.is_admin?

        sector = SpaceSector[request.args[:id]]
        return { error: t('space.sector_not_found', name: request.args[:id]) } if !sector

        combat = Engagements.active_combat(sector)
        return { error: t('space.no_active_combat', sector: sector.name) } if !combat

        report = Resolver.resolve_round(combat)
        return { error: report[:error] } if report[:error]

        rendered = Display.render_report(report, sector.geometry)
        Engagements.notify_crews(sector, rendered)
        Engagements.notify_web(sector, :space_round, rendered)

        { message: t('space.round_resolved', round: report[:round]) }
      end
    end
  end
end
