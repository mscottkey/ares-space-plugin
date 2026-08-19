module AresMUSH
  module Space
    # The tactical plot for one sector, from the viewer's own sensors.
    class SpaceTacticalRequestHandler
      def handle(request)
        error = Website.check_login(request)
        return error if error

        enactor = request.enactor
        sector = SpaceSector[Space.arg(request, :id)]
        return { error: t('space.sector_not_found', name: Space.arg(request, :id)) } if !sector

        is_admin = enactor.is_admin?
        viewer = Ships.ship_for_char(enactor)
        viewer = nil if viewer && viewer.sector_id.to_s != sector.id.to_s

        return { error: t('space.not_your_sector') } if !viewer && !is_admin

        WebData.tactical(sector, viewer, is_admin)
      end
    end
  end
end
