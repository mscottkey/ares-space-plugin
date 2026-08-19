module AresMUSH
  module Space
    # Full detail for one ship. Only your own ship, or anything if staff.
    class SpaceShipRequestHandler
      def handle(request)
        error = Website.check_login(request)
        return error if error

        enactor = request.enactor
        ship = SpaceShip[Space.arg(request, :id)]
        return { error: t('space.ship_not_found', name: Space.arg(request, :id)) } if !ship

        own = Ships.ship_for_char(enactor)
        is_own = own && own.id.to_s == ship.id.to_s
        return { error: t('space.not_your_ship') } if !is_own && !enactor.is_admin?

        WebData.ship_detail(ship)
      end
    end
  end
end
