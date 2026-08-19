module AresMUSH
  module Space
    # Sets a course from the browser, through the same path the in-game
    # command uses.
    class SpaceTravelRequestHandler
      def handle(request)
        error = Website.check_login(request)
        return error if error

        ship = Ships.ship_for_char(request.enactor)
        return { error: t('space.not_crewing') } if !ship
        return { error: t('space.ship_destroyed_order') } if !ship.active?

        result = Systems.set_course(ship, Space.arg(request, :destination))
        return { error: result[:error] } if result[:error]

        { message: result[:message] }
      end
    end
  end
end
