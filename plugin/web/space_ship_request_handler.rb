module AresMUSH
  module Space
    # Full detail for one ship. Any ship you hold a station on, or
    # anything if staff - the same rule WebData.ships_list uses to
    # build the roster this is reached from, so a ship the roster
    # legitimately shows you can't then be refused here.
    class SpaceShipRequestHandler
      def handle(request)
        error = Website.check_login(request)
        return error if error

        enactor = request.enactor
        ship = SpaceShip[Space.arg(request, :id)]
        return { error: t('space.ship_not_found', name: Space.arg(request, :id)) } if !ship

        crews_it = !Ships.station_for_char(ship, enactor).nil?
        return { error: t('space.not_your_ship') } if !crews_it && !enactor.is_admin?

        WebData.ship_detail(ship)
      end
    end
  end
end
